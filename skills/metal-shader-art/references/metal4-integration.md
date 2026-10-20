# Metal 4 integration

## Contents

- [Baseline and sources](#baseline-and-sources)
- [Shader and host contract](#shader-and-host-contract)
- [Metal 4 lifecycle](#metal-4-lifecycle)
- [GLSL to MSL](#glsl-to-msl)
- [Color and coordinates](#color-and-coordinates)
- [Verification](#verification)
- [Scope](#scope)

## Baseline and sources

Target **MSL 4.0** explicitly with `-std=metal4.0`, or
`MTLCompileOptions.languageVersion = .version4_0`. Use Xcode 26 or later
with its Metal Toolchain. The native runner targets macOS 26 and arm64.
Check OS availability and `device.supportsFamily(.metal4)` before creating
Metal 4 objects. MSL 4.0 language support alone does not prove that a device
supports every optional GPU feature.

Apple's linked specification was version 4.1, dated June 4, 2026, when checked
on October 20, 2026. Its section 1.6.10 gives separate `metal4.0` and `metal4.1`
targets. This fork uses the 4.0 baseline. Do not adopt a 4.1-only feature without
changing and checking the requested deployment target.

Primary sources:

- [Metal Shading Language Specification](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf):
  language options, section 1.6.10; coordinates, 1.7; vector/matrix layout,
  2.2–2.5; address spaces, chapter 4; function attributes, chapter 5.
- [Understanding the Metal 4 core API](https://developer.apple.com/documentation/metal/understanding-the-metal-4-core-api):
  queues, buffers, allocators, encoders, and argument tables.
- [Resource synchronization](https://developer.apple.com/documentation/metal/resource-synchronization):
  select barriers and events for the actual producer/consumer dependency.
- [Residency sets](https://developer.apple.com/documentation/metal/simplifying-gpu-resource-management-with-residency-sets):
  make allocations accessible to the GPU.
- [Drawing a triangle with Metal 4](https://developer.apple.com/documentation/metal/drawing-a-triangle-with-metal-4):
  a native frame loop.
- [MTL4Compiler](https://developer.apple.com/documentation/metal/mtl4compiler):
  Metal 4 pipeline compilation.

Refresh these sources for new APIs or hardware decisions. The specification
remains on Apple's site; this repository does not redistribute the PDF.

## Shader and host contract

`bundle` emits a standalone translation unit. It contains a full-screen triangle
vertex function and a fragment function named `shaderFragment`.

The fragment's constant buffer occupies **buffer slot 0**:

| Field | MSL | Offset | Bytes |
|---|---|---:|---:|
| resolution | float2 | 0 | 8 |
| time | float | 8 | 4 |
| frame | uint | 12 | 4 |

Total stride: **16 bytes**. Alignment: **8 bytes**. A matching Swift value is:

```swift
struct ShaderUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var frame: UInt32
}
```

Check `MemoryLayout<ShaderUniforms>.stride == 16` when integrating. The bundled
fragment constructs a thread-local scene from this buffer. Scene functions and
library helpers are members of that object; this is the bundler's source format.
Call `shade(thread float4 &color, float2 pixel)` to compute a scene pixel.

`float3` has 16-byte size and alignment in MSL. A host struct with three packed
scalars is not interchangeable with a `float3` buffer field. Use matching
SIMD types or an intentional `packed_float3` layout and verify offsets.

Textures are explicit resources. For a textured native fragment, accept a
`texture2d<float> source [[texture(0)]]` and a
`sampler sourceSampler [[sampler(0)]]`, then pass them to the scene helper
that uses `source.sample(sourceSampler, uv)`. Add matching texture and sampler
entries to the argument table. Shipped templates need only the uniform buffer;
they do not invent external images or textures.

## Metal 4 lifecycle

The supplied `scripts/metal_runner.mm` is an executable host example. It uses
Objective-C++ so its API calls match Apple's Metal headers directly.

1. Create an `MTL4CommandQueue`, `MTL4Compiler`, `MTL4CommandBuffer`, and
   `MTL4CommandAllocator` from the device.
2. Compile the MSL library with language version 4.0. Create
   `MTL4LibraryFunctionDescriptor` values for the vertex and fragment functions,
   then create a pipeline with `MTL4RenderPipelineDescriptor` and the compiler.
3. Allocate a uniform buffer and target texture. Set the argument table's
   `maxBufferBindCount` to at least 1 and bind the buffer's `gpuAddress` at 0.
   Bind the table to the fragment stage with `setArgumentTable`.
4. Add all used allocations to an `MTLResidencySet`, commit its changes, then
   attach it to the queue or command buffer. Residency and object lifetime are
   separate duties. Keep strong references to all resources until GPU completion.
5. Begin the command buffer with an allocator, encode the render pass, end the
   encoder, end the command buffer, and commit it through the Metal 4 queue.
6. Signal a shared event after submission. Wait for the event before CPU
   readback, resource release, or allocator reset. The runner has one submission
   in flight and uses a bounded wait.

For an app frame loop, use a bounded set of allocators and uniform buffers for
the frames in flight. Reuse each allocator only after its GPU work has finished.
Argument tables snapshot bindings at draw/dispatch time, but this does not
snapshot a buffer's bytes. Do not overwrite a uniform buffer while the GPU
still reads it.

Metal 4 needs explicit resource synchronization. For multiple dependent passes,
use barriers with the correct producer/consumer stages, or events between
queues. A residency set does not resolve a read-after-write hazard.
The example's one render pass followed by a shared-event CPU wait does not
demonstrate synchronization between multiple GPU passes.

For an `MTKView`, set its color pixel format to match the pipeline. Account for
drawable availability and presentation with the Metal 4 queue's drawable wait
and signal operations. The offscreen runner does not present a drawable.

## GLSL to MSL

| GLSL construct | MSL form |
|---|---|
| vec2 / vec3 / vec4 | float2 / float3 / float4 |
| mat2 / mat3 / mat4 | float2x2 / float3x3 / float4x4 |
| out or inout local parameter | thread T &value |
| uniform | explicit constant buffer argument |
| atan(y, x) | atan2(y, x) |
| mod(x, y) | floorMod(x, y) for floor-based wrapping |
| dFdx / dFdy | dfdx / dfdy |
| vec2[3](a, b, c) | float2 values[3] = {a, b, c} |
| lessThan(a, b) | a < b; use any/all to reduce a vector |
| texture(texture, uv) | texture.sample(sampler, uv) |
| mainImage | shade scene method, called by a native fragment entry |

Both languages use column-major matrices, but constructor and conversion rules
still need a compile check. Do not substitute element-wise multiplication for
a matrix product. MSL permits ordinary C++ structures; the old WebGL ban on
structure ternaries is not a Metal rule.

A vector swizzle cannot bind to a non-const reference. Write
`p.xz = p.xz * rotation` instead of `p.xz *= rotation` when a matrix operator
requires a reference to its left operand. Copy a swizzle to a local variable
before passing it to a helper with a `thread T &` output parameter.

Address spaces are part of pointer/reference types. A `thread` reference to a
local value cannot stand in for `device` buffer storage. This library's output
parameters write to local scene variables. Choose another address space only
when the function's storage contract requires it.

## Color and coordinates

Metal's fragment position uses a top-left viewport origin. The scene adapter
passes `(position.x, height - position.y)` to the scene so its existing camera,
noise, and poster math uses bottom-left pixel centers.

The templates encode final color with `linearToSrgb`. The runner stores that
value in an **RGBA32Float target**, checks finite values before conversion, and
saves an sRGB-tagged PNG without another transfer function.
For direct display, a non-sRGB format such as `bgra8Unorm` accepts this encoded
value. If the app uses `bgra8Unorm_srgb`, return linear color instead and let the
attachment encode it. Avoid a second encoding.

Sample an sRGB texture through an sRGB texture format when appropriate; those
samples are already decoded to linear. Do not decode them again in the shader.
For HDR output, choose a separate exposure, tone mapping, color space and
display contract; these SDR examples do not prove an HDR path.

## Verification

- `check` compiles with `xcrun -sdk macosx metal -std=metal4.0 -fno-fast-math`.
  It fails if the compiler is absent. Full diagnostics stay in `build/metal-compile`.
- `render` compiles and runs one complete bundle with Metal 4 and saves its MSL,
  PNG, and JSON receipt. Inspect the image.
- From the repository, `python3 tests/run_metal.py --save-gallery` compiles every
  library/reference/template unit, runs the existing GPU properties at
  16,384 samples each, and renders all annotated variants. It checks floating
  point output before PNG conversion and saves full logs and hashes in `build/`.
- Safe math is the validation baseline. Fast math or half precision needs a
  separate measured comparison.

## Scope

This skill covers procedural fragment art. The compiler checks are macOS checks;
they do not prove iOS or visionOS runtime behavior. The native runner does not
prove SwiftUI stitchable shader or RealityKit CustomMaterial integration.
Those systems have their own entry signatures and constraints.
Metal 4 ML/tensor, mesh, and ray-tracing pipelines need separate, task-specific
design and capability checks. Do not add them to a small fragment effect
without a concrete need.
