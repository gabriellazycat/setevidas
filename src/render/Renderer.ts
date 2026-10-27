import * as THREE from 'three';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/examples/jsm/postprocessing/OutputPass.js';
import { ShaderPass } from 'three/examples/jsm/postprocessing/ShaderPass.js';
import { Settings, type Quality } from '../core/Settings';

const FinalShader = {
  uniforms: {
    tDiffuse: { value: null as THREE.Texture | null },
    uRes: { value: new THREE.Vector2(1, 1) },
    uTime: { value: 0 },
    uFear: { value: 0 },
    uVision: { value: 0 },
    uGrain: { value: 1 },
    uCA: { value: 0 },
    uFade: { value: 0 },
    uBright: { value: 1 },
    uDistort: { value: 0 },
    uVignette: { value: 0 },
    uFlash: { value: 0 },
    uFlashColor: { value: new THREE.Color(1, 0.95, 0.9) },
    uTint: { value: new THREE.Vector3(1, 1, 1) },
    uLift: { value: new THREE.Vector3(0, 0, 0) },
    uSat: { value: 1 },
    uLetterbox: { value: 0 },
    uHunt: { value: 0 },
    uPulse: { value: 0 },
  },
  vertexShader: /* glsl */ `
    varying vec2 vUv;
    void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }
  `,
  fragmentShader: /* glsl */ `
    uniform sampler2D tDiffuse;
    uniform vec2 uRes;
    uniform float uTime, uFear, uVision, uGrain, uCA, uFade, uBright, uDistort, uVignette, uFlash, uSat, uLetterbox, uHunt, uPulse;
    uniform vec3 uTint, uLift, uFlashColor;
    varying vec2 vUv;
    float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
    float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }
    vec3 tex(vec2 uv) { return texture2D(tDiffuse, uv).rgb; }
    void main() {
      vec2 uv = vUv;
      vec2 cc = uv - 0.5;
      float r2 = dot(cc, cc);
      // scare distortion
      uv += cc * r2 * uDistort * 0.5;
      uv.x += sin(uv.y * 38.0 + uTime * 27.0) * 0.0025 * uDistort;
      float ca = (0.0008 + uCA * 0.01 + uFear * 0.0018 + uVision * 0.0015) * (0.3 + r2 * 2.5);
      vec3 col;
      col.r = tex(uv + cc * ca).r;
      col.g = tex(uv).g;
      col.b = tex(uv - cc * ca).b;

      // ---- cat vision: desaturated, edges glow, spectral cyan preserved
      if (uVision > 0.001) {
        vec2 px = 1.5 / uRes;
        float tl = luma(tex(uv + px * vec2(-1.0, 1.0)));
        float t  = luma(tex(uv + px * vec2( 0.0, 1.0)));
        float tr = luma(tex(uv + px * vec2( 1.0, 1.0)));
        float l  = luma(tex(uv + px * vec2(-1.0, 0.0)));
        float r  = luma(tex(uv + px * vec2( 1.0, 0.0)));
        float bl = luma(tex(uv + px * vec2(-1.0,-1.0)));
        float b  = luma(tex(uv + px * vec2( 0.0,-1.0)));
        float br = luma(tex(uv + px * vec2( 1.0,-1.0)));
        float gx = -tl - 2.0 * l - bl + tr + 2.0 * r + br;
        float gy = -tl - 2.0 * t - tr + bl + 2.0 * b + br;
        float edge = sqrt(gx * gx + gy * gy);
        float lum = luma(col);
        vec3 v = vec3(pow(lum, 0.8) * 0.85 + 0.03) * vec3(0.62, 0.74, 0.95);
        v += vec3(0.30, 0.72, 0.85) * smoothstep(0.04, 0.35, edge) * 0.55;
        float cyan = smoothstep(0.08, 0.3, col.b - col.r) * smoothstep(0.15, 0.45, col.g);
        v = mix(v, col * 1.25, cyan);
        // breathing pulse on the edges of the screen
        float pulse = 0.5 + 0.5 * sin(uTime * 3.0);
        v *= 1.0 - smoothstep(0.25, 0.75, sqrt(r2) * 1.35) * (0.55 + 0.1 * pulse);
        col = mix(col, v, uVision);
      }

      // ---- fear: color drains, the house goes cold
      float lum = luma(col);
      float sat = uSat * (1.0 - uFear * 0.8);
      col = mix(vec3(lum), col, sat);
      col *= mix(vec3(1.0), vec3(0.86, 0.93, 1.08), uFear);

      // grading
      col = col * uTint + uLift;
      col = pow(max(col, 0.0), vec3(1.0 / uBright));

      // vignette
      float vd = length(cc * vec2(1.0, 0.82));
      float vig = 1.0 - smoothstep(0.32 - uVignette * 0.18, 0.9 - uVignette * 0.25, vd);
      col *= mix(1.0, vig, 0.6 + uVignette * 0.4);
      // hunted: the edges go red and the world beats with the heart
      float edge = smoothstep(0.28, 0.85, vd);
      col = mix(col, col * vec3(1.15, 0.42, 0.4) + vec3(0.2, 0.0, 0.0) * edge, uHunt * edge);
      col *= 1.0 - uPulse * (0.08 + 0.18 * edge);
      col = mix(vec3(luma(col)), col, 1.0 - uHunt * 0.35);

      // grain (stronger in darks) + dither
      float g = hash(uv * uRes + fract(uTime * 13.7) * 91.0) - 0.5;
      col += g * uGrain * (0.035 + 0.055 * (1.0 - clamp(luma(col) * 2.0, 0.0, 1.0)));
      col += (hash(uv * uRes * 1.37 + 3.1) - 0.5) / 255.0;

      col = mix(col, uFlashColor, uFlash);
      // cinematic bars
      float bar = step(abs(uv.y - 0.5), 0.5 - uLetterbox * 0.11);
      col *= bar;
      col *= 1.0 - uFade;
      gl_FragColor = vec4(col, 1.0);
    }
  `,
};

export class GameRenderer {
  renderer: THREE.WebGLRenderer;
  composer: EffectComposer;
  renderPass: RenderPass;
  bloom: UnrealBloomPass;
  output: OutputPass;
  final: ShaderPass;
  private quality: Quality = 'high';
  private target: THREE.WebGLRenderTarget;
  scale = 1;

  constructor(container: HTMLElement, scene: THREE.Scene, camera: THREE.PerspectiveCamera) {
    this.renderer = new THREE.WebGLRenderer({
      antialias: false,
      powerPreference: 'high-performance',
      stencil: false,
    });
    const r = this.renderer;
    r.outputColorSpace = THREE.SRGBColorSpace;
    r.toneMapping = THREE.ACESFilmicToneMapping;
    r.toneMappingExposure = 1.0;
    r.shadowMap.enabled = true;
    r.shadowMap.type = THREE.PCFShadowMap;
    r.domElement.id = 'game-canvas';
    container.appendChild(r.domElement);

    this.target = new THREE.WebGLRenderTarget(1, 1, { type: THREE.HalfFloatType, samples: 4 });
    this.composer = new EffectComposer(r, this.target);
    this.renderPass = new RenderPass(scene, camera);
    this.bloom = new UnrealBloomPass(new THREE.Vector2(512, 512), 0.22, 0.35, 2.6);
    this.output = new OutputPass();
    this.final = new ShaderPass(FinalShader);
    this.composer.addPass(this.renderPass);
    this.composer.addPass(this.bloom);
    this.composer.addPass(this.output);
    this.composer.addPass(this.final);

    this.applySettings();
    Settings.onChange(() => this.applySettings());
    window.addEventListener('resize', () => this.resize());
  }

  get u() {
    return this.final.uniforms as unknown as typeof FinalShader.uniforms;
  }

  applySettings() {
    const s = Settings.data;
    this.quality = s.quality;
    const dprCap = { low: 0.75, medium: 1, high: 1.25, ultra: 2 }[s.quality];
    this.scale = Math.min(window.devicePixelRatio || 1, dprCap) * s.renderScale;
    this.bloom.enabled = s.bloom && s.quality !== 'low';
    const samples = { low: 0, medium: 2, high: 4, ultra: 4 }[s.quality];
    if (this.target.samples !== samples) {
      this.target.samples = samples;
      this.composer.renderTarget1.samples = samples;
      this.composer.renderTarget2.samples = samples;
      this.target.dispose();
    }
    this.renderer.shadowMap.type = THREE.PCFShadowMap;
    this.u.uGrain.value = s.grain ? 1 : 0;
    this.u.uBright.value = s.brightness;
    this.resize();
  }

  shadowSize() {
    return { low: 1024, medium: 1024, high: 2048, ultra: 4096 }[this.quality];
  }

  resize() {
    const w = window.innerWidth;
    const h = window.innerHeight;
    this.renderer.setPixelRatio(this.scale);
    this.renderer.setSize(w, h);
    this.composer.setPixelRatio(this.scale);
    this.composer.setSize(w, h);
    this.bloom.resolution.set(w * this.scale * 0.5, h * this.scale * 0.5);
    this.u.uRes.value.set(w * this.scale, h * this.scale);
    this.onResize?.(w, h);
  }

  onResize?: (w: number, h: number) => void;

  render(dt: number) {
    this.u.uTime.value += dt;
    this.composer.render(dt);
  }
}
