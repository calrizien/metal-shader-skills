// Ten noise studies, matching the learning progression in references/noise-use-cases.md.
// Top row, left to right: Perlin-style gradient, Voronoi borders, simplex, fBm, domain warp.
// Bottom row: smooth value, Worley F1/F2, ridged, billow, hybrid terrain height.
// Base noise and layered noise deliberately look different: a single octave is not a cloud texture.
// @render time=2.0
#define DEBUG_MODE 0 // 0 grayscale | 3 tile IDs | 5 unclipped scalar false color
const float SCALE = 5.0;
const int OCTAVES = 5;

float noiseStudy(int id, float2 p, float px) {
    if (id == 0) return 0.5 + 0.7 * gradientNoise(p);
    if (id == 1) return 1.0 - smoothstep(0.0, 0.13 + px, voronoiBorder(p, 0.85).x);
    if (id == 2) return 0.5 + 0.5 * simplexNoise(p);
    if (id == 3) return 0.5 + 0.5 * fbm(p, OCTAVES);
    if (id == 4) {
        float2 q, r;
        float f = warpedFbm(p * 0.6, 1.5, 3, q, r);
        return 0.5 + 0.5 * sin(p.x * 2.0 + 6.0 * f);
    }
    if (id == 5) return valueNoise(p);
    if (id == 6) {
        float4 cell = voronoi(p, 0.85);
        return saturate(1.8 * (cell.y - cell.x));
    }
    if (id == 7) return ridgedFbm(p, OCTAVES);
    if (id == 8) return billowFbm(p, OCTAVES);
    return hybridTerrainHeight(p, OCTAVES);
}

void shade(thread float4 &fragColor, float2 fragCoord) {
    float2 board = fragCoord / resolution.xy * float2(5.0, 2.0);
    int2 tile = int2(floor(board));
    int id = tile.x + (1 - tile.y) * 5;
    float2 local = fract(board);
    float2 p = local * SCALE + float2(1.23, 4.56);
    float px = SCALE * 5.0 / resolution.x;
    float f = noiseStudy(id, p, px);
    float3 col = float3(saturate(f)); // grayscale values are already display values
#if DEBUG_MODE == 3
    col = cosinePalette(float(id) / 10.0, float3(0.5), float3(0.4), float3(1.0), float3(0.0,0.3,0.6));
#elif DEBUG_MODE == 5
    col = float3(max(f,0.0), max(-f,0.0), max(f-1.0,0.0));
#endif
    float2 edge = min(local,1.0-local);
    float frame = smoothstep(0.01,0.025,min(edge.x,edge.y));
    col = mix(float3(0.035), col, frame);
    // The small white ticks identify columns 1–5 without font/texture dependencies.
    float tick = step(0.965,local.y) * step(0.1,local.x) * step(local.x,0.1+0.03*float(tile.x+1));
    col = mix(col,float3(0.9),tick);
    fragColor = float4(col + ditherTPDF(fragCoord,frame),1.0);
}
