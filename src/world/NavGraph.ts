import * as THREE from 'three';
import { NAV_EDGES, NAV_NODES, ROOMS, type RoomId } from './Layout';

export interface NavNode {
  id: string;
  p: THREE.Vector3;
  room: RoomId;
  links: { to: NavNode; ghostOnly: boolean; cost: number }[];
}

export class NavGraph {
  nodes = new Map<string, NavNode>();

  constructor() {
    for (const n of NAV_NODES) this.nodes.set(n.id, { id: n.id, p: new THREE.Vector3(...n.p), room: n.room, links: [] });
    for (const [a, b, ghost] of NAV_EDGES) {
      const na = this.nodes.get(a)!;
      const nb = this.nodes.get(b)!;
      if (!na || !nb) throw new Error(`bad nav edge ${a}-${b}`);
      const cost = na.p.distanceTo(nb.p);
      na.links.push({ to: nb, ghostOnly: !!ghost, cost });
      nb.links.push({ to: na, ghostOnly: !!ghost, cost });
    }
  }

  get(id: string) {
    const n = this.nodes.get(id);
    if (!n) throw new Error(`no nav node ${id}`);
    return n;
  }

  /** Nearest node on roughly the same floor as p. */
  nearest(p: THREE.Vector3, ghost = false): NavNode {
    let best: NavNode | null = null;
    let bd = Infinity;
    for (const n of this.nodes.values()) {
      if (!ghost && n.room === 'sotao') continue;
      const dy = Math.abs(n.p.y - p.y);
      const d = Math.hypot(n.p.x - p.x, n.p.z - p.z) + dy * 4;
      if (d < bd) {
        bd = d;
        best = n;
      }
    }
    return best!;
  }

  /** A* between nodes. */
  route(from: NavNode, to: NavNode, ghost = false, extra?: (n: NavNode) => number): NavNode[] {
    if (from === to) return [from];
    const open = new Set<NavNode>([from]);
    const came = new Map<NavNode, NavNode>();
    const g = new Map<NavNode, number>([[from, 0]]);
    const f = new Map<NavNode, number>([[from, from.p.distanceTo(to.p)]]);
    while (open.size) {
      let cur: NavNode | null = null;
      let best = Infinity;
      for (const n of open) {
        const v = f.get(n) ?? Infinity;
        if (v < best) {
          best = v;
          cur = n;
        }
      }
      if (!cur) break;
      if (cur === to) {
        const path = [cur];
        while (came.has(cur!)) {
          cur = came.get(cur!)!;
          path.unshift(cur);
        }
        return path;
      }
      open.delete(cur);
      for (const l of cur.links) {
        if (l.ghostOnly && !ghost) continue;
        const ng = (g.get(cur) ?? Infinity) + l.cost + (extra ? extra(l.to) : 0);
        if (ng < (g.get(l.to) ?? Infinity)) {
          came.set(l.to, cur);
          g.set(l.to, ng);
          f.set(l.to, ng + l.to.p.distanceTo(to.p));
          open.add(l.to);
        }
      }
    }
    return [from, to];
  }

  /** World-space path of points from a position to a node (optionally ending at an exact point). */
  pathTo(from: THREE.Vector3, toId: string, end?: THREE.Vector3, ghost = false): THREE.Vector3[] {
    const a = this.nearest(from, ghost);
    const b = this.get(toId);
    const nodes = this.route(a, b, ghost);
    const pts = nodes.map((n) => n.p.clone());
    // skip the first node if we are already past it towards the second
    if (pts.length > 1) {
      const d0 = from.distanceTo(pts[1]);
      const d01 = pts[0].distanceTo(pts[1]);
      if (d0 < d01 && Math.abs(from.y - pts[0].y) < 0.6) pts.shift();
    }
    if (end) pts.push(end.clone());
    return pts;
  }

  /** Graph hop count between rooms (for sound occlusion). */
  private roomHops: Map<string, number> | null = null;
  hops(a: RoomId, b: RoomId): number {
    if (a === b) return 0;
    if (!this.roomHops) this.buildRoomHops();
    return this.roomHops!.get(`${a}|${b}`) ?? 4;
  }

  private buildRoomHops() {
    const adj = new Map<RoomId, Set<RoomId>>();
    for (const r of ROOMS) adj.set(r.id, new Set());
    for (const n of this.nodes.values())
      for (const l of n.links) if (l.to.room !== n.room) adj.get(n.room)!.add(l.to.room);
    adj.get('banheiro_cima')!.add('varanda');
    adj.get('varanda')!.add('banheiro_cima');
    this.roomHops = new Map();
    for (const r of ROOMS) {
      const dist = new Map<RoomId, number>([[r.id, 0]]);
      const q: RoomId[] = [r.id];
      while (q.length) {
        const c = q.shift()!;
        for (const nb of adj.get(c)!) {
          if (dist.has(nb)) continue;
          dist.set(nb, dist.get(c)! + 1);
          q.push(nb);
        }
      }
      for (const [k, v] of dist) this.roomHops.set(`${r.id}|${k}`, v);
    }
  }
}

/** Which room contains a point (null if outside). */
export function roomAt(p: THREE.Vector3): RoomId | null {
  let best: RoomId | null = null;
  for (const r of ROOMS) {
    if (p.x < r.x0 - 0.01 || p.x > r.x1 + 0.01 || p.z < r.z0 - 0.01 || p.z > r.z1 + 0.01) continue;
    if (p.y < r.y - 0.45 || p.y > r.y + r.h + 0.1) continue;
    // stairwells: prefer the room whose floor is closer below
    if (!best) best = r.id;
    else {
      const rb = ROOMS.find((x) => x.id === best)!;
      if (Math.abs(p.y - r.y) < Math.abs(p.y - rb.y)) best = r.id;
    }
  }
  return best;
}
