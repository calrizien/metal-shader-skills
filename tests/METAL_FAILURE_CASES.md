# Metal 4 port: failure cases

Written before implementation. Use the existing numerical properties as the
oracle. Do not relax their tolerances to make the port pass.

| Failure | Observable check |
|---|---|
| GLSL syntax remains, or MSL 4.1 is required | Compile every module, reference definition, template and annotated variant with `-std=metal4.0`. |
| Reference parameters use the wrong address space | Compile the complete library, including camera and volume helpers that write through references. |
| Matrix columns, negative modulo, boolean selection or integer hashes change | Run the existing GPU properties on Metal, with the same seeds, sample count and tolerances. |
| A dependency is hidden behind a quality macro | Compile and render every annotated quality/debug variant. |
| A scene callback is missing or a name is unresolved | Compile complete templates without synthetic scene stubs; use stubs only for isolated library/reference compilation. |
| Pixel origin is wrong or output is encoded twice | Inspect native Metal renders of the poster, terrain and still life; use one documented coordinate conversion and an unorm/float output target. |
| Metal 4 is only a label | The E2E runner must create an MTL4 compiler, queue, command allocator, command buffer and argument table, and record device/API/language in its receipt. |
| Resources are not resident or expire before GPU completion | Enable Metal validation; retain allocations, use a residency set and wait on a shared event before CPU readback or allocator reuse. |
| A render contains NaN, infinity, or an empty frame | Read the floating-point render target before conversion to PNG and fail with counts. |
| A compiler or GPU is missing | Fail required compile/runtime checks; allow an explicit lint-only mode with a different result. |
| The runner hangs or fails halfway | Use a bounded GPU wait; keep complete compiler output and a partial JSON receipt. |
| WebGL evidence is presented as Metal evidence | Replace gallery images only after native rendering and keep the Metal receipt with hashes. |

The full E2E run must save its generated MSL, diagnostics, numerical failure
counts, native PNGs, toolchain/device details and source hashes. Model skill
evaluations are a separate check and must not be reported as run unless run.
