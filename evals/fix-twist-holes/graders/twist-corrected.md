---
type: llm
focus:
  source: file
  path: final.metal
---

The file is a Metal 4 shader that raymarches a box twisted around the Y axis. The original set TWIST = 3.0 radians per unit of height and stepped the full distance returned by map(), which overshoots because the twist raises the field's Lipschitz constant above 1, so the surface showed holes.

PASS if both hold:
- The twist is still applied at 1.5 radians per unit of height or more.
- The overshoot is compensated: map() divides the twisted distance by a factor above 1 or multiplies it by one below 1 (a constant such as 0.4, or a formula such as 1.0 / sqrt(1.0 + k*k*r*r)), or the march loop advances by a fraction of the distance (a step scale below 1).

FAIL if the twist was removed or weakened below 1.5, or if the only changes are more iterations, a smaller hit epsilon, or other tweaks that still step the full distance.
