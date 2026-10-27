import type { Owner } from '../actors/Owner';
import type { ThreatId } from './World';

/** The people the cat protects. Davi moves in on day 4. */
export class Household {
  members: Owner[];

  constructor(
    public clara: Owner,
    public davi: Owner,
  ) {
    this.members = [clara, davi];
  }

  get present() {
    return this.members.filter((m) => m.present);
  }

  /** weighted pick: prefers people that are not already under attack */
  pickTarget(threat: ThreatId, underAttack: Owner[]): Owner {
    const list = this.present;
    if (list.length === 1) return list[0];
    const weights = list.map((m) => {
      let w = 1;
      if (underAttack.includes(m)) w *= 0.3;
      if (m.paralysis || m.hypno) w *= 0.2;
      if (m.purring) w *= 0.6;
      if (threat === 'visitor' && m.cfg.skeptic) w *= 1.9;
      if ((threat === 'shadow' || threat === 'doll') && m.inBed) w *= 1.2;
      return w;
    });
    let r = Math.random() * weights.reduce((a, b) => a + b, 0);
    for (let i = 0; i < list.length; i++) {
      r -= weights[i];
      if (r <= 0) return list[i];
    }
    return list[0];
  }

  /** nobody may reach 100 */
  anyBroken(): Owner | null {
    for (const m of this.present) if (m.fear >= 100) return m;
    return null;
  }
}
