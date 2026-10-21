# Model behavior evaluations

These cases adapt the upstream `claude plugin eval` suite for `metal-shader-art`.
They check skill selection and output rules. **They have not been run as model
evaluations for this fork.** The Metal GPU receipt is a separate library check.

| Case | Expected task |
|---|---|
| sdf-still-life | Native MSL still life |
| terrain-flyover | Animated terrain camera |
| cloud-layer | Volumetric clouds |
| poster-2d | Antialiased 2D poster |
| fix-twist-holes | Correct a deformed distance field |
| port-webgl1 | Port GLSL input to MSL 4.1 with explicit resources |
| neg-css-gradient | Keep a CSS task in CSS |
| neg-hlsl-compute | Keep a Unity compute task in HLSL |
| neg-matplotlib-noise | Keep a plotting task in Python |

Positive cases ask for `final.metal` with a native fragment entry. Shared graders
check that entry, rejected GLSL syntax, actual use of the MSL compiler, and skill
selection. The compiler/skill indicators are with-plugin-only because the
no-plugin run has no bundled tools. Regex output graders do not prove a good
image or correct resource binding.

Validate the case files and grader fixtures without model calls:

```sh
python3 tests/check_evals.py
```

This command uses the local Metal compiler for its fixture checks. It does not
invoke a model or access credentials.

For an authorized paid model run on a Mac with Xcode and Metal tools, use the
installed Claude Code plugin-eval command. A bounded example is:

```sh
claude plugin eval . --case sdf-still-life --runs 1 --ablation none --no-publish --max-cost-usd 2 --allow-tools Write Edit Bash
```

Confirm the options against the installed CLI. Keep its model receipts separate
from `verification/metal-results.json`. Inspect saved generated shaders with the
compiler and renderer; the texture-port case also needs a host that binds its
specified texture and sampler. The preview runner's default contract uses only
the uniform buffer.

The fork does not run paid model evaluations in CI. Extend these cases when a
real task shows a gap, and do not count format validation as model performance.
