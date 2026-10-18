---
description: "Near miss: asks for a shader-demo look, but in plain CSS."
tags: [negative]
expected_outcome: "hero.css animates a CSS gradient with @keyframes; the shader skill does not fire."
max_turns: 15
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

For my landing page I want an animated gradient background, that soft, slowly drifting multi-colour blob look you see in WebGL shader demos, but in plain CSS with no canvas or JavaScript. Purple, coral and a little teal. Save it as `hero.css`, styling a `.hero` class.
