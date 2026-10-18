---
description: "Near miss: a GPU shader, but HLSL compute for Unity, which the skill description excludes."
tags: [negative]
expected_outcome: "Blur.compute is an HLSL compute shader with #pragma kernel and [numthreads]; no GLSL; the shader skill does not fire."
max_turns: 15
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Write me an HLSL compute shader for Unity that runs a separable 9-tap Gaussian blur on a RenderTexture, with one kernel for the horizontal pass and one for the vertical pass. Save it as `Blur.compute`.
