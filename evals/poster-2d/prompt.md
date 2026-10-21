---
description: "2D distance-field graphics: shapes, outlines, halftone, antialiasing."
tags: [positive]
expected_outcome: "final.metal is a Metal 4 fragment 2D poster shader that follows the hard rules; the skill fires and its checker reports 0 errors."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Design a flat 2D poster as a Metal 4 shader: a big sun disc over three overlapping mountain silhouettes, a thin inset frame, halftone dots in the sky, crisp antialiased edges, and a retro orange-and-teal palette. Save the finished, standalone MSL 4.1 shader with fullscreenVertex and shaderFragment entry functions as `final.metal`.
