import * as THREE from 'three';
import { ARCHES, DOORS, LIGHTS, ROOM_BY_ID, STAIR_BASE, STAIR_MAIN, type LightDef, type RoomId } from './Layout';
import { RM_REGIONS, RoomMask, mat, stdMat } from '../render/Materials';
import { clamp, damp, noise1, rand } from '../core/math';
import { roomAt } from './NavGraph';
import type { Door } from './Doors';

interface Spill {
  min: THREE.Vector3;
  max: THREE.Vector3;
  gain: () => number;
}

export class RoomLight {
  light: THREE.PointLight;
  on = false;
  level = 0;
  /** 0..1: how strongly the light misbehaves */
  flicker = 0;
  private flickerT = 0;
  private flickSeed = Math.random() * 100;
  bulbMats: THREE.MeshBasicMaterial[] = [];
  glowMats: THREE.MeshStandardMaterial[] = [];
  lever: THREE.Object3D | null = null;
  indicator: THREE.MeshBasicMaterial | null = null;
  switchPos: THREE.Vector3 | null = null;
  switchNormal: THREE.Vector3 | null = null;
  baseColor: THREE.Color;
  /** burnt by the Shadow: cannot be lit until this timer ends */
  dead = 0;
  scale = 1;
  /** seconds of light left (only counts at night); lamps last longer than ceiling bulbs */
  life = 0;
  warn = 0;

  constructor(
    public def: LightDef,
    public group: THREE.Group,
  ) {
    this.light = new THREE.PointLight(def.color, 0, def.distance, 2);
    this.light.position.set(...def.pos);
    this.light.castShadow = false;
    this.baseColor = new THREE.Color(def.color);
    group.add(this.light);
  }

  get room(): RoomId | null {
    return this.def.room === 'exterior' || this.def.room === 'dynamic' ? null : (this.def.room as RoomId);
  }

  /** ceiling bulbs burn out quickly, lamps last longer */
  get ticks() {
    return this.def.room !== 'dynamic' && this.def.room !== 'exterior';
  }

  setOn(on: boolean) {
    if (on && this.dead > 0) return false;
    if (on && !this.on) this.life = this.def.fixture === 'lamp' ? rand(28, 45) : rand(10, 20);
    if (!on) this.warn = 0;
    this.on = on;
    if (this.lever) this.lever.rotation.x = on ? -0.45 : 0.45;
    return true;
  }

  update(dt: number, ambientFlicker: number) {
    if (this.dead > 0) this.dead -= dt;
    this.flickerT += dt;
    let target = this.on ? 1 : 0;
    const fl = Math.max(this.flicker, this.warn, this.on ? ambientFlicker : 0);
    if (this.on && fl > 0.001) {
      const n = noise1(this.flickerT * (8 + fl * 22) + this.flickSeed);
      const n2 = noise1(this.flickerT * 3.1 + this.flickSeed * 2);
      if (n < fl * 0.75) target = 0.04;
      else target = 1 - fl * 0.35 * n2;
    }
    this.level = damp(this.level, target, target > this.level ? 28 : 16, dt);
    this.light.intensity = this.def.intensity * this.level * this.scale;
    for (const m of this.bulbMats) m.color.copy(this.baseColor).multiplyScalar(0.06 + this.level * 3.3);
    for (const m of this.glowMats) m.emissiveIntensity = this.level * 0.55;
    if (this.indicator) this.indicator.color.setRGB(0.9, 0.55, 0.2).multiplyScalar(this.on ? 0.25 : 1.6);
  }
}

/** Builds fixtures and owns all point lights (fixed count, fixed order). */
export class LightSystem {
  lights: RoomLight[] = [];
  byRoom = new Map<RoomId, RoomLight>();
  group = new THREE.Group();
  ambientFlicker = 0;
  onToggle?: (l: RoomLight, on: boolean) => void;

  constructor(parent: THREE.Object3D) {
    parent.add(this.group);
    for (const def of LIGHTS) {
      const rl = new RoomLight(def, this.group);
      this.lights.push(rl);
      this.buildFixture(rl);
      if (def.sw) this.buildSwitch(rl);
      if (def.room !== 'exterior' && def.room !== 'dynamic' && def.fixture !== 'lamp') this.byRoom.set(def.room, rl);
      this.setMaskForDef(rl);
    }
  }

  get(index: number) {
    return this.lights[index];
  }

  private setMaskForDef(rl: RoomLight) {
    const d = rl.def;
    if (d.room === 'exterior') {
      this.setMask(d.index, new THREE.Vector3(-30, -1.2, -40), new THREE.Vector3(40, 14, -0.1));
    } else if (d.room === 'dynamic') {
      this.setMask(d.index, new THREE.Vector3(1e5, 1e5, 1e5), new THREE.Vector3(-1e5, -1e5, -1e5));
    } else {
      this.setRoomMask(d.index, d.room);
    }
  }

  setRoomMask(index: number, room: RoomId) {
    const r = ROOM_BY_ID[room];
    this.setMask(index, new THREE.Vector3(r.x0, r.y - 0.05, r.z0), new THREE.Vector3(r.x1, r.y + r.h + 0.06, r.z1));
  }

  setMask(index: number, min: THREE.Vector3, max: THREE.Vector3) {
    this.setRegion(index, 0, min, max, 1);
  }

  setRegion(index: number, k: number, min: THREE.Vector3, max: THREE.Vector3, gain: number) {
    const i = index * RM_REGIONS + k;
    RoomMask.min.value[i].set(min.x, min.y, min.z, gain);
    RoomMask.max.value[i].set(max.x, max.y, max.z, 0);
  }

  clearRegion(index: number, k: number) {
    const i = index * RM_REGIONS + k;
    RoomMask.min.value[i].set(1e5, 1e5, 1e5, 0);
    RoomMask.max.value[i].set(-1e5, -1e5, -1e5, 0);
  }

  /** where each room light may leak: through open doors, arches and stairwells */
  private spills = new Map<number, Spill[]>();

  setupSpills(doors: Map<string, Door>) {
    const D = 3.4;
    const V = (x: number, y: number, z: number) => new THREE.Vector3(x, y, z);
    const lightsOf = (room: RoomId) => this.lights.filter((l) => l.def.room === room).map((l) => l.def.index);
    const add = (idx: number[], sp: Spill) => {
      for (const i of idx) {
        let arr = this.spills.get(i);
        if (!arr) this.spills.set(i, (arr = []));
        arr.push(sp);
      }
    };
    const opening = (axis: 'x' | 'z', fixed: number, s0: number, s1: number, y: number, door: Door | null) => {
      const lo = axis === 'z' ? V(fixed - 0.4, y + 1, (s0 + s1) / 2) : V((s0 + s1) / 2, y + 1, fixed - 0.4);
      const hi = axis === 'z' ? V(fixed + 0.4, y + 1, (s0 + s1) / 2) : V((s0 + s1) / 2, y + 1, fixed + 0.4);
      const ra = roomAt(lo);
      const rb = roomAt(hi);
      if (!ra || !rb || ra === rb) return;
      const A = ROOM_BY_ID[ra];
      const B = ROOM_BY_ID[rb];
      const gain = () => (door ? clamp((door.angle - 0.2) / 0.8) : 1);
      const boxIn = (R: typeof A, from: 'neg' | 'pos') => {
        // region inside room R, starting at the opening and reaching D metres away
        if (axis === 'z') {
          const x0 = from === 'pos' ? fixed : Math.max(R.x0, fixed - D);
          const x1 = from === 'pos' ? Math.min(R.x1, fixed + D) : fixed;
          return { min: V(x0, R.y - 0.05, Math.max(R.z0, s0 - 1)), max: V(x1, R.y + R.h + 0.06, Math.min(R.z1, s1 + 1)) };
        }
        const z0 = from === 'pos' ? fixed : Math.max(R.z0, fixed - D);
        const z1 = from === 'pos' ? Math.min(R.z1, fixed + D) : fixed;
        return { min: V(Math.max(R.x0, s0 - 1), R.y - 0.05, z0), max: V(Math.min(R.x1, s1 + 1), R.y + R.h + 0.06, z1) };
      };
      add(lightsOf(ra), { ...boxIn(B, 'pos'), gain });
      add(lightsOf(rb), { ...boxIn(A, 'neg'), gain });
    };
    for (const d of DOORS) opening(d.axis, d.fixed, d.s0, d.s1, d.y, doors.get(d.id) ?? null);
    for (const a of ARCHES) opening(a.axis, a.fixed, a.s0, a.s1, a.y0, null);
    // stairwells connect floors
    const fixedGain = () => 0.8;
    add(lightsOf('hall'), { min: V(STAIR_MAIN.x0, 2.9, STAIR_MAIN.z0), max: V(STAIR_MAIN.x1, 5.8, STAIR_MAIN.z1), gain: fixedGain });
    add(lightsOf('corredor'), { min: V(STAIR_MAIN.x0, -0.05, STAIR_MAIN.z0), max: V(STAIR_MAIN.x1, 2.86, STAIR_MAIN.z1), gain: fixedGain });
    add(lightsOf('lavanderia'), { min: V(STAIR_BASE.x0, -0.05, STAIR_BASE.z0), max: V(STAIR_BASE.x1, 2.86, STAIR_BASE.z1), gain: fixedGain });
    add(lightsOf('cozinha'), { min: V(STAIR_BASE.x0, -3.05, STAIR_BASE.z0), max: V(STAIR_BASE.x1, -0.15, STAIR_BASE.z1), gain: fixedGain });
  }

  private updateSpills() {
    for (const [idx, list] of this.spills) {
      if (!this.lights[idx].on && this.lights[idx].level < 0.01) {
        for (let k = 1; k < RM_REGIONS; k++) this.clearRegion(idx, k);
        continue;
      }
      const scored = list.map((sp) => ({ sp, g: sp.gain() })).filter((e) => e.g > 0.01);
      scored.sort((a, b) => b.g - a.g);
      for (let k = 1; k < RM_REGIONS; k++) {
        const e = scored[k - 1];
        if (e) this.setRegion(idx, k, e.sp.min, e.sp.max, e.g);
        else this.clearRegion(idx, k);
      }
    }
  }

  private bulbMat(rl: RoomLight) {
    const m = new THREE.MeshBasicMaterial({ color: rl.def.color });
    rl.bulbMats.push(m);
    return m;
  }

  private buildFixture(rl: RoomLight) {
    const d = rl.def;
    const [x, y, z] = d.pos;
    const g = this.group;
    const ceilingY = (() => {
      if (d.room === 'exterior' || d.room === 'dynamic') return y;
      const r = ROOM_BY_ID[d.room];
      return r.y + r.h;
    })();
    const cord = (len: number) => {
      const c = new THREE.Mesh(new THREE.CylinderGeometry(0.006, 0.006, len, 4), mat('plastic_black'));
      c.position.set(x, ceilingY - len / 2, z);
      g.add(c);
    };
    if (d.fixture === 'bulb') {
      cord(ceilingY - y - 0.05);
      const b = new THREE.Mesh(new THREE.SphereGeometry(0.045, 12, 10), this.bulbMat(rl));
      b.position.set(x, y, z);
      g.add(b);
      const sock = new THREE.Mesh(new THREE.CylinderGeometry(0.02, 0.024, 0.05, 8), mat('brass'));
      sock.position.set(x, y + 0.055, z);
      g.add(sock);
    } else if (d.fixture === 'pendant') {
      cord(ceilingY - y - 0.12);
      const shadeMat = stdMat({ color: '#d9c49a', roughness: 0.8, side: THREE.DoubleSide, emissive: new THREE.Color('#ffb066'), emissiveIntensity: 0 });
      rl.glowMats.push(shadeMat);
      const shade = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.26, 0.22, 20, 1, true), shadeMat);
      shade.position.set(x, y + 0.08, z);
      shade.castShadow = true;
      g.add(shade);
      const b = new THREE.Mesh(new THREE.SphereGeometry(0.05, 12, 10), this.bulbMat(rl));
      b.position.set(x, y, z);
      g.add(b);
    } else if (d.fixture === 'flush') {
      const base = new THREE.Mesh(new THREE.CylinderGeometry(0.2, 0.2, 0.03, 20), mat('plastic_white'));
      base.position.set(x, ceilingY - 0.015, z);
      g.add(base);
      const dome = new THREE.Mesh(new THREE.SphereGeometry(0.18, 20, 10, 0, Math.PI * 2, Math.PI / 2, Math.PI / 2), this.bulbMat(rl));
      dome.position.set(x, ceilingY - 0.03, z);
      g.add(dome);
    } else if (d.fixture === 'chandelier') {
      cord(0.45);
      const body = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.06, 0.14, 10), mat('brass'));
      body.position.set(x, ceilingY - 0.5, z);
      g.add(body);
      for (let i = 0; i < 5; i++) {
        const a = (i / 5) * Math.PI * 2;
        const ax = x + Math.cos(a) * 0.28;
        const az = z + Math.sin(a) * 0.28;
        const arm = new THREE.Mesh(new THREE.CylinderGeometry(0.008, 0.008, 0.3, 4), mat('brass'));
        arm.position.set((x + ax) / 2, ceilingY - 0.52, (z + az) / 2);
        arm.rotation.z = Math.PI / 2;
        arm.rotation.y = -a;
        g.add(arm);
        const cup = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.018, 0.04, 8), mat('brass'));
        cup.position.set(ax, ceilingY - 0.5, az);
        g.add(cup);
        const b = new THREE.Mesh(new THREE.SphereGeometry(0.026, 10, 8), this.bulbMat(rl));
        b.scale.y = 1.6;
        b.position.set(ax, ceilingY - 0.44, az);
        g.add(b);
      }
    } else if (d.fixture === 'lamp') {
      // bedside lamp, sits on the nightstand (top at y ~ 3.55)
      const baseY = 3.55;
      const base = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.07, 0.04, 14), mat('brass'));
      base.position.set(x, baseY + 0.02, z);
      g.add(base);
      const body = new THREE.Mesh(new THREE.SphereGeometry(0.07, 14, 10), mat('ceramic'));
      body.scale.y = 1.3;
      body.position.set(x, baseY + 0.12, z);
      g.add(body);
      const shadeMat = stdMat({ color: '#e8d2a8', roughness: 0.85, side: THREE.DoubleSide, emissive: new THREE.Color('#ffa253'), emissiveIntensity: 0 });
      rl.glowMats.push(shadeMat);
      const shade = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.15, 0.17, 18, 1, true), shadeMat);
      shade.position.set(x, baseY + 0.33, z);
      g.add(shade);
      const b = new THREE.Mesh(new THREE.SphereGeometry(0.03, 10, 8), this.bulbMat(rl));
      b.position.set(x, baseY + 0.3, z);
      g.add(b);
    } else if (d.fixture === 'street') {
      const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.09, y + 0.9, 8), mat('metal_dark'));
      pole.position.set(x, (y - 0.9) / 2, z);
      pole.castShadow = true;
      g.add(pole);
      const arm = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.06, 0.7), mat('metal_dark'));
      arm.position.set(x, y + 0.25, z + 0.3);
      g.add(arm);
      const head = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.22, 0.18, 10), mat('metal_dark'));
      head.position.set(x, y + 0.12, z + 0.6);
      g.add(head);
      const b = new THREE.Mesh(new THREE.SphereGeometry(0.09, 10, 8), this.bulbMat(rl));
      b.scale.y = 0.5;
      b.position.set(x, y + 0.02, z + 0.6);
      g.add(b);
      rl.light.position.set(x, y - 0.1, z + 0.6);
    }
  }

  private buildSwitch(rl: RoomLight) {
    const sw = rl.def.sw!;
    const p = new THREE.Vector3(...sw.p);
    const n = new THREE.Vector3(...sw.n);
    rl.switchPos = p.clone();
    rl.switchNormal = n.clone();
    const grp = new THREE.Group();
    grp.position.copy(p);
    grp.lookAt(p.clone().add(n));
    const plate = new THREE.Mesh(new THREE.BoxGeometry(0.075, 0.115, 0.012), mat('plastic_beige'));
    grp.add(plate);
    const lever = new THREE.Mesh(new THREE.BoxGeometry(0.016, 0.036, 0.022), mat('plastic_white'));
    lever.position.z = 0.012;
    lever.rotation.x = 0.45;
    grp.add(lever);
    // tiny glowing locator dot (real switches have them; helps find them in the dark)
    const ind = new THREE.MeshBasicMaterial({ color: '#ff9a40' });
    const dot = new THREE.Mesh(new THREE.SphereGeometry(0.006, 6, 4), ind);
    dot.position.set(0, -0.04, 0.008);
    grp.add(dot);
    rl.lever = lever;
    rl.indicator = ind;
    this.group.add(grp);
  }

  /** bulbs burn out on their own while this is on (night) */
  lifetimes = false;
  onWarn?: (l: RoomLight) => void;
  onBurnOut?: (l: RoomLight) => void;

  update(dt: number) {
    if (this.lifetimes) {
      for (const l of this.lights) {
        if (!l.ticks || !l.on) continue;
        l.life -= dt;
        if (l.life < 3.2 && l.life > 0) {
          if (l.warn === 0) this.onWarn?.(l);
          l.warn = 0.55 + 0.4 * (1 - l.life / 3.2);
        }
        if (l.life <= 0) {
          l.setOn(false);
          l.dead = 1.4;
          l.warn = 0;
          this.onBurnOut?.(l);
        }
      }
    }
    for (const l of this.lights) l.update(dt, this.ambientFlicker);
    this.updateSpills();
  }

  /** Turn everything on/off (used by phases). */
  setAll(on: boolean, except: number[] = []) {
    for (const l of this.lights) {
      if (l.def.room === 'dynamic' || except.includes(l.def.index)) continue;
      if (l.def.room === 'exterior') continue;
      l.dead = 0;
      l.setOn(on);
    }
  }

  toggle(rl: RoomLight) {
    const ok = rl.setOn(!rl.on);
    if (ok) this.onToggle?.(rl, rl.on);
    return ok;
  }

  isRoomLit(room: RoomId) {
    const l = this.byRoom.get(room);
    let lit = !!l && l.on && l.level > 0.5;
    if (room === 'quarto') {
      const lamp = this.lights[8];
      lit = lit || (lamp.on && lamp.level > 0.5);
    }
    return lit;
  }

  randomJitter() {
    return rand(0.9, 1.1);
  }
}
