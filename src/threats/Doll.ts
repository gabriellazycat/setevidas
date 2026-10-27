import * as THREE from 'three';
import { Threat } from './Threat';
import type { World } from '../game/World';
import type { NavNode } from '../world/NavGraph';
import { Carryable } from '../world/Props';
import { stdMat, spectralMat } from '../render/Materials';
import { textures } from '../render/Textures';
import { choose, rand } from '../core/math';

function makeDollMesh() {
  const g = new THREE.Group();
  const porcelain = stdMat({ color: '#efe7de', roughness: 0.25 });
  const dress = stdMat({ color: '#a8707a', roughness: 0.9 });
  const lace = stdMat({ color: '#e9e1d2', roughness: 0.9 });
  const hair = stdMat({ color: '#4a2c1c', roughness: 0.8, flatShading: true });
  const face = stdMat({ map: textures().porcelain, roughness: 0.25 });
  const skirt = new THREE.Mesh(new THREE.ConeGeometry(0.11, 0.18, 12, 1, true), dress);
  skirt.position.y = 0.11;
  const hem = new THREE.Mesh(new THREE.TorusGeometry(0.105, 0.012, 6, 16), lace);
  hem.rotation.x = Math.PI / 2;
  hem.position.y = 0.025;
  const torso = new THREE.Mesh(new THREE.CylinderGeometry(0.04, 0.05, 0.08, 10), dress);
  torso.position.y = 0.22;
  const collar = new THREE.Mesh(new THREE.TorusGeometry(0.04, 0.01, 6, 12), lace);
  collar.rotation.x = Math.PI / 2;
  collar.position.y = 0.26;
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.06, 16, 12), face);
  head.position.y = 0.32;
  head.rotation.y = -Math.PI / 2;
  const hairCap = new THREE.Mesh(new THREE.SphereGeometry(0.065, 12, 10, 0, Math.PI * 2, 0, Math.PI / 1.8), hair);
  hairCap.position.set(0, 0.33, -0.008);
  hairCap.rotation.x = -0.3;
  g.add(skirt, hem, torso, collar, head, hairCap);
  for (const s of [-1, 1]) {
    const curl = new THREE.Mesh(new THREE.CylinderGeometry(0.014, 0.01, 0.1, 6), hair);
    curl.position.set(s * 0.055, 0.28, -0.01);
    const arm = new THREE.Mesh(new THREE.CylinderGeometry(0.012, 0.012, 0.09, 6), porcelain);
    arm.position.set(s * 0.055, 0.19, 0.01);
    arm.rotation.z = s * 0.3;
    g.add(curl, arm);
  }
  g.traverse((o) => {
    if ((o as THREE.Mesh).isMesh) {
      o.castShadow = true;
      o.receiveShadow = true;
    }
  });
  return g;
}

/**
 * A Boneca — climbs out of the attic chest and creeps toward Clara,
 * but only moves while nobody is watching. Stare at it with cat vision
 * (or keep its room lit) to freeze it; carry it back to the chest.
 */
export class Doll extends Threat {
  readonly id = 'doll' as const;
  readonly name = 'A Boneca';
  item: Carryable;
  private route: NavNode[];
  private ri = 0;
  private hopT = 0;
  private glow: THREE.Mesh;
  carried = false;
  inChest = true;
  private routeFor = '';
  private giggleT = 3;

  constructor(w: World) {
    super(w);
    const mesh = makeDollMesh();
    this.item = new Carryable('doll', 'a boneca', mesh);
    w.scene.add(mesh);
    w.house.carryables.set('doll', this.item);
    const nav = w.house.nav;
    this.route = nav.route(nav.get('a_chest'), nav.get('f_quarto_bed'), true);
    this.routeFor = 'f_quarto_bed';
    // a cyan outline only cat vision shows
    this.glow = new THREE.Mesh(new THREE.SphereGeometry(0.2, 10, 8), spectralMat({ color: '#000000', rim: '#000000', alpha: 0, vision: '#7ff9ff', noise: 0.1 }));
    this.glow.scale.set(0.7, 1.1, 0.7);
    mesh.add(this.glow);
    this.glow.position.y = 0.2;
    this.hideInChest();
  }

  private hideInChest() {
    this.inChest = true;
    this.item.enabled = false;
    this.item.mesh.visible = false;
    this.item.place(this.w.house.chestPos.clone().setY(6.1));
  }

  reset() {
    this.stage = 0;
    this.t = 0;
    this.ri = 0;
    this.carried = false;
    if (this.w.cat.carrying === this.item) this.w.cat.carrying = null;
    this.hideInChest();
    this.w.house.setChest(false);
  }

  protected onStage(s: number) {
    const w = this.w;
    if (s === 1) {
      w.house.setChest(true);
      w.audio.creak(w.house.chestPos.clone().add(new THREE.Vector3(0, 0.4, 0)), 0.45, 1.6, 1.3);
      setTimeout(() => w.audio.giggle(w.house.chestPos.clone().add(new THREE.Vector3(0, 0.5, 0))), 1200);
    }
    if (s === 2) {
      if (w.house.hatchTarget < 0.5) {
        w.house.setHatch(true);
        w.audio.creak(new THREE.Vector3(6.85, 5.6, 1.6), 0.55, 1.8, 0.9);
        setTimeout(() => w.audio.thud(new THREE.Vector3(6.85, 3.3, 2.2), 0.6, 60), 1500);
      }
      this.inChest = false;
      this.item.enabled = true;
      this.item.mesh.visible = true;
      this.ri = 0;
      // the way to whoever it is after
      const nav = w.house.nav;
      this.route = nav.route(nav.get('a_chest'), nav.get(this.target.cfg.bedNode), true);
      this.routeFor = this.target.cfg.bedNode;
      this.item.place(this.route[0].p.clone().add(new THREE.Vector3(0.3, 0, -0.2)), rand(-3, 3));
      w.audio.porcelain(this.item.pos);
    }
    if (s === 5) {
      w.fx.sting(0.5);
      w.audio.giggle(this.item.pos.clone().add(new THREE.Vector3(0, 0.4, 0)));
    }
  }

  private observed() {
    return this.w.isObserved(this.item.pos.clone().add(new THREE.Vector3(0, 0.25, 0)), true);
  }

  protected tick(dt: number) {
    const w = this.w;
    if (this.carried) {
      // it fights back: giggles and drains the cat's focus
      this.giggleT -= dt;
      if (this.giggleT <= 0) {
        this.giggleT = 3.2;
        w.audio.giggle(w.cat.head.clone());
        w.fx.shake(0.12);
      }
      w.cat.focus = Math.max(0, w.cat.focus - 4 * dt);
      return;
    }
    const obs = this.observed();
    if (this.stage === 1 && this.t > this.d(9)) this.setStage(2);
    else if (this.stage === 2 && this.t > this.d(5)) this.setStage(3);
    else if (this.stage >= 3) {
      if (!obs) this.hopT += dt;
      else this.hopT = Math.max(0, this.hopT - dt * 0.5);
      const interval = this.stage === 3 ? this.d(5) : this.d(8);
      if (this.hopT > interval) {
        this.hopT = 0;
        this.hop();
      }
      if (this.stage === 4) this.target.addFear(4.5 * dt);
      if (this.stage === 5) this.target.addFear(8.5 * dt);
      if (this.stage === 3) this.target.addFear(0.2 * dt);
    }
    this.glowUpdate();
  }

  private hop() {
    const w = this.w;
    if (this.stage === 5) return;
    if (this.stage === 4) {
      if (!this.mayAttack) return;
      // onto the bed, beside her
      this.item.place(new THREE.Vector3(...this.target.cfg.bedTop), Math.PI);
      w.audio.porcelain(this.item.pos);
      this.setStage(5);
      return;
    }
    const nextI = Math.min(this.ri + 1, this.route.length - 1);
    const next = this.route[nextI];
    if (next.room === this.target.cfg.bedRoom && !this.mayAttack) return;
    this.ri = nextI;
    const p = next.p.clone().add(new THREE.Vector3(rand(-0.25, 0.25), 0, rand(-0.25, 0.25)));
    // face toward the bedroom
    const ahead = this.route[Math.min(this.ri + 1, this.route.length - 1)].p;
    this.item.place(p, Math.atan2(ahead.x - p.x, ahead.z - p.z));
    w.audio.porcelain(p);
    if (Math.random() < 0.35) setTimeout(() => w.audio.giggle(p.clone().add(new THREE.Vector3(0, 0.4, 0))), 300);
    if (next.room === this.target.cfg.bedRoom) this.setStage(4);
  }

  private glowUpdate() {
    const m = this.glow.material as THREE.ShaderMaterial;
    m.uniforms.uAlpha.value = 0;
  }

  /** the cat picked it up */
  pickedUp() {
    this.carried = true;
    this.target.addFear(0);
  }

  /** the cat dropped it somewhere */
  dropped(p: THREE.Vector3) {
    this.carried = false;
    if (this.stage < 3) return;
    // continue from the closest route node
    let best = 0;
    let bd = Infinity;
    this.route.forEach((n, i) => {
      const d = n.p.distanceTo(p) + Math.abs(n.p.y - p.y) * 3;
      if (d < bd) {
        bd = d;
        best = i;
      }
    });
    this.ri = best;
    this.stage = this.route[best].room === this.target.cfg.bedRoom ? 4 : 3;
    this.hopT = 0;
  }

  describeDeath() {
    return {
      title: `${this.target.name} foi levado(a) pela Boneca`,
      why: 'A Boneca andou pela casa sempre que ninguém olhava e apareceu na cama da pessoa.',
      tip: 'Encare-a (Visão de Gato ou cômodo aceso) para congelá-la, pegue-a na boca e leve de volta ao baú do sótão. Carregá-la drena o Foco e você não pode bufar.',
    };
  }

  canHiss(p: THREE.Vector3) {
    return this.stage >= 3 && !this.carried && p.distanceTo(this.item.pos) < 2.2;
  }

  /** the cat put it back in the chest */
  returned() {
    const w = this.w;
    w.audio.thud(w.house.chestPos.clone().add(new THREE.Vector3(0, 0.4, 0)), 0.5, 80);
    w.audio.giggle(w.house.chestPos.clone().add(new THREE.Vector3(0, 0.4, 0)));
    if (this.stage >= 4) this.target.say(choose(['Ufa... que pesadelo.', 'Hm? Tinha alguma coisa na cama...?']), 2.6, 'whisper');
    this.repel();
  }

  onHiss(p: THREE.Vector3, strong: boolean) {
    if (this.stage < 3 || !strong || this.carried) return false;
    if (p.distanceTo(this.item.pos) > 2.2) return false;
    this.ri = Math.max(0, this.ri - 1);
    if (this.stage >= 4) this.stage = 3;
    this.item.place(this.route[this.ri].p.clone(), this.item.yaw);
    this.w.audio.porcelain(this.item.pos);
    this.stall = this.d(4);
    return true;
  }

  focus() {
    if (this.stage === 0) return null;
    return this.stage < 2 ? this.w.house.chestPos : this.item.pos;
  }
  entity() {
    return this.stage >= 2 && !this.carried ? this.item.pos : null;
  }
}
