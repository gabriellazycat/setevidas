import * as THREE from 'three';
import { textures } from './Textures';

/** Uniforms shared by every custom shader in the game. */
export const Shared = {
  time: { value: 0 },
  vision: { value: 0 },
  fear: { value: 0 },
  camPos: { value: new THREE.Vector3() },
  /** 0..1 gust strength: trees sway and the leaves rustle */
  wind: { value: 0.25 },
};

/**
 * Room-masked point lights.
 * Every lit material is patched so point light `i` only affects fragments inside box `i`
 * (with a short soft edge). This keeps light from bleeding through walls into the next room,
 * which is essential for the "lights go out room by room" gameplay.
 */
export const RM_MAX = 18;
/** per light: region 0 is its own room, regions 1..3 are "spill" zones behind open doors / arches / stairwells */
export const RM_REGIONS = 4;
export const RoomMask = {
  /** xyz = box min, w = gain */
  min: { value: Array.from({ length: RM_MAX * RM_REGIONS }, () => new THREE.Vector4(1e5, 1e5, 1e5, 0)) },
  max: { value: Array.from({ length: RM_MAX * RM_REGIONS }, () => new THREE.Vector4(-1e5, -1e5, -1e5, 0)) },
};

const POINT_START = 'getPointLightInfo( pointLight, geometryPosition, directLight );';
const RE_LINE =
  'RE_Direct( directLight, geometryPosition, geometryNormal, geometryViewDir, geometryClearcoatNormal, material, reflectedLight );';

let patchedLightsChunk: string | null = null;
function lightsChunk() {
  if (patchedLightsChunk) return patchedLightsChunk;
  const src = THREE.ShaderChunk.lights_fragment_begin;
  const a = src.indexOf(POINT_START);
  const b = src.indexOf(RE_LINE, a);
  if (a < 0 || b < 0) {
    console.warn('[Materials] light chunk layout changed; room masks disabled');
    patchedLightsChunk = src;
    return src;
  }
  const middle = src.slice(a + POINT_START.length, b);
  // note: three only rewrites `[ i ]` and UNROLLED_LOOP_INDEX inside unrolled loops
  const replaced =
    POINT_START +
    `
		float rmk_UNROLLED_LOOP_INDEX = 0.0;
		if ( dot( directLight.color, vec3( 1.0 ) ) > 0.0001 ) {
		rmk_UNROLLED_LOOP_INDEX = max( max( rmRegion( uRMMin[ UNROLLED_LOOP_INDEX * ${RM_REGIONS} ], uRMMax[ UNROLLED_LOOP_INDEX * ${RM_REGIONS} ] ), rmRegion( uRMMin[ UNROLLED_LOOP_INDEX * ${RM_REGIONS} + 1 ], uRMMax[ UNROLLED_LOOP_INDEX * ${RM_REGIONS} + 1 ] ) ), max( rmRegion( uRMMin[ UNROLLED_LOOP_INDEX * ${RM_REGIONS} + 2 ], uRMMax[ UNROLLED_LOOP_INDEX * ${RM_REGIONS} + 2 ] ), rmRegion( uRMMin[ UNROLLED_LOOP_INDEX * ${RM_REGIONS} + 3 ], uRMMax[ UNROLLED_LOOP_INDEX * ${RM_REGIONS} + 3 ] ) ) );
		}
		if ( rmk_UNROLLED_LOOP_INDEX > 0.001 ) {
		directLight.color *= rmk_UNROLLED_LOOP_INDEX;
		` +
    middle +
    RE_LINE +
    `
		}`;
  patchedLightsChunk = src.slice(0, a) + replaced + src.slice(b + RE_LINE.length);
  return patchedLightsChunk;
}

export function patchRoomMask<T extends THREE.Material>(m: T): T {
  m.onBeforeCompile = (shader) => {
    shader.uniforms.uRMMin = RoomMask.min;
    shader.uniforms.uRMMax = RoomMask.max;
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vRMWorld;')
      .replace(
        '#include <project_vertex>',
        `#include <project_vertex>
        vec4 rmW = vec4( transformed, 1.0 );
        #ifdef USE_BATCHING
        rmW = batchingMatrix * rmW;
        #endif
        #ifdef USE_INSTANCING
        rmW = instanceMatrix * rmW;
        #endif
        vRMWorld = ( modelMatrix * rmW ).xyz;`,
      );
    shader.fragmentShader = shader.fragmentShader
      .replace(
        '#include <common>',
        `#include <common>
        varying vec3 vRMWorld;
        uniform vec4 uRMMin[ ${RM_MAX * RM_REGIONS} ];
        uniform vec4 uRMMax[ ${RM_MAX * RM_REGIONS} ];
        float rmRegion( vec4 bmin, vec4 bmax ) {
          vec3 d = max( bmin.xyz - vRMWorld, vRMWorld - bmax.xyz );
          float o = max( max( d.x, d.y ), d.z );
          return ( 1.0 - smoothstep( 0.0, 0.14, o ) ) * bmin.w;
        }`,
      )
      .replace('#include <lights_fragment_begin>', lightsChunk());
  };
  m.customProgramCacheKey = () => 'roommask2';
  return m;
}

interface MatDef {
  color?: string;
  map?: string;
  tile?: number;
  rough?: number;
  metal?: number;
  flat?: boolean;
  transparent?: boolean;
  opacity?: number;
  emissive?: string;
  emissiveIntensity?: number;
  side?: THREE.Side;
  envBoost?: number;
  /** polygon-offset priority: negative wins ties against coplanar faces of other materials */
  po?: number;
}

const DEFS: Record<string, MatDef> = {
  floor_wood: { map: 'woodFloor', tile: 2.2, rough: 0.55 },
  floor_wood_dark: { map: 'woodFloorDark', tile: 2.2, rough: 0.6 },
  floor_checker: { map: 'tileChecker', tile: 1.6, rough: 0.35 },
  floor_tile: { map: 'tileWhite', tile: 1.5, rough: 0.3 },
  floor_concrete: { map: 'concrete', tile: 4, rough: 0.9 },
  floor_attic: { map: 'woodFloorDark', tile: 3, rough: 0.85, color: '#9a8a7a' },
  wall_sala: { map: 'papSala', tile: 1.2, rough: 0.9 },
  wall_quarto: { map: 'papQuarto', tile: 1.4, rough: 0.9 },
  wall_hospedes: { map: 'papHospedes', tile: 1.0, rough: 0.9 },
  wall_escritorio: { map: 'papEscritorio', tile: 1.6, rough: 0.9 },
  wall_hall: { map: 'plasterHall', tile: 2, rough: 0.95, color: '#d8c8b0' },
  wall_corredor: { map: 'plasterBeige', tile: 2, rough: 0.95, color: '#e8dccb' },
  wall_cozinha: { map: 'tileKitchenWall', tile: 1.2, rough: 0.4 },
  wall_banheiro: { map: 'tileBlue', tile: 1.2, rough: 0.3 },
  wall_brick: { map: 'brickBasement', tile: 1.6, rough: 0.95 },
  wall_attic: { map: 'woodFurniture', tile: 2, rough: 0.9, color: '#8a7a68' },
  wall_lavanderia: { map: 'concrete', tile: 3, rough: 0.95, color: '#c0b8a8' },
  exterior: { po: -1, map: 'siding', tile: 2.2, rough: 0.85 },
  exterior_base: { po: -1, map: 'brick', tile: 1.6, rough: 0.95 },
  ceiling: { po: -1, map: 'plasterCeiling', tile: 3, rough: 0.95 },
  trim: { po: -2, color: '#e9e3d6', rough: 0.6, map: 'woodPaint', tile: 1 },
  wood: { po: -0.5, map: 'woodFurniture', tile: 1.2, rough: 0.55 },
  wood_dark: { po: -0.5, map: 'woodDarkFurniture', tile: 1.2, rough: 0.5 },
  wood_paint: { po: -1, map: 'woodPaint', tile: 1, rough: 0.6, color: '#efe8da' },
  wood_paint_green: { map: 'woodPaint', tile: 1, rough: 0.6, color: '#7c9a86' },
  wood_paint_blue: { map: 'woodPaint', tile: 1, rough: 0.6, color: '#6f8aa6' },
  roof: { po: -1, map: 'shingles', tile: 1.4, rough: 0.9 },
  grass: { map: 'grass', tile: 6, rough: 1 },
  asphalt: { map: 'asphalt', tile: 4, rough: 0.85 },
  sidewalk: { map: 'concrete', tile: 3, rough: 0.9, color: '#a9a49a' },
  metal: { color: '#8c9096', rough: 0.35, metal: 0.8 },
  metal_dark: { color: '#2e3135', rough: 0.45, metal: 0.7 },
  chrome: { color: '#d8dde2', rough: 0.12, metal: 1 },
  brass: { color: '#b08a4a', rough: 0.3, metal: 0.9 },
  ceramic: { color: '#f1f0ea', rough: 0.12 },
  enamel: { color: '#e9e6dc', rough: 0.2 },
  glass: { po: -1.5, color: '#a8c4d8', rough: 0.04, transparent: true, opacity: 0.16 },
  mirror: { color: '#b9c7cf', rough: 0.02, metal: 1 },
  sofa: { map: 'sofa', tile: 0.6, rough: 0.95 },
  fabric_blue: { map: 'fabricBlue', tile: 0.6, rough: 0.95 },
  fabric_cream: { map: 'fabricCream', tile: 0.6, rough: 0.95 },
  fabric_green: { map: 'fabricGreen', tile: 0.6, rough: 0.95 },
  blanket: { map: 'blanket', tile: 0.8, rough: 0.95 },
  sheet: { map: 'sheet', tile: 1, rough: 0.95 },
  carpet_red: { map: 'carpetRed', tile: 2.4, rough: 1 },
  carpet_blue: { map: 'carpetBlue', tile: 2.0, rough: 1 },
  cardboard: { color: '#a9835a', rough: 0.95 },
  cardboard_dark: { color: '#8a6a48', rough: 0.95 },
  tape: { color: '#c9b48a', rough: 0.6 },
  plastic_black: { color: '#1b1c1e', rough: 0.4 },
  plastic_beige: { color: '#cfc4ad', rough: 0.5 },
  plastic_white: { color: '#e6e6e2', rough: 0.4 },
  plastic_red: { color: '#9a2f2a', rough: 0.45 },
  paper: { color: '#ece6d6', rough: 0.9 },
  book_a: { color: '#6a2f2a', rough: 0.8 },
  book_b: { color: '#2f4a5a', rough: 0.8 },
  book_c: { color: '#5a5a2f', rough: 0.8 },
  book_d: { color: '#3d2f4a', rough: 0.8 },
  plant: { color: '#3f6a3a', rough: 0.8, flat: true },
  plant_dark: { color: '#2c4a2a', rough: 0.8, flat: true },
  soil: { color: '#3a2a1e', rough: 1 },
  terracotta: { color: '#a65a3a', rough: 0.8 },
  lampshade: { color: '#e8d6b0', rough: 0.9, side: THREE.DoubleSide },
  screen: { color: '#0d1214', rough: 0.15, metal: 0.2 },
  painting0: { map: 'painting0', rough: 0.7 },
  painting1: { map: 'painting1', rough: 0.7 },
  painting2: { map: 'painting2', rough: 0.7 },
  frame: { color: '#5a3d22', rough: 0.5 },
  frame_gold: { color: '#a8843f', rough: 0.35, metal: 0.7 },
  stone: { color: '#6a6862', rough: 0.95, flat: true },
  bark: { color: '#3a2c22', rough: 1, flat: true },
  leaves: { color: '#26381f', rough: 0.9, flat: true },
  leaves_b: { color: '#1f2d1c', rough: 0.9, flat: true },
  fence: { color: '#d8d4ca', rough: 0.8 },
  mattress: { color: '#e8e2d6', rough: 0.95 },
  pillow: { color: '#f0ece4', rough: 0.95 },
  rubber: { color: '#262626', rough: 0.95 },
  water: { color: '#6f97a8', rough: 0.05, transparent: true, opacity: 0.55 },
  puddle: { color: '#1a2228', rough: 0.02, metal: 0.4, transparent: true, opacity: 0.85 },
  boiler: { color: '#5a5f55', rough: 0.6, metal: 0.5 },
  white_sheet: { color: '#b7b0a2', map: 'sheet', tile: 0.9, rough: 0.95, flat: true },
  cat_food: { color: '#6a4228', rough: 0.9 },
  bowl: { color: '#b84a3a', rough: 0.3 },
};

/** vertex sway for trees: geometry is merged in world space, so position is already world position */
function patchWind(m: THREE.Material, amount: number) {
  const prev = m.onBeforeCompile;
  m.onBeforeCompile = (shader, renderer) => {
    prev?.call(m, shader, renderer);
    shader.uniforms.uWindT = Shared.time;
    shader.uniforms.uWind = Shared.wind;
    shader.vertexShader = shader.vertexShader
      .replace('#include <common>', '#include <common>\nuniform float uWindT;\nuniform float uWind;')
      .replace(
        '#include <begin_vertex>',
        `#include <begin_vertex>
        {
          float h = clamp((position.y + 0.9) / 5.0, 0.0, 1.0);
          float ph = position.x * 0.45 + position.z * 0.31;
          float gust = 0.55 + 0.45 * sin(uWindT * 0.35 + ph * 0.2);
          float sway = sin(uWindT * 1.35 + ph) * 0.5 + sin(uWindT * 2.9 + ph * 1.7) * 0.22;
          transformed.x += sway * h * h * (0.05 + 0.34 * uWind * gust) * ${amount.toFixed(2)};
          transformed.z += cos(uWindT * 1.1 + ph * 1.3) * h * h * (0.04 + 0.26 * uWind * gust) * ${amount.toFixed(2)};
        }`,
      );
  };
  m.customProgramCacheKey = () => 'roommask2wind';
}

const cache = new Map<string, THREE.MeshStandardMaterial>();

export function mat(key: string): THREE.MeshStandardMaterial {
  const c = cache.get(key);
  if (c) return c;
  const d = DEFS[key];
  if (!d) throw new Error(`Unknown material ${key}`);
  const lib = textures();
  const m = new THREE.MeshStandardMaterial({
    color: d.color ?? '#ffffff',
    roughness: d.rough ?? 0.8,
    metalness: d.metal ?? 0,
    flatShading: d.flat ?? false,
    transparent: d.transparent ?? false,
    opacity: d.opacity ?? 1,
    side: d.side ?? THREE.FrontSide,
  });
  if (d.map) {
    const t = lib[d.map].clone();
    const tile = d.tile ?? 1;
    t.repeat.set(1 / tile, 1 / tile);
    t.needsUpdate = true;
    m.map = t;
  }
  if (d.emissive) {
    m.emissive = new THREE.Color(d.emissive);
    m.emissiveIntensity = d.emissiveIntensity ?? 1;
  }
  if (d.transparent) m.depthWrite = false;
  if (d.po) {
    m.polygonOffset = true;
    m.polygonOffsetFactor = d.po;
    m.polygonOffsetUnits = d.po;
  }
  m.name = key;
  patchRoomMask(m);
  if (key === 'leaves' || key === 'leaves_b' || key === 'bark') patchWind(m, key === 'bark' ? 0.35 : 1);
  cache.set(key, m);
  return m;
}

/** A fresh (non-cached) patched standard material, e.g. for things whose emissive changes. */
export function stdMat(p: THREE.MeshStandardMaterialParameters): THREE.MeshStandardMaterial {
  return patchRoomMask(new THREE.MeshStandardMaterial(p));
}

export function allCachedMaterials() {
  return [...cache.values()];
}

/* ------------------------------------------------------------------ */
/* Spectral material: ghosts, hands, wisps. Unlit, noisy, x-ray in vision */
/* ------------------------------------------------------------------ */

const SPECTRAL_VS = /* glsl */ `
  uniform float uTime;
  uniform float uWobble;
  varying vec3 vN;
  varying vec3 vWorld;
  varying vec3 vView;
  varying float vH;
  void main() {
    vec3 p = position;
    float w = sin(p.y * 6.0 + uTime * 2.3) * 0.5 + sin(p.y * 13.0 - uTime * 3.1) * 0.25;
    p.xz += normal.xz * w * uWobble;
    vH = position.y;
    vec4 wp = modelMatrix * vec4(p, 1.0);
    vWorld = wp.xyz;
    vN = normalize(mat3(modelMatrix) * normal);
    vView = cameraPosition - wp.xyz;
    gl_Position = projectionMatrix * viewMatrix * wp;
  }
`;

const SPECTRAL_FS = /* glsl */ `
  uniform float uTime;
  uniform float uVision;
  uniform float uAlpha;
  uniform vec3 uColor;
  uniform vec3 uRim;
  uniform vec3 uVisionColor;
  uniform float uNoise;
  uniform float uXray;
  varying vec3 vN;
  varying vec3 vWorld;
  varying vec3 vView;
  varying float vH;
  float hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
  float noise(vec3 x) {
    vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash(i + vec3(0,0,0)), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
               mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
  }
  void main() {
    vec3 V = normalize(vView);
    float fres = pow(1.0 - abs(dot(normalize(vN), V)), 2.2);
    float n = noise(vWorld * 3.5 + vec3(0.0, -uTime * 0.8, uTime * 0.3));
    float n2 = noise(vWorld * 9.0 + vec3(uTime * 0.5));
    float holes = smoothstep(uNoise, uNoise + 0.25, n * 0.7 + n2 * 0.3);
    float dist = length(vView);
    vec3 col = mix(uColor, uRim, fres);
    float a = uAlpha * holes * (0.55 + fres * 0.6);
    // in cat vision: glowing cyan silhouette, visible through walls within range
    vec3 vcol = uVisionColor * (0.6 + fres * 2.2) * (0.7 + n2 * 0.6);
    float va = (0.35 + fres * 0.9) * holes * smoothstep(14.0, 4.0, dist);
    col = mix(col, vcol, uVision);
    a = mix(a, max(a, va), uVision);
    if (a < 0.01) discard;
    gl_FragColor = vec4(col, clamp(a, 0.0, 1.0));
  }
`;

export interface SpectralOpts {
  color?: string;
  rim?: string;
  vision?: string;
  alpha?: number;
  noise?: number;
  wobble?: number;
  additive?: boolean;
}

export function spectralMat(o: SpectralOpts = {}) {
  const m = new THREE.ShaderMaterial({
    uniforms: {
      uTime: Shared.time,
      uVision: { value: 0 },
      uAlpha: { value: o.alpha ?? 0.9 },
      uColor: { value: new THREE.Color(o.color ?? '#020203') },
      uRim: { value: new THREE.Color(o.rim ?? '#1a1d22') },
      uVisionColor: { value: new THREE.Color(o.vision ?? '#5ff6ff') },
      uNoise: { value: o.noise ?? 0.25 },
      uWobble: { value: o.wobble ?? 0.02 },
      uXray: { value: 0 },
    },
    vertexShader: SPECTRAL_VS,
    fragmentShader: SPECTRAL_FS,
    transparent: true,
    depthWrite: false,
    side: THREE.DoubleSide,
    blending: o.additive ? THREE.AdditiveBlending : THREE.NormalBlending,
  });
  spectralRegistry.add(m);
  return m;
}

/** All spectral materials; vision toggles x-ray on each. */
export const spectralRegistry = new Set<THREE.ShaderMaterial>();

export function updateSpectral(vision: number) {
  for (const m of spectralRegistry) {
    m.uniforms.uVision.value = vision;
    const xray = vision > 0.5;
    if (m.depthTest === xray) {
      m.depthTest = !xray;
      m.needsUpdate = true;
    }
  }
}

/* Glow sprite-ish additive material for cyan "investigation" marks visible only in vision */
export function markMat(tex: THREE.Texture, color = '#6ff8ff') {
  const m = new THREE.MeshBasicMaterial({
    map: tex,
    color,
    transparent: true,
    opacity: 0,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
    polygonOffset: true,
    polygonOffsetFactor: -2,
  });
  return m;
}
