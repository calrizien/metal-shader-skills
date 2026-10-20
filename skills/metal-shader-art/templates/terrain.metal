// Eroded mountains at golden hour under a physically based sky.
// Shows: derivative-damped fBm terrain, heightfield marching as a scaled bound, slope/altitude material masks,
// soft terrain shadows, single-scattering atmosphere (Rayleigh/Mie/ozone), aerial perspective, sun disk, AgX.
// Units are kilometers so the atmosphere constants apply directly.
// @render time=0.0

#define DEBUG_MODE 0   // 0 final | 1 height map | 2 normals | 3 material masks | 4 steps | 5 shadow | 6 light terms

// ---- art controls ----
const float3  SUN_DIR = normalize(float3(0.85, 0.2, -0.45));
const float SUN_INTENSITY = 20.0;
const float TERRAIN_SCALE = 0.32;    // horizontal frequency: smaller = broader mountains
const float TERRAIN_HEIGHT = 2.0;    // vertical scale in km
const float SNOW_LINE = 1.05;        // km
const float EXPOSURE = 1.4;
const float FOCAL = 1.8;

float terrainHeight(float2 xz) { return TERRAIN_HEIGHT * erodedFbm(xz * TERRAIN_SCALE, 9); }

float2 map(float3 p) {
    // p.y - h(xz) is not a distance on slopes. Scaling by 0.45 keeps the march safe for slopes up to about 63 degrees.
    return float2(0.45 * (p.y - terrainHeight(p.xz)), 1.0);
}

// Transmittance from a point at heightKm toward dir, through the atmosphere (colors the sunlight).
float3 sunTransmittance(float heightKm, float3 dir) {
    float3 ro = float3(0.0, ATMOSPHERE_GROUND_KM + heightKm, 0.0);
    if (iSphere(ro, dir, float3(0.0), ATMOSPHERE_GROUND_KM).x > 0.0) return float3(0.0);
    float tl = iSphere(ro, dir, float3(0.0), ATMOSPHERE_TOP_KM).y;
    float3 depth = float3(0.0);
    for (int i = 0; i < 12; i++) {
        float3 q = ro + dir * ((float(i) + 0.5) * tl / 12.0);
        depth += atmosphereExtinction(atmosphereDensity(length(q) - ATMOSPHERE_GROUND_KM)) * tl / 12.0;
    }
    return exp(-depth);
}

float3 render(float2 fragCoord) {
    float2 uv = (2.0 * fragCoord - resolution.xy) / resolution.y;

#if DEBUG_MODE == 1
    return float3(terrainHeight(uv * 8.0) / TERRAIN_HEIGHT * 0.5 + 0.3);
#endif

    float3 ro = float3(-3.0 + 0.2 * time, 0.0, 4.0 - 0.6 * time);
    ro.y = terrainHeight(ro.xz) + 0.9;
    float3 ta = ro + float3(0.25, -0.16, -1.0);
    float3x3 cam = cameraMatrix(ro, ta, 0.0);
    float3 rd = cameraRay(cam, uv, FOCAL);

    float3 sky = atmosphereSky(rd, SUN_DIR, ro.y, SUN_INTENSITY);
    float3 sunColor = SUN_INTENSITY * 0.12 * sunTransmittance(ro.y, SUN_DIR);
    float3 hit = raymarch(ro, rd, 0.01, 40.0, 1.0);
#if DEBUG_MODE == 4
    return debugHeat(hit.z / float(RAYMARCH_MAX_STEPS));
#endif
    if (hit.x < 0.0) {
        return sky + sunColor * 40.0 * sunDisk(rd, SUN_DIR, 0.012, 2.0 / (resolution.y * FOCAL));
    }

    float t = hit.x;
    float3 p = ro + rd * t;
    float3 n = calcNormal(p, 0.001 * t);

    // material masks: rock on steep slopes, grass on flats, snow on high upward-facing ground
    float flatness = smoothstep(0.72, 0.88, n.y);
    float snow = smoothstep(SNOW_LINE - 0.15, SNOW_LINE + 0.1, p.y + 0.25 * fbm(p.xz * 6.0, 3))
               * smoothstep(0.55, 0.8, n.y);
    float grain = 0.5 + 0.5 * fbm(p.xz * 40.0, 4);
    float3 rock = mix(float3(0.10, 0.085, 0.07), float3(0.20, 0.17, 0.14), grain);
    float3 grass = mix(float3(0.06, 0.08, 0.03), float3(0.11, 0.12, 0.05), grain);
    float3 albedo = mix(rock, grass, flatness * (1.0 - smoothstep(0.6, 1.0, p.y)));
    albedo = mix(albedo, float3(0.85, 0.88, 0.92), snow);

    float sha = softShadow(p + n * 0.01, SUN_DIR, 0.02, 20.0, 16.0);
    float NoL = clamp(dot(n, SUN_DIR), 0.0, 1.0);
    float3 skyAmbient = atmosphereSky(float3(0.0, 1.0, 0.0), SUN_DIR, p.y, SUN_INTENSITY);
    float3 key = albedo * sunColor * NoL * sha;
    float3 fill = albedo * skyAmbient * (0.5 + 0.5 * n.y) * 2.0;
    float3 bounce = albedo * sunColor * 0.08 * clamp(dot(n, normalize(float3(-SUN_DIR.x, 0.0, -SUN_DIR.z))), 0.0, 1.0);

#if DEBUG_MODE == 2
    return debugNormal(n);
#elif DEBUG_MODE == 3
    return float3(1.0 - flatness, flatness, snow);
#elif DEBUG_MODE == 5
    return float3(sha);
#elif DEBUG_MODE == 6
    return float3(luminance(key), luminance(fill), luminance(bounce)) * 2.0;
#endif

    float3 col = key + fill + bounce;
    // aerial perspective: attenuate by the air between camera and hit and fill with sky color. Use the sky at the
    // horizon-clamped direction: below the planet's horizon the sky integral jumps, which would print a seam.
    float3 fogColor = atmosphereSky(normalize(float3(rd.x, max(rd.y, 0.02), rd.z)), SUN_DIR, ro.y, SUN_INTENSITY);
    float3 airT = exp(-t * atmosphereExtinction(atmosphereDensity(0.5 * (ro.y + p.y))) * 4.0);
    return col * airT + fogColor * (1.0 - airT);
}

void shade(thread float4 &fragColor, float2 fragCoord) {
    float3 col = render(fragCoord);
#if DEBUG_MODE == 0
    col = linearToSrgb(tonemapAgX(col * EXPOSURE)) + ditherTPDF(fragCoord, frame);
#endif
    fragColor = float4(col, 1.0);
}
