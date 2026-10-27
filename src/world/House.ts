import * as THREE from 'three';
import { Builder, boxMesh, rectMinus } from './Builder';
import { ColliderWorld, type Box } from './Colliders';
import {
  ARCHES,
  CEILING_HOLES,
  DOORS,
  FLOOR_HOLES,
  HATCH,
  RITUAL_CENTER,
  ROOMS,
  STAIR_BASE,
  STAIR_MAIN,
  TERRAIN_Y,
  WALLS,
  WINDOWS,
  CAT_BED,
  type OpeningDef,
  type RoomId,
  type WallDef,
  type WindowDef,
} from './Layout';
import { Door } from './Doors';
import { decorate } from './Decor';
import { LightSystem } from './Lights';
import { NavGraph } from './NavGraph';
import { PropSystem, Carryable, makeClueMesh } from './Props';
import * as F from './Furniture';
import { mat, stdMat, markMat, Shared } from '../render/Materials';
import { textures } from '../render/Textures';
import { rand, clamp, damp } from '../core/math';

export interface Device {
  id: 'tv' | 'radio' | 'laptop';
  name: string;
  room: RoomId;
  pos: THREE.Vector3;
  outlet: THREE.Vector3;
  normal: THREE.Vector3;
  plugged: boolean;
  /** 0..1 how "on" the device is (driven by the Whisperer) */
  glow: number;
  mats: THREE.MeshStandardMaterial[];
  cord: THREE.Mesh;
  cordFrom: THREE.Vector3;
  plug: THREE.Mesh;
  floorY: number;
}

export interface Faucet {
  id: 'tub' | 'banb' | 'coz';
  name: string;
  room: RoomId;
  spout: THREE.Vector3;
  handle: THREE.Vector3;
  running: number;
  level: number;
  puddle: number;
  water: THREE.Mesh;
  stream: THREE.Mesh;
  puddleMesh: THREE.Mesh;
  bottomY: number;
  topY: number;
  floorY: number;
  puddleCenter: THREE.Vector3;
}

export interface Mark {
  id: string;
  day: number;
  pos: THREE.Vector3;
  mesh: THREE.Mesh;
  mat: THREE.MeshBasicMaterial;
  text: string;
}

const _m = new THREE.Matrix4();
const _v = new THREE.Vector3();

const CROWN = new Set(['wall_hall', 'wall_corredor', 'wall_sala', 'wall_escritorio', 'wall_quarto', 'wall_hospedes', 'wall_cozinha']);
const CURTAIN_COLOR: Record<string, string> = {
  w_quarto: 'fabric_cream',
  w_hosp: 'fabric_cream',
  w_esc: 'fabric_blue',
  w_coz: 'fabric_cream',
  w_banb: 'fabric_blue',
  w_cor: 'fabric_green',
};
const WAINSCOT: Record<string, string | undefined> = {
  wall_hall: 'wood_paint',
  wall_corredor: 'wood_paint',
  wall_sala: 'wood_paint',
  wall_escritorio: 'wood_paint_blue',
  wall_quarto: 'wood_paint',
};

/** Box geometry with meter UVs in local space (for rotated pieces). */
function localBox(w: number, h: number, d: number) {
  const g = new THREE.BoxGeometry(w, h, d);
  const pos = g.getAttribute('position') as THREE.BufferAttribute;
  const nor = g.getAttribute('normal') as THREE.BufferAttribute;
  const uv = g.getAttribute('uv') as THREE.BufferAttribute;
  for (let i = 0; i < pos.count; i++) {
    const nx = Math.abs(nor.getX(i));
    const ny = Math.abs(nor.getY(i));
    if (ny > 0.5) uv.setXY(i, pos.getX(i), pos.getZ(i));
    else if (nx > 0.5) uv.setXY(i, pos.getZ(i), pos.getY(i));
    else uv.setXY(i, pos.getX(i), pos.getY(i));
  }
  return g;
}

export class House {
  root = new THREE.Group();
  col = new ColliderWorld();
  b: Builder;
  lights: LightSystem;
  nav = new NavGraph();
  doors = new Map<string, Door>();
  props: PropSystem;
  devices: Device[] = [];
  faucets: Faucet[] = [];
  marks: Mark[] = [];
  carryables = new Map<string, Carryable>();
  windows: WindowDef[] = WINDOWS;

  chestLid!: THREE.Group;
  chestPos = new THREE.Vector3(3.1, 6, 9.0);
  chestOpen = 0;
  hatchPanel!: THREE.Group;
  hatchOpen = 0;
  ladder!: THREE.Group;
  ladderBoxes: Box[] = [];
  hatchBox!: Box;
  cord!: THREE.Mesh;
  ductGrates: THREE.Group[] = [];
  ductOpen = 0;
  basculante!: THREE.Group;
  basculanteOpen = 0;
  ritual!: THREE.Mesh;
  ritualMat!: THREE.MeshBasicMaterial;
  ritualGlow = 0;
  guestDust = new THREE.Group();
  guestMoveIn = new THREE.Group();
  davBlanketOn!: THREE.Mesh;
  davBlanketOff!: THREE.Mesh;
  blanketOn!: THREE.Mesh;
  blanketOff!: THREE.Mesh;
  bowlFood!: THREE.Mesh;
  catBed = new THREE.Vector3(...CAT_BED);
  shafts = new THREE.Group();
  dust!: THREE.Points;
  sheets: THREE.Mesh[] = [];
  treeSway: THREE.Object3D[] = [];
  outsideBlockers: Box[] = [];
  clockHand!: THREE.Object3D;
  clockPos = new THREE.Vector3(0.07, 2.0, 1.0);

  constructor(parent: THREE.Object3D) {
    parent.add(this.root);
    this.b = new Builder(this.root, this.col);
    this.lights = new LightSystem(this.root);
    this.props = new PropSystem(this.root, this.col);
    this.buildShell();
    this.buildStairs();
    this.buildRoof();
    this.buildExterior();
    this.buildFurniture();
    this.buildDynamic();
    this.b.finish();
    this.lights.setupSpills(this.doors);
    this.root.add(this.shafts);
    this.buildDust();
  }

  /* ================================================================ shell */

  private buildShell() {
    const b = this.b;
    // floors and ceilings
    for (const r of ROOMS) {
      const rect = { x0: r.x0, x1: r.x1, z0: r.z0, z1: r.z1 };
      for (const fr of rectMinus(rect, FLOOR_HOLES[r.id] ?? []))
        b.box(r.floor, fr.x0, r.y - 0.1, fr.z0, fr.x1, r.y, fr.z1, { tag: 'floor' });
      if (r.ceiling)
        for (const cr of rectMinus(rect, CEILING_HOLES[r.id] ?? []))
          b.box('ceiling', cr.x0, r.y + r.h, cr.z0, cr.x1, r.y + r.h + 0.1, cr.z1, { tag: 'ceiling' });
    }
    // stairwell floor edge under the kitchen landing (keeps the slab continuous)
    // walls
    for (const w of WALLS) this.buildWall(w);
    // windows
    for (const w of WINDOWS) this.buildWindow(w);
    // door trims
    for (const d of DOORS) this.trimOpening({ axis: d.axis, fixed: d.fixed, s0: d.s0, s1: d.s1, y0: d.y, y1: d.y + d.h }, d.style === 'front' ? 0.2 : 0.12);
    for (const a of ARCHES) this.trimOpening(a, 0.12);
  }

  private openingsOn(w: WallDef): OpeningDef[] {
    const out: OpeningDef[] = [];
    const yTop = w.y + w.h;
    const on = (o: OpeningDef) =>
      o.axis === w.axis && Math.abs(o.fixed - w.fixed) < 0.01 && o.s1 > w.a && o.s0 < w.b && o.y1 > w.y && o.y0 < yTop;
    for (const d of DOORS) {
      const o = { axis: d.axis, fixed: d.fixed, s0: d.s0, s1: d.s1, y0: d.y, y1: d.y + d.h };
      if (on(o)) out.push(o);
    }
    for (const win of WINDOWS) if (on(win)) out.push(win);
    for (const a of ARCHES) if (on(a)) out.push(a);
    return out.sort((p, q) => p.s0 - q.s0);
  }

  private buildWall(w: WallDef) {
    const ops = this.openingsOn(w);
    const y0 = w.y;
    const y1 = w.y + w.h;
    const segs: { s0: number; s1: number; ya: number; yb: number; base: boolean }[] = [];
    let cur = w.a;
    for (const o of ops) {
      const s0 = Math.max(o.s0, w.a);
      const s1 = Math.min(o.s1, w.b);
      if (s0 > cur) segs.push({ s0: cur, s1: s0, ya: y0, yb: y1, base: true });
      if (o.y0 > y0) segs.push({ s0, s1, ya: y0, yb: o.y0, base: true });
      if (o.y1 < y1) segs.push({ s0, s1, ya: o.y1, yb: y1, base: false });
      cur = Math.max(cur, s1);
    }
    if (cur < w.b) segs.push({ s0: cur, s1: w.b, ya: y0, yb: y1, base: true });

    const half = w.t / 2;
    for (const s of segs) {
      // two halves so each room gets its own finish
      if (w.axis === 'z') {
        if (w.neg) this.b.box(w.neg, w.fixed - half, s.ya, s.s0, w.fixed, s.yb, s.s1, { tag: 'wall' });
        if (w.pos) this.b.box(w.pos, w.fixed, s.ya, s.s0, w.fixed + half, s.yb, s.s1, { tag: 'wall' });
      } else {
        if (w.neg) this.b.box(w.neg, s.s0, s.ya, w.fixed - half, s.s1, s.yb, w.fixed, { tag: 'wall' });
        if (w.pos) this.b.box(w.pos, s.s0, s.ya, w.fixed, s.s1, s.yb, w.fixed + half, { tag: 'wall' });
      }
      // crown molding and wainscot on the finished interior faces
      {
        const fl = w.y < -2 ? -3 : w.y < 0.5 && w.y > -0.5 ? 0 : w.y > 2.5 && w.y < 3.5 ? 3 : w.y;
        for (const [side, key] of [
          [-1, w.neg],
          [1, w.pos],
        ] as const) {
          if (!key) continue;
          const face = w.fixed + side * half;
          const out = side * 0.045;
          if (CROWN.has(key) && s.yb >= y1 - 0.01) {
            if (w.axis === 'z') this.b.box('trim', Math.min(face, face + out), y1 - 0.1, s.s0, Math.max(face, face + out), y1, s.s1, { col: false, shadow: false });
            else this.b.box('trim', s.s0, y1 - 0.1, Math.min(face, face + out), s.s1, y1, Math.max(face, face + out), { col: false, shadow: false });
          }
          const wk = WAINSCOT[key];
          if (wk && s.ya <= y0 + 0.01) {
            const top = Math.min(fl + 1.05, s.yb);
            if (top > fl + 0.2) {
              const t = side * 0.012;
              const t2 = side * 0.03;
              if (w.axis === 'z') {
                this.b.box(wk, Math.min(face, face + t), fl + 0.1, s.s0, Math.max(face, face + t), top, s.s1, { col: false, shadow: false });
                if (top >= fl + 1.04) this.b.box('trim', Math.min(face, face + t2), top, s.s0, Math.max(face, face + t2), top + 0.04, s.s1, { col: false, shadow: false });
              } else {
                this.b.box(wk, s.s0, fl + 0.1, Math.min(face, face + t), s.s1, top, Math.max(face, face + t), { col: false, shadow: false });
                if (top >= fl + 1.04) this.b.box('trim', s.s0, top, Math.min(face, face + t2), s.s1, top + 0.04, Math.max(face, face + t2), { col: false, shadow: false });
              }
            }
          }
        }
      }
      // baseboards on interior sides
      if (s.base) {
        const floorY = w.y < -2 ? -3 : w.y < 0.5 && w.y > -0.5 ? 0 : w.y > 2.5 && w.y < 3.5 ? 3 : w.y;
        const bh = 0.1;
        for (const [side, key] of [
          [-1, w.neg],
          [1, w.pos],
        ] as const) {
          if (!key || key === 'exterior' || key === 'exterior_base') continue;
          if (w.axis === 'z') {
            const x = w.fixed + side * half;
            this.b.box('trim', Math.min(x, x + side * 0.018), floorY, s.s0, Math.max(x, x + side * 0.018), floorY + bh, s.s1, { col: false, shadow: false });
          } else {
            const z = w.fixed + side * half;
            this.b.box('trim', s.s0, floorY, Math.min(z, z + side * 0.018), s.s1, floorY + bh, Math.max(z, z + side * 0.018), { col: false, shadow: false });
          }
        }
      }
    }
  }

  private trimOpening(o: OpeningDef, t: number) {
    const tw = 0.07;
    const depth = t / 2 + 0.02;
    const b = this.b;
    if (o.axis === 'z') {
      b.box('trim', o.fixed - depth, o.y0, o.s0 - tw, o.fixed + depth, o.y1, o.s0, { col: false });
      b.box('trim', o.fixed - depth, o.y0, o.s1, o.fixed + depth, o.y1, o.s1 + tw, { col: false });
      b.box('trim', o.fixed - depth, o.y1, o.s0 - tw, o.fixed + depth, o.y1 + tw, o.s1 + tw, { col: false });
    } else {
      b.box('trim', o.s0 - tw, o.y0, o.fixed - depth, o.s0, o.y1, o.fixed + depth, { col: false });
      b.box('trim', o.s1, o.y0, o.fixed - depth, o.s1 + tw, o.y1, o.fixed + depth, { col: false });
      b.box('trim', o.s0 - tw, o.y1, o.fixed - depth, o.s1 + tw, o.y1 + tw, o.fixed + depth, { col: false });
    }
  }

  private buildWindow(w: WindowDef) {
    const b = this.b;
    const t = 0.2;
    const fw = 0.05;
    const L = (s0: number, s1: number, y0: number, y1: number, n0: number, n1: number, key: string, col = false) => {
      if (w.axis === 'z') return b.box(key, w.fixed + n0, y0, s0, w.fixed + n1, y1, s1, { col });
      return b.box(key, s0, y0, w.fixed + n0, s1, y1, w.fixed + n1, { col });
    };
    // frame
    L(w.s0, w.s1, w.y0, w.y0 + fw, -t / 2, t / 2, 'trim');
    L(w.s0, w.s1, w.y1 - fw, w.y1, -t / 2, t / 2, 'trim');
    L(w.s0, w.s0 + fw, w.y0, w.y1, -t / 2, t / 2, 'trim');
    L(w.s1 - fw, w.s1, w.y0, w.y1, -t / 2, t / 2, 'trim');
    if (!w.small) {
      const mid = (w.s0 + w.s1) / 2;
      L(mid - 0.02, mid + 0.02, w.y0, w.y1, -0.03, 0.03, 'trim');
      const my = w.y0 + (w.y1 - w.y0) * 0.55;
      L(w.s0, w.s1, my - 0.02, my + 0.02, -0.03, 0.03, 'trim');
    }
    // glass (not for the basculante, which is a separate pivoting pane)
    if (w.id !== 'w_basculante') L(w.s0 + fw, w.s1 - fw, w.y0 + fw, w.y1 - fw, -0.006, 0.006, 'glass');
    // interior sill (a ledge cats love)
    const inS = w.inside;
    const sillD = w.small ? 0.12 : 0.22;
    const sy = w.y0;
    if (inS > 0) L(w.s0 - 0.06, w.s1 + 0.06, sy - 0.04, sy + 0.004, t / 2 - 0.02, t / 2 + sillD, 'trim', true);
    else L(w.s0 - 0.06, w.s1 + 0.06, sy - 0.04, sy + 0.004, -t / 2 - sillD, -t / 2 + 0.02, 'trim', true);
    // exterior sill
    if (inS > 0) L(w.s0 - 0.05, w.s1 + 0.05, sy - 0.05, sy + 0.004, -t / 2 - 0.08, -t / 2 + 0.02, 'trim');
    else L(w.s0 - 0.05, w.s1 + 0.05, sy - 0.05, sy + 0.004, t / 2 - 0.02, t / 2 + 0.08, 'trim');
    if (w.curtains) F.curtains(b, w.axis, w.fixed, inS, w.s0, w.s1, w.y0, w.y1, CURTAIN_COLOR[w.id.split('_').slice(0, 2).join('_')] ?? 'fabric_green');
  }

  /* ================================================================ stairs */

  private buildStairs() {
    const b = this.b;
    // main staircase: 16 steps from z 4.0 (y 0) to z 8.5 (y 3), x 5..6.1
    {
      const s = STAIR_MAIN;
      const n = 16;
      const run = (s.z1 - s.z0) / n;
      const rise = 3 / n;
      for (let k = 0; k < n; k++) {
        const z0 = s.z0 + k * run;
        const top = (k + 1) * rise;
        b.box('wood_dark', s.x0, 0, z0, s.x1, top - 0.03, z0 + run, { tag: 'stair' });
        b.box('wood', s.x0, top - 0.03, z0 - 0.02, s.x1, top, z0 + run, { tag: 'stair' });
      }
      // stringer on the open side + handrail
      for (let k = 0; k < n - 1; k += 2) {
        const z = s.z0 + k * run + 0.1;
        const y = (k + 1) * rise;
        b.box('wood_paint', s.x1 - 0.06, y, z - 0.02, s.x1 - 0.02, y + 0.9, z + 0.02, { col: false });
      }
      const len = Math.hypot(s.z1 - s.z0, 3);
      const ang = Math.atan2(3, s.z1 - s.z0);
      const rail = localBox(0.06, 0.05, len);
      _m.makeRotationX(-ang).premultiply(new THREE.Matrix4().makeTranslation(s.x1 - 0.04, 1.5 + 0.95, (s.z0 + s.z1) / 2));
      b.geo('wood', rail, _m);
      // invisible guard on the open side
      for (let k = 0; k < n; k++) {
        const z0 = s.z0 + k * run;
        const top = (k + 1) * rise;
        b.col.add(new THREE.Vector3(s.x1 - 0.04, top, z0), new THREE.Vector3(s.x1 + 0.02, top + 0.9, z0 + run), { tag: 'rail', camera: false });
      }
      // first floor railing around the stair hole
      const fy = 3;
      b.box('wood', s.x1 - 0.03, fy + 0.9, s.z0, s.x1 + 0.03, fy + 0.95, s.z1, { col: false });
      b.box('wood', s.x0, fy + 0.9, s.z0 - 0.03, s.x1 + 0.03, fy + 0.95, s.z0 + 0.03, { col: false });
      for (let z = s.z0; z <= s.z1; z += 0.28) b.box('wood_paint', s.x1 - 0.015, fy, z - 0.015, s.x1 + 0.015, fy + 0.9, z + 0.015, { col: false });
      for (let x = s.x0 + 0.2; x <= s.x1; x += 0.28) b.box('wood_paint', x - 0.015, fy, s.z0 - 0.015, x + 0.015, fy + 0.9, s.z0 + 0.015, { col: false });
      b.col.add(new THREE.Vector3(s.x1 - 0.04, fy, s.z0), new THREE.Vector3(s.x1 + 0.04, fy + 0.95, s.z1), { tag: 'rail', camera: false });
      b.col.add(new THREE.Vector3(s.x0, fy, s.z0 - 0.04), new THREE.Vector3(s.x1 + 0.04, fy + 0.95, s.z0 + 0.04), { tag: 'rail', camera: false });
    }
    // basement stairs: from z 5.2 (y -3) up to z 9.2 (y 0), x 11..12
    {
      const s = STAIR_BASE;
      const n = 16;
      const run = (s.z1 - s.z0) / n;
      const rise = 3 / n;
      for (let k = 0; k < n; k++) {
        const z0 = s.z0 + k * run;
        const top = -3 + (k + 1) * rise;
        b.box('wood_dark', s.x0, -3, z0, s.x1, top, z0 + run, { tag: 'stair' });
      }
      // open side in the laundry: simple rail
      for (let k = 0; k < n; k += 3) {
        const z = s.z0 + k * run + 0.1;
        const y = -3 + (k + 1) * rise;
        b.box('wood', s.x0 + 0.02, y, z - 0.02, s.x0 + 0.06, y + 0.9, z + 0.02, { col: false });
      }
      for (let k = 0; k < n; k++) {
        const z0 = s.z0 + k * run;
        const top = -3 + (k + 1) * rise;
        b.col.add(new THREE.Vector3(s.x0 - 0.02, top, z0), new THREE.Vector3(s.x0 + 0.04, top + 0.9, z0 + run), { tag: 'rail', camera: false });
      }
    }
  }

  /* ================================================================ roof */

  private buildRoof() {
    const b = this.b;
    const ridgeY = 8.4;
    const ang = Math.atan2(2.4, 3.75);
    // west slope
    for (const side of [-1, 1]) {
      const eaveX = side < 0 ? -0.45 : 7.62;
      const ridgeX = 3.75;
      const horiz = Math.abs(ridgeX - eaveX);
      const slopeLen = horiz / Math.cos(ang);
      const cx = (eaveX + ridgeX) / 2;
      const yAt = (x: number) => 6 + (side < 0 ? x : 7.5 - x) * Math.tan(ang);
      const yc = yAt(cx);
      const rot = side < 0 ? ang : -ang;
      for (const [key, off, th] of [
        ['roof', 0.11, 0.08],
        ['wall_attic', 0.02, 0.04],
      ] as const) {
        const g = localBox(slopeLen, th, 10.8);
        _m.makeRotationZ(rot).premultiply(new THREE.Matrix4().makeTranslation(cx, yc + off, 5));
        b.geo(key, g, _m);
      }
      // collision strips under the slope
      const strips = 8;
      for (let i = 0; i < strips; i++) {
        const xa = side < 0 ? (i / strips) * 3.75 : 7.5 - ((i + 1) / strips) * 3.75;
        const xb = xa + 3.75 / strips;
        const low = Math.min(yAt(xa), yAt(xb));
        b.col.add(new THREE.Vector3(xa, low, -0.1), new THREE.Vector3(xb, ridgeY + 0.6, 10.1), { tag: 'roof', camera: true });
      }
    }
    // ridge cap
    b.box('roof', 3.6, ridgeY + 0.08, -0.4, 3.9, ridgeY + 0.2, 10.4, { col: false });
    // gables (front has the round window)
    for (const z of [0, 10]) {
      for (const [key, z0, z1] of [
        ['exterior', z === 0 ? -0.1 : 10.0, z === 0 ? 0 : 10.1],
        ['wall_attic', z === 0 ? 0 : 9.9, z === 0 ? 0.1 : 10.0],
      ] as const) {
        const sh = new THREE.Shape();
        sh.moveTo(-0.1, 5.8);
        sh.lineTo(7.6, 5.8);
        sh.lineTo(7.6, 6.0);
        sh.lineTo(3.75, ridgeY + 0.08);
        sh.lineTo(-0.1, 6.0);
        sh.closePath();
        if (z === 0) {
          const hole = new THREE.Path();
          hole.absarc(3.75, 7.15, 0.42, 0, Math.PI * 2, true);
          sh.holes.push(hole);
        }
        const g = new THREE.ExtrudeGeometry(sh, { depth: z1 - z0, bevelEnabled: false, curveSegments: 20 });
        _m.makeTranslation(0, 0, z0);
        b.geo(key, g, _m, { worldUV: true });
      }
      b.col.add(new THREE.Vector3(-0.1, 6, z === 0 ? -0.1 : 9.9), new THREE.Vector3(7.6, ridgeY, z === 0 ? 0.1 : 10.1), { tag: 'wall' });
    }
    // round window frame + glass
    const ring = new THREE.TorusGeometry(0.42, 0.05, 8, 28);
    _m.makeTranslation(3.75, 7.15, -0.02);
    b.geo('trim', ring, _m);
    const glass = new THREE.CircleGeometry(0.4, 24);
    _m.makeTranslation(3.75, 7.15, 0.0);
    b.geo('glass', glass, _m, { shadow: false });
    const bar = localBox(0.8, 0.03, 0.03);
    _m.makeTranslation(3.75, 7.15, 0.0);
    b.geo('trim', bar, _m);
    _m.makeRotationZ(Math.PI / 2).premultiply(new THREE.Matrix4().makeTranslation(3.75, 7.15, 0));
    b.geo('trim', localBox(0.8, 0.03, 0.03), _m);
    // bathroom flat roof + parapet
    b.box('roof', 7.5, 5.9, 5.9, 12.1, 6.0, 10.1);
    b.box('trim', 7.5, 6.0, 5.9, 12.15, 6.12, 5.98, { col: false });
    b.box('trim', 12.07, 6.0, 5.9, 12.15, 6.12, 10.1, { col: false });
    b.box('trim', 7.5, 6.0, 10.07, 12.15, 6.12, 10.15, { col: false });
    // fascia boards
    b.box('trim', -0.5, 5.62, -0.42, 7.67, 5.72, -0.36, { col: false });
    b.box('trim', -0.5, 5.62, 10.36, 7.67, 5.72, 10.42, { col: false });
    // eaves along the first-floor top on the balcony side (the balcony has no roof)
    // ground floor: roof over the kitchen back porch none
  }

  /* ================================================================ exterior */

  private buildExterior() {
    const b = this.b;
    const ty = TERRAIN_Y;
    // terrain around the house footprint
    const big = { x0: -60, x1: 72, z0: -60, z1: 70 };
    for (const r of rectMinus(big, [{ x0: -0.1, x1: 12.1, z0: -0.1, z1: 10.1 }]))
      b.box('grass', r.x0, ty - 0.3, r.z0, r.x1, ty, r.z1, { tag: 'terrain', shadow: true });
    // road + sidewalk
    b.box('asphalt', -60, ty + 0.005, -16, 72, ty + 0.01, -8.5, { col: false });
    for (let x = -58; x < 72; x += 6) b.box('fence', x, ty + 0.011, -12.35, x + 3, ty + 0.014, -12.2, { col: false, shadow: false });
    b.box('sidewalk', -60, ty, -8.5, 72, ty + 0.06, -6.5, { col: false });
    b.box('sidewalk', -60, ty, -16.0 - 2, 72, ty + 0.06, -16.0, { col: false });
    // path to the porch
    for (let z = -6.3; z < -2.9; z += 0.55) b.box('sidewalk', 6.0 + rand(-0.06, 0.06), ty, z, 6.9, ty + 0.04, z + 0.42, { col: false });
    // porch deck + steps + awning
    b.box('wood_dark', 5.2, ty, -1.6, 7.8, 0, 0, { tag: 'porch' });
    for (let i = 0; i < 4; i++) {
      const top = -0.225 * (i + 1);
      b.box('wood_dark', 5.7, ty, -1.6 - (i + 1) * 0.3, 7.2, top, -1.6 - i * 0.3, { tag: 'porch' });
    }
    for (const x of [5.3, 7.7]) b.box('wood_paint', x - 0.06, 0, -1.56, x + 0.06, 2.6, -1.44);
    b.box('roof', 5.0, 2.6, -1.9, 8.0, 2.72, 0.0, { col: false });
    b.box('trim', 5.0, 2.52, -1.92, 8.0, 2.6, -1.86, { col: false });
    // porch railing
    b.box('wood_paint', 5.2, 0, -1.58, 5.7, 0.08, -1.52, { col: false });
    b.box('wood_paint', 7.2, 0, -1.58, 7.8, 0.08, -1.52, { col: false });
    b.box('wood_paint', 5.2, 0.85, -1.58, 5.7, 0.9, -1.52, { col: false });
    b.box('wood_paint', 7.2, 0.85, -1.58, 7.8, 0.9, -1.52, { col: false });
    // house base trim at terrain
    b.box('exterior_base', -0.15, ty, -0.15, 12.15, ty + 0.12, -0.08, { col: false });
    // mailbox
    b.box('wood_dark', 4.6, ty, -5.9, 4.68, ty + 1.05, -5.82, { col: false });
    b.box('metal_dark', 4.45, ty + 1.05, -6.05, 4.85, ty + 1.3, -5.7, { col: false });
    // picket fence along the front with a gate gap
    const picket = (x0: number, x1: number, z: number) => {
      b.box('fence', x0, ty + 0.25, z - 0.02, x1, ty + 0.32, z + 0.02, { col: false });
      b.box('fence', x0, ty + 0.75, z - 0.02, x1, ty + 0.82, z + 0.02, { col: false });
      for (let x = x0; x < x1; x += 0.16) b.box('fence', x, ty, z - 0.012, x + 0.07, ty + 1.0, z + 0.012, { col: false });
    };
    picket(-8, 5.6, -5.6);
    picket(7.3, 20, -5.6);
    // side fences
    const sideFence = (x: number, z0: number, z1: number) => {
      b.box('fence', x - 0.02, ty + 0.25, z0, x + 0.02, ty + 0.32, z1, { col: false });
      b.box('fence', x - 0.02, ty + 0.75, z0, x + 0.02, ty + 0.82, z1, { col: false });
      for (let z = z0; z < z1; z += 0.16) b.box('fence', x - 0.012, ty, z, x + 0.012, ty + 1.0, z + 0.07, { col: false });
    };
    sideFence(-8, -5.6, 18);
    sideFence(20, -5.6, 18);
    // bushes along the facade
    for (const [x, z] of [
      [0.8, -0.7],
      [2.4, -0.8],
      [3.8, -0.6],
      [8.6, -0.7],
      [10.4, -0.8],
      [11.6, -0.6],
      [-0.7, 3],
      [-0.7, 7],
      [12.7, 7.5],
    ])
      b.sphere(Math.random() < 0.5 ? 'leaves' : 'leaves_b', x, ty + 0.3, z, 0.55, 1.1, 0.75, 1, { col: false });
    // trees
    const tree = (x: number, z: number, s: number) => {
      b.cyl('bark', x, ty, z, 0.12 * s, 0.22 * s, 3.2 * s, 7, { col: false });
      for (let i = 0; i < 6; i++) {
        const a = (i / 6) * Math.PI * 2 + rand(-0.4, 0.4);
        const r = rand(0.5, 1.2) * s;
        b.sphere(i % 2 ? 'leaves' : 'leaves_b', x + Math.cos(a) * r, ty + (3.0 + rand(-0.3, 1.2)) * s, z + Math.sin(a) * r, rand(0.9, 1.4) * s, 1, rand(0.8, 1.1), 1, { col: false });
      }
      b.sphere('leaves_b', x, ty + 4.2 * s, z, 1.3 * s, 1, 0.9, 1, { col: false });
    };
    tree(-3.5, 4, 1.2);
    tree(-4.5, 12, 1.4);
    tree(15.5, 13, 1.3);
    tree(16.5, 3, 1.1);
    tree(-2.5, -3.2, 0.9);
    tree(24, -2, 1.5);
    tree(-14, -3, 1.6);
    // the old tree by the balcony (its branches reach over the railing)
    b.cyl('bark', 13.6, ty, 1.2, 0.2, 0.32, 5.6, 8, { col: false });
    const branch = localBox(0.16, 0.16, 2.4);
    _m.makeRotationY(-1.1).multiply(new THREE.Matrix4().makeRotationX(-0.35)).premultiply(new THREE.Matrix4().makeTranslation(12.7, 4.6, 1.6));
    b.geo('bark', branch, _m);
    for (let i = 0; i < 7; i++) b.sphere(i % 2 ? 'leaves' : 'leaves_b', 13.6 + rand(-1.6, 1.0), 5.6 + rand(-0.6, 1.4), 1.2 + rand(-1.6, 1.6), rand(1.0, 1.6), 1, 0.85, 1, { col: false });
    // neighbour houses (silhouettes with a few lit windows)
    const neighbour = (x: number, z: number, w: number, d: number, h: number, lit: [number, number][]) => {
      b.box('exterior', x - w / 2, ty, z - d / 2, x + w / 2, ty + h, z + d / 2, { col: false });
      const rg = localBox(w + 0.6, 0.15, d * 0.62);
      for (const side of [-1, 1]) {
        _m.makeRotationX(side * 0.62).premultiply(new THREE.Matrix4().makeTranslation(x, ty + h + d * 0.18, z + side * d * 0.25));
        b.geo('roof', rg, _m, { shadow: false });
      }
      for (const [lx, ly] of lit) {
        const m = new THREE.Mesh(new THREE.PlaneGeometry(0.9, 1.1), new THREE.MeshBasicMaterial({ color: new THREE.Color('#ffb868').multiplyScalar(1.6) }));
        m.position.set(x + lx, ty + ly, z - d / 2 - 0.01);
        m.rotation.y = Math.PI;
        this.root.add(m);
      }
    };
    neighbour(-20, 3, 9, 8, 5.5, [[-2, 3.8]]);
    neighbour(33, 4, 10, 9, 6, [[3, 1.6]]);
    neighbour(4, -26, 11, 8, 6, []);
    neighbour(22, -27, 9, 8, 5.2, [[-1, 1.7]]);
    neighbour(-14, -26, 10, 8, 5.8, []);
    // a parked car
    b.box('plastic_red', 13, ty + 0.3, -11.8, 17.2, ty + 0.95, -10.1, { col: false });
    b.box('plastic_red', 14, ty + 0.95, -11.7, 16.4, ty + 1.45, -10.2, { col: false });
    b.box('glass', 13.98, ty + 1.0, -11.65, 16.42, ty + 1.42, -10.25, { col: false, shadow: false });
    for (const [x, z] of [
      [13.7, -11.85],
      [16.5, -11.85],
      [13.7, -10.05],
      [16.5, -10.05],
    ]) {
      const g = new THREE.CylinderGeometry(0.33, 0.33, 0.22, 14);
      _m.makeRotationX(Math.PI / 2).premultiply(new THREE.Matrix4().makeTranslation(x, ty + 0.33, z));
      b.geo('rubber', g, _m);
    }
    // keep the cat inside the house: invisible blockers around the balcony
    this.outsideBlockers.push(
      b.col.add(new THREE.Vector3(7.5, 3, -0.4), new THREE.Vector3(12.4, 6.5, 0.02), { tag: 'blocker', camera: false }),
      b.col.add(new THREE.Vector3(11.98, 3, -0.4), new THREE.Vector3(12.4, 6.5, 6.0), { tag: 'blocker', camera: false }),
    );
    // balcony railing
    for (let x = 7.6; x < 12; x += 0.22) b.box('wood_paint', x - 0.02, 3, -0.02, x + 0.02, 3.95, 0.02, { col: false });
    for (let z = 0.1; z < 6; z += 0.22) b.box('wood_paint', 11.98, 3, z - 0.02, 12.02, 3.95, z + 0.02, { col: false });
    b.box('wood', 7.5, 3.95, -0.05, 12.06, 4.02, 0.05);
    b.box('wood', 11.94, 3.95, -0.05, 12.06, 4.02, 6.0);
    b.box('trim', 7.5, 2.8, -0.12, 12.12, 3.0, -0.0, { col: false });
    b.box('trim', 12.0, 2.8, -0.12, 12.12, 3.0, 6.0, { col: false });
    // balcony underside fascia (the balcony floor is the ceiling of rooms below)
  }

  /* ================================================================ furniture */

  private buildFurniture() {
    const b = this.b;
    const r = this.root;
    const cs = (cx: number, cz: number, y: number, w: number, d: number, s = 0.5) => F.contactShadow(r, cx, cz, y, w, d, s);

    /* ---------- SALA (x 0..5, z 0..5.5, y 0) */
    F.rug(b, 1.1, 2.15, 3.9, 4.25, 0, 'carpet_red');
    F.sofa(b, 1.0, 1.0, 4.0, 1.9, 0, '+z', 'sofa');
    cs(2.5, 1.45, 0, 3.0, 0.9);
    F.table(b, 2.0, 2.7, 3.2, 3.4, 0, 0.42, 'wood_dark', 'wood_dark');
    cs(2.6, 3.05, 0, 1.2, 0.7, 0.35);
    b.box('wood_dark', 1.7, 0, 5.0, 3.3, 0.55, 5.44); // tv stand
    cs(2.5, 5.2, 0, 1.6, 0.44);
    F.armchair(b, 0.75, 3.85, 0, '+x', 'fabric_green');
    cs(0.75, 3.85, 0, 0.8, 0.8);
    F.shelf(b, 0.06, 4.4, 0.42, 5.42, 0, 1.9, 4, 'wood_dark', 'books');
    // floor lamp (decor)
    b.cyl('brass', 0.45, 0, 3.05, 0.012, 0.012, 1.5, 6, { col: false });
    b.cyl('brass', 0.45, 0, 3.05, 0.12, 0.14, 0.03, 12, { col: false });
    b.cyl('lampshade', 0.45, 1.45, 3.05, 0.14, 0.2, 0.25, 14, { col: false });
    // moving boxes
    F.boxStack(b, 4.5, 0.55, 0, [
      [0.55, 0.42, 0.5],
      [0.45, 0.36, 0.42],
    ]);
    F.cardboardBox(b, 4.45, 3.2, 0, 0.5, 0.35, 0.45, true);
    // paintings
    // radiator under the front window
    b.box('metal', 1.6, 0.15, 0.12, 3.4, 0.7, 0.24);
    // props
    this.props.add('cup', 2.35, 0.42, 3.0);
    this.props.add('book', 2.85, 0.42, 3.15, 0.4);
    this.props.add('vase', 3.05, 0.55, 5.2);
    this.props.add('frame', 1.85, 0.55, 5.25);

    /* ---------- ESCRITÓRIO (x 0..5, z 5.5..10) */
    F.rug(b, 1.0, 7.2, 3.8, 9.2, 0, 'carpet_blue');
    F.table(b, 1.5, 9.3, 3.3, 9.94, 0, 0.75, 'wood_dark', 'wood_dark');
    cs(2.4, 9.62, 0, 1.8, 0.64);
    F.chair(b, 2.45, 8.85, 0, '+z', 'wood_dark');
    F.shelf(b, 0.06, 5.66, 0.42, 6.9, 0, 2.0, 5, 'wood_dark', 'books');
    b.box('metal_dark', 4.2, 0, 5.66, 4.8, 1.1, 6.16); // filing cabinet
    for (let i = 0; i < 3; i++) b.box('metal', 4.42, 0.25 + i * 0.33, 6.16, 4.58, 0.28 + i * 0.33, 6.18, { col: false });
    b.box('wood', 0.1, 0, 7.4, 0.5, 0.6, 7.9); // side table under the window
    F.boxStack(b, 4.2, 7.3, 0, [
      [0.6, 0.45, 0.55],
      [0.5, 0.4, 0.45],
      [0.38, 0.3, 0.36],
    ]);
    this.props.add('cup', 3.05, 0.75, 9.55);
    this.props.add('book', 1.75, 0.75, 9.6, 0.2);
    this.props.add('pot', 0.3, 0.6, 7.65);

    /* ---------- HALL (x 5..7.5) */
    b.box('wood_dark', 7.0, 0, 0.4, 7.44, 0.9, 1.3); // shoe cabinet
    b.cyl('wood_dark', 5.35, 0, 0.4, 0.025, 0.025, 1.75, 6, { col: true });
    for (let i = 0; i < 4; i++) {
      const a = (i / 4) * Math.PI * 2;
      b.box('wood_dark', 5.35 + Math.cos(a) * 0.12 - 0.01, 1.6, 0.4 + Math.sin(a) * 0.12 - 0.01, 5.35 + Math.cos(a) * 0.12 + 0.01, 1.68, 0.4 + Math.sin(a) * 0.12 + 0.01, { col: false });
    }
    b.sphere('fabric_blue', 5.4, 1.35, 0.42, 0.18, 1, 1.6, 0.6, { col: false }); // coat
    b.box('wood', 7.1, 0, 2.6, 7.44, 0.8, 3.3); // side table
    b.box('plastic_black', 7.2, 0.8, 2.75, 7.38, 0.86, 2.95, { col: false }); // phone
    F.rug(b, 5.5, 0.35, 7.0, 3.2, 0, 'carpet_blue');
    b.box('wood_dark', 5.1, 0, 9.55, 5.9, 0.45, 9.94); // bench
    b.box('mirror', 7.42, 1.0, 0.45, 7.44, 1.9, 1.25, { col: false });
    this.props.add('vase', 7.27, 0.8, 3.15);

    /* ---------- COZINHA (x 7.5..12, z 3.5..10) */
    F.counter(b, 7.56, 9.35, 10.3, 9.94, 0, 0.9);
    // sink basin cut + stove details
    b.box('metal', 8.4, 0.86, 9.45, 9.2, 0.905, 9.85, { col: false });
    b.box('metal_dark', 9.4, 0.9, 9.4, 10.2, 0.92, 9.9, { col: false });
    for (const [x, z] of [
      [9.6, 9.55],
      [10.0, 9.55],
      [9.6, 9.78],
      [10.0, 9.78],
    ])
      b.cyl('metal_dark', x, 0.92, z, 0.07, 0.07, 0.015, 12, { col: false });
    // upper cabinets
    b.box('wood_paint_green', 7.56, 1.5, 9.6, 10.3, 2.2, 9.94);
    // fridge
    F.fridge(b, 7.56, 3.56, 8.26, 4.26, 0, 1.8);
    cs(7.9, 3.9, 0, 0.7, 0.7);
    // table + chairs
    F.table(b, 8.6, 6.2, 9.8, 7.2, 0, 0.76, 'wood', 'wood');
    cs(9.2, 6.7, 0, 1.2, 1.0, 0.4);
    F.chair(b, 9.2, 5.85, 0, '+z', 'wood');
    F.chair(b, 9.2, 7.55, 0, '-z', 'wood');
    // side counter along the stairwell wall (radio)
    F.counter(b, 10.4, 5.4, 10.94, 7.4, 0, 0.9);
    // small counter under the east window
    F.counter(b, 11.4, 3.56, 11.94, 5.1, 0, 0.9);
    // bowls
    b.cyl('bowl', 8.6, 0, 3.9, 0.09, 0.07, 0.05, 14, { col: false });
    b.cyl('metal', 8.9, 0, 3.92, 0.09, 0.07, 0.05, 14, { col: false });
    this.props.add('glass', 10.5, 0.9, 5.6);
    this.props.add('cup', 10.0, 0.9, 9.5);
    this.props.add('bottle', 11.6, 0.9, 4.5);
    this.props.add('pot', 7.9, 0.9, 9.6);

    /* ---------- BANHEIRO DE BAIXO (x 7.5..12, z 0..3.5) */
    F.pedestalSink(b, 9.3, 0.3, 0, '+z');
    b.box('mirror', 9.05, 1.2, 0.1, 9.55, 1.85, 0.12, { col: false });
    F.toilet(b, 10.62, 0.42, 0, '+z');
    // shower stall
    b.box('floor_tile', 11.0, 0, 2.5, 11.94, 0.06, 3.44);
    b.box('glass', 11.0, 0.06, 2.48, 11.94, 2.0, 2.52);
    b.box('glass', 10.98, 0.06, 2.5, 11.02, 2.0, 3.44);
    b.cyl('chrome', 11.75, 1.9, 3.3, 0.06, 0.06, 0.02, 10, { col: false });
    b.box('wood_paint', 7.56, 0, 2.55, 8.0, 0.9, 3.35); // cabinet
    b.box('fabric_cream', 8.2, 1.4, 3.42, 8.6, 1.9, 3.44, { col: false }); // towel
    this.props.add('bottle', 7.8, 0.9, 2.8);

    /* ---------- PORÃO (x 0..8, z 0..10, y -3) */
    const by = -3;
    F.shelf(b, 0.06, 3.0, 0.52, 6.0, by, 1.8, 4, 'metal_dark', 'jars');
    F.boxStack(b, 5.9, 0.6, by, [
      [0.7, 0.5, 0.6],
      [0.55, 0.4, 0.5],
    ]);
    F.cardboardBox(b, 6.75, 0.55, by, 0.55, 0.38, 0.5, true); // the box with the photo
    F.boxStack(b, 2.8, 9.3, by, [
      [0.6, 0.45, 0.55],
      [0.6, 0.45, 0.55],
      [0.45, 0.35, 0.4],
    ]);
    F.boxStack(b, 1.6, 9.4, by, [[0.5, 0.4, 0.45]]);
    F.sheetCovered(b, 3.5, 7.0, by, 0.9, 0.95, 0.85);
    F.sheetCovered(b, 1.5, 0.6, by, 1.8, 0.8, 0.8);
    F.sheetCovered(b, 6.9, 9.6, by, 0.6, 1.8, 0.35);
    this.sheetBoiler = F.boiler(b, 0.1, 8.9, 1.0, 9.8, by, r);
    F.table(b, 6.8, 3.0, 7.94, 4.4, by, 0.9, 'wood', 'wood');
    b.box('metal_dark', 7.0, by + 0.9, 3.3, 7.4, by + 0.95, 3.6, { col: false });
    b.cyl('plastic_red', 7.6, by + 0.9, 4.0, 0.08, 0.08, 0.2, 10, { col: false });
    // pipes along the ceiling
    for (const z of [2.0, 8.0]) {
      const g = new THREE.CylinderGeometry(0.05, 0.05, 8, 8);
      _m.makeRotationZ(Math.PI / 2).premultiply(new THREE.Matrix4().makeTranslation(4, -0.4, z));
      b.geo('metal_dark', g, _m);
    }

    /* ---------- LAVANDERIA (x 8..12, z 0..10, y -3) */
    F.washer(b, 8.47, 0.57, by, r, '+z');
    F.washer(b, 9.15, 0.57, by, r, '+z');
    b.box('ceramic', 9.8, by, 0.08, 10.5, by + 0.85, 0.68); // tanque
    b.box('wood_dark', 11.5, by, 1.0, 11.94, by + 1.6, 3.5); // shelf
    F.shelf(b, 11.5, 1.0, 11.94, 3.5, by, 1.6, 3, 'wood_dark', 'boxes');
    b.box('plastic_beige', 8.3, by, 2.2, 8.8, by + 0.4, 2.7); // basket
    // clothesline with hanging sheets (they sway)
    b.box('metal', 8.4, by + 1.8, 2.98, 11.0, by + 1.81, 3.0, { col: false });
    for (let i = 0; i < 3; i++) {
      const sh = new THREE.Mesh(new THREE.PlaneGeometry(0.7, 1.1, 4, 6), stdMat({ color: '#d8d2c4', roughness: 0.95, side: THREE.DoubleSide }));
      sh.position.set(8.9 + i * 0.85, by + 1.25, 2.99);
      sh.castShadow = true;
      r.add(sh);
      this.sheets.push(sh);
    }

    /* ---------- QUARTO (x 0..5, z 0..5.5, y 3) */
    const qy = 3;
    F.rug(b, 0.9, 1.3, 3.5, 4.3, qy, 'carpet_red');
    F.bed(b, 0.06, 2.0, 2.2, 3.6, qy, 'x0');
    cs(1.13, 2.8, qy, 2.2, 1.7, 0.6);
    b.box('wood_dark', 0.08, qy, 1.45, 0.52, qy + 0.55, 1.92); // nightstand L
    b.box('wood_dark', 0.08, qy, 3.68, 0.52, qy + 0.55, 4.15); // nightstand R
    b.box('wood_dark', 3.6, qy, 4.9, 4.94, qy + 2.1, 5.44); // wardrobe
    b.box('brass', 4.2, qy + 1.0, 4.88, 4.24, qy + 1.2, 4.9, { col: false });
    b.box('wood', 2.2, qy, 5.0, 3.4, qy + 0.85, 5.44); // dresser
    b.box('mirror', 2.4, qy + 1.0, 5.43, 3.2, qy + 1.8, 5.445, { col: false });
    F.boxStack(b, 4.5, 0.5, qy, [
      [0.55, 0.4, 0.5],
      [0.42, 0.34, 0.4],
    ]);
    this.props.add('glass', 0.3, qy + 0.55, 3.9);
    this.props.add('bottle', 2.5, qy + 0.85, 5.2);
    this.props.add('bottle', 2.65, qy + 0.85, 5.25);
    this.props.add('frame', 3.15, qy + 0.85, 5.25);
    // blankets: one shaped over a sleeper, one flat
    this.blanketOn = new THREE.Mesh(new THREE.SphereGeometry(0.5, 16, 10), mat('blanket'));
    this.blanketOn.scale.set(1.85, 0.42, 1.4);
    this.blanketOn.position.set(1.38, qy + 0.5, 2.8);
    this.blanketOn.castShadow = true;
    this.blanketOff = boxMesh('blanket', 1.3, 0.06, 1.62);
    this.blanketOff.position.set(1.5, qy + 0.52, 2.8);
    r.add(this.blanketOn, this.blanketOff);
    this.blanketOff.visible = false;

    // the guest room: dust sheets before Davi moves in, his things afterwards
    {
      const dust = boxMesh('white_sheet', 1.98, 0.07, 1.0);
      dust.position.set(1.09, qy + 0.5, 8.33);
      this.guestDust.add(dust);
      const linen = boxMesh('sheet', 1.96, 0.025, 0.98);
      linen.position.set(1.09, qy + 0.49, 8.33);
      const suit = boxMesh('plastic_black', 0.62, 0.22, 0.4);
      suit.position.set(4.3, qy + 0.0, 8.7);
      suit.rotation.y = 0.2;
      suit.position.y = qy;
      const pack = boxMesh('fabric_green', 0.3, 0.4, 0.18);
      pack.position.set(4.3, qy + 0.22, 8.7);
      pack.rotation.y = 0.2;
      const shoes = boxMesh('plastic_black', 0.12, 0.08, 0.28);
      shoes.position.set(2.5, qy, 9.0);
      const shoes2 = boxMesh('plastic_black', 0.12, 0.08, 0.28);
      shoes2.position.set(2.7, qy, 9.05);
      shoes2.rotation.y = 0.4;
      const photo = new THREE.Mesh(new THREE.PlaneGeometry(0.1, 0.07), stdMat({ map: textures().photo, roughness: 0.6 }));
      photo.position.set(0.3, qy + 0.62, 9.1);
      photo.rotation.set(-0.2, Math.PI / 2, 0);
      const mug = new THREE.Mesh(new THREE.CylinderGeometry(0.04, 0.035, 0.09, 10), mat('plastic_red'));
      mug.position.set(0.3, qy + 0.595, 9.3);
      this.davBlanketOn = new THREE.Mesh(new THREE.SphereGeometry(0.5, 16, 10), mat('fabric_blue'));
      this.davBlanketOn.scale.set(1.85, 0.42, 1.4);
      this.davBlanketOn.position.set(1.38, qy + 0.5, 8.33);
      this.davBlanketOn.castShadow = true;
      this.davBlanketOff = boxMesh('fabric_blue', 0.6, 0.07, 0.5);
      this.davBlanketOff.position.set(1.7, qy + 0.52, 8.33);
      this.guestMoveIn.add(linen, suit, pack, shoes, shoes2, photo, mug, this.davBlanketOn, this.davBlanketOff);
      this.davBlanketOn.visible = false;
      r.add(this.guestDust, this.guestMoveIn);
      this.guestMoveIn.visible = false;
    }

    /* ---------- HÓSPEDES (x 0..5, z 5.5..10, y 3) */
    F.bed(b, 0.06, 7.8, 2.1, 8.85, qy, 'x0', 'sheet');
    b.box('wood_dark', 0.08, qy, 8.95, 0.52, qy + 0.55, 9.45); // nightstand (Davi's lamp sits on it)
    F.boxStack(b, 2.6, 6.2, qy, [
      [0.6, 0.45, 0.55],
      [0.55, 0.4, 0.5],
      [0.4, 0.32, 0.38],
    ]);
    F.boxStack(b, 3.4, 6.1, qy, [[0.6, 0.5, 0.6]]);
    F.boxStack(b, 4.4, 7.2, qy, [
      [0.6, 0.45, 0.6],
      [0.5, 0.4, 0.5],
    ]);
    F.boxStack(b, 3.2, 9.4, qy, [
      [0.7, 0.5, 0.6],
      [0.6, 0.45, 0.5],
    ]);
    F.sheetCovered(b, 4.62, 6.0, qy, 0.5, 1.8, 0.3); // covered mirror
    // rocking chair (legs sit on the rockers, rockers on the floor)
    {
      const cx = 3.6;
      const cz = 8.0;
      for (const x of [cx - 0.22, cx + 0.22]) {
        const arc = new THREE.TorusGeometry(0.55, 0.014, 5, 20, Math.PI * 0.42);
        _m.makeRotationZ(-Math.PI / 2 - Math.PI * 0.21).premultiply(new THREE.Matrix4().makeRotationY(Math.PI / 2)).premultiply(new THREE.Matrix4().makeTranslation(x, qy + 0.55 + 0.014, cz));
        b.geo('wood_dark', arc, _m);
      }
      for (const [dx, dz] of [
        [-0.22, -0.2],
        [0.22, -0.2],
        [-0.22, 0.2],
        [0.22, 0.2],
      ] as const)
        b.box('wood_dark', cx + dx - 0.015, qy + 0.03, cz + dz - 0.015, cx + dx + 0.015, qy + 0.42, cz + dz + 0.015, { col: false });
      b.box('wood_dark', cx - 0.26, qy + 0.42, cz - 0.24, cx + 0.26, qy + 0.46, cz + 0.24);
      b.box('wood_dark', cx - 0.26, qy + 0.46, cz - 0.26, cx + 0.26, qy + 1.05, cz - 0.22);
      b.box('fabric_cream', cx - 0.24, qy + 0.46, cz - 0.2, cx + 0.24, qy + 0.5, cz + 0.22, { col: false });
    }
    this.props.add('pot', 2.6, qy + 1.25, 6.2);

    /* ---------- CORREDOR (x 5..7.5, y 3) */
    b.box('wood', 7.05, qy, 6.5, 7.44, qy + 0.8, 7.5);
    F.rug(b, 6.2, 4.4, 7.3, 9.6, qy, 'carpet_blue');
    this.props.add('vase', 7.25, qy + 0.8, 7.2);
    this.props.add('frame', 7.25, qy + 0.8, 6.75);

    /* ---------- BANHEIRO DE CIMA (x 7.5..12, z 6..10, y 3) */
    const tub = F.bathtub(b, 9.4, 9.2, 11.94, 9.94, qy, r);
    this.tubWater = tub;
    F.pedestalSink(b, 8.2, 6.3, qy, '-z');
    F.toilet(b, 11.52, 6.42, qy, '+z');
    b.box('wood_paint', 9.9, qy, 6.06, 10.9, qy + 0.9, 6.55); // cabinet under the basculante
    b.box('plastic_beige', 8.0, qy, 9.4, 8.45, qy + 0.5, 9.85);
    b.box('mirror', 7.95, qy + 1.2, 6.06, 8.45, qy + 1.85, 6.08, { col: false });
    b.box('fabric_blue', 11.0, qy + 1.3, 9.92, 11.4, qy + 1.9, 9.94, { col: false });
    this.props.add('bottle', 10.2, qy + 0.9, 6.3);
    this.props.add('glass', 10.6, qy + 0.9, 6.3);

    /* ---------- VARANDA (x 7.5..12, z 0..6, y 3) */
    F.plant(b, 11.6, 0.45, qy, 1.2);
    F.plant(b, 8.0, 0.45, qy, 1);
    F.plant(b, 11.6, 5.5, qy, 1.1);
    F.table(b, 9.9, 2.6, 10.6, 3.2, qy, 0.72, 'metal_dark', 'metal_dark');
    F.chair(b, 10.25, 2.15, qy, '+z', 'metal_dark');

    /* ---------- SÓTÃO (x 0..7.5, z 0..10, y 6) */
    const ay = 6;
    F.boxStack(b, 2.0, 2.2, ay, [
      [0.6, 0.45, 0.5],
      [0.5, 0.35, 0.45],
    ]);
    F.boxStack(b, 5.0, 8.5, ay, [[0.6, 0.45, 0.55]]);
    F.boxStack(b, 1.8, 6.5, ay, [[0.5, 0.4, 0.5]]);
    F.sheetCovered(b, 4.6, 6.4, ay, 0.6, 1.5, 0.5);
    F.sheetCovered(b, 2.6, 4.6, ay, 1.0, 0.7, 0.7);
    // dressmaker's mannequin
    b.cyl('wood_dark', 4.2, ay, 3.6, 0.15, 0.2, 0.05, 10, { col: false });
    b.cyl('wood_dark', 4.2, ay + 0.05, 3.6, 0.02, 0.02, 0.9, 6, { col: false });
    b.sphere('fabric_cream', 4.2, ay + 1.25, 3.6, 0.2, 1, 1.7, 0.75, { col: true });
    // rocking horse
    for (const [hx, hz] of [
      [2.84, 3.02],
      [3.34, 3.02],
      [2.84, 3.14],
      [3.34, 3.14],
    ] as const)
      b.box('wood_paint_blue', hx, ay + 0.05, hz, hx + 0.04, ay + 0.25, hz + 0.04, { col: false });
    b.box('wood_paint_blue', 2.8, ay + 0.25, 3.0, 3.4, ay + 0.5, 3.18);
    b.box('wood_paint_blue', 3.32, ay + 0.45, 3.02, 3.5, ay + 0.75, 3.16);
    b.box('wood_dark', 2.7, ay, 2.98, 3.6, ay + 0.05, 3.02, { col: false });
    b.box('wood_dark', 2.7, ay, 3.16, 3.6, ay + 0.05, 3.2, { col: false });
    // the chest (baú)
    b.box('wood_dark', 2.6, ay, 8.7, 3.6, ay + 0.42, 9.35);
    b.box('brass', 2.58, ay + 0.1, 8.68, 3.62, ay + 0.13, 9.37, { col: false });
    decorate(b, r, this.props);
    this.chestLid = new THREE.Group();
    this.chestLid.position.set(3.1, ay + 0.42, 9.35);
    const lid = boxMesh('wood_dark', 1.02, 0.1, 0.67);
    lid.position.set(0, 0.05, -0.335);
    this.chestLid.add(lid);
    r.add(this.chestLid);
    this.col.add(new THREE.Vector3(2.6, ay + 0.42, 8.7), new THREE.Vector3(3.6, ay + 0.52, 9.35), { tag: 'chest' });
  }

  sheetBoiler: THREE.Mesh | null = null;
  tubWater!: { water: THREE.Mesh; bottomY: number; topY: number };

  /* ================================================================ dynamic */

  private buildDynamic() {
    const r = this.root;
    // doors
    for (const d of DOORS) this.doors.set(d.id, new Door(d, r, this.col));

    // devices
    const tv = F.crtTV(this.b, 2.5, 5.2, 0.55, '-z', r);
    this.addDevice('tv', 'a TV', 'sala', new THREE.Vector3(2.5, 0.85, 5.2), new THREE.Vector3(3.55, 0.3, 5.43), new THREE.Vector3(0, 0, -1), [tv.screenMat], 0);
    const radio = F.radioSet(this.b, 10.66, 6.4, 0.9, '-x', r);
    this.addDevice('radio', 'o rádio', 'cozinha', new THREE.Vector3(10.66, 1.0, 6.4), new THREE.Vector3(10.93, 1.1, 6.95), new THREE.Vector3(-1, 0, 0), [radio.dialMat], 0.9);
    const lap = F.laptop(this.b, 2.4, 9.6, 0.75, r);
    this.addDevice('laptop', 'o notebook', 'escritorio', new THREE.Vector3(2.4, 0.85, 9.6), new THREE.Vector3(3.5, 0.3, 9.89), new THREE.Vector3(0, 0, -1), [lap.screenMat], 0);

    // faucets
    this.addFaucet('coz', 'a pia da cozinha', 'cozinha', new THREE.Vector3(8.8, 1.12, 9.8), new THREE.Vector3(8.8, 0.95, 9.72), 0.74, 0.88, 0, new THREE.Vector3(8.8, 0, 9.0), [0.78, 0.38]);
    this.addFaucet('banb', 'a pia do banheiro', 'banheiro_baixo', new THREE.Vector3(9.3, 1.0, 0.16), new THREE.Vector3(9.3, 0.88, 0.2), 0.8, 0.85, 0, new THREE.Vector3(9.3, 0, 0.9), [0.5, 0.4]);
    {
      const tw = this.tubWater;
      this.addFaucet('tub', 'a banheira', 'banheiro_cima', new THREE.Vector3(11.72, 3.78, 9.57), new THREE.Vector3(11.6, 3.62, 9.57), tw.bottomY, tw.topY, 3, new THREE.Vector3(10.6, 3, 8.8), null, tw.water);
    }

    // attic hatch + ladder
    this.hatchPanel = new THREE.Group();
    this.hatchPanel.position.set(HATCH.x0, 5.8, HATCH.z1);
    const panel = boxMesh('wood_paint', HATCH.x1 - HATCH.x0, 0.05, HATCH.z1 - HATCH.z0);
    panel.position.set((HATCH.x1 - HATCH.x0) / 2, 0.025, -(HATCH.z1 - HATCH.z0) / 2);
    this.hatchPanel.add(panel);
    r.add(this.hatchPanel);
    this.hatchBox = this.col.add(new THREE.Vector3(HATCH.x0, 5.8, HATCH.z0), new THREE.Vector3(HATCH.x1, 6.0, HATCH.z1), { tag: 'hatch' });
    this.ladder = new THREE.Group();
    const n = 12;
    for (let k = 0; k < n; k++) {
      const z1 = 2.9 - k * 0.15;
      const z0 = z1 - 0.15;
      const top = 3 + (k + 1) * 0.25;
      const step = boxMesh('wood', HATCH.x1 - HATCH.x0 - 0.1, 0.04, 0.12);
      step.position.set((HATCH.x0 + HATCH.x1) / 2, top - 0.02, (z0 + z1) / 2);
      this.ladder.add(step);
      this.ladderBoxes.push(this.col.add(new THREE.Vector3(HATCH.x0 + 0.05, 3, z0), new THREE.Vector3(HATCH.x1 - 0.05, top, z1), { tag: 'ladder', camera: false, enabled: false }));
    }
    for (const x of [HATCH.x0 + 0.04, HATCH.x1 - 0.04]) {
      const len = Math.hypot(1.8, 3);
      const rail = boxMesh('wood', 0.04, 0.08, len);
      rail.position.set(x, 4.5, 2.0);
      rail.rotation.x = Math.atan2(3, 1.8);
      this.ladder.add(rail);
    }
    this.ladder.visible = false;
    r.add(this.ladder);
    this.cord = new THREE.Mesh(new THREE.CylinderGeometry(0.006, 0.006, 2.3, 4), mat('fabric_cream'));
    this.cord.position.set(6.85, 5.8 - 1.15, 2.1);
    r.add(this.cord);
    const knob = new THREE.Mesh(new THREE.SphereGeometry(0.025, 8, 6), mat('wood'));
    knob.position.set(0, -1.15, 0);
    this.cord.add(knob);

    // duct grates (lavanderia south wall, kitchen wall z=3.5)
    for (const [x, y, z, rot] of [
      [10.95, -2.95, 0.105, 0],
      [10.8, 0.05, 3.565, Math.PI],
    ] as const) {
      const g = new THREE.Group();
      g.position.set(x - 0.18, y, z);
      g.rotation.y = rot;
      const frame = boxMesh('metal', 0.36, 0.3, 0.02);
      frame.position.set(0.18 * (rot ? -1 : 1), 0.15, 0);
      g.add(frame);
      for (let i = 0; i < 5; i++) {
        const slat = boxMesh('metal_dark', 0.32, 0.02, 0.03);
        slat.position.set(0.18 * (rot ? -1 : 1), 0.04 + i * 0.055, 0.01);
        g.add(slat);
      }
      r.add(g);
      this.ductGrates.push(g);
      // dark hole behind
      const hole = new THREE.Mesh(new THREE.PlaneGeometry(0.34, 0.28), new THREE.MeshBasicMaterial({ color: '#000000' }));
      hole.position.set(x, y + 0.15, z + (rot ? 0.005 : -0.005));
      if (rot) hole.rotation.y = Math.PI;
      r.add(hole);
    }

    // basculante pane
    this.basculante = new THREE.Group();
    this.basculante.position.set(10.0, 5.3, 6.0);
    const pane = new THREE.Mesh(new THREE.BoxGeometry(0.8, 0.7, 0.012), mat('glass'));
    pane.position.set(0.4, -0.35, 0);
    const pf = boxMesh('trim', 0.8, 0.04, 0.03);
    pf.position.set(0.4, -0.68, 0);
    this.basculante.add(pane, pf);
    r.add(this.basculante);
    this.basculanteBox = this.col.add(new THREE.Vector3(10.0, 4.6, 5.9), new THREE.Vector3(10.8, 5.3, 6.1), { tag: 'basculante' });

    // ritual circle
    this.ritualMat = new THREE.MeshBasicMaterial({ map: textures().chalk, transparent: true, opacity: 0, depthWrite: false, color: '#ffffff', polygonOffset: true, polygonOffsetFactor: -3 });
    this.ritual = new THREE.Mesh(new THREE.PlaneGeometry(2.4, 2.4), this.ritualMat);
    this.ritual.rotation.x = -Math.PI / 2;
    this.ritual.position.set(RITUAL_CENTER[0], RITUAL_CENTER[1] + 0.006, RITUAL_CENTER[2]);
    r.add(this.ritual);

    // cat bed + food
    const bed = new THREE.Mesh(new THREE.TorusGeometry(0.25, 0.09, 8, 20), mat('fabric_blue'));
    bed.rotation.x = Math.PI / 2;
    bed.position.set(this.catBed.x, 0.07, this.catBed.z);
    bed.castShadow = true;
    const cushion = new THREE.Mesh(new THREE.CylinderGeometry(0.24, 0.24, 0.05, 20), mat('fabric_cream'));
    cushion.position.set(this.catBed.x, 0.03, this.catBed.z);
    r.add(bed, cushion);
    this.bowlFood = new THREE.Mesh(new THREE.SphereGeometry(0.07, 10, 6, 0, Math.PI * 2, 0, Math.PI / 2), mat('cat_food'));
    this.bowlFood.scale.y = 0.35;
    this.bowlFood.position.set(8.6, 0.03, 3.9);
    this.bowlFood.visible = false;
    r.add(this.bowlFood);

    // clock hand
    this.clockHand = new THREE.Group();
    this.clockHand.position.set(0.108, 2.05, 1.0);
    const face = new THREE.Mesh(new THREE.CircleGeometry(0.15, 20), mat('paper'));
    face.rotation.y = Math.PI / 2;
    face.position.set(0.0, 0, 0);
    const hand = boxMesh('plastic_black', 0.005, 0.11, 0.012);
    hand.position.set(0.006, 0.05, 0);
    const handGroup = new THREE.Group();
    handGroup.add(hand);
    this.clockHand.add(face, handGroup);
    r.add(this.clockHand);
    this.clockHandInner = handGroup;

    // clues + toy
    this.addCarry('foto', 'a foto antiga', makeClueMesh('foto'), new THREE.Vector3(6.75, -3 + 0.02, 0.55));
    this.addCarry('coleira', 'a coleira antiga', makeClueMesh('coleira'), new THREE.Vector3(8.5, -3, 0.16));
    this.addCarry('chave', 'a chave do baú', makeClueMesh('chave'), new THREE.Vector3(2.0, 6 + 0.8, 2.2));
    this.addCarry('toy', 'o ratinho de brinquedo', makeClueMesh('toy'), new THREE.Vector3(3.6, 0, 4.0));

    // investigation marks (only visible in cat vision)
    this.addMark('m_tv', 2, 'claw', new THREE.Vector3(3.55, 0.45, 5.43), new THREE.Vector3(0, 0, -1), 'Arranhões perto da tomada da TV. Algo aqui gosta de eletricidade.');
    this.addMark('m_radio', 2, 'claw', new THREE.Vector3(10.93, 1.3, 6.95), new THREE.Vector3(-1, 0, 0), 'Marcas ao redor da tomada do rádio. Um sussurro ficou preso nos fios.');
    this.addMark('m_laptop', 2, 'claw', new THREE.Vector3(3.5, 0.45, 9.89), new THREE.Vector3(0, 0, -1), 'O notebook cheira a queimado. Tomadas são a porta de entrada dele.');
    this.addMark('m_tub', 3, 'hand', new THREE.Vector3(10.6, 3.85, 9.89), new THREE.Vector3(0, 0, -1), 'Mãos molhadas na parede da banheira. Ela vem pela água.');
    this.addMark('m_sink', 3, 'hand', new THREE.Vector3(8.8, 1.4, 9.89), new THREE.Vector3(0, 0, -1), 'A torneira da cozinha está gelada. Alguém a abre de dentro.');
    this.addMark('m_chest', 4, 'hand', new THREE.Vector3(3.1, 6.3, 8.69), new THREE.Vector3(0, 0, -1), 'Mãozinhas pequenas no baú, por dentro. Ela só anda quando ninguém olha.');
    this.addMark('m_door', 5, 'hand', new THREE.Vector3(6.45, 1.35, 0.03), new THREE.Vector3(0, 0, 1), 'Uma mão enorme do lado de dentro da porta da frente. Ele quer ser convidado.');
    this.addMark('m_hound', 2, 'claw', new THREE.Vector3(6.3, 0.012, 2.4), new THREE.Vector3(0, 1, 0), 'Marcas fundas de garras no piso do hall. Algo grande rondou por aqui, e não foi atrás de Clara: foi atrás de você.');
    this.addMark('m_porao', 2, 'claw', new THREE.Vector3(4.6, -2.99, 6.0), new THREE.Vector3(0, 1, 0), 'O chão do porão está riscado. A Sombra começa aqui, sempre.');
  }

  basculanteBox!: Box;
  clockHandInner!: THREE.Object3D;

  private addDevice(id: Device['id'], name: string, room: RoomId, pos: THREE.Vector3, outlet: THREE.Vector3, normal: THREE.Vector3, mats: THREE.MeshStandardMaterial[], floorY: number) {
    // outlet plate
    const plate = new THREE.Mesh(new THREE.BoxGeometry(0.07, 0.1, 0.012), mat('plastic_beige'));
    plate.position.copy(outlet);
    plate.lookAt(outlet.clone().add(normal));
    this.root.add(plate);
    const plug = new THREE.Mesh(new THREE.BoxGeometry(0.035, 0.045, 0.04), mat('plastic_black'));
    this.root.add(plug);
    const cord = new THREE.Mesh(new THREE.BufferGeometry(), mat('plastic_black'));
    this.root.add(cord);
    const dev: Device = { id, name, room, pos, outlet: outlet.clone(), normal: normal.clone(), plugged: true, glow: 0, mats, cord, cordFrom: pos.clone().add(new THREE.Vector3(0, -0.25, 0)), plug, floorY };
    this.devices.push(dev);
    this.setPlugged(dev, true);
  }

  setPlugged(d: Device, plugged: boolean) {
    d.plugged = plugged;
    const n = d.normal;
    const plugAt = plugged ? d.outlet.clone().addScaledVector(n, 0.025) : d.outlet.clone().addScaledVector(n, 0.35).setY(d.floorY + 0.02);
    d.plug.position.copy(plugAt);
    d.plug.lookAt(plugAt.clone().add(n));
    const a = d.cordFrom;
    const mid = a.clone().lerp(plugAt, 0.5);
    mid.y = Math.min(a.y, plugAt.y) - 0.15;
    if (mid.y < d.floorY + 0.01) mid.y = d.floorY + 0.01;
    const curve = new THREE.CatmullRomCurve3([a, mid, plugAt]);
    d.cord.geometry.dispose();
    d.cord.geometry = new THREE.TubeGeometry(curve, 16, 0.006, 4, false);
  }

  private addFaucet(
    id: Faucet['id'],
    name: string,
    room: RoomId,
    spout: THREE.Vector3,
    handle: THREE.Vector3,
    bottomY: number,
    topY: number,
    floorY: number,
    puddleCenter: THREE.Vector3,
    basin: [number, number] | null,
    water?: THREE.Mesh,
  ) {
    const r = this.root;
    if (!water) {
      water = new THREE.Mesh(new THREE.PlaneGeometry(basin![0] - 0.08, basin![1] - 0.06), mat('water'));
      water.rotation.x = -Math.PI / 2;
      water.position.set(spout.x, bottomY, spout.z - (id === 'coz' ? 0.14 : -0.12));
      water.visible = false;
      r.add(water);
    }
    // faucet body
    const body = new THREE.Mesh(new THREE.CylinderGeometry(0.018, 0.018, 0.14, 8), mat('chrome'));
    body.position.copy(spout).add(new THREE.Vector3(0, 0.03, 0));
    r.add(body);
    const streamMat = new THREE.MeshStandardMaterial({ color: '#b8d4e0', roughness: 0.05, transparent: true, opacity: 0.6, depthWrite: false });
    const stream = new THREE.Mesh(new THREE.CylinderGeometry(0.008, 0.012, 1, 6, 1, true), streamMat);
    stream.visible = false;
    r.add(stream);
    const puddleMesh = new THREE.Mesh(new THREE.CircleGeometry(1, 24), mat('puddle'));
    puddleMesh.rotation.x = -Math.PI / 2;
    puddleMesh.position.set(puddleCenter.x, floorY + 0.008, puddleCenter.z);
    puddleMesh.scale.setScalar(0.001);
    puddleMesh.renderOrder = 2;
    r.add(puddleMesh);
    this.faucets.push({ id, name, room, spout, handle, running: 0, level: 0, puddle: 0, water, stream, puddleMesh, bottomY, topY, floorY, puddleCenter });
  }

  private addCarry(id: string, name: string, mesh: THREE.Object3D, at: THREE.Vector3) {
    const c = new Carryable(id, name, mesh);
    c.place(at);
    this.root.add(mesh);
    this.carryables.set(id, c);
    return c;
  }

  private addMark(id: string, day: number, kind: 'claw' | 'hand', pos: THREE.Vector3, n: THREE.Vector3, text: string) {
    const m = markMat(kind === 'claw' ? textures().claw : textures().hand);
    const mesh = new THREE.Mesh(new THREE.PlaneGeometry(kind === 'claw' ? 0.35 : 0.3, kind === 'claw' ? 0.35 : 0.3), m);
    mesh.position.copy(pos).addScaledVector(n, 0.012);
    mesh.lookAt(mesh.position.clone().add(n));
    mesh.visible = false;
    mesh.renderOrder = 3;
    this.root.add(mesh);
    this.marks.push({ id, day, pos: pos.clone(), mesh, mat: m, text });
  }

  /* ================================================================ shafts + dust */

  buildShafts(dir: THREE.Vector3, color: THREE.ColorRepresentation, intensity: number) {
    for (const c of [...this.shafts.children]) {
      const m = c as THREE.Mesh;
      m.geometry.dispose();
      this.shafts.remove(c);
    }
    if (intensity <= 0) return;
    const d = dir.clone().normalize();
    const shaftMat = new THREE.ShaderMaterial({
      uniforms: { uColor: { value: new THREE.Color(color) }, uInt: { value: intensity }, uTime: Shared.time },
      vertexShader: /* glsl */ `
        attribute vec2 sh;
        varying vec2 vSh;
        varying vec3 vW;
        void main() { vSh = sh; vec4 w = modelMatrix * vec4(position, 1.0); vW = w.xyz; gl_Position = projectionMatrix * viewMatrix * w; }
      `,
      fragmentShader: /* glsl */ `
        uniform vec3 uColor; uniform float uInt; uniform float uTime;
        varying vec2 vSh; varying vec3 vW;
        float h(vec3 p){ p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
        void main() {
          float along = vSh.y;
          float across = sin(3.14159 * clamp(vSh.x, 0.0, 1.0));
          float fade = (1.0 - along) * smoothstep(0.0, 0.08, along);
          float dust = 0.75 + 0.25 * h(floor(vW * 40.0 + vec3(0.0, uTime * 2.0, 0.0)));
          float a = uInt * fade * pow(across, 1.6) * dust;
          gl_FragColor = vec4(uColor * a, a);
        }
      `,
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
      side: THREE.DoubleSide,
    });
    for (const w of WINDOWS) {
      if (!w.exterior) continue;
      // light must enter through this wall: dot(dir, inward normal) > 0
      const inward = w.axis === 'z' ? new THREE.Vector3(w.inside, 0, 0) : new THREE.Vector3(0, 0, w.inside);
      const facing = d.dot(inward);
      if (facing < 0.15) continue;
      const inset = 0.1 * w.inside;
      const corners: THREE.Vector3[] =
        w.axis === 'z'
          ? [
              new THREE.Vector3(w.fixed + inset, w.y0 + 0.05, w.s0 + 0.05),
              new THREE.Vector3(w.fixed + inset, w.y0 + 0.05, w.s1 - 0.05),
              new THREE.Vector3(w.fixed + inset, w.y1 - 0.05, w.s1 - 0.05),
              new THREE.Vector3(w.fixed + inset, w.y1 - 0.05, w.s0 + 0.05),
            ]
          : [
              new THREE.Vector3(w.s0 + 0.05, w.y0 + 0.05, w.fixed + inset),
              new THREE.Vector3(w.s1 - 0.05, w.y0 + 0.05, w.fixed + inset),
              new THREE.Vector3(w.s1 - 0.05, w.y1 - 0.05, w.fixed + inset),
              new THREE.Vector3(w.s0 + 0.05, w.y1 - 0.05, w.fixed + inset),
            ];
      // floor of the room behind
      const floorY = w.y0 < -0.3 ? -3 : w.y0 < 2.5 ? 0 : w.y0 < 5.8 ? 3 : 6;
      const L = Math.min(6, (w.y1 - floorY) / Math.max(0.15, -d.y));
      const pos: number[] = [];
      const sh: number[] = [];
      for (let i = 0; i < 4; i++) {
        const a = corners[i];
        const bb = corners[(i + 1) % 4];
        const a2 = a.clone().addScaledVector(d, L);
        const b2 = bb.clone().addScaledVector(d, L);
        pos.push(a.x, a.y, a.z, bb.x, bb.y, bb.z, b2.x, b2.y, b2.z, a.x, a.y, a.z, b2.x, b2.y, b2.z, a2.x, a2.y, a2.z);
        sh.push(0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1);
      }
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
      g.setAttribute('sh', new THREE.Float32BufferAttribute(sh, 2));
      const mesh = new THREE.Mesh(g, shaftMat);
      mesh.renderOrder = 5;
      mesh.frustumCulled = false;
      this.shafts.add(mesh);
    }
  }

  private buildDust() {
    const count = 900;
    const pos = new Float32Array(count * 3);
    const seed = new Float32Array(count);
    for (let i = 0; i < count; i++) {
      const room = ROOMS[i % ROOMS.length];
      pos[i * 3] = rand(room.x0 + 0.2, room.x1 - 0.2);
      pos[i * 3 + 1] = rand(room.y + 0.2, room.y + room.h - 0.3);
      pos[i * 3 + 2] = rand(room.z0 + 0.2, room.z1 - 0.2);
      seed[i] = Math.random() * 100;
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    g.setAttribute('seed', new THREE.BufferAttribute(seed, 1));
    const m = new THREE.ShaderMaterial({
      uniforms: { uTime: Shared.time, uTex: { value: textures().dot }, uAmt: { value: 0.5 } },
      vertexShader: /* glsl */ `
        attribute float seed; uniform float uTime; varying float vA;
        void main() {
          vec3 p = position;
          p.x += sin(uTime * 0.13 + seed) * 0.25;
          p.y += sin(uTime * 0.07 + seed * 1.7) * 0.18;
          p.z += cos(uTime * 0.11 + seed * 0.7) * 0.25;
          vec4 mv = modelViewMatrix * vec4(p, 1.0);
          gl_PointSize = clamp(26.0 / -mv.z, 1.0, 6.0);
          vA = 0.5 + 0.5 * sin(uTime * 0.7 + seed * 3.0);
          gl_Position = projectionMatrix * mv;
        }
      `,
      fragmentShader: /* glsl */ `
        uniform sampler2D uTex; uniform float uAmt; varying float vA;
        void main() { float a = texture2D(uTex, gl_PointCoord).a * vA * uAmt * 0.35; gl_FragColor = vec4(vec3(1.0, 0.92, 0.8) * a, a); }
      `,
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
    });
    this.dust = new THREE.Points(g, m);
    this.dust.frustumCulled = false;
    this.root.add(this.dust);
  }

  /* ================================================================ state */

  setHatch(open: boolean, instant = false) {
    this.hatchTarget = open ? 1 : 0;
    if (instant) this.hatchOpen = this.hatchTarget;
    this.ladder.visible = open;
    for (const bx of this.ladderBoxes) bx.enabled = open;
    this.hatchBox.enabled = !open;
    this.cord.visible = !open;
  }
  hatchTarget = 0;

  setDuct(open: boolean, instant = false) {
    this.ductTarget = open ? 1 : 0;
    if (instant) this.ductOpen = this.ductTarget;
  }
  ductTarget = 0;

  setBasculante(open: boolean, instant = false) {
    this.basculanteTarget = open ? 1 : 0;
    if (instant) this.basculanteOpen = this.basculanteTarget;
  }
  basculanteTarget = 0;

  chestTarget = 0;
  setChest(open: boolean) {
    this.chestTarget = open ? 1 : 0;
  }

  setGuestMoveIn(on: boolean) {
    this.guestMoveIn.visible = on;
    this.guestDust.visible = !on;
  }

  setDavBlanket(occupied: boolean) {
    this.davBlanketOn.visible = occupied;
    this.davBlanketOff.visible = !occupied;
  }

  setBlanket(occupied: boolean) {
    this.blanketOn.visible = occupied;
    this.blanketOff.visible = !occupied;
  }

  update(dt: number, vision: number, day: number, phase: string) {
    for (const d of this.doors.values()) d.update(dt);
    this.lights.update(dt);
    this.props.update(dt);
    // hatch
    this.hatchOpen = damp(this.hatchOpen, this.hatchTarget, 4, dt);
    this.hatchPanel.rotation.x = -this.hatchOpen * 1.45;
    this.ductOpen = damp(this.ductOpen, this.ductTarget, 5, dt);
    this.ductGrates.forEach((g) => (g.rotation.x = -this.ductOpen * 1.3));
    this.basculanteOpen = damp(this.basculanteOpen, this.basculanteTarget, 4, dt);
    this.basculante.rotation.x = -this.basculanteOpen * 0.9;
    this.basculanteBox.enabled = this.basculanteOpen < 0.5;
    this.chestOpen = damp(this.chestOpen, this.chestTarget, 3, dt);
    this.chestLid.rotation.x = -this.chestOpen * 1.2;
    // faucets
    const t = Shared.time.value;
    for (const f of this.faucets) {
      f.stream.visible = f.running > 0.05;
      if (f.stream.visible) {
        const fall = f.spout.y - Math.max(f.bottomY, f.bottomY + (f.topY - f.bottomY) * f.level);
        f.stream.scale.set(0.5 + f.running * 0.8, Math.max(0.02, fall), 0.5 + f.running * 0.8);
        f.stream.position.set(f.spout.x + (f.id === 'tub' ? -0.08 : 0), f.spout.y - fall / 2, f.spout.z + (f.id === 'coz' ? -0.05 : f.id === 'banb' ? 0.05 : 0));
      }
      f.water.visible = f.level > 0.02;
      f.water.position.y = f.bottomY + (f.topY - f.bottomY) * f.level;
      const pr = f.puddle * 1.4;
      f.puddleMesh.scale.setScalar(Math.max(0.001, pr));
      f.puddleMesh.visible = f.puddle > 0.01;
    }
    // devices
    for (const dv of this.devices) {
      for (const m of dv.mats) {
        m.emissiveIntensity = dv.glow * 1.6;
        if (m.emissiveMap) {
          m.emissiveMap.offset.set(Math.random(), Math.random());
        }
      }
    }
    // marks visible only through cat vision, only on their day (mornings) or the day after
    for (const mk of this.marks) {
      const active = phase === 'morning' && mk.day === day;
      const target = active ? vision : 0;
      mk.mat.opacity = damp(mk.mat.opacity, target * (0.75 + 0.25 * Math.sin(t * 3 + mk.pos.x)), 8, dt);
      mk.mesh.visible = mk.mat.opacity > 0.01;
    }
    // ritual glow
    this.ritualMat.opacity = clamp(this.ritualGlow);
    this.ritualMat.color.setRGB(1, 1, 1).lerp(new THREE.Color('#ff6a4a'), clamp(this.ritualGlow - 1)).multiplyScalar(1 + clamp(this.ritualGlow - 1) * 2);
    // sheets sway
    this.sheets.forEach((s, i) => (s.rotation.x = Math.sin(t * 0.8 + i) * 0.06));
    // clock
    this.clockHandInner.rotation.x = -t * 0.5;
    void _v;
  }
}
