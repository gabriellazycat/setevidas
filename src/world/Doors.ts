import * as THREE from 'three';
import type { DoorDef, DoorState } from './Layout';
import type { Box, ColliderWorld } from './Colliders';
import { boxMesh } from './Builder';
import { mat } from '../render/Materials';
import { damp } from '../core/math';

const ANGLES: Record<DoorState, number> = { closed: 0, ajar: 0.55, open: 1.62 };

export class Door {
  pivot = new THREE.Group();
  angle = 0;
  target = 0;
  state: DoorState;
  collider: Box;
  locked = false;
  private dirS: number;
  private wasMoving = false;
  onMove?: (door: Door, opening: boolean) => void;

  constructor(
    public def: DoorDef,
    parent: THREE.Object3D,
    col: ColliderWorld,
  ) {
    const d = def;
    this.state = d.state;
    this.dirS = d.hinge === 0 ? 1 : -1;
    const width = d.s1 - d.s0 - 0.03;
    const hingeS = d.hinge === 0 ? d.s0 + 0.015 : d.s1 - 0.015;
    if (d.axis === 'z') this.pivot.position.set(d.fixed, d.y, hingeS);
    else this.pivot.position.set(hingeS, d.y, d.fixed);
    parent.add(this.pivot);

    const leaf = new THREE.Group();
    const t = 0.045;
    const h = d.h - 0.02;
    const key = d.style === 'front' ? 'wood_paint_green' : d.style === 'basement' ? 'wood_dark' : 'wood_paint';
    const along = (w: number, hh: number, tt: number) => (d.axis === 'z' ? boxMesh(key, tt, hh, w) : boxMesh(key, w, hh, tt));

    if (d.style === 'glass') {
      const frameW = 0.08;
      const parts: [number, number, number, number][] = [
        // [offsetAlong, y, w, h]
        [frameW / 2, h / 2, frameW, h],
        [width - frameW / 2, h / 2, frameW, h],
        [width / 2, frameW / 2, width, frameW],
        [width / 2, h - frameW / 2, width, frameW],
        [width / 2, h * 0.45, width, 0.05],
      ];
      for (const [o, y, w, hh] of parts) {
        const m = along(w, hh, t);
        this.place(m, o, y);
        leaf.add(m);
      }
      const glass = d.axis === 'z'
        ? new THREE.Mesh(new THREE.BoxGeometry(0.01, h - 0.16, width - 0.16), mat('glass'))
        : new THREE.Mesh(new THREE.BoxGeometry(width - 0.16, h - 0.16, 0.01), mat('glass'));
      this.place(glass, width / 2, h / 2);
      leaf.add(glass);
    } else {
      const slab = along(width, h, t);
      this.place(slab, width / 2, h / 2);
      leaf.add(slab);
      // raised panels on both faces
      const panelKey = key;
      const pw = width * 0.32;
      for (const sideSign of [-1, 1]) {
        for (const [ox, oy, ph] of [
          [0.27, 0.27, 0.62],
          [0.73, 0.27, 0.62],
          [0.27, 0.72, 0.6],
          [0.73, 0.72, 0.6],
        ] as const) {
          const p = d.axis === 'z' ? boxMesh(panelKey, 0.012, h * 0.36 * ph * 2.2 * 0.45, pw) : boxMesh(panelKey, pw, h * 0.36 * ph * 2.2 * 0.45, 0.012);
          this.place(p, width * ox, h * oy, sideSign * (t / 2 + 0.006));
          p.castShadow = false;
          leaf.add(p);
        }
      }
      if (d.style === 'front') {
        // small window in the front door
        const g = d.axis === 'z'
          ? new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.35, width * 0.5), mat('glass'))
          : new THREE.Mesh(new THREE.BoxGeometry(width * 0.5, 0.35, 0.05), mat('glass'));
        this.place(g, width / 2, h * 0.8);
        leaf.add(g);
      }
    }
    // knobs
    for (const sideSign of [-1, 1]) {
      const knob = new THREE.Mesh(new THREE.SphereGeometry(0.03, 10, 8), mat('brass'));
      this.place(knob, width - 0.08, 1.0, sideSign * (t / 2 + 0.035));
      knob.castShadow = false;
      leaf.add(knob);
    }
    this.pivot.add(leaf);

    // collider when closed
    if (d.axis === 'z')
      this.collider = col.add(
        new THREE.Vector3(d.fixed - 0.07, d.y, d.s0),
        new THREE.Vector3(d.fixed + 0.07, d.y + d.h, d.s1),
        { tag: 'door', camera: true },
      );
    else
      this.collider = col.add(
        new THREE.Vector3(d.s0, d.y, d.fixed - 0.07),
        new THREE.Vector3(d.s1, d.y + d.h, d.fixed + 0.07),
        { tag: 'door', camera: true },
      );

    this.angle = this.target = ANGLES[this.state];
    this.apply();
  }

  /** place a mesh along the leaf: o = distance from hinge, y = height, n = offset normal to the leaf */
  private place(m: THREE.Object3D, o: number, y: number, n = 0) {
    if (this.def.axis === 'z') m.position.set(n, y, this.dirS * o);
    else m.position.set(this.dirS * o, y, n);
  }

  private apply() {
    const d = this.def;
    const phi = d.axis === 'z' ? d.swing * this.dirS * this.angle : -d.swing * this.dirS * this.angle;
    this.pivot.rotation.y = phi;
    this.collider.enabled = this.angle < 0.22;
  }

  setState(s: DoorState, instant = false) {
    if (this.locked && s !== 'closed') return;
    this.state = s;
    this.target = ANGLES[s];
    if (instant) {
      this.angle = this.target;
      this.apply();
    }
  }

  get isClosed() {
    return this.angle < 0.22;
  }

  center(out = new THREE.Vector3()) {
    const d = this.def;
    const m = (d.s0 + d.s1) / 2;
    return d.axis === 'z' ? out.set(d.fixed, d.y, m) : out.set(m, d.y, d.fixed);
  }

  /** Point just in front of the door on the given side (-1/+1 of the perpendicular axis). */
  sidePoint(side: number, dist = 0.5, out = new THREE.Vector3()) {
    this.center(out);
    if (this.def.axis === 'z') out.x += side * dist;
    else out.z += side * dist;
    return out;
  }

  update(dt: number) {
    const prev = this.angle;
    this.angle = damp(this.angle, this.target, 5, dt);
    const moving = Math.abs(this.angle - prev) > 0.0015;
    if (moving && !this.wasMoving) this.onMove?.(this, this.target > prev);
    this.wasMoving = moving;
    this.apply();
  }
}
