//! hash: integer hashes and float wrappers for lattice ids.
//! Naming: hashNM returns N floats from M inputs (hash12 = 1 output, 2 inputs). Outputs are in [0,1).
//! The float wrappers hash INTEGER-VALUED inputs (cell ids, pixel coords, frame numbers). Fractional parts
//! are dropped. That is deliberate: conversion through a signed integer preserves negative lattice IDs, and -0.0
//! has different bits from 0.0. Integer conversion also canonicalizes zero. To hash a continuous value, scale it first.
//! Do not use fract(sin(dot(p, k)) * 43758.5453): its result changes across GPUs and degrades at large inputs.
//! Integer mixers are from Jarzynski and Olano, "Hash Functions for GPU Rendering" (JCGT 2020): pcg3d and pcg4d sit
//! on that study's quality/speed frontier, and 32-bit integer math is bit-exact on every GPU, unlike sin().

/// PCG-style 1D integer hash.
/// @use seeding, per-instance randomness, building other hashes
/// @see https://jcgt.org/published/0009/03/02/
uint pcgHash(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

/// 3D integer hash, three decorrelated outputs.
/// @use 3D cell ids, voxel jitter, (pixel, frame) noise
/// @see https://jcgt.org/published/0009/03/02/
uint3 pcg3d(uint3 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.z;
    v.y += v.z * v.x;
    v.z += v.x * v.y;
    v ^= v >> 16u;
    v.x += v.y * v.z;
    v.y += v.z * v.x;
    v.z += v.x * v.y;
    return v;
}

/// 4D integer hash, four decorrelated outputs (0 BigCrush failures in the JCGT study).
/// @use (pixel.x, pixel.y, frame, sample) streams for stochastic sampling, 4D cell ids
/// @see https://jcgt.org/published/0009/03/02/
uint4 pcg4d(uint4 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.w;
    v.y += v.z * v.x;
    v.z += v.x * v.y;
    v.w += v.y * v.z;
    v ^= v >> 16u;
    v.x += v.y * v.w;
    v.y += v.z * v.x;
    v.z += v.x * v.y;
    v.w += v.y * v.z;
    return v;
}

/// Map a uint to [0,1) using the top 24 bits, so the result can never round up to 1.0.
float uintToUnit(uint h) { return float(h >> 8u) * (1.0 / 16777216.0); }
float2 uintToUnit(uint2 h) { return float2(h >> 8u) * (1.0 / 16777216.0); }
float3 uintToUnit(uint3 h) { return float3(h >> 8u) * (1.0 / 16777216.0); }
float4 uintToUnit(uint4 h) { return float4(h >> 8u) * (1.0 / 16777216.0); }

/// Random float in [0,1) for an integer-valued input.
/// @use per-cell randomness, stable random per instance id
/// @range [0,1)
float hash11(float p) { return uintToUnit(pcgHash(uint(int(floor(p))))); }

/// Random float in [0,1) for an integer-valued 2D input.
/// @use per-cell variation (color, height, rotation), sparse spots, star fields
/// @range [0,1)
float hash12(float2 p) {
    uint2 q = uint2(int2(floor(p)));
    return uintToUnit(pcgHash(q.x + pcgHash(q.y)));
}

/// Random float in [0,1) for an integer-valued 3D input.
/// @use per-voxel randomness, per-pixel-per-frame noise via hash13(float3(fragCoord, frame))
/// @range [0,1)
float hash13(float3 p) {
    uint3 q = uint3(int3(floor(p)));
    return uintToUnit(pcgHash(q.x + pcgHash(q.y + pcgHash(q.z))));
}

/// Random float2 in [0,1)^2 for an integer-valued 2D input.
/// @use Voronoi feature points, 2D jitter, random gradients
/// @range [0,1)^2
float2 hash22(float2 p) {
    int2 q = int2(floor(p));
    return uintToUnit(pcg3d(uint3(q.x, q.y, 0x2545u))).xy;
}

/// Random float3 in [0,1)^3 for an integer-valued 3D input.
/// @use 3D Voronoi points, random colors per cell, random directions
/// @range [0,1)^3
float3 hash33(float3 p) { return uintToUnit(pcg3d(uint3(int3(floor(p))))); }

/// Random float4 in [0,1)^4 for an integer-valued 4D input.
/// @use per-pixel, per-frame, per-sample random numbers: hash44(float4(fragCoord, frame, sampleIndex))
/// @range [0,1)^4
float4 hash44(float4 p) { return uintToUnit(pcg4d(uint4(int4(floor(p))))); }

/// Random float3 in [0,1)^3 for an integer-valued 2D input.
/// @use per-tile random color, per-cell (offset, rotation, scale) triples
/// @range [0,1)^3
float3 hash32(float2 p) {
    int2 q = int2(floor(p));
    return uintToUnit(pcg3d(uint3(q.x, q.y, 0x9E37u)));
}
