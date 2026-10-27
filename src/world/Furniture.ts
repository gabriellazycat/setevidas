import * as THREE from 'three';
import type { Builder } from './Builder';
import { mat, stdMat } from '../render/Materials';
import { textures } from '../render/Textures';
import { rand, choose } from '../core/math';

/** Facing: the direction the "front" of a piece points to. */
export type Facing = '+x' | '-x' | '+z' | '-z';

const _m = new THREE.Matrix4();

export function table(b: Builder, x0: number, z0: number, x1: number, z1: number, y: number, h: number, top = 'wood', legs = 'wood') {
  const t = 0.04;
  b.box(top, x0, y + h - t, z0, x1, y + h, z1);
  const inset = 0.06;
  const lw = 0.05;
  for (const [lx, lz] of [
    [x0 + inset, z0 + inset],
    [x1 - inset - lw, z0 + inset],
    [x0 + inset, z1 - inset - lw],
    [x1 - inset - lw, z1 - inset - lw],
  ])
    b.box(legs, lx, y, lz, lx + lw, y + h - t, lz + lw, { col: false });
  // apron
  b.box(legs, x0 + inset, y + h - t - 0.08, z0 + inset, x1 - inset, y + h - t, z0 + inset + 0.02, { col: false });
  b.box(legs, x0 + inset, y + h - t - 0.08, z1 - inset - 0.02, x1 - inset, y + h - t, z1 - inset, { col: false });
  // collision: only the top slab (the cat can walk under tables)
}

export function chair(b: Builder, cx: number, cz: number, y: number, facing: Facing, m = 'wood') {
  const s = 0.42;
  const sh = 0.45;
  b.box(m, cx - s / 2, y + sh - 0.04, cz - s / 2, cx + s / 2, y + sh, cz + s / 2);
  for (const [dx, dz] of [
    [-1, -1],
    [1, -1],
    [-1, 1],
    [1, 1],
  ])
    b.box(m, cx + dx * (s / 2 - 0.03) - 0.02, y, cz + dz * (s / 2 - 0.03) - 0.02, cx + dx * (s / 2 - 0.03) + 0.02, y + sh - 0.04, cz + dz * (s / 2 - 0.03) + 0.02, { col: false });
  // back on the opposite side of facing
  const bt = 0.04;
  const bh = 0.5;
  if (facing === '+z') b.box(m, cx - s / 2, y + sh, cz - s / 2, cx + s / 2, y + sh + bh, cz - s / 2 + bt);
  if (facing === '-z') b.box(m, cx - s / 2, y + sh, cz + s / 2 - bt, cx + s / 2, y + sh + bh, cz + s / 2);
  if (facing === '+x') b.box(m, cx - s / 2, y + sh, cz - s / 2, cx - s / 2 + bt, y + sh + bh, cz + s / 2);
  if (facing === '-x') b.box(m, cx + s / 2 - bt, y + sh, cz - s / 2, cx + s / 2, y + sh + bh, cz + s / 2);
}

const BOOKS = ['book_a', 'book_b', 'book_c', 'book_d', 'paper'];

/** Open shelf unit against a wall. `along` = which axis the shelf runs. */
export function shelf(
  b: Builder,
  x0: number,
  z0: number,
  x1: number,
  z1: number,
  y: number,
  h: number,
  levels: number,
  m = 'wood_dark',
  fill: 'books' | 'jars' | 'boxes' | 'none' = 'books',
) {
  const t = 0.03;
  const alongX = x1 - x0 > z1 - z0;
  // sides
  if (alongX) {
    b.box(m, x0, y, z0, x0 + t, y + h, z1);
    b.box(m, x1 - t, y, z0, x1, y + h, z1);
  } else {
    b.box(m, x0, y, z0, x1, y + h, z0 + t);
    b.box(m, x0, y, z1 - t, x1, y + h, z1);
  }
  for (let i = 0; i <= levels; i++) {
    const ly = y + (i / levels) * (h - t);
    b.box(m, x0, ly, z0, x1, ly + t, z1);
    if (i === levels || fill === 'none') continue;
    // fill items between ly+t and next level
    const nextY = y + ((i + 1) / levels) * (h - t);
    const space = nextY - ly - t;
    const len = alongX ? x1 - x0 - 2 * t : z1 - z0 - 2 * t;
    let s = 0.02;
    const depth = alongX ? z1 - z0 : x1 - x0;
    while (s < len - 0.06) {
      if (fill === 'books') {
        const bw = rand(0.025, 0.05);
        const bh = Math.min(space - 0.02, rand(0.16, 0.26));
        const bd = Math.min(depth - 0.03, rand(0.14, 0.2));
        if (Math.random() < 0.12) {
          s += rand(0.05, 0.15);
          continue;
        }
        const key = choose(BOOKS);
        if (alongX) b.box(key, x0 + t + s, ly + t, z0 + 0.01, x0 + t + s + bw, ly + t + bh, z0 + 0.01 + bd, { col: false, shadow: false });
        else b.box(key, x0 + 0.01, ly + t, z0 + t + s, x0 + 0.01 + bd, ly + t + bh, z0 + t + s + bw, { col: false, shadow: false });
        s += bw + 0.003;
      } else if (fill === 'jars') {
        const r = rand(0.03, 0.05);
        const jh = Math.min(space - 0.03, rand(0.08, 0.18));
        const cx = alongX ? x0 + t + s + r : (x0 + x1) / 2;
        const cz = alongX ? (z0 + z1) / 2 : z0 + t + s + r;
        b.cyl(choose(['glass', 'metal', 'terracotta', 'plastic_red']), cx, ly + t, cz, r, r, jh, 10, { shadow: false });
        s += r * 2 + rand(0.02, 0.08);
      } else {
        const bw = rand(0.18, 0.3);
        const bh = Math.min(space - 0.02, rand(0.12, 0.25));
        if (alongX) b.box(choose(['cardboard', 'cardboard_dark']), x0 + t + s, ly + t, z0 + 0.02, x0 + t + s + bw, ly + t + bh, z1 - 0.02, { col: false });
        else b.box(choose(['cardboard', 'cardboard_dark']), x0 + 0.02, ly + t, z0 + t + s, x1 - 0.02, ly + t + bh, z0 + t + s + bw, { col: false });
        s += bw + 0.03;
      }
    }
  }
}

export function cardboardBox(b: Builder, cx: number, cz: number, y: number, w: number, h: number, d: number, open = false) {
  const key = Math.random() < 0.5 ? 'cardboard' : 'cardboard_dark';
  if (!open) {
    b.box(key, cx - w / 2, y, cz - d / 2, cx + w / 2, y + h, cz + d / 2);
    b.box('tape', cx - 0.03, y + h, cz - d / 2 - 0.001, cx + 0.03, y + h + 0.003, cz + d / 2 + 0.001, { col: false, shadow: false });
  } else {
    const t = 0.01;
    b.box(key, cx - w / 2, y, cz - d / 2, cx + w / 2, y + 0.01, cz + d / 2);
    b.box(key, cx - w / 2, y, cz - d / 2, cx + w / 2, y + h, cz - d / 2 + t);
    b.box(key, cx - w / 2, y, cz + d / 2 - t, cx + w / 2, y + h, cz + d / 2);
    b.box(key, cx - w / 2, y, cz - d / 2, cx - w / 2 + t, y + h, cz + d / 2);
    b.box(key, cx + w / 2 - t, y, cz - d / 2, cx + w / 2, y + h, cz + d / 2);
    // flaps
    b.boxC(key, cx - w / 2 - 0.08, y + h - 0.02, cz, 0.18, 0.01, d, { col: false, rotY: 0 });
  }
}

/** Stack of boxes: list of [w,h,d] from the bottom up with small random offsets. */
export function boxStack(b: Builder, cx: number, cz: number, y: number, sizes: [number, number, number][]) {
  let yy = y;
  for (const [w, h, d] of sizes) {
    cardboardBox(b, cx + rand(-0.04, 0.04), cz + rand(-0.04, 0.04), yy, w, h, d);
    yy += h;
  }
  return yy;
}

export function sofa(b: Builder, x0: number, z0: number, x1: number, z1: number, y: number, facing: Facing, m = 'sofa') {
  const seatH = 0.44;
  const backT = 0.2;
  const armW = 0.16;
  const armH = 0.62;
  b.box(m, x0, y + 0.08, z0, x1, y + seatH - 0.1, z1);
  // feet
  for (const [fx, fz] of [
    [x0 + 0.06, z0 + 0.06],
    [x1 - 0.1, z0 + 0.06],
    [x0 + 0.06, z1 - 0.1],
    [x1 - 0.1, z1 - 0.1],
  ])
    b.box('wood_dark', fx, y, fz, fx + 0.04, y + 0.08, fz + 0.04, { col: false });
  if (facing === '+z' || facing === '-z') {
    const bz0 = facing === '+z' ? z0 : z1 - backT;
    b.box(m, x0, y + 0.08, bz0, x1, y + 0.92, bz0 + backT);
    b.box(m, x0, y + 0.08, z0, x0 + armW, y + armH, z1);
    b.box(m, x1 - armW, y + 0.08, z0, x1, y + armH, z1);
    // cushions
    const n = 3;
    const cw = (x1 - x0 - 2 * armW) / n;
    for (let i = 0; i < n; i++) {
      const cx0 = x0 + armW + i * cw + 0.01;
      const cz0 = facing === '+z' ? z0 + backT : z0;
      const cz1 = facing === '+z' ? z1 : z1 - backT;
      b.box(m, cx0, y + seatH - 0.1, cz0, cx0 + cw - 0.02, y + seatH, cz1);
      // back cushion
      const bc0 = facing === '+z' ? z0 + backT : z1 - backT - 0.12;
      b.box(m, cx0, y + seatH, bc0, cx0 + cw - 0.02, y + 0.85, bc0 + 0.12, { col: false });
    }
  } else {
    const bx0 = facing === '+x' ? x0 : x1 - backT;
    b.box(m, bx0, y + 0.08, z0, bx0 + backT, y + 0.92, z1);
    b.box(m, x0, y + 0.08, z0, x1, y + armH, z0 + armW);
    b.box(m, x0, y + 0.08, z1 - armW, x1, y + armH, z1);
    const cx0 = facing === '+x' ? x0 + backT : x0;
    const cx1 = facing === '+x' ? x1 : x1 - backT;
    b.box(m, cx0, y + seatH - 0.1, z0 + armW, cx1, y + seatH, z1 - armW);
  }
}

export function armchair(b: Builder, cx: number, cz: number, y: number, facing: Facing, m = 'fabric_green') {
  const s = 0.8;
  sofa(b, cx - s / 2, cz - s / 2, cx + s / 2, cz + s / 2, y, facing, m);
}

export function rug(b: Builder, x0: number, z0: number, x1: number, z1: number, y: number, m = 'carpet_red') {
  b.box(m, x0, y, z0, x1, y + 0.012, z1, { col: false, shadow: false });
}

export function counter(b: Builder, x0: number, z0: number, x1: number, z1: number, y: number, h = 0.9, body = 'wood_paint_green', top = 'stone') {
  b.box(body, x0 + 0.02, y + 0.1, z0 + 0.02, x1 - 0.02, y + h - 0.04, z1 - 0.02);
  b.box('plastic_black', x0 + 0.06, y, z0 + 0.06, x1 - 0.06, y + 0.1, z1 - 0.06, { col: false });
  b.box(top, x0, y + h - 0.04, z0, x1, y + h, z1);
}

export function painting(b: Builder, axis: 'x' | 'z', fixed: number, normal: number, s: number, y: number, w: number, h: number, kind: 0 | 1 | 2) {
  const t = 0.03;
  const key = `painting${kind}`;
  if (axis === 'x') {
    // wall runs along x at z = fixed; painting faces normal (+1 => +z)
    const z = fixed + normal * (t / 2 + 0.005);
    b.box('frame', s - w / 2 - 0.04, y - h / 2 - 0.04, z - t / 2, s + w / 2 + 0.04, y + h / 2 + 0.04, z + t / 2, { col: false });
    const g = new THREE.PlaneGeometry(w, h);
    _m.makeTranslation(s, y, z + normal * (t / 2 + 0.002));
    if (normal < 0) _m.multiply(new THREE.Matrix4().makeRotationY(Math.PI));
    b.geo(key, g, _m, { shadow: false });
  } else {
    const x = fixed + normal * (t / 2 + 0.005);
    b.box('frame', x - t / 2, y - h / 2 - 0.04, s - w / 2 - 0.04, x + t / 2, y + h / 2 + 0.04, s + w / 2 + 0.04, { col: false });
    const g = new THREE.PlaneGeometry(w, h);
    _m.makeTranslation(x + normal * (t / 2 + 0.002), y, s);
    _m.multiply(new THREE.Matrix4().makeRotationY(normal > 0 ? Math.PI / 2 : -Math.PI / 2));
    b.geo(key, g, _m, { shadow: false });
  }
}

export function plant(b: Builder, x: number, z: number, y: number, scale = 1) {
  b.cyl('terracotta', x, y, z, 0.13 * scale, 0.1 * scale, 0.22 * scale, 12, { col: true });
  b.cyl('soil', x, y + 0.2 * scale, z, 0.12 * scale, 0.12 * scale, 0.02, 12);
  for (let i = 0; i < 7; i++) {
    const a = (i / 7) * Math.PI * 2 + rand(-0.3, 0.3);
    const r = rand(0.05, 0.14) * scale;
    b.sphere(i % 2 ? 'plant' : 'plant_dark', x + Math.cos(a) * r, y + (0.32 + rand(0, 0.3)) * scale, z + Math.sin(a) * r, 0.11 * scale, 1, rand(1.2, 1.8), 1);
  }
}

/** A blob of furniture under a white sheet (creepy). */
export function sheetCovered(b: Builder, cx: number, cz: number, y: number, w: number, h: number, d: number) {
  b.box('white_sheet', cx - w / 2, y, cz - d / 2, cx + w / 2, y + h * 0.8, cz + d / 2);
  b.sphere('white_sheet', cx, y + h * 0.75, cz, 0.5, w * 0.9, h * 0.5, d * 0.9, { col: false });
  for (let i = 0; i < 4; i++) {
    const sx = cx + (i % 2 ? 1 : -1) * w * 0.48;
    const sz = cz + (i < 2 ? 1 : -1) * d * 0.48;
    b.boxC('white_sheet', sx, y, sz, 0.12, h * 0.45, 0.12, { col: false, rotY: rand(0, 1) });
  }
}

export function curtains(b: Builder, axis: 'x' | 'z', fixed: number, inside: number, s0: number, s1: number, y0: number, y1: number, m = 'fabric_blue') {
  const off = inside * 0.12;
  const top = y1 + 0.18;
  const bottom = Math.max(y0 - 0.25, y0 - 0.25);
  const pw = 0.32;
  // rod
  if (axis === 'x') b.box('brass', s0 - 0.35, top, fixed + off - 0.01, s1 + 0.35, top + 0.025, fixed + off + 0.01, { col: false });
  else b.box('brass', fixed + off - 0.01, top, s0 - 0.35, fixed + off + 0.01, top + 0.025, s1 + 0.35, { col: false });
  for (const side of [0, 1]) {
    const c0 = side === 0 ? s0 - 0.32 : s1 + 0.32 - pw;
    // folds: three slim boxes per panel
    for (let k = 0; k < 4; k++) {
      const fs = c0 + (k * pw) / 4;
      const depth = k % 2 ? 0.05 : 0.03;
      if (axis === 'x') b.box(m, fs, bottom, fixed + off - depth, fs + pw / 4 + 0.01, top, fixed + off + depth, { col: false });
      else b.box(m, fixed + off - depth, bottom, fs, fixed + off + depth, top, fs + pw / 4 + 0.01, { col: false });
    }
  }
}

/** Fake contact shadow under a piece of furniture. */
export function contactShadow(parent: THREE.Object3D, cx: number, cz: number, y: number, w: number, d: number, strength = 0.55) {
  const m = new THREE.MeshBasicMaterial({
    map: textures().blob,
    color: '#000000',
    transparent: true,
    opacity: strength,
    depthWrite: false,
    polygonOffset: true,
    polygonOffsetFactor: -1,
  });
  const p = new THREE.Mesh(new THREE.PlaneGeometry(w * 1.25, d * 1.25), m);
  p.rotation.x = -Math.PI / 2;
  p.position.set(cx, y + 0.004, cz);
  p.renderOrder = 1;
  parent.add(p);
  return p;
}

/** CRT television; returns the screen material so it can show static. */
export function crtTV(b: Builder, cx: number, cz: number, y: number, facing: Facing, parent: THREE.Object3D) {
  const w = 0.68;
  const h = 0.55;
  const d = 0.48;
  b.box('plastic_black', cx - w / 2, y, cz - d / 2, cx + w / 2, y + h, cz + d / 2);
  const screenMat = stdMat({ color: '#0b0f12', roughness: 0.15, metalness: 0.1, emissive: new THREE.Color('#9fc8ff'), emissiveIntensity: 0 });
  screenMat.emissiveMap = textures().staticNoise;
  const screen = new THREE.Mesh(new THREE.PlaneGeometry(w * 0.78, h * 0.72), screenMat);
  const zf = facing === '-z' ? cz - d / 2 - 0.002 : cz + d / 2 + 0.002;
  screen.position.set(cx - 0.04, y + h / 2 + 0.01, zf);
  if (facing === '-z') screen.rotation.y = Math.PI;
  parent.add(screen);
  // knobs
  for (let i = 0; i < 2; i++) b.sphere('metal', cx + w * 0.4, y + 0.18 + i * 0.12, zf, 0.018, 1, 1, 0.6, { col: false, shadow: false });
  return { screen, screenMat };
}

export function radioSet(b: Builder, cx: number, cz: number, y: number, facing: Facing, parent: THREE.Object3D) {
  const w = 0.34;
  const h = 0.2;
  const d = 0.14;
  const alongZ = facing === '+x' || facing === '-x';
  if (alongZ) b.box('wood_dark', cx - d / 2, y, cz - w / 2, cx + d / 2, y + h, cz + w / 2, { col: true });
  else b.box('wood_dark', cx - w / 2, y, cz - d / 2, cx + w / 2, y + h, cz + d / 2, { col: true });
  const dialMat = stdMat({ color: '#d8c79a', roughness: 0.4, emissive: new THREE.Color('#ffb36b'), emissiveIntensity: 0 });
  const dial = new THREE.Mesh(new THREE.PlaneGeometry(alongZ ? w * 0.6 : w * 0.6, h * 0.3), dialMat);
  const sgn = facing === '-x' || facing === '-z' ? -1 : 1;
  if (alongZ) {
    dial.position.set(cx + sgn * (d / 2 + 0.002), y + h * 0.68, cz);
    dial.rotation.y = sgn > 0 ? Math.PI / 2 : -Math.PI / 2;
  } else {
    dial.position.set(cx, y + h * 0.68, cz + sgn * (d / 2 + 0.002));
    if (sgn < 0) dial.rotation.y = Math.PI;
  }
  parent.add(dial);
  const grill = new THREE.Mesh(new THREE.PlaneGeometry(w * 0.7, h * 0.35), mat('fabric_cream'));
  grill.position.copy(dial.position).add(new THREE.Vector3(0, -h * 0.38, 0));
  grill.rotation.copy(dial.rotation);
  parent.add(grill);
  // antenna
  b.cyl('chrome', cx, y + h, cz, 0.004, 0.004, 0.3, 4, { shadow: false });
  return { dialMat };
}

export function laptop(b: Builder, cx: number, cz: number, y: number, parent: THREE.Object3D) {
  b.box('metal_dark', cx - 0.17, y, cz - 0.12, cx + 0.17, y + 0.02, cz + 0.12, { col: false });
  const screenMat = stdMat({ color: '#0b0f12', roughness: 0.2, emissive: new THREE.Color('#a6c4ff'), emissiveIntensity: 0 });
  screenMat.emissiveMap = textures().staticNoise;
  const lid = new THREE.Group();
  lid.position.set(cx, y + 0.02, cz + 0.12);
  const back = new THREE.Mesh(new THREE.BoxGeometry(0.34, 0.23, 0.012), mat('metal_dark'));
  back.position.set(0, 0.115, 0.006);
  lid.add(back);
  const scr = new THREE.Mesh(new THREE.PlaneGeometry(0.3, 0.19), screenMat);
  scr.position.set(0, 0.115, -0.001);
  scr.rotation.y = Math.PI;
  lid.add(scr);
  lid.rotation.x = 0.25;
  parent.add(lid);
  return { screenMat };
}

/** Clawfoot bathtub along x. Returns the water surface mesh (scale.y driven). */
export function bathtub(b: Builder, x0: number, z0: number, x1: number, z1: number, y: number, parent: THREE.Object3D) {
  const h = 0.58;
  const t = 0.06;
  b.box('enamel', x0, y + 0.12, z0, x1, y + 0.2, z1);
  b.box('enamel', x0, y + 0.12, z0, x1, y + h, z0 + t);
  b.box('enamel', x0, y + 0.12, z1 - t, x1, y + h, z1);
  b.box('enamel', x0, y + 0.12, z0, x0 + t, y + h, z1);
  b.box('enamel', x1 - t, y + 0.12, z0, x1, y + h, z1);
  b.box('chrome', x0 - 0.01, y + h - 0.02, z0 - 0.01, x1 + 0.01, y + h + 0.01, z0 + t + 0.01, { col: false });
  for (const [fx, fz] of [
    [x0 + 0.12, z0 + 0.1],
    [x1 - 0.12, z0 + 0.1],
    [x0 + 0.12, z1 - 0.1],
    [x1 - 0.12, z1 - 0.1],
  ])
    b.sphere('brass', fx, y + 0.06, fz, 0.06, 1, 1.1, 1, { col: false });
  const water = new THREE.Mesh(new THREE.PlaneGeometry(x1 - x0 - 2 * t, z1 - z0 - 2 * t), mat('water'));
  water.rotation.x = -Math.PI / 2;
  water.position.set((x0 + x1) / 2, y + 0.21, (z0 + z1) / 2);
  water.visible = false;
  parent.add(water);
  return { water, bottomY: y + 0.21, topY: y + h - 0.04 };
}

export function toilet(b: Builder, cx: number, cz: number, y: number, facing: Facing) {
  // tank against the wall opposite to facing
  const back = facing === '+z' ? -1 : facing === '-z' ? 1 : 0;
  const backX = facing === '+x' ? -1 : facing === '-x' ? 1 : 0;
  b.cyl('ceramic', cx, y, cz, 0.18, 0.15, 0.4, 14);
  b.cyl('ceramic', cx, y + 0.4, cz, 0.2, 0.2, 0.03, 14, { col: false });
  b.boxC('ceramic', cx + backX * 0.22, y + 0.4, cz + back * 0.22, backX ? 0.18 : 0.42, 0.38, backX ? 0.42 : 0.18);
}

export function pedestalSink(b: Builder, cx: number, cz: number, y: number, facing: Facing) {
  b.cyl('ceramic', cx, y, cz, 0.08, 0.11, 0.72, 12);
  b.boxC('ceramic', cx, y + 0.72, cz, 0.56, 0.14, 0.44);
  const bz = facing === '+z' ? -0.17 : 0.17;
  b.cyl('chrome', cx, y + 0.86, cz + bz, 0.015, 0.015, 0.16, 8, { col: false });
}

export function washer(b: Builder, cx: number, cz: number, y: number, parent: THREE.Object3D, front: Facing = '+z') {
  b.boxC('plastic_white', cx, y, cz, 0.62, 0.86, 0.62);
  const ring = new THREE.Mesh(new THREE.TorusGeometry(0.17, 0.025, 8, 24), mat('chrome'));
  const glass = new THREE.Mesh(new THREE.CircleGeometry(0.16, 24), mat('glass'));
  const z = front === '+z' ? cz + 0.315 : cz - 0.315;
  ring.position.set(cx, y + 0.42, z);
  glass.position.set(cx, y + 0.42, z + (front === '+z' ? 0.001 : -0.001));
  if (front === '-z') glass.rotation.y = Math.PI;
  parent.add(ring, glass);
  b.box('plastic_black', cx - 0.25, y + 0.75, z - 0.005, cx + 0.25, y + 0.82, z + 0.005, { col: false });
}

export function fridge(b: Builder, x0: number, z0: number, x1: number, z1: number, y: number, h = 1.8) {
  b.box('enamel', x0, y + 0.05, z0, x1, y + h, z1);
  b.box('plastic_black', x0 + 0.04, y, z0 + 0.04, x1 - 0.04, y + 0.05, z1 - 0.04, { col: false });
  // rounded top hint
  b.box('enamel', x0 + 0.02, y + h, z0 + 0.02, x1 - 0.02, y + h + 0.03, z1 - 0.02);
  // handle (on +z side)
  b.box('chrome', x1 - 0.12, y + 0.9, z1, x1 - 0.09, y + 1.4, z1 + 0.04, { col: false });
  b.box('plastic_black', x0, y + 1.25, z1 - 0.002, x1, y + 1.26, z1 + 0.003, { col: false, shadow: false });
}

export function boiler(b: Builder, x0: number, z0: number, x1: number, z1: number, y: number, parent: THREE.Object3D) {
  const cx = (x0 + x1) / 2;
  const cz = (z0 + z1) / 2;
  b.cyl('boiler', cx, y, cz, (x1 - x0) / 2, (x1 - x0) / 2, 1.75, 16, { col: true });
  b.cyl('metal_dark', cx, y + 1.75, cz, 0.08, 0.08, 1.0, 8);
  const pilot = new THREE.Mesh(new THREE.CircleGeometry(0.03, 10), new THREE.MeshBasicMaterial({ color: new THREE.Color('#ff7a2a').multiplyScalar(4) }));
  pilot.position.set(cx + (x1 - x0) / 2 + 0.005, y + 0.25, cz);
  pilot.rotation.y = Math.PI / 2;
  parent.add(pilot);
  b.box('metal_dark', cx + (x1 - x0) / 2 - 0.02, y + 0.15, cz - 0.1, cx + (x1 - x0) / 2 + 0.01, y + 0.35, cz + 0.1, { col: false });
  return pilot;
}

export function bed(b: Builder, x0: number, z0: number, x1: number, z1: number, y: number, headAt: 'x0' | 'x1', blanketKey = 'blanket') {
  const frameH = 0.3;
  const mattressTop = 0.55;
  b.box('wood_dark', x0, y + 0.08, z0, x1, y + frameH, z1);
  for (const [fx, fz] of [
    [x0, z0],
    [x1 - 0.06, z0],
    [x0, z1 - 0.06],
    [x1 - 0.06, z1 - 0.06],
  ])
    b.box('wood_dark', fx, y, fz, fx + 0.06, y + 0.08, fz + 0.06, { col: false });
  b.box('mattress', x0 + 0.03, y + frameH, z0 + 0.03, x1 - 0.03, y + mattressTop - 0.06, z1 - 0.03);
  const hx = headAt === 'x0' ? x0 : x1 - 0.08;
  b.box('wood_dark', hx, y, z0, hx + 0.08, y + 1.15, z1);
  // pillows
  const px = headAt === 'x0' ? x0 + 0.12 : x1 - 0.5;
  const zm = (z0 + z1) / 2;
  const width = z1 - z0;
  if (width > 1.2) {
    b.sphere('pillow', px + 0.19, y + mattressTop - 0.02, zm - width * 0.24, 0.2, 1.0, 0.35, 1.6, { col: false });
    b.sphere('pillow', px + 0.19, y + mattressTop - 0.02, zm + width * 0.24, 0.2, 1.0, 0.35, 1.6, { col: false });
  } else b.sphere('pillow', px + 0.19, y + mattressTop - 0.02, zm, 0.2, 1.0, 0.35, 1.6, { col: false });
  return { mattressTop: y + mattressTop - 0.06, blanketKey };
}
