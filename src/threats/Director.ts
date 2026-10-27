import * as THREE from 'three';
import type { World, ThreatId } from '../game/World';
import { Threat } from './Threat';
import { Shadow } from './Shadow';
import { Whisperer } from './Whisperer';
import { Drowner } from './Drowner';
import { Doll } from './Doll';
import { Visitor } from './Visitor';
import { Thing } from './Thing';
import { Hound } from './Hound';
import { NIGHT_THREATS, NIGHT_SPEED, NEW_ON_NIGHT, HOUND_FROM } from '../game/Config';

export { NIGHT_THREATS };

/** first appearance delays (seconds) of a threat that is not new tonight */
const FIRST_DELAY: Record<ThreatId, number> = {
  shadow: 18,
  whisperer: 36,
  drowner: 48,
  doll: 62,
  visitor: 76,
  thing: 0,
  hound: 0,
};

/** a uniform description of "what is the most urgent danger", for the cat's ears and the HUD */
export interface Alert {
  id: ThreatId;
  focus: THREE.Vector3 | null;
  urgency: number;
  stage: number;
}

export class Director {
  shadow: Shadow;
  whisperer: Whisperer;
  drowner: Drowner;
  doll: Doll;
  visitor: Visitor;
  thing: Thing;
  hound: Hound;
  all: Threat[];
  baseSpeed = 1;
  /** seconds since a ghost last went into an attack stage */
  private calm = 99;

  constructor(private w: World) {
    this.shadow = new Shadow(w);
    this.whisperer = new Whisperer(w);
    this.drowner = new Drowner(w);
    this.doll = new Doll(w);
    this.visitor = new Visitor(w);
    this.thing = new Thing(w);
    this.hound = new Hound(w);
    this.all = [this.shadow, this.whisperer, this.drowner, this.doll, this.visitor, this.thing];
  }

  get(id: ThreatId) {
    return this.all.find((t) => t.id === id)!;
  }

  startNight(n: number, nightSpeedSetting: number) {
    this.baseSpeed = (NIGHT_SPEED[n] ?? 1) * nightSpeedSetting;
    this.w.speed = this.baseSpeed;
    this.calm = 99;
    for (const t of this.all) t.disable();
    this.whisperer.replugAll();
    this.drowner.dryAll();
    const ids = NIGHT_THREATS[n] ?? [];
    const fresh = NEW_ON_NIGHT[n] ?? null;
    for (const id of ids) {
      // the ghost that is new tonight shows up early, so its night teaches it
      const first = id === fresh ? 24 : n === 1 ? FIRST_DELAY[id] + 8 : FIRST_DELAY[id];
      this.get(id).enable(first / this.baseSpeed);
    }
    if (n >= HOUND_FROM) this.hound.startNight(n, this.baseSpeed);
    else this.hound.stop();
  }

  stopAll() {
    for (const t of this.all) t.disable();
    this.hound.stop();
  }

  update(dt: number) {
    // fairness: limit simultaneous attacks
    const cap = this.w.night >= 4 ? 2 : 1;
    const attackers = this.all.filter((t) => t.enabled && t.stage >= 4 && t.id !== 'thing');
    for (const t of this.all) t.mayAttack = t.stage >= 4 || attackers.length < cap;
    // the awakened Thing makes everything faster
    this.w.speed = this.baseSpeed * (this.thing.enabled && this.thing.stage > 0 ? 1.18 : 1);
    for (const t of this.all) t.update(dt);

    // the hound never overlaps with an attack and always has a long calm before it starts
    if (attackers.length) this.calm = 0;
    else this.calm += dt;
    this.hound.mayHunt = attackers.length === 0 && this.calm > 10;
    this.hound.update(dt);
  }

  /** the most urgent danger: where the cat's ears point */
  mostUrgent(): Alert | null {
    let best: Alert | null = null;
    let bu = 0.05;
    for (const t of this.all) {
      if (!t.enabled || t.stage === 0) continue;
      const u = t.urgency();
      if (u > bu) {
        bu = u;
        best = { id: t.id, focus: t.focus(), urgency: u, stage: t.stage };
      }
    }
    // the hound is only "urgent" once it is actually after the cat
    const hu = this.hound.threatLevel();
    if (hu > bu && this.hound.active) best = { id: 'hound', focus: this.hound.focus(), urgency: hu, stage: this.hound.hunting ? 4 : 2 };
    return best;
  }

  tension() {
    let m = 0;
    for (const t of this.all) if (t.enabled) m = Math.max(m, t.stage / 5);
    return Math.max(m, this.hound.threatLevel() * 0.8);
  }

  /** nearest visible entity to p (for fur bristle) */
  nearestEntity(p: THREE.Vector3) {
    let bd = Infinity;
    for (const t of this.all) {
      if (!t.enabled) continue;
      const e = t.entity();
      if (!e) continue;
      const d = e.distanceTo(p);
      if (d < bd) bd = d;
    }
    if (this.hound.active) bd = Math.min(bd, this.hound.pos.distanceTo(p));
    return bd;
  }

  hiss(p: THREE.Vector3, strong: boolean) {
    let any = false;
    for (const t of this.all) if (t.enabled && t.onHiss(p, strong)) any = true;
    if (this.hound.onHiss(p, strong)) any = true;
    return any;
  }

  /** would a hiss from here do anything? (for the on-screen prompt) */
  canHissAt(p: THREE.Vector3) {
    for (const t of this.all) if (t.enabled && t.stage > 0 && t.canHiss(p)) return true;
    return this.hound.canHiss(p);
  }

  /** sounds made in the house: lure or alert whoever hunts by ear */
  hearNoise(p: THREE.Vector3, loud: number, kind: string) {
    this.hound.hearNoise(p, loud, kind);
    this.drowner.hearNoise(p, loud);
  }
}
