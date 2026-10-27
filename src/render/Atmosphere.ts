import * as THREE from 'three';
import { Shared } from './Materials';
import { textures } from './Textures';
import { clamp, rand } from '../core/math';

interface PointsCfg {
  count: number;
  size: number;
  color: string;
  opacity: number;
  additive?: boolean;
}

/** Soft-sprite particle layer driven by a CPU update (counts are small). */
class Layer {
  pos: Float32Array;
  vel: Float32Array;
  life: Float32Array;
  max: Float32Array;
  pts: THREE.Points;
  mat: THREE.PointsMaterial;
  constructor(cfg: PointsCfg) {
    this.pos = new Float32Array(cfg.count * 3);
    this.vel = new Float32Array(cfg.count * 3);
    this.life = new Float32Array(cfg.count);
    this.max = new Float32Array(cfg.count).fill(1);
    for (let i = 0; i < cfg.count; i++) this.pos[i * 3 + 1] = -999;
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(this.pos, 3));
    this.mat = new THREE.PointsMaterial({
      map: textures().dot,
      size: cfg.size,
      color: cfg.color,
      opacity: cfg.opacity,
      transparent: true,
      depthWrite: false,
      blending: cfg.additive ? THREE.AdditiveBlending : THREE.NormalBlending,
      sizeAttenuation: true,
      fog: false,
    });
    this.pts = new THREE.Points(g, this.mat);
    this.pts.frustumCulled = false;
    this.pts.renderOrder = 5;
  }
  dirty() {
    (this.pts.geometry.attributes.position as THREE.BufferAttribute).needsUpdate = true;
  }
}

/** Fog banks, moths, steam, cold breath and attic ash. */
export class Atmosphere {
  private fog: Layer;
  private moths: Layer;
  private steam: Layer;
  private breath: Layer;
  private ash: Layer;
  private cursor = { steam: 0, breath: 0 };
  private breathT = 0;
  private clock = 0;
  private lampOn = true;

  constructor(scene: THREE.Scene) {
    // ground fog: wide faint blobs drifting along the yard and the basement
    this.fog = new Layer({ count: 70, size: 5.5, color: '#8a98b4', opacity: 0.1 });
    for (let i = 0; i < 70; i++) {
      const basement = i < 22;
      let x: number, z: number, y: number;
      if (basement) {
        x = rand(0.5, 11.5);
        z = rand(0.5, 9.5);
        y = -2.6 + rand(0, 0.5);
      } else {
        do {
          x = rand(-9, 20);
          z = rand(-10, 18);
        } while (x > -0.5 && x < 12.5 && z > -0.5 && z < 10.5);
        y = rand(-0.7, 0.2);
      }
      this.fog.pos.set([x, y, z], i * 3);
      this.fog.vel.set([rand(-0.12, 0.12), 0, rand(-0.12, 0.12)], i * 3);
      this.fog.life[i] = basement ? 1 : 0;
    }
    this.moths = new Layer({ count: 14, size: 0.09, color: '#fff2c0', opacity: 0.9, additive: true });
    for (let i = 0; i < 14; i++) this.moths.life[i] = rand(0, 100);
    this.steam = new Layer({ count: 60, size: 0.35, color: '#dfe8f0', opacity: 0.18 });
    this.breath = new Layer({ count: 24, size: 0.22, color: '#cfe0ff', opacity: 0.2 });
    this.ash = new Layer({ count: 70, size: 0.05, color: '#b8a89a', opacity: 0.55 });
    for (let i = 0; i < 70; i++) {
      this.ash.pos.set([rand(0.3, 7.2), rand(6.1, 8.2), rand(0.3, 9.7)], i * 3);
      this.ash.vel.set([rand(-0.03, 0.03), -rand(0.02, 0.07), rand(-0.03, 0.03)], i * 3);
    }
    for (const l of [this.fog, this.moths, this.steam, this.breath, this.ash]) scene.add(l.pts);
    this.steam.life.fill(0);
    this.breath.life.fill(0);
  }

  /** 0..1 how strongly fog shows (storm nights are foggier) */
  fogAmount = 0.5;

  update(
    dt: number,
    o: { cam: THREE.Vector3; catPos: THREE.Vector3; catDir: THREE.Vector3; fear: number; hunted: number; night: boolean; steamAt: THREE.Vector3[] },
  ) {
    this.clock += dt;
    const t = this.clock;
    // fog
    this.fog.mat.opacity = (o.night ? 0.12 : 0.04) * (0.5 + this.fogAmount);
    for (let i = 0; i < 70; i++) {
      const p = this.fog.pos;
      p[i * 3] += this.fog.vel[i * 3] * dt;
      p[i * 3 + 2] += this.fog.vel[i * 3 + 2] * dt;
      if (this.fog.life[i] > 0.5) {
        if (p[i * 3] < 0.3 || p[i * 3] > 11.7) this.fog.vel[i * 3] *= -1;
        if (p[i * 3 + 2] < 0.3 || p[i * 3 + 2] > 9.7) this.fog.vel[i * 3 + 2] *= -1;
      } else if (p[i * 3] > -0.5 && p[i * 3] < 12.5 && p[i * 3 + 2] > -0.5 && p[i * 3 + 2] < 10.5) {
        // drifted under the house: push back out the nearest side
        this.fog.vel[i * 3] = p[i * 3] < 6 ? -0.15 : 0.15;
        p[i * 3] += this.fog.vel[i * 3] * dt * 20;
      }
    }
    this.fog.dirty();
    this.fog.pts.visible = o.night;

    // moths circling the street lamp
    const m = this.moths;
    for (let i = 0; i < 14; i++) {
      const a = t * (0.9 + (i % 5) * 0.25) + m.life[i];
      const r = 0.35 + 0.25 * Math.sin(m.life[i] * 3 + t * 0.7);
      m.pos[i * 3] = -1.8 + Math.cos(a) * r;
      m.pos[i * 3 + 1] = 4.3 + Math.sin(a * 1.7 + i) * 0.35;
      m.pos[i * 3 + 2] = -7.0 + Math.sin(a) * r;
    }
    m.dirty();
    m.pts.visible = o.night && this.lampOn;

    // steam from running hot water
    const s = this.steam;
    for (const src of o.steamAt) {
      if (Math.random() < dt * 12) {
        const k = this.cursor.steam++ % 60;
        s.pos.set([src.x + rand(-0.1, 0.1), src.y, src.z + rand(-0.1, 0.1)], k * 3);
        s.vel.set([rand(-0.04, 0.04), rand(0.12, 0.25), rand(-0.04, 0.04)], k * 3);
        s.life[k] = 1;
      }
    }
    for (let i = 0; i < 60; i++) {
      if (s.life[i] <= 0) {
        s.pos[i * 3 + 1] = -999;
        continue;
      }
      s.life[i] -= dt * 0.45;
      s.pos[i * 3] += s.vel[i * 3] * dt;
      s.pos[i * 3 + 1] += s.vel[i * 3 + 1] * dt;
      s.pos[i * 3 + 2] += s.vel[i * 3 + 2] * dt;
    }
    s.dirty();

    // cold breath in front of the cat's face when scared
    const b = this.breath;
    const cold = o.fear > 50 || o.hunted > 0.3;
    this.breathT -= dt;
    if (cold && this.breathT <= 0) {
      this.breathT = o.hunted > 0.3 ? 0.35 : 1.1;
      const k = this.cursor.breath++ % 24;
      b.pos.set([o.catPos.x + o.catDir.x * 0.3, o.catPos.y + 0.28, o.catPos.z + o.catDir.z * 0.3], k * 3);
      b.vel.set([o.catDir.x * 0.25, 0.1, o.catDir.z * 0.25], k * 3);
      b.life[k] = 1;
    }
    for (let i = 0; i < 24; i++) {
      if (b.life[i] <= 0) {
        b.pos[i * 3 + 1] = -999;
        continue;
      }
      b.life[i] -= dt * 1.1;
      b.pos[i * 3] += b.vel[i * 3] * dt;
      b.pos[i * 3 + 1] += b.vel[i * 3 + 1] * dt;
      b.pos[i * 3 + 2] += b.vel[i * 3 + 2] * dt;
    }
    b.dirty();

    // attic ash falls and recycles
    const a = this.ash;
    for (let i = 0; i < 70; i++) {
      a.pos[i * 3] += (a.vel[i * 3] + Math.sin(t * 0.5 + i) * 0.02) * dt;
      a.pos[i * 3 + 1] += a.vel[i * 3 + 1] * dt;
      a.pos[i * 3 + 2] += a.vel[i * 3 + 2] * dt;
      if (a.pos[i * 3 + 1] < 6.05) a.pos[i * 3 + 1] = 8.2;
    }
    a.dirty();
    a.pts.visible = o.cam.y > 4.5;
    void clamp;
    void Shared;
  }

  setStreetLamp(on: boolean) {
    this.lampOn = on;
  }
}
