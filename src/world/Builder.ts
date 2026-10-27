import * as THREE from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import { ColliderWorld, type Box } from './Colliders';
import { mat } from '../render/Materials';

export interface PartOpts {
  col?: boolean;
  cam?: boolean;
  tag?: string;
  shadow?: boolean;
  /** world-space planar UVs (default true for boxes) */
  worldUV?: boolean;
  rotY?: number;
}

const _m = new THREE.Matrix4();
const _q = new THREE.Quaternion();
const _s = new THREE.Vector3();
const _p = new THREE.Vector3();
const _e = new THREE.Euler();

/** Recompute UVs from world positions so textures tile continuously across pieces. */
function worldUVs(g: THREE.BufferGeometry) {
  const pos = g.getAttribute('position') as THREE.BufferAttribute;
  const nor = g.getAttribute('normal') as THREE.BufferAttribute;
  const uv = g.getAttribute('uv') as THREE.BufferAttribute;
  if (!uv) return;
  for (let i = 0; i < pos.count; i++) {
    const nx = Math.abs(nor.getX(i));
    const ny = Math.abs(nor.getY(i));
    const nz = Math.abs(nor.getZ(i));
    const x = pos.getX(i);
    const y = pos.getY(i);
    const z = pos.getZ(i);
    if (ny >= nx && ny >= nz) uv.setXY(i, x, z);
    else if (nx >= nz) uv.setXY(i, z, y);
    else uv.setXY(i, x, y);
  }
  uv.needsUpdate = true;
}

/**
 * Collects static geometry per material and merges it into one mesh per material at the end.
 * Also registers colliders. This keeps draw calls low (~1 per material) for the whole house.
 */
export class Builder {
  private parts = new Map<string, THREE.BufferGeometry[]>();
  private noShadow = new Set<string>();
  /** every axis-aligned box ever added (for the dev-time z-fighting check) */
  records: { key: string; min: number[]; max: number[] }[] = [];

  constructor(
    public root: THREE.Object3D,
    public col: ColliderWorld,
  ) {}

  private push(key: string, g: THREE.BufferGeometry, shadow = true) {
    let arr = this.parts.get(key);
    if (!arr) this.parts.set(key, (arr = []));
    const ng = g.index ? g.toNonIndexed() : g;
    if (!ng.getAttribute('uv')) {
      ng.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(ng.getAttribute('position').count * 2), 2));
    }
    // merge requires identical attribute sets
    for (const name of Object.keys(ng.attributes)) {
      if (name !== 'position' && name !== 'normal' && name !== 'uv') ng.deleteAttribute(name);
    }
    arr.push(ng);
    if (!shadow) this.noShadow.add(key);
  }

  /** Axis-aligned box from min/max corners. */
  box(key: string, x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, o: PartOpts = {}): Box | null {
    const w = Math.abs(x1 - x0);
    const h = Math.abs(y1 - y0);
    const d = Math.abs(z1 - z0);
    if (w < 1e-4 || h < 1e-4 || d < 1e-4) return null;
    const g = new THREE.BoxGeometry(w, h, d);
    g.translate((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2);
    if (o.worldUV !== false) worldUVs(g);
    this.push(key, g, o.shadow !== false);
    this.records.push({ key, min: [Math.min(x0, x1), Math.min(y0, y1), Math.min(z0, z1)], max: [Math.max(x0, x1), Math.max(y0, y1), Math.max(z0, z1)] });
    if (o.col !== false) {
      return this.col.add(
        new THREE.Vector3(Math.min(x0, x1), Math.min(y0, y1), Math.min(z0, z1)),
        new THREE.Vector3(Math.max(x0, x1), Math.max(y0, y1), Math.max(z0, z1)),
        { tag: o.tag, camera: o.cam ?? true },
      );
    }
    return null;
  }

  /** Centered box (cx, cy = bottom, cz) with optional yaw. y is the BOTTOM of the box. */
  boxC(key: string, cx: number, y: number, cz: number, w: number, h: number, d: number, o: PartOpts = {}): Box | null {
    const rot = o.rotY ?? 0;
    if (Math.abs(rot) < 1e-5) return this.box(key, cx - w / 2, y, cz - d / 2, cx + w / 2, y + h, cz + d / 2, o);
    const g = new THREE.BoxGeometry(w, h, d);
    _m.compose(_p.set(cx, y + h / 2, cz), _q.setFromEuler(_e.set(0, rot, 0)), _s.set(1, 1, 1));
    g.applyMatrix4(_m);
    if (o.worldUV !== false) worldUVs(g);
    this.push(key, g, o.shadow !== false);
    if (o.col !== false) {
      g.computeBoundingBox();
      const bb = g.boundingBox!;
      return this.col.add(bb.min, bb.max, { tag: o.tag, camera: o.cam ?? true });
    }
    return null;
  }

  /** Arbitrary geometry, transformed. Collider = its world AABB if requested (default no). */
  geo(key: string, g: THREE.BufferGeometry, matrix: THREE.Matrix4, o: PartOpts = {}): Box | null {
    const gg = g.clone();
    gg.applyMatrix4(matrix);
    if (o.worldUV) worldUVs(gg);
    this.push(key, gg, o.shadow !== false);
    if (o.col) {
      gg.computeBoundingBox();
      const bb = gg.boundingBox!;
      return this.col.add(bb.min, bb.max, { tag: o.tag, camera: o.cam ?? true });
    }
    return null;
  }

  cyl(key: string, x: number, y: number, z: number, rTop: number, rBot: number, h: number, seg = 12, o: PartOpts = {}) {
    const g = new THREE.CylinderGeometry(rTop, rBot, h, seg);
    _m.makeTranslation(x, y + h / 2, z);
    return this.geo(key, g, _m, o);
  }

  sphere(key: string, x: number, y: number, z: number, r: number, sx = 1, sy = 1, sz = 1, o: PartOpts = {}) {
    const g = new THREE.IcosahedronGeometry(r, 1);
    _m.compose(_p.set(x, y, z), _q.identity(), _s.set(sx, sy, sz));
    return this.geo(key, g, _m, o);
  }

  /**
   * Dev check: pairs of boxes with different materials that share a face plane
   * (same facing) and overlap in area. Those z-fight and show as flickering textures.
   */
  findCoplanar(eps = 0.002, minArea = 1e-4) {
    const out: { a: string; b: string; axis: string; at: number; area: number; where: number[] }[] = [];
    const r = this.records;
    const axes = ['x', 'y', 'z'] as const;
    for (let i = 0; i < r.length; i++) {
      for (let j = i + 1; j < r.length; j++) {
        const A = r[i];
        const B = r[j];
        if (A.key === B.key) continue;
        for (let ax = 0; ax < 3; ax++) {
          const o1 = (ax + 1) % 3;
          const o2 = (ax + 2) % 3;
          const ov1 = Math.min(A.max[o1], B.max[o1]) - Math.max(A.min[o1], B.min[o1]);
          const ov2 = Math.min(A.max[o2], B.max[o2]) - Math.max(A.min[o2], B.min[o2]);
          if (ov1 <= 0 || ov2 <= 0 || ov1 * ov2 < minArea) continue;
          for (const side of ['min', 'max'] as const) {
            if (Math.abs(A[side][ax] - B[side][ax]) < eps) {
              // skip faces buried inside a third box (not visible)
              const c = [0, 0, 0];
              c[ax] = A[side][ax] + (side === 'min' ? -1 : 1) * 0.004;
              c[o1] = (Math.max(A.min[o1], B.min[o1]) + Math.min(A.max[o1], B.max[o1])) / 2;
              c[o2] = (Math.max(A.min[o2], B.min[o2]) + Math.min(A.max[o2], B.max[o2])) / 2;
              let buried = false;
              for (let k = 0; k < r.length && !buried; k++) {
                if (k === i || k === j) continue;
                const C = r[k];
                buried = c[0] > C.min[0] && c[0] < C.max[0] && c[1] > C.min[1] && c[1] < C.max[1] && c[2] > C.min[2] && c[2] < C.max[2];
              }
              if (buried) continue;
              out.push({
                a: A.key,
                b: B.key,
                axis: axes[ax] + (side === 'min' ? '-' : '+'),
                at: +A[side][ax].toFixed(3),
                area: +(ov1 * ov2).toFixed(4),
                where: [Math.max(A.min[0], B.min[0]), Math.max(A.min[1], B.min[1]), Math.max(A.min[2], B.min[2])].map((v) => +v.toFixed(2)),
              });
            }
          }
        }
      }
    }
    return out;
  }

  /**
   * Dev check: boxes that touch nothing (no support below, no neighbour at the sides).
   * Those are floating furniture or parts that stick out in mid-air.
   */
  findFloating(eps = 0.02) {
    const skip = /^(wall_|floor_|ceiling|exterior|roof|grass|asphalt|sidewalk|glass|plant|leaves|bark|stone|fence)/;
    const r = this.records;
    const out: { key: string; min: number[]; max: number[] }[] = [];
    for (const A of r) {
      if (skip.test(A.key)) continue;
      let ok = false;
      for (const B of r) {
        if (B === A) continue;
        // sits on top of / hangs under B
        const ox = Math.min(A.max[0], B.max[0]) - Math.max(A.min[0], B.min[0]);
        const oz = Math.min(A.max[2], B.max[2]) - Math.max(A.min[2], B.min[2]);
        const oy = Math.min(A.max[1], B.max[1]) - Math.max(A.min[1], B.min[1]);
        if (ox > -eps && oz > -eps && oy > -eps) {
          // touching or overlapping in all three axes
          ok = true;
          break;
        }
      }
      if (!ok) out.push(A);
    }
    return out;
  }

  /** Merge everything. Returns the created meshes. */
  finish(): THREE.Mesh[] {
    const out: THREE.Mesh[] = [];
    for (const [key, arr] of this.parts) {
      if (!arr.length) continue;
      const merged = mergeGeometries(arr, false);
      if (!merged) continue;
      merged.computeBoundingSphere();
      const m = mat(key);
      const mesh = new THREE.Mesh(merged, m);
      mesh.name = `static:${key}`;
      const shadow = !this.noShadow.has(key) && !m.transparent;
      mesh.castShadow = shadow;
      mesh.receiveShadow = true;
      mesh.matrixAutoUpdate = false;
      mesh.updateMatrix();
      this.root.add(mesh);
      out.push(mesh);
      for (const g of arr) g.dispose();
    }
    this.parts.clear();
    return out;
  }
}

/** Standalone mesh helper for dynamic objects (doors, lids, props). */
export function boxMesh(key: string | THREE.Material, w: number, h: number, d: number, worldish = true) {
  const g = new THREE.BoxGeometry(w, h, d);
  if (worldish) {
    // meter-based uv so textures keep their scale
    const pos = g.getAttribute('position') as THREE.BufferAttribute;
    const nor = g.getAttribute('normal') as THREE.BufferAttribute;
    const uv = g.getAttribute('uv') as THREE.BufferAttribute;
    for (let i = 0; i < pos.count; i++) {
      const nx = Math.abs(nor.getX(i));
      const ny = Math.abs(nor.getY(i));
      const x = pos.getX(i) + w / 2;
      const y = pos.getY(i) + h / 2;
      const z = pos.getZ(i) + d / 2;
      if (ny > 0.5) uv.setXY(i, x, z);
      else if (nx > 0.5) uv.setXY(i, z, y);
      else uv.setXY(i, x, y);
    }
  }
  const m = new THREE.Mesh(g, typeof key === 'string' ? mat(key) : key);
  m.castShadow = true;
  m.receiveShadow = true;
  return m;
}

/** Rectangle minus a list of holes (all axis aligned) -> list of rectangles. */
export function rectMinus(
  r: { x0: number; x1: number; z0: number; z1: number },
  holes: { x0: number; x1: number; z0: number; z1: number }[],
) {
  let rects = [r];
  for (const h of holes) {
    const next: typeof rects = [];
    for (const a of rects) {
      if (h.x1 <= a.x0 || h.x0 >= a.x1 || h.z1 <= a.z0 || h.z0 >= a.z1) {
        next.push(a);
        continue;
      }
      const ix0 = Math.max(a.x0, h.x0);
      const ix1 = Math.min(a.x1, h.x1);
      const iz0 = Math.max(a.z0, h.z0);
      const iz1 = Math.min(a.z1, h.z1);
      if (a.z0 < iz0) next.push({ x0: a.x0, x1: a.x1, z0: a.z0, z1: iz0 });
      if (iz1 < a.z1) next.push({ x0: a.x0, x1: a.x1, z0: iz1, z1: a.z1 });
      if (a.x0 < ix0) next.push({ x0: a.x0, x1: ix0, z0: iz0, z1: iz1 });
      if (ix1 < a.x1) next.push({ x0: ix1, x1: a.x1, z0: iz0, z1: iz1 });
    }
    rects = next;
  }
  return rects;
}
