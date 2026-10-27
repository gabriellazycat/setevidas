import * as THREE from 'three';
import { CatModel, defaultPose } from './CatModel';
import type { ColliderWorld } from '../world/Colliders';
import type { Input } from '../core/Input';
import type { Carryable } from '../world/Props';
import { Settings } from '../core/Settings';
import { clamp, damp, dampAngle, lerp, smoothstep } from '../core/math';

const R = 0.14;
const H = 0.3;
const STEP = 0.3;
const G = 22;
const MAX_JUMP = 1.72;

export type CatMode = 'free' | 'purr' | 'scratch' | 'busy' | 'frozen' | 'hidden';

export interface CatEvents {
  step?: (run: boolean, sneak: boolean) => void;
  jump?: (big: boolean) => void;
  land?: (impact: number) => void;
  meow?: () => void;
  hiss?: (strong: boolean) => void;
}

interface Arc {
  from: THREE.Vector3;
  to: THREE.Vector3;
  t: number;
  dur: number;
  h: number;
}

const _v = new THREE.Vector3();
const _f = new THREE.Vector3();

export class Cat {
  model = new CatModel();
  pos = new THREE.Vector3();
  vel = new THREE.Vector3();
  vy = 0;
  yaw = 0;
  grounded = true;
  pose = defaultPose();
  focus = 100;
  vision = 0;
  visionHeld = false;
  visionToggled = false;
  sneaking = false;
  running = false;
  carrying: Carryable | null = null;
  mode: CatMode = 'free';
  /** seconds left of being stunned (caught by the hound): no control */
  stunT = 0;
  knock = new THREE.Vector3();
  /** 0..1 how hunted the cat feels (drives pupils, fur, screen) */
  hunted = 0;
  /** 0..1: standing in water, the floor is slippery */
  slip = 0;
  modeTarget = new THREE.Vector3();
  modeYaw = 0;
  arc: Arc | null = null;
  jumpTarget: THREE.Vector3 | null = null;
  marker: THREE.Mesh;
  events: CatEvents = {};
  /** set by the game each frame */
  earTargetWorld: THREE.Vector3 | null = null;
  alert = 0;
  bristle = 0;
  lockedMovement = false;
  speedScale = 1;
  private meowT = 0;
  private hissT = 0;
  private meowCd = 0;
  private hissCd = 0;
  private visionIdle = 0;
  private idleT = 0;
  private stepAcc = 0;
  private landT = 0;
  private targetHold: THREE.Vector3 | null = null;
  private markerT = 0;

  constructor(scene: THREE.Object3D) {
    scene.add(this.model.root);
    const m = new THREE.Mesh(
      new THREE.RingGeometry(0.11, 0.15, 32),
      new THREE.MeshBasicMaterial({ color: new THREE.Color('#fff2d6').multiplyScalar(1.4), transparent: true, opacity: 0.0, depthWrite: false, side: THREE.DoubleSide }),
    );
    m.rotation.x = -Math.PI / 2;
    m.renderOrder = 10;
    this.marker = m;
    scene.add(m);
  }

  get forward() {
    return _f.set(Math.sin(this.yaw), 0, Math.cos(this.yaw));
  }

  get head() {
    return _v.copy(this.pos).add(new THREE.Vector3(0, 0.3, 0));
  }

  teleport(p: THREE.Vector3, yaw = this.yaw) {
    this.pos.copy(p);
    this.vel.set(0, 0, 0);
    this.vy = 0;
    this.yaw = yaw;
    this.arc = null;
    this.grounded = true;
    this.mode = 'free';
    this.syncModel();
  }

  /** the hound got the cat: flung away, dazed, drained */
  stun(sec: number, from: THREE.Vector3) {
    this.stunT = sec;
    this.focus = Math.max(0, this.focus - 60);
    this.vision = 0;
    this.visionToggled = false;
    this.arc = null;
    this.vy = 0;
    const away = _v.set(this.pos.x - from.x, 0, this.pos.z - from.z);
    if (away.lengthSq() < 1e-4) away.set(Math.sin(this.yaw), 0, Math.cos(this.yaw));
    away.normalize().multiplyScalar(5.5);
    this.knock.copy(away);
    this.vel.set(0, 0, 0);
  }

  meow() {
    if (this.meowCd > 0) return false;
    this.meowCd = 1.1;
    this.meowT = 0.65;
    this.idleT = 0;
    this.events.meow?.();
    return true;
  }

  hiss() {
    if (this.hissCd > 0 || this.carrying?.id === 'doll') return null;
    this.hissCd = 1.3;
    this.hissT = 0.9;
    this.idleT = 0;
    const strong = this.focus >= 22;
    if (strong) this.focus -= 22;
    this.events.hiss?.(strong);
    return strong;
  }

  update(dt: number, input: Input, camYaw: number, col: ColliderWorld, controlsEnabled: boolean) {
    this.meowCd -= dt;
    this.hissCd -= dt;
    this.meowT = Math.max(0, this.meowT - dt);
    this.hissT = Math.max(0, this.hissT - dt);
    this.landT = Math.max(0, this.landT - dt);

    // ------------------------------------------------ input
    let mx = 0;
    let my = 0;
    this.stunT = Math.max(0, this.stunT - dt);
    if (controlsEnabled && this.mode === 'free' && !this.lockedMovement && this.stunT <= 0) {
      mx = input.move.x;
      my = input.move.y;
      if (input.wasPressed('sneak')) {
        if (Settings.data.sneakToggle) this.sneaking = !this.sneaking;
      }
      if (!Settings.data.sneakToggle) this.sneaking = input.isDown('sneak');
      this.running = input.isDown('run') && !this.carrying;
      if (this.running) this.sneaking = false;
    }
    // vision
    if (controlsEnabled) {
      if (Settings.data.visionToggle) {
        if (input.wasPressed('vision')) this.visionToggled = !this.visionToggled;
        this.visionHeld = this.visionToggled;
      } else this.visionHeld = input.isDown('vision');
    } else this.visionHeld = false;
    const visionActive = this.visionHeld && this.focus > 0.5;
    if (visionActive) {
      this.focus = Math.max(0, this.focus - 10 * dt);
      this.visionIdle = 0;
      if (this.focus <= 0.5) this.visionToggled = false;
    } else {
      this.visionIdle += dt;
      if (this.visionIdle > 0.8) this.focus = Math.min(100, this.focus + (this.mode === 'purr' ? 9 : 5.5) * dt);
    }
    this.vision = damp(this.vision, visionActive ? 1 : 0, visionActive ? 7 : 5, dt);

    if (controlsEnabled && this.mode !== 'frozen') {
      if (input.wasPressed('meow')) this.meow();
      if (input.wasPressed('hiss') && this.mode === 'free') this.hiss();
    }

    // camera-relative move
    const fx = Math.sin(camYaw);
    const fz = Math.cos(camYaw);
    const rx = -fz;
    const rz = fx;
    let dx = fx * my + rx * mx;
    let dz = fz * my + rz * mx;
    const mag = Math.min(1, Math.hypot(dx, dz));
    if (mag > 1e-3) {
      const l = Math.hypot(dx, dz);
      dx /= l;
      dz /= l;
    }
    const maxSpeed = (this.sneaking ? 0.95 : this.running ? 4.4 : 2.1) * this.speedScale * (this.carrying ? 0.85 : 1);
    const target = mag * maxSpeed;
    const accel = (target > Math.hypot(this.vel.x, this.vel.z) ? 11 : 9) * lerp(1, 0.28, this.slip);
    this.vel.x = damp(this.vel.x, dx * target, accel, dt);
    this.vel.z = damp(this.vel.z, dz * target, accel, dt);
    const speed = Math.hypot(this.vel.x, this.vel.z);
    if (speed > 0.08 && this.mode === 'free') this.yaw = dampAngle(this.yaw, Math.atan2(this.vel.x, this.vel.z), 12, dt);

    // ------------------------------------------------ modes that pin the cat
    if (this.mode === 'purr' || this.mode === 'scratch' || this.mode === 'busy' || this.mode === 'hidden') {
      this.vel.set(0, 0, 0);
      this.pos.x = damp(this.pos.x, this.modeTarget.x, 8, dt);
      this.pos.y = damp(this.pos.y, this.modeTarget.y, 8, dt);
      this.pos.z = damp(this.pos.z, this.modeTarget.z, 8, dt);
      this.yaw = dampAngle(this.yaw, this.modeYaw, 8, dt);
      this.arc = null;
      this.grounded = true;
      this.vy = 0;
    } else if (this.arc) {
      // ------------------------------------------------ assisted jump arc
      const a = this.arc;
      a.t += dt / a.dur;
      const t = Math.min(1, a.t);
      const e = t;
      this.pos.lerpVectors(a.from, a.to, e);
      this.pos.y += a.h * 4 * t * (1 - t);
      this.vy = (a.to.y - a.from.y) / a.dur + a.h * 4 * (1 - 2 * t) / a.dur;
      this.grounded = false;
      if (t >= 1) {
        this.arc = null;
        this.pos.copy(a.to);
        this.grounded = true;
        this.landT = 0.18;
        this.events.land?.(Math.max(0, -this.vy));
        this.vy = 0;
      }
    } else if (this.mode === 'free') {
      // ------------------------------------------------ walking physics
      this.pos.x += this.vel.x * dt;
      this.pos.z += this.vel.z * dt;
      if (this.knock.lengthSq() > 0.001) {
        this.pos.x += this.knock.x * dt;
        this.pos.z += this.knock.z * dt;
        this.knock.multiplyScalar(Math.max(0, 1 - 5 * dt));
      }
      col.resolveCylinder(this.pos, R, H, STEP);
      const ground = col.groundHeight(this.pos.x, this.pos.z, this.pos.y + STEP, 0.05);
      if (this.grounded) {
        if (ground >= this.pos.y - 0.32) {
          if (ground > this.pos.y) this.pos.y = Math.min(ground, damp(this.pos.y, ground, 30, dt) + 0.01);
          else this.pos.y = ground;
        } else {
          this.grounded = false;
          this.vy = 0;
        }
      } else {
        this.vy -= G * dt;
        this.pos.y += this.vy * dt;
        if (this.pos.y <= ground) {
          const impact = -this.vy;
          this.pos.y = ground;
          this.grounded = true;
          this.vy = 0;
          if (impact > 2) {
            this.landT = 0.18;
            this.events.land?.(impact);
          }
        }
      }
      const ceil = col.ceilingHeight(this.pos.x, this.pos.z, this.pos.y + 0.05, 0.05);
      if (this.pos.y + H > ceil) {
        this.pos.y = Math.max(ground, ceil - H);
        if (this.vy > 0) this.vy = 0;
      }
      // safety: never fall out of the world
      if (this.pos.y < -10) this.pos.set(2.5, 0.05, 3.5);
    }

    // ------------------------------------------------ jump
    this.findJumpTarget(col, mag > 0.1 ? new THREE.Vector3(dx, 0, dz) : null);
    if (controlsEnabled && this.mode === 'free' && input.wasPressed('jump') && this.grounded && !this.arc) {
      if (this.jumpTarget) {
        const to = this.jumpTarget.clone();
        const dist = Math.hypot(to.x - this.pos.x, to.z - this.pos.z);
        const dy = to.y - this.pos.y;
        this.arc = {
          from: this.pos.clone(),
          to,
          t: 0,
          dur: 0.3 + dist * 0.09 + Math.abs(dy) * 0.07,
          h: dy > 0 ? 0.22 + dy * 0.18 : 0.14,
        };
        this.yaw = Math.atan2(to.x - this.pos.x, to.z - this.pos.z);
        this.events.jump?.(dy > 0.6);
      } else {
        this.vy = 3.7;
        this.grounded = false;
        this.pos.y += 0.01;
        this.events.jump?.(false);
      }
      this.idleT = 0;
    }

    // ------------------------------------------------ footsteps
    if (this.grounded && !this.arc && this.mode === 'free' && speed > 0.2) {
      this.stepAcc += speed * dt;
      const stride = this.running ? 0.42 : 0.24;
      if (this.stepAcc > stride) {
        this.stepAcc = 0;
        this.events.step?.(this.running, this.sneaking);
      }
    }

    // ------------------------------------------------ pose
    if (speed > 0.15 || !this.grounded || this.mode !== 'free' || this.alert > 0.5) this.idleT = 0;
    else this.idleT += dt;
    const p = this.pose;
    p.speed = this.mode === 'free' ? speed : 0;
    p.grounded = this.grounded && !this.arc;
    p.vy = this.vy;
    p.run = this.running;
    p.crouch = this.sneaking || this.mode === 'hidden' ? 1 : this.arc && this.arc.t < 0.12 ? 0.6 : 0;
    p.sit = this.mode === 'free' && this.idleT > 2.5 && this.idleT < 25 ? 1 : 0;
    p.lie = this.mode === 'purr' || this.stunT > 0 || (this.mode === 'free' && this.idleT >= 25) ? 1 : 0;
    p.meow = this.meowT > 0 ? 1 : 0;
    p.hiss = this.hissT > 0 ? 1 : 0;
    p.bristle = this.bristle;
    p.tailUp = clamp(this.focus / 100) * (1 - this.bristle * 0.3);
    p.land = this.landT > 0 ? 1 : 0;
    p.purr = this.mode === 'purr' ? 1 : 0;
    p.scratch = this.mode === 'scratch' ? 1 : 0;
    p.carry = !!this.carrying;
    p.pupil = clamp(0.25 + this.vision * 0.75 + this.alert * 0.4 + this.hunted * 0.55);
    p.earAlert = this.alert;
    if (this.earTargetWorld) {
      const ang = Math.atan2(this.earTargetWorld.x - this.pos.x, this.earTargetWorld.z - this.pos.z);
      let rel = ang - this.yaw;
      while (rel > Math.PI) rel -= Math.PI * 2;
      while (rel < -Math.PI) rel += Math.PI * 2;
      p.earYaw = -rel;
      p.headYaw = clamp(-rel * 0.35 * this.alert * (speed < 0.3 ? 1 : 0.3), -0.7, 0.7);
    } else {
      p.earYaw = 0;
      p.headYaw = 0;
    }
    p.headPitch = 0;
    this.syncModel();
    this.model.update(dt, p);

    // marker
    this.markerT += dt;
    const mm = this.marker.material as THREE.MeshBasicMaterial;
    const show = this.jumpTarget && this.grounded && !this.arc && this.mode === 'free';
    mm.opacity = damp(mm.opacity, show ? 0.55 + 0.2 * Math.sin(this.markerT * 6) : 0, 12, dt);
    if (this.jumpTarget) this.marker.position.set(this.jumpTarget.x, this.jumpTarget.y + 0.012, this.jumpTarget.z);
    this.marker.visible = mm.opacity > 0.02;
    const sc = 1 + 0.08 * Math.sin(this.markerT * 6);
    this.marker.scale.setScalar(sc);
  }

  private syncModel() {
    this.model.root.position.copy(this.pos);
    this.model.root.rotation.y = this.yaw;
  }

  /** Stray-style assisted jump: find a surface ahead to land on. */
  private findJumpTarget(col: ColliderWorld, moveDir: THREE.Vector3 | null) {
    if (!this.grounded || this.arc || this.mode !== 'free') {
      this.jumpTarget = null;
      return;
    }
    const dir = moveDir ? moveDir.clone().normalize() : new THREE.Vector3(Math.sin(this.yaw), 0, Math.cos(this.yaw));
    const side = new THREE.Vector3(dir.z, 0, -dir.x);
    let bestUp: THREE.Vector3 | null = null;
    let bestDown: THREE.Vector3 | null = null;
    const y0 = this.pos.y;
    outer: for (let d = 0.35; d <= 2.05; d += 0.1) {
      for (const lat of [0, 0.14, -0.14]) {
        const px = this.pos.x + dir.x * d + side.x * lat;
        const pz = this.pos.z + dir.z * d + side.z * lat;
        const top = col.groundHeight(px, pz, y0 + MAX_JUMP, 0.02);
        const dy = top - y0;
        const up = dy > 0.3;
        const down = dy < -0.45 && dy > -3.2;
        if (!up && !down) continue;
        if (up && bestUp) continue;
        if (down && (bestDown || d > 1.6)) continue;
        // landing surface must be roomy and have headroom
        if (col.ceilingHeight(px, pz, top + 0.01, 0.06) - top < 0.32) continue;
        let flat = true;
        for (const [ox, oz] of [
          [0.07, 0],
          [-0.07, 0],
          [0, 0.07],
          [0, -0.07],
        ]) {
          if (Math.abs(col.groundHeight(px + ox, pz + oz, top + 0.05, 0.0) - top) > 0.06) {
            flat = false;
            break;
          }
        }
        if (!flat) continue;
        // path clearance along the arc
        const h = up ? 0.22 + dy * 0.18 : 0.14;
        let clear = true;
        for (const s of [0.2, 0.4, 0.6, 0.8]) {
          const ax = lerp(this.pos.x, px, s);
          const az = lerp(this.pos.z, pz, s);
          const ay = lerp(y0, top, s) + h * 4 * s * (1 - s);
          const bottom = ay + (up ? 0.06 : 0.02);
          if (col.occupied(ax, az, bottom, ay + 0.26, 0.06)) {
            clear = false;
            break;
          }
        }
        if (!clear) continue;
        const p = new THREE.Vector3(px, top, pz);
        if (up) bestUp = p;
        else bestDown = p;
        if (bestUp) break outer;
      }
    }
    let best = bestUp ?? bestDown;
    // hysteresis: keep the previous target if still valid and close
    const th = this.targetHold;
    const facingHold = th ? (th.x - this.pos.x) * dir.x + (th.z - this.pos.z) * dir.z > 0.25 : false;
    if (!best && th && facingHold && th.distanceTo(this.pos) < 2.2) {
      const top = col.groundHeight(th.x, th.z, th.y + 0.02, 0.02);
      if (Math.abs(top - th.y) < 0.01 && Math.abs(top - y0) > 0.3) best = th;
    }
    this.jumpTarget = best;
    this.targetHold = best;
    void smoothstep;
  }
}
