import * as THREE from 'three';
import type { Game } from './Game';
import { ROOM_BY_ID, RITUAL_CENTER, SPOTS, HIDE_SPOTS, type RoomId } from '../world/Layout';
import { LAST_NIGHT } from './Config';
import type { ClueId } from '../core/Save';
import { choose } from '../core/math';

const V = (x: number, y: number, z: number) => new THREE.Vector3(x, y, z);
const CLUES: ClueId[] = ['foto', 'coleira', 'chave'];

export function ritualSlot(i: number) {
  const a = -Math.PI / 2 + (i / 3) * Math.PI * 2;
  return V(RITUAL_CENTER[0] + Math.cos(a) * 0.85, RITUAL_CENTER[1], RITUAL_CENTER[2] + Math.sin(a) * 0.85);
}

/** All world interactions the cat can perform. */
export function registerInteractions(g: Game) {
  const h = g.house;
  const inter = g.inter;
  const cat = g.cat;
  const night = () => g.phase === 'night';

  /* ---------------------------------------------------------- light switches */
  for (const l of h.lights.lights) {
    if (!l.switchPos) continue;
    const roomName = l.room ? ROOM_BY_ID[l.room].name.toLowerCase() : '';
    inter.add({
      id: `sw_${l.def.index}`,
      pos: l.switchPos.clone().addScaledVector(l.switchNormal!, 0.25).setY(l.switchPos.y),
      radius: 0.85,
      above: 1.4,
      below: 0.6,
      omni: true,
      prompt: () => (l.dead > 0 ? 'A lâmpada não responde...' : `${l.on ? 'Apagar' : 'Acender'} a luz${roomName ? ` (${roomName})` : ''}`),
      enabled: () => g.phase !== 'morning' || true,
      onInteract: () => {
        g.catHop();
        if (l.dead > 0) {
          g.audio.click(l.switchPos!, 0.4);
          return;
        }
        h.lights.toggle(l);
        g.audio.click(l.switchPos!, 0.5);
        g.onLightToggled(l.def.index, l.on);
      },
    });
  }
  // bedside lamp
  const lamp = h.lights.get(8);
  inter.add({
    id: 'abajur',
    pos: V(0.3, 3.55, 1.68),
    radius: 0.85,
    above: 0.9,
    omni: true,
    prompt: () => (lamp.dead > 0 ? 'O abajur não acende...' : `${lamp.on ? 'Apagar' : 'Acender'} o abajur`),
    enabled: () => true,
    onInteract: () => {
      g.catHop();
      if (lamp.dead > 0) return;
      h.lights.toggle(lamp);
      g.audio.click(lamp.light.position, 0.4);
      g.onLightToggled(8, lamp.on);
    },
  });

  /* ---------------------------------------------------------- doors */
  for (const d of h.doors.values()) {
    if (d.def.style === 'front') continue;
    const c = d.center(new THREE.Vector3());
    for (const side of [-1, 1]) {
      const p = d.sidePoint(side, 0.45);
      p.y = d.def.y;
      inter.add({
        id: `door_${d.def.id}_${side}`,
        pos: p,
        radius: 0.7,
        above: 0.6,
        below: 0.4,
        omni: true,
        priority: 1,
        prompt: () => (d.locked ? 'Arranhar a porta' : 'Abrir a porta'),
        enabled: () => d.isClosed,
        hold: () => (d.locked ? 5 : 0.9),
        pose: 'scratch',
        holdLabel: () => (d.locked ? 'Arranhando...' : 'Empurrando...'),
        onInteract: () => {
          if (d.locked) {
            d.locked = false;
            g.owner.addPatience(-8);
            g.emitNoise(c, 0.6, 'scratch');
            g.onEscapedLock();
          }
          d.setState('ajar');
          g.audio.creak(c.clone().setY(c.y + 1), 0.4, 1.0);
        },
      });
    }
  }

  /* ---------------------------------------------------------- devices (pull the plug) */
  for (const dv of h.devices) {
    inter.add({
      id: `plug_${dv.id}`,
      pos: dv.outlet.clone().addScaledVector(dv.normal, 0.25),
      radius: 0.8,
      above: 1.4,
      below: 0.6,
      omni: true,
      priority: 2,
      prompt: () => `Puxar o fio d${dv.name.startsWith('a ') ? 'a' : 'o'} ${dv.name.slice(2)}`,
      enabled: () => dv.plugged,
      onInteract: () => {
        g.catHop();
        h.setPlugged(dv, false);
        g.audio.click(dv.outlet, 0.7);
        g.audio.thud(dv.outlet, 0.15, 200);
        g.onTask('unplug');
      },
    });
  }

  /* ---------------------------------------------------------- faucets */
  for (const f of h.faucets) {
    inter.add({
      id: `faucet_${f.id}`,
      pos: f.handle.clone().setY(f.floorY + (f.id === 'tub' ? 0 : 0)),
      radius: f.id === 'tub' ? 1.0 : 0.85,
      above: 1.4,
      below: 0.6,
      omni: true,
      priority: 2,
      prompt: () => (f.id === 'tub' ? 'Puxar a tampa do ralo' : `Fechar a torneira (${f.name.replace(/^a /, '')})`),
      enabled: () => f.running > 0.04,
      hold: 0.6,
      pose: 'busy',
      onInteract: () => {
        g.director.drowner.close(f);
        if (f.id === 'tub') f.level = Math.min(f.level, 0.6);
      },
    });
  }

  /* ---------------------------------------------------------- carryables */
  const pickup = (id: string) => {
    const c = h.carryables.get(id)!;
    cat.carrying = c;
    c.carried = true;
    g.audio.click(c.pos, 0.3);
    if (id === 'doll') g.director.doll.pickedUp();
    if ((CLUES as string[]).includes(id)) {
      const cid = id as ClueId;
      const first = !g.flags.clues[cid];
      g.flags.clues[cid] = { x: c.pos.x, y: c.pos.y, z: c.pos.z, onCircle: false };
      if (first) g.onClueFound(cid);
    }
  };
  for (const [id, c] of h.carryables) {
    inter.add({
      id: `pick_${id}`,
      pos: c.pos,
      radius: id === 'coleira' ? 1.15 : id === 'foto' ? 1.0 : 0.6,
      above: 1.0,
      below: 0.7,
      omni: id === 'coleira' || id === 'foto',
      priority: 3,
      prompt: () => {
        if (id === 'coleira' && !g.flags.clues.coleira) return 'Fuçar atrás da máquina de lavar';
        if (id === 'foto' && !g.flags.clues.foto) return 'Fuçar na caixa aberta';
        if (id === 'doll') return 'Pegar a boneca';
        return `Pegar ${c.name}`;
      },
      enabled: () => c.enabled && !c.carried && !cat.carrying && c.mesh.visible && !(g.ritualPlaced(id)),
      hold: () => ((id === 'coleira' && !g.flags.clues.coleira) ? 1.6 : id === 'foto' && !g.flags.clues.foto ? 1.2 : 0),
      pose: 'busy',
      onInteract: () => pickup(id),
    });
  }

  // put the doll back in the chest
  inter.add({
    id: 'chest',
    pos: V(3.1, 6, 8.3),
    radius: 0.9,
    above: 0.9,
    omni: true,
    priority: 5,
    prompt: () => 'Guardar a boneca no baú',
    enabled: () => cat.carrying?.id === 'doll',
    onInteract: () => {
      const c = cat.carrying!;
      cat.carrying = null;
      c.carried = false;
      g.director.doll.returned();
    },
  });

  // ritual circle
  inter.add({
    id: 'ritual_place',
    pos: V(...RITUAL_CENTER),
    radius: 1.6,
    above: 0.6,
    omni: true,
    priority: 5,
    prompt: () => `Colocar ${cat.carrying!.name} no círculo`,
    enabled: () => !!cat.carrying && (CLUES as string[]).includes(cat.carrying.id) && (g.day === LAST_NIGHT),
    onInteract: () => {
      const c = cat.carrying!;
      const id = c.id as ClueId;
      cat.carrying = null;
      c.carried = false;
      const n = CLUES.filter((k) => g.flags.clues[k]?.onCircle).length;
      const slot = ritualSlot(n);
      c.place(slot.clone().setY(slot.y + 0.005), Math.random() * 6);
      g.flags.clues[id] = { x: slot.x, y: slot.y, z: slot.z, onCircle: true };
      g.audio.bell(slot, 1, 0.25);
      g.onRitualItem();
    },
  });
  inter.add({
    id: 'ritual_do',
    pos: V(...RITUAL_CENTER),
    radius: 1.3,
    above: 0.6,
    omni: true,
    priority: 6,
    prompt: () => (g.director.thing.stage >= 2 ? 'Completar o ritual' : 'O círculo está pronto... algo ainda dorme'),
    enabled: () => g.day === LAST_NIGHT && !cat.carrying && CLUES.every((k) => g.flags.clues[k]?.onCircle) && night(),
    hold: () => (g.director.thing.stage >= 2 ? 4 : 0),
    pose: 'busy',
    holdLabel: () => 'O círculo responde...',
    onInteract: () => {
      if (g.director.thing.stage >= 2) g.completeRitual();
    },
  });

  /* ---------------------------------------------------------- duct */
  const ductEnds = [V(10.95, -3, 0.45), V(10.8, 0, 3.95)];
  ductEnds.forEach((p, i) => {
    inter.add({
      id: `duct_${i}`,
      pos: p,
      radius: 0.75,
      above: 0.6,
      below: 0.5,
      omni: true,
      priority: 2,
      prompt: () => (h.ductTarget > 0.5 ? (i === 0 ? 'Entrar no duto (para a cozinha)' : 'Entrar no duto (para a lavanderia)') : 'Abrir a grade do duto'),
      enabled: () => !cat.carrying || h.ductTarget > 0.5,
      hold: () => (h.ductTarget > 0.5 ? 0 : 1.2),
      pose: 'scratch',
      onInteract: () => {
        if (h.ductTarget < 0.5) {
          h.setDuct(true);
          g.flags.ductOpen = true;
          g.audio.creak(p.clone().setY(p.y + 0.2), 0.3, 0.6, 2.4);
          g.audio.thud(p, 0.2, 160);
          g.onTask('duct');
          return;
        }
        const other = ductEnds[1 - i];
        g.passage(other.clone().add(i === 0 ? V(0, 0, 0.25) : V(0, 0, -0.3)), i === 0 ? Math.PI : 0, 'duct');
      },
    });
  });

  /* ---------------------------------------------------------- basculante */
  inter.add({
    id: 'basculante_in',
    pos: V(10.4, 3.9, 6.3),
    radius: 0.7,
    above: 1.0,
    below: 0.3,
    omni: true,
    priority: 2,
    prompt: () => (h.basculanteTarget > 0.5 ? 'Passar pela janela (varanda)' : 'Abrir a janela basculante'),
    enabled: () => true,
    hold: () => (h.basculanteTarget > 0.5 ? 0 : 1.4),
    pose: 'scratch',
    onInteract: () => {
      if (h.basculanteTarget < 0.5) {
        h.setBasculante(true);
        g.flags.basculanteOpen = true;
        g.audio.creak(V(10.4, 5.0, 6.0), 0.35, 0.8, 1.8);
        g.onTask('basculante');
        return;
      }
      g.passage(V(10.4, 3, 5.4), Math.PI, 'window');
    },
  });
  inter.add({
    id: 'basculante_out',
    pos: V(10.4, 3, 5.55),
    radius: 0.7,
    above: 1.8,
    below: 0.3,
    omni: true,
    priority: 2,
    prompt: () => 'Pular pela janela (banheiro)',
    enabled: () => h.basculanteTarget > 0.5,
    onInteract: () => g.passage(V(10.4, 3.9, 6.32), 0, 'window'),
  });

  /* ---------------------------------------------------------- attic cord */
  inter.add({
    id: 'cord',
    pos: V(6.85, 3, 2.1),
    radius: 0.7,
    above: 1.6,
    below: 0.3,
    omni: true,
    priority: 2,
    prompt: () => 'Puxar o cordão do sótão',
    enabled: () => h.hatchTarget < 0.5,
    hold: 0.8,
    pose: 'scratch',
    onInteract: () => {
      h.setHatch(true);
      g.flags.hatchOpen = true;
      g.audio.creak(V(6.85, 5.6, 1.6), 0.55, 1.6, 0.9);
      setTimeout(() => g.audio.thud(V(6.85, 3.2, 2.4), 0.6, 60), 1300);
      g.emitNoise(V(6.85, 3.2, 2.4), 0.4, 'thud');
      g.onTask('hatch');
    },
  });

  /* ---------------------------------------------------------- cat bed (skip time) */
  inter.add({
    id: 'catbed',
    pos: h.catBed.clone(),
    radius: 0.7,
    above: 0.5,
    omni: true,
    prompt: () => (g.phase === 'morning' ? 'Dormir até Clara chegar' : 'Cochilar até a hora de dormir'),
    enabled: () => (g.phase === 'morning' || (g.phase === 'afternoon' && g.aft.canSkip)) && !cat.carrying,
    hold: 1.0,
    pose: 'busy',
    onInteract: () => g.skipPhase(),
  });

  /* ---------------------------------------------------------- Clara */
  // lie down next to whoever is in bed (Clara upstairs front, Davi in the guest room)
  for (const who of [g.owner, g.davi]) {
    inter.add({
      id: `purr_${who.cfg.id}`,
      pos: V(1.6, 3, who.cfg.bedSpot.p[2]),
      radius: 1.6,
      above: 0.8,
      below: 0.4,
      omni: true,
      priority: 4,
      prompt: () => (cat.mode === 'purr' ? 'Levantar' : who.paralysis ? `Deitar no rosto de ${who.name} (acordar)` : `Deitar com ${who.name} e ronronar`),
      enabled: () => night() && who.present && who.inBed && !cat.carrying,
      onInteract: () => g.togglePurr(who),
    });
  }
  // hiding places against the hound
  for (const spot of HIDE_SPOTS) {
    inter.add({
      id: `hide_${spot.id}`,
      pos: V(spot.p[0], spot.p[1], spot.p[2]),
      radius: 0.95,
      above: 0.6,
      below: 0.5,
      omni: true,
      priority: 1,
      prompt: () => `Esconder-se (${spot.name})`,
      enabled: () => night() && cat.mode === 'free',
      onInteract: () => g.hideAt(spot),
    });
  }
  inter.add({
    id: 'pet',
    pos: g.owner.pos,
    radius: 1.1,
    above: 1.2,
    below: 0.6,
    omni: true,
    priority: 4,
    prompt: () => 'Pedir carinho',
    enabled: () => g.phase === 'afternoon' && g.aft.pets < 3 && g.aft.petCd <= 0 && !g.owner.busy && !cat.carrying,
    onInteract: () => g.petOwner(),
  });
  inter.add({
    id: 'toy',
    pos: g.owner.pos,
    radius: 1.3,
    above: 1.2,
    below: 0.6,
    omni: true,
    priority: 5,
    prompt: () => 'Levar o ratinho para Clara',
    enabled: () => g.phase === 'afternoon' && cat.carrying?.id === 'toy' && !g.aft.played,
    onInteract: () => g.playWithOwner(),
  });
  inter.add({
    id: 'eat',
    pos: V(8.6, 0, 3.9),
    radius: 0.6,
    above: 0.5,
    omni: true,
    priority: 3,
    prompt: () => 'Comer',
    enabled: () => g.phase === 'afternoon' && g.aft.bowlFilled && !g.aft.fed && !cat.carrying,
    hold: 1.5,
    pose: 'busy',
    onInteract: () => g.eat(),
  });
  inter.add({
    id: 'bath',
    pos: V(10.6, 3, 8.75),
    radius: 1.3,
    above: 0.8,
    omni: true,
    priority: 5,
    prompt: () => 'Arranhar a banheira',
    enabled: () => g.phase === 'afternoon' && g.aft.scene === 'bath' && g.aft.bathing,
    hold: 1.2,
    pose: 'scratch',
    onInteract: () => g.endBath(true),
  });

  /* ---------------------------------------------------------- marks / misc flavor */
  void SPOTS;
  void choose;
  void (null as unknown as RoomId);
}
