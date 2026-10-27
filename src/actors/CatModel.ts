import * as THREE from 'three';
import { stdMat } from '../render/Materials';
import { clamp, damp, dampAngle, lerp } from '../core/math';

export interface CatPose {
  speed: number;
  grounded: boolean;
  vy: number;
  crouch: number;
  sit: number;
  lie: number;
  meow: number;
  hiss: number;
  bristle: number;
  tailUp: number;
  earYaw: number;
  earAlert: number;
  headYaw: number;
  headPitch: number;
  pupil: number;
  scratch: number;
  jump: number;
  land: number;
  purr: number;
  carry: boolean;
  run: boolean;
}

export function defaultPose(): CatPose {
  return {
    speed: 0,
    grounded: true,
    vy: 0,
    crouch: 0,
    sit: 0,
    lie: 0,
    meow: 0,
    hiss: 0,
    bristle: 0,
    tailUp: 0.6,
    earYaw: 0,
    earAlert: 0,
    headYaw: 0,
    headPitch: 0,
    pupil: 0.3,
    scratch: 0,
    jump: 0,
    land: 0,
    purr: 0,
    carry: false,
    run: false,
  };
}

interface Leg {
  hip: THREE.Group;
  knee: THREE.Group;
  front: boolean;
  side: number;
  phase: number;
  runPhase: number;
}

const FUR = '#ece2d0';
const PATCH = '#d29a5c';

export class CatModel {
  root = new THREE.Group();
  body = new THREE.Group();
  neck = new THREE.Group();
  head = new THREE.Group();
  jaw = new THREE.Group();
  mouthSocket = new THREE.Group();
  earL = new THREE.Group();
  earR = new THREE.Group();
  tail: THREE.Group[] = [];
  legs: Leg[] = [];
  fur: THREE.Mesh;
  pupils: THREE.Mesh[] = [];
  eyeMat: THREE.MeshStandardMaterial;
  private t = 0;
  private gait = 0;
  private sm = defaultPose();
  private blink = 0;
  private blinkT = 2;
  private flick = 0;
  private flickT = 3;

  constructor() {
    const fur = stdMat({ color: FUR, roughness: 0.92, flatShading: true });
    const patch = stdMat({ color: PATCH, roughness: 0.92, flatShading: true });
    const pink = stdMat({ color: '#d79292', roughness: 0.7 });
    const dark = stdMat({ color: '#1a1412', roughness: 0.4 });
    this.eyeMat = stdMat({ color: '#b8d24a', roughness: 0.15, emissive: new THREE.Color('#9fd23a'), emissiveIntensity: 0.25 });

    const ell = (r: number, sx: number, sy: number, sz: number, m: THREE.Material, detail = 1) => {
      const mesh = new THREE.Mesh(new THREE.IcosahedronGeometry(r, detail), m);
      mesh.scale.set(sx, sy, sz);
      mesh.castShadow = true;
      mesh.receiveShadow = true;
      return mesh;
    };

    this.root.add(this.body);
    this.body.position.y = 0.2;
    // torso
    const torso = ell(1, 0.105, 0.1, 0.2, fur, 2);
    this.body.add(torso);
    const chest = ell(1, 0.1, 0.105, 0.1, fur);
    chest.position.set(0, 0.01, 0.11);
    const hips = ell(1, 0.1, 0.1, 0.1, fur);
    hips.position.set(0, 0.005, -0.11);
    const saddle = ell(1, 0.085, 0.04, 0.13, patch);
    saddle.position.set(0, 0.075, -0.04);
    this.body.add(chest, hips, saddle);
    // fur ridge (bristles when scared)
    const ridgeGeo = new THREE.ConeGeometry(0.012, 0.05, 4);
    const ridge = new THREE.Group();
    for (let i = 0; i < 9; i++) {
      const c = new THREE.Mesh(ridgeGeo, i % 3 === 1 ? patch : fur);
      c.position.set(0, 0.085, -0.15 + i * 0.035);
      c.rotation.x = -0.4;
      ridge.add(c);
    }
    this.fur = ridge as unknown as THREE.Mesh;
    this.body.add(ridge);

    // neck + head
    this.neck.position.set(0, 0.05, 0.17);
    this.body.add(this.neck);
    this.head.position.set(0, 0.06, 0.05);
    this.neck.add(this.head);
    const neckMesh = ell(1, 0.06, 0.07, 0.07, fur);
    neckMesh.position.set(0, 0.0, 0.0);
    this.neck.add(neckMesh);
    const skull = ell(0.075, 1, 0.88, 0.95, fur, 2);
    this.head.add(skull);
    const cap = ell(0.06, 1, 0.45, 0.9, patch);
    cap.position.set(0, 0.04, -0.01);
    this.head.add(cap);
    const muzzle = ell(0.034, 1.35, 0.8, 0.95, fur);
    muzzle.position.set(0, -0.022, 0.058);
    this.head.add(muzzle);
    const nose = new THREE.Mesh(new THREE.ConeGeometry(0.009, 0.01, 3), pink);
    nose.rotation.x = Math.PI;
    nose.position.set(0, -0.005, 0.088);
    this.head.add(nose);
    this.jaw.position.set(0, -0.035, 0.035);
    const jawMesh = ell(0.025, 1.2, 0.5, 1.1, fur);
    jawMesh.position.set(0, -0.004, 0.018);
    this.jaw.add(jawMesh);
    const tongue = ell(0.013, 1, 0.3, 1.3, pink, 0);
    tongue.position.set(0, 0.004, 0.02);
    this.jaw.add(tongue);
    this.head.add(this.jaw);
    this.mouthSocket.position.set(0, -0.045, 0.085);
    this.head.add(this.mouthSocket);
    // eyes
    for (const s of [-1, 1]) {
      const eye = new THREE.Mesh(new THREE.SphereGeometry(0.0165, 12, 10), this.eyeMat);
      eye.scale.set(1, 0.95, 0.55);
      eye.position.set(s * 0.031, 0.008, 0.06);
      eye.rotation.y = s * 0.35;
      this.head.add(eye);
      const pupil = new THREE.Mesh(new THREE.SphereGeometry(0.0168, 10, 8), dark);
      pupil.scale.set(0.3, 0.92, 0.3);
      pupil.position.set(s * 0.032, 0.008, 0.066);
      this.head.add(pupil);
      this.pupils.push(pupil);
    }
    // ears
    for (const [ear, s] of [
      [this.earL, -1],
      [this.earR, 1],
    ] as const) {
      ear.position.set(s * 0.04, 0.052, -0.005);
      ear.rotation.z = -s * 0.25;
      const outer = new THREE.Mesh(new THREE.ConeGeometry(0.03, 0.062, 4), patch);
      outer.position.y = 0.028;
      outer.rotation.y = Math.PI / 4;
      outer.scale.z = 0.55;
      outer.castShadow = true;
      const inner = new THREE.Mesh(new THREE.ConeGeometry(0.02, 0.045, 3), pink);
      inner.position.set(0, 0.024, 0.008);
      inner.scale.z = 0.3;
      ear.add(outer, inner);
      this.head.add(ear);
    }
    // whiskers
    const wpts: number[] = [];
    for (const s of [-1, 1])
      for (let i = 0; i < 3; i++) {
        wpts.push(s * 0.03, -0.02, 0.075, s * 0.11, -0.02 + (i - 1) * 0.012, 0.06 - i * 0.008);
      }
    const wg = new THREE.BufferGeometry();
    wg.setAttribute('position', new THREE.Float32BufferAttribute(wpts, 3));
    this.head.add(new THREE.LineSegments(wg, new THREE.LineBasicMaterial({ color: '#e9e6df', transparent: true, opacity: 0.6 })));

    // tail
    let parent: THREE.Object3D = this.body;
    const segs = 10;
    for (let i = 0; i < segs; i++) {
      const g = new THREE.Group();
      g.position.set(0, i === 0 ? 0.04 : 0, i === 0 ? -0.2 : -0.036);
      const r = lerp(0.027, 0.015, i / segs);
      const m = new THREE.Mesh(new THREE.CylinderGeometry(r * 0.92, r, 0.046, 7), i >= segs - 2 ? patch : fur);
      m.rotation.x = Math.PI / 2;
      m.position.z = -0.018;
      m.castShadow = true;
      // a ball at each joint hides the seams between segments
      const joint = new THREE.Mesh(new THREE.SphereGeometry(r * 0.98, 7, 5), i >= segs - 2 ? patch : fur);
      joint.castShadow = true;
      g.add(m, joint);
      if (i === segs - 1) {
        const tip = new THREE.Mesh(new THREE.SphereGeometry(r * 0.9, 7, 5), patch);
        tip.position.z = -0.04;
        g.add(tip);
      }
      parent.add(g);
      this.tail.push(g);
      parent = g;
    }

    // legs
    const legDefs: [boolean, number, number][] = [
      [true, -1, 0.0],
      [true, 1, 0.5],
      [false, -1, 0.75],
      [false, 1, 0.25],
    ];
    for (const [front, side, phase] of legDefs) {
      const hip = new THREE.Group();
      hip.position.set(side * 0.06, -0.02, front ? 0.12 : -0.12);
      const upper = new THREE.Mesh(new THREE.CylinderGeometry(front ? 0.022 : 0.03, 0.02, 0.1, 6), fur);
      upper.position.y = -0.05;
      upper.castShadow = true;
      hip.add(upper);
      const knee = new THREE.Group();
      knee.position.y = -0.095;
      const lower = new THREE.Mesh(new THREE.CylinderGeometry(0.018, 0.016, 0.085, 6), fur);
      lower.position.y = -0.042;
      lower.castShadow = true;
      knee.add(lower);
      const paw = new THREE.Mesh(new THREE.SphereGeometry(0.022, 8, 6), fur);
      paw.scale.set(1, 0.6, 1.3);
      paw.position.set(0, -0.085, 0.008);
      paw.castShadow = true;
      knee.add(paw);
      hip.add(knee);
      this.body.add(hip);
      this.legs.push({ hip, knee, front, side, phase, runPhase: front ? (side < 0 ? 0.5 : 0.6) : side < 0 ? 0 : 0.1 });
    }
    this.root.traverse((o) => {
      if ((o as THREE.Mesh).isMesh) o.castShadow = true;
    });
  }

  update(dt: number, p: CatPose) {
    this.t += dt;
    const s = this.sm;
    const k = 10;
    s.speed = damp(s.speed, p.speed, 12, dt);
    s.crouch = damp(s.crouch, p.crouch, k, dt);
    s.sit = damp(s.sit, p.sit, 4, dt);
    s.lie = damp(s.lie, p.lie, 3, dt);
    s.meow = damp(s.meow, p.meow, 14, dt);
    s.hiss = damp(s.hiss, p.hiss, 16, dt);
    s.bristle = damp(s.bristle, Math.max(p.bristle, p.hiss), 8, dt);
    s.tailUp = damp(s.tailUp, p.tailUp, 3, dt);
    s.earYaw = dampAngle(s.earYaw, p.earYaw, 6, dt);
    s.earAlert = damp(s.earAlert, p.earAlert, 5, dt);
    s.headYaw = dampAngle(s.headYaw, p.headYaw, 6, dt);
    s.headPitch = damp(s.headPitch, p.headPitch, 6, dt);
    s.pupil = damp(s.pupil, p.pupil, 5, dt);
    s.scratch = damp(s.scratch, p.scratch, 8, dt);
    s.jump = damp(s.jump, p.grounded ? 0 : 1, 14, dt);
    s.land = damp(s.land, p.land, 18, dt);
    s.purr = damp(s.purr, p.purr, 3, dt);

    const moving = clamp(s.speed / 0.4);
    const runK = clamp((s.speed - 2.4) / 1.6);
    const stride = lerp(0.36, 0.85, runK);
    this.gait += (s.speed / stride) * Math.PI * 2 * dt;
    const g = this.gait;

    // body
    const breathe = Math.sin(this.t * (s.purr > 0.1 ? 3.2 : 1.9)) * 0.004;
    const bob = -Math.abs(Math.sin(g)) * 0.012 * moving * (1 - runK) - Math.abs(Math.sin(g)) * 0.02 * runK;
    let bodyY = 0.2 + bob + breathe;
    bodyY -= s.crouch * 0.055;
    bodyY -= s.lie * 0.12;
    bodyY -= s.sit * 0.03;
    bodyY += s.hiss * 0.035;
    bodyY -= s.land * 0.04;
    bodyY += s.scratch * 0.12;
    this.body.position.y = bodyY;
    let pitch = Math.sin(g * 1) * 0.07 * runK;
    pitch += -s.sit * 0.55;
    pitch += -s.scratch * 1.15;
    pitch += s.jump * clamp(-p.vy * 0.12, -0.5, 0.5);
    this.body.rotation.x = pitch;
    this.body.position.z = -s.sit * 0.05;
    this.body.scale.set(1 + s.bristle * 0.06, 1 + s.hiss * 0.06 - s.land * 0.08, 1 + s.jump * 0.06);

    // head
    const headPitchBase = s.crouch * 0.25 - s.meow * 0.35 + s.hiss * 0.25 + s.sit * 0.5 + s.scratch * 0.9 + s.lie * 0.2;
    this.neck.rotation.x = -0.25 + headPitchBase + s.headPitch;
    this.neck.rotation.y = s.headYaw;
    this.neck.position.y = 0.05 - s.crouch * 0.02 - s.hiss * 0.03;
    this.jaw.rotation.x = s.meow * 0.45 + s.hiss * 0.6 + (p.carry ? 0.25 : 0);

    // blink
    this.blinkT -= dt;
    if (this.blinkT < 0) {
      this.blink = 1;
      this.blinkT = 2 + Math.random() * 4;
    }
    this.blink = Math.max(0, this.blink - dt * 8);
    const pw = lerp(0.18, 0.85, s.pupil);
    for (const pu of this.pupils) pu.scale.set(pw * 0.95, 0.92 * (1 - this.blink * 0.9), 0.3);
    this.eyeMat.emissiveIntensity = 0.12 + s.pupil * 0.5;

    // ears: alert ears swivel toward the threat; hiss flattens them
    this.flickT -= dt;
    if (this.flickT < 0) {
      this.flick = 1;
      this.flickT = 2 + Math.random() * 5;
    }
    this.flick = Math.max(0, this.flick - dt * 6);
    for (const [ear, side] of [
      [this.earL, -1],
      [this.earR, 1],
    ] as const) {
      const yaw = clamp(s.earYaw * s.earAlert, -1.3, 1.3);
      ear.rotation.y = yaw * 0.9 + (side < 0 ? 0.15 : -0.15) * (1 - s.earAlert);
      ear.rotation.x = -s.hiss * 1.0 + s.earAlert * 0.2 - this.flick * (side < 0 ? 0.4 : 0);
      ear.rotation.z = -side * (0.25 + s.hiss * 0.9);
    }

    // fur ridge
    (this.fur as unknown as THREE.Group).children.forEach((c, i) => {
      c.scale.y = 0.2 + s.bristle * 1.4 + Math.sin(this.t * 30 + i) * 0.05 * s.bristle;
      c.visible = s.bristle > 0.05;
    });

    // tail: curve + sway (positive x rotation raises the tail)
    const sway = Math.sin(this.t * (1.2 + s.bristle * 3)) * (0.18 + moving * 0.1);
    const base = lerp(-0.5, 0.95, s.tailUp) + s.hiss * 0.45 - s.crouch * 0.8 - s.lie * 0.8 - s.sit * 1.1;
    const puff = 1 + s.bristle * 1.2;
    this.tail.forEach((seg, i) => {
      const f = i / this.tail.length;
      if (i === 0) seg.rotation.x = base;
      else {
        // relaxed tails droop, proud tails hook forward at the tip
        const hook = s.tailUp > 0.5 ? (f > 0.55 ? 0.2 : 0.06) : 0.1;
        seg.rotation.x = hook * (1 - s.hiss) + (s.sit + s.lie) * -0.05;
      }
      seg.rotation.y = sway * (0.3 + f) * 0.35 + (s.sit + s.lie) * 0.28;
      seg.scale.set(puff, puff, 1);
    });

    // legs
    const amp = lerp(0.55, 0.95, runK) * moving;
    for (const L of this.legs) {
      const ph = lerp(L.phase, L.runPhase, runK) * Math.PI * 2;
      const sw = Math.sin(g + ph);
      const lift = Math.max(0, Math.cos(g + ph));
      // Convention: positive hip swings the foot backwards (+z is forward); positive knee folds the
      // lower leg backwards. Front legs: elbow behind, wrist forward. Hind legs: knee forward, hock behind.
      let hipA = sw * amp;
      let kneeA = lift * (L.front ? 0.9 : 1.1) * moving;
      // crouch: elbows back with forearms forward; hind thighs forward with hocks folded
      if (L.front) {
        hipA += 0.3 * s.crouch;
        kneeA += -0.6 * s.crouch;
      } else {
        hipA += -0.5 * s.crouch;
        kneeA += 0.9 * s.crouch;
      }
      // sit: back legs folded, front legs straight under the raised chest
      if (!L.front) {
        hipA = lerp(hipA, -1.05, s.sit);
        kneeA = lerp(kneeA, 2.2, s.sit);
      } else {
        hipA = lerp(hipA, 0.55, s.sit);
        kneeA = lerp(kneeA, 0, s.sit);
      }
      // lie (loaf): front legs tucked with forearms forward, hind legs folded under the body
      hipA = lerp(hipA, L.front ? 1.05 : -1.25, s.lie);
      kneeA = lerp(kneeA, L.front ? -2.1 : 2.4, s.lie);
      // airborne: stretch (front reaches forward, hind pushes back)
      const air = s.jump;
      hipA = lerp(hipA, L.front ? -0.75 : 0.8, air * 0.8);
      kneeA = lerp(kneeA, L.front ? -0.15 : 0.25, air * 0.8);
      // scratching: front paws claw at the door, hind legs carry the weight
      if (L.front && s.scratch > 0.01) {
        hipA = lerp(hipA, -1.4 + Math.sin(this.t * 14 + (L.side > 0 ? Math.PI : 0)) * 0.35, s.scratch);
        kneeA = lerp(kneeA, -0.3, s.scratch);
      }
      if (!L.front) hipA = lerp(hipA, 1.0, s.scratch);
      // hiss: legs straight, body tall
      hipA *= 1 - s.hiss * 0.6;
      kneeA *= 1 - s.hiss * 0.8;
      L.hip.rotation.x = hipA;
      L.knee.rotation.x = kneeA;
      L.hip.position.y = -0.02 + s.lie * 0.03;
    }
  }

  /** World position of the mouth (for carried items). */
  mouthWorld(out: THREE.Vector3) {
    return this.mouthSocket.getWorldPosition(out);
  }
}
