import * as THREE from 'three';
import type { AudioEngine, LoopHandle } from '../audio/Audio';
import { Shared } from './Materials';
import { Settings } from '../core/Settings';
import { damp, rand } from '../core/math';

export interface NightWeather {
  wind: number;
  rain: number;
  /** average seconds between lightning bolts (0 = none) */
  bolts: number;
}

/** how each night feels outside */
export const WEATHER: Record<number, NightWeather> = {
  1: { wind: 0.4, rain: 0, bolts: 0 },
  2: { wind: 0.5, rain: 0, bolts: 0 },
  3: { wind: 0.6, rain: 0.4, bolts: 70 },
  4: { wind: 0.7, rain: 0.6, bolts: 55 },
  5: { wind: 0.8, rain: 0.75, bolts: 45 },
  6: { wind: 1.0, rain: 1.0, bolts: 28 },
  7: { wind: 0.9, rain: 0.85, bolts: 22 },
};
export const CLEAR_DAY: NightWeather = { wind: 0.18, rain: 0, bolts: 0 };

const COUNT = 2600;

/** Wind, rain and lightning. Rain is drawn as streaks that follow the camera and never fall indoors. */
export class Weather {
  rain = 0;
  private target: NightWeather = CLEAR_DAY;
  private streaks: THREE.LineSegments;
  private mat: THREE.ShaderMaterial;
  private rainLoop: LoopHandle | null = null;
  private boltT = 30;
  private flashT = 0;
  private pending: { at: number; power: number }[] = [];
  private clock = 0;
  /** extra directional light energy for a bolt (decays), consumed by the game */
  boost = 0;
  onFlash?: (power: number) => void;

  constructor(
    scene: THREE.Scene,
    private audio: AudioEngine,
  ) {
    const base: number[] = [];
    const tip: number[] = [];
    for (let i = 0; i < COUNT; i++) {
      const x = Math.random() * 36;
      const y = Math.random() * 18;
      const z = Math.random() * 36;
      base.push(x, y, z, x, y, z);
      tip.push(0, 1);
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(base, 3));
    g.setAttribute('base', new THREE.Float32BufferAttribute(base, 3));
    g.setAttribute('tip', new THREE.Float32BufferAttribute(tip, 1));
    this.mat = new THREE.ShaderMaterial({
      uniforms: {
        uCam: { value: new THREE.Vector3() },
        uTime: Shared.time,
        uRain: { value: 0 },
        uWind: Shared.wind,
      },
      vertexShader: /* glsl */ `
        attribute vec3 base;
        attribute float tip;
        uniform vec3 uCam;
        uniform float uTime;
        uniform float uWind;
        varying vec3 vW;
        void main() {
          vec3 box = vec3(36.0, 18.0, 36.0);
          vec3 p = base;
          p.y -= uTime * (13.0 + fract(base.x * 13.7) * 7.0);
          p = mod(p - uCam + box * 0.5, box) - box * 0.5 + uCam;
          p.x += tip * 0.14 * (0.4 + uWind);
          p.y += tip * 0.6;
          vW = p;
          gl_Position = projectionMatrix * viewMatrix * vec4(p, 1.0);
        }
      `,
      fragmentShader: /* glsl */ `
        uniform float uRain;
        varying vec3 vW;
        void main() {
          // never indoors: the whole house footprint (and its roof) is dry
          if (vW.x > -0.3 && vW.x < 12.3 && vW.z > -0.3 && vW.z < 10.3 && vW.y < 9.5) discard;
          if (vW.y < -0.9) discard;
          gl_FragColor = vec4(0.62, 0.74, 0.95, uRain * 0.3);
        }
      `,
      transparent: true,
      depthWrite: false,
      fog: false,
    });
    this.streaks = new THREE.LineSegments(g, this.mat);
    this.streaks.frustumCulled = false;
    this.streaks.renderOrder = 6;
    scene.add(this.streaks);
  }

  setWeather(w: NightWeather) {
    this.target = w;
    this.boltT = w.bolts > 0 ? rand(w.bolts * 0.3, w.bolts) : 999;
    if (w.rain > 0 && !this.rainLoop) this.rainLoop = this.audio.loop('rain', null, { bus: 'amb' });
  }

  /** an immediate storm bolt (scripted moments) */
  bolt(power = 1) {
    this.flashT = 0.0;
    this.pending.push({ at: 0, power });
    this.audio.thunder(rand(0.5, 2.8), power);
  }

  update(dt: number, camera: THREE.Camera, indoors: boolean) {
    this.clock += dt;
    const w = this.target;
    this.rain = damp(this.rain, w.rain, 0.6, dt);
    // gusty wind: slow swells on top of the base strength
    const gust = 0.6 + 0.4 * Math.sin(this.clock * 0.21) * Math.sin(this.clock * 0.07 + 1.3);
    Shared.wind.value = damp(Shared.wind.value, w.wind * gust, 1.2, dt);
    this.mat.uniforms.uCam.value.copy(camera.position);
    this.mat.uniforms.uRain.value = this.rain;
    this.streaks.visible = this.rain > 0.02;
    this.rainLoop?.setLevel(this.rain * (indoors ? 0.28 : 0.7));
    // lightning
    if (w.bolts > 0) {
      this.boltT -= dt;
      if (this.boltT <= 0) {
        this.boltT = rand(w.bolts * 0.5, w.bolts * 1.3);
        const power = rand(0.6, 1);
        this.pending.push({ at: 0, power });
        if (Math.random() < 0.4) this.pending.push({ at: 0.22, power: power * 0.7 });
        this.audio.thunder(rand(0.4, 3.2), power);
      }
    }
    this.boost = damp(this.boost, 0, 14, dt);
    for (let i = this.pending.length - 1; i >= 0; i--) {
      const p = this.pending[i];
      p.at -= dt;
      if (p.at <= 0) {
        this.pending.splice(i, 1);
        this.boost = Math.max(this.boost, p.power * (Settings.data.reduceFlashes ? 0.35 : 1));
        this.onFlash?.(p.power);
      }
    }
  }
}
