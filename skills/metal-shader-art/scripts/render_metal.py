"""Render a scene or standalone bundle on an Apple silicon Metal 4 GPU."""
from __future__ import annotations

import hashlib
import json
import math
import os
from pathlib import Path
import platform
import subprocess
import sys


def render(source: Path, output: Path, size: str, time_value: float, frame: int) -> int:
    from metal_tools import Library, lint_shader, shader_unit

    if platform.system() != "Darwin" or platform.machine() != "arm64" or int(platform.mac_ver()[0].split(".")[0]) < 27:
        print("render requires an Apple silicon Mac, macOS 27+, Xcode 27+, and a Metal 4 GPU", file=sys.stderr)
        return 1
    try:
        width, height = map(int, size.split("x"))
        if not (1 <= width <= 4096 and 1 <= height <= 4096
                and math.isfinite(time_value) and 0 <= frame <= 2147483647):
            raise ValueError
    except ValueError:
        print("use WIDTHxHEIGHT (1..4096), finite time, and frame 0..2147483647", file=sys.stderr)
        return 1
    text = source.read_text(encoding="utf-8")
    findings = lint_shader(text, str(source), complete=True)
    for finding in findings:
        print(finding)
    if any(f.level == "error" for f in findings):
        return 1
    code = shader_unit(Library(), text)
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    manifest = output / "manifest.json"
    manifest.write_text(json.dumps({"units": {}, "tests": [], "renders": [
        {"name": "preview", "time": time_value, "frame": frame, "code": code}
    ]}), encoding="utf-8")
    native_source = Path(__file__).with_name("metal_runner.mm")
    runner = output / "metal-runner"
    command = ["xcrun", "clang++", "-std=c++17", "-fobjc-arc", "-O2", "-arch", "arm64",
               "-mmacosx-version-min=27.0", "-framework", "Foundation", "-framework", "Metal",
               "-framework", "CoreGraphics", "-framework", "ImageIO", str(native_source), "-o", str(runner)]
    compiled = subprocess.run(command, capture_output=True, text=True, timeout=120)
    (output / "host-compile.log").write_text(compiled.stdout + compiled.stderr)
    if compiled.returncode:
        print(compiled.stdout + compiled.stderr, file=sys.stderr)
        return 1
    with (output / "run.log").open("w") as log:
        result = subprocess.run([str(runner), str(manifest), str(output), str(width), str(height)],
                                env=dict(os.environ, MTL_DEBUG_LAYER="1"), stdout=log,
                                stderr=subprocess.STDOUT, timeout=180)
    receipt_path = output / "metal-results.json"
    receipt = json.loads(receipt_path.read_text()) if receipt_path.exists() else {"status": "failed"}
    receipt["bundleSHA256"] = hashlib.sha256(code.encode()).hexdigest()
    receipt["runnerSHA256"] = hashlib.sha256(native_source.read_bytes()).hexdigest()
    receipt["exitCode"] = result.returncode
    receipt["xcode"] = subprocess.check_output(["xcodebuild", "-version"], text=True).strip()
    receipt["metalCompiler"] = subprocess.check_output(["xcrun", "metal", "--version"], text=True).strip()
    if result.returncode:
        receipt["status"] = "failed"
    receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"status": receipt["status"], "image": str(output / "preview.png"),
                      "receipt": str(receipt_path)}, indent=2))
    return 0 if receipt["status"] == "passed" else 1
