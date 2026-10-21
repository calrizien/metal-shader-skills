---
name: metal-shader-art
description: >-
  Write, port, debug, and refine procedural Metal Shading Language shaders for
  Metal 4: SDF scenes, noise, terrain, water, clouds, lighting, and color.
  Use for .metal shader art, GLSL-to-MSL ports, or native Apple GPU visual
  effects. Includes a function library, bundler, compiler check, and native
  renderer. Not for HLSL, CSS effects, or general-purpose GPU compute.
license: MIT
metadata:
  target: Metal 4 / MSL 4.1
---

# Metal Shader Art

Start with the intended image. Build the scene in visible stages and inspect
the native Metal result. Use MSL 4.1 as the language baseline.

## Workflow

1. Set the subject, camera, materials, light, motion, resolution, and GPU budget.
   For host integration or a port, read `references/metal4-integration.md`.
2. Choose a template with `references/subject-routing.md`. Search the library
   with `python3 scripts/metal_tools.py search <words>`. Call the supplied
   functions by name instead of copying their implementation.
3. Get a first image with one form and one light. Add `DEBUG_MODE` views.
   Refine shape, composition, materials, light, atmosphere, then performance.
4. Bundle and compile:
   `python3 scripts/metal_tools.py bundle scene.metal -o final.metal`
   and `python3 scripts/metal_tools.py check final.metal`.
   The checker requires Apple's Metal compiler and uses `-std=metal4.1`.
   `--lint-only` is an explicit static check and does not prove compilation.
5. Render with `python3 scripts/metal_tools.py render final.metal --output build/preview`.
   Inspect the PNG and receipt. Fix visible faults before calling the image
   verified. If this host has no Metal 4 GPU, state that runtime proof is pending.

Run these commands from the installed skill directory, or use absolute script
paths. Python tools use the standard library. Rendering needs an Apple silicon
Mac, macOS 27 or later, Xcode 27 or later, and the Metal Toolchain.

## Scene contract

Templates contain native MSL scene members:

```metal
void shade(thread float4 &color, float2 pixel) {
    float2 uv = (2.0 * pixel - resolution) / resolution.y;
    float d = sdCircle(uv, 0.55);
    float mask = fillAA(d, 2.0 / resolution.y);
    color = float4(float3(mask), 1.0);
}
```

The bundler places the scene and required helpers in a thread-local
`ShaderScene`. Its `resolution` (`float2`), `time` (`float`), and `frame` (`int`)
members come from an explicit constant buffer. This keeps scene callbacks such
as `float2 map(float3 p)` available to the raymarch helpers without mutable
global variables. The result is a complete `.metal` file with
`fullscreenVertex` and `shaderFragment` entry functions.

- `map(p)` returns `float2(distance, materialId)`. Keep distance and material
  units consistent with the selected template.
- Scene pixels use a bottom-left origin. The fragment entry converts Metal's
  top-left pixel coordinates once. Do not add a second flip.
- `DEBUG_MODE`: 0 final, 1 distance, 2 normals, 3 IDs, 4 steps, 5 masks,
  6 light terms. Annotate important presets with `// @variant QUALITY=3`.
- Respect each SDF's `@exact`, `@bound`, or `@approx` tag. A twist, displacement,
  or nonuniform scale can require a smaller ray step.
- Use float precision for distance, coordinates, and noise. Change to half only
  after measuring error and GPU cost on the target device.

## MSL rules that matter

- Use `float2/3/4`, `floatNxN`, `thread T &` for local output parameters, and
  `constant T & [[buffer(n)]]` for uniform data. Match the host ABI.
- Use `atan2(y, x)`, `dfdx`, `dfdy`, brace-initialized arrays, and explicit
  texture/sampler bindings. Use `floorMod` for floor-based wrapping; `fmod`
  has different behavior for negative coordinates.
- Use integer PCG hashes for stable cell noise. Guard zero denominators,
  invalid square roots and powers, and zero-length normals.
- Derivatives belong in fragment work with uniform control flow. Use
  `fillAA(d, pixelWidth)` when derivatives are unavailable.
- Light in linear color. Apply exposure, tonemap each AA sample, then average.
  Shipped templates encode with `linearToSrgb` once and need a non-sRGB target.
  For an `_sRGB` render target, remove that manual encoding. Never do both.
- MSL 4.1 is a language setting. Metal 4 also has a host API. Use argument
  tables, residency sets, command allocators, and explicit synchronization
  where that API requires them; see `references/metal4-integration.md`.

## References

Read only the material needed for the task.

| Reference | Use |
|---|---|
| `references/metal4-integration.md` | MSL version, native entry points, host bindings, Metal 4 lifecycle, porting |
| `references/subject-routing.md` | Select a technique and template from the subject |
| `references/library-index.md` | Function signatures, exactness, uses |
| `references/sdf-library-guide.md` | SDF modeling, blends, repetition, deformation |
| `references/rendering-pipeline.md` | Lighting, sky, fog, volumes, color, AA |
| `references/noise-use-cases.md` | Noise families, derivatives, fBm, warping |
| `references/procedural-buildings.md` | Parcels, massing, roofs, filtered facades |
| `references/terrain-production.md` | Heightfields, tracing, biomes, chunks, LOD |
| `references/water-quality.md` | Waves, reflection, refraction, absorption, foam |
| `references/shader-workflow.md` | Plan and review a complex shader |
| `references/composition-and-debugging.md` | Diagnose a weak image or visible defect |
| `references/formula-cookbook.md` | Multi-step scene recipes |
| `references/formula-code-couples-sdf.md` | SDF equations and MSL |
| `references/formula-code-couples-terrain.md` | Terrain and atmosphere equations and MSL |
| `references/formula-code-couples-materials.md` | Materials, color, motion equations and MSL |

The 11 templates cover still life, terrain, ocean, clouds, a 2D poster,
pattern swatches, noise studies, a terrain map, a city, an alpine valley,
and coastal water. `templates/*.metal` are scene inputs; `gallery/*.metal`
in the repository are complete bundles.

## Delivery

Deliver the complete `.metal` file, host binding contract, and a short tuning
guide. State compile, GPU numerical, and visual results separately. Include the
repeatable command and receipt when a renderer ran. A procedural foam mask is
not a fluid simulation; a heightfield does not provide caves. State such limits
when they affect the requested result.
