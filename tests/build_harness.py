#!/usr/bin/env python3
"""Build build/harness.html: a WebGL2 page that
  1. compiles every unit the skill ships (library modules, reference snippets, templates),
  2. runs the numerical property tests from tests/properties.py on the GPU,
  3. renders each template and checks the image (no NaN, not black), optionally saving gallery PNGs.

Run it in a browser with tests/serve.py (local) or tests/run_webgl.py (headless Chromium, CI).
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "skills" / "shader-art-coding" / "scripts"))
sys.path.insert(0, str(ROOT / "tests"))

import glsl_tools as gt  # noqa: E402
import properties as props  # noqa: E402

PROP_MAIN = """
void main() {
    uvec4 s = pcg4d(uvec4(uvec2(gl_FragCoord.xy), 7u, 13u));
    uvec4 t = pcg4d(s ^ uvec4(0x9E3779B9u, 0x85EBCA6Bu, 0xC2B2AE35u, 0x27D4EB2Fu));
    int f = runTest(uintToUnit(s), uintToUnit(t));
    st_FragColor = vec4(float(f) / 255.0, 0.0, 0.0, 1.0);
}
"""


def vec_literal(dim: int, pt: str) -> str:
    return f"vec{dim}({pt})"


def exactness(lib: gt.Library, expr: str) -> str:
    """'exact' if every tagged function in expr is exact, 'approx' if any is approx, else 'bound'."""
    tagged = [it for name in lib.idents(expr) for it in lib.by_name[name]
              if it.tags.keys() & {"exact", "bound", "approx"}]
    if any("approx" in it.tags for it in tagged):
        return "approx"
    return "exact" if tagged and all("exact" in it.tags for it in tagged) else "bound"


def sdf_property(lib: gt.Library, name: str, expr: str, dom: float, inside: list[str], outside: list[str],
                 extra: dict | None = None, *, dim: int, brute: tuple | None) -> dict:
    T = f"vec{dim}"
    sw = ".xyz" if dim == 3 else ".xy"
    kind = exactness(lib, expr)
    if "domTwist" in expr or "domBend" in expr:
        kind = "bound"
    exact = kind == "exact"
    # approx fields only promise a bound outside the shape
    lip_guard = "dp > 0.0 && dq > 0.0 && " if kind == "approx" else ""
    code = [f"float F({T} p) {{ return {expr}; }}"]
    if brute:
        code.append(f"{T} curvePoint(float t) {{ return {brute[1]}; }}")
    body = [
        f"{T} p = (a{sw} * 2.0 - 1.0) * {dom:.4f};",
        f"{T} dir = normalize(b{sw} * 2.0 - 1.0 + 1e-4);",
        f"float len = {dom:.4f} * exp2(-12.0 * b.w);",
        f"{T} q = p + dir * len;",
        "float dp = F(p), dq = F(q);",
        "int f = 0;",
        "if (isnan(dp) || isinf(dp)) f |= 1;",
        f"if ({lip_guard}abs(dp - dq) > length(q - p) * 1.0005 + 1e-5) f |= 1;",
    ]
    if exact:
        axes = ["vec3(e, 0.0, 0.0)", "vec3(0.0, e, 0.0)", "vec3(0.0, 0.0, e)"] if dim == 3 else \
               ["vec2(e, 0.0)", "vec2(0.0, e)"]
        grad = ", ".join(f"F(p + {a}) - F(p - {a})" for a in axes)
        body += [
            "float e = 1e-3;",
            f"{T} g = {T}({grad}) / (2.0 * e);",
            "float gl = length(g);",
            "if (gl > 1e-3) {",
            f"    {T} s = p - dp * g / gl;",
            "    if (abs(F(s)) > 0.02 * abs(dp) + 2e-3) f |= 2;",
            "}",
        ]
    for pt in inside:
        body.append(f"if (!(F({vec_literal(dim, pt)}) < 0.0)) f |= 4;")
    for pt in outside:
        body.append(f"if (!(F({vec_literal(dim, pt)}) > 0.0)) f |= 4;")
    if brute:
        body += [
            "float bd = 1e9;",
            "for (int i = 0; i <= 1024; i++) bd = min(bd, length(p - curvePoint(float(i) / 1024.0)));",
            f"if (abs(dp + {brute[2]:.4f} - bd) > 0.004) f |= 8;",
        ]
    body.append("return f;")
    src = "\n".join(code) + "\nint runTest(vec4 a, vec4 b) {\n    " + "\n    ".join(body) + "\n}\n" + PROP_MAIN
    allow = {"2": props.EXACT_ALLOWANCE} if exact else {}
    allow.update((extra or {}).get("allow", {}))
    return {"name": f"{name} ({kind})", "code": gt.SHADERTOY_PRELUDE + gt.bundle_source(lib, src, keep_docs=False),
            "allow": allow}


def build(save_gallery: bool = False) -> Path:
    lib = gt.Library()
    units, findings = gt.all_units(lib)
    tests = []
    for spec in props.SDF3:
        tests.append(sdf_property(lib, *spec, dim=3, brute=props.BRUTE.get(spec[0])))
    for spec in props.SDF2:
        tests.append(sdf_property(lib, *spec, dim=2, brute=props.BRUTE.get(spec[0])))
    for name, body, allow in props.PROPERTIES:
        src = f"int runTest(vec4 a, vec4 b) {{{body}\n}}\n" + PROP_MAIN
        tests.append({"name": name, "code": gt.SHADERTOY_PRELUDE + gt.bundle_source(lib, src, keep_docs=False),
                      "allow": allow})
    renders = []
    for tpl in sorted(gt.TEMPLATE_DIR.glob("*.glsl")):
        src = tpl.read_text(encoding="utf-8")
        m = re.search(r"//\s*@render\s+time=([\d.]+)", src)
        renders.append({"name": tpl.stem, "time": float(m.group(1)) if m else 2.0,
                        "code": gt.SHADERTOY_PRELUDE + gt.bundle_source(lib, src, keep_docs=False) + gt.MAIN_COMPLETE})
        # Explicit template presets/debug views are compiled AND rendered in CI. Keep them out of the gallery;
        # they are diagnostic variants, not additional public examples.
        for variant_name, variant in gt.template_variants(src):
            name = f"{tpl.stem}--{variant_name}"
            code = gt.SHADERTOY_PRELUDE + gt.bundle_source(lib, variant, keep_docs=False) + gt.MAIN_COMPLETE
            renders.append({"name": name, "time": float(m.group(1)) if m else 2.0,
                            "code": code, "diagnostic": True})
    data = {"units": units, "tests": tests, "renders": renders, "save": save_gallery,
            "lint": [str(f) for f in findings]}
    out_dir = ROOT / "build"
    out_dir.mkdir(exist_ok=True)
    html = (ROOT / "tests" / "harness_template.html").read_text(encoding="utf-8")
    out = out_dir / "harness.html"
    out.write_text(html.replace("/*__DATA__*/null", json.dumps(data)), encoding="utf-8")
    return out


if __name__ == "__main__":
    path = build(save_gallery="--save-gallery" in sys.argv)
    print(f"wrote {path.relative_to(ROOT)}")
