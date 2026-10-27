import * as THREE from 'three';
import { Threat, makeSilhouette, Wisps } from './Threat';
import type { World } from '../game/World';
import type { NavNode } from '../world/NavGraph';
import { roomAt } from '../world/NavGraph';
import type { RoomId } from '../world/Layout';
import { damp, dampAngle, choose } from '../core/math';

/** Where the Shadow may rise from. Never the bedroom floor. */
const SPAWNS: { node: string; room: RoomId; minNight: number }[] = [
  { node: 'b_porao_mid', room: 'porao', minNight: 1 },
  { node: 'b_lav_mid', room: 'lavanderia', minNight: 2 },
  { node: 'g_esc_mid', room: 'escritorio', minNight: 2 },
  { node: 'g_coz_n', room: 'cozinha', minNight: 3 },
  { node: 'g_sala_mid', room: 'sala', minNight: 3 },
  { node: 'a_mid', room: 'sotao', minNight: 5 },
];

/**
 * A Sombra — rises from somewhere in the house (never the bedroom floor) and walks through the
 * dark toward whoever it is after. It cannot stand light: lighting the room it is in banishes it.
 * It avoids lit rooms when it can and drains any light in its way. Bulbs also die on their own,
 * so a lit room is only a short-lived shield.
 */
export class Shadow extends Threat {
  readonly id = 'shadow' as const;
  readonly name = 'A Sombra';
  group: THREE.Group;
  private wisps: Wisps;
  private route: NavNode[] = [];
  private ri = 0;
  pos = new THREE.Vector3();
  private yaw = 0;
  private draining: RoomId | null = null;
  private drainT = 0;
  private visible = 0;
  private breathT = 0;
  private lastSpawn = '';
  private spawn = SPAWNS[0];
  private retargetT = 0;

  constructor(w: World) {
    super(w);
    this.group = makeSilhouette(1.95);
    this.group.visible = false;
    w.scene.add(this.group);
    this.wisps = new Wisps(w.scene, 36, '#020203', 0.35, 0.3);
    this.wisps.opacity = 0;
    this.route = [this.nav().get(SPAWNS[0].node)];
    this.pos.copy(this.route[0].p);
  }

  private nav() {
    return this.w.house.nav;
  }

  private pickSpawn() {
    const w = this.w;
    const lights = w.house.lights;
    const opts = SPAWNS.filter((s) => s.minNight <= w.night && s.node !== this.lastSpawn);
    const list = opts.length ? opts : SPAWNS.filter((s) => s.minNight <= Math.max(1, w.night));
    // prefer dark rooms away from the cat
    const scored = list.map((s) => {
      const n = this.nav().get(s.node);
      const dist = n.p.distanceTo(w.cat.pos);
      let score = Math.random() * 2 + Math.min(dist, 12) * 0.2;
      if (lights.isRoomLit(s.room)) score -= 1.5;
      if (dist < 4.5) score -= 5;
      return { s, score };
    });
    scored.sort((a, b) => b.score - a.score);
    this.spawn = scored[0]?.s ?? SPAWNS[0];
    this.lastSpawn = this.spawn.node;
  }

  private litPenalty = (n: NavNode) => (this.w.house.lights.isRoomLit(n.room) ? 14 : 0);

  private buildRoute(from: NavNode) {
    const nav = this.nav();
    const tgt = this.target;
    let to = nav.get(tgt.cfg.bedNode);
    if (!tgt.inBed) to = nav.nearest(tgt.pos);
    this.route = nav.route(from, to, true, this.litPenalty);
    this.ri = 0;
  }

  reset() {
    this.stage = 0;
    this.t = 0;
    this.ri = 0;
    this.draining = null;
    this.group.visible = false;
    this.visible = 0;
    this.wisps.opacity = 0;
    this.target.paralysis = false;
    for (const l of this.w.house.lights.lights) if (l.flicker > 0 && l.def.room !== 'dynamic') l.flicker = 0;
    this.pickSpawn();
    this.buildRoute(this.nav().get(this.spawn.node));
    this.pos.copy(this.route[0].p);
  }

  get room(): RoomId {
    return this.route[Math.min(this.ri, this.route.length - 1)]?.room ?? 'porao';
  }

  /** where the player should go to light it up */
  get roomHint(): RoomId {
    return this.room;
  }

  protected onStage(s: number) {
    const w = this.w;
    const a = w.audio;
    const lights = w.house.lights;
    if (s === 1) {
      this.buildRoute(this.nav().get(this.spawn.node));
      this.pos.copy(this.route[0].p);
      const at = this.pos.clone().add(new THREE.Vector3(0, 1.2, 0));
      if (this.spawn.room === 'porao') {
        const door = w.house.doors.get('d_porao')!;
        if (door.state === 'closed') {
          setTimeout(() => {
            if (this.stage >= 1) {
              door.setState('ajar');
              a.creak(door.center(new THREE.Vector3()).add(new THREE.Vector3(0, 1, 0)), 0.6, 2.2, 0.7);
            }
          }, 2500);
        }
      } else a.creak(at, 0.5, 1.8, 0.65);
      a.breath(at.clone().setY(this.pos.y + 1.6), 0.55);
    }
    if (s === 2) {
      const l = lights.byRoom.get(this.spawn.room);
      if (l && l.on) {
        this.draining = this.spawn.room;
        l.flicker = 1;
        a.buzz(l.light.position, 1.5);
        setTimeout(() => {
          l.flicker = 0;
          l.setOn(false);
          l.dead = 2;
          this.draining = null;
          a.click(l.light.position, 0.6);
        }, 1500);
      }
      a.creak(this.pos.clone().add(new THREE.Vector3(0, 1, 0)), 0.35, 1.6, 0.6);
    }
    if (s === 4) {
      this.target.say(choose(['Hmm... quem tá aí...?', '...{cat}? É você?', 'Que frio...']), 2.6, 'whisper');
      const lamp = lights.get(this.target.cfg.lampIndex);
      if (lamp.on) {
        this.draining = this.target.cfg.bedRoom;
        lamp.flicker = 1;
        setTimeout(() => {
          lamp.flicker = 0;
          lamp.setOn(false);
          lamp.dead = 2;
          this.draining = null;
        }, 1800);
      }
      a.breath(this.pos.clone().add(new THREE.Vector3(0, 1.6, 0)), 0.8);
    }
    if (s === 5) {
      if (this.target.inBed) this.target.paralysis = true;
      w.fx.sting(0.55);
      w.fx.distort(0.6);
    }
  }

  protected tick(dt: number) {
    const w = this.w;
    const lights = w.house.lights;
    const tgt = this.target;
    this.breathT -= dt;
    this.updateVisual(dt);

    // banished if the room it stands in is lit
    if (this.stage >= 2) {
      const here = roomAt(this.pos) ?? this.room;
      const lit = lights.isRoomLit(here);
      if (lit && this.draining !== here && this.t > 0.3) {
        this.banish();
        return;
      }
    }

    if (this.stage === 1 && this.t > this.d(9)) this.setStage(2);
    else if (this.stage === 2 && this.t > this.d(5)) this.setStage(3);
    else if (this.stage === 3) {
      // a person who left the bed is hunted where she stands
      this.retargetT -= dt;
      if (this.retargetT <= 0) {
        this.retargetT = 3;
        const wantRoom = tgt.inBed ? tgt.cfg.bedRoom : (roomAt(tgt.pos) ?? tgt.cfg.bedRoom);
        const last = this.route[this.route.length - 1];
        if (!last || last.room !== wantRoom) this.buildRoute(this.nav().nearest(this.pos, true));
      }
      const next = this.route[this.ri + 1];
      if (!next) {
        this.setStage(4);
      } else {
        const nextRoom = next.room;
        const reachesBed = nextRoom === tgt.cfg.bedRoom || this.ri + 1 >= this.route.length - 1;
        if (nextRoom !== this.room && reachesBed && !this.mayAttack) return;
        if (nextRoom !== this.room && lights.isRoomLit(nextRoom)) {
          // stand at the threshold and drain the light
          if (this.draining !== nextRoom) {
            this.draining = nextRoom;
            this.drainT = 0;
            const nl = lights.byRoom.get(nextRoom);
            w.audio.buzz(nl ? nl.light.position : next.p, this.d(3.5));
          }
          this.drainT += dt;
          const l = lights.byRoom.get(nextRoom);
          const isBed = nextRoom === tgt.cfg.bedRoom;
          const lamp = isBed ? lights.get(tgt.cfg.lampIndex) : null;
          if (l) l.flicker = Math.min(1, 0.4 + this.drainT / this.d(3.5));
          if (lamp) lamp.flicker = l?.flicker ?? 1;
          if (this.drainT > this.d(3.5)) {
            const deadT = isBed ? 5.5 : 2.2;
            if (l) {
              l.flicker = 0;
              l.setOn(false);
              l.dead = deadT;
            }
            if (lamp) {
              lamp.flicker = 0;
              lamp.setOn(false);
              lamp.dead = deadT;
            }
            w.audio.click(l ? l.light.position : this.pos, 0.6);
            this.draining = null;
          }
          return;
        }
        this.draining = null;
        const dir = new THREE.Vector3().subVectors(next.p, this.pos);
        const dist = dir.length();
        const sp = 0.85 * w.speed;
        if (dist < 0.05) {
          this.ri++;
          if (this.room === tgt.cfg.bedRoom && tgt.inBed) this.setStage(4);
          else if (this.breathT <= 0 && Math.random() < 0.35) {
            this.breathT = 6;
            w.audio.breath(this.pos.clone().add(new THREE.Vector3(0, 1.6, 0)), 0.45);
          }
        } else {
          this.pos.addScaledVector(dir.normalize(), Math.min(dist, sp * dt));
          this.yaw = dampAngle(this.yaw, Math.atan2(dir.x, dir.z), 6, dt);
        }
        if (Math.random() < dt * 0.25) w.audio.creak(this.pos.clone().add(new THREE.Vector3(0, 0.1, 0)), 0.25, 0.8, 0.7);
        tgt.addFear(0.25 * dt);
        // reached a person walking about in the dark
        if (!tgt.inBed && this.pos.distanceTo(tgt.pos) < 2.0) this.setStage(4);
      }
    } else if (this.stage === 4) {
      // loom over the sleeper, or close in on someone walking about
      const target = tgt.inBed
        ? new THREE.Vector3(...tgt.cfg.bedSide)
        : tgt.pos.clone().add(new THREE.Vector3(Math.sin(tgt.yaw + Math.PI) * 1.1, 0, Math.cos(tgt.yaw + Math.PI) * 1.1));
      this.pos.lerp(target, 1 - Math.exp(-dt * 0.8));
      this.yaw = dampAngle(this.yaw, Math.atan2(tgt.pos.x - this.pos.x, tgt.pos.z - this.pos.z), 4, dt);
      tgt.addFear(4 * dt);
      if (this.t > this.d(8) && this.mayAttack) this.setStage(5);
    } else if (this.stage === 5) {
      const bedP = tgt.cfg.bedSide;
      const target = tgt.inBed ? new THREE.Vector3(bedP[0] - 0.05, bedP[1] + 0.05, bedP[2] + 0.8) : tgt.pos.clone().add(new THREE.Vector3(0, 0, 0.8));
      this.pos.lerp(target, 1 - Math.exp(-dt * 0.6));
      tgt.addFear(8.5 * dt);
    }
  }

  private banish() {
    const w = this.w;
    w.audio.shriek(this.pos.clone().add(new THREE.Vector3(0, 1.5, 0)), 0.7);
    w.fx.flash(0.25, '#ffe6c0');
    w.fx.shake(0.6);
    if (this.stage >= 4) this.target.say(choose(['Ah! A luz...', 'Ufa... foi só um sonho...', 'O que... o que era aquilo?']), 2.6, 'scared');
    this.target.paralysis = false;
    this.repel();
  }

  canHiss(p: THREE.Vector3) {
    return this.stage >= 2 && p.distanceTo(this.pos) < 2.6 && Math.abs(p.y - this.pos.y) < 1.5;
  }

  onHiss(p: THREE.Vector3, strong: boolean) {
    if (!strong || !this.canHiss(p)) return false;
    // pushed back one node, stalls
    if (this.stage >= 4) this.setStage(3);
    this.ri = Math.max(0, this.ri - 1);
    this.pos.copy(this.route[this.ri].p);
    this.target.paralysis = false;
    this.stall = this.d(5);
    this.w.audio.shriek(this.pos.clone().add(new THREE.Vector3(0, 1.5, 0)), 0.35);
    return true;
  }

  protected tickStalled(dt: number) {
    this.updateVisual(dt);
  }

  private updateVisual(dt: number) {
    const show = this.stage >= 2;
    this.visible = damp(this.visible, show ? 1 : 0, 3, dt);
    this.group.visible = this.visible > 0.02;
    const m = this.group.userData.mat as THREE.ShaderMaterial;
    m.uniforms.uAlpha.value = 0.95 * this.visible;
    (this.group.userData.eyes as THREE.MeshBasicMaterial).opacity = this.visible * (0.6 + 0.4 * Math.sin(performance.now() * 0.003));
    this.group.position.copy(this.pos);
    this.group.position.y += Math.sin(performance.now() * 0.0012) * 0.03;
    this.group.rotation.y = this.yaw;
    this.wisps.opacity = 0.55 * this.visible;
    this.wisps.update(dt, this.pos, 1.9);
  }

  focus() {
    if (this.stage === 0) return null;
    return this.pos.clone().add(new THREE.Vector3(0, 1, 0));
  }

  entity() {
    return this.stage >= 2 ? this.pos : null;
  }

  urgency() {
    if (this.stage === 3) return 0.45 + (this.ri / Math.max(1, this.route.length)) * 0.3;
    return this.stage / 5;
  }

  describeDeath() {
    const where = this.target.inBed ? `no quarto de ${this.target.name}` : 'no escuro';
    return {
      title: `${this.target.name} foi levado(a) pela Sombra`,
      why: `A Sombra atravessou a casa e chegou ${where}. Ela só se aproxima onde não há luz.`,
      tip: 'Acenda a luz do cômodo onde ela está (ou a do quarto, antes que ela entre). As lâmpadas queimam sozinhas em 10–20 s: fique de olho e religue.',
    };
  }
}
