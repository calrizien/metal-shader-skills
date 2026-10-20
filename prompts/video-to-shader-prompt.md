# Video reference to Metal 4 shader

Use this prompt with a supplied video or frame sequence. It asks for a procedural
approximation, not a pixel-identical reconstruction.

---

Use the `metal-shader-art` skill to reconstruct the main visual structure and
motion of the supplied reference as a native Metal 4 shader. Target MSL 4.0.

First inspect the reference. Describe the camera, silhouette, depth layers,
materials, light, colors, repeated forms, and motion. Identify what can be
computed procedurally and what needs an external texture or scene asset. State
any missing timing, scale, or viewpoint information.

Choose the smallest suitable scene model: 2D fields, SDF raymarching,
heightfields, volumes, or a combination. Start with composition and silhouette.
Use the supplied library functions by name. Build a first native preview before
adding small detail.

Use `resolution`, `time`, and `frame` from the explicit scene uniform buffer.
For a loop, derive a local time with `floorMod(time + startTime, duration)` and
check the boundary. Keep animation deterministic for a given frame. Preserve
an explicit camera and named controls for scale, color, light, and speed.

Add `DEBUG_MODE` views for fields, normals, material IDs, steps, masks, and light.
Annotate important quality presets so the native suite can compile and render
them. State the chosen resolution and cost budget. Do not claim real-time
performance without a measurement on the target GPU.

Deliver:

- An editable scene input and a complete bundled `.metal` file.
- MSL 4.0 compiler results, with full diagnostics for any failure.
- Native PNG previews at representative times and the render receipts.
- A short list of art controls and remaining differences from the reference.
- The host resource and color contract if it differs from the supplied template.

Commands, from the installed skill directory:

```sh
python3 scripts/metal_tools.py search <subject>
python3 scripts/metal_tools.py bundle scene.metal -o final.metal
python3 scripts/metal_tools.py check final.metal
python3 scripts/metal_tools.py render final.metal --output build/preview --time 2.0
```

Inspect the native output. Treat compilation, GPU execution, visual similarity,
and performance as separate results.
