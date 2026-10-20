# Formula-Code Couples: Materials, Color, Composition, and Polish

Use this file when the task needs equation-to-code translation for color ramps, masks, material layering, lighting, antialiasing, composition overlays, texture-like detail, or final polish.

Each couple has:

- Equation: the compact mathematical idea.
- MSL: an Metal scene implementation.
- Visual result: what should appear when the formula is correct.
- Debug view: the simplest way to inspect it.

## Contents

- [1. Smoothstep Mask](#1-smoothstep-mask)
- [2. Derivative Antialiasing](#2-derivative-antialiasing)
- [3. Fill Mask From SDF](#3-fill-mask-from-sdf)
- [4. Stroke Mask From SDF](#4-stroke-mask-from-sdf)
- [5. Cosine Palette](#5-cosine-palette)
- [6. Warm Light, Cool Shadow](#6-warm-light-cool-shadow)
- [7. Fresnel Rim](#7-fresnel-rim)
- [8. Normal-View Localized Warmth Mask](#8-normal-view-localized-warmth-mask)
- [9. Sparse Stochastic Spot Field](#9-sparse-stochastic-spot-field)
- [10. Radial-Cell ID Albedo Variation](#10-radial-cell-id-albedo-variation)
- [11. Local Cell Grain](#11-local-cell-grain)
- [12. Interstitial Boundary Mask](#12-interstitial-boundary-mask)
- [13. Material Lambda Mix](#13-material-lambda-mix)
- [14. Multi-Material Weighted Sum](#14-multi-material-weighted-sum)
- [15. Edge Wear](#15-edge-wear)
- [16. Dirt or Stain Gravity Bias](#16-dirt-or-stain-gravity-bias)
- [17. Specular Lobe](#17-specular-lobe)
- [18. Radial Chromatic Ring Field](#18-radial-chromatic-ring-field)
- [19. Composition Thirds Overlay](#19-composition-thirds-overlay)
- [20. Golden Ratio Overlay](#20-golden-ratio-overlay)
- [21. Tonemap](#21-tonemap)
- [22. Linear to sRGB](#22-linear-to-srgb)
- [23. Dithering](#23-dithering)
- [24. Slow Procedural Motion](#24-slow-procedural-motion)
- [25. Looping Time Phase](#25-looping-time-phase)
- [26. Temporal Aperture Pulse Mask](#26-temporal-aperture-pulse-mask)
- [27. Background Blur Weight](#27-background-blur-weight)
- [28. Material Debug Router](#28-material-debug-router)

Names here describe geometry, not subjects, so the formulas stay reusable. `subject-routing.md` maps them to subjects (for example, "bilobed carrier" is a head or torso). Helpers such as `sdEllipsoid`, `smin`, `hash12` and `fbm` come from `metal/` and are verified there.

## 1. Smoothstep Mask

Equation:

```text
m = S(a, b, x)
```

MSL:

```metal
float softMask(float a, float b, float x) {
    return smoothstep(a, b, x);
}
```

Visual result:

A soft transition from black to white. This is the base for almost every controllable material boundary.

Debug view:

```metal
fragColor = float4(float3(softMask(a, b, x)), 1.0);
```

## 2. Derivative Antialiasing

Equation:

```text
w = fwidth(x)
m = smoothstep(edge - w, edge + w, x)
```

MSL:

```metal
float aaStep(float edge, float x) {
    float w = fwidth(x);
    return smoothstep(edge - w, edge + w, x);
}
```

Visual result:

Sharp analytic masks become clean instead of stair-stepped.

Debug view:

Compare `step(edge, x)` and `aaStep(edge, x)` side by side.

## 3. Fill Mask From SDF

Equation:

```text
fill = smoothstep(w, -w, d)
```

MSL:

```metal
float sdfFill(float d) {
    float w = fwidth(d);
    return smoothstep(w, -w, d);
}
```

Visual result:

A filled 2D shape with antialiased edges.

Debug view:

Show `float3(sdfFill(d))`.

## 4. Stroke Mask From SDF

Equation:

```text
stroke = smoothstep(width+w, width-w, |d|)
```

MSL:

```metal
float sdfStroke(float d, float width) {
    float w = fwidth(d);
    return smoothstep(width + w, width - w, abs(d));
}
```

Visual result:

A clean outline or ring around a shape.

Debug view:

Show stroke alone before compositing.

## 5. Cosine Palette

Equation:

```text
color(t) = a + b cos(2pi(c t + d))
```

MSL:

```metal
float3 palette(float t, float3 a, float3 b, float3 c, float3 d) {
    return a + b*cos(6.2831853*(c*t + d));
}
```

Visual result:

Smooth repeating color harmonies useful for abstract shaders, heatmaps, irises, skies, and debug colors.

Debug view:

Render `palette(uv.x, ...)` as a horizontal strip.

## 6. Warm Light, Cool Shadow

Equation:

```text
color = albedo * (ambient + diffuse * warm) + shadowTint * (1-diffuse)
```

MSL:

```metal
float3 warmCoolDiffuse(float3 albedo, float3 n, float3 l) {
    float ndl = max(dot(n, l), 0.0);
    float3 warm = float3(1.08, 0.92, 0.72);
    float3 cool = float3(0.35, 0.45, 0.70);
    return albedo * (0.18*cool + ndl*warm);
}
```

Visual result:

Objects feel lit by sunlight rather than gray diffuse light.

Debug view:

Show `float3(ndl)` and then the warm/cool shaded output.

## 7. Fresnel Rim

Equation:

```text
F = (1 + dot(n, rd))^p
```

MSL:

```metal
float fresnelRim(float3 n, float3 rd, float power) {
    return pow(clamp(1.0 + dot(n, rd), 0.0, 1.0), power);
}
```

Visual result:

A soft rim highlight near silhouettes, useful for subsurface, waxy, crystalline, reflective, or stylized material regions.

Debug view:

Show rim as grayscale; it should hug the silhouette.

## 8. Normal-View Localized Warmth Mask

Equation:

```text
mask = regionMask * max(dot(n, -view), 0)^p
```

MSL:

```metal
float normalViewWarmth(float3 n, float3 viewDir, float regionMask) {
    float facing = pow(clamp(dot(n, -viewDir), 0.0, 1.0), 2.0);
    return regionMask * facing;
}
```

Visual result:

Soft localized warmth on selected convex material regions.

Debug view:

Show the localized warmth mask over a neutral albedo.

## 9. Sparse Stochastic Spot Field

Equation:

```text
cell = floor(uv N)
q = fract(uv N)-1/2
spot = exp(-k ||q||^2 / r)
spot *= step(threshold, hash(cell))
```

MSL:

```metal
float sparseSpotField(float2 uv) {
    float2 cell = floor(uv*25.0);
    float2 q = fract(uv*25.0) - 0.5;
    float r = 0.08 + 0.12*hash12(cell);
    float spot = exp(-24.0*dot(q, q) / r);
    return spot * step(0.78, hash12(cell + 19.1));
}
```

Visual result:

Sparse stochastic spots on a mapped surface. They should appear only inside a deliberate region mask.

Debug view:

Show sparse spots as black dots on white before material mixing.

## 10. Radial-Cell ID Albedo Variation

Equation:

```text
color = mix(C1, C2, hash(id))
```

MSL:

```metal
float3 cellIdAlbedo(float2 id) {
    float h = hash12(id);
    return mix(float3(0.42, 0.10, 0.06), float3(0.86, 0.28, 0.14), h);
}
```

Visual result:

Individual modular cells vary in albedo while remaining one material family.

Debug view:

Render cell IDs as colors before lighting.

## 11. Local Cell Grain

Equation:

```text
grain = fbm(localUV * frequency + seed)
color *= a + b grain
```

MSL:

```metal
float3 applyCellGrain(float3 color, float2 localUv, float2 id) {
    float seed = 13.0*hash12(id);
    float grain = fbm(localUv*18.0 + seed, 4);
    return color * (0.78 + 0.32*grain);
}
```

Visual result:

Rough local-coordinate detail that stays attached to each modular cell.

Debug view:

Show grain only in local coordinates. If it swims or crosses interstitial boundaries, the coordinate space is wrong.

## 12. Interstitial Boundary Mask

Equation:

```text
mask = smoothstep(edge0, edge1, distanceFromMortar)
```

MSL:

```metal
float interstitialToCellMask(float distFromInterstitial) {
    return smoothstep(0.02, 0.08, distFromInterstitial);
}
```

Visual result:

Clean transition from an interstitial material to a cell material.

Debug view:

Show the mask as grayscale; the interstitial field should be continuous.

## 13. Material Lambda Mix

Equation:

```text
C = C0(1-lambda) + C1 lambda
```

MSL:

```metal
float3 lambdaMix(float3 a, float3 b, float lambda) {
    return mix(a, b, clamp(lambda, 0.0, 1.0));
}
```

Visual result:

Any material blend becomes inspectable through one scalar control.

Debug view:

Always show `lambda` alone first.

## 14. Multi-Material Weighted Sum

Equation:

```text
C = sum_i w_i C_i / sum_i w_i
```

MSL:

```metal
float3 weightedMaterial(float3 c0, float3 c1, float3 c2, float3 w) {
    w = max(w, float3(0.0));
    return (c0*w.x + c1*w.y + c2*w.z) / max(0.001, w.x + w.y + w.z);
}
```

Visual result:

Three-channel material blends remain normalized and controllable.

Debug view:

Show `w` as RGB.

## 15. Edge Wear

Equation:

```text
wear = smoothstep(a, b, abs(distanceToEdge))
```

MSL:

```metal
float edgeWear(float bevelDistance, float noiseValue) {
    float edge = smoothstep(0.0, 0.08, bevelDistance);
    return clamp((1.0 - edge) + 0.25*noiseValue, 0.0, 1.0);
}
```

Visual result:

Lighter worn edges on any beveled or high-contact material.

Debug view:

Show wear mask before using it in albedo or roughness.

## 16. Dirt or Stain Gravity Bias

Equation:

```text
stain = noise(worldXZ) * smoothstep(top, bottom, y)
```

MSL:

```metal
float verticalStain(float3 p) {
    float flow = smoothstep(0.7, -0.4, p.y);
    float breakup = fbm(float2(p.x*1.7, p.z*1.7), 4);
    return flow * smoothstep(0.35, 0.8, breakup);
}
```

Visual result:

Weathering, moss, or grime collects downward rather than randomly everywhere.

Debug view:

Show stain as a mask over a neutral material.

## 17. Specular Lobe

Equation:

```text
spec = max(dot(reflect(-l,n), -rd), 0)^shininess
```

MSL:

```metal
float specularLobe(float3 n, float3 l, float3 rd, float shininess) {
    float3 r = reflect(-l, n);
    return pow(max(dot(r, -rd), 0.0), shininess);
}
```

Visual result:

Controlled highlights on glossy, wet, polished, crystalline, or reflective material regions.

Debug view:

Show specular alone. If it covers the whole object, shininess is too low or normals are wrong.

## 18. Radial Chromatic Ring Field

Equation:

```text
r = ||uv||
a = atan2(y,x)
iris = palette(r + noise(a,r))
```

MSL:

```metal
float3 radialRingColor(float2 uv) {
    float r = length(uv);
    float a = atan2(uv.y, uv.x);
    float fibers = 0.5 + 0.5*sin(34.0*a + 8.0*fbm(float2(r*5.0, a), 4));
    float3 inner = float3(0.16, 0.08, 0.03);
    float3 outer = float3(0.55, 0.32, 0.12);
    float3 col = mix(inner, outer, smoothstep(0.08, 0.45, r));
    col += 0.18*fibers*(1.0 - smoothstep(0.35, 0.48, r));
    return col;
}
```

Visual result:

Radial chromatic detail with an inner disk and outer ring.

Debug view:

Render the radial ring field in 2D before mapping it onto a surface.

## 19. Composition Thirds Overlay

Equation:

```text
line = smoothstep(width, 0, |uv.x - k|)
```

MSL:

```metal
float lineAt(float x, float k, float w) {
    return smoothstep(w, 0.0, abs(x - k));
}

float3 thirdsOverlay(float2 uv, float3 col) {
    float l = 0.0;
    l = max(l, lineAt(uv.x, -1.0/3.0, 0.006));
    l = max(l, lineAt(uv.x,  1.0/3.0, 0.006));
    l = max(l, lineAt(uv.y, -1.0/3.0, 0.006));
    l = max(l, lineAt(uv.y,  1.0/3.0, 0.006));
    return mix(col, float3(1.0, 0.85, 0.1), 0.5*l);
}
```

Visual result:

Temporary composition guides to place focal objects and horizon.

Debug view:

Use only during composition, then remove or gate behind a debug constant.

## 20. Golden Ratio Overlay

Equation:

```text
phi^-1 = 0.618...
```

MSL:

```metal
float3 goldenOverlay(float2 uv, float3 col) {
    float g = 0.6180339;
    float l = 0.0;
    l = max(l, lineAt(uv.x, -g, 0.005));
    l = max(l, lineAt(uv.x,  g, 0.005));
    l = max(l, lineAt(uv.y, -g, 0.005));
    l = max(l, lineAt(uv.y,  g, 0.005));
    return mix(col, float3(0.2, 0.9, 1.0), 0.45*l);
}
```

Visual result:

Subtle framing guides for dominant silhouettes, horizons, and focal masses.

Debug view:

Toggle with `#define DEBUG_COMPOSITION 1`.

## 21. Tonemap

Equation:

```text
display = T(exposure * hdr)       T = AgX (default), Khronos Neutral (palette-faithful), ACES (filmic contrast)
```

MSL: use `metal/tonemap.metal`. Every tonemapper there takes linear HDR and returns linear [0,1]. `x / (1 + x)`
looks grey (1.0 maps to 0.5) and shifts hue in highlights; avoid it for finished work.

```metal
float3 finishColor(float3 hdr, float exposure) {
    return tonemapAgX(hdr * exposure);
}
```

Visual result:

Suns, glows and specular highlights roll off smoothly toward white instead of clipping to flat saturated blobs.

Debug view:

Render a horizontal HDR ramp `float3(exp2(uv.x * 12.0 - 8.0))` through each tonemapper and compare the shoulders.

## 22. Linear to sRGB

Equation:

```text
srgb = 12.92 c                      for c <= 0.0031308
srgb = 1.055 c^(1/2.4) - 0.055      otherwise
```

MSL: `linearToSrgb` (and the inverse `srgbToLinear`) from `metal/color.metal`. `pow(c, 1/2.2)` is visibly wrong near
black: linear 0.001 encodes to 0.013 with the exact curve but 0.043 with gamma 2.2, which lifts and fogs shadows.

```metal
float3 encodeOutput(float3 linearColor) { return linearToSrgb(linearColor); }
```

Visual result:

Correct mid-tones and clean shadows. Apply exactly once, after tonemapping and after averaging AA samples.

Debug view:

A linear ramp `float3(uv.x)` encoded once should look perceptually even; encoded twice it looks washed out.

## 23. Dithering

Equation:

```text
encoded += (u1 + u2 - 1) / 255        triangular PDF, +-1 LSB, added after encoding
```

MSL: `ditherTPDF(fragCoord, frame)` from `metal/post.metal`.

```metal
float3 finalPixel(float3 hdr, float exposure, float2 fragCoord) {
    return linearToSrgb(tonemapAgX(hdr * exposure)) + ditherTPDF(fragCoord, frame);
}
```

Visual result:

Smooth skies, fog and vignettes with no banding and no visible noise.

Debug view:

Multiply the dither by 32 to see its pattern; it should be fine, even grain with no structure.

## 24. Slow Procedural Motion

Equation:

```text
offset(t) = A (noise(wt + seed) - 1/2)
```

MSL:

```metal
float slowNoise(float t, float seed) {
    return fbm(float2(0.13*t, seed), 4);
}

float3 subtleCameraOffset(float t) {
    return 0.01*float3(
        slowNoise(t, 1.0) - 0.5,
        slowNoise(t, 2.0) - 0.5,
        slowNoise(t, 3.0) - 0.5
    );
}
```

Visual result:

Camera or subject breathes subtly. Motion should feel alive, not unstable.

Debug view:

Print/plot the offset mentally: it should be low amplitude and low frequency.

## 25. Looping Time Phase

Equation:

```text
phase = 2pi fract(t / duration)
```

MSL:

```metal
float loopPhase(float t, float duration) {
    return 6.2831853 * fract(t / duration);
}
```

Visual result:

Reusable loop control for periodic field motion, aperture changes, flow, or camera orbit.

Debug view:

Animate `sin(phase)` and confirm it loops without a jump.

## 26. Temporal Aperture Pulse Mask

Equation:

```text
blink = smooth pulse over phase
```

MSL:

```metal
float aperturePulseAmount(float t) {
    float ph = fract(t / 4.0);
    float close = smoothstep(0.02, 0.05, ph);
    float open = smoothstep(0.11, 0.16, ph);
    return close * (1.0 - open);
}
```

Visual result:

A parameter closes briefly and reopens, useful for any aperture-like animated feature.

Debug view:

Show aperture openness as a number or mask before driving geometry.

## 27. Background Blur Weight

Equation:

```text
color' = sum_i w_i color(uv + offset_i) / sum_i w_i
```

MSL:

```metal
float3 tinyBlur(texture2d<float> tex, sampler textureSampler, float2 uv, float2 px) {
    float3 c = float3(0.0);
    float wsum = 0.0;
    for (int i = -2; i <= 2; i++) {
        float w = 1.0 - abs(float(i))/3.0;
        c += w * tex.sample(textureSampler, uv + px*float(i)).rgb;
        wsum += w;
    }
    return c / wsum;
}
```

Visual result:

Soft background or post-effect blur when texture input is available. For pure procedural scenes, use distance/fog instead.

Debug view:

Compare blurred and original background side by side.

## 28. Material Debug Router

Equation:

```text
debugMode selects scalar/vector field
```

MSL:

```metal
float3 debugMaterialRouter(int mode, float3 col, float3 n, float mat, float depth, float mask) {
    if (mode == 1) return 0.5 + 0.5*n;
    if (mode == 2) return float3(fract(mat*0.37), fract(mat*0.61), fract(mat*0.83));
    if (mode == 3) return float3(depth * 0.03);
    if (mode == 4) return float3(mask);
    return col;
}
```

Visual result:

A shader that can be inspected without rewriting code.

Debug view:

This is itself the debug view; keep it cheap and removable.
