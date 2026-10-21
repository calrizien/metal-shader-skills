#!/usr/bin/env python3
"""Compile and run the Metal 4 E2E suite, preserving a repeatable receipt."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import time

from build_harness import build

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--size", default="320x180")
    parser.add_argument("--save-gallery", action="store_true")
    parser.add_argument("--output", type=Path, default=ROOT / "build/metal-e2e")
    args = parser.parse_args()
    if platform.system() != "Darwin" or platform.machine() != "arm64" or int(platform.mac_ver()[0].split(".")[0]) < 27:
        parser.error("the runtime suite requires an Apple silicon Mac with macOS 27+ and Metal 4")
    try:
        width, height = map(int, args.size.split("x"))
        if not 1 <= width <= 4096 or not 1 <= height <= 4096:
            raise ValueError
    except ValueError:
        parser.error("--size must be WIDTHxHEIGHT with dimensions from 1 to 4096")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    manifest = build(args.save_gallery)
    # Hash all source inputs before running; the receipt identifies the exact tested state.
    paths = sorted(p for directory in ["skills", "tests"] for p in (ROOT / directory).rglob("*")
                   if p.is_file() and "__pycache__" not in p.parts)
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    (output / "inputs.json").write_text(json.dumps(hashes, indent=2, sort_keys=True) + "\n")
    shutil.copyfile(manifest, output / "manifest.json")
    runner = ROOT / "build/metal-runner"
    source = ROOT / "skills/metal-shader-art/scripts/metal_runner.mm"
    command = ["xcrun", "clang++", "-std=c++17", "-fobjc-arc", "-O2", "-arch", "arm64",
               "-mmacosx-version-min=27.0", "-framework", "Foundation", "-framework", "Metal",
               "-framework", "CoreGraphics", "-framework", "ImageIO", str(source), "-o", str(runner)]
    compile_result = subprocess.run(command, text=True, capture_output=True, timeout=120)
    (output / "host-compile.log").write_text(compile_result.stdout + compile_result.stderr)
    if compile_result.returncode:
        print(compile_result.stdout + compile_result.stderr, file=sys.stderr)
        return compile_result.returncode
    env = dict(os.environ, MTL_DEBUG_LAYER="1")
    start = time.time()
    runtime_command = [str(runner), str(manifest), str(output), str(width), str(height)]
    with (output / "run.log").open("w") as log:
        result = subprocess.run(runtime_command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=1800)
    receipt_path = output / "metal-results.json"
    receipt = json.loads(receipt_path.read_text()) if receipt_path.exists() else {"status": "failed", "error": "runner produced no receipt"}
    receipt.update({
        "elapsedSeconds": round(time.time() - start, 3),
        "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
        "metalCompiler": subprocess.check_output(["xcrun", "metal", "--version"], text=True).strip(),
        "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "sourceState": "inputs.json is authoritative; the commit can precede local edits",
        "manifestSHA256": hashlib.sha256(manifest.read_bytes()).hexdigest(),
        "exitCode": result.returncode,
    })
    if result.returncode:
        receipt["status"] = "failed"
    receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    for item in receipt.get("results", []):
        if not item["pass"]:
            print("FAIL", item["kind"], item["name"], item.get("error", item.get("failureBits", "")))
    counts = {kind: sum(item["kind"] == kind for item in receipt.get("results", []))
              for kind in ["compile", "property", "render"]}
    print(json.dumps({"status": receipt["status"], "counts": counts, "receipt": str(receipt_path)}, indent=2))
    if receipt["status"] == "passed" and args.save_gallery:
        for item in receipt["results"]:
            if item["kind"] == "render" and "--" not in item["name"]:
                shutil.copyfile(output / item["image"], ROOT / "gallery" / item["image"])
        # Keep a compact committed proof artifact. Full generated sources/logs stay in build/.
        evidence = ROOT / "verification"
        evidence.mkdir(exist_ok=True)
        shutil.copyfile(receipt_path, evidence / "metal-results.json")
        shutil.copyfile(output / "inputs.json", evidence / "inputs.json")
    return 0 if receipt["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
