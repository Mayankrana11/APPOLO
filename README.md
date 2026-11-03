# APPOLO

<p align="center">
  <img src="docs/image1.jpg" alt="APPOLO Shaders Showcase" width="100%">
</p>

<p align="center">
  <b>Next-Generation Physically Based Rendering & Hybrid Ray Tracing Shader Pack for Minecraft Java Edition</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Status-Beta-orange?style=for-the-badge" alt="Status: Beta">
  <img src="https://img.shields.io/badge/Minecraft-26.3-brightgreen?style=for-the-badge" alt="Minecraft 26.3">
  <img src="https://img.shields.io/badge/Loader-Iris%20%7C%20Sodium%20%7C%20OptiFine-blue?style=for-the-badge" alt="Loaders">
  <img src="https://img.shields.io/badge/Pipeline-OpenGL%204.3%2B-red?style=for-the-badge" alt="OpenGL 4.3+">
  <img src="https://img.shields.io/badge/License-Custom%20Agreement-lightgrey?style=for-the-badge" alt="License">
</p>

---

> [!IMPORTANT]
> **BETA RELEASE NOTICE**  
> **APPOLO** is currently in active **Public Beta**. While feature-complete and extensively verified across core rendering pipelines, certain features, shader option ranges, and texture pack integrations are undergoing continuous refinement. Feedback, compatibility reports, and visual benchmarks are welcome.

---

## Overview

**APPOLO** is an ultra-realistic, physically based rendering (PBR) and ray-tracing-style shader pack built from the ground up for modern **Minecraft Java Edition 26.3**. 

Designed to push the visual boundaries of the Java Edition rendering engine to cinematic fidelity, APPOLO incorporates comprehensive physical light transport models, hybrid screen-space ray tracing, volumetric light simulation, multi-scale atmospheric scattering, true point-source planetary celestial illumination, and a complete AgX/ACES filmic color science pipeline.

<p align="center">
  <img src="docs/image2.jpg" alt="APPOLO Daytime Lighting and Water" width="49%">
  <img src="docs/image3.jpg" alt="APPOLO Night Sky and Milky Way" width="49%">
</p>

---

## Key Features & Implementation Breakdown

### 1. Physically Based Rendering (PBR) & Material Pipeline
* **Unified PBR Specification**: Universal auto-detection supporting **LabPBR 1.3** and legacy **OldPBR / SEUS** formats (e.g. UMSOEA), plus built-in procedural material synthesis for full vanilla fidelity without external resource packs.
* **Microfacet Specular BRDF**: Energy-conserving Cook-Torrance GGX microfacet distribution with Smith height-correlated geometric shadowing and Schlick/Dielectric Fresnel equations.
* **Burley Diffuse Reflection**: Disney diffuse formulation accounting for surface roughness retro-reflection and grazing-angle diffuse rolloff.
* **Subsurface Scattering (SSS)**: Translucent light diffusion modeling for foliage, leaves, flora, ice, and thin geometry.
* **Architectural Glass (`MAT_GLASS`)**: Unpolarized Dielectric Fresnel ($IOR = 1.52$), true physical transparency at perpendicular incidence, high reflectivity at shallow angles, dual-interface refraction offset, and Beer-Lambert spectral transmission absorption for clear and stained glass.
* **Volcanic Glass Obsidian (`MAT_OBSIDIAN`)**: High-index dielectric response ($IOR = 1.62$), deep black and dark-amethyst coloration, 3D conchoidal cleavage micro-normal relief, dual-lobe clearcoat specular response, and emissive purple vein illumination for Crying Obsidian.
* **Photorealistic Water (`MAT_WATER`)**: 5-cascade analytical Gerstner swell and capillary wave synthesis (zero repeating texture seams), Dielectric Water Fresnel ($IOR = 1.333$), screen-space wave refraction, Beer-Lambert spectral absorption (aquamarine shallow to deep ocean sapphire), dual-layer Voronoi caustics, and vivid multi-layer reflections (sun/moon specular glints, clouds, terrain, and night stars).
* **Molten Magma & Lava (`MAT_LAVA`)**: Dynamic 3D thermal convection normals, preserving resource pack base textures while adding physical blackbody emission gradients (deep crimson basaltic crust to incandescent golden-orange fissures).

### 2. Illumination & Shadow Transport
* **Physically Sourced Lighting**: Direct sunlight and moonlight with spectral atmospheric transmission curves.
* **PCSS Soft Shadows**: Percentage-Closer Soft Shadows with variable penumbra width based on blocker-to-receiver distance.
* **Contact Shadows**: Screen-space ray-traced micro-contact shadows resolving fine details around foliage, character feet, and block crevices.
* **Colored Shadow Mapping**: Chromatic shadow transmission through stained glass panes and translucent water bodies.
* **Global Illumination & Ambient Occlusion**:
  * **GTAO**: Ground-Truth Ambient Occlusion with cosine weighting.
  * **Multi-Bounce Approximation**: Analytical albedo color bounce mitigating unnatural dark cavity darkening.
  * **RSM & SSGI**: Reflective Shadow Map indirect bounce paired with Screen-Space Global Illumination for real-time color bleeding from bright terrain and emissive light sources (torches, glowstone, lava).

### 3. Diurnal Atmosphere & Astrophotography Night Sky
* **24-Hour Continuous Sky Progression**: Fully seamless transition sequence:  
  `Early Dawn → Sunrise / Morning → Mid-Day Noon → Golden Afternoon → Sunset → Dusk / Blue Hour → Night → Midnight → Pre-Dawn`.
* **Atmospheric Scattering**: Physical Rayleigh scattering and Cornette-Shanks Mie aerosol scattering producing clean, luminous azure daytime skies and radiant golden-hour horizons.
* **Volumetric Cumulus Clouds**: 3D ray-marched dual-octave fractal cumulus clouds with powder-sugar multi-scattering approximations and dynamic terrain shadow projection.
* **Astrophotography Milky Way**: Reference-matched, 100% isotropic 3D unit-sphere galactic core featuring the warm-ivory Sagittarius star cloud, clumpy Great Rift dark dust lanes, violet-pink H-II emission knots (Lagoon M8 / Trifid M20), and 5 tiers of pinpoint blackbody stars.
* **3D Ray-Traced Moon**: Spherical geometric intersection with procedural lunar maria, craters, ray systems, dynamic phase illumination, and Earthshine.

### 4. Custom Dimension Overhauls
* **The End — 3D Solar System**:
  * Replaces the abstract void with a scientifically scaled deep-space interplanetary vista positioned along the ecliptic between **Jupiter** and **Saturn**.
  * Complete planetary bodies: **Jupiter** (14 zonal belts, Great Red Spot), **Saturn** (multi-ring system with Cassini Division, Encke gap, and mutual planet/ring cast shadows), **Mars**, **Earth** (continents, blue oceans with specular glints, atmospheric limb, and nocturnal city light grids), **Venus**, **Mercury**, and the blazing point-source **Sun**.
  * **Point-Source Terminator Illumination**: All planetary spheres are lit directly by the End Sun ($L = \text{normalize}(P_\text{sun} - P_\text{hit})$) with sharp day/night terminators and atmospheric crescent rims.
* **The Nether — Volcanic Hellscape**:
  * Multi-scattered atmospheric volcanic haze responding dynamically to biomes (Crimson/Wastes amber-red vs. Soul Sand Valley cyan-blue).
  * 3D ray-marched thermal vapor plumes rising from lava lakes with upward-projected radiant light transport.
  * Subtle refractive heat shimmer on distant horizon silhouettes.

### 5. Camera, Exposure & Cinematic Post-Processing
* **Temporal Anti-Aliasing (TAA)**: Sub-pixel jitter reprojection in $Y\text{CoCg}$ color space with variance clipping to eliminate edge aliasing and specular shimmer without motion ghosting.
* **HDR Eye Adaptation**: Smooth temporal exposure metering adapting dynamically between sunlit landscapes and dark cave interiors.
* **Cinematic Tone Mapping**: Native support for **AgX** (Blender filmic highlight rolloff), **ACES Fitted**, and **Khronos PBR Neutral**.
* **Physical Bloom**: Multi-scale dual-ring Gaussian/Kawase bloom filter with soft-knee highlight extraction.
* **Contrast-Adaptive Sharpening (CAS)**: Linear HDR sharpening restoring fine texture fidelity post-TAA.

---

## Technical Specifications & Compatibility

| Component | Minimum / Target Specification |
| :--- | :--- |
| **Minecraft Version** | **Java Edition 26.3** |
| **Supported Loaders** | **Iris Shaders** (Recommended), **Sodium**, **Embeddium / Beddium**, **OptiFine** |
| **Shading Language** | **GLSL `#version 430 compatibility`** (Validated across 82 base programs + 42 option permutations) |
| **Buffer Architecture** | Dual-pass G-buffer layout with `RGBA16F` HDR accumulation and `RGBA8` auxiliary channels |
| **PBR Formats** | **LabPBR 1.3** (`_n`, `_s`), **OldPBR / SEUS**, and Procedural Fallback |
| **Required GPU** | Modern dedicated GPU supporting OpenGL 4.3 or higher (NVIDIA GeForce, AMD Radeon, Intel Arc) |

---

## Repository & Folder Structure

```
appolo/
├── pack.mcmeta                     # Minecraft shader pack identifier & resource metadata
├── README.md                       # Main documentation & technical guide
├── LICENSE                         # APPOLO Shaders License Agreement
├── git_commits.txt                 # Ordered git history commands
├── docs/                           # Documentation assets and screenshots
│   ├── image1.jpg                  # Hero showcase image
│   ├── image2.jpg                  # Daytime & water showcase
│   └── image3.jpg                  # Night sky & astrophotography showcase
└── shaders/                        # Primary shader source code
    ├── shaders.properties          # Pipeline flags, buffer blending, profile definitions, UI sliders
    ├── block.properties            # Block ID mapping to PBR material categories (water, glass, obsidian, etc.)
    ├── dimension.properties        # Dimension ID routing (0 = Overworld, -1 = Nether, 1 = The End)
    ├── shadow.vsh / shadow.fsh     # Shadow pass entry points
    ├── gbuffers_*.vsh / *.fsh      # G-buffer stage entry points (terrain, entities, water, sky, etc.)
    ├── deferred.vsh / deferred.fsh # Deferred lighting & PBR direct/indirect illumination pass
    ├── composite.vsh / *.fsh       # Composite pass 0 (water, glass, obsidian, reflections)
    ├── composite1.vsh / *.fsh      # Composite pass 1 (volumetric fog, light shafts, steam)
    ├── composite2.vsh / *.fsh      # Composite pass 2 (temporal anti-aliasing / TAA)
    ├── composite3.vsh / *.fsh      # Composite pass 3 (HDR bloom extraction & auto-exposure)
    ├── final.vsh / final.fsh       # Presentation pass (tone mapping & CAS sharpening)
    ├── lang/                       # Localization dictionaries
    │   └── en_US.lang              # English UI labels, screen titles, and option descriptions
    ├── textures/                   # Atlas textures and procedural lookups
    │   ├── noisetex.png            # 512x512 4-quadrant scientific atlas (blue noise, waves, caustics)
    │   └── README.txt              # Atlas documentation
    ├── lib/                        # Modular GLSL include libraries
    │   ├── common.glsl             # Coordinate transforms, hash functions, and format directives
    │   ├── settings.glsl           # Quality presets, feature defines, and configuration sliders
    │   ├── pbr.glsl                # Material decoding, GGX BRDF, Fresnel, wave & lava math
    │   ├── shadows.glsl            # PCSS shadow filtering, contact shadows, colored glass shadows
    │   ├── gi_ao.glsl              # GTAO, SSGI, RSM bounce, and dynamic block illumination
    │   ├── reflections.glsl        # Screen-space ray tracing (SSRT) and environment specular
    │   ├── sky_overworld.glsl      # Atmospheric scattering, cumulus clouds, Milky Way, 3D Moon
    │   ├── sky_end.glsl            # 3D ray-traced solar system, planetary shading, Saturn rings
    │   ├── sky_nether.glsl         # Volcanic atmosphere, rising steam plumes, heat distortion
    │   ├── volumetrics.glsl        # Crepuscular rays, stained-glass light shafts, valley mist
    │   └── post.glsl               # TAA reprojection, AgX/ACES tone mapping, color grading
    ├── programs/                   # Core shared GLSL implementation programs
    │   ├── gbuffers_opaque_*.glsl  # Opaque and cutout G-buffer vertex & fragment stages
    │   ├── gbuffers_water_*.glsl   # Translucent (water, glass, ice) vertex & fragment stages
    │   ├── gbuffers_sky_*.glsl     # Sky suppression passes
    │   ├── shadow_*.glsl           # Shadow mapping & RSM flux output
    │   ├── deferred_frag.glsl      # Deferred lighting evaluation
    │   ├── composite_frag.glsl     # Composite 0 evaluation
    │   ├── composite1_frag.glsl    # Composite 1 evaluation
    │   ├── composite2_frag.glsl    # TAA resolve stage
    │   ├── composite3_frag.glsl    # Bloom & exposure metering
    │   ├── final_frag.glsl         # Presentation tone mapping
    │   └── fullscreen_vert.glsl    # Standard screen-space pass vertex shader
    ├── world0/                     # Overworld-specific overrides & entry points
    ├── world-1/                    # Nether-specific overrides & entry points
    └── world1/                     # The End-specific overrides & entry points
```

---

## Installation & Setup

1. **Prerequisites**: Ensure you have installed **Minecraft Java Edition 26.3** with **Iris Shaders** (recommended) or **OptiFine**.
2. **Download**: Obtain the latest `APPOLO` release archive (`APPOLO-v0.1-MC26.3-UltraRT.zip`).
3. **Install**: Place the `.zip` file or unpacked folder directly into your `.minecraft/shaderpacks/` directory.
4. **Activate**:
   * Launch Minecraft.
   * Navigate to **Options → Video Settings → Shader Packs**.
   * Select **APPOLO** from the list and select **Apply**.
5. **Configuration Profiles**:
   * Open **Shader Pack Settings** to choose between built-in performance profiles:
     * **Ultra RT (Default)**: Full graphical fidelity, high-precision SSR, maximum shadow resolution, full volumetric scattering.
     * **Extreme Cinematic**: Maximum ray-march steps, extended shadow distance, enhanced volumetric density.
     * **High**: Balanced high-fidelity setting suited for standard gameplay.
     * **Balanced**: Optimized ray-march budgets and shadow resolutions for mid-range systems.

---

## License & Usage Terms

**APPOLO** is distributed under the terms of the **[APPOLO Shaders License Agreement](LICENSE)**.

### Summary of Terms:
* **Personal & Content Creation Use**: You are free to use APPOLO for personal gameplay, screenshots, and commercial video production (e.g., YouTube, Twitch) with credit.
* **Modification**: Personal modifications and studying the source code are permitted.
* **Redistribution Restrictions**:
  * You **may not** redistribute APPOLO or derivative works on platforms providing direct or indirect monetization (such as Modrinth, CurseForge) without explicit written permission from the author.
  * You **may not** sell or charge money for copies or derivative works of APPOLO.
* **Modpacks**: Inclusion in non-commercial or commercial modpacks is permitted provided original credit and the license document are preserved.

For the full binding legal text, please refer directly to the **[LICENSE](LICENSE)** file.

---

<p align="center">
  <b>Developed by Mayank Rana (<a href="https://github.com/Mayankrana11">@Mayankrana11</a>)</b><br>
  <i>Pushing Minecraft graphics beyond reality.</i>
</p>
