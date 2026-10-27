import * as THREE from 'three';
import type { ColliderWorld } from './Colliders';
import { mat, stdMat } from '../render/Materials';
import { textures } from '../render/Textures';
import { rand } from '../core/math';

export type PropKind = 'cup' | 'vase' | 'bottle' | 'book' | 'frame' | 'glass' | 'pot' | 'toy';

/** Knock-off-able props: the cat pushes them; they fall and maybe break. */
export class Prop {
  pos = new THREE.Vector3();
  vel = new THREE.Vector3();
  spin = new THREE.Vector3();
  state: 'rest' | 'fall' | 'broken' = 'rest';
  restY = 0;
  home = new THREE.Vector3();
  homeRot = new THREE.Euler();

  constructor(
    public kind: PropKind,
    public mesh: THREE.Object3D,
    public radius: number,
    public fragile: boolean,
  ) {}

  reset() {
    this.state = 'rest';
    this.pos.copy(this.home);
    this.vel.set(0, 0, 0);
    this.spin.set(0, 0, 0);
    this.restY = this.home.y;
    this.mesh.visible = true;
    this.mesh.position.copy(this.home);
    this.mesh.rotation.copy(this.homeRot);
  }
}

function makePropMesh(kind: PropKind): { mesh: THREE.Object3D; r: number; fragile: boolean } {
  const g = new THREE.Group();
  let r = 0.06;
  let fragile = true;
  switch (kind) {
    case 'cup': {
      const c = new THREE.Mesh(new THREE.CylinderGeometry(0.04, 0.034, 0.09, 12), mat('ceramic'));
      c.position.y = 0.045;
      const h = new THREE.Mesh(new THREE.TorusGeometry(0.022, 0.006, 6, 10), mat('ceramic'));
      h.position.set(0.045, 0.05, 0);
      g.add(c, h);
      r = 0.05;
      break;
    }
    case 'glass': {
      const c = new THREE.Mesh(new THREE.CylinderGeometry(0.035, 0.03, 0.11, 12), mat('glass'));
      c.position.y = 0.055;
      const w = new THREE.Mesh(new THREE.CylinderGeometry(0.031, 0.028, 0.06, 12), mat('water'));
      w.position.y = 0.035;
      g.add(c, w);
      r = 0.045;
      break;
    }
    case 'vase': {
      const pts = [0, 0.05, 0.07, 0.06, 0.035, 0.03, 0.045].map((x, i) => new THREE.Vector2(x, i * 0.05));
      const v = new THREE.Mesh(new THREE.LatheGeometry(pts, 14), stdMat({ color: '#3d5a6e', roughness: 0.25 }));
      g.add(v);
      for (let i = 0; i < 3; i++) {
        const f = new THREE.Mesh(new THREE.IcosahedronGeometry(0.035, 0), stdMat({ color: ['#c9475a', '#e8d27a', '#e6e2d8'][i], roughness: 0.8, flatShading: true }));
        f.position.set(rand(-0.03, 0.03), 0.34 + rand(0, 0.05), rand(-0.03, 0.03));
        const st = new THREE.Mesh(new THREE.CylinderGeometry(0.003, 0.003, 0.12, 4), mat('plant'));
        st.position.set(f.position.x * 0.5, 0.28, f.position.z * 0.5);
        g.add(f, st);
      }
      r = 0.08;
      break;
    }
    case 'bottle': {
      const pts = [0, 0.03, 0.03, 0.03, 0.012, 0.012].map((x, i) => new THREE.Vector2(x, [0, 0, 0.08, 0.1, 0.13, 0.15][i]));
      const v = new THREE.Mesh(new THREE.LatheGeometry(pts, 10), stdMat({ color: '#b98aa8', roughness: 0.1, transparent: true, opacity: 0.8 }));
      g.add(v);
      r = 0.04;
      break;
    }
    case 'book': {
      const v = new THREE.Mesh(new THREE.BoxGeometry(0.15, 0.035, 0.21), mat('book_b'));
      v.position.y = 0.0175;
      g.add(v);
      r = 0.1;
      fragile = false;
      break;
    }
    case 'frame': {
      const v = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.2, 0.02), mat('frame_gold'));
      v.position.y = 0.1;
      v.rotation.x = -0.15;
      const p = new THREE.Mesh(new THREE.PlaneGeometry(0.12, 0.16), stdMat({ map: textures().photo, roughness: 0.6 }));
      p.position.set(0, 0.1, 0.0115);
      p.rotation.x = -0.15;
      g.add(v, p);
      r = 0.08;
      break;
    }
    case 'pot': {
      const v = new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.05, 0.12, 12), mat('terracotta'));
      v.position.y = 0.06;
      const l = new THREE.Mesh(new THREE.IcosahedronGeometry(0.08, 0), mat('plant'));
      l.position.y = 0.17;
      l.scale.y = 1.3;
      g.add(v, l);
      r = 0.07;
      break;
    }
    case 'toy': {
      const body = new THREE.Mesh(new THREE.SphereGeometry(0.035, 10, 8), stdMat({ color: '#9a9a9a', roughness: 0.9 }));
      body.scale.set(1, 0.8, 1.5);
      body.position.y = 0.03;
      const tail = new THREE.Mesh(new THREE.CylinderGeometry(0.003, 0.003, 0.12, 4), stdMat({ color: '#d46a7a' }));
      tail.rotation.x = Math.PI / 2;
      tail.position.set(0, 0.02, -0.1);
      g.add(body, tail);
      r = 0.05;
      fragile = false;
      break;
    }
  }
  g.traverse((o) => {
    if ((o as THREE.Mesh).isMesh) {
      o.castShadow = true;
      o.receiveShadow = true;
    }
  });
  return { mesh: g, r, fragile };
}

interface Shard {
  m: THREE.Mesh;
  v: THREE.Vector3;
  s: THREE.Vector3;
  life: number;
  ground: number;
}

export interface NoiseEvent {
  pos: THREE.Vector3;
  loudness: number;
  kind: 'break' | 'thud' | 'scratch' | 'meow' | 'run' | 'door';
}

export class PropSystem {
  props: Prop[] = [];
  private shards: Shard[] = [];
  private shardGeo = new THREE.TetrahedronGeometry(0.02, 0);
  onNoise?: (e: NoiseEvent) => void;

  constructor(
    private parent: THREE.Object3D,
    private col: ColliderWorld,
  ) {}

  add(kind: PropKind, x: number, y: number, z: number, rotY = 0) {
    const { mesh, r, fragile } = makePropMesh(kind);
    const p = new Prop(kind, mesh, r, fragile);
    p.home.set(x, y, z);
    p.homeRot.set(0, rotY, 0);
    p.reset();
    this.parent.add(mesh);
    this.props.push(p);
    return p;
  }

  resetAll() {
    for (const p of this.props) p.reset();
    for (const s of this.shards) this.parent.remove(s.m);
    this.shards.length = 0;
  }

  /** Push props near the cat. catVel is horizontal velocity. */
  interactCat(catPos: THREE.Vector3, catVel: THREE.Vector3, catR: number) {
    for (const p of this.props) {
      if (p.state !== 'rest') continue;
      const dy = p.pos.y - catPos.y;
      if (dy < -0.12 || dy > 0.22) continue;
      const dx = p.pos.x - catPos.x;
      const dz = p.pos.z - catPos.z;
      const d = Math.hypot(dx, dz);
      const min = p.radius + catR;
      if (d < min && d > 1e-4) {
        const nx = dx / d;
        const nz = dz / d;
        const push = min - d;
        p.pos.x += nx * push;
        p.pos.z += nz * push;
        const sp = Math.max(0.6, Math.hypot(catVel.x, catVel.z) * 0.9);
        p.vel.x = nx * sp;
        p.vel.z = nz * sp;
      }
    }
  }

  /** Swat: knock the closest prop in front of the cat off its surface. */
  swat(catPos: THREE.Vector3, forward: THREE.Vector3): Prop | null {
    let best: Prop | null = null;
    let bd = 0.55;
    for (const p of this.props) {
      if (p.state !== 'rest') continue;
      const dy = p.pos.y - catPos.y;
      if (dy < -0.15 || dy > 0.55) continue;
      const d = Math.hypot(p.pos.x - catPos.x, p.pos.z - catPos.z);
      if (d < bd) {
        bd = d;
        best = p;
      }
    }
    if (best) {
      const dx = best.pos.x - catPos.x;
      const dz = best.pos.z - catPos.z;
      const d = Math.max(0.01, Math.hypot(dx, dz));
      best.vel.set((dx / d) * 1.6 + forward.x * 0.6, 0.6, (dz / d) * 1.6 + forward.z * 0.6);
      best.spin.set(rand(-6, 6), rand(-3, 3), rand(-6, 6));
      best.state = 'fall';
    }
    return best;
  }

  nearSwattable(catPos: THREE.Vector3) {
    for (const p of this.props) {
      if (p.state !== 'rest') continue;
      const dy = p.pos.y - catPos.y;
      if (dy < -0.15 || dy > 0.55) continue;
      if (Math.hypot(p.pos.x - catPos.x, p.pos.z - catPos.z) < 0.55) return p;
    }
    return null;
  }

  update(dt: number) {
    for (const p of this.props) {
      if (p.state === 'broken') continue;
      if (p.state === 'rest') {
        if (p.vel.lengthSq() < 1e-6) continue;
        p.pos.x += p.vel.x * dt;
        p.pos.z += p.vel.z * dt;
        p.vel.multiplyScalar(Math.max(0, 1 - 6 * dt));
        // slid off the surface?
        const g = this.col.groundHeight(p.pos.x, p.pos.z, p.pos.y + 0.05, 0.01);
        if (g < p.pos.y - 0.04) {
          p.state = 'fall';
          p.spin.set(rand(-5, 5), rand(-2, 2), rand(-5, 5));
        }
        p.mesh.position.copy(p.pos);
        continue;
      }
      // falling
      p.vel.y -= 9.8 * dt;
      p.pos.addScaledVector(p.vel, dt);
      p.mesh.rotation.x += p.spin.x * dt;
      p.mesh.rotation.y += p.spin.y * dt;
      p.mesh.rotation.z += p.spin.z * dt;
      const g = this.col.groundHeight(p.pos.x, p.pos.z, p.pos.y + 0.3, 0.01);
      if (p.pos.y <= g) {
        p.pos.y = g;
        const impact = -p.vel.y;
        if (p.fragile && impact > 2.2) {
          this.breakProp(p);
          this.onNoise?.({ pos: p.pos.clone(), loudness: 1, kind: 'break' });
        } else if (impact > 1) {
          p.vel.y = impact * 0.25;
          p.vel.x *= 0.5;
          p.vel.z *= 0.5;
          p.spin.multiplyScalar(0.5);
          this.onNoise?.({ pos: p.pos.clone(), loudness: Math.min(0.7, impact / 5), kind: 'thud' });
        } else {
          p.state = 'rest';
          p.vel.set(0, 0, 0);
          p.mesh.rotation.x = Math.PI / 2 * (Math.random() < 0.5 ? 1 : -1) * (p.kind === 'book' || p.kind === 'toy' ? 0 : 1);
          p.mesh.rotation.z = 0;
          p.pos.y = g + (p.kind === 'book' || p.kind === 'toy' ? 0 : p.radius * 0.6);
        }
      }
      p.mesh.position.copy(p.pos);
    }
    // shards
    for (let i = this.shards.length - 1; i >= 0; i--) {
      const s = this.shards[i];
      s.life -= dt;
      if (s.m.position.y > s.ground) {
        s.v.y -= 9.8 * dt;
        s.m.position.addScaledVector(s.v, dt);
        s.m.rotation.x += s.s.x * dt;
        s.m.rotation.z += s.s.z * dt;
        if (s.m.position.y < s.ground) {
          s.m.position.y = s.ground + 0.005;
          s.v.set(0, 0, 0);
        }
      }
      if (s.life < 0) {
        this.parent.remove(s.m);
        this.shards.splice(i, 1);
      }
    }
  }

  private breakProp(p: Prop) {
    p.state = 'broken';
    p.mesh.visible = false;
    const m = p.kind === 'glass' || p.kind === 'bottle' ? mat('glass') : p.kind === 'pot' ? mat('terracotta') : mat('ceramic');
    for (let i = 0; i < 14; i++) {
      const sm = new THREE.Mesh(this.shardGeo, m);
      sm.position.copy(p.pos).add(new THREE.Vector3(0, 0.03, 0));
      sm.scale.setScalar(rand(0.5, 1.4));
      this.parent.add(sm);
      this.shards.push({
        m: sm,
        v: new THREE.Vector3(rand(-1.2, 1.2), rand(0.6, 1.8), rand(-1.2, 1.2)),
        s: new THREE.Vector3(rand(-10, 10), 0, rand(-10, 10)),
        life: 60,
        ground: p.pos.y,
      });
    }
  }
}

/* ------------------------------------------------------------ carryables */

export class Carryable {
  pos = new THREE.Vector3();
  yaw = 0;
  carried = false;
  enabled = true;
  /** vertical offset of the mesh origin when resting on a surface */
  restOffset = 0;

  constructor(
    public id: string,
    public name: string,
    public mesh: THREE.Object3D,
  ) {}

  place(p: THREE.Vector3, yaw = this.yaw) {
    this.pos.copy(p);
    this.yaw = yaw;
    this.mesh.position.copy(p);
    this.mesh.position.y += this.restOffset;
    this.mesh.rotation.set(0, yaw, 0);
  }
}

export function makeClueMesh(id: 'foto' | 'coleira' | 'chave' | 'toy'): THREE.Object3D {
  const g = new THREE.Group();
  if (id === 'foto') {
    const f = new THREE.Mesh(new THREE.BoxGeometry(0.15, 0.012, 0.11), mat('frame'));
    f.position.y = 0.006;
    const p = new THREE.Mesh(new THREE.PlaneGeometry(0.12, 0.085), stdMat({ map: textures().photo, roughness: 0.7 }));
    p.rotation.x = -Math.PI / 2;
    p.position.y = 0.0125;
    g.add(f, p);
  } else if (id === 'coleira') {
    const ring = new THREE.Mesh(new THREE.TorusGeometry(0.05, 0.01, 6, 18), stdMat({ color: '#7a1f1f', roughness: 0.6 }));
    ring.rotation.x = Math.PI / 2;
    ring.position.y = 0.012;
    const bell = new THREE.Mesh(new THREE.SphereGeometry(0.014, 8, 6), mat('brass'));
    bell.position.set(0, 0.012, 0.062);
    const tag = new THREE.Mesh(new THREE.CylinderGeometry(0.014, 0.014, 0.003, 10), mat('brass'));
    tag.position.set(0.02, 0.006, 0.062);
    g.add(ring, bell, tag);
  } else if (id === 'chave') {
    const bow = new THREE.Mesh(new THREE.TorusGeometry(0.02, 0.005, 6, 12), mat('brass'));
    bow.rotation.x = Math.PI / 2;
    bow.position.set(-0.04, 0.006, 0);
    const shaft = new THREE.Mesh(new THREE.BoxGeometry(0.07, 0.008, 0.008), mat('brass'));
    shaft.position.set(0.01, 0.006, 0);
    const bit = new THREE.Mesh(new THREE.BoxGeometry(0.012, 0.008, 0.02), mat('brass'));
    bit.position.set(0.04, 0.006, 0.01);
    g.add(bow, shaft, bit);
  } else {
    const body = new THREE.Mesh(new THREE.SphereGeometry(0.035, 10, 8), stdMat({ color: '#9a9a9a', roughness: 0.9 }));
    body.scale.set(1, 0.8, 1.5);
    body.position.y = 0.03;
    g.add(body);
  }
  g.traverse((o) => {
    if ((o as THREE.Mesh).isMesh) o.castShadow = true;
  });
  return g;
}
