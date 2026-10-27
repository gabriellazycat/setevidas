import * as THREE from 'three';
import type { Builder } from './Builder';
import * as F from './Furniture';
import { mat, stdMat } from '../render/Materials';
import { textures } from '../render/Textures';
import { rand, choose } from '../core/math';
import type { PropSystem } from './Props';

/**
 * The "lived-in" pass: small objects, wall art, rugs, plants and clutter.
 * Every item rests on something real (the dev check `Builder.findFloating` verifies it).
 */

const NC = { col: false } as const;
const NS = { col: false, shadow: false } as const;
const _m = new THREE.Matrix4();

/** wall face coordinate of an interior wall of thickness 0.12 */
const face = (fixed: number, side: 1 | -1, t = 0.12) => fixed + side * (t / 2);

function jar(b: Builder, x: number, y: number, z: number, r: number, h: number, key = 'ceramic') {
  b.cyl(key, x, y, z, r, r * 0.95, h, 10, NC);
  b.cyl('metal', x, y + h, z, r * 1.02, r * 1.02, 0.015, 10, NC);
}

function bookStack(b: Builder, x: number, y: number, z: number, n = 3) {
  let yy = y;
  for (let i = 0; i < n; i++) {
    const h = rand(0.025, 0.045);
    b.boxC(choose(['book_a', 'book_b', 'book_c', 'book_d']), x + rand(-0.01, 0.01), yy, z + rand(-0.01, 0.01), rand(0.15, 0.2), h, rand(0.2, 0.25), { ...NC, rotY: rand(-0.3, 0.3) });
    yy += h;
  }
  return yy;
}

function shade(b: Builder, x: number, y: number, z: number, rt: number, rb: number, h: number) {
  const g = new THREE.CylinderGeometry(rt, rb, h, 16, 1, true);
  _m.makeTranslation(x, y + h / 2, z);
  b.geo('lampshade', g, _m, { shadow: false });
}

/** purely decorative table lamp (the real, switchable ones are in Lights.ts) */
function tableLamp(b: Builder, x: number, y: number, z: number, s = 1) {
  b.cyl('brass', x, y, z, 0.06 * s, 0.07 * s, 0.03 * s, 12, NC);
  b.sphere('ceramic', x, y + 0.14 * s, z, 0.075 * s, 1, 1.3, 1, NC);
  shade(b, x, y + 0.24 * s, z, 0.09 * s, 0.15 * s, 0.17 * s);
}

function mug(b: Builder, x: number, y: number, z: number, key = 'ceramic') {
  b.cyl(key, x, y, z, 0.04, 0.035, 0.09, 10, NC);
}

function fruitBowl(b: Builder, x: number, y: number, z: number) {
  b.cyl('ceramic', x, y, z, 0.13, 0.07, 0.07, 14, NC);
  const cols = ['plastic_red', 'plant', 'terracotta', 'brass'];
  for (let i = 0; i < 5; i++) {
    const a = (i / 5) * Math.PI * 2;
    b.sphere(cols[i % cols.length], x + Math.cos(a) * 0.05, y + 0.1, z + Math.sin(a) * 0.05, 0.04, 1, 1, 1, NC);
  }
}

function flowers(b: Builder, x: number, y: number, z: number) {
  b.cyl('glass', x, y, z, 0.045, 0.035, 0.16, 10, NC);
  for (let i = 0; i < 6; i++) {
    const a = (i / 6) * Math.PI * 2;
    b.sphere(['plastic_red', 'paper', 'brass', 'terracotta'][i % 4], x + Math.cos(a) * 0.04, y + 0.22 + rand(0, 0.05), z + Math.sin(a) * 0.04, 0.03, 1, 1, 1, NC);
  }
}

function plantPot(b: Builder, x: number, y: number, z: number, s = 1, col = true) {
  F.plant(b, x, z, y, s);
  void col;
}

/** hanging cobweb in a ceiling corner */
function cobweb(root: THREE.Object3D, corner: THREE.Vector3, dirA: THREE.Vector3, dirB: THREE.Vector3, size = 0.7) {
  const g = new THREE.BufferGeometry();
  const a = corner.clone().addScaledVector(dirA, size);
  const b = corner.clone().addScaledVector(dirB, size);
  g.setAttribute('position', new THREE.Float32BufferAttribute([corner.x, corner.y, corner.z, a.x, a.y, a.z, b.x, b.y, b.z], 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute([0, 0, 1, 0, 0, 1], 2));
  g.computeVertexNormals();
  const m = new THREE.Mesh(
    g,
    stdMat({ map: textures().cobweb, transparent: true, depthWrite: false, side: THREE.DoubleSide, roughness: 1, color: '#d8d8d0' }),
  );
  root.add(m);
}

export function decorate(b: Builder, root: THREE.Object3D, props: PropSystem) {
  /* ============================================================ SALA */
  {
    // wall art (faces are at the true wall surface)
    F.painting(b, 'x', face(5.5, -1), -1, 1.0, 1.7, 0.5, 0.62, 0);
    F.painting(b, 'x', face(5.5, -1), -1, 4.0, 1.75, 0.42, 0.55, 2);
    F.painting(b, 'z', 0.1, 1, 0.75, 1.7, 0.4, 0.52, 1);
    F.painting(b, 'z', face(5, -1), -1, 3.8, 1.6, 0.42, 0.55, 2);
    // side table + lamp beside the sofa
    F.table(b, 4.15, 1.05, 4.65, 1.5, 0, 0.5, 'wood_dark', 'wood_dark');
    tableLamp(b, 4.4, 0.5, 1.28, 1);
    bookStack(b, 4.3, 0.5, 1.15, 2);
    // cushions and a throw on the sofa
    b.sphere('fabric_blue', 1.45, 0.55, 1.3, 0.17, 1, 0.8, 0.55, NC);
    b.sphere('fabric_cream', 3.55, 0.56, 1.3, 0.17, 1, 0.8, 0.55, NC);
    b.boxC('blanket', 2.5, 0.44, 1.55, 0.7, 0.03, 0.55, { ...NC, rotY: 0.15 });
    // corner plant and a rolled rug by the shelf
    plantPot(b, 4.55, 0, 4.95, 1.35);
    // magazines and a mug on the coffee table
    b.boxC('paper', 2.6, 0.42, 3.05, 0.22, 0.012, 0.3, { ...NC, rotY: 0.4 });
    // books on the TV stand
    bookStack(b, 1.95, 0.55, 5.2, 2);
    b.cyl('plant_dark', 3.0, 0.55, 5.22, 0.07, 0.06, 0.1, 10, NC);
    // curtain rod shadow box above the window is handled by the window itself
    // picture ledge with frames on the east wall of the sala above the radiator
    b.box('wood_paint', 0.9, 1.35, 0.1, 3.5, 1.38, 0.2, NC);
    for (const [x, c] of [
      [1.2, 'frame'],
      [1.9, 'frame_gold'],
      [2.8, 'frame'],
    ] as const) {
      b.boxC(c, x, 1.38, 0.15, 0.22, 0.28, 0.025, { ...NC, rotY: 0 });
    }
  }

  /* ============================================================ COZINHA */
  {
    // counter by the window / stove side (y = 0.9)
    b.boxC('metal', 7.75, 0.9, 9.62, 0.28, 0.17, 0.18, NC); // toaster
    b.boxC('plastic_black', 7.75, 1.07, 9.62, 0.2, 0.01, 0.1, NC);
    for (let i = 0; i < 3; i++) jar(b, 7.7 + i * 0.15, 0.9, 9.8, 0.05, 0.16 + i * 0.03);
    b.cyl('metal', 10.05, 0.92, 9.62, 0.1, 0.09, 0.14, 12, NC); // kettle on the stove
    b.boxC('wood', 9.15, 0.9, 9.72, 0.36, 0.025, 0.22, NC); // cutting board next to the sink
    mug(b, 8.35, 0.9, 9.55, 'plastic_red');
    // east counter
    fruitBowl(b, 10.66, 0.9, 5.7);
    b.boxC('wood', 10.68, 0.9, 7.1, 0.3, 0.025, 0.22, { ...NC, rotY: 0.2 });
    jar(b, 10.76, 0.9, 5.45, 0.05, 0.2, 'glass');
    // window counter
    b.cyl('metal', 11.7, 0.9, 4.3, 0.09, 0.08, 0.14, 12, NC);
    mug(b, 11.55, 0.9, 3.8);
    mug(b, 11.55, 0.9, 3.95, 'plastic_red');
    // table dressing
    b.box('fabric_cream', 8.55, 0.76, 6.15, 9.85, 0.775, 7.25, NC);
    for (const [x0, z0, x1, z1] of [
      [8.55, 6.15, 9.85, 6.18],
      [8.55, 7.22, 9.85, 7.25],
      [8.55, 6.15, 8.58, 7.25],
      [9.82, 6.15, 9.85, 7.25],
    ] as const)
      b.box('fabric_cream', x0, 0.5, z0, x1, 0.775, z1, NS);
    flowers(b, 9.2, 0.775, 6.7);
    // floor mats
    b.boxC('carpet_red', 8.8, 0, 8.6, 0.85, 0.012, 0.5, { ...NC, rotY: 0 });
    b.boxC('rubber', 8.75, 0, 3.92, 0.6, 0.008, 0.32, NS);
    // hanging utensils rail by the stove
    b.box('brass', 9.35, 1.4, 9.86, 10.25, 1.42, 9.9, NS);
    for (let i = 0; i < 4; i++) b.box('metal', 9.45 + i * 0.22, 1.12, 9.87, 9.47 + i * 0.22, 1.4, 9.89, NS);
    // wall art and clock
    F.painting(b, 'x', face(3.5, 1), 1, 10.3, 1.6, 0.4, 0.5, 2);
    // plant on the sill
    plantPot(b, 11.55, 1.15, 4.35, 0.5, false);
  }

  /* ============================================================ BANHEIRO DE BAIXO */
  {
    b.boxC('carpet_blue', 9.45, 0, 1.2, 0.8, 0.012, 0.5, NC);
    b.boxC('fabric_cream', 10.4, 0, 1.55, 0.6, 0.012, 0.4, NC);
    // shelf above the toilet
    b.box('wood_paint', 10.2, 1.4, 0.1, 11.0, 1.43, 0.3, NC);
    jar(b, 10.4, 1.43, 0.2, 0.04, 0.12, 'glass');
    b.cyl('plastic_white', 10.6, 1.43, 0.2, 0.05, 0.05, 0.1, 10, NC);
    plantPot(b, 10.85, 1.43, 0.2, 0.35, false);
    // towel bar and toilet paper
    b.box('chrome', 7.6, 1.35, 1.0, 7.64, 1.38, 1.4, NS);
    b.box('fabric_blue', 7.6, 1.0, 1.05, 7.64, 1.36, 1.35, NS);
    b.cyl('paper', 11.1, 0.5, 0.18, 0.05, 0.05, 0.1, 10, NC);
    // sink details
    b.cyl('ceramic', 9.55, 0.86, 0.35, 0.04, 0.04, 0.04, 8, NC);
    mug(b, 9.0, 0.86, 0.3, 'plastic_white');
  }

  /* ============================================================ BANHEIRO DE CIMA */
  {
    const qy = 3;
    b.boxC('carpet_blue', 9.6, qy, 8.6, 0.8, 0.012, 0.5, NC);
    b.boxC('fabric_cream', 8.1, qy, 7.3, 0.7, 0.012, 0.45, { ...NC, rotY: 0.2 });
    // shower curtain half drawn along the tub
    b.box('metal', 9.35, qy + 1.95, 9.12, 11.95, qy + 1.97, 9.15, NS);
    b.box('fabric_blue', 9.4, qy + 0.85, 9.12, 10.5, qy + 1.95, 9.14, NS);
    // candles and soap on the tub rim
    for (const [x, h] of [
      [10.2, 0.1],
      [10.35, 0.14],
    ] as const)
      b.cyl('paper', x, qy + 0.58, 9.28, 0.025, 0.025, h, 8, NC);
    b.boxC('ceramic', 10.7, qy + 0.58, 9.28, 0.09, 0.03, 0.06, NC);
    // shelf over the toilet
    b.box('wood_paint', 11.1, qy + 1.5, 6.1, 11.9, qy + 1.53, 6.3, NC);
    jar(b, 11.3, qy + 1.53, 6.2, 0.04, 0.12, 'glass');
    plantPot(b, 11.65, qy + 1.53, 6.2, 0.35, false);
    b.cyl('paper', 11.9, qy + 0.5, 6.7, 0.05, 0.05, 0.1, 10, NC);
    F.painting(b, 'x', 6.1, 1, 9.6, qy + 1.75, 0.4, 0.5, 0);
  }

  /* ============================================================ HALL */
  {
    plantPot(b, 7.15, 0, 9.5, 1.3);
    // umbrella stand by the door
    b.cyl('ceramic', 5.5, 0, 1.4, 0.1, 0.09, 0.45, 12, NC);
    for (let i = 0; i < 2; i++) b.cyl('plastic_black', 5.48 + i * 0.05, 0.45, 1.4, 0.012, 0.012, 0.35 + i * 0.05, 6, NC);
    // key bowl and mail on the shoe cabinet
    b.cyl('brass', 7.2, 0.9, 0.7, 0.07, 0.04, 0.04, 10, NC);
    b.boxC('paper', 7.2, 0.9, 1.1, 0.18, 0.012, 0.12, NC);
    // bench cushion and shoes
    b.boxC('fabric_blue', 5.5, 0.45, 9.75, 0.7, 0.05, 0.34, NC);
    b.boxC('plastic_black', 6.5, 0, 0.7, 0.12, 0.08, 0.28, { ...NC, rotY: 0.5 });
    b.boxC('plastic_black', 6.7, 0, 0.62, 0.12, 0.08, 0.28, { ...NC, rotY: -0.3 });
    // paintings (true wall faces)
    F.painting(b, 'z', face(7.5, -1), -1, 8.2, 1.7, 0.5, 0.6, 2);
    F.painting(b, 'z', face(7.5, -1), -1, 5.0, 1.7, 0.45, 0.55, 0);
  }

  /* ============================================================ ESCRITÓRIO */
  {
    tableLamp(b, 3.18, 0.75, 9.8, 1.0);
    b.boxC('paper', 1.75, 0.75, 9.8, 0.4, 0.04, 0.2, { ...NC, rotY: 0.1 });
    bookStack(b, 3.0, 0.75, 9.85, 2);
    // corkboard on the west wall
    b.box('cardboard_dark', 0.1, 1.3, 7.7, 0.13, 1.85, 8.6, NC);
    for (let i = 0; i < 5; i++) b.boxC('paper', 0.14, 1.4 + rand(0, 0.3), 7.8 + i * 0.16, 0.012, 0.12, 0.1, { ...NC, rotY: 0 });
    // paintings
    F.painting(b, 'x', face(5.5, 1), 1, 3.2, 1.7, 0.45, 0.55, 1);
    F.painting(b, 'x', face(5.5, 1), 1, 1.4, 1.65, 0.4, 0.5, 2);
    // globe on the side table
    b.cyl('wood_dark', 0.3, 0.6, 7.45, 0.05, 0.06, 0.03, 10, NC);
    b.sphere('terracotta', 0.3, 0.8, 7.45, 0.13, 1, 1, 1, NC);
    // boxes of files and a waste bin
    b.cyl('metal', 1.2, 0, 9.5, 0.14, 0.12, 0.3, 12, NC);
  }

  /* ============================================================ QUARTO */
  {
    const qy = 3;
    b.boxC('plastic_black', 0.22, qy + 0.55, 4.0, 0.1, 0.06, 0.07, NC); // alarm clock
    b.boxC('paper', 0.2, qy + 0.55, 3.8, 0.14, 0.03, 0.2, NC); // a book
    // plant on the sill
    plantPot(b, 3.25, qy + 0.85, 0.24, 0.45, false);
    // chair with clothes
    F.chair(b, 2.95, 4.3, qy, '+z', 'wood');
    b.boxC('fabric_blue', 2.95, qy + 0.45, 4.3, 0.34, 0.1, 0.3, { ...NC, rotY: 0.2 });
    b.boxC('fabric_cream', 2.95, qy + 0.55, 4.32, 0.28, 0.05, 0.22, { ...NC, rotY: -0.3 });
    // wall art over the bed and by the door
    F.painting(b, 'z', 0.1, 1, 2.8, qy + 1.7, 0.5, 0.62, 2);
    F.painting(b, 'z', face(5, -1), -1, 3.6, qy + 1.65, 0.42, 0.55, 0);
    // slippers
    b.boxC('fabric_cream', 1.9, qy, 1.55, 0.1, 0.05, 0.22, { ...NC, rotY: 0.3 });
    b.boxC('fabric_cream', 2.05, qy, 1.5, 0.1, 0.05, 0.22, { ...NC, rotY: 0.2 });
    // dresser top: jewellery box, brush
    b.boxC('wood_dark', 2.6, qy + 0.85, 5.2, 0.22, 0.1, 0.14, NC);
    b.boxC('brass', 2.6, qy + 0.95, 5.2, 0.2, 0.01, 0.12, NC);
  }

  /* ============================================================ HÓSPEDES (empty, unused) */
  {
    const qy = 3;
    // folded blanket on the bare bed and a lamp stand
    b.cyl('wood_dark', 4.6, qy, 9.5, 0.03, 0.05, 1.35, 8, NC);
    shade(b, 4.6, qy + 1.3, 9.5, 0.1, 0.18, 0.2);
    // a leaning canvas against the wall (frame + back)
    b.boxC('frame', 4.82, qy, 8.2, 0.04, 0.7, 0.55, { ...NC, rotY: 0 });
    F.painting(b, 'z', face(5, -1), -1, 7.2, qy + 1.6, 0.45, 0.55, 2);
  }

  /* ============================================================ CORREDOR */
  {
    const qy = 3;
    plantPot(b, 6.9, qy, 0.4, 1.2);
    F.painting(b, 'z', face(7.5, -1), -1, 8.2, qy + 1.6, 0.45, 0.55, 1);
    F.painting(b, 'z', face(5, 1), 1, 2.8, qy + 1.6, 0.4, 0.5, 0);
    F.painting(b, 'z', face(7.5, -1), -1, 1.0, qy + 1.6, 0.4, 0.5, 2);
    // lamp on the side table
    tableLamp(b, 7.25, qy + 0.8, 7.0, 0.9);
  }

  /* ============================================================ PORÃO */
  {
    const by = -3;
    // workbench pegboard with tools
    b.box('wood', 7.9, by + 1.1, 3.1, 7.94, by + 1.9, 4.3, NC);
    for (let i = 0; i < 5; i++) b.box('metal', 7.86, by + 1.3 + (i % 2) * 0.3, 3.25 + i * 0.2, 7.9, by + 1.6 + (i % 2) * 0.3, 3.29 + i * 0.2, NS);
    // paint cans and a bucket
    for (let i = 0; i < 3; i++) b.cyl('metal', 6.9 + i * 0.2, by + 0.9, 3.7, 0.08, 0.08, 0.12, 10, NC);
    b.cyl('plastic_red', 7.5, by, 8.8, 0.18, 0.14, 0.3, 12, NC);
    // old crate and a stack of newspapers
    b.boxC('wood', 5.4, by, 9.3, 0.6, 0.35, 0.45, { rotY: 0.2 });
    b.boxC('paper', 4.4, by, 9.4, 0.3, 0.2, 0.22, NC);
    // exposed pipes down the walls
    for (const [x, z] of [
      [0.12, 6.5],
      [0.12, 2.2],
    ] as const)
      b.cyl('metal_dark', x, by, z, 0.04, 0.04, 2.7, 8, NC);
    // cobwebs in the ceiling corners
    const c = -0.2;
    cobweb(root, new THREE.Vector3(0.1, c - 0.01, 0.1), new THREE.Vector3(1, 0, 0), new THREE.Vector3(0, 0, 1), 0.9);
    cobweb(root, new THREE.Vector3(7.9, c - 0.01, 0.1), new THREE.Vector3(-1, 0, 0), new THREE.Vector3(0, 0, 1), 0.9);
    cobweb(root, new THREE.Vector3(0.1, c - 0.01, 9.9), new THREE.Vector3(1, 0, 0), new THREE.Vector3(0, 0, -1), 0.9);
    cobweb(root, new THREE.Vector3(7.9, c - 0.01, 9.9), new THREE.Vector3(-1, 0, 0), new THREE.Vector3(0, 0, -1), 0.9);
  }

  /* ============================================================ LAVANDERIA */
  {
    const by = -3;
    // ironing board with a shirt
    b.box('fabric_cream', 9.3, by + 0.8, 4.3, 10.5, by + 0.83, 4.6, NC);
    for (const x of [9.5, 10.3]) {
      b.box('metal', x, by, 4.38, x + 0.03, by + 0.8, 4.4, NC);
      b.box('metal', x, by, 4.5, x + 0.03, by + 0.8, 4.52, NC);
    }
    b.boxC('fabric_blue', 9.6, by + 0.83, 4.45, 0.35, 0.02, 0.22, NC);
    // bucket and mop, detergent bottles
    b.cyl('plastic_red', 11.6, by, 0.5, 0.17, 0.13, 0.28, 12, NC);
    b.cyl('wood', 11.6, by, 0.5, 0.012, 0.012, 1.3, 6, NC);
    for (let i = 0; i < 3; i++) b.cyl(['plastic_white', 'fabric_blue', 'plant'][i] as string, 9.9 + i * 0.18, by + 0.85, 0.35, 0.06, 0.06, 0.2, 8, NC);
    // floor drain
    const drain = new THREE.Mesh(new THREE.CircleGeometry(0.12, 12), new THREE.MeshBasicMaterial({ color: '#0a0a0b' }));
    drain.rotation.x = -Math.PI / 2;
    drain.position.set(10.0, by + 0.01, 5.5);
    root.add(drain);
    cobweb(root, new THREE.Vector3(8.1, -0.21, 0.1), new THREE.Vector3(1, 0, 0), new THREE.Vector3(0, 0, 1), 0.8);
    cobweb(root, new THREE.Vector3(11.9, -0.21, 9.9), new THREE.Vector3(-1, 0, 0), new THREE.Vector3(0, 0, -1), 0.8);
  }

  /* ============================================================ SÓTÃO */
  {
    const ay = 6;
    // a crib, dusty
    b.box('wood_paint', 5.6, ay + 0.05, 7.4, 6.6, ay + 0.1, 8.1, NC);
    for (const [x, z] of [
      [5.6, 7.4],
      [6.54, 7.4],
      [5.6, 8.04],
      [6.54, 8.04],
    ] as const)
      b.box('wood_paint', x, ay, z, x + 0.06, ay + 0.95, z + 0.06, NC);
    for (let i = 0; i < 9; i++) b.box('wood_paint', 5.62 + i * 0.11, ay + 0.1, 7.4, 5.64 + i * 0.11, ay + 0.8, 7.42, NC);
    // rolled rug and framed pictures stacked against the beam
    const rug = new THREE.CylinderGeometry(0.13, 0.13, 1.3, 12);
    _m.makeRotationZ(Math.PI / 2).premultiply(new THREE.Matrix4().makeTranslation(1.5, ay + 0.13, 9.5));
    b.geo('carpet_red', rug, _m);
    for (let i = 0; i < 3; i++) b.boxC('frame', 6.4 + i * 0.05, ay, 1.2 + i * 0.4, 0.04, 0.6 + i * 0.1, 0.45, NC);
    // paint cans and a rocking horse's missing legs fixed in House.ts
    for (let i = 0; i < 4; i++) b.cyl('metal', 0.5 + (i % 2) * 0.25, ay, 6.2 + Math.floor(i / 2) * 0.25, 0.08, 0.08, 0.12, 10, NC);
    cobweb(root, new THREE.Vector3(0.12, ay + 1.4, 0.12), new THREE.Vector3(1, 0, 0), new THREE.Vector3(0, 0, 1), 0.9);
    cobweb(root, new THREE.Vector3(0.12, ay + 1.4, 9.88), new THREE.Vector3(1, 0, 0), new THREE.Vector3(0, 0, -1), 0.9);
    cobweb(root, new THREE.Vector3(7.4, ay + 1.4, 0.12), new THREE.Vector3(-1, 0, 0), new THREE.Vector3(0, 0, 1), 0.9);
  }

  /* ============================================================ FACHADA */
  {
    // flower boxes under the front windows
    for (const [x0, x1, y] of [
      [1.2, 3.8, 0.7],
      [1.5, 3.5, 3.7],
    ] as const) {
      b.box('wood', x0, y, -0.34, x1, y + 0.16, -0.1, NC);
      for (let x = x0 + 0.15; x < x1; x += 0.28) b.sphere(Math.random() < 0.5 ? 'plant' : 'plastic_red', x, y + 0.24, -0.22, 0.12, 1, 0.9, 1, NC);
    }
    // doormat and porch plants
    b.boxC('carpet_red', 6.45, 0, -0.55, 0.7, 0.015, 0.45, NC);
    plantPot(b, 5.5, 0, -1.2, 1.4);
    plantPot(b, 7.5, 0, -1.2, 1.4);
    // bins by the side of the house
    b.cyl('metal_dark', 12.6, -0.9, 4.2, 0.28, 0.25, 0.95, 12, NC);
    b.cyl('metal_dark', 13.2, -0.9, 4.4, 0.28, 0.25, 0.95, 12, NC);
  }

  void props;
}
