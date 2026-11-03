// ============================================================================
// Appolo v0.1 — Configurable Shader Settings & Quality Presets
// ============================================================================
#ifndef APPOLO_SETTINGS_GLSL
#define APPOLO_SETTINGS_GLSL

// --- Core Quality Settings (Default = Maximum Fidelity / ULTRA_RT) ---
#define REFLECTION_QUALITY 4 // [1 2 3 4]
#define SHADOW_QUALITY 4 // [1 2 3 4]
const int shadowMapResolution = 2048; // [1024 2048 3072 4096]
const float shadowDistance = 192.0; // [64.0 96.0 128.0 160.0 192.0 256.0 320.0]
#define GI_QUALITY 3 // [0 1 2 3]
#define ATMOSPHERE_QUALITY 3 // [1 2 3]
#define VOLUMETRIC_QUALITY 4 // [1 2 3 4]
#define PLANET_RENDERING 3 // [1 2 3]
#define STAR_DENSITY 4 // [1 2 3 4]

// --- Lighting & Global Illumination Parameters ---
#define CONTACT_SHADOWS // Screen-space contact shadows
#define GI_BOUNCE_INTENSITY 1.25 // [0.25 0.50 0.75 1.00 1.25 1.50 2.00]
#define AO_INTENSITY 1.15 // [0.00 0.50 0.75 1.00 1.15 1.35 1.50]
#define DYNAMIC_LAVA_LIGHT 1.40 // [0.50 0.75 1.00 1.25 1.40 1.75 2.00]
#define CAVE_DARKNESS_LEVEL 0.92 // [0.50 0.70 0.85 0.92 0.97 1.00]
#define SUNLIGHT_INTENSITY 1.00 // [0.50 0.75 1.00 1.25 1.50]
#define MOONLIGHT_INTENSITY 1.00 // [0.25 0.50 0.75 1.00 1.25 1.50]

// --- PBR Materials, Glass, Obsidian & Water ---
#define PBR_MODE 1 // [1 2 3]
#define GLASS_REFRACTION // Dual-interface architectural glass refraction
#define GLASS_REFLECTION_BOOST 1.15 // [0.50 0.75 1.00 1.15 1.35 1.50]
#define OBSIDIAN_GLOSS 0.96 // [0.75 0.85 0.90 0.94 0.96 0.99]
#define WATER_WAVE_HEIGHT 1.00 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00]
#define WATER_CAUSTICS // Photon-mapped & Voronoi underwater caustics
#define WATER_ABSORPTION_SCALE 1.00 // [0.25 0.50 0.75 1.00 1.25 1.50 2.00]
#define ROUGHNESS_FILTERING // Specular cone filtering

// --- Overworld Environment & Night Sky ---
#define CLOUD_COVERAGE 0.52 // [0.00 0.25 0.40 0.52 0.65 0.80 0.95]
#define CLOUD_SHADOWS // Dynamic terrain cloud shadows
#define MILKY_WAY_INTENSITY 1.25 // [0.25 0.50 0.75 1.00 1.25 1.50 2.00]
#define DEEP_SPACE_GALAXIES // Andromeda M31 & deep-space galaxies
#define MOON_PHASE_LIGHTING // Physical lunar phase & Earthshine

// --- The End — 3D Solar System ---
#define JUPITER_SCALE 1.00 // [0.50 0.75 1.00 1.25 1.50]
#define SATURN_SCALE 1.00 // [0.50 0.75 1.00 1.25 1.50]
#define SATURN_RING_DETAIL 1.00 // [0.50 0.75 1.00 1.25]
#define EARTH_CITY_LIGHTS // Earth night-side metropolitan lights
#define END_SUN_INTENSITY 1.20 // [0.50 0.75 1.00 1.20 1.50 2.00]
#define END_STAR_BRIGHTNESS 1.15 // [0.50 0.75 1.00 1.15 1.50]
#define PLANET_ROTATION_SPEED 1.00 // [0.00 0.25 0.50 1.00 2.00 5.00]

// --- The Nether — Volcanic Hellscape ---
#define NETHER_ATMOSPHERE_DENSITY 1.25 // [0.50 0.75 0.85 1.00 1.25 1.40 1.75 2.00]
#define HEAT_DISTORTION // Refractive thermal heat haze
#define HEAT_HAZE_STRENGTH 1.00 // [0.00 0.25 0.50 0.75 1.00 1.50 2.00]
#define NETHER_STEAM_INTENSITY 1.25 // [0.00 0.50 0.75 1.00 1.25 1.50 2.00]
#define NETHER_EMBER_DENSITY 1.20 // [0.00 0.50 0.75 1.00 1.20 1.50 2.00]
#define LAVA_EMISSION_STRENGTH 1.50 // [0.50 0.75 1.00 1.25 1.50 2.00 3.00]

// --- Camera, Exposure, Tone Mapping & TAA ---
#define TONEMAP_OPERATOR 1 // [1 2 3]
#define BLOOM_INTENSITY 0.35 // [0.00 0.15 0.25 0.30 0.35 0.45 0.60 0.80 1.00]
#define EXPOSURE_SPEED 1.50 // [0.50 1.00 1.50 2.50 5.00]
#define EXPOSURE_BIAS 0.00 // [-1.50 -1.00 -0.50 -0.25 0.00 0.25 0.50 1.00 1.50]
#define CONTRAST_LEVEL 1.06 // [0.85 0.95 1.00 1.06 1.12 1.20]
#define SATURATION_LEVEL 1.02 // [0.75 0.90 1.00 1.02 1.10 1.20]
#define TAA_ENABLED // Temporal anti-aliasing & denoising
#define TAA_SHARPENING 0.45 // [0.00 0.25 0.45 0.65 0.85 1.00]

// --- Performance & Ray-Marching Budgets ---
#define RENDER_RESOLUTION 1.0 // [0.50 0.67 0.75 0.85 1.0]
#define SSR_MAX_STEPS 48 // [16 24 32 48 64 96]
#define VOLUMETRIC_STEPS 24 // [8 12 16 24 32 48]
#define CLOUD_MARCH_STEPS 20 // [8 12 16 20 28 36]

// --- Material ID Constants ---
const int MAT_DEFAULT       = 0;
const int MAT_WATER         = 1;
const int MAT_GLASS         = 2;
const int MAT_OBSIDIAN      = 3;
const int MAT_LAVA          = 4;
const int MAT_EMISSIVE_WARM = 5;
const int MAT_EMISSIVE_COOL = 6;
const int MAT_EMISSIVE_SOUL = 7;
const int MAT_METAL         = 10;
const int MAT_POLISHED      = 11;
const int MAT_FOLIAGE       = 12;
const int MAT_ICE           = 13;
const int MAT_VOLCANIC      = 14;
const int MAT_PORTAL        = 15;

#endif // APPOLO_SETTINGS_GLSL
