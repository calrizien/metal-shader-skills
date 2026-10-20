//! common: constants, rotation, remapping and shaping functions.
//! Target: Metal Shading Language 4.0. Every function here is original and MIT licensed.

const float PI  = 3.14159265358979;
const float TAU = 6.28318530717959;

/// Clamp to [0,1].
/// @use masks, weights, colors
float saturate(float x) { return clamp(x, 0.0, 1.0); }
float3 saturate(float3 x) { return clamp(x, 0.0, 1.0); }

/// Squared length.
/// @use cheap distance comparisons, SDF internals
float dot2(float2 v) { return dot(v, v); }
float dot2(float3 v) { return dot(v, v); }

/// 2D rotation matrix. `rot2(a) * v` rotates v counter-clockwise by a radians.
/// Normalize the trig pair to keep the rotation length-preserving under finite precision.
/// @use spinning parts, posing limbs, rotating octaves, camera roll
float2x2 rot2(float a) {
    float2 cs = normalize(float2(cos(a), sin(a)));
    return float2x2(cs.x, cs.y, -cs.y, cs.x);
}

/// Linear remap of x from [a,b] to [c,d] (unclamped).
/// @use converting ranges, rescaling noise
float remap(float x, float a, float b, float c, float d) {
    return c + (d - c) * (x - a) / (b - a);
}

/// Linear ramp from 0 at a to 1 at b, clamped.
/// @use masks whose falloff should not ease in or out
float linearstep(float a, float b, float x) {
    return clamp((x - a) / (b - a), 0.0, 1.0);
}

/// Smooth bump: 1 at x == c, falling to 0 at |x - c| >= w (cubic).
/// @use stripes, rings, highlights at one height, pulses in time
float cubicPulse(float c, float w, float x) {
    x = abs(x - c);
    if (x > w) return 0.0;
    x /= w;
    return 1.0 - x * x * (3.0 - 2.0 * x);
}

/// Fast attack, exponential decay. Peaks at 1 when x == 1/k.
/// @use heartbeat motion, impacts, flashes, plucked-string envelopes
float expImpulse(float x, float k) {
    float h = k * x;
    return h * exp(1.0 - h);
}

/// Contrast curve on [0,1] that keeps 0, 0.5 and 1 fixed. k > 1 adds contrast, k < 1 flattens.
/// @use tightening masks, adjusting animation easing
float gain(float x, float k) {
    float a = 0.5 * pow(2.0 * ((x < 0.5) ? x : 1.0 - x), k);
    return (x < 0.5) ? a : 1.0 - a;
}

/// 0 at x = 0 and x = 1, peak 1 at x = 0.5; k sharpens.
/// @use petal width along length, leaf profiles, arches
float parabola(float x, float k) {
    return pow(4.0 * x * (1.0 - x), k);
}

/// Returns x when x > m; smoothly bottoms out at n when x -> 0. Needs 2n < m.
/// @use avoiding hard zero in falloffs, soft floor on thickness
float almostIdentity(float x, float m, float n) {
    if (x > m) return x;
    float a = 2.0 * n - m;
    float b = 2.0 * m - 3.0 * n;
    float t = x / m;
    return (a * t + b) * t * t + n;
}

/// Floor-based modulo. Unlike fmod, negative coordinates wrap into a positive period.
/// @use repeating cells, polar sectors, negative lattice coordinates
float floorMod(float x, float y) { return x - y * floor(x / y); }
float2 floorMod(float2 x, float2 y) { return x - y * floor(x / y); }
float2 floorMod(float2 x, float y) { return x - y * floor(x / y); }
float3 floorMod(float3 x, float3 y) { return x - y * floor(x / y); }
float3 floorMod(float3 x, float y) { return x - y * floor(x / y); }
