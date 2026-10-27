import * as THREE from 'three';
import { Threat, Wisps } from './Threat';
import type { World } from '../game/World';
import type { Device } from '../world/House';
import type { LoopHandle } from '../audio/Audio';
import { SPOTS } from '../world/Layout';
import { choose, rand, damp } from '../core/math';
import { ROOMS } from '../world/Layout';
import { spectralMat } from '../render/Materials';

const DEVICE_SPOT: Record<Device['id'], keyof typeof SPOTS> = { tv: 'tv', radio: 'radio', laptop: 'laptop' };

/**
 * O Sussurrador — lives in the wires. A device switches itself on, whispers,
 * and Clara sleepwalks to it. Pull the plug to silence it.
 */
export class Whisperer extends Threat {
  readonly id = 'whisperer' as const;
  readonly name = 'O Sussurrador';
  dev: Device | null = null;
  private whisper: LoopHandle | null = null;
  private stat: LoopHandle | null = null;
  private wisps: Wisps;
  private face: THREE.Mesh;
  private replug: Map<Device, number> = new Map();
  private ownerSent = false;
  private hops = 0;
  private decoyT = 6;
  private decoyPos: THREE.Vector3 | null = null;
  private decoyUntil = 0;

  constructor(w: World) {
    super(w);
    this.wisps = new Wisps(w.scene, 30, '#5ff6ff', 0.12, 0.25, true);
    this.wisps.opacity = 0;
    const m = spectralMat({ color: '#0a0f12', rim: '#9fd8ff', alpha: 0.0, noise: 0.35, vision: '#5ff6ff' });
    this.face = new THREE.Mesh(new THREE.SphereGeometry(0.22, 14, 10), m);
    this.face.scale.set(0.8, 1.1, 0.4);
    this.face.visible = false;
    w.scene.add(this.face);
  }

  reset() {
    this.stage = 0;
    this.t = 0;
    if (this.dev) this.dev.glow = 0;
    this.dev = null;
    this.whisper?.stop(0.5);
    this.stat?.stop(0.5);
    this.whisper = this.stat = null;
    this.wisps.opacity = 0;
    this.face.visible = false;
    this.ownerSent = false;
    this.hops = 0;
    this.decoyPos = null;
    this.decoyUntil = 0;
    const sl = this.w.house.lights.get(14);
    sl.setOn(false);
    if (this.target.taskName === 'whisper') this.target.abort();
  }

  /** full reset for a new night: replug everything */
  replugAll() {
    for (const d of this.w.house.devices) this.w.house.setPlugged(d, true);
    this.replug.clear();
  }

  protected onStage(s: number) {
    const w = this.w;
    if (s === 1) {
      const plugged = w.house.devices.filter((d) => d.plugged);
      if (!plugged.length) {
        this.stage = 0;
        this.cooldown = 8;
        return;
      }
      this.dev = choose(plugged);
      this.hops = 0;
      this.decoyT = 4;
      this.whisper = w.audio.loop('whisper', this.dev.pos, { ref: 1.2, gain: 0.9 });
      this.whisper.setLevel(0.25);
    }
    if (s === 2 && this.dev) this.lightUp(this.dev, 0.45, 0.6);
    if (s === 3 && this.dev) this.sendOwner();
    if (s === 5 && this.dev) {
      w.fx.sting(0.45);
      w.audio.shriek(this.dev.pos, 0.3);
    }
  }

  /** the screen / dial glows and the voice gets louder */
  private lightUp(dev: Device, staticLevel: number, whisperLevel: number) {
    const w = this.w;
    this.stat?.stop(0.2);
    this.stat = w.audio.loop('static', dev.pos, { ref: 1.3, gain: 0.8 });
    this.stat.setLevel(staticLevel);
    this.whisper?.setLevel(whisperLevel);
    w.audio.click(dev.pos, 0.5);
    const sl = w.house.lights.get(14);
    sl.light.position.copy(dev.pos).add(new THREE.Vector3(0, 0.1, dev.id === 'radio' ? 0 : -0.5));
    if (dev.id === 'radio') sl.light.position.x -= 0.5;
    sl.light.color.set(dev.id === 'radio' ? '#ffb36b' : '#9fc8ff');
    sl.baseColor.copy(sl.light.color);
    w.house.lights.setRoomMask(14, dev.room);
    sl.setOn(true);
    sl.flicker = 0.35;
  }

  /** the plug was pulled but it jumps into another appliance, keeping its progress */
  private hopTo(next: Device) {
    const w = this.w;
    const old = this.dev!;
    old.glow = 0;
    w.audio.shriek(old.pos, 0.3);
    w.audio.click(old.pos, 0.6);
    this.replug.set(old, this.d(rand(70, 100)));
    this.hops++;
    this.dev = next;
    this.whisper?.stop(0.2);
    this.whisper = w.audio.loop('whisper', next.pos, { ref: 1.2, gain: 0.9 });
    this.lightUp(next, 0.6, 0.7);
    w.audio.shriek(next.pos, 0.2);
    w.fx.shake(0.25);
    w.hint(`Ele pulou para ${next.name}!`, 3.2);
    if (this.stage >= 3) {
      if (this.target.taskName === 'whisper') this.target.abort();
      this.ownerSent = false;
      this.sendOwner();
    }
  }

  /** fake noises in other rooms: not everything you hear is true */
  private playDecoy() {
    const w = this.w;
    const rooms = [...ROOMS].filter((r) => r.id !== 'sotao' && r.id !== 'varanda' && r.id !== this.dev?.room);
    const room = choose(rooms);
    const pos = new THREE.Vector3((room.x0 + room.x1) / 2, room.y + 1.0, (room.z0 + room.z1) / 2);
    if (pos.distanceTo(w.cat.pos) < 4) return;
    const kind = Math.floor(Math.random() * 4);
    if (kind === 0) for (let i = 0; i < 4; i++) setTimeout(() => w.audio.humanStep(pos.clone().setY(room.y), false), i * 520);
    else if (kind === 1) w.audio.voice(pos, 8, 'call', 1.05);
    else if (kind === 2) w.audio.knock(pos, 3, 0.6);
    else w.audio.creak(pos, 0.5, 1.4, 1);
    this.decoyPos = pos;
    this.decoyUntil = 3.4;
    this.hintOnceDecoy();
  }

  private shownDecoyHint = false;
  private hintOnceDecoy() {
    if (this.shownDecoyHint) return;
    this.shownDecoyHint = true;
    this.w.hint('Nem todo som é de verdade. O Sussurrador imita a casa.', 4);
  }

  private sendOwner() {
    const w = this.w;
    if (!this.dev) return;
    const spot = SPOTS[DEVICE_SPOT[this.dev.id]];
    const ok = this.target.run(
      'whisper',
      [
        { t: 'say', text: '...', dur: 1 },
        { t: 'spot', spot, style: 'hypno' },
        { t: 'until', cond: () => this.stage === 0 || this.stage >= 3, pose: 'stare' },
        { t: 'until', cond: () => this.stage === 0, pose: 'stare' },
      ],
      3,
    );
    this.ownerSent = ok;
  }

  override update(dt: number) {
    const w = this.w;
    if (this.enabled) {
      // unplugged devices slowly plug themselves back in
      for (const [dev, tleft] of this.replug) {
        const nt = tleft - dt;
        if (nt <= 0) {
          this.replug.delete(dev);
          w.house.setPlugged(dev, true);
          w.audio.creak(dev.outlet, 0.15, 0.6, 2.5);
          w.audio.click(dev.outlet, 0.4);
        } else this.replug.set(dev, nt);
      }
    }
    super.update(dt);
  }

  protected tick(dt: number) {
    const w = this.w;
    const d = this.dev;
    if (!d) return;
    if (!d.plugged) {
      // the cat pulled the plug: it may jump to another appliance
      const others = w.house.devices.filter((x) => x.plugged && x !== d);
      const chance = 0.7 - this.hops * 0.28;
      if (this.stage >= 2 && others.length && Math.random() < chance) this.hopTo(choose(others));
      else this.banish();
      return;
    }
    if (this.decoyUntil > 0) this.decoyUntil -= dt;
    if (this.stage >= 1 && this.stage <= 3) {
      this.decoyT -= dt;
      if (this.decoyT <= 0) {
        this.decoyT = rand(7, 11) / Math.max(0.6, w.speed);
        this.playDecoy();
      }
    }
    const glowTarget = this.stage === 1 ? 0.12 + Math.random() * 0.15 : this.stage >= 2 ? 0.85 + Math.random() * 0.15 : 0;
    d.glow = damp(d.glow, glowTarget, 10, dt);
    this.wisps.opacity = (this.stage >= 1 ? 0.35 + this.stage * 0.08 : 0) * Math.max(0.15, w.cat.vision);
    this.wisps.update(dt, d.pos.clone().add(new THREE.Vector3(0, -0.2, 0)), 0.8);
    if (this.stage === 1 && this.t > this.d(8)) this.setStage(2);
    else if (this.stage === 2 && this.t > this.d(9)) {
      if (this.mayAttack || this.target.inBed) this.setStage(3);
    } else if (this.stage === 3) {
      if (!this.ownerSent || this.target.taskName !== 'whisper') {
        // trance broken (meow) – try again after a while
        if (this.t > this.d(9)) {
          this.t = 0;
          this.sendOwner();
        }
      } else {
        const spot = SPOTS[DEVICE_SPOT[d.id]];
        const sp = new THREE.Vector3(...spot.p);
        if (this.target.pos.distanceTo(sp) < 0.25 && this.mayAttack) this.setStage(4);
      }
      this.stat?.setLevel(0.6);
      this.target.addFear(0.4 * dt);
    } else if (this.stage === 4) {
      this.target.addFear(6 * dt);
      if (this.target.taskName !== 'whisper') this.setStage(3);
      else if (this.t > this.d(7)) this.setStage(5);
    } else if (this.stage === 5) {
      this.target.addFear(9 * dt);
      if (this.target.taskName !== 'whisper') this.setStage(3);
      this.face.visible = true;
      const fm = this.face.material as THREE.ShaderMaterial;
      fm.uniforms.uAlpha.value = 0.6 + Math.sin(performance.now() * 0.01) * 0.2;
      this.face.position.copy(d.pos).add(new THREE.Vector3(0, 0.05, d.id === 'radio' ? 0 : -0.3));
      if (d.id === 'radio') this.face.position.x -= 0.25;
    }
  }

  private banish() {
    const w = this.w;
    const d = this.dev!;
    w.audio.shriek(d.pos, 0.35);
    w.audio.click(d.pos, 0.6);
    d.glow = 0;
    this.replug.set(d, this.d(rand(70, 100)));
    const wasHypno = this.target.taskName === 'whisper';
    this.repel();
    if (wasHypno) {
      this.target.addFear(5);
      this.target.say(choose(['O que eu tô fazendo aqui...?', 'Ai... eu tava sonhando com uma voz...', '{cat}? Por que a TV... deixa pra lá.']), 3, 'whisper');
      this.target.goToBed(2);
    }
  }

  canHiss(p: THREE.Vector3) {
    return !!this.dev && this.stage >= 1 && p.distanceTo(this.dev.pos) < 2.2;
  }

  describeDeath() {
    return {
      title: `${this.target.name} foi levado(a) pelo Sussurrador`,
      why: `O Sussurrador chamou ${this.target.name} até ${this.dev ? this.dev.name : 'um aparelho'} e não largou mais.`,
      tip: 'Puxe o fio da tomada do aparelho que acendeu. Ele pode pular para outro aparelho: continue de olho. Sons falsos em outros cômodos são isca; as orelhas do gato também podem enganar.',
    };
  }

  onHiss(p: THREE.Vector3, strong: boolean) {
    if (!this.dev || this.stage < 1 || !strong) return false;
    if (p.distanceTo(this.dev.pos) > 2.2) return false;
    this.stall = this.d(6);
    this.w.audio.shriek(this.dev.pos, 0.2);
    return true;
  }

  focus() {
    if (!this.dev || this.stage === 0) return null;
    // the ears sometimes lie: while a decoy sounds they point at it
    if (this.decoyUntil > 0 && this.decoyPos) return this.decoyPos;
    return this.dev.pos;
  }
  entity() {
    return this.dev && this.stage >= 2 ? this.dev.pos : null;
  }
  get activeDevice() {
    return this.stage > 0 ? this.dev : null;
  }
}
