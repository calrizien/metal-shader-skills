// Procedural material swatches: six texture-free patterns on one board.
// Shows: two-level domain warping (marble), exact Voronoi borders (cracked earth), hex tiles with bevels,
// Truchet weaves, smooth Voronoi (organic cells) and a box-filtered checker. Each tile uses explicit pixel-size
// filtering instead of fwidth, so it stays valid inside branches.
// @render time=2.0

#define DEBUG_MODE 0   // 0 final | 3 tile ids

float3 marble(float2 p) {
    float2 q, r;
    float f = warpedFbm(p * 1.5, 3.0, 5, q, r);
    float3 col = mixOklab(srgbToLinear(float3(0.92, 0.90, 0.86)), srgbToLinear(float3(0.35, 0.38, 0.45)), saturate(length(q) * 0.9));
    col = mix(col, srgbToLinear(float3(0.62, 0.42, 0.30)), saturate(r.y * r.y * 2.0));
    return col * (0.85 + 0.25 * f);
}

float3 crackedEarth(float2 p, float px) {
    float3 v = voronoiBorder(p * 4.0, 0.9);
    float2 cell = floor(p * 4.0 + v.yz);
    float tint = hash12(cell);
    float3 col = mix(srgbToLinear(float3(0.62, 0.44, 0.30)), srgbToLinear(float3(0.75, 0.58, 0.40)), tint);
    col *= 0.75 + 0.25 * smoothstep(0.0, 0.25, v.x);          // plates darken toward their curled edges
    float plate = fillAA(0.03 - v.x, px * 4.0);                 // cracks: border distance < 0.03 cell units
    return mix(srgbToLinear(float3(0.12, 0.08, 0.06)), col, plate);
}

float3 hexTiles(float2 p, float px) {
    float4 h = hexGrid(p * 5.0);
    float edge = hexEdgeDistance(h.xy);
    float3 base = oklchToLinearSrgb(float3(0.7, 0.09, 3.6 + 0.8 * hash12(h.zw)));
    float bevel = smoothstep(0.0, 0.12, edge);
    return mix(float3(0.02), base * (0.7 + 0.3 * bevel), smoothstep(0.03 - px * 5.0, 0.03 + px * 5.0, edge));
}

float3 truchet(float2 p, float px) {
    float d = truchetArcs(p * 5.0, 0.12) / 5.0;
    float stripe = truchetArcs(p * 5.0, 0.03) / 5.0;
    float3 col = srgbToLinear(float3(0.08, 0.10, 0.16));
    col = mix(col, srgbToLinear(float3(0.95, 0.75, 0.30)), fillAA(d, px));
    return mix(col, srgbToLinear(float3(0.55, 0.20, 0.10)), fillAA(stripe, px));
}

float3 organicCells(float2 p) {
    float s = smoothVoronoi(p * 5.0, 12.0);
    float3 col = mixOklab(srgbToLinear(float3(0.95, 0.55, 0.55)), srgbToLinear(float3(0.35, 0.05, 0.15)), saturate(s * 1.6));
    return col * (0.6 + 0.4 * smoothstep(0.1, 0.5, s));
}

float3 checker(float2 p, float px) {
    // perspective floor: the filtered checker stays grey instead of moire in the distance
    float z = 1.0 / max(0.55 - p.y, 0.02);
    float2 floorUV = float2(p.x * z, z) * 1.5;
    float c = filteredChecker(floorUV, float2(px * z * z * 1.5 + px * z * 1.5));
    return mix(float3(0.05), float3(0.8), c) * smoothstep(0.55, 0.3, p.y);
}

void shade(thread float4 &fragColor, float2 fragCoord) {
    float2 uv = fragCoord / resolution.y;
    float px = 1.0 / resolution.y;
    float aspect = resolution.x / resolution.y;
    float2 grid = float2(3.0, 2.0);
    float2 tileSize = float2(aspect, 1.0) / grid;
    float2 id = floor(uv / tileSize);
    float2 local = (uv - id * tileSize) / tileSize.y;        // 0..(tile aspect) x 0..1
    float2 p = local - 0.5 * float2(tileSize.x / tileSize.y, 1.0);
    float k = id.x + 3.0 * (1.0 - id.y);
    float lpx = px / tileSize.y;

    float3 col;
    if (k < 0.5) col = marble(p + 0.05 * time);
    else if (k < 1.5) col = crackedEarth(p, lpx);
    else if (k < 2.5) col = hexTiles(p, lpx);
    else if (k < 3.5) col = truchet(p, lpx);
    else if (k < 4.5) col = organicCells(p + float2(0.0, 0.03 * time));
    else col = checker(p, lpx);

    // tile frame
    float2 e = min(local, float2(tileSize.x / tileSize.y, 1.0) - local);
    col *= smoothstep(0.0, 0.02, min(e.x, e.y));

#if DEBUG_MODE == 3
    col = debugIdColor(k);
#endif
    fragColor = float4(linearToSrgb(col) + ditherTPDF(fragCoord, frame), 1.0);
}
