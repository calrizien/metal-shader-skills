#!/usr/bin/env python3
"""Tools for the metal-shader-art MSL 4.1 library. Standard library only.

Commands (run from anywhere):
  search TERM...        find library functions by name, summary or @use tags ("petal", "noise terrain")
  bundle SHADER [-o F]  inline exactly the library functions SHADER uses -> standalone Metal vertex and fragment code
  check [SHADER...]     lint and require MSL 4.1 compilation (--lint-only opts out); no args = check the skill
  render SHADER        render through the native Metal 4 API and save a PNG plus receipt
  index [--check]       regenerate references/library-index.md (or fail if it is stale)

Shaders are written against the library by name: call sdRoundBox, fbm, softShadow, ... without pasting them.
`bundle` resolves dependencies transitively and emits them in declaration order before your code.
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parents[1]
LIB_DIR = SKILL_DIR / "metal"
REF_DIR = SKILL_DIR / "references"
TEMPLATE_DIR = SKILL_DIR / "templates"
INDEX_PATH = REF_DIR / "library-index.md"

# Declaration order: a module may only depend on modules listed before it.
MODULE_ORDER = [
    "common", "hash", "noise", "pattern", "sdf3d", "sdf2d", "operators", "domain", "architecture", "raymarch", "intersect",
    "camera", "shading", "water", "color", "tonemap", "volume", "atmosphere", "post", "debug",
]

METAL_PRELUDE = "/*\n" + (SKILL_DIR / "LICENSE").read_text(encoding="utf-8") + "*/\n" + """// metal-shader-skills: MSL 4.1, MIT.
// Derived from https://github.com/gokayfem/shader-skills
// Metal fork: https://github.com/calrizien/metal-shader-skills
#include <metal_stdlib>
using namespace metal;

// Shared ABI: 16 bytes, alignment 8. Swift: SIMD2<Float>, Float, UInt32.
struct ShaderUniforms {
    float2 resolution;
    float time;
    uint frame;
};
vertex float4 fullscreenVertex(uint id [[vertex_id]]) {
    const float2 positions[3] = {float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0)};
    return float4(positions[id], 0.0, 1.0);
}
"""
METAL_ENTRY = """
fragment float4 shaderFragment(float4 position [[position]],
                               constant ShaderUniforms &uniforms [[buffer(0)]]) {
    ShaderScene scene{uniforms.resolution, uniforms.time, int(uniforms.frame)};
    float4 color = float4(0.0);
    // Metal's viewport origin is top-left. Scene math uses a bottom-left origin.
    scene.shade(color, float2(position.x, uniforms.resolution.y - position.y));
    return color;
}
"""

def metal_unit(body: str, complete: bool = True) -> str:
    """Wrap scene members in a thread-local object; entry functions remain native MSL."""
    # C++ member functions can refer to later members. A separate declaration and
    # definition inside the same class would instead be an invalid redeclaration.
    body = "\n".join(it.text for it in parse(body) if it.kind != "proto")
    if not complete:
        body += "\nvoid shade(thread float4 &color, float2 pixel) { color = float4(0.0); }\n"
    return (METAL_PRELUDE + "\nstruct ShaderScene {\n"
            "    float2 resolution;\n    float time;\n    int frame;\n" + body +
            "\n};\n" + METAL_ENTRY)


def stub_prototypes(code: str) -> str:
    """Give scene-provided prototypes (e.g. `float terrainHeight(vec2 p);`, `vec2 map(vec3 p);`) a trivial body so a
    snippet or library module can be compiled on its own."""
    items = parse(code)
    defined = {it.key for it in items if it.kind == "fn"}
    stubs = []
    for it in items:
        if it.kind == "proto" and it.key not in defined:
            ret = it.signature.split()[0]
            value = "0.0" if ret == "float" else ("0" if ret == "int" else f"{ret}(0.0)")
            if it.name == "map" and ret == "float2":
                value = "float2(length(p) - 1.0, 0.0)"
            params = it.signature[it.signature.index("(") + 1:-1]
            stubs.append(f"{ret} {it.name}({params}) {{ return {value}; }}")
            defined.add(it.key)
    return code + ("\n// stubs for scene-provided functions\n" + "\n".join(stubs) + "\n" if stubs else "")

QUALIFIERS = {"thread", "&","in", "out", "inout", "const", "highp", "mediump", "lowp", "flat", "smooth"}
METAL_KEYWORDS = {
    "float", "int", "uint", "bool", "void", "float2", "float3", "float4", "int2", "int3", "int4", "uint2",
    "uint3", "uint4", "bool2", "bool3", "bool4", "float2x2", "float3x3", "float4x4", "if", "else", "for", "while",
    "return", "break", "continue", "struct", "const", "in", "out", "inout", "true", "false",
}
FN_RE = re.compile(r"^\s*((?:(?:highp|mediump|lowp)\s+)?\w+)\s+(\w+)\s*\(([^)]*)\)\s*(\{|;)", re.S)
STRUCT_RE = re.compile(r"^\s*struct\s+(\w+)")
CONST_RE = re.compile(r"^\s*const\s+(?:(?:highp|mediump|lowp)\s+)?\w+\s+(\w+)\s*=")
DEFINE_RE = re.compile(r"^#\s*define\s+(\w+)")
IDENT_RE = re.compile(r"\b[A-Za-z_]\w*\b")


@dataclass
class Item:
    kind: str            # fn | proto | struct | const | define | directive | other
    name: str
    text: str            # source text without doc comments
    doc: list[str] = field(default_factory=list)
    signature: str = ""  # e.g. "float sdBox(vec3 p, vec3 b)"
    key: str = ""        # name + parameter types, for overload identity
    module: str = ""
    deps: set[str] = field(default_factory=set)

    @property
    def tags(self) -> dict[str, str]:
        out: dict[str, str] = {}
        for line in self.doc:
            if line.startswith("@"):
                tag, _, rest = line[1:].partition(" ")
                out[tag] = rest.strip()
        return out

    @property
    def summary(self) -> str:
        return " ".join(l for l in self.doc if not l.startswith("@")).strip()


def strip_comments(code: str) -> str:
    code = re.sub(r"/\*.*?\*/", " ", code, flags=re.S)
    return re.sub(r"//[^\n]*", "", code)


def normalize(code: str) -> str:
    return re.sub(r"\s+", "", strip_comments(code))


def param_types(params: str) -> list[str]:
    types = []
    for raw in params.split(","):
        toks = [t for t in re.split(r"\s+", raw.replace("&", " & ").strip()) if t and t not in QUALIFIERS]
        if not toks or toks == ["void"]:
            continue
        types.append(toks[0] if len(toks) == 1 else toks[-2])
    return types


def parse(src: str, module: str = "") -> list[Item]:
    """Split MSL scene source into top-level items, attaching /// doc lines to the item that follows."""
    items: list[Item] = []
    doc: list[str] = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c.isspace():
            i += 1
            continue
        if src.startswith("///", i) or src.startswith("//!", i) or src.startswith("//", i):
            end = src.find("\n", i)
            end = n if end < 0 else end
            if src.startswith("///", i):
                doc.append(src[i + 3:end].strip())
            i = end
            continue
        if src.startswith("/*", i):
            end = src.find("*/", i)
            i = n if end < 0 else end + 2
            continue
        if c == "#":
            end = i
            while True:
                nl = src.find("\n", end)
                nl = n if nl < 0 else nl
                if src[nl - 1:nl] == "\\":
                    end = nl + 1
                    continue
                end = nl
                break
            text = src[i:end]
            m = DEFINE_RE.match(text)
            items.append(Item("define" if m else "directive", m.group(1) if m else "", text, doc, module=module))
            doc = []
            i = end
            continue
        # statement or block
        start, depth, j = i, 0, i
        while j < n:
            ch = src[j]
            if src.startswith("//", j):
                nl = src.find("\n", j)
                j = n if nl < 0 else nl
                continue
            if src.startswith("/*", j):
                e = src.find("*/", j)
                j = n if e < 0 else e + 2
                continue
            if ch in "({[":
                depth += 1
            elif ch in ")}]":
                depth -= 1
                if ch == "}" and depth == 0:
                    # end of a function body or struct
                    k = j + 1
                    while k < n and src[k] in " \t":
                        k += 1
                    if k < n and src[k] == ";":
                        j = k
                    break
            elif ch == ";" and depth == 0:
                break
            j += 1
        text = src[start:j + 1]
        i = j + 1
        m_fn, m_st, m_co = FN_RE.match(text), STRUCT_RE.match(text), CONST_RE.match(text)
        if m_st:
            item = Item("struct", m_st.group(1), text, doc, module=module, key=m_st.group(1))
        elif m_co:
            item = Item("const", m_co.group(1), text, doc, module=module, key=m_co.group(1))
        elif m_fn and m_fn.group(1) not in ("return", "else"):
            ret, name, params = m_fn.group(1), m_fn.group(2), m_fn.group(3)
            sig = f"{ret} {name}({' '.join(params.split())})"
            kind = "fn" if m_fn.group(4) == "{" else "proto"
            item = Item(kind, name, text, doc, signature=sig, key=f"{name}({','.join(param_types(params))})",
                        module=module)
        else:
            item = Item("other", "", text, doc, module=module)
        items.append(item)
        doc = []
    return items


class Library:
    def __init__(self, lib_dir: Path = LIB_DIR):
        self.items: list[Item] = []
        self.modules: dict[str, str] = {}
        files = {p.stem: p for p in lib_dir.glob("*.metal")}
        unknown = sorted(set(files) - set(MODULE_ORDER))
        if unknown:
            raise SystemExit(f"metal/: modules missing from MODULE_ORDER: {unknown}")
        for mod in MODULE_ORDER:
            if mod not in files:
                continue
            src = files[mod].read_text(encoding="utf-8")
            header = [l[3:].strip() for l in src.splitlines() if l.startswith("//!")]
            self.modules[mod] = " ".join(header)
            self.items.extend(parse(src, mod))
        self.by_name: dict[str, list[Item]] = {}
        for it in self.items:
            if it.name:
                self.by_name.setdefault(it.name, []).append(it)
        for it in self.items:
            it.deps = self.idents(it.text) - {it.name}
            if it.kind == "proto":
                it.deps = set()

    def idents(self, code: str) -> set[str]:
        return {t for t in IDENT_RE.findall(strip_comments(code)) if t in self.by_name and t not in METAL_KEYWORDS}

    def closure(self, names: set[str], exclude: set[str] = frozenset()) -> list[Item]:
        seen: set[str] = set()
        stack = [n for n in names if n not in exclude]
        while stack:
            name = stack.pop()
            if name in seen:
                continue
            seen.add(name)
            for it in self.by_name.get(name, []):
                stack.extend(d for d in it.deps if d not in seen and d not in exclude)
        return [it for it in self.items if it.name in seen]

    def bundle(self, user_src: str, keep_docs: bool = True) -> tuple[str, list[Item]]:
        user_items = parse(user_src)
        defined = {it.name for it in user_items if it.kind in ("fn", "struct", "const", "define")}
        needed = self.idents(user_src) - defined
        deps = self.closure(needed, exclude=defined - {"map"})
        # The map() prototype is only needed when raymarch helpers are pulled in.
        if not any("map" in it.deps for it in deps):
            deps = [it for it in deps if not (it.kind == "proto" and it.name == "map")]
        chunks, current = [], None
        for it in deps:
            if it.module != current:
                current = it.module
                chunks.append(f"\n// ---- metal-shader-skills library: {current} ----")
            body = it.text.strip()
            if keep_docs and it.doc and it.kind == "fn":
                summary = it.summary
                if summary:
                    body = f"// {summary}\n{body}"
            chunks.append(body)
        lib_code = "\n".join(chunks).strip()
        return lib_code, deps


def bundle_source(lib: Library, user_src: str, keep_docs: bool = True) -> str:
    lib_code, deps = lib.bundle(user_src, keep_docs)
    if not deps:
        return user_src
    header = ("// Library code below is bundled from metal-shader-skills (MIT; derived from gokayfem/shader-skills): "
              "https://github.com/calrizien/metal-shader-skills\n")
    # Keep user #defines (e.g. DEBUG_MODE, AA) at the very top so library code can see them.
    lines = user_src.splitlines()
    lead = 0
    while lead < len(lines) and (lines[lead].lstrip().startswith(("#", "//")) or not lines[lead].strip()):
        lead += 1
    # Never insert dependencies inside a conditional whose body starts with a declaration.
    # A quality-preset #if followed by a const used to hide the entire library on its false branch.
    directives = []
    depth = 0
    for i in range(lead):
        match = re.match(r"\s*#\s*(\w+)", lines[i])
        if not match:
            continue
        word = match.group(1)
        if word in ("if", "ifdef", "ifndef"):
            depth += 1
        elif word == "endif":
            depth -= 1
        if depth == 0:
            directives.append(i)
    cut = directives[-1] + 1 if directives else 0
    while cut < lead and lines[cut].strip() == "":
        cut += 1
    if not directives:
        # no #defines: keep only the opening comment block (up to the first blank line) on top
        cut = next((i for i in range(lead) if not lines[i].strip()), 0)
    top, rest = lines[:cut], lines[cut:]
    return ("\n".join(top).rstrip() + "\n\n" + header + lib_code + "\n\n// ---- shader ----\n"
            + "\n".join(rest).strip() + "\n")


# ------------------------------------------------------------------------------------------------ lint

@dataclass
class Finding:
    level: str  # error | warning
    where: str
    message: str

    def __str__(self) -> str:
        return f"{self.level.upper():7} {self.where}: {self.message}"


SHADER_RULES = [
    (r"\b(?:vec[234]|[uib]vec[234]|mat[234]|gl_FragColor|gl_FragCoord|mainImage)\b",
     "error", "GLSL syntax remains; use native MSL types and shade(thread float4 &, float2)"),
    (r"\b(?:uniform|varying|precision|inout)\b", "error", "GLSL qualifier remains; use the MSL address-space contract"),
    (r"^\s*#version\b", "error", "use the compiler flag -std=metal4.1"),
    (r"\btexture2D\s*\(", "error", "MSL samples a texture2d with .sample(sampler, uv)"),
    (r"\bfract\s*\(\s*[-+]?\s*(?:[\d.]+(?:[eE][-+]?\d+)?\s*\*\s*)?sin\s*\(|43758\.5453",
     "error", "use the integer PCG hash helpers in metal/hash.metal"),
]

def lint_shader(src: str, where: str, complete: bool) -> list[Finding]:
    out = []
    code = strip_comments(src)
    for pattern, level, message in SHADER_RULES:
        if re.search(pattern, code, re.M):
            out.append(Finding(level, where, message))
    if complete and not re.search(r"\b(?:void\s+shade|fragment\s+float4\s+shaderFragment)\s*\(", code):
        out.append(Finding("error", where, "missing shade(thread float4 &color, float2 pixel) or shaderFragment entry"))
    return out


def lint_library(lib: Library) -> list[Finding]:
    out: list[Finding] = []
    seen: dict[str, Item] = {}
    for it in lib.items:
        where = f"metal/{it.module}.metal:{it.name or it.kind}"
        if it.kind == "fn":
            if it.key in seen:
                out.append(Finding("error", where, f"duplicate definition of {it.key}"))
            seen[it.key] = it
            documented = it.doc or any(o.doc for o in lib.by_name[it.name])
            if not documented:
                out.append(Finding("error", where, "missing /// doc comment"))
            tags = {k: v for o in lib.by_name[it.name] for k, v in o.tags.items()}
            if it.doc and "use" not in tags and not it.name.startswith(("uintToUnit", "quintic", "latticeG")):
                out.append(Finding("warning", where, "doc comment has no @use line"))
            if re.match(r"sd[A-Z]", it.name) and not ({"exact", "bound", "approx"} & set(tags)):
                out.append(Finding("error", where, "SDF needs an @exact, @bound or @approx tag"))
        for pattern, level, msg in SHADER_RULES:
            if re.search(pattern, strip_comments(it.text), re.M):
                out.append(Finding(level, where, msg))
        bad_deps = [d for d in it.deps if any(MODULE_ORDER.index(o.module) > MODULE_ORDER.index(it.module)
                                              for o in lib.by_name[d])]
        if bad_deps:
            out.append(Finding("error", where, f"depends on later module(s): {sorted(bad_deps)}"))
    return out


def lint_skill() -> list[Finding]:
    """Packaging rules from the Agent Skills spec: frontmatter, size, one-level references with tables of contents."""
    out: list[Finding] = []
    text = (SKILL_DIR / "SKILL.md").read_text(encoding="utf-8")
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
    if not m:
        return [Finding("error", "SKILL.md", "missing YAML frontmatter")]
    front, body = m.group(1), m.group(2)
    name = re.search(r"^name:\s*(\S+)", front, re.M)
    if not name or name.group(1) != SKILL_DIR.name:
        out.append(Finding("error", "SKILL.md", f"frontmatter name must equal the folder name '{SKILL_DIR.name}'"))
    desc = re.search(r"^description:\s*(?:>-?|\|-?)?\s*\n((?:[ \t]+.*\n?)+)|^description:\s*(.+)$", front, re.M)
    desc_text = " ".join((desc.group(1) or desc.group(2) or "").split()) if desc else ""
    if not desc_text:
        out.append(Finding("error", "SKILL.md", "missing description"))
    elif len(desc_text) > 1024:
        out.append(Finding("error", "SKILL.md", f"description is {len(desc_text)} chars (max 1024)"))
    if re.search(r"\[[^\]\n]*,[^\]\n]*\]", front):
        out.append(Finding("error", "SKILL.md", "use block-style YAML lists in frontmatter (strict validators reject [a, b])"))
    if body.count("\n") > 500:
        out.append(Finding("error", "SKILL.md", "body exceeds 500 lines; move detail into references/"))
    for ref in sorted(REF_DIR.glob("*.md")):
        rel = f"references/{ref.name}"
        if rel not in body:
            out.append(Finding("error", "SKILL.md", f"{rel} is not linked from SKILL.md"))
        ref_text = ref.read_text(encoding="utf-8")
        if ref_text.count("\n") > 100 and "## Contents" not in ref_text:
            out.append(Finding("error", rel, "over 100 lines without a '## Contents' section"))
    for rel in sorted(set(re.findall(r"`((?:references|templates|scripts|metal)/[\w./-]+)`", body))):
        if not (SKILL_DIR / rel).exists():
            out.append(Finding("error", "SKILL.md", f"links missing file {rel}"))
    return out


# --------------------------------------------------------------------------------------------- snippets

FENCE_RE = re.compile(r"```metal[^\n]*\n(.*?)\n```", re.S)


@dataclass
class Snippet:
    where: str
    code: str
    kind: str  # complete | defs | fragment


def reference_snippets(paths: list[Path]) -> list[Snippet]:
    out = []
    for path in paths:
        text = path.read_text(encoding="utf-8")
        for idx, m in enumerate(FENCE_RE.finditer(text), 1):
            code = m.group(1)
            line = text.count("\n", 0, m.start()) + 2
            where = f"{path.relative_to(SKILL_DIR.parent.parent) if SKILL_DIR.parent.parent in path.parents else path.name}:{line}"
            items = parse(code)
            if re.search(r"\bvoid\s+shade\b", code):
                kind = "complete"
            elif items and all(it.kind in ("fn", "struct", "const", "define", "proto") for it in items):
                kind = "defs"
            else:
                kind = "fragment"
            out.append(Snippet(where, code, kind))
    return out


def snippet_drift(lib: Library, snip: Snippet) -> list[Finding]:
    """A reference snippet may reuse a library name only if it is the library code verbatim (modulo whitespace)."""
    out = []
    lib_by_key = {it.key: it for it in lib.items if it.kind == "fn"}
    for it in parse(snip.code):
        if it.kind != "fn":
            continue
        if it.key in lib_by_key and normalize(it.text) != normalize(lib_by_key[it.key].text):
            out.append(Finding("error", snip.where,
                               f"{it.key} differs from metal/{lib_by_key[it.key].module}.metal; "
                               "use the library version or rename the variant"))
    return out


def snippet_unit(lib: Library, snip: Snippet, extra_defs: str = "") -> str:
    """Compile unit for a reference snippet: library deps + definitions from earlier snippets + the snippet."""
    body = extra_defs + "\n" + snip.code
    code = stub_prototypes(bundle_source(lib, body, keep_docs=False))
    return metal_unit(code, complete=snip.kind == "complete")


def shader_unit(lib: Library, src: str, complete: bool = True) -> str:
    if "#include <metal_stdlib>" in src and "fragment float4 shaderFragment" in src:
        return src
    code = bundle_source(lib, src, keep_docs=False)
    if not complete:
        code = stub_prototypes(code)
    return metal_unit(code, complete=complete)


def library_units(lib: Library) -> dict[str, str]:
    """One compile unit per module: every function in it plus its dependencies."""
    units = {}
    for mod in lib.modules:
        names = {it.name for it in lib.items if it.module == mod and it.name}
        deps = lib.closure(names)
        code = stub_prototypes("\n\n".join(it.text.strip() for it in deps))
        units[f"metal/{mod}.metal"] = metal_unit(code, complete=False)
    return units


def template_variants(src: str) -> list[tuple[str, str]]:
    """Materialize explicitly annotated quality/debug presets; reject an annotation with no matching define."""
    variants = []
    for key, value in re.findall(r"//\s*@variant\s+(\w+)=(\d+)", src):
        variant, count = re.subn(rf"(^\s*#define\s+{re.escape(key)}\s+)\d+", rf"\g<1>{value}", src, flags=re.M)
        if count != 1:
            raise ValueError(f"@variant {key}={value} needs exactly one matching #define")
        variants.append((f"{key.lower()}-{value}", variant))
    return variants


def all_units(lib: Library) -> tuple[dict[str, str], list[Finding]]:
    """Every compile unit the skill ships: library modules, reference snippets, templates."""
    findings: list[Finding] = []
    units = library_units(lib)
    refs = sorted(REF_DIR.glob("*.md")) + [SKILL_DIR / "SKILL.md"]
    by_file: dict[str, str] = {}
    for snip in reference_snippets(refs):
        findings += snippet_drift(lib, snip)
        file_key = snip.where.split(":")[0]
        if snip.kind == "fragment":
            continue
        findings += lint_shader(snip.code, snip.where, complete=snip.kind == "complete")
        # Snippets may build on definitions from earlier snippets in the same file (minus anything they redefine).
        prior = by_file.get(file_key, "")
        own = {it.key or it.name for it in parse(snip.code)}
        prior_kept = "\n".join(it.text for it in parse(prior) if (it.key or it.name) not in own)
        units[snip.where] = snippet_unit(lib, snip, prior_kept)
        if snip.kind == "defs":
            by_file[file_key] = prior + "\n" + snip.code
    for tpl in sorted(TEMPLATE_DIR.glob("*.metal")):
        src = tpl.read_text(encoding="utf-8")
        where = f"templates/{tpl.name}"
        findings += lint_shader(src, where, complete=True)
        units[where] = shader_unit(lib, src)
        for name, variant in template_variants(src):
            units[f"templates/{tpl.stem}--{name}"] = shader_unit(lib, variant)
    return units, findings


# ------------------------------------------------------------------------------------------- Metal compiler

def metal_compile(units: dict[str, str]) -> list[Finding]:
    """Compile with the requested baseline. Missing tools are a failed check."""
    if not shutil.which("xcrun"):
        return [Finding("error", "compiler", "xcrun is missing; use --lint-only for a static check")]
    out = []
    diagnostic_root = Path.cwd() / "build" / "metal-compile"
    diagnostic_root.mkdir(parents=True, exist_ok=True)
    diagnostics = Path(tempfile.mkdtemp(prefix="run-", dir=diagnostic_root))
    for i, (where, code) in enumerate(units.items()):
        path = diagnostics / f"unit-{i:03d}.metal"
        path.write_text(code, encoding="utf-8")
        command = ["xcrun", "-sdk", "macosx", "metal", "-std=metal4.1",
                   "-fno-fast-math", "-c", str(path), "-o", str(path.with_suffix(".air"))]
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=120)
            log = result.stdout + result.stderr
            path.with_suffix(".log").write_text(where + "\n" + log, encoding="utf-8")
            if result.returncode:
                out.append(Finding("error", where, f"MSL compile failed; {path.with_suffix('.log')}\n{log}"))
        except subprocess.TimeoutExpired:
            path.with_suffix(".log").write_text(where + "\nCompiler timeout after 120 seconds")
            out.append(Finding("error", where, "MSL compiler timeout after 120 seconds"))
    return out


# --------------------------------------------------------------------------------------------- index

def render_index(lib: Library) -> str:
    lines = [
        "# Metal Shading Language Library Index",
        "",
        "Generated by `scripts/metal_tools.py index`. Do not edit by hand.",
        "",
        "Call these functions by name in your shader, then run",
        "`python3 scripts/metal_tools.py bundle your.metal -o out.metal` to inline exactly what it uses.",
        "Find candidates with `python3 scripts/metal_tools.py search <words>`.",
        "",
        "Tags: **exact** is a true Euclidean distance, safe for blending, AO, shadows and offsets.",
        "**bound** never overestimates, so it is safe to march, but less accurate for offsets.",
        "**approx** has an exact surface but may overestimate in places; read its note for a safe step scale.",
        "",
        "## Contents",
        "",
    ]
    for mod in lib.modules:
        lines.append(f"- [{mod}](#{mod}) - {lib.modules[mod].split('. ')[0].split(': ', 1)[-1]}")
    for mod, header in lib.modules.items():
        lines += ["", f"## {mod}", "", header, ""]
        shown: set[str] = set()
        for it in lib.items:
            if it.module != mod or it.kind not in ("fn", "const", "define") or it.name in shown:
                continue
            group = [o for o in lib.by_name[it.name] if o.module == mod and o.kind in ("fn", "const", "define")]
            shown.add(it.name)
            doc_item = next((o for o in group if o.doc), it)
            tags = doc_item.tags
            sigs = " / ".join(f"`{o.signature}`" if o.signature else f"`{o.text.strip()[:60]}`" for o in group)
            exact = next((f" **{t}**" for t in ("exact", "bound", "approx") if t in tags), "")
            summary = doc_item.summary
            line = f"- {sigs}{exact}"
            if summary:
                line += f" - {summary}"
            if tags.get("use"):
                line += f" *Use: {tags['use']}.*"
            if tags.get("range"):
                line += f" Range {tags['range']}."
            lines.append(line)
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------------------------- main

def cmd_search(lib: Library, terms: list[str]) -> int:
    terms = [t.lower() for t in terms]
    scored = []
    for name, group in lib.by_name.items():
        fns = [g for g in group if g.kind == "fn"]
        if not fns:
            continue
        doc_item = next((g for g in fns if g.doc), fns[0])
        use = doc_item.tags.get("use", "").lower()
        summary = doc_item.summary.lower()
        score = sum((3 if t in name.lower() else 0) + 2 * use.count(t) + summary.count(t) for t in terms)
        if score:
            scored.append((score, name, fns, doc_item))
    for score, name, fns, doc_item in sorted(scored, key=lambda s: -s[0])[:15]:
        print(f"{fns[0].module}: " + " / ".join(f.signature for f in fns))
        if doc_item.summary:
            print(f"    {doc_item.summary}")
        if doc_item.tags.get("use"):
            print(f"    use: {doc_item.tags['use']}")
    if not scored:
        print("no matches; try broader words or read references/library-index.md")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("search")
    s.add_argument("terms", nargs="+")
    b = sub.add_parser("bundle")
    b.add_argument("shader")
    b.add_argument("-o", "--output")
    c = sub.add_parser("check")
    c.add_argument("shaders", nargs="*")
    c.add_argument("--lint-only", action="store_true", help="static checks only; does not prove MSL compilation")
    c.add_argument("--defs", action="store_true", help="files contain helper definitions, not a full shade function")
    r = sub.add_parser("render")
    r.add_argument("shader")
    r.add_argument("--output", default="build/metal-render")
    r.add_argument("--size", default="640x360")
    r.add_argument("--time", type=float, default=2.0)
    r.add_argument("--frame", type=int, default=0)
    i = sub.add_parser("index")
    i.add_argument("--check", action="store_true")
    args = ap.parse_args(argv)

    lib = Library()
    if args.cmd == "render":
        from render_metal import render
        return render(Path(args.shader), Path(args.output), args.size, args.time, args.frame)
    if args.cmd == "search":
        return cmd_search(lib, args.terms)
    if args.cmd == "bundle":
        out = shader_unit(lib, Path(args.shader).read_text(encoding="utf-8"))
        if args.output:
            Path(args.output).write_text(out, encoding="utf-8")
        else:
            sys.stdout.write(out)
        return 0
    if args.cmd == "index":
        text = render_index(lib)
        if args.check:
            if not INDEX_PATH.exists() or INDEX_PATH.read_text(encoding="utf-8") != text:
                print("references/library-index.md is stale: run scripts/metal_tools.py index")
                return 1
            print("library index is up to date")
            return 0
        INDEX_PATH.write_text(text, encoding="utf-8")
        print(f"wrote {INDEX_PATH.relative_to(SKILL_DIR)}")
        return 0

    # check
    findings: list[Finding] = []
    if args.shaders:
        units = {}
        for path in args.shaders:
            src = Path(path).read_text(encoding="utf-8")
            findings += lint_shader(src, path, complete=not args.defs)
            units[path] = shader_unit(lib, src, complete=not args.defs)
    else:
        findings += lint_library(lib)
        findings += lint_skill()
        units, more = all_units(lib)
        findings += more
        if INDEX_PATH.exists() and INDEX_PATH.read_text(encoding="utf-8") != render_index(lib):
            findings.append(Finding("error", "references/library-index.md", "stale; run scripts/metal_tools.py index"))
    if args.lint_only:
        print(f"lint only: {len(units)} unit(s); compilation was not run")
    else:
        findings += metal_compile(units)
        print(f"checked {len(units)} unit(s) with the MSL 4.1 compiler; full logs in build/metal-compile")
    errors = [f for f in findings if f.level == "error"]
    for f in findings:
        print(f)
    print(f"{len(errors)} error(s), {len(findings) - len(errors)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
