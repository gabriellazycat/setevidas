import * as THREE from 'three';
import type { World } from '../game/World';
import type { NavNode } from '../world/NavGraph';
import { roomAt } from '../world/NavGraph';
import { ROOM_BY_ID } from '../world/Layout';
import { spectralMat } from '../render/Materials';
import { clamp, damp, dampAngle, rand, lerp } from '../core/math';

export type HoundState = 'absent' | 'tracking' | 'hunting' | 'chasing' | 'lurking' | 'searching' | 'recoil';

/** build the spectral dog */
function makeHoundMesh() {
  const g = new THREE.Group();
  const m = spectralMat({ color: '#030203', rim: '#34100c', vision: '#ff6a55', alpha: 0.96, noise: 0.14, wobble: 0.02 });
  const parts: THREE.Mesh[] = [];
  const add = (geo: THREE.BufferGeometry, x: number, y: number, z: number, parent: THREE.Object3D = g) => {
    const mesh = new THREE.Mesh(geo, m);
    mesh.position.set(x, y, z);
    parent.add(mesh);
    parts.push(mesh);
    return mesh;
  };
  const torso = add(new THREE.CapsuleGeometry(0.2, 0.5, 4, 10), 0, 0.66, 0);
  torso.rotation.x = Math.PI / 2;
  torso.scale.set(1, 1, 1.05);
  add(new THREE.SphereGeometry(0.2, 10, 8), 0, 0.7, 0.34);
  // head
  const head = new THREE.Group();
  head.position.set(0, 0.85, 0.52);
  g.add(head);
  add(new THREE.BoxGeometry(0.24, 0.22, 0.3), 0, 0, 0.06, head);
  add(new THREE.BoxGeometry(0.15, 0.12, 0.26), 0, -0.04, 0.3, head);
  for (const sx of [-1, 1]) {
    const ear = add(new THREE.ConeGeometry(0.06, 0.18, 4), sx * 0.09, 0.17, -0.02, head);
    ear.rotation.z = -sx * 0.25;
  }
  const eyeMat = new THREE.MeshBasicMaterial({ color: new THREE.Color('#ff3a1a').multiplyScalar(6), transparent: true, opacity: 0.95, fog: false });
  const eyes: THREE.Mesh[] = [];
  for (const sx of [-1, 1]) {
    const e = new THREE.Mesh(new THREE.SphereGeometry(0.022, 8, 6), eyeMat);
    e.position.set(sx * 0.07, 0.04, 0.2);
    e.scale.set(1.3, 0.8, 0.6);
    head.add(e);
    eyes.push(e);
  }
  // tail
  const tail = add(new THREE.ConeGeometry(0.05, 0.45, 5), 0, 0.78, -0.55);
  tail.rotation.x = -1.0;
  // legs
  const legs: { hip: THREE.Group; knee: THREE.Group; front: boolean; phase: number }[] = [];
  for (const [x, z, front, ph] of [
    [-0.13, 0.36, true, 0],
    [0.13, 0.36, true, 0.5],
    [-0.13, -0.38, false, 0.5],
    [0.13, -0.38, false, 0],
  ] as const) {
    const hip = new THREE.Group();
    hip.position.set(x, 0.58, z);
    g.add(hip);
    add(new THREE.CylinderGeometry(0.06, 0.045, 0.32, 6), 0, -0.16, 0, hip);
    const knee = new THREE.Group();
    knee.position.y = -0.31;
    hip.add(knee);
    add(new THREE.CylinderGeometry(0.045, 0.035, 0.3, 6), 0, -0.15, 0, knee);
    add(new THREE.SphereGeometry(0.055, 7, 5), 0, -0.3, 0.03, knee).scale.set(1, 0.6, 1.4);
    legs.push({ hip, knee, front, phase: ph });
  }
  g.scale.setScalar(1.12);
  g.userData = { mat: m, eyeMat, head, tail, legs, eyes };
  return g;
}

interface HoundEvents {
  onCaught?: (hound: Hound) => void;
  onSight?: () => void;
}

/**
 * O Cão Fantasma — the cat's own enemy. It hunts the *cat*, never the people.
 * It is a rare, telegraphed presence (signs → hunt → short chase) governed by a budget in the
 * Director, so the game never becomes "just run". The cat can: hide, climb onto furniture, use the
 * duct / window, or hiss it away at close range. Being caught never kills: the cat is flung,
 * dazed and drained, and the household hears the cry.
 */
export class Hound {
  group: THREE.Group;
  state: HoundState = 'absent';
  enabled = false;
  pos = new THREE.Vector3(0, -50, 0);
  yaw = 0;
  events: HoundEvents = {};

  /** the Director clears this while a ghost is attacking someone */
  mayHunt = true;
  night = 1;
  huntsDone = 0;
  maxHunts = 3;
  cooldown = 40;
  /** seconds spent hunting this night (for the balance check) */
  huntTime = 0;
  catches = 0;

  private stateT = 0;
  private awareness = 0;
  private lastKnown = new THREE.Vector3();
  private path: THREE.Vector3[] = [];
  private pi = 0;
  private segFrom = new THREE.Vector3();
  private vis = 0;
  private gait = 0;
  private growlT = 0;
  private sniffT = 0;
  private clawsT = 0;
  private windup = 0;
  private lunge = 0;
  private lungeCd = 0;
  private lostT = 0;
  private immune = 0;
  private giveUpT = -1;
  private hearT = 0;
  private repathT = 0;
  private catHiddenSince = 0;

  constructor(private w: World) {
    this.group = makeHoundMesh();
    this.group.visible = false;
    w.scene.add(this.group);
  }

  /* ------------------------------------------------------------ control */

  startNight(n: number, speedScale = 1) {
    this.night = n;
    this.enabled = true;
    this.huntsDone = 0;
    this.huntTime = 0;
    this.catches = 0;
    this.maxHunts = n <= 2 ? 3 : n <= 4 ? 3 : 4;
    this.cooldown = (n === 2 ? 28 : 55) / speedScale + rand(0, 14);
    this.setState('absent');
  }

  stop() {
    this.enabled = false;
    this.setState('absent');
    this.group.visible = false;
  }

  /** how hunted the cat should feel, 0..1 */
  threatLevel() {
    switch (this.state) {
      case 'tracking':
        return clamp(0.12 + this.awareness * 0.4);
      case 'hunting':
        return 0.65;
      case 'chasing':
        return 1;
      case 'lurking':
        return 0.85;
      case 'searching':
        return 0.4;
      default:
        return 0;
    }
  }

  get active() {
    return this.state !== 'absent';
  }

  get hunting() {
    return this.state === 'hunting' || this.state === 'chasing' || this.state === 'lurking';
  }

  private canClimb() {
    return this.night >= 6;
  }

  private setState(s: HoundState) {
    const prev = this.state;
    this.state = s;
    this.stateT = 0;
    this.lostT = 0;
    if (s === 'absent') {
      this.group.visible = false;
      this.pos.set(0, -50, 0);
      this.path = [];
    }
    if (s === 'tracking') {
      this.awareness = 0;
      this.spawn();
      this.w.introduce('hound');
    }
    if (s === 'hunting' && prev !== 'hunting') {
      this.huntsDone++;
      this.windup = 1.3;
      this.w.audio.growl(this.pos.clone().add(new THREE.Vector3(0, 0.6, 0)), 0.9, 1.6);
      this.w.audio.sting(0.35);
      this.w.fx.shake(0.25);
    }
    if (s === 'chasing') {
      this.lungeCd = 1.2;
      this.w.audio.bark(this.pos.clone().add(new THREE.Vector3(0, 0.6, 0)), 0.7);
    }
  }

  /** leaves the cat alone for a while */
  private leave(extra = 0) {
    this.cooldown = rand(45, 70) + extra;
    this.setState('absent');
  }

  /** something more urgent is happening, or the cat is safe: retreat quickly */
  giveUp() {
    if (this.hunting && this.giveUpT < 0) this.giveUpT = 2.2;
  }

  /** forced calm: skip the rest of this night's budget quickly */
  pauseFor(sec: number) {
    this.cooldown = Math.max(this.cooldown, sec);
  }

  /* ------------------------------------------------------------ sensing */

  hearNoise(p: THREE.Vector3, loud: number, kind: string) {
    if (!this.enabled || this.state === 'absent' || this.state === 'recoil') return;
    const d = this.pos.distanceTo(p);
    const reach = this.state === 'tracking' ? 10 : 18;
    if (d > reach) return;
    const cat = this.w.cat;
    // only noise made by (or around) the cat matters to it, thrown objects are lures
    const gain = (kind === 'run' ? 0.5 : kind === 'meow' ? 0.9 : kind === 'break' ? 1.6 : kind === 'thud' ? 0.9 : 0.6) * loud;
    if (this.state === 'tracking') {
      if (cat.mode !== 'hidden') this.awareness += gain * (1 - d / (reach + 2)) * 0.9;
      this.lastKnown.copy(p);
    } else if (this.state === 'searching' || this.state === 'hunting') {
      this.lastKnown.copy(p);
      this.lostT = 0;
      if (this.state === 'searching') {
        this.state = 'hunting';
        this.stateT = 0;
        this.windup = 0.4;
        this.go(this.lastKnown);
      }
    } else if (this.state === 'lurking') this.stateT = Math.max(0, this.stateT - 1);
  }

  private los() {
    const cat = this.w.cat;
    if (cat.mode === 'hidden') return false;
    const a = this.pos.clone().add(new THREE.Vector3(0, 0.65, 0));
    const b = cat.pos.clone().add(new THREE.Vector3(0, 0.2, 0));
    if (Math.abs(this.pos.y - cat.pos.y) > 2.2) return false;
    return !this.w.house.col.blocked(a, b);
  }

  /** the cat is on something tall: the hound cannot reach it */
  private catIsHigh() {
    const cat = this.w.cat;
    const room = roomAt(cat.pos);
    if (!room) return false;
    return cat.pos.y - ROOM_BY_ID[room].y > 0.62;
  }

  /* ------------------------------------------------------------ movement */

  private spawn() {
    const w = this.w;
    const nav = w.house.nav;
    const cat = w.cat;
    const catRoom = roomAt(cat.pos);
    const cands: NavNode[] = [];
    for (const n of nav.nodes.values()) {
      if (n.p.y > 2.5 && !this.canClimb()) continue;
      if (n.room === 'sotao') continue;
      const d = n.p.distanceTo(cat.pos);
      if (d < 8 || n.room === catRoom) continue;
      cands.push(n);
    }
    const pick = cands.length ? cands[Math.floor(Math.random() * cands.length)] : nav.get('b_porao_mid');
    this.pos.copy(pick.p);
    this.yaw = Math.atan2(cat.pos.x - this.pos.x, cat.pos.z - this.pos.z);
    this.lastKnown.copy(cat.pos);
    this.group.visible = true;
    this.go(cat.pos);
  }

  private go(dest: THREE.Vector3) {
    const nav = this.w.house.nav;
    const a = nav.nearest(this.pos);
    const b = nav.nearest(dest);
    const climb = this.canClimb();
    let nodes = nav.route(a, b, false, (n) => (n.p.y > 2.5 && !climb ? 400 : 0));
    if (!climb) {
      const idx = nodes.findIndex((n) => n.p.y > 2.5);
      if (idx >= 0) nodes = nodes.slice(0, idx);
    }
    this.path = nodes.map((n) => n.p.clone());
    if (this.path.length && this.path[this.path.length - 1].distanceTo(b.p) < 0.05 && dest.y - b.p.y < 1.5 && (climb || dest.y < 2.5)) {
      const end = dest.clone();
      end.y = b.p.y;
      this.path.push(end);
    }
    // skip a first node that lies behind us
    if (this.path.length > 1) {
      const d0 = this.pos.distanceTo(this.path[1]);
      const d01 = this.path[0].distanceTo(this.path[1]);
      if (d0 < d01 && Math.abs(this.pos.y - this.path[0].y) < 0.6) this.path.shift();
    }
    this.pi = 0;
    this.segFrom.copy(this.pos);
  }

  /** follow the current path; returns true when it is finished */
  private follow(dt: number, speed: number, stopDist = 0) {
    const t = this.path[this.pi];
    if (!t) return true;
    const dx = t.x - this.pos.x;
    const dz = t.z - this.pos.z;
    const dist = Math.hypot(dx, dz);
    const last = this.pi === this.path.length - 1;
    if (dist < 0.1 || (last && stopDist > 0 && this.pos.distanceTo(this.lastKnown) < stopDist)) {
      this.pi++;
      this.segFrom.copy(this.pos);
      return this.pi >= this.path.length;
    }
    const step = Math.min(dist, speed * dt);
    this.pos.x += (dx / dist) * step;
    this.pos.z += (dz / dist) * step;
    const segLen = Math.hypot(t.x - this.segFrom.x, t.z - this.segFrom.z);
    const done = segLen > 1e-3 ? 1 - dist / segLen : 1;
    this.pos.y = this.segFrom.y + (t.y - this.segFrom.y) * clamp(done);
    this.yaw = dampAngle(this.yaw, Math.atan2(dx, dz), 9, dt);
    this.gait += step * 5.2;
    return false;
  }

  /* ------------------------------------------------------------ update */

  update(dt: number) {
    const w = this.w;
    const cat = w.cat;
    if (!this.enabled) {
      this.updateVisual(dt, 0);
      return;
    }
    this.immune = Math.max(0, this.immune - dt);
    this.lungeCd = Math.max(0, this.lungeCd - dt);
    this.stateT += dt;
    if (this.hunting) this.huntTime += dt;

    // an attack on the household takes priority: the hound backs off
    if (!this.mayHunt) {
      if (this.hunting) this.giveUp();
      if (this.state === 'tracking') this.leave(8);
    }
    if (this.giveUpT >= 0) {
      this.giveUpT -= dt;
      if (this.giveUpT < 0) {
        this.giveUpT = -1;
        if (this.hunting || this.state === 'searching') this.leave();
      }
    }

    switch (this.state) {
      case 'absent': {
        this.cooldown -= dt;
        if (this.cooldown <= 0 && this.huntsDone < this.maxHunts && this.mayHunt && cat.mode !== 'frozen') this.setState('tracking');
        break;
      }
      case 'tracking': {
        // prowls toward the cat's area but keeps its distance until it has caught the scent
        const d = this.pos.distanceTo(cat.pos);
        this.repathT -= dt;
        if (this.repathT <= 0) {
          this.repathT = 3;
          this.go(cat.pos);
        }
        const hold = 7.5 - this.awareness * 3;
        if (d > hold) this.follow(dt, 1.35);
        else this.gait += dt * 1.2;
        this.signs(dt, d);
        // being seen or heard raises awareness, sneaking and hiding reduce it
        let up = 0;
        const sneakK = cat.sneaking ? 0.25 : 1;
        if (cat.mode !== 'hidden') {
          if (d < 9 && this.los()) up += 0.2;
          if (cat.running) up += 0.22 * (d < 12 ? 1 : 0.3);
          up *= sneakK;
        }
        this.awareness = clamp(this.awareness + up * dt - 0.03 * dt);
        if (this.awareness >= 1 && this.mayHunt) {
          this.lastKnown.copy(cat.pos);
          this.setState('hunting');
        } else if (this.stateT > 26) this.leave();
        break;
      }
      case 'hunting': {
        if (this.windup > 0) {
          // freezes and growls: the tell before it comes
          this.windup -= dt;
          this.signs(dt, this.pos.distanceTo(cat.pos), true);
          break;
        }
        const d = this.pos.distanceTo(cat.pos);
        if (this.los() && d < 9) {
          this.lastKnown.copy(cat.pos);
          this.lostT = 0;
          if (d < 7) {
            this.setState('chasing');
            break;
          }
        } else this.lostT += dt;
        this.repathT -= dt;
        if (this.repathT <= 0) {
          this.repathT = 1.2;
          this.go(this.lastKnown);
        }
        this.follow(dt, 2.4);
        this.signs(dt, d);
        if (this.lostT > 9 || this.stateT > 22) this.setState('searching');
        break;
      }
      case 'chasing':
        this.chase(dt);
        break;
      case 'lurking': {
        // cannot reach: circles, growls, then loses interest
        const d = this.pos.distanceTo(cat.pos);
        if (!this.catIsHigh() || cat.mode === 'hidden') {
          this.setState(cat.mode === 'hidden' ? 'searching' : 'chasing');
          break;
        }
        const ang = this.stateT * 0.8;
        const target = cat.pos.clone().add(new THREE.Vector3(Math.cos(ang) * 1.1, 0, Math.sin(ang) * 1.1));
        target.y = this.pos.y;
        const to = target.sub(this.pos);
        if (to.length() > 0.1) this.pos.addScaledVector(to.normalize(), Math.min(1.8 * dt, to.length()));
        this.yaw = dampAngle(this.yaw, Math.atan2(cat.pos.x - this.pos.x, cat.pos.z - this.pos.z), 6, dt);
        this.gait += dt * 3;
        this.growlT -= dt;
        if (this.growlT <= 0) {
          this.growlT = 2.4;
          w.audio.growl(this.pos.clone().add(new THREE.Vector3(0, 0.6, 0)), 0.7, 1.4);
        }
        void d;
        if (this.stateT > 7) this.setState('searching');
        break;
      }
      case 'searching': {
        // goes to where it last sensed the cat and sniffs around
        if (cat.mode === 'hidden') this.catHiddenSince += dt;
        else this.catHiddenSince = 0;
        if (this.path.length === 0 || this.pi >= this.path.length) {
          this.sniffT -= dt;
          if (this.sniffT <= 0) {
            this.sniffT = 1.3;
            w.audio.sniff(this.pos.clone().add(new THREE.Vector3(0, 0.4, 0)), 0.45);
          }
          this.gait += dt * 0.6;
          this.yaw += Math.sin(this.stateT * 1.4) * dt * 1.2;
        } else {
          this.follow(dt, 1.7);
          this.signs(dt, this.pos.distanceTo(cat.pos));
        }
        // a noise or a glimpse brings the hunt back
        if (cat.mode !== 'hidden' && this.los() && this.pos.distanceTo(cat.pos) < 6 && !this.catIsHigh()) this.setState('chasing');
        else if (this.stateT > (cat.mode === 'hidden' ? 8.5 : 7)) this.leave();
        break;
      }
      case 'recoil': {
        // stunned by a hiss
        this.gait += dt * 0.2;
        if (this.stateT > 2.4) this.setState('searching');
        break;
      }
    }
    // keep the dog on the floor under it
    if (this.state !== 'absent') {
      const ground = w.house.col.groundHeight(this.pos.x, this.pos.z, this.pos.y + 0.5, 0.15);
      if (ground > -500 && Math.abs(ground - this.pos.y) < 0.6 && this.state !== 'tracking') this.pos.y = damp(this.pos.y, ground, 14, dt);
    }
    const showAmt = this.state === 'absent' ? 0 : this.state === 'tracking' ? 0.35 + this.awareness * 0.5 : 1;
    this.updateVisual(dt, showAmt);
  }

  private chase(dt: number) {
    const w = this.w;
    const cat = w.cat;
    const d = this.pos.distanceTo(cat.pos);
    const los = this.los();
    if (cat.mode === 'hidden') {
      // it saw the cat slip away
      this.lastKnown.copy(cat.pos);
      this.go(this.lastKnown);
      this.setState('searching');
      return;
    }
    if (this.catIsHigh() && d < 3.2) {
      this.setState('lurking');
      return;
    }
    if (los) {
      this.lastKnown.copy(cat.pos);
      this.lostT = 0;
    } else this.lostT += dt;
    if (this.lostT > 6 || this.stateT > 26) {
      this.setState('searching');
      this.go(this.lastKnown);
      return;
    }
    // the cat left through the duct / window or fled upstairs: it cannot follow
    if (!this.canClimb() && cat.pos.y > 2.6) {
      if (this.stateT > 6) this.leave();
      this.gait += dt * 2;
      return;
    }
    const speed = this.lunge > 0 ? 8.5 : 4.25;
    if (los && d < 9 && Math.abs(cat.pos.y - this.pos.y) < 1.2) {
      const dir = new THREE.Vector3(cat.pos.x - this.pos.x, 0, cat.pos.z - this.pos.z);
      const dl = dir.length();
      if (dl > 0.01) {
        dir.divideScalar(dl);
        this.pos.addScaledVector(dir, Math.min(dl, speed * dt));
        this.yaw = dampAngle(this.yaw, Math.atan2(dir.x, dir.z), 11, dt);
        this.gait += speed * dt * 5.2;
        w.house.col.resolveCylinder(this.pos, 0.28, 0.7, 0.3);
      }
    } else {
      this.repathT -= dt;
      if (this.repathT <= 0) {
        this.repathT = 0.8;
        this.go(this.lastKnown);
      }
      this.follow(dt, speed);
    }
    // lunge with a telegraph: crouch + bark, then a short burst
    if (this.lunge > 0) this.lunge -= dt;
    if (this.windup > 0) {
      this.windup -= dt;
      if (this.windup <= 0) {
        this.lunge = 0.5;
        this.lungeCd = 2.5;
      }
    } else if (d < 2.6 && los && this.lungeCd <= 0 && this.lunge <= 0) {
      this.windup = 0.4;
      w.audio.growl(this.pos.clone().add(new THREE.Vector3(0, 0.5, 0)), 0.8, 0.5);
    }
    this.clawsT -= dt;
    if (this.clawsT <= 0) {
      this.clawsT = 0.16;
      w.audio.claws(this.pos, 0.45);
    }
    // caught
    if (d < 0.55 && Math.abs(cat.pos.y - this.pos.y) < 0.7 && this.immune <= 0 && cat.stunT <= 0) {
      this.catches++;
      this.immune = 10;
      this.events.onCaught?.(this);
      this.cooldown = rand(50, 70);
      this.setState('absent');
    }
  }

  /** claws, sniffs and a distant growl */
  private signs(dt: number, distToCat: number, still = false) {
    const w = this.w;
    const near = this.pos.clone().add(new THREE.Vector3(0, 0.4, 0));
    this.clawsT -= dt;
    if (!still && this.clawsT <= 0) {
      this.clawsT = this.state === 'tracking' ? 0.55 : 0.3;
      w.audio.claws(this.pos, this.state === 'tracking' ? 0.3 : 0.4);
    }
    this.sniffT -= dt;
    if (this.sniffT <= 0) {
      this.sniffT = rand(3.5, 5.5);
      w.audio.sniff(near, 0.35);
    }
    this.growlT -= dt;
    if (this.growlT <= 0) {
      this.growlT = this.state === 'tracking' ? rand(7, 10) : rand(2.8, 4);
      w.audio.growl(near, this.state === 'tracking' ? 0.45 : 0.8, 1.4);
    }
    void distToCat;
  }

  /* ------------------------------------------------------------ reactions */

  canHiss(p: THREE.Vector3) {
    return (this.state === 'chasing' || this.state === 'hunting' || this.state === 'lurking') && p.distanceTo(this.pos) < 1.5 && Math.abs(p.y - this.pos.y) < 1.0;
  }

  onHiss(p: THREE.Vector3, strong: boolean) {
    if (!strong || !this.canHiss(p)) return false;
    this.w.audio.growl(this.pos.clone().add(new THREE.Vector3(0, 0.6, 0)), 0.5, 0.6);
    this.w.audio.shriek(this.pos.clone().add(new THREE.Vector3(0, 0.6, 0)), 0.25);
    this.lunge = 0;
    this.windup = 0;
    this.setState('recoil');
    this.immune = Math.max(this.immune, 3);
    return true;
  }

  /** the cat used the duct / window: it loses the trail */
  catVanished() {
    if (this.hunting) {
      this.lostT = 99;
      this.setState('searching');
    }
  }

  /* ------------------------------------------------------------ visual */

  private updateVisual(dt: number, amt: number) {
    this.vis = damp(this.vis, amt, 5, dt);
    const g = this.group;
    g.visible = this.vis > 0.02 && this.state !== 'absent';
    if (!g.visible) return;
    const u = g.userData;
    (u.mat as THREE.ShaderMaterial).uniforms.uAlpha.value = 0.96 * this.vis;
    const eyes = u.eyeMat as THREE.MeshBasicMaterial;
    eyes.opacity = clamp(this.vis * 1.4) * (this.state === 'chasing' ? 1 : 0.85);
    g.position.copy(this.pos);
    g.rotation.y = this.yaw;
    // gait
    const moving = this.state === 'chasing' || this.state === 'hunting' || this.state === 'tracking' || (this.state === 'searching' && this.pi < this.path.length) ? 1 : 0.15;
    const crouch = this.windup > 0 || this.state === 'recoil' ? 1 : 0;
    const ph = this.gait;
    for (const L of u.legs as { hip: THREE.Group; knee: THREE.Group; front: boolean; phase: number }[]) {
      const a = Math.sin(ph + L.phase * Math.PI * 2) * 0.7 * moving;
      L.hip.rotation.x = a + crouch * (L.front ? 0.5 : -0.4);
      L.knee.rotation.x = Math.max(0, -Math.sin(ph + L.phase * Math.PI * 2 + 1.2)) * 0.9 * moving + crouch * 0.6;
    }
    const head = u.head as THREE.Group;
    head.position.y = lerp(0.85, 0.62, crouch);
    head.rotation.x = crouch * 0.45 + (this.state === 'searching' && this.pi >= this.path.length ? 0.6 + Math.sin(this.stateT * 6) * 0.1 : 0);
    g.rotation.x = this.lunge > 0 ? -0.2 : 0;
    (u.tail as THREE.Mesh).rotation.z = Math.sin(performance.now() * 0.004) * 0.3;
  }

  focus() {
    return this.state === 'absent' ? null : this.pos.clone().add(new THREE.Vector3(0, 0.6, 0));
  }
}
