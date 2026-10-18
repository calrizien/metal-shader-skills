---
type: regex
target:
  source: file
  path: Blur.compute
pattern: '\bmainImage\b|\bvec[234]\s*\(|\bgl_GlobalInvocationID\b|\bimageStore\s*\('
match: not_contains
---
