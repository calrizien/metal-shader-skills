//! camera: look-at frames, primary rays, field of view, thin-lens depth of field.
//! Convention: uv = (2.0 * fragCoord - resolution.xy) / resolution.y, so uv.y spans [-1, 1] and aspect is kept.

/// Camera-to-world matrix looking from ro toward ta, with roll in radians. Columns are (right, up, forward).
/// @use every 3D shader
float3x3 cameraMatrix(float3 ro, float3 ta, float roll) {
    float3 w = normalize(ta - ro);
    float3 up = float3(sin(roll), cos(roll), 0.0);
    float3 u = normalize(cross(w, up));
    float3 v = cross(u, w);
    return float3x3(u, v, w);
}

/// Focal length (the z of the view-space ray) for a vertical field of view in degrees.
/// @use matching a reference photo, wide (90) vs telephoto (20) framing
float fovToFocal(float fovDegrees) { return 1.0 / tan(fovDegrees * (PI / 180.0) * 0.5); }

/// Primary ray direction for screen point uv. focal is about 1.5-2.5 for natural framing (see fovToFocal).
/// @use every 3D shader
float3 cameraRay(float3x3 cam, float2 uv, float focal) {
    return normalize(cam * float3(uv, focal));
}

/// Thin-lens depth of field. Moves the ray origin over a lens disk of radius aperture, and re-aims it so that
/// points at distance focusDist stay sharp. xi is a pair of uniform random numbers in [0,1) (e.g. hash22 of the
/// pixel and frame). Average many samples (AA loop or multipass accumulation).
/// @use macro shots, product renders, cinematic focus pulls, bokeh
void thinLensRay(float3x3 cam, float2 uv, float focal, float aperture, float focusDist, float2 xi,
                 thread float3 &ro, thread float3 &rd) {
    float3 dir = normalize(cam * float3(uv, focal));
    float ft = focusDist / dot(dir, cam[2]);
    float3 focusPoint = ro + dir * ft;
    float a = TAU * xi.x;
    float r = aperture * sqrt(xi.y);
    ro += cam * float3(r * cos(a), r * sin(a), 0.0);
    rd = normalize(focusPoint - ro);
}

/// Orthographic ray: parallel rays from a plane of half-height `size` centered on ro.
/// @use isometric scenes, technical illustrations, flat diorama looks
void orthoRay(float3x3 cam, float2 uv, float size, thread float3 &ro, thread float3 &rd) {
    ro += cam * float3(uv * size, 0.0);
    rd = cam[2];
}
