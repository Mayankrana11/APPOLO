# Appolo v0.1 — Ultra-Realistic Ray Tracing & PBR Shader Pack for Minecraft 26.3

**Appolo v0.1** is a next-generation, physically based rendering (PBR) and hybrid ray-tracing shader pack engineered for **Minecraft Java Edition 26.3** with full compatibility across **Iris Shaders**, **Sodium**, **Beddium / Embeddium**, and **OptiFine**.

---

## 1. Technical Compatibility & Architecture

- **Target Minecraft Version**: Minecraft Java Edition **26.3**
- **Target Shader Loaders & Renderers**: **Iris Shaders**, **Sodium**, **Beddium / Embeddium / Oculus**, and **OptiFine**
- **GLSL Target**: `#version 430 compatibility` (Hardware-validated across all 82 shader programs on OpenGL 4.6, with both `/* RENDERTARGETS: ... */` and `/* DRAWBUFFERS:... */` annotations plus `const int colortexNFormat = RGBA16F;` directives for universal loader support)
- **PBR Standard**: Full **LabPBR 1.3** resource pack decoding (`_n` and `_s` textures) + **Integrated Procedural Material Synthesis** (so vanilla blocks automatically exhibit physically distinct roughness, F0 reflectance, micro-normals, and emission even without an external PBR texture pack).
- **Honest Ray Tracing Architecture**:
  - Because Minecraft Java Edition 26.3 with Iris / Sodium / Beddium / OptiFine executes over OpenGL rather than Vulkan `VK_KHR_ray_tracing_pipeline` / DXR hardware BVH, Appolo v0.1 implements a **Hybrid Screen-Space + Shadow-Space + Analytic 3D Ray-Tracing Pipeline**:
    1. **Hierarchical Screen-Space Ray Marching (SSRT)** with 4-step binary search hit refinement and thickness validation for reflections, refractions, and contact shadows (`shaders/lib/reflections.glsl`, `shaders/lib/shadows.glsl`).
    2. **Reflective Shadow Map (RSM) + Screen-Space Path-Traced Global Illumination (SSGI)** with multi-bounce color bleeding, cave portal light gradients, and dynamic lava/emissive block bounce (`shaders/lib/gi_ao.glsl`).
    3. **Analytic 3D Ray-Sphere & Ray-Plane Intersection Ray Tracing** for The End's Solar System (`shaders/lib/sky_end.glsl`) and Overworld's 3D Moon (`shaders/lib/sky_overworld.glsl`), delivering true spherical geometry, mutual planet-and-ring shadow casting, and atmospheric limb scattering.
    4. **3D Volumetric Ray Marching** for Overworld atmospheric light shafts & cumulus clouds (`shaders/lib/volumetrics.glsl`, `shaders/lib/sky_overworld.glsl`) and The Nether's rising lava steam plumes, volcanic smoke, ash, and embers (`shaders/lib/sky_nether.glsl`).

---

## 2. Key Visual Features

### Extreme PBR Materials (`shaders/lib/pbr.glsl`, `shaders/programs/composite_frag.glsl`)
- **Architectural Glass (`MAT_GLASS`)**: Exact unpolarized Dielectric Fresnel (`IOR = 1.52`), crystal-clear transparency at normal incidence (`~4%` reflectance), strong architectural reflections at shallow grazing angles, dual-interface refraction offset, subtle cyan-green grazing edge absorption, and Beer-Lambert spectral transmission for all 16 stained glass colors.
- **Volcanic Glass Obsidian (`MAT_OBSIDIAN`)**: High-index volcanic glass Fresnel (`IOR = 1.62`), deep black and dark purple coloration, dual-lobe GGX specular clearcoat over conchoidal micro-normal fractures, and glowing violet veins on Crying Obsidian.
- **Physically Based Water (`MAT_WATER`)**: Multi-octave Gerstner + capillary wave synthesis, Dielectric Water Fresnel (`IOR = 1.333`), screen-space wave refraction, Beer-Lambert exponential depth absorption (`exp(-vec3(0.42, 0.088, 0.036) * depth)`), shoreline foam, dual-layer Voronoi interference caustics, and full reflections of the Milky Way, stars, Moon, Sun, clouds, and terrain.

### Overworld & Astrophotography Night Sky (`shaders/lib/sky_overworld.glsl`)
- **Daytime & Twilight**: Physical Rayleigh and Cornette-Shanks Mie scattering, natural golden-hour transitions, twilight Belt of Venus, and 3D ray-marched volumetric clouds casting dynamic shadows on terrain.
- **Night Sky**: Reference-matched astrophotography Milky Way with a warm golden-amber Sagittarius core, subtle purple/violet/sapphire galactic band, multi-scale dark dust lanes (Great Rift filaments using Beer-Lambert extinction), H-II pink emission nebulae, Andromeda (`M31`) inclined spiral galaxy, 4-tier Cube-Sphere blackbody starfield (thousands of pinpoint stars), and a 3D ray-traced Moon with lunar maria, craters, phases, and Earthshine.

### The End — Complete 3D Solar System (`shaders/lib/sky_end.glsl`)
- Replaces the vanilla purple End with a deep-space cosmic environment positioned **between Jupiter and Saturn**:
  - **Jupiter**: Enormous 3D gas giant with 14 turbulent zonal belts/zones, Kelvin-Helmholtz festoons, white anticyclonic ovals, atmospheric limb glow, and a swirling **Great Red Spot**.
  - **Saturn**: Enormous opposite-hemisphere gas giant with golden-ochre bands, polar hexagon tint, and an analytic 3D concentric ring system (**D, C, B, Cassini Division, A, Encke Gap, F rings**) with mutual ray-traced **planet-on-ring** and **ring-on-planet** shadows.
  - **Inner Ecliptic Arc (`Jupiter → Mars → Earth → Venus → Mercury → Sun`)**:
    - **Mars**: Reddish iron-oxide deserts, dark basalt regions, polar ice caps, and salmon atmospheric haze.
    - **Earth**: Blue oceans with solar specular glint, fractal continents, polar ice caps, swirling white clouds, blue Rayleigh limb glow, and **golden night-side city light networks**.
    - **Venus**: Dense yellowish sulfuric cloud deck and thick atmospheric scattering.
    - **Mercury**: Heavily cratered dark silicate regolith surface next to the blazing **Sun** (with convective granulation and multi-stage coronal streamers).
  - **Outer Ice Giants (`Saturn → Uranus → Neptune`)**: Pale cyan **Uranus** and deep cobalt-azure **Neptune** with white methane cirrus bands and Great Dark Spot.

### The Nether — Hostile Volcanic Hellscape (`shaders/lib/sky_nether.glsl`)
- **Volcanic Atmosphere & Sky**: Billowing dark pyroclastic smoke canopy, glowing magma fissures, and biome-aware coloration.
- **3D Rising Lava Steam & Heat Haze**: Ray-marched vertical steam and vapor plumes rising from lava lakes (illuminated from below by molten orange-red lava), refractive screen-space heat distortion, floating incandescent embers, and volcanic ash.

---

## 3. Installation

1. Install **Iris Shaders + Sodium** (or **Beddium / Embeddium / OptiFine**) for **Minecraft Java Edition 26.3**.
2. Copy `Appolo-v0.1-MC26.3-UltraRT.zip` (or the `appolo-v0.1` folder) into `.minecraft/shaderpacks/`.
3. Launch Minecraft 26.3, open **Options → Video Settings → Shader Packs**, select **Appolo v0.1**, and click **Apply**.
4. Default profile is **Ultra RT (Maximum Fidelity)**. Additional presets (**Extreme Cinematic**, **High**, **Balanced**) and granular sliders are available in **Shader Pack Settings**.
