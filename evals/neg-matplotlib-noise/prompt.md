---
description: "Near miss: procedural noise, but as a matplotlib figure."
tags: [negative]
expected_outcome: "plot_noise.py builds a noise field with numpy and saves a matplotlib heatmap to noise.png; the shader skill does not fire."
max_turns: 15
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

I need a quick figure for a blog post about procedural noise: plot a 2D Perlin-style noise field as a 256x256 heatmap with matplotlib, viridis colormap and a colorbar, and save it as `noise.png`. Put the script in `plot_noise.py`. numpy is fine, but please don't add other dependencies.
