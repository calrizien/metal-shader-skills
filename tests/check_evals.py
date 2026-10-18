#!/usr/bin/env python3
"""Validate evals/ against the `claude plugin eval` case format without running it (running costs money).

  python3 tests/check_evals.py

Checks every case's prompt.md and graders/*.md against the fields the plugin-evals docs list, enforces this suite's
conventions (positive / negative tags, identical shared graders, a skill-not-fired grader on negatives), and runs the
grader regexes on real inputs: the gallery shaders, the fixture shaders embedded in the prompts, and real output of
`glsl_tools.py check`. Frontmatter is parsed with a small YAML subset (scalars, quoted strings, flow lists, one level of
nested maps), so keep it within that subset.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVALS = ROOT / "evals"
TOOLS = ROOT / "skills" / "shader-art-coding" / "scripts" / "glsl_tools.py"

# https://code.claude.com/docs/en/plugin-evals#prompt-md-fields and #grader-frontmatter
PROMPT_FIELDS = {"schema_version", "name", "description", "tags", "plugins", "runs", "expected_outcome", "model",
                 "max_turns", "timeout_seconds", "allowed_tools", "append_system_prompt", "env"}
GRADER_COMMON = {"type", "weight", "arm"}
GRADER_OPTIONS = {
    "regex": {"pattern", "flags", "match", "target"},
    "tool_used": {"tool", "input_match", "min", "max"},
    "tool_order": {"before", "after"},
    "file_exists": {"path", "exists"},
    "llm": {"criteria", "focus"},
    "baseline": {"baseline_file", "criteria"},
}
TARGETS = {"last_message", "trace", "files", "mock_calls"}
TOOLS_KNOWN = {"Read", "Glob", "Grep", "NotebookRead", "Skill", "AskUserQuestion", "Agent", "TodoWrite", "TaskCreate",
               "TaskGet", "TaskList", "TaskUpdate", "TaskStop", "Bash", "Write", "Edit", "WebFetch", "WebSearch"}
# graders every positive case carries, byte-identical
SHARED_POSITIVE = ["mainimage", "no-banned-constructs", "ran-check", "check-clean", "skill-fired"]

errors: list[str] = []


def fail(where: str, msg: str) -> None:
    errors.append(f"{where}: {msg}")


# ------------------------------------------------------------------------------------------- frontmatter

def scalar(v: str, where: str):
    if v.startswith("'"):
        if len(v) < 2 or not v.endswith("'") or "'" in v[1:-1].replace("''", ""):
            fail(where, f"bad single-quoted string: {v}")
        return v[1:-1].replace("''", "'")
    if v.startswith('"'):
        try:
            return json.loads(v)
        except json.JSONDecodeError:
            fail(where, f"bad double-quoted string: {v}")
            return v
    if v.startswith("["):
        if not v.endswith("]"):
            fail(where, f"unterminated flow list: {v}")
        return [scalar(x.strip(), where) for x in v[1:-1].split(",") if x.strip()]
    if re.fullmatch(r"-?\d+", v):
        return int(v)
    if re.fullmatch(r"-?\d+\.\d+", v):
        return float(v)
    if v in ("true", "false"):
        return v == "true"
    if ": " in v or " #" in v or v[0] in "{&*!|>%@`":
        fail(where, f"quote this value: {v}")
    return v


def frontmatter(path: Path) -> tuple[dict, str]:
    where = str(path.relative_to(ROOT))
    text = path.read_text(encoding="utf-8")
    m = re.match(r"---\n(.*?)\n---(?:\n|$)(.*)", text, re.S)
    if not m:
        fail(where, "missing --- frontmatter ---")
        return {}, text
    data: dict = {}
    nested = None
    for line in m.group(1).split("\n"):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        kv = re.match(r"( *)([A-Za-z_][\w-]*):(?: +(.*))?$", line)
        if not kv:
            fail(where, f"cannot parse line: {line!r}")
            continue
        indent, key, val = kv.groups()
        target = data
        if indent:
            if nested is None:
                fail(where, f"unexpected indent: {line!r}")
                continue
            target = data[nested]
        if key in target:
            fail(where, f"duplicate key {key}")
        if val is None and not indent:
            target[key] = {}
            nested = key
        else:
            target[key] = scalar((val or "").strip(), where)
            if not indent:
                nested = None
    return data, m.group(2)


# ------------------------------------------------------------------------------------------- regexes

def js_regex(pattern: str, flags: str, where: str) -> re.Pattern | None:
    """Compile a grader's JavaScript regex with Python's re, rejecting syntax only one of the two accepts."""
    if re.search(r"\(\?[aiLmsux]+\)|\(\?P|\(\?>|\\[AZz]|[*+?}]\+", pattern):
        fail(where, f"pattern uses syntax JavaScript does not accept: {pattern}")
    if set(flags) - set("dgimsuyv"):
        fail(where, f"unknown JavaScript regex flags: {flags}")
    py_flags = (re.I if "i" in flags else 0) | (re.M if "m" in flags else 0) | (re.S if "s" in flags else 0)
    try:
        return re.compile(pattern, py_flags)
    except re.error as e:
        fail(where, f"pattern does not compile: {e}")
        return None


def grader_regex(case: str, grader: str) -> re.Pattern:
    data, _ = frontmatter(EVALS / case / "graders" / f"{grader}.md")
    key = "input_match" if data["type"] == "tool_used" else "pattern"
    rx = js_regex(data[key], data.get("flags", ""), f"{case}/{grader}")
    assert rx is not None
    return rx


# ------------------------------------------------------------------------------------------- format

def check_target(value, where: str, key: str) -> str | None:
    """Validate a target/focus value; return the workspace path it reads, if any."""
    if isinstance(value, dict):
        if set(value) != {"source", "path"} or value["source"] != "file" or not value["path"]:
            fail(where, f"{key} must be one of {sorted(TARGETS)} or {{source: file, path: <path>}}")
            return None
        return value["path"]
    if value not in TARGETS:
        fail(where, f"{key} {value!r} is not one of {sorted(TARGETS)}")
    return None


def check_grader(path: Path, prompt_body: str) -> None:
    where = str(path.relative_to(ROOT))
    data, body = frontmatter(path)
    gtype = data.get("type")
    if gtype not in GRADER_OPTIONS:
        fail(where, f"type {gtype!r} is not one of {sorted(GRADER_OPTIONS)}")
        return
    for key in set(data) - GRADER_COMMON - GRADER_OPTIONS[gtype]:
        fail(where, f"unknown key {key!r} for a {gtype} grader")
    if "arm" in data and data["arm"] not in ("with-only", "both"):
        fail(where, "arm must be with-only or both")
    if "weight" in data and not (isinstance(data["weight"], (int, float)) and data["weight"] > 0):
        fail(where, "weight must be a positive number")
    if gtype != "llm" and body.strip():
        fail(where, "only llm graders carry a body in this suite; put options in frontmatter")
    file_read = None
    if gtype == "regex":
        if not data.get("pattern"):
            fail(where, "regex grader needs a pattern")
        else:
            js_regex(data["pattern"], data.get("flags", ""), where)
        if "match" in data and not re.fullmatch(r"not_contains|count:\d+", str(data["match"])):
            fail(where, "match must be not_contains or count:N")
        file_read = check_target(data.get("target", "last_message"), where, "target")
    elif gtype == "tool_used":
        if not data.get("tool"):
            fail(where, "tool_used grader needs a tool")
        if "input_match" in data:
            js_regex(data["input_match"], "", where)
        for key in ("min", "max"):
            if key in data and not (isinstance(data[key], int) and data[key] >= 0):
                fail(where, f"{key} must be a non-negative integer")
    elif gtype == "llm":
        if not body.strip() and not data.get("criteria"):
            fail(where, "llm grader needs criteria (the file body)")
        file_read = check_target(data.get("focus", "last_message"), where, "focus")
    elif gtype == "file_exists" and not data.get("path"):
        fail(where, "file_exists grader needs a path")
    if file_read and f"`{file_read}`" not in prompt_body:
        fail(where, f"grades {file_read}, but the prompt never asks for `{file_read}`")


def check_case(case_dir: Path) -> str | None:
    """Validate one case; return its polarity tag."""
    where = str(case_dir.relative_to(ROOT))
    data, body = frontmatter(case_dir / "prompt.md")
    for key in set(data) - PROMPT_FIELDS:
        fail(where, f"unknown prompt.md field {key!r} (unknown keys are an error)")
    if not body.strip():
        fail(where, "prompt body is empty")
    if not 1 <= data.get("max_turns", 10) <= 200:
        fail(where, "max_turns must be 1..200")
    if not 1 <= data.get("timeout_seconds", 300) <= 3600:
        fail(where, "timeout_seconds must be 1..3600")
    if not 1 <= data.get("runs", 3) <= 50:
        fail(where, "runs must be 1..50")
    for tool in data.get("allowed_tools", []):
        if re.sub(r"\(.*\)$", "", tool) not in TOOLS_KNOWN:
            fail(where, f"unknown tool {tool!r} in allowed_tools")
    for key in data.get("env", {}) or {}:
        if not re.fullmatch(r"EVAL_[A-Z0-9_]*", key):
            fail(where, f"env key {key} must match EVAL_[A-Z0-9_]*")
    graders = sorted((case_dir / "graders").glob("*.md"))
    if not graders:
        fail(where, "a case needs at least one grader")
    for g in graders:
        check_grader(g, body)
    polarity = {"positive", "negative"} & set(data.get("tags", []))
    if len(polarity) != 1:
        fail(where, "tag the case with exactly one of positive / negative")
        return None
    return polarity.pop()


def check_suite_policy(positives: list[Path], negatives: list[Path]) -> None:
    for name in SHARED_POSITIVE:
        texts = {}
        for case in positives:
            p = case / "graders" / f"{name}.md"
            if not p.exists():
                fail(str(case.relative_to(ROOT)), f"positive case is missing the shared grader {name}.md")
            else:
                texts[case.name] = p.read_text(encoding="utf-8")
        if len(set(texts.values())) > 1:
            fail("evals", f"shared grader {name}.md differs between positive cases: {sorted(texts)}")
    for case in negatives:
        p = case / "graders" / "skill-not-fired.md"
        if not p.exists():
            fail(str(case.relative_to(ROOT)), "negative case needs graders/skill-not-fired.md")
            continue
        data, _ = frontmatter(p)
        if (data.get("tool"), data.get("min"), data.get("max"), data.get("arm")) != ("Skill", 0, 0, "both"):
            fail(str(p.relative_to(ROOT)), "skill-not-fired needs tool: Skill, min: 0, max: 0, arm: both")


# ------------------------------------------------------------------------------------------- grader self-tests

def fixture(case: str) -> str:
    _, body = frontmatter(EVALS / case / "prompt.md")
    m = re.search(r"```glsl\n(.*?)```", body, re.S)
    assert m, f"{case}: no ```glsl fixture in the prompt"
    return m.group(1)


def checker_output(src: str) -> str:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "final.glsl"
        path.write_text(src, encoding="utf-8")
        run = subprocess.run([sys.executable, str(TOOLS), "check", str(path)], capture_output=True, text=True)
    return run.stdout


def expect(name: str, rx: re.Pattern, text: str, found: bool) -> None:
    if bool(rx.search(text)) != found:
        fail("self-test", f"{name}: expected {'a match' if found else 'no match'}")


def self_tests() -> None:
    main_rx = grader_regex("sdf-still-life", "mainimage")
    banned_rx = grader_regex("sdf-still-life", "no-banned-constructs")
    for shader in sorted((ROOT / "gallery").glob("*.glsl")):
        text = shader.read_text(encoding="utf-8")
        expect(f"mainimage on gallery/{shader.name}", main_rx, text, True)
        expect(f"no-banned-constructs on gallery/{shader.name}", banned_rx, text, False)

    twisted, webgl1 = fixture("fix-twist-holes"), fixture("port-webgl1")
    expect("mainimage on the twist fixture", main_rx, twisted, True)
    expect("no-banned-constructs on the twist fixture", banned_rx, twisted, False)
    expect("mainimage on the WebGL1 fixture", main_rx, webgl1, False)
    for token in ("gl_FragColor = vec4(1.0);", "c = texture2D(t, uv);", "#version 300 es",
                  "return fract(sin(x) * 43758.5453);"):
        expect(f"no-banned-constructs on {token!r}", banned_rx, "void f() {}\n" + token, True)
        expect(f"no-banned-constructs on a comment about {token!r}", banned_rx, "x = 1.0; // was " + token, False)
    io_rx = grader_regex("port-webgl1", "no-webgl1-io")
    expect("no-webgl1-io on the WebGL1 fixture", io_rx, webgl1, True)
    expect("no-webgl1-io on the twist fixture", io_rx, twisted, False)

    clean, dirty = checker_output(twisted), checker_output(webgl1)
    if "0 error(s)" not in clean or "0 error(s)" in dirty:
        fail("self-test", f"unexpected glsl_tools.py check output:\n{clean}\n{dirty}")
    clean_rx = grader_regex("sdf-still-life", "check-clean")
    # Traces and tool inputs are compact JSON (no spaces after `:` or `,`), as in a real v2.1.299 eval trace.
    compact = lambda o: json.dumps(o, separators=(",", ":"))  # noqa: E731
    as_trace = lambda *outs: "\n".join(compact({"type": "tool_result", "content": o}) for o in outs)  # noqa: E731
    expect("check-clean on [clean]", clean_rx, as_trace(clean), True)
    expect("check-clean on [failing, clean]", clean_rx, as_trace(dirty, clean), True)
    expect("check-clean on [clean, failing]", clean_rx, as_trace(clean, dirty), False)
    expect("check-clean on [failing]", clean_rx, as_trace(dirty), False)
    expect("check-clean on '10 error(s)'", clean_rx, as_trace("10 error(s), 0 warning(s)"), False)

    ran_rx = grader_regex("sdf-still-life", "ran-check")
    bash = lambda cmd: compact({"command": cmd, "description": "Check the shader"})  # noqa: E731
    expect("ran-check on a relative check", ran_rx, bash("python3 scripts/glsl_tools.py check out.glsl"), True)
    expect("ran-check on a quoted absolute check", ran_rx,
           bash('cd /p/skills/shader-art-coding && python3 "scripts/glsl_tools.py" check "/w/final.glsl"'), True)
    expect("ran-check on the library self-check", ran_rx, bash("python3 scripts/glsl_tools.py check"), False)
    expect("ran-check on a bundle", ran_rx, bash("python3 scripts/glsl_tools.py bundle shader.glsl -o out.glsl"),
           False)

    skill_rx = grader_regex("sdf-still-life", "skill-fired")
    skill = lambda name: compact({"skill": name, "args": "Port the shader"})  # noqa: E731
    expect("skill-fired, namespaced", skill_rx, skill("shader-skills:shader-art-coding"), True)
    expect("skill-fired, bare", skill_rx, skill("shader-art-coding"), True)
    expect("skill-fired, other skill", skill_rx, skill("shader-skills:other"), False)


def main() -> int:
    cases = sorted(p.parent for p in EVALS.glob("*/prompt.md"))
    polarity = {c: check_case(c) for c in cases}
    positives = [c for c, p in polarity.items() if p == "positive"]
    negatives = [c for c, p in polarity.items() if p == "negative"]
    check_suite_policy(positives, negatives)
    if not errors:
        self_tests()
    for e in errors:
        print(f"ERROR   {e}")
    print(f"{len(cases)} case(s): {len(positives)} positive, {len(negatives)} negative; {len(errors)} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
