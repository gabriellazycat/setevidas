import * as THREE from 'three';
import { rand } from '../core/math';
import { Settings } from '../core/Settings';
import { textures } from '../render/Textures';
import type { House } from '../world/House';
import { ROOMS } from '../world/Layout';
import { roomAt } from '../world/NavGraph';

export interface AmbientCtx {
  house: House;
  camera: THREE.Camera;
  catPos: THREE.Vector3;
  night: number;
  /** can the camera see this point (distance, frustum and walls) */
  observed: (p: THREE.Vector3) => boolean;
  /** world-space angle in degrees between the camera forward and the point */
  angleTo: (p: THREE.Vector3) => number;
  creak: (p: THREE.Vector3) => void;
}

/** Spots where something can watch from the dark: [x, y, z]. */
const EYE_SPOTS: [number, number, number][] = [
  [0.4, 0.35, 8.8], // escritório canto
  [4.7, 0.5, 0.5], // sala, atrás do sofá
  [0.5, -2.6, 0.6], // porão
  [7.5, -2.5, 9.4], // porão fundo
  [11.3, -2.4, 0.7], // lavanderia
  [0.5, 3.4, 9.3], // hóspedes
  [4.6, 3.4, 0.5], // quarto
  [0.6, 6.5, 0.8], // sótão
  [7.0, 6.4, 9.2], // sótão
];

/** Rare, capped environmental scares. Each one vanishes when looked at or when its room is lit. */
export class Ambient {
  private eyes: THREE.Points;
  private eyeMat: THREE.PointsMaterial;
  private eyeUntil = 0;
  private eyeSeen = 0;
  private eyeSpot = new THREE.Vector3();
  private figure: THREE.Group;
  private figureT = 0;
  private figureSeen = 0;
  private cd = { eyes: 40, figure: 80, door: 60 };
  private clock = 0;

  constructor(scene: THREE.Scene) {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(6), 3));
    this.eyeMat = new THREE.PointsMaterial({ map: textures().dot, size: 0.07, color: '#ff4a2a', transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, fog: false });
    this.eyes = new THREE.Points(g, this.eyeMat);
    this.eyes.frustumCulled = false;
    this.eyes.visible = false;
    scene.add(this.eyes);

    const dark = new THREE.MeshBasicMaterial({ color: '#010102' });
    this.figure = new THREE.Group();
    const body = new THREE.Mesh(new THREE.CylinderGeometry(0.2, 0.28, 1.1, 8), dark);
    body.position.y = 0.55;
    const head = new THREE.Mesh(new THREE.SphereGeometry(0.17, 10, 8), dark);
    head.position.y = 1.35;
    this.figure.add(body, head);
    this.figure.position.set(-1.1, 0.0, 2.7); // outside the sala window
    this.figure.visible = false;
    scene.add(this.figure);
  }

  reset() {
    this.eyes.visible = false;
    this.figure.visible = false;
    this.cd = { eyes: rand(30, 60), figure: rand(60, 120), door: rand(40, 90) };
  }

  update(dt: number, c: AmbientCtx) {
    this.clock += dt;
    if (c.night < 1) return;
    const calm = !Settings.data.reduceFlashes;

    // glowing eyes in a dark corner
    if (this.eyes.visible) {
      const room = roomAt(this.eyeSpot);
      const lit = room ? c.house.lights.isRoomLit(room) : false;
      const watched = c.observed(this.eyeSpot) && c.angleTo(this.eyeSpot) < 14;
      this.eyeSeen = watched ? this.eyeSeen + dt : 0;
      const blink = Math.sin(this.clock * 2.3) > 0.96;
      this.eyeMat.opacity = blink ? 0 : 1;
      if (lit || this.eyeSeen > 0.7 || this.clock > this.eyeUntil) {
        this.eyes.visible = false;
        this.cd.eyes = rand(45, 90);
      }
    } else {
      this.cd.eyes -= dt;
      if (this.cd.eyes <= 0) {
        const spots = EYE_SPOTS.map((s) => new THREE.Vector3(...s)).filter((p) => {
          const d = p.distanceTo(c.catPos);
          const room = roomAt(p);
          return d > 3.5 && d < 9 && room && !c.house.lights.isRoomLit(room) && c.observed(p) === false;
        });
        if (spots.length) {
          const p = spots[Math.floor(Math.random() * spots.length)];
          this.eyeSpot.copy(p);
          const pos = this.eyes.geometry.attributes.position as THREE.BufferAttribute;
          const side = new THREE.Vector3(-(p.z - c.catPos.z), 0, p.x - c.catPos.x).normalize().multiplyScalar(0.07);
          pos.setXYZ(0, p.x + side.x, p.y, p.z + side.z);
          pos.setXYZ(1, p.x - side.x, p.y, p.z - side.z);
          pos.needsUpdate = true;
          this.eyes.visible = true;
          this.eyeSeen = 0;
          this.eyeUntil = this.clock + rand(10, 18);
        } else this.cd.eyes = 8;
      }
    }

    // a figure standing outside the window (nights 3+), gone the moment it is looked at
    if (this.figure.visible) {
      this.figureT -= dt;
      const p = this.figure.position.clone().setY(1.4);
      const watched = c.observed(p) && c.angleTo(p) < 16;
      this.figureSeen = watched ? this.figureSeen + dt : 0;
      if (this.figureSeen > 0.9 || this.figureT <= 0) {
        this.figure.visible = false;
        this.cd.figure = rand(90, 160);
      }
    } else if (c.night >= 3 && calm) {
      this.cd.figure -= dt;
      const salaLit = c.house.lights.isRoomLit('sala');
      if (this.cd.figure <= 0) {
        const room = roomAt(c.catPos);
        if (room === 'sala' && !salaLit) {
          this.figure.visible = true;
          this.figureT = rand(8, 14);
          this.figureSeen = 0;
        } else this.cd.figure = 10;
      }
    }

    // a door that drifts open on its own, somewhere near but not in view
    this.cd.door -= dt;
    if (this.cd.door <= 0) {
      this.cd.door = rand(70, 140);
      const cands = [...c.house.doors.values()].filter((d) => {
        if (d.locked || d.state !== 'closed' || d.def.style === 'front' || d.def.style === 'basement') return false;
        const ctr = d.center(new THREE.Vector3());
        const dist = ctr.distanceTo(c.catPos);
        return dist > 3 && dist < 10 && !c.observed(ctr);
      });
      if (cands.length) {
        const d = cands[Math.floor(Math.random() * cands.length)];
        d.setState('ajar');
        c.creak(d.center(new THREE.Vector3()));
      }
    }
    void ROOMS;
  }
}
