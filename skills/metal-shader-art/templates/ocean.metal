// Open ocean at golden hour under a physically based sky.
// Shows: a sum of dispersive exp-sine waves with analytic slope and curvature (normals and foam with no extra samples),
// a heightfield tracer clipped to the wave slab, distance filtering that hands the slope of vanished waves to GGX
// roughness (the glitter path widens with distance), simplex flow-noise ripples, Fresnel sky reflection, a sun glint,
// light glowing through thin crests, curvature foam broken up by billow noise, aerial perspective, AgX.
// Units are meters; the atmosphere functions take kilometers.
// @render time=12.5

#define DEBUG_MODE 0   // 0 final | 1 height | 2 normals | 3 foam mask | 4 trace steps | 5 fresnel | 6 light terms

// ---- art controls ----
const float3  SUN_DIR = normalize(float3(0.2, 0.14, -1.0));    // low sun ahead of the camera, a little to the right
const float SUN_INTENSITY = 20.0;
const float WIND_ANGLE = 1.9;          // direction the waves travel, radians from +X toward +Z (camera looks down -Z)
const float SWELL_LENGTH = 34.0;       // longest wavelength, meters
const float SWELL_HEIGHT = 0.8;        // amplitude of the longest wave, meters
const float CHOP = 0.7;                // amplitude ratio between successive waves: higher = choppier
const float CREST_SHARPNESS = 2.4;     // 1 rolling swell .. 3 peaky crests
const float RIPPLE = 0.008;            // capillary ripple amplitude, meters
const float FOAM_AMOUNT = 1.0;
const float3  WATER_DEEP = float3(0.004, 0.02, 0.04);      // linear albedo of the deep body
const float3  WATER_GLOW = float3(0.05, 0.26, 0.25);       // color of sunlight scattered through thin crests
const float HAZE = 6.0;                // aerial perspective strength (multiplies sea-level air extinction)
const float CAMERA_HEIGHT = 3.0;       // meters above mean sea level
const float EXPOSURE = 0.9;
const float FOCAL = 2.0;

const float GRAVITY = 9.81;
const float WAVELENGTH_RATIO = 0.8;    // wavelength ratio between successive waves
const int   TRACE_WAVES = 12;          // waves in the traced surface
const int   SHADE_WAVES = 28;          // waves in the shading normal (adds fine chop)
const int   FOAM_WAVES = 6;            // waves whose crests make foam
const float TRACE_FAR = 400.0;         // beyond this, intersect the mean plane and rely on filtering

// Wave i of the sum: unit direction, wavenumber, amplitude and phase. Wavelengths fall geometrically from the swell;
// long waves run with the wind, short chop spreads wider around it.
void wave(int i, thread float2 &dir, thread float &k, thread float &amp, thread float &phase) {
    float fi = float(i);
    float3 h = hash32(float2(fi, 17.0));
    float a = WIND_ANGLE + mix(0.35, 1.3, min(fi / 12.0, 1.0)) * (2.0 * h.x - 1.0);
    dir = float2(cos(a), sin(a));
    k = TAU / (SWELL_LENGTH * pow(WAVELENGTH_RATIO, fi) * mix(0.85, 1.15, h.y));
    amp = SWELL_HEIGHT * pow(CHOP, fi);
    phase = TAU * h.z;
}

// Deep-water dispersion: a wave of wavenumber k moves at angular frequency sqrt(g k), so long swell outruns chop.
float wavePhase(float2 dir, float k, float phase, float2 xz) {
    return k * dot(dir, xz) - sqrt(GRAVITY * k) * time + phase;
}

// How much of a wave survives filtering: 1 while its wavelength spans 6+ pixel footprints, 0 below 2.
// A pixel covers an ellipse on the water: fp.zw = its size across and along the view, fp.xy = the unit view
// direction projected on the water. At grazing angles it is far longer along the view, which is where waves alias.
float waveKeep(float2 dir, float k, float4 fp) {
    float footprint = length(float2(dot(dir, float2(-fp.y, fp.x)) * fp.z, dot(dir, fp.xy) * fp.w));
    return smoothstep(2.0, 6.0, TAU / (k * footprint));
}

// Exp-sine profile: sharp crests, broad troughs. exp(s (sin - 1)) - 0.3 keeps the mean level near 0.
// Waves too small for the footprint are faded out, so distant geometry does not alias into streaks.
float oceanHeight(float2 xz, int count, float4 fp) {
    float h = 0.0;
    for (int i = 0; i < SHADE_WAVES; i++) {
        if (i >= count) break;
        float2 dir; float k, amp, phase;
        wave(i, dir, k, amp, phase);
        h += waveKeep(dir, k, fp) * amp * (exp(CREST_SHARPNESS * (sin(wavePhase(dir, k, phase, xz)) - 1.0)) - 0.3);
    }
    return h;
}

// Steepest slope one wave of amplitude a and wavenumber k can reach: a k max|s cos(t) e^(s (sin(t) - 1))|.
float profileMaxSlope() {
    float s = CREST_SHARPNESS;
    float sn = (sqrt(1.0 + 4.0 * s * s) - 1.0) / (2.0 * s);
    return s * sqrt(1.0 - sn * sn) * exp(s * (sn - 1.0));
}

// Bounds of the traced surface: float3(lowest height, highest height, steepest slope).
float3 oceanBounds() {
    float ampSum = 0.0, slopeSum = 0.0;
    for (int i = 0; i < TRACE_WAVES; i++) {
        float2 dir; float k, amp, phase;
        wave(i, dir, k, amp, phase);
        ampSum += amp;
        slopeSum += amp * k;
    }
    return float3(-0.3 * ampSum, 0.7 * ampSum, slopeSum * profileMaxSlope());
}

// Ray vs the traced wave surface. The surface lies inside the slab bounds.x <= y <= bounds.y, so clip the ray to it,
// then step by the height gap over the fastest rate the gap can close (the ray's descent plus the steepest slope times
// its horizontal speed). The slope bound is relaxed by 0.6 for speed; a secant step refines the crossing.
// Returns float2(t, steps); t < 0 when the ray reaches TRACE_FAR first.
float2 traceOcean(float3 ro, float3 rd, float3 bounds, float4 pixelSpread) {
    if (rd.y >= 0.0) return float2(-1.0, 0.0);
    float t = max((ro.y - bounds.y) / -rd.y, 0.0);
    float tEnd = min((ro.y - bounds.x) / -rd.y, TRACE_FAR);
    float closing = -rd.y + 0.6 * bounds.z * length(rd.xz);
    float tPrev = t, gapPrev = 1e10;
    for (int i = 0; i < 200; i++) {
        float3 p = ro + rd * t;
        float gap = p.y - oceanHeight(p.xz, TRACE_WAVES, pixelSpread * float4(1.0, 1.0, t, t));
        if (gap < 0.0) return float2(mix(tPrev, t, gapPrev / (gapPrev - gap)), float(i));
        if (t >= tEnd) break;
        tPrev = t;
        gapPrev = gap;
        t = min(t + max(gap / closing, 0.004 * t), tEnd);
    }
    return float2(-1.0, 200.0);
}

// Shading detail at xz: height, slope and Laplacian of all SHADE_WAVES, each wave faded out as its wavelength nears
// the pixel footprint. Returns float4(height, dh/dx, dh/dz, laplacian). lostSlope2 collects the slope variance of the
// faded waves (it becomes roughness); crest is the convexity of the big waves, 1 where all their crests meet (foam).
float4 oceanDetail(float2 xz, float4 fp, thread float &lostSlope2, thread float &crest) {
    const float slopeRms = 0.3 + 0.06 * CREST_SHARPNESS;   // RMS of the profile's slope per unit a k
    float4 s = float4(0.0);
    lostSlope2 = 0.0;
    crest = 0.0;
    float crestMax = 0.0;
    for (int i = 0; i < SHADE_WAVES; i++) {
        float2 dir; float k, amp, phase;
        wave(i, dir, k, amp, phase);
        float keep = waveKeep(dir, k, fp);
        float theta = wavePhase(dir, k, phase, xz);
        float sn = sin(theta), cs = cos(theta);
        float e = exp(CREST_SHARPNESS * (sn - 1.0));
        float d1 = CREST_SHARPNESS * cs * e;                                      // dW/dtheta
        float d2 = CREST_SHARPNESS * (CREST_SHARPNESS * cs * cs - sn) * e;        // d2W/dtheta2
        s += keep * amp * float4(e - 0.3, k * d1 * dir, k * k * d2);
        lostSlope2 += (1.0 - keep) * (amp * k * slopeRms) * (amp * k * slopeRms);
        if (i < FOAM_WAVES) {
            crest -= keep * amp * k * k * d2;
            crestMax += amp * k * k * CREST_SHARPNESS;   // a crest's curvature: -W'' = s at the top
        }
    }
    crest /= crestMax;
    return s;
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
    float pixelAngle = 2.0 / (resolution.y * FOCAL);
    float viewKm = CAMERA_HEIGHT * 0.001;

#if DEBUG_MODE == 1
    return float3(0.5 + 0.5 * oceanHeight(uv * 30.0, SHADE_WAVES, float4(1.0, 0.0, 1e-4, 1e-4)) / SWELL_HEIGHT);
#endif

    float3 ro = float3(0.0, CAMERA_HEIGHT, 0.0);
    float3x3 cam = cameraMatrix(ro, ro + float3(0.0, -0.06, -1.0), 0.0);
    float3 rd = cameraRay(cam, uv, FOCAL);

    float3 sunColor = SUN_INTENSITY * 0.12 * sunTransmittance(viewKm, SUN_DIR);
    if (rd.y >= 0.0) {
        float3 sky = atmosphereSky(rd, SUN_DIR, viewKm, SUN_INTENSITY);
        return sky + sunColor * 40.0 * sunDisk(rd, SUN_DIR, 0.012, pixelAngle);
    }

    // pixel footprint on the water per meter of distance: pixelAngle across the view, stretched by 1/sin(grazing
    // angle) along it
    float4 pixelSpread = float4(normalize(rd.xz), pixelAngle, pixelAngle / max(-rd.y, 0.01));
    float3 bounds = oceanBounds();
    float2 hit = traceOcean(ro, rd, bounds, pixelSpread);
#if DEBUG_MODE == 4
    return debugHeat(hit.y / 200.0);
#endif
    // past TRACE_FAR the waves are below pixel size anyway: use the mean plane and let filtering do the rest
    float t = (hit.x > 0.0) ? hit.x : ro.y / -rd.y;
    float3 p = ro + rd * t;

    float4 fp = pixelSpread * float4(1.0, 1.0, t, t);
    float lostSlope2, crest;
    float4 wv = oceanDetail(p.xz, fp, lostSlope2, crest);
    float2 slope = wv.yz;

    // capillary ripples: two octaves of simplex flow noise whose gradients spin, so they churn instead of sliding
    float footprint = sqrt(fp.z * fp.w);   // ripples are isotropic: use the ellipse's mean size
    float keepRipple = smoothstep(2.0, 6.0, 0.8 / footprint);
    float3 r1 = simplexNoiseD(p.xz * 1.3 + float2(0.3, 0.9) * time, 1.3 * time);
    float3 r2 = simplexNoiseD(p.xz * 3.7 - float2(0.6, 0.2) * time, -2.1 * time);
    slope += RIPPLE * keepRipple * (1.3 * r1.yz + 0.5 * 3.7 * r2.yz * smoothstep(2.0, 6.0, 0.3 / footprint));
    lostSlope2 += RIPPLE * RIPPLE * 4.0 * (1.0 - keepRipple);
    float3 n = normalize(float3(-slope.x, 1.0, -slope.y));

    // foam: the convexity of the big waves' crests sets how much of a billow-noise lace is covered, so patches
    // grow from crisp filaments on mild crests to solid caps on the sharpest ones
    float lace = billowFbm(p.xz * float2(1.2, 2.4) + float2(0.0, 0.5 * time), 6);
    float coverage = 0.7 * smoothstep(0.08, 0.3, crest);   // below 1, so even the sharpest caps stay broken
    float foam = FOAM_AMOUNT * coverage * smoothstep(1.0 - coverage, 1.15 - coverage, lace);
    // inside a patch, foam is a network of bubbles: dense along Voronoi borders, thin inside the cells
    float bubbles = smoothstep(0.22, 0.0, voronoiBorder(p.xz * float2(2.5, 4.0), 1.0).x);
    foam *= mix(0.75, mix(0.4, 1.0, bubbles), smoothstep(2.0, 6.0, 0.3 / footprint));

    float3 v = -rd;
    float NoV = max(dot(n, v), 1e-3);
    float3 F = fresnelSchlick(NoV, float3(0.02));
    float3 refl = reflect(rd, n);
    refl.y = abs(refl.y);   // a reflection into the water would hit the next wave: fold it back to the sky
    float3 skyRefl = atmosphereSky(refl, SUN_DIR, viewKm, SUN_INTENSITY);
    float3 skyAmbient = atmosphereSky(float3(0.0, 1.0, 0.0), SUN_DIR, viewKm, SUN_INTENSITY);

    // sun glint: GGX whose roughness absorbs the slope variance of the waves filtered away at this distance
    float alpha = sqrt(0.02 * 0.02 + 2.0 * lostSlope2);
    float3 glint = specularGGX(n, v, SUN_DIR, sqrt(alpha), float3(0.02)) * sunColor;
    float3 reflection = F * skyRefl;

    // body: refracted light scattered back out, plus sunlight glowing through thin crests seen against the sun
    float backlit = pow(clamp(dot(rd, SUN_DIR), 0.0, 1.0), 4.0);
    float thin = smoothstep(0.45, 0.9, (wv.x - bounds.x) / (bounds.y - bounds.x));   // crest tops only
    float3 body = (1.0 - F) * (WATER_DEEP * (skyAmbient + sunColor * max(dot(n, SUN_DIR), 0.0))
                             + WATER_GLOW * sunColor * backlit * thin);

    // foam is a thin white scatterer: diffuse sun and sky light, plus sunlight shining through it from behind
    float3 foamColor = float3(0.9) * (sunColor * (max(dot(n, SUN_DIR), 0.0) + 0.5 * backlit) + 3.0 * skyAmbient);

#if DEBUG_MODE == 2
    return debugNormal(n);
#elif DEBUG_MODE == 3
    return float3(foam, clamp(crest, 0.0, 1.0), lace);
#elif DEBUG_MODE == 5
    return sqrt(F);
#elif DEBUG_MODE == 6
    return float3(luminance(reflection), luminance(glint) * 0.1, luminance(body) * 10.0);
#endif

    float3 col = mix(reflection + glint + body, foamColor, foam);
    // aerial perspective, with the haze color taken from the sky just above the horizon so the two meet without a seam
    float3 fogColor = atmosphereSky(normalize(float3(rd.x, 0.0, rd.z)), SUN_DIR, viewKm, SUN_INTENSITY);
    float3 airT = exp(-t * 0.001 * HAZE * atmosphereExtinction(atmosphereDensity(0.0)));
    return col * airT + fogColor * (1.0 - airT);
}

void shade(thread float4 &fragColor, float2 fragCoord) {
    float3 col = render(fragCoord);
#if DEBUG_MODE == 0
    col = linearToSrgb(tonemapAgXPunchy(col * EXPOSURE)) + ditherTPDF(fragCoord, frame);
#endif
    fragColor = float4(col, 1.0);
}
