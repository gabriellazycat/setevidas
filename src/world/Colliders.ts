import * as THREE from 'three';

export interface Box {
  id: number;
  min: THREE.Vector3;
  max: THREE.Vector3;
  enabled: boolean;
  tag: string;
  /** blocks the camera ray (walls, big furniture) */
  camera: boolean;
  stamp: number;
}

const CELL = 1;

/** Axis-aligned box world with a uniform XZ grid. All gameplay collision runs on this. */
export class ColliderWorld {
  boxes: Box[] = [];
  private grid = new Map<number, Box[]>();
  private stamp = 1;

  private key(ix: number, iz: number) {
    return (ix + 512) * 4096 + (iz + 512);
  }

  add(
    min: THREE.Vector3,
    max: THREE.Vector3,
    opts: { tag?: string; camera?: boolean; enabled?: boolean } = {},
  ): Box {
    const b: Box = {
      id: this.boxes.length,
      min: min.clone(),
      max: max.clone(),
      enabled: opts.enabled ?? true,
      tag: opts.tag ?? '',
      camera: opts.camera ?? true,
      stamp: 0,
    };
    this.boxes.push(b);
    this.insert(b);
    return b;
  }

  addCentered(cx: number, cy: number, cz: number, w: number, h: number, d: number, opts?: Parameters<ColliderWorld['add']>[2]) {
    return this.add(
      new THREE.Vector3(cx - w / 2, cy - h / 2, cz - d / 2),
      new THREE.Vector3(cx + w / 2, cy + h / 2, cz + d / 2),
      opts,
    );
  }

  private insert(b: Box) {
    const x0 = Math.floor(b.min.x / CELL);
    const x1 = Math.floor(b.max.x / CELL);
    const z0 = Math.floor(b.min.z / CELL);
    const z1 = Math.floor(b.max.z / CELL);
    for (let ix = x0; ix <= x1; ix++)
      for (let iz = z0; iz <= z1; iz++) {
        const k = this.key(ix, iz);
        let arr = this.grid.get(k);
        if (!arr) this.grid.set(k, (arr = []));
        arr.push(b);
      }
  }

  query(x0: number, z0: number, x1: number, z1: number, out: Box[] = []): Box[] {
    out.length = 0;
    const s = ++this.stamp;
    const ix0 = Math.floor(x0 / CELL);
    const ix1 = Math.floor(x1 / CELL);
    const iz0 = Math.floor(z0 / CELL);
    const iz1 = Math.floor(z1 / CELL);
    for (let ix = ix0; ix <= ix1; ix++)
      for (let iz = iz0; iz <= iz1; iz++) {
        const arr = this.grid.get(this.key(ix, iz));
        if (!arr) continue;
        for (const b of arr) {
          if (b.stamp === s || !b.enabled) continue;
          b.stamp = s;
          if (b.max.x < x0 || b.min.x > x1 || b.max.z < z0 || b.min.z > z1) continue;
          out.push(b);
        }
      }
    return out;
  }

  private tmp: Box[] = [];

  /** Highest surface top under (x,z) that is at most maxY. */
  groundHeight(x: number, z: number, maxY: number, r = 0.04): number {
    const list = this.query(x - r, z - r, x + r, z + r, this.tmp);
    let best = -1000;
    for (const b of list) {
      if (b.max.y > maxY + 1e-4) continue;
      if (x < b.min.x - r || x > b.max.x + r || z < b.min.z - r || z > b.max.z + r) continue;
      if (b.max.y > best) best = b.max.y;
    }
    return best;
  }

  /** Lowest box bottom above minY at (x,z). */
  ceilingHeight(x: number, z: number, minY: number, r = 0.04): number {
    const list = this.query(x - r, z - r, x + r, z + r, this.tmp);
    let best = 1000;
    for (const b of list) {
      if (b.min.y < minY - 1e-4) continue;
      if (x < b.min.x - r || x > b.max.x + r || z < b.min.z - r || z > b.max.z + r) continue;
      if (b.min.y < best) best = b.min.y;
    }
    return best;
  }

  /** Is any box overlapping the vertical segment [y0,y1] at (x,z) (with radius r)? */
  occupied(x: number, z: number, y0: number, y1: number, r = 0.05): boolean {
    const list = this.query(x - r, z - r, x + r, z + r, this.tmp);
    for (const b of list) {
      if (b.min.y >= y1 || b.max.y <= y0) continue;
      if (x < b.min.x - r || x > b.max.x + r || z < b.min.z - r || z > b.max.z + r) continue;
      return true;
    }
    return false;
  }

  /**
   * Push a vertical cylinder (feet at pos.y) out of every box it overlaps.
   * Boxes whose top is within `step` of the feet are ignored (they are climbed instead).
   */
  resolveCylinder(pos: THREE.Vector3, radius: number, height: number, step: number) {
    let hit = false;
    for (let iter = 0; iter < 3; iter++) {
      const list = this.query(pos.x - radius, pos.z - radius, pos.x + radius, pos.z + radius, this.tmp);
      let moved = false;
      for (const b of list) {
        if (b.max.y <= pos.y + step) continue;
        if (b.min.y >= pos.y + height) continue;
        // closest point on box (xz) to circle center
        const cx = Math.max(b.min.x, Math.min(pos.x, b.max.x));
        const cz = Math.max(b.min.z, Math.min(pos.z, b.max.z));
        let dx = pos.x - cx;
        let dz = pos.z - cz;
        const d2 = dx * dx + dz * dz;
        if (d2 >= radius * radius) continue;
        if (d2 > 1e-10) {
          const d = Math.sqrt(d2);
          const push = radius - d;
          pos.x += (dx / d) * push;
          pos.z += (dz / d) * push;
        } else {
          // center inside box: push out along smallest axis
          const px0 = pos.x - b.min.x;
          const px1 = b.max.x - pos.x;
          const pz0 = pos.z - b.min.z;
          const pz1 = b.max.z - pos.z;
          const m = Math.min(px0, px1, pz0, pz1);
          if (m === px0) pos.x = b.min.x - radius;
          else if (m === px1) pos.x = b.max.x + radius;
          else if (m === pz0) pos.z = b.min.z - radius;
          else pos.z = b.max.z + radius;
        }
        moved = true;
        hit = true;
      }
      if (!moved) break;
    }
    return hit;
  }

  /** Ray vs boxes (slab test). Returns distance or Infinity. */
  raycast(o: THREE.Vector3, dir: THREE.Vector3, maxDist: number, filter?: (b: Box) => boolean): number {
    const ex = o.x + dir.x * maxDist;
    const ez = o.z + dir.z * maxDist;
    const list = this.query(Math.min(o.x, ex), Math.min(o.z, ez), Math.max(o.x, ex), Math.max(o.z, ez), this.tmp);
    let best = maxDist;
    const inv = new THREE.Vector3(1 / dir.x, 1 / dir.y, 1 / dir.z);
    for (const b of list) {
      if (filter && !filter(b)) continue;
      let tmin = 0;
      let tmax = best;
      let ok = true;
      for (const ax of ['x', 'y', 'z'] as const) {
        const iv = inv[ax];
        let t1 = (b.min[ax] - o[ax]) * iv;
        let t2 = (b.max[ax] - o[ax]) * iv;
        if (t1 > t2) {
          const t = t1;
          t1 = t2;
          t2 = t;
        }
        if (!isFinite(iv)) {
          if (o[ax] < b.min[ax] || o[ax] > b.max[ax]) {
            ok = false;
            break;
          }
          continue;
        }
        tmin = Math.max(tmin, t1);
        tmax = Math.min(tmax, t2);
        if (tmin > tmax) {
          ok = false;
          break;
        }
      }
      if (ok && tmin < best) best = tmin;
    }
    return best >= maxDist ? Infinity : best;
  }

  /** True if line of sight between a and b is blocked by a camera-blocking box. */
  blocked(a: THREE.Vector3, b: THREE.Vector3) {
    const d = new THREE.Vector3().subVectors(b, a);
    const len = d.length();
    if (len < 1e-4) return false;
    d.divideScalar(len);
    return this.raycast(a, d, len - 0.05, (bx) => bx.camera) < len - 0.05;
  }
}
