// Flat-graphic poster: dusk sky, striped sun, layered ridges, foliage and stars, all from 2D distance fields.
// Shows: 2D SDF primitives, antialiasing with a fixed pixel size, Oklab gradients, polar repetition for petals,
// per-cell randomness, layered composition back-to-front, film grain, Neutral tonemap for palette fidelity.
// @render time=3.0

#define DEBUG_MODE 0   // 0 final | 1 distance field of the foliage layer | 5 layer masks

// ---- palette (sRGB picks, decoded to linear before use) ----
const float3 SKY_TOP = float3(0.13, 0.10, 0.30);
const float3 SKY_HORIZON = float3(0.98, 0.52, 0.36);
const float3 SUN = float3(1.0, 0.86, 0.55);
const float3 RIDGE_FAR = float3(0.55, 0.30, 0.42);
const float3 RIDGE_NEAR = float3(0.20, 0.12, 0.26);
const float3 FOLIAGE = float3(0.07, 0.05, 0.12);

// Ridge silhouette: y below the line is "inside". Returns an approximate signed distance (good enough for AA).
float ridge(float2 uv, float base, float amp, float freq, float seed) {
    float h = base + amp * fbm(float2(uv.x * freq + seed, seed), 5);
    return (uv.y - h) / sqrt(1.0 + 4.0 * amp * amp * freq * freq);   // divide by an approximate slope bound
}

// A palm-like plant: a curved trunk plus a fan of vesica leaves around its crown.
float plant(float2 p) {
    float trunk = sdQuadraticBezier(p, float2(0.0, -1.0), float2(0.12, -0.45), float2(0.02, 0.0)) - 0.025;
    float2 q = p - float2(0.02, 0.0);
    q = domPolar(q, 9.0);                 // 9 leaves, each pointing along +X in its sector
    q.y += 0.06 * q.x * q.x;              // droop
    float leaf = sdVesica((q - float2(0.24, 0.0)).yx, 0.32, 0.27);
    return min(trunk, leaf);
}

void shade(thread float4 &fragColor, float2 fragCoord) {
    float2 uv = (2.0 * fragCoord - resolution.xy) / resolution.y;
    float px = 2.0 / resolution.y;

    // sky: perceptual gradient
    float3 col = mixOklab(srgbToLinear(SKY_HORIZON), srgbToLinear(SKY_TOP), smoothstep(-0.3, 1.0, uv.y));

    // stars: one random star per grid cell, fading toward the horizon
    float2 cell = floor(uv * 18.0);
    float3 rnd = hash32(cell);
    float star = sdCircle(uv * 18.0 - cell - 0.2 - 0.6 * rnd.xy, 0.02 + 0.05 * rnd.z * rnd.z) / 18.0;
    float twinkle = 0.6 + 0.4 * sin(time * (1.0 + 3.0 * rnd.z) + 6.0 * rnd.x);
    col += float3(1.0, 0.95, 0.9) * fillAA(star, px) * smoothstep(0.1, 0.8, uv.y) * twinkle;

    // sun with retro gaps that thicken toward its bottom edge
    float2 sp = uv - float2(0.42, 0.18);
    float sun = sdCircle(sp, 0.36);
    float gaps = filteredStripes(sp.y * 14.0 + 0.5, px * 14.0);
    float gapMask = mix(1.0, gaps, smoothstep(0.0, -0.3, sp.y)) ;
    col = mix(col, srgbToLinear(SUN) * 1.6, fillAA(sun, px) * gapMask);
    col += srgbToLinear(SUN) * 0.25 * exp(-6.0 * max(sun, 0.0));   // glow

    // ridges, back to front
    col = mix(col, srgbToLinear(RIDGE_FAR), fillAA(ridge(uv, -0.1, 0.18, 1.2, 3.0), px));
    col = mix(col, mixOklab(srgbToLinear(RIDGE_FAR), srgbToLinear(RIDGE_NEAR), 0.6),
              fillAA(ridge(uv, -0.32, 0.14, 1.8, 11.0), px));
    col = mix(col, srgbToLinear(RIDGE_NEAR), fillAA(ridge(uv, -0.55, 0.10, 2.6, 23.0), px));

    // foreground plants
    float plants = min(plant((uv - float2(-0.95, 0.15)) / 0.9) * 0.9, plant((uv - float2(1.25, -0.05)) * float2(-1.0, 1.0) / 0.7) * 0.7);
    col = mix(col, srgbToLinear(FOLIAGE), fillAA(plants, px));

#if DEBUG_MODE == 1
    fragColor = float4(debugDistance(plants), 1.0);
    return;
#elif DEBUG_MODE == 5
    fragColor = float4(fillAA(sun, px), fillAA(ridge(uv, -0.1, 0.18, 1.2, 3.0), px), fillAA(plants, px), 1.0);
    return;
#endif

    // finish: grain in linear, palette-faithful tonemap, encode, dither
    col = filmGrain(col, 0.04, hash13(float3(fragCoord, frame)) * 2.0 - 1.0);
    col = linearToSrgb(tonemapNeutral(col)) + ditherTPDF(fragCoord, frame);
    fragColor = float4(col, 1.0);
}
