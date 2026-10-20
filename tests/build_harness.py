#!/usr/bin/env python3
"""Build build/metal-harness.json for the native Metal 4 runner:
  1. compiles every unit the skill ships (library modules, reference snippets, templates),
  2. runs the numerical property tests from tests/properties.py on the GPU,
  3. renders each template and checks the image (no NaN, not black), optionally saving gallery PNGs.

Run with tests/run_metal.py. Keep the upstream numerical oracles and tolerances.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "skills" / "metal-shader-art" / "scripts"))
sys.path.insert(0, str(ROOT / "tests"))

import metal_tools as gt  # noqa: E402
import properties as props  # noqa: E402

PROP_MAIN = """
void shade(thread float4 &fragColor, float2 fragCoord) {
    uint4 s = pcg4d(uint4(uint2(fragCoord), 7u, 13u));
    uint4 t = pcg4d(s ^ uint4(0x9E3779B9u, 0x85EBCA6Bu, 0xC2B2AE35u, 0x27D4EB2Fu));
    int f = runTest(uintToUnit(s), uintToUnit(t));
    fragColor = float4(float(f), 0.0, 0.0, 1.0);
}
"""


def vec_literal(dim: int, pt: str) -> str:
    return f"float{dim}({pt})"


def exactness(lib: gt.Library, expr: str) -> str:
    """'exact' if every tagged function in expr is exact, 'approx' if any is approx, else 'bound'."""
    tagged = [it for name in lib.idents(expr) for it in lib.by_name[name]
              if it.tags.keys() & {"exact", "bound", "approx"}]
    if any("approx" in it.tags for it in tagged):
        return "approx"
    return "exact" if tagged and all("exact" in it.tags for it in tagged) else "bound"


def sdf_property(lib: gt.Library, name: str, expr: str, dom: float, inside: list[str], outside: list[str],
                 extra: dict | None = None, *, dim: int, brute: tuple | None) -> dict:
    T = f"float{dim}"
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
        axes = ["float3(e, 0.0, 0.0)", "float3(0.0, e, 0.0)", "float3(0.0, 0.0, e)"] if dim == 3 else \
               ["float2(e, 0.0)", "float2(0.0, e)"]
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
    src = "\n".join(code) + "\nint runTest(float4 a, float4 b) {\n    " + "\n    ".join(body) + "\n}\n" + PROP_MAIN
    allow = {"2": props.EXACT_ALLOWANCE} if exact else {}
    allow.update((extra or {}).get("allow", {}))
    return {"name": f"{name} ({kind})", "code": gt.shader_unit(lib, src),
            "allow": allow}


def build(save_gallery: bool = False) -> Path:
    lib = gt.Library()
    units, findings = gt.all_units(lib)
    findings += gt.lint_library(lib) + gt.lint_skill()
    errors = [f for f in findings if f.level == "error"]
    if errors:
        raise SystemExit("\n".join(str(f) for f in errors))
    tests = []
    for spec in props.SDF3:
        tests.append(sdf_property(lib, *spec, dim=3, brute=props.BRUTE.get(spec[0])))
    for spec in props.SDF2:
        tests.append(sdf_property(lib, *spec, dim=2, brute=props.BRUTE.get(spec[0])))
    for name, body, allow in props.PROPERTIES:
        src = f"int runTest(float4 a, float4 b) {{{body}\n}}\n" + PROP_MAIN
        tests.append({"name": name, "code": gt.shader_unit(lib, src),
                      "allow": allow})
    renders = []
    for tpl in sorted(gt.TEMPLATE_DIR.glob("*.metal")):
        src = tpl.read_text(encoding="utf-8")
        m = re.search(r"//\s*@render\s+time=([\d.]+)", src)
        renders.append({"name": tpl.stem, "time": float(m.group(1)) if m else 2.0,
                        "code": gt.shader_unit(lib, src)})
        # Explicit template presets/debug views are compiled AND rendered in CI. Keep them out of the gallery;
        # they are diagnostic variants, not additional public examples.
        for variant_name, variant in gt.template_variants(src):
            name = f"{tpl.stem}--{variant_name}"
            code = gt.shader_unit(lib, variant)
            renders.append({"name": name, "time": float(m.group(1)) if m else 2.0,
                            "code": code, "diagnostic": True})
    data = {"units": units, "tests": tests, "renders": renders, "save": save_gallery,
            "lint": [str(f) for f in findings]}
    out_dir = ROOT / "build"
    out_dir.mkdir(exist_ok=True)
    out = out_dir / "metal-harness.json"
    out.write_text(json.dumps(data), encoding="utf-8")
    return out


if __name__ == "__main__":
    path = build(save_gallery="--save-gallery" in sys.argv)
    print(f"wrote {path.relative_to(ROOT)}")
