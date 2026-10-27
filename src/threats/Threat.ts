import * as THREE from 'three';
import type { World, ThreatId } from '../game/World';
import type { Owner } from '../actors/Owner';
import { spectralMat } from '../render/Materials';
import { textures } from '../render/Textures';
import { rand } from '../core/math';

export abstract class Threat {
  abstract readonly id: ThreatId;
  abstract readonly name: string;
  stage = 0;
  t = 0;
  cooldown = 0;
  enabled = false;
  /** set by the director: may this threat go to stage 4+ right now? */
  mayAttack = true;
  stall = 0;

  /** who this threat is after (picked when it wakes up) */
  target: Owner;

  constructor(protected w: World) {
    this.target = w.owner;
  }

  protected fearAll(v: number) {
    for (const o of this.w.household.present) o.addFear(v);
  }

  /** Seconds scaled by the night's speed. */
  protected d(sec: number) {
    return sec / Math.max(0.3, this.w.speed);
  }

  enable(delay: number) {
    this.enabled = true;
    this.reset();
    this.cooldown = delay;
  }

  disable() {
    this.enabled = false;
    this.reset();
  }

  protected setStage(s: number) {
    if (s === this.stage) return;
    const prev = this.stage;
    this.stage = s;
    this.t = 0;
    if (prev === 0 && s === 1) {
      this.target = this.w.pickTarget(this.id);
      this.w.introduce(this.id);
    }
    this.onStage(s, prev);
  }

  /** Called when the cat banishes it. */
  protected repel(cool?: number) {
    this.w.repelled(this.id);
    this.reset();
    this.cooldown = cool ?? this.d(rand(32, 55));
  }

  update(dt: number) {
    if (!this.enabled) return;
    if (this.stall > 0) {
      this.stall -= dt;
      this.tickStalled(dt);
      return;
    }
    if (this.stage === 0) {
      this.cooldown -= dt;
      if (this.cooldown <= 0) this.setStage(1);
      return;
    }
    this.t += dt;
    this.tick(dt);
  }

  protected tickStalled(_dt: number) {}

  abstract reset(): void;
  protected abstract tick(dt: number): void;
  protected onStage(_s: number, _prev: number) {}
  /** where the cat should go (ears point here) */
  abstract focus(): THREE.Vector3 | null;
  /** the visible entity, if any (for fur bristle) */
  entity(): THREE.Vector3 | null {
    return null;
  }
  /** cat hissed nearby; return true if it affected this threat */
  onHiss(_p: THREE.Vector3, _strong: boolean): boolean {
    return false;
  }
  urgency() {
    return this.stage / 5;
  }
  /** shown on the defeat screen */
  describeDeath(): { title: string; why: string; tip: string } {
    return {
      title: `${this.target.name} foi levado(a)`,
      why: `${this.name} chegou até ${this.target.name}.`,
      tip: 'Fique de olho nos sinais sonoros e resolva a ameaça antes que ela chegue.',
    };
  }
  /** would a hiss from here do something? (drives the on-screen "Bufar" prompt) */
  canHiss(_p: THREE.Vector3): boolean {
    return false;
  }
  /** fear-free check: is it close to attacking */
  get attacking() {
    return this.stage >= 4;
  }
}

/* ------------------------------------------------------------ shared visuals */

/** Tall thin humanoid silhouette with long arms. */
export function makeSilhouette(height = 1.95, opts: { color?: string; rim?: string; vision?: string; alpha?: number; noise?: number } = {}) {
  const g = new THREE.Group();
  const m = spectralMat({ color: opts.color ?? '#010102', rim: opts.rim ?? '#141820', vision: opts.vision, alpha: opts.alpha ?? 0.95, noise: opts.noise ?? 0.18, wobble: 0.03 });
  const s = height / 1.95;
  const pts: THREE.Vector2[] = [];
  const prof = [
    [0.0, 0],
    [0.09, 0.05],
    [0.13, 0.5],
    [0.16, 0.95],
    [0.2, 1.35],
    [0.17, 1.5],
    [0.06, 1.6],
    [0.07, 1.62],
    [0.11, 1.72],
    [0.1, 1.85],
    [0.0, 1.95],
  ];
  for (const [x, y] of prof) pts.push(new THREE.Vector2(x * s, y * s));
  const body = new THREE.Mesh(new THREE.LatheGeometry(pts, 14), m);
  g.add(body);
  for (const side of [-1, 1]) {
    const arm = new THREE.Mesh(new THREE.CylinderGeometry(0.025 * s, 0.045 * s, 1.15 * s, 6), m);
    arm.position.set(side * 0.24 * s, 0.92 * s, 0.04);
    arm.rotation.z = side * 0.12;
    g.add(arm);
    const fingers = new THREE.Mesh(new THREE.ConeGeometry(0.04 * s, 0.22 * s, 5), m);
    fingers.position.set(side * 0.31 * s, 0.25 * s, 0.05);
    fingers.rotation.x = Math.PI;
    g.add(fingers);
  }
  const eyeMat = new THREE.MeshBasicMaterial({ color: new THREE.Color('#e8f0ff').multiplyScalar(5), transparent: true, opacity: 0.85 });
  for (const side of [-1, 1]) {
    const e = new THREE.Mesh(new THREE.SphereGeometry(0.012 * s, 6, 4), eyeMat);
    e.position.set(side * 0.035 * s, 1.78 * s, 0.09 * s);
    g.add(e);
  }
  g.userData.mat = m;
  g.userData.eyes = eyeMat;
  return g;
}

/** Soft smoke/wisp particles around an entity. */
export class Wisps {
  points: THREE.Points;
  private vel: Float32Array;
  private life: Float32Array;
  private mat: THREE.PointsMaterial;
  constructor(
    parent: THREE.Object3D,
    private count = 40,
    color = '#000000',
    size = 0.25,
    private spread = 0.35,
    additive = false,
  ) {
    const pos = new Float32Array(count * 3);
    this.vel = new Float32Array(count * 3);
    this.life = new Float32Array(count);
    for (let i = 0; i < count; i++) this.life[i] = Math.random();
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    this.mat = new THREE.PointsMaterial({
      color,
      size,
      map: textures().dot,
      transparent: true,
      opacity: 0.6,
      depthWrite: false,
      blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending,
      sizeAttenuation: true,
    });
    this.points = new THREE.Points(g, this.mat);
    this.points.frustumCulled = false;
    parent.add(this.points);
  }
  set opacity(v: number) {
    this.mat.opacity = v;
    this.points.visible = v > 0.01;
  }
  update(dt: number, origin: THREE.Vector3, height = 1.8) {
    const pos = this.points.geometry.getAttribute('position') as THREE.BufferAttribute;
    for (let i = 0; i < this.count; i++) {
      this.life[i] += dt * 0.6;
      if (this.life[i] > 1) {
        this.life[i] = 0;
        pos.setXYZ(i, origin.x + rand(-this.spread, this.spread), origin.y + rand(0, height), origin.z + rand(-this.spread, this.spread));
        this.vel[i * 3] = rand(-0.1, 0.1);
        this.vel[i * 3 + 1] = rand(0.05, 0.35);
        this.vel[i * 3 + 2] = rand(-0.1, 0.1);
      } else {
        pos.setXYZ(i, pos.getX(i) + this.vel[i * 3] * dt, pos.getY(i) + this.vel[i * 3 + 1] * dt, pos.getZ(i) + this.vel[i * 3 + 2] * dt);
      }
    }
    pos.needsUpdate = true;
  }
}
