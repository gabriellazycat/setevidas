import * as THREE from 'three';
import { Threat, makeSilhouette } from './Threat';
import type { World } from '../game/World';
import type { Faucet } from '../world/House';
import type { LoopHandle } from '../audio/Audio';
import type { NavNode } from '../world/NavGraph';
import { roomAt } from '../world/NavGraph';
import { spectralMat } from '../render/Materials';
import { textures } from '../render/Textures';
import { choose, clamp, damp, dampAngle } from '../core/math';

/**
 * A Afogadora — comes through the water, and then WALKS.
 * 1-2  a faucet drips, then runs and the basin overflows (close it to banish her).
 * 3    the puddle spreads.
 * 4    she emerges and walks toward her target, leaving wet footprints and slippery puddles.
 *      She hunts by SOUND: knock something over in another room and she turns to it.
 *      She is made of water, so she melts as she walks (essence); a strong hiss costs her a lot.
 * 5    she has reached the person: cold hands, fear climbs fast.
 */
export class Drowner extends Threat {
  readonly id = 'drowner' as const;
  readonly name = 'A Afogadora';
  source: Faucet | null = null;
  private tub: Faucet;
  private water: LoopHandle | null = null;
  private dripT = 0;
  /** the arms rising from the water (also used by the bath scene) */
  hands: THREE.Group;
  private handsVis = 0;
  /** the walking body */
  body: THREE.Group;
  pos = new THREE.Vector3();
  private yaw = 0;
  private essence = 100;
  private path: THREE.Vector3[] = [];
  private pi = 0;
  private segFrom = new THREE.Vector3();
  private lure: THREE.Vector3 | null = null;
  private lureT = 0;
  private lureWait = 0;
  private stepAcc = 0;
  private repathT = 0;
  private bodyVis = 0;
  private foot: { m: THREE.Mesh; life: number }[] = [];
  private footI = 0;
  private closedByCat = false;
  private coldT = 0;

  constructor(w: World) {
    super(w);
    this.tub = w.house.faucets.find((f) => f.id === 'tub')!;
    this.hands = new THREE.Group();
    const m = spectralMat({ color: '#9fb4b8', rim: '#e6f6ff', alpha: 0, noise: 0.3, vision: '#5ff6ff', wobble: 0.01 });
    for (let i = 0; i < 2; i++) {
      const arm = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.045, 0.7, 6), m);
      arm.position.set(i ? 0.18 : -0.18, 0.3, 0);
      arm.rotation.z = i ? -0.3 : 0.3;
      const hand = new THREE.Mesh(new THREE.SphereGeometry(0.06, 8, 6), m);
      hand.scale.set(1, 1.5, 0.5);
      hand.position.set(i ? 0.29 : -0.29, 0.66, 0);
      for (let f = 0; f < 4; f++) {
        const finger = new THREE.Mesh(new THREE.CylinderGeometry(0.008, 0.012, 0.12, 4), m);
        finger.position.set((i ? 0.29 : -0.29) + (f - 1.5) * 0.022, 0.78, 0);
        this.hands.add(finger);
      }
      this.hands.add(arm, hand);
    }
    this.hands.userData.mat = m;
    this.hands.visible = false;
    w.scene.add(this.hands);

    this.body = makeSilhouette(1.72, { color: '#0a1317', rim: '#5aa6bd', vision: '#5ff6ff', alpha: 0.86, noise: 0.2 });
    this.body.visible = false;
    w.scene.add(this.body);

    // wet footprints
    const fm = new THREE.MeshBasicMaterial({ map: textures().blob, color: '#0b1216', transparent: true, opacity: 0, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2 });
    for (let i = 0; i < 28; i++) {
      const p = new THREE.Mesh(new THREE.PlaneGeometry(0.2, 0.3), fm.clone());
      p.rotation.x = -Math.PI / 2;
      p.visible = false;
      p.renderOrder = 2;
      w.scene.add(p);
      this.foot.push({ m: p, life: 0 });
    }
  }

  reset() {
    this.stage = 0;
    this.t = 0;
    for (const f of this.w.house.faucets) f.running = 0;
    this.source = null;
    this.water?.stop(0.6);
    this.water = null;
    this.hands.visible = false;
    this.handsVis = 0;
    this.body.visible = false;
    this.bodyVis = 0;
    this.essence = 100;
    this.lure = null;
    this.path = [];
    this.closedByCat = false;
    if (this.target.taskName === 'drown') this.target.abort();
  }

  /** dry everything (new night) */
  dryAll() {
    for (const f of this.w.house.faucets) {
      f.level = 0;
      f.puddle = 0;
      f.running = 0;
    }
    for (const f of this.foot) {
      f.life = 0;
      f.m.visible = false;
    }
  }

  protected onStage(s: number) {
    const w = this.w;
    if (s === 1) {
      // not the one she used last time: variety
      const opts = w.house.faucets.filter((f) => f !== this.source);
      this.source = choose(opts.length ? opts : w.house.faucets);
      this.dripT = 0;
    }
    if (s === 2 && this.source) {
      this.source.running = 1;
      this.water = w.audio.loop('water', this.source.spout, { ref: 1.2, gain: 0.7 });
      this.water.setLevel(0.6);
      w.audio.creak(this.source.handle, 0.25, 0.5, 2.2);
    }
    if (s === 4 && this.source) {
      // she rises from the puddle
      this.pos.copy(this.source.puddleCenter);
      this.pos.y = this.source.floorY;
      this.essence = 100;
      this.yaw = 0;
      this.bodyVis = 0;
      this.path = [];
      this.pi = 0;
      this.repath();
      w.audio.thud(this.pos.clone().add(new THREE.Vector3(0, 0.3, 0)), 0.4, 50);
      w.audio.breath(this.pos.clone().add(new THREE.Vector3(0, 1.5, 0)), 0.5);
      w.hint('Algo molhado saiu da água e está andando.', 3.5);
    }
    if (s === 5) {
      w.fx.sting(0.5);
      w.audio.shriek(this.pos.clone().add(new THREE.Vector3(0, 1.4, 0)), 0.3);
    }
  }

  /** close a faucet (cat interaction) */
  close(f: Faucet) {
    if (this.stage >= 1 && this.stage <= 3 && f === this.source) this.closedByCat = true;
    f.running = 0;
    this.w.audio.creak(f.handle, 0.2, 0.4, 2.4);
    if (f === this.source) this.water?.stop(0.5);
  }

  /** sounds in the house lure her */
  hearNoise(p: THREE.Vector3, loud: number) {
    if (!this.enabled || this.stage < 4 || loud < 0.22) return;
    const hops = this.w.hops(p, this.pos);
    if (hops > 4) return;
    this.lure = p.clone();
    this.lureT = 14;
    this.lureWait = 0;
    this.repath();
  }

  private nav() {
    return this.w.house.nav;
  }

  private destination(): THREE.Vector3 {
    if (this.lure && this.lureT > 0) return this.lure;
    const tgt = this.target;
    return tgt.inBed ? this.nav().get(tgt.cfg.bedNode).p : tgt.pos;
  }

  private repath() {
    const nav = this.nav();
    const dest = this.destination();
    const a = nav.nearest(this.pos);
    const b = nav.nearest(dest);
    const nodes: NavNode[] = nav.route(a, b, false);
    this.path = nodes.map((n) => n.p.clone());
    if (this.path.length > 1) {
      const d0 = this.pos.distanceTo(this.path[1]);
      const d01 = this.path[0].distanceTo(this.path[1]);
      if (d0 < d01 && Math.abs(this.pos.y - this.path[0].y) < 0.6) this.path.shift();
    }
    this.pi = 0;
    this.segFrom.copy(this.pos);
  }

  private walk(dt: number, speed: number) {
    const t = this.path[this.pi];
    if (!t) return true;
    const dx = t.x - this.pos.x;
    const dz = t.z - this.pos.z;
    const dist = Math.hypot(dx, dz);
    if (dist < 0.1) {
      this.pi++;
      this.segFrom.copy(this.pos);
      return this.pi >= this.path.length;
    }
    const step = Math.min(dist, speed * dt);
    this.pos.x += (dx / dist) * step;
    this.pos.z += (dz / dist) * step;
    const segLen = Math.hypot(t.x - this.segFrom.x, t.z - this.segFrom.z);
    const done = segLen > 1e-3 ? 1 - dist / segLen : 1;
    this.pos.y = this.segFrom.y + (t.y - this.segFrom.y) * clamp(done);
    this.yaw = dampAngle(this.yaw, Math.atan2(dx, dz), 6, dt);
    this.essence -= step * 3.0;
    this.stepAcc += step;
    if (this.stepAcc > 0.55) {
      this.stepAcc = 0;
      this.placeFoot();
      this.w.audio.drip(this.pos.clone().add(new THREE.Vector3(0, 0.1, 0)));
    }
    return false;
  }

  private placeFoot() {
    const f = this.foot[this.footI++ % this.foot.length];
    f.life = 14;
    f.m.visible = true;
    const ground = this.w.house.col.groundHeight(this.pos.x, this.pos.z, this.pos.y + 0.4, 0.1);
    const side = this.footI % 2 ? 1 : -1;
    f.m.position.set(this.pos.x + Math.cos(this.yaw) * 0.08 * side, (ground > -500 ? ground : this.pos.y) + 0.012, this.pos.z - Math.sin(this.yaw) * 0.08 * side);
    f.m.rotation.z = this.yaw;
  }

  /** is this point on a wet puddle? (the cat slips there) */
  wetAt(p: THREE.Vector3) {
    let wet = 0;
    for (const f of this.w.house.faucets) {
      if (f.puddle < 0.05 || Math.abs(p.y - f.floorY) > 0.6) continue;
      const r = f.puddle * 1.4;
      const d = Math.hypot(p.x - f.puddleCenter.x, p.z - f.puddleCenter.z);
      if (d < r) wet = Math.max(wet, clamp(1 - d / r) * 0.6 + 0.4);
    }
    if (this.stage >= 4 && this.bodyVis > 0.3 && Math.abs(p.y - this.pos.y) < 0.6) {
      const d = Math.hypot(p.x - this.pos.x, p.z - this.pos.z);
      if (d < 1.0) wet = Math.max(wet, 0.8);
    }
    return wet;
  }

  protected tick(dt: number) {
    const w = this.w;
    const src = this.source;
    if (!src) return;
    // the cat closed the faucet that matters before she got out
    if (this.closedByCat || (this.stage >= 2 && this.stage <= 3 && src.running <= 0.01)) {
      this.closedByCat = false;
      this.banish(false);
      return;
    }
    if (this.stage === 1) {
      this.dripT -= dt;
      if (this.dripT <= 0) {
        this.dripT = 0.5 + Math.random() * 0.7;
        w.audio.drip(src.spout);
        src.running = 0.06;
      }
      if (this.t > this.d(10)) this.setStage(2);
    } else if (this.stage === 2) {
      src.level = Math.min(1, src.level + dt / this.d(16));
      if (src.level >= 1) this.setStage(3);
    } else if (this.stage === 3) {
      src.puddle = Math.min(1, src.puddle + dt / this.d(14));
      this.target.addFear(0.3 * dt);
      if (src.puddle >= 1 && this.mayAttack) this.setStage(4);
    } else if (this.stage >= 4) {
      this.updateWalker(dt);
    }
    // hands rise in the water while it overflows
    const handTarget = this.stage >= 3 && this.stage < 4 ? 1 : 0;
    this.handsVis = damp(this.handsVis, handTarget, 2, dt);
    this.hands.visible = this.handsVis > 0.02;
    if (this.hands.visible) {
      this.hands.position.copy(src.puddleCenter).setY(src.floorY - 0.5);
      this.hands.position.y += this.handsVis * 0.45 + Math.sin(performance.now() * 0.002) * 0.03;
      (this.hands.userData.mat as THREE.ShaderMaterial).uniforms.uAlpha.value = 0.45 * this.handsVis;
    }
  }

  private updateWalker(dt: number) {
    const w = this.w;
    const tgt = this.target;
    this.lureT -= dt;
    this.coldT -= dt;
    const atTarget = this.pos.distanceTo(tgt.pos) < 2.0 && Math.abs(this.pos.y - tgt.pos.y) < 1.5;
    if (this.lure && this.lureT > 0) {
      // goes to a noise, listens, then resumes
      const arrived = this.pos.distanceTo(this.lure) < 1.2 || this.pi >= this.path.length;
      if (arrived) {
        this.lureWait += dt;
        this.yaw += Math.sin(this.lureWait * 2) * dt;
        if (this.lureWait > 3.5) {
          this.lure = null;
          this.repath();
        }
      } else this.walk(dt, 0.8 * w.speed);
    } else {
      this.repathT -= dt;
      if (this.repathT <= 0) {
        this.repathT = 2.5;
        this.repath();
      }
      if (this.stage === 4) {
        const done = this.walk(dt, 0.72 * w.speed);
        if (done || atTarget) this.setStage(5);
        tgt.addFear((roomAt(this.pos) === roomAt(tgt.pos) ? 2.2 : 0.35) * dt);
      } else if (this.stage === 5) {
        // cold wet hands
        tgt.addFear(9.5 * dt);
        this.yaw = dampAngle(this.yaw, Math.atan2(tgt.pos.x - this.pos.x, tgt.pos.z - this.pos.z), 4, dt);
        if (!atTarget) this.setStage(4);
        if (this.coldT <= 0) {
          this.coldT = 3.2;
          w.audio.breath(this.pos.clone().add(new THREE.Vector3(0, 1.4, 0)), 0.5);
        }
      }
    }
    // the source keeps feeding her unless it is closed
    if (this.source && this.source.running > 0.05) this.essence = Math.min(100, this.essence + 4 * dt);
    if (this.essence <= 0) this.banish(true);
    // body visuals
    this.bodyVis = damp(this.bodyVis, 1, 1.5, dt);
    this.body.visible = this.bodyVis > 0.03;
    this.body.position.copy(this.pos);
    this.body.rotation.y = this.yaw;
    (this.body.userData.mat as THREE.ShaderMaterial).uniforms.uAlpha.value = 0.86 * this.bodyVis * clamp(0.35 + this.essence / 100);
    (this.body.userData.eyes as THREE.MeshBasicMaterial).opacity = this.bodyVis * 0.8;
  }

  protected tickStalled(dt: number) {
    for (const f of this.foot) this.fadeFoot(f, dt);
  }

  private fadeFoot(f: { m: THREE.Mesh; life: number }, dt: number) {
    if (f.life <= 0) return;
    f.life -= dt;
    const mat = f.m.material as THREE.MeshBasicMaterial;
    mat.opacity = clamp(f.life / 4) * 0.55;
    if (f.life <= 0) f.m.visible = false;
  }

  /** `melted` = she ran out of essence while the faucet was left running */
  private banish(melted: boolean) {
    const w = this.w;
    const at = this.stage >= 4 ? this.pos.clone().add(new THREE.Vector3(0, 1, 0)) : this.source!.spout;
    w.audio.shriek(at, 0.4);
    if (melted) {
      // she collapses into a puddle that dries slowly
      const f = this.source!;
      f.puddle = Math.max(f.puddle, 0.5);
      w.audio.thud(this.pos.clone().add(new THREE.Vector3(0, 0.2, 0)), 0.4, 60);
    }
    const wasNear = this.stage >= 5;
    this.repel();
    this.body.visible = false;
    if (wasNear) {
      this.target.addFear(4);
      this.target.say(choose(['Ah! Tava tão gelado... mas passou.', 'Foi só um pesadelo... molhado.', '{cat}... obrigada.']), 3, 'scared');
    }
  }

  canHiss(p: THREE.Vector3) {
    return this.stage >= 4 && p.distanceTo(this.pos) < 2.6 && Math.abs(p.y - this.pos.y) < 1.4;
  }

  onHiss(p: THREE.Vector3, strong: boolean) {
    if (!strong || !this.canHiss(p)) return false;
    this.essence -= 38;
    this.w.audio.shriek(this.pos.clone().add(new THREE.Vector3(0, 1.3, 0)), 0.3);
    if (this.stage === 5) this.setStage(4);
    // pushed back along her path, stalled
    this.pi = Math.max(0, this.pi - 1);
    this.lure = null;
    this.stall = this.d(3.5);
    this.w.fx.shake(0.3);
    return true;
  }

  override update(dt: number) {
    super.update(dt);
    for (const f of this.foot) this.fadeFoot(f, dt);
    // basins drain and puddles dry slowly when nothing runs
    for (const f of this.w.house.faucets) {
      if (f.running <= 0.05 && (this.stage === 0 || f !== this.source)) {
        f.level = Math.max(0, f.level - dt * 0.03);
        f.puddle = Math.max(0, f.puddle - dt * 0.01);
      }
    }
  }

  focus() {
    if (!this.source || this.stage === 0) return null;
    return this.stage >= 4 ? this.pos.clone().add(new THREE.Vector3(0, 1, 0)) : this.source.spout;
  }
  entity() {
    if (this.stage >= 4 && this.bodyVis > 0.2) return this.pos;
    return this.stage >= 3 ? this.hands.position : null;
  }
  get runningFaucet() {
    return this.stage >= 1 && this.stage <= 4 ? this.source : null;
  }
  urgency() {
    if (this.stage >= 4) return 0.5 + (this.stage - 4) * 0.35;
    return this.stage / 5;
  }

  describeDeath() {
    return {
      title: `${this.target.name} foi levado(a) pela Afogadora`,
      why: 'A Afogadora saiu da poça, atravessou a casa deixando pegadas molhadas e agarrou a pessoa com mãos geladas.',
      tip: 'Feche a torneira que abre sozinha antes de a poça crescer. Se ela já saiu, faça barulho longe (derrube um copo) para atraí-la, ou bufe de perto: ela derrete ao andar.',
    };
  }
}
