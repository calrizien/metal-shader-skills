# Credits and Sources

All GLSL in this repository is an original implementation, released under the MIT license (see LICENSE). The
techniques come from the published work below. Numeric constants (matrices, fit coefficients, physical
coefficients) are facts reproduced from their sources. No third-party shader source is copied; Shadertoy shaders
default to CC BY-NC-SA 3.0, which is incompatible with MIT.

| Technique | Source | License or terms of the source |
|---|---|---|
| SDF primitives, operators, smooth minimum, domain repetition, normals, soft shadows, intersectors, fog, palettes, filtered patterns, Voronoi borders, noise derivatives, domain warping | Inigo Quilez, iquilezles.org/articles | articles state no license; ideas reimplemented |
| Chamfer, stairs and engrave combinators, polar and mirrored repetition | Mercury demogroup, hg_sdf (mercury.sexy/hg_sdf) | MIT OR CC BY-NC 4.0 |
| PCG hashes (pcgHash, pcg3d, pcg4d) and hash quality data | Jarzynski and Olano, "Hash Functions for GPU Rendering", JCGT 9(3), 2020 | paper CC BY-ND 3.0; arithmetic reimplemented |
| Interleaved gradient noise | Jorge Jimenez, "Next Generation Post Processing in Call of Duty: Advanced Warfare", SIGGRAPH 2014 | constants are facts |
| R2 low-discrepancy sequence | Martin Roberts, "The Unreasonable Effectiveness of Quasirandom Sequences" | constants are facts |
| Curl noise | Bridson, Hourihan and Nordenstam, SIGGRAPH 2007 | math |
| Enhanced (over-relaxed) sphere tracing (documented, not shipped) | Keinert et al., STAG 2014 | math |
| AgX tonemapping (minimal polynomial version) | Troy Sobotka (AgX); Benjamin Wrensch / iolite (polynomial fit) | MIT |
| Khronos PBR Neutral tonemapping | Khronos Group, github.com/KhronosGroup/ToneMapping | Apache-2.0 (constants) |
| ACES fitted (RRT+ODT) | Stephen Hill, via MJP's BakingLab | MIT |
| Oklab / OkLCh | Bjorn Ottosson, bottosson.github.io/posts/oklab | public domain / MIT |
| Blackbody chromaticity | Krystek 1985 Planckian-locus fit | math |
| GGX, height-correlated Smith visibility, Schlick Fresnel | Filament documentation (Google) | Apache-2.0 (formulas) |
| Environment BRDF approximation | Brian Karis, "Physically Based Shading on Mobile" (after Lazarov) | constants are facts |
| Energy-conserving wrap lighting | Stephen Hill, "Righting Wrap" (2011) | math |
| Fast translucency | Barre-Brisebois and Bouchard, GDC 2011 | math |
| Energy-conserving volume integration, sky constants | Sebastien Hillaire, Frostbite (SIGGRAPH 2015/2016) and EGSR 2020 | math, constants are facts |
| Beer-Powder cloud lighting, dual-lobe phase | Andrew Schneider, Horizon Zero Dawn clouds (SIGGRAPH 2015) | math |
| Sun limb darkening | Neckel 1996 | constants are facts |
| Cornette-Shanks phase function | Cornette and Shanks 1992 | math |
| Simplex noise and its analytic gradient | Stefan Gustavson, "Simplex noise demystified" (2005); Gustavson and McEwan, "Tiling simplex noise and flow noise in two and three dimensions", JCGT 11(1), 2022 | papers; math reimplemented, the psrdnoise reference code is not used |
| Flow noise (rotating gradients) | Perlin and Neyret, "Flow Noise", SIGGRAPH 2001 technical sketch | math |
| Turbulence | Ken Perlin, "An Image Synthesizer", SIGGRAPH 1985 | math |
| Gradient-noise learning reference | [Ken Perlin, improved noise](https://cs.nyu.edu/~perlin/noise/) | reference only; fixed-permutation Java code not copied |
| Noise progression: fBm, ridges, cellular construction, domain warping | [Gonzalez Vivo and Lowe, The Book of Shaders, chapters 12](https://thebookofshaders.com/12/) and [13](https://thebookofshaders.com/13/) | explanatory sources; no source code copied |
| External noise code catalog | [Gustavson / Ashima, webgl-noise](https://github.com/stegu/webgl-noise), [psrdnoise](https://github.com/stegu/psrdnoise), [Auburn, FastNoise Lite](https://github.com/Auburn/FastNoiseLite) | MIT alternatives linked in the use-case guide; not vendored |
| Billow terminology | [libnoise Billow documentation](https://libnoise.sourceforge.net/docs/classnoise_1_1module_1_1Billow.html) | reference only; code not copied; local weighted [0,1] billow differs |
| Hybrid terrain height and designed river composition | this repository, `hybridTerrainHeight` / `noise-terrain-map.glsl` | original MIT composition; not a claim to implement Musgrave's hybrid multifractal or hydrological erosion |
| Sum-of-sines water with sharpened crests, deep-water dispersion | Mark Finch, "Effective Water Simulation from Physical Models", GPU Gems (2004), chapter 1 | math |
| Filtering vanished normal detail into roughness | Toksvig, "Mipmapping Normal Maps" (2005); Olano and Baker, "LEAN Mapping" (I3D 2010) | math |
| Four-arc (Moss) egg | classical compass construction | geometry |
