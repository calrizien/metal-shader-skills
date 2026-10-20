# Repository work

This is the Metal 4 fork of `gokayfem/shader-skills`. The installable skill is
`skills/metal-shader-art/`. Keep the upstream MIT license and credits.

## Source contract

- Target MSL 4.0, not an implicit compiler default.
- `metal/` contains scene-member functions. The bundler puts selected helpers
  and the user scene inside `ShaderScene`, with native vertex/fragment entries.
- Modules follow `MODULE_ORDER` in `scripts/metal_tools.py`.
- Keep function summaries, `@use` tags and SDF exactness tags.
- References that repeat a library function must use the same implementation.
- `templates/` are editable scene inputs. `gallery/*.metal` are generated bundles.
- Keep Apple API evidence in `references/metal4-integration.md`.

## Verification

Write observable failure cases before changing behavior. Use the existing GPU
property suite and end-to-end renderer; do not add wording or change-detector
tests. Keep the property tolerances unless mathematical evidence supports a change.

```sh
python3 skills/metal-shader-art/scripts/metal_tools.py index
python3 tests/build_gallery.py
python3 skills/metal-shader-art/scripts/metal_tools.py check
python3 tests/check_evals.py
python3 tests/run_metal.py --size 640x360 --save-gallery
git diff --check
```

The full runtime check uses an Apple silicon Mac with macOS 26+, Xcode 26+,
the Metal Toolchain, and a Metal 4 GPU. It runs with Metal API validation.
Inspect the native PNGs after visual changes. Preserve generated MSL, compiler
logs, failure counts, and source hashes in `build/`; a successful gallery run
also updates `verification/`.

CI compiles MSL on macOS. Hosted-runner compilation does not prove GPU behavior.
The optional self-hosted Metal 4 workflow runs the GPU suite. Model evaluations
are manual and separate; do not run paid evals without authorization.
