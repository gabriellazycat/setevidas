import * as THREE from 'three';
import { stdMat } from '../render/Materials';
import { damp, lerp } from '../core/math';

export type PoseName =
  | 'stand'
  | 'lie'
  | 'sitUp'
  | 'hug'
  | 'cry'
  | 'paralysis'
  | 'kneel'
  | 'sit'
  | 'read'
  | 'reach'
  | 'pet'
  | 'phone'
  | 'drink'
  | 'bath'
  | 'stare'
  | 'carry';

type J = { x?: number; y?: number; z?: number };
interface PoseDef {
  hipsY: number;
  hips: J;
  spine: J;
  chest: J;
  neck: J;
  head: J;
  shL: J;
  elL: J;
  shR: J;
  elR: J;
  thL: J;
  knL: J;
  thR: J;
  knR: J;
}

const P = (o: Partial<PoseDef>): PoseDef => ({
  hipsY: 0,
  hips: {},
  spine: {},
  chest: {},
  neck: {},
  head: {},
  shL: { z: 0.12 },
  elL: { x: -0.15 },
  shR: { z: -0.12 },
  elR: { x: -0.15 },
  thL: {},
  knL: {},
  thR: {},
  knR: {},
  ...o,
});

const POSES: Record<PoseName, PoseDef> = {
  stand: P({}),
  stare: P({ head: { x: 0.12 }, shL: { z: 0.05 }, shR: { z: -0.05 }, elL: { x: 0 }, elR: { x: 0 } }),
  lie: P({ hips: { x: -Math.PI / 2 }, hipsY: -0.38, shL: { z: 0.05, x: 0.1 }, shR: { z: -0.05, x: 0.1 }, head: { x: -0.1 } }),
  sitUp: P({ hipsY: -0.4, thL: { x: -1.5 }, thR: { x: -1.5 }, knL: { x: 0.15 }, knR: { x: 0.15 }, shL: { x: -0.2, z: 0.25 }, shR: { x: -0.2, z: -0.25 }, spine: { x: 0.12 } }),
  hug: P({ hipsY: -0.42, thL: { x: -2.3 }, thR: { x: -2.3 }, knL: { x: 2.2 }, knR: { x: 2.2 }, spine: { x: 0.45 }, chest: { x: 0.2 }, neck: { x: 0.3 }, head: { x: 0.25 }, shL: { x: -1.25, z: 0.1 }, shR: { x: -1.25, z: -0.1 }, elL: { x: -1.4 }, elR: { x: -1.4 } }),
  cry: P({ hipsY: -0.42, thL: { x: -2.3 }, thR: { x: -2.3 }, knL: { x: 2.2 }, knR: { x: 2.2 }, spine: { x: 0.5 }, chest: { x: 0.25 }, neck: { x: 0.35 }, head: { x: 0.35 }, shL: { x: -2.2, z: 0.35 }, shR: { x: -2.2, z: -0.35 }, elL: { x: -2.3 }, elR: { x: -2.3 } }),
  paralysis: P({ hipsY: -0.4, thL: { x: -1.5 }, thR: { x: -1.5 }, spine: { x: -0.1 }, neck: { x: -0.25 }, head: { x: -0.2 }, shL: { z: 0.2 }, shR: { z: -0.2 }, elL: { x: 0 }, elR: { x: 0 } }),
  kneel: P({ hipsY: -0.44, thL: { x: 0.05 }, thR: { x: 0.05 }, knL: { x: 1.55 }, knR: { x: 1.55 }, spine: { x: 0.7 }, chest: { x: 0.2 }, neck: { x: 0.1 }, shL: { x: -1.3, z: 0.15 }, shR: { x: -1.3, z: -0.15 }, elL: { x: -0.3 }, elR: { x: -0.3 } }),
  sit: P({ hipsY: -0.44, thL: { x: -1.5, z: 0.06 }, thR: { x: -1.5, z: -0.06 }, knL: { x: 1.5 }, knR: { x: 1.5 }, shL: { x: -0.3, z: 0.1 }, shR: { x: -0.3, z: -0.1 }, elL: { x: -0.8 }, elR: { x: -0.8 } }),
  read: P({ hipsY: -0.44, thL: { x: -1.5 }, thR: { x: -1.5 }, knL: { x: 1.5 }, knR: { x: 1.5 }, spine: { x: 0.2 }, neck: { x: 0.35 }, shL: { x: -0.9, z: 0.2 }, shR: { x: -0.9, z: -0.2 }, elL: { x: -0.9 }, elR: { x: -0.9 } }),
  reach: P({ spine: { x: 0.15 }, shR: { x: -1.35, z: -0.05 }, elR: { x: -0.2 }, head: { x: 0.15 } }),
  pet: P({ hipsY: -0.42, thL: { x: -1.1 }, thR: { x: -0.4 }, knL: { x: 2.1 }, knR: { x: 1.9 }, spine: { x: 0.5 }, neck: { x: 0.3 }, shR: { x: -0.9, z: -0.1 }, elR: { x: -0.3 }, shL: { x: -0.2, z: 0.2 } }),
  phone: P({ shR: { x: -0.4, z: -0.9 }, elR: { x: -2.4 }, head: { y: 0.2, z: -0.1 } }),
  drink: P({ shR: { x: -1.1, z: -0.3 }, elR: { x: -2.0 }, head: { x: -0.25 } }),
  bath: P({ hipsY: -0.62, hips: { x: -1.0 }, thL: { x: -0.6 }, thR: { x: -0.6 }, knL: { x: 0.6 }, knR: { x: 0.6 }, neck: { x: 0.6 }, head: { x: 0.25 }, shL: { z: 0.4 }, shR: { z: -0.4 } }),
  carry: P({ shL: { x: -1.1, z: 0.25 }, shR: { x: -1.1, z: -0.25 }, elL: { x: -1.2 }, elR: { x: -1.2 } }),
};

type JointKey = Exclude<keyof PoseDef, 'hipsY'>;
const JOINTS: JointKey[] = ['hips', 'spine', 'chest', 'neck', 'head', 'shL', 'elL', 'shR', 'elR', 'thL', 'knL', 'thR', 'knR'];

export interface OwnerLook {
  skin: string;
  hair: string;
  hairStyle: 'bun' | 'short';
  scale: number;
  glasses: boolean;
  stubble: boolean;
  day: Outfit;
  night: Outfit;
}

export interface Outfit {
  top: string;
  bottom: string;
  shoes: string;
}
export const OUTFIT_DAY: Outfit = { top: '#b5853a', bottom: '#33425e', shoes: '#2a2422' };
export const OUTFIT_NIGHT: Outfit = { top: '#8ea6c8', bottom: '#7a90b2', shoes: '#d8cfc4' };

export const CLARA_LOOK: OwnerLook = { skin: '#e0b39a', hair: '#3a2820', hairStyle: 'bun', scale: 1, glasses: false, stubble: false, day: OUTFIT_DAY, night: OUTFIT_NIGHT };
export const DAVI_LOOK: OwnerLook = {
  skin: '#b98866',
  hair: '#1d1612',
  hairStyle: 'short',
  scale: 1.08,
  glasses: true,
  stubble: true,
  day: { top: '#3f6b5a', bottom: '#2f3744', shoes: '#e2ddd2' },
  night: { top: '#59606b', bottom: '#2b2f38', shoes: '#4a4540' },
};

export class OwnerModel {
  root = new THREE.Group();
  hips = new THREE.Group();
  spine = new THREE.Group();
  chest = new THREE.Group();
  neck = new THREE.Group();
  head = new THREE.Group();
  shL = new THREE.Group();
  elL = new THREE.Group();
  shR = new THREE.Group();
  elR = new THREE.Group();
  thL = new THREE.Group();
  knL = new THREE.Group();
  thR = new THREE.Group();
  knR = new THREE.Group();
  handR = new THREE.Group();
  private cur: Record<string, THREE.Vector3> = {};
  private hipsY = 0;
  pose: PoseName = 'stand';
  speed = 0;
  style: 'normal' | 'hypno' | 'hurry' = 'normal';
  tremble = 0;
  eyesWide = 0;
  private gait = 0;
  private t = 0;
  private topMat: THREE.MeshStandardMaterial;
  private botMat: THREE.MeshStandardMaterial;
  private shoeMat: THREE.MeshStandardMaterial;
  private eyes: THREE.Mesh[] = [];

  constructor(public look: OwnerLook = CLARA_LOOK) {
    const skin = stdMat({ color: look.skin, roughness: 0.7 });
    const hair = stdMat({ color: look.hair, roughness: 0.85, flatShading: true });
    this.topMat = stdMat({ color: look.night.top, roughness: 0.9 });
    this.botMat = stdMat({ color: look.night.bottom, roughness: 0.9 });
    this.shoeMat = stdMat({ color: look.night.shoes, roughness: 0.8 });
    this.root.scale.setScalar(look.scale);
    const eyeMat = stdMat({ color: '#1b1412', roughness: 0.3 });
    const cap = (r: number, len: number, m: THREE.Material) => {
      const mesh = new THREE.Mesh(new THREE.CapsuleGeometry(r, len, 4, 10), m);
      mesh.castShadow = true;
      mesh.receiveShadow = true;
      return mesh;
    };
    this.root.add(this.hips);
    this.hips.position.y = 0.93;
    const pelvis = cap(0.13, 0.08, this.botMat);
    pelvis.rotation.z = Math.PI / 2;
    pelvis.scale.set(1, 1, 0.75);
    this.hips.add(pelvis);
    // legs
    for (const [th, kn, s] of [
      [this.thL, this.knL, 1],
      [this.thR, this.knR, -1],
    ] as const) {
      th.position.set(s * 0.09, -0.04, 0);
      const thigh = cap(0.068, 0.3, this.botMat);
      thigh.position.y = -0.21;
      th.add(thigh);
      kn.position.y = -0.44;
      const shin = cap(0.052, 0.3, this.botMat);
      shin.position.y = -0.2;
      kn.add(shin);
      const foot = new THREE.Mesh(new THREE.BoxGeometry(0.085, 0.06, 0.18), this.shoeMat);
      foot.position.set(0, -0.43, 0.04);
      foot.castShadow = true;
      kn.add(foot);
      th.add(kn);
      this.hips.add(th);
    }
    // torso
    this.spine.position.y = 0.05;
    this.hips.add(this.spine);
    const belly = cap(0.13, 0.12, this.topMat);
    belly.position.y = 0.12;
    belly.scale.z = 0.75;
    this.spine.add(belly);
    this.chest.position.y = 0.24;
    this.spine.add(this.chest);
    const chestMesh = cap(0.15, 0.12, this.topMat);
    chestMesh.position.y = 0.06;
    chestMesh.rotation.z = Math.PI / 2;
    chestMesh.scale.set(1, 0.95, 0.68);
    this.chest.add(chestMesh);
    // arms
    for (const [sh, el, s] of [
      [this.shL, this.elL, 1],
      [this.shR, this.elR, -1],
    ] as const) {
      sh.position.set(s * 0.21, 0.13, 0);
      const upper = cap(0.048, 0.2, this.topMat);
      upper.position.y = -0.14;
      sh.add(upper);
      el.position.y = -0.29;
      const fore = cap(0.04, 0.19, skin);
      fore.position.y = -0.13;
      el.add(fore);
      const hand = new THREE.Mesh(new THREE.SphereGeometry(0.045, 8, 6), skin);
      hand.scale.set(0.8, 1.1, 0.5);
      hand.position.y = -0.28;
      el.add(hand);
      if (s < 0) {
        this.handR.position.y = -0.3;
        el.add(this.handR);
      }
      sh.add(el);
      this.chest.add(sh);
    }
    // neck + head
    this.neck.position.y = 0.2;
    this.chest.add(this.neck);
    const neckMesh = cap(0.045, 0.06, skin);
    neckMesh.position.y = 0.03;
    this.neck.add(neckMesh);
    this.head.position.y = 0.1;
    this.neck.add(this.head);
    const skull = new THREE.Mesh(new THREE.SphereGeometry(0.105, 16, 12), skin);
    skull.scale.set(0.92, 1.05, 1);
    skull.position.y = 0.06;
    skull.castShadow = true;
    this.head.add(skull);
    const hairBack = new THREE.Mesh(new THREE.SphereGeometry(0.115, 14, 10), hair);
    hairBack.scale.set(1.0, 1.08, 1.02);
    hairBack.position.set(0, 0.085, -0.02);
    this.head.add(hairBack);
    const fringe = new THREE.Mesh(new THREE.SphereGeometry(0.1, 12, 8, 0, Math.PI * 2, 0, Math.PI / 2.4), hair);
    fringe.position.set(0, 0.1, 0.02);
    fringe.rotation.x = 0.35;
    this.head.add(fringe);
    if (look.hairStyle === 'bun') {
      const bun = new THREE.Mesh(new THREE.SphereGeometry(0.055, 10, 8), hair);
      bun.position.set(0, 0.17, -0.09);
      this.head.add(bun);
      const tail = cap(0.04, 0.16, hair);
      tail.position.set(0, -0.02, -0.11);
      tail.rotation.x = 0.2;
      this.head.add(tail);
    } else {
      // short, slightly tousled hair
      for (let i = 0; i < 6; i++) {
        const tuft = new THREE.Mesh(new THREE.IcosahedronGeometry(0.035, 0), hair);
        const a = (i / 6) * Math.PI * 2;
        tuft.position.set(Math.cos(a) * 0.07, 0.15 + (i % 2) * 0.01, Math.sin(a) * 0.07 - 0.01);
        this.head.add(tuft);
      }
    }
    if (look.stubble) {
      const st = new THREE.Mesh(new THREE.SphereGeometry(0.1, 12, 8, 0, Math.PI * 2, Math.PI * 0.55, Math.PI * 0.4), stdMat({ color: '#2a201a', roughness: 1 }));
      st.scale.set(0.93, 1.0, 1.02);
      st.position.set(0, 0.055, 0.003);
      this.head.add(st);
    }
    if (look.glasses) {
      const gm = stdMat({ color: '#151515', roughness: 0.4 });
      for (const s of [-1, 1]) {
        const ring = new THREE.Mesh(new THREE.TorusGeometry(0.03, 0.004, 5, 14), gm);
        ring.position.set(s * 0.038, 0.07, 0.1);
        this.head.add(ring);
      }
      const bridge = new THREE.Mesh(new THREE.BoxGeometry(0.02, 0.004, 0.004), gm);
      bridge.position.set(0, 0.075, 0.102);
      this.head.add(bridge);
    }
    for (const s of [-1, 1]) {
      const e = new THREE.Mesh(new THREE.SphereGeometry(0.014, 8, 6), eyeMat);
      e.position.set(s * 0.036, 0.07, 0.093);
      e.scale.set(1, 0.8, 0.5);
      this.head.add(e);
      this.eyes.push(e);
    }
    const nose = new THREE.Mesh(new THREE.SphereGeometry(0.015, 6, 6), skin);
    nose.position.set(0, 0.045, 0.105);
    this.head.add(nose);
    for (const j of JOINTS) this.cur[j] = new THREE.Vector3();
    this.hips.traverse((o) => {
      if ((o as THREE.Mesh).isMesh) o.castShadow = true;
    });
  }

  setOutfit(o: Outfit) {
    this.topMat.color.set(o.top);
    this.botMat.color.set(o.bottom);
    this.shoeMat.color.set(o.shoes);
  }

  snapPose(p: PoseName) {
    this.pose = p;
    const def = POSES[p];
    for (const j of JOINTS) {
      const v = def[j] as J;
      this.cur[j].set(v.x ?? 0, v.y ?? 0, v.z ?? 0);
    }
    this.hipsY = def.hipsY;
  }

  update(dt: number) {
    this.t += dt;
    const def = POSES[this.pose];
    const rate = 5;
    for (const j of JOINTS) {
      const v = def[j] as J;
      const c = this.cur[j];
      c.x = damp(c.x, v.x ?? 0, rate, dt);
      c.y = damp(c.y, v.y ?? 0, rate, dt);
      c.z = damp(c.z, v.z ?? 0, rate, dt);
    }
    this.hipsY = damp(this.hipsY, def.hipsY, rate, dt);

    const sp = this.speed;
    const stride = this.style === 'hurry' ? 1.25 : 0.95;
    this.gait += (sp / stride) * Math.PI * 2 * dt;
    const w = Math.min(1, sp / 0.5);
    const g = this.gait;
    const hyp = this.style === 'hypno' ? 1 : 0;
    const legA = 0.5 * w;
    const armA = (0.35 - hyp * 0.3) * w;
    const breathe = Math.sin(this.t * 1.6) * 0.015;
    const tr = this.tremble > 0 ? (Math.random() - 0.5) * 0.04 * this.tremble : 0;

    const set = (o: THREE.Object3D, k: JointKey, ax = 0, ay = 0, az = 0) => {
      const c = this.cur[k];
      o.rotation.set(c.x + ax, c.y + ay, c.z + az);
    };
    set(this.hips, 'hips', 0, 0, Math.sin(g) * 0.04 * w);
    this.hips.position.y = 0.93 + this.hipsY - Math.abs(Math.sin(g)) * 0.03 * w;
    set(this.spine, 'spine', breathe + hyp * 0.1 + tr, 0, 0);
    set(this.chest, 'chest', breathe * 0.5, Math.sin(g) * 0.08 * w, 0);
    set(this.neck, 'neck', hyp * 0.3, 0, hyp * 0.2);
    set(this.head, 'head', tr, 0, tr * 0.5);
    set(this.thL, 'thL', Math.sin(g) * legA);
    set(this.thR, 'thR', -Math.sin(g) * legA);
    set(this.knL, 'knL', Math.max(0, Math.sin(g - 1.2)) * 0.9 * w);
    set(this.knR, 'knR', Math.max(0, -Math.sin(g - 1.2)) * 0.9 * w);
    set(this.shL, 'shL', -Math.sin(g) * armA);
    set(this.shR, 'shR', Math.sin(g) * armA);
    set(this.elL, 'elL', -Math.max(0, Math.sin(g)) * 0.3 * w);
    set(this.elR, 'elR', -Math.max(0, -Math.sin(g)) * 0.3 * w);
    const ew = lerp(0.8, 1.6, this.eyesWide);
    for (const e of this.eyes) e.scale.set(ew, 0.8 * ew, 0.5);
  }
}
