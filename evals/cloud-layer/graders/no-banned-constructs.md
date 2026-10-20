---
type: regex
target:
  source: file
  path: final.metal
pattern: '(?:^|\n)(?:(?!//)[^\n])*?(?:\bgl_FragColor\b|\bvec[234]\b|\btexture2D\s*\(|\bmainImage\b|\bfract\s*\(\s*sin\s*\()|(?:^|\n)[ \t]*#[ \t]*version\b'
match: not_contains
---
