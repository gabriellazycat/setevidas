import * as THREE from 'three';

export interface Interactable {
  id: string;
  pos: THREE.Vector3;
  /** horizontal reach */
  radius: number;
  /** vertical tolerance above the cat's feet (switches are high on the wall) */
  above?: number;
  below?: number;
  prompt: () => string;
  enabled: () => boolean;
  /** seconds to hold; 0 = instant */
  hold?: number | (() => number);
  priority?: number;
  /** if true, works even when the cat is not facing it */
  omni?: boolean;
  onInteract: () => void;
  holdLabel?: () => string;
  /** how the cat looks while holding */
  pose?: 'scratch' | 'busy';
}

const _d = new THREE.Vector3();

export class InteractionSystem {
  list: Interactable[] = [];

  add(i: Interactable) {
    this.list.push(i);
    return i;
  }

  remove(id: string) {
    this.list = this.list.filter((x) => x.id !== id);
  }

  best(catPos: THREE.Vector3, forward: THREE.Vector3): Interactable | null {
    let best: Interactable | null = null;
    let bestScore = -Infinity;
    for (const it of this.list) {
      const dy = it.pos.y - catPos.y;
      if (dy > (it.above ?? 0.9) || dy < -(it.below ?? 0.5)) continue;
      _d.set(it.pos.x - catPos.x, 0, it.pos.z - catPos.z);
      const dist = _d.length();
      if (dist > it.radius) continue;
      if (!it.enabled()) continue;
      let facing = 1;
      if (dist > 0.05) {
        _d.divideScalar(dist);
        facing = _d.dot(forward);
        if (!it.omni && facing < -0.25 && dist > 0.35) continue;
      }
      const score = (it.priority ?? 0) * 10 - dist * 2 + facing * 1.2;
      if (score > bestScore) {
        bestScore = score;
        best = it;
      }
    }
    return best;
  }
}
