#!/usr/bin/env python3
"""Write gallery/<template>.glsl: each template bundled with its library dependencies, ready to paste into Shadertoy.

  python3 tests/build_gallery.py           regenerate
  python3 tests/build_gallery.py --check   fail if any bundle is stale (CI)
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "skills" / "shader-art-coding" / "scripts"))

import glsl_tools as gt  # noqa: E402


def main() -> int:
    check = "--check" in sys.argv
    lib = gt.Library()
    out_dir = ROOT / "gallery"
    out_dir.mkdir(exist_ok=True)
    stale = []
    for tpl in sorted(gt.TEMPLATE_DIR.glob("*.glsl")):
        text = gt.bundle_source(lib, tpl.read_text(encoding="utf-8"))
        target = out_dir / tpl.name
        if check:
            if not target.exists() or target.read_text(encoding="utf-8") != text:
                stale.append(target.name)
        else:
            target.write_text(text, encoding="utf-8")
            print(f"wrote gallery/{tpl.name} ({text.count(chr(10))} lines)")
    if stale:
        print("stale gallery bundles (run tests/build_gallery.py):", ", ".join(stale))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
