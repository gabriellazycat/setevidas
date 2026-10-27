import * as THREE from 'three';
import { OwnerModel, type PoseName, type OwnerLook, CLARA_LOOK, DAVI_LOOK } from './OwnerModel';
import type { NavGraph } from '../world/NavGraph';
import type { Door } from '../world/Doors';
import { SPOTS, type Spot, type RoomId } from '../world/Layout';
import { clamp, damp, dampAngle, rand, choose } from '../core/math';

export type Step =
  | { t: 'walk'; node: string; end?: THREE.Vector3; style?: 'normal' | 'hypno' | 'hurry' }
  | { t: 'spot'; spot: Spot; style?: 'normal' | 'hypno' | 'hurry' }
  | { t: 'pose'; pose: PoseName; dur?: number }
  | { t: 'wait'; dur: number }
  | { t: 'say'; text: string; dur?: number; kind?: SayKind }
  | { t: 'do'; fn: () => void }
  | { t: 'until'; cond: () => boolean; timeout?: number; pose?: PoseName }
  | { t: 'face'; yaw: number }
  | { t: 'bed' };

export type SayKind = 'normal' | 'call' | 'whisper' | 'scared' | 'annoyed' | 'read';

interface Task {
  name: string;
  steps: Step[];
  idx: number;
  timer: number;
  priority: number;
  onDone?: () => void;
  stepStarted: boolean;
}

export interface OwnerEvents {
  say?: (text: string, dur: number, kind: SayKind, who: Owner) => void;
  step?: (pos: THREE.Vector3) => void;
  door?: (d: Door) => void;
  lamp?: (who: Owner) => void;
}

export interface OwnerConfig {
  id: 'clara' | 'davi';
  name: string;
  look: OwnerLook;
  /** the sceptic goes to look into noises instead of hiding under the covers */
  skeptic: boolean;
  /** how much of a scare turns into fear */
  fearScale: number;
  bedSpot: Spot;
  bedsideSpot: Spot;
  bedRoom: RoomId;
  bedNode: string;
  /** where a ghost looms over the sleeper / sits on the bed */
  bedSide: [number, number, number];
  bedTop: [number, number, number];
  /** where the cat lies down to purr */
  purrPos: [number, number, number];
  purrYaw: number;
  lampIndex: number;
  voicePitch: number;
}

export const CLARA_CONFIG: OwnerConfig = {
  id: 'clara',
  name: 'Clara',
  look: CLARA_LOOK,
  skeptic: false,
  fearScale: 1,
  bedSpot: SPOTS.bed,
  bedsideSpot: SPOTS.bedside,
  bedRoom: 'quarto',
  bedNode: 'f_quarto_bed',
  bedSide: [1.6, 3, 1.4],
  bedTop: [1.55, 3.49, 2.15],
  purrPos: [0.95, 3.55, 2.35],
  purrYaw: -Math.PI / 2,
  lampIndex: 8,
  voicePitch: 1,
};

export const DAVI_CONFIG: OwnerConfig = {
  id: 'davi',
  name: 'Davi',
  look: DAVI_LOOK,
  skeptic: true,
  fearScale: 0.7,
  bedSpot: SPOTS.davBed,
  bedsideSpot: SPOTS.davBedside,
  bedRoom: 'hospedes',
  bedNode: 'f_hosp_bed',
  bedSide: [1.5, 3, 7.3],
  bedTop: [1.55, 3.49, 7.95],
  purrPos: [0.95, 3.55, 7.95],
  purrYaw: -Math.PI / 2,
  lampIndex: 17,
  voicePitch: 0.62,
};

export class Owner {
  model: OwnerModel;
  name: string;
  /** set while the person is part of the household this night */
  present = true;
  /** the cat's meow pulled this person out of bed to come and see */
  following = false;
  pos = new THREE.Vector3();
  yaw = 0;
  fear = 0;
  patience = 70;
  inBed = false;
  asleep = false;
  task: Task | null = null;
  events: OwnerEvents = {};
  purring = false;
  paralysis = false;
  hypno = false;
  catName = 'Mingau';
  /** fear added this frame by threats (for decay logic) */
  private fearFeed = 0;
  private sinceFear = 99;
  private path: THREE.Vector3[] = [];
  private pathI = 0;
  private style: 'normal' | 'hypno' | 'hurry' = 'normal';
  private stepAcc = 0;
  private callT = 6;
  private noiseCd = 0;
  private lampDone = false;
  private sayCd = 0;
  night = true;
  paused = false;
  /** while set, the owner reacts to nothing (cutscenes) */
  scripted = false;

  constructor(
    scene: THREE.Object3D,
    private nav: NavGraph,
    private doors: Door[],
    public cfg: OwnerConfig = CLARA_CONFIG,
  ) {
    this.model = new OwnerModel(cfg.look);
    this.name = cfg.name;
    scene.add(this.model.root);
  }

  setNight(night: boolean) {
    this.night = night;
    this.model.setOutfit(night ? this.cfg.look.night : this.cfg.look.day);
  }

  place(spot: Spot) {
    this.pos.set(...spot.p);
    this.yaw = spot.yaw;
    this.sync();
  }

  putInBed(asleep = true) {
    this.place(this.cfg.bedSpot);
    this.inBed = true;
    this.asleep = asleep;
    this.model.snapPose('lie');
    this.task = null;
    this.path = [];
    this.lampDone = false;
  }

  hide() {
    this.model.root.visible = false;
  }
  show() {
    this.model.root.visible = true;
  }

  get busy() {
    return !!this.task;
  }
  get taskName() {
    return this.task?.name ?? '';
  }

  headPos(out = new THREE.Vector3()) {
    return this.model.head.getWorldPosition(out);
  }

  addFear(v: number) {
    if (v > 0) v *= this.cfg.fearScale;
    if (v > 0) {
      this.fearFeed += v;
      this.sinceFear = 0;
    }
    this.fear = clamp(this.fear + v, 0, 100);
  }

  addPatience(v: number) {
    this.patience = clamp(this.patience + v, 0, 100);
  }

  say(text: string, dur = 3, kind: SayKind = 'normal') {
    this.events.say?.(text.replace(/\{cat\}/g, this.catName), dur, kind, this);
  }

  /** Run a task if its priority is at least the current one's. */
  run(name: string, steps: Step[], priority = 1, onDone?: () => void) {
    if (this.task && this.task.priority > priority) return false;
    this.task = { name, steps, idx: 0, timer: 0, priority, onDone, stepStarted: false };
    this.path = [];
    this.inBed = false;
    this.asleep = false;
    this.paralysis = false;
    return true;
  }

  abort() {
    this.task = null;
    this.path = [];
    this.hypno = false;
    this.model.style = 'normal';
  }

  goToBed(priority = 0, say?: string) {
    const steps: Step[] = [];
    if (say) steps.push({ t: 'say', text: say, dur: 2.6 });
    steps.push({ t: 'spot', spot: this.cfg.bedsideSpot }, { t: 'bed' });
    this.run('bed', steps, priority);
  }

  /**
   * The cat meowed nearby.
   * 'coming' = the person gets up and walks to the cat (a meow is a call).
   */
  hearMeow(catPos: THREE.Vector3, hops: number): 'none' | 'trance' | 'woke' | 'paused' | 'coming' {
    if (this.scripted || !this.present) return 'none';
    const d = catPos.distanceTo(this.pos) + hops * 3;
    if (d > 18) return 'none';
    if (this.hypno) {
      this.hypno = false;
      this.model.style = 'normal';
      this.addPatience(-3);
      this.say(choose(['Hã...? O que eu tô fazendo aqui...?', 'Ai... {cat}? Eu tava sonâmbulo?', 'Que frio... como eu vim parar aqui?']), 3.2, 'whisper');
      this.goToBed(2);
      return 'trance';
    }
    if (this.paralysis) return 'none';
    const sk = this.cfg.skeptic;
    let result: 'woke' | 'coming' | 'none' = 'none';
    if (this.asleep && this.inBed) {
      if (d > 9) return 'none';
      this.addPatience(this.fear > 50 ? 0 : sk ? -6 : -4);
      this.asleep = false;
      this.wakeT = 3.5;
      if (this.fear < 50) this.say(choose(sk ? ['Ô, gato... são três da manhã.', 'Shh. Dorme, bicho.', 'Cara, de novo?'] : ['{cat}... dorme, gato.', 'Hmm... {cat}, são três da manhã...', 'Shhh... {cat}...']), 2.6, 'annoyed');
      else this.say(choose(['{cat}? Você também ouviu?', 'Tá aí, {cat}? Fica aqui comigo.']), 2.6, 'scared');
      result = 'woke';
    }
    if (this.task && this.task.name === 'visitor') {
      this.pauseT = 4;
      this.say('{cat}? O que foi?', 2, 'call');
      return 'paused';
    }
    // a deliberate meow pulls the person out of bed to see what the cat wants
    if ((this.inBed || !this.task) && this.fear < 68 && d < 14) {
      const delay = this.inBed ? 2.4 : 0.2;
      this.addPatience(-2);
      this.following = true;
      setTimeout(() => {
        if (!this.following || this.paralysis || this.hypno) return;
        this.comeTo(catPos.clone());
      }, delay * 1000);
      return result === 'none' ? 'coming' : 'woke';
    }
    return result;
  }

  /** walk to the cat, look around, then go back to bed */
  comeTo(target: THREE.Vector3) {
    if (this.task && this.task.priority >= 3) {
      this.following = false;
      return;
    }
    const near = this.nav.nearest(target);
    const sk = this.cfg.skeptic;
    this.run(
      'follow',
      [
        { t: 'say', text: choose(sk ? ['Tô indo, tô indo.', 'O que foi agora?'] : ['Já vou, {cat}!', 'Tô indo, {cat}...']), dur: 2, kind: 'call' },
        { t: 'walk', node: near.id, style: 'hurry' },
        { t: 'wait', dur: 3.2 },
        { t: 'say', text: choose(['Tá tudo bem aqui... acho.', 'Nada. Você me enganou, {cat}.', 'O que você queria me mostrar?']), dur: 2.4, kind: 'whisper' },
        { t: 'do', fn: () => (this.following = false) },
        { t: 'spot', spot: this.cfg.bedsideSpot },
        { t: 'bed' },
      ],
      2,
      () => (this.following = false),
    );
  }

  /** Something fell / broke / scratched. */
  hearNoise(p: THREE.Vector3, loudness: number, hops: number, kind: string) {
    if (this.scripted || !this.present || this.noiseCd > 0) return;
    const d = p.distanceTo(this.pos) + hops * 2.5;
    const eff = loudness * clamp(1 - d / 16);
    if (eff < 0.12) return;
    this.noiseCd = 5;
    const cost = kind === 'break' ? 10 : kind === 'scratch' ? 3 : 5;
    const sk = this.cfg.skeptic;
    if (this.asleep || this.inBed) {
      this.asleep = false;
      this.wakeT = 4;
      this.addPatience(-cost * clamp(eff * 1.5, 0.4, 1) * (sk ? 1.3 : 1));
      if (this.fear > 55) this.say(choose(['O que foi isso?!', 'Tem alguém aí?']), 2.4, 'scared');
      else if (sk) this.say(choose(['Hm? ...Gato idiota.', 'Que barulho foi esse? Vou ver.']), 2.6, 'annoyed');
      else this.say(choose(['{cat}! O que você derrubou?', 'Sério, {cat}?', 'Mas que barulho é esse...']), 2.6, 'annoyed');
      // the sceptic checks it out himself
      if (sk && this.fear < 45 && !this.task) {
        const near = this.nav.nearest(p);
        this.run(
          'investigate',
          [
            { t: 'wait', dur: 1.5 },
            { t: 'walk', node: near.id },
            { t: 'wait', dur: 2.5 },
            { t: 'say', text: choose(['Ninguém. Só o gato aprontando.', 'Nada aqui... estranho.']), dur: 2.4, kind: 'whisper' },
            { t: 'spot', spot: this.cfg.bedsideSpot },
            { t: 'bed' },
          ],
          2,
        );
      }
    } else {
      this.addPatience(-cost * 0.5 * clamp(eff * 1.5, 0.4, 1));
      if (kind === 'break') this.say(choose(['{cat}!! Era meu copo!', 'Ah não... {cat}!']), 2.4, 'annoyed');
    }
  }

  private wakeT = 0;
  private pauseT = 0;

  private nextStep() {
    if (!this.task) return;
    this.task.idx++;
    this.task.timer = 0;
    this.task.stepStarted = false;
    this.path = [];
    if (this.task.idx >= this.task.steps.length) {
      const done = this.task.onDone;
      this.task = null;
      done?.();
    }
  }

  private startPath(nodeId: string, end?: THREE.Vector3) {
    this.path = this.nav.pathTo(this.pos, nodeId, end);
    this.pathI = 0;
  }

  update(dt: number) {
    this.noiseCd -= dt;
    this.sayCd -= dt;
    this.sinceFear += dt;
    const fearFed = this.fearFeed;
    this.fearFeed = 0;
    void fearFed;

    // fear decay
    if (this.purring) this.fear = Math.max(0, this.fear - 7 * dt);
    else if (this.sinceFear > 2.5) this.fear = Math.max(0, this.fear - (this.inBed ? 1.4 : 0.9) * dt);
    if (this.asleep && this.fear < 25) this.patience = Math.min(100, this.patience + 0.05 * dt);

    let speed = 0;
    if (this.paused) {
      this.model.speed = 0;
      this.model.update(dt);
      this.sync();
      return;
    }
    if (this.pauseT > 0) {
      this.pauseT -= dt;
      this.model.pose = 'stand';
      this.model.speed = 0;
      this.model.update(dt);
      this.sync();
      return;
    }

    const t = this.task;
    if (t) {
      const st = t.steps[t.idx];
      t.timer += dt;
      switch (st.t) {
        case 'walk':
        case 'spot': {
          if (!t.stepStarted) {
            t.stepStarted = true;
            this.style = st.style ?? 'normal';
            this.hypno = this.style === 'hypno';
            this.model.style = this.style;
            if (st.t === 'walk') this.startPath(st.node, st.end);
            else this.startPath(st.spot.node, new THREE.Vector3(...st.spot.p));
            this.model.pose = 'stand';
          }
          const sp = this.style === 'hurry' ? 1.75 : this.style === 'hypno' ? 0.62 : 1.2;
          const target = this.path[this.pathI];
          if (!target) {
            if (st.t === 'spot') this.yaw = dampAngle(this.yaw, st.spot.yaw, 10, dt);
            this.nextStep();
            break;
          }
          const dx = target.x - this.pos.x;
          const dz = target.z - this.pos.z;
          const dist = Math.hypot(dx, dz);
          if (dist < 0.08 && Math.abs(target.y - this.pos.y) < 0.2) {
            this.pos.y = target.y;
            this.pathI++;
            if (this.pathI >= this.path.length && st.t === 'spot') {
              this.pos.set(...st.spot.p);
            }
            break;
          }
          const step = Math.min(dist, sp * dt);
          const prevX = this.pos.x;
          const prevZ = this.pos.z;
          this.pos.x += (dx / Math.max(dist, 1e-5)) * step;
          this.pos.z += (dz / Math.max(dist, 1e-5)) * step;
          // y follows the segment linearly (stairs)
          const prev = this.pathI > 0 ? this.path[this.pathI - 1] : null;
          if (prev) {
            const segLen = Math.hypot(target.x - prev.x, target.z - prev.z);
            const done = segLen > 1e-4 ? 1 - Math.hypot(target.x - this.pos.x, target.z - this.pos.z) / segLen : 1;
            this.pos.y = prev.y + (target.y - prev.y) * clamp(done);
          } else this.pos.y = damp(this.pos.y, target.y, 6, dt);
          if (dist > 0.05) this.yaw = dampAngle(this.yaw, Math.atan2(dx, dz), 9, dt);
          speed = Math.hypot(this.pos.x - prevX, this.pos.z - prevZ) / Math.max(dt, 1e-4);
          this.stepAcc += step;
          if (this.stepAcc > 0.62) {
            this.stepAcc = 0;
            this.events.step?.(this.pos);
          }
          this.openDoorsAhead();
          break;
        }
        case 'pose':
          this.model.pose = st.pose;
          if (!st.dur || t.timer >= st.dur) this.nextStep();
          break;
        case 'wait':
          if (t.timer >= st.dur) this.nextStep();
          break;
        case 'say':
          this.say(st.text, st.dur ?? 3, st.kind ?? 'normal');
          this.nextStep();
          break;
        case 'do':
          st.fn();
          this.nextStep();
          break;
        case 'until':
          if (st.pose) this.model.pose = st.pose;
          if (st.cond() || (st.timeout && t.timer >= st.timeout)) this.nextStep();
          break;
        case 'face':
          this.yaw = dampAngle(this.yaw, st.yaw, 8, dt);
          if (t.timer > 0.5) this.nextStep();
          break;
        case 'bed':
          this.putInBed(true);
          this.nextStep();
          break;
      }
    } else if (this.inBed) {
      this.bedBehaviour(dt);
    }
    if (!this.task || (this.task && this.task.steps[this.task.idx]?.t !== 'walk' && this.task.steps[this.task.idx]?.t !== 'spot')) {
      this.hypno = this.task ? this.hypno : false;
    }
    this.model.speed = speed;
    this.model.tremble = this.fear > 60 && this.inBed ? (this.fear - 60) / 40 : 0;
    this.model.eyesWide = clamp((this.fear - 40) / 50) + (this.paralysis ? 1 : 0);
    this.model.update(dt);
    this.sync();
  }

  private bedBehaviour(dt: number) {
    const m = this.model;
    this.wakeT -= dt;
    if (this.paralysis) {
      m.pose = 'paralysis';
      this.asleep = false;
      return;
    }
    const f = this.fear;
    if (f < 32 && !this.purring) {
      m.pose = this.wakeT > 0 ? 'sitUp' : 'lie';
      if (this.wakeT <= 0) this.asleep = true;
    } else if (f < 58) {
      m.pose = this.wakeT > 0 || this.purring ? 'sitUp' : 'lie';
      this.asleep = false;
      if (!this.lampDone && f > 38) {
        this.lampDone = true;
        this.events.lamp?.(this);
      }
    } else if (f < 82) {
      m.pose = this.purring ? 'sitUp' : 'hug';
      this.asleep = false;
      this.callT -= dt;
      if (this.callT < 0) {
        this.callT = rand(9, 14);
        this.say(choose(this.cfg.skeptic ? ['Gato? ...Isso aí não tá certo.', 'Tem alguma coisa aqui, não tem?', 'Ô, {cat}... vem pra cá.'] : ['{cat}? Cadê você?', '{cat}... vem cá...', 'Tem alguém aí?', '{cat}? Você tá vendo isso?']), 2.8, 'call');
      }
    } else {
      m.pose = 'cry';
      this.asleep = false;
      this.callT -= dt;
      if (this.callT < 0) {
        this.callT = rand(7, 11);
        this.say(choose(['Por favor... por favor...', 'Vai embora... vai embora...', '{cat}... me ajuda...', 'Isso não é real...']), 3, 'scared');
      }
    }
    if (this.purring && f < 32) m.pose = 'lie';
  }

  private openDoorsAhead() {
    const fx = Math.sin(this.yaw);
    const fz = Math.cos(this.yaw);
    for (const d of this.doors) {
      if (d.def.style === 'front') continue;
      const c = d.center(new THREE.Vector3());
      if (Math.abs(c.y - this.pos.y) > 1.2) continue;
      const dx = c.x - this.pos.x;
      const dz = c.z - this.pos.z;
      const dist = Math.hypot(dx, dz);
      if (dist < 1.3 && (dx * fx + dz * fz) > -0.2 && d.state !== 'open' && !d.locked) {
        d.setState('open');
        this.events.door?.(d);
      }
    }
  }

  private sync() {
    this.model.root.position.copy(this.pos);
    this.model.root.rotation.y = this.yaw;
  }

  setDayLook() {
    this.setNight(false);
  }
}
