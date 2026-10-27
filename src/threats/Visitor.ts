import * as THREE from 'three';
import { Threat, makeSilhouette } from './Threat';
import type { World } from '../game/World';
import { SPOTS, type Spot } from '../world/Layout';
import { choose, damp } from '../core/math';

interface Entrance {
  id: string;
  name: string;
  spot: Spot;
  /** where the knocking comes from (outside) */
  knock: THREE.Vector3;
  /** where the figure stands outside */
  figure: THREE.Vector3;
  yaw: number;
  door?: string;
}

/**
 * O Visitante — knocks at night with a familiar voice. Clara goes to open.
 * Get there first and hiss at the door (cat vision shows it is not human).
 */
export class Visitor extends Threat {
  readonly id = 'visitor' as const;
  readonly name = 'O Visitante';
  entrances: Entrance[];
  cur: Entrance | null = null;
  private fig: THREE.Group;
  private vis = 0;
  private knockT = 0;
  private hissed = 0;
  private hissT = 0;

  constructor(w: World) {
    super(w);
    this.entrances = [
      { id: 'front', name: 'a porta da frente', spot: SPOTS.frontDoor, knock: new THREE.Vector3(6.45, 1.2, -0.05), figure: new THREE.Vector3(6.45, 0, -0.75), yaw: 0, door: 'd_front' },
      { id: 'sala', name: 'a janela da sala', spot: SPOTS.salaWindow, knock: new THREE.Vector3(-0.05, 1.5, 2.75), figure: new THREE.Vector3(-0.8, -0.9, 2.75), yaw: Math.PI / 2 },
      { id: 'coz', name: 'a janela da cozinha', spot: SPOTS.kitchenWindow, knock: new THREE.Vector3(8.3, 1.6, 10.05), figure: new THREE.Vector3(8.3, -0.9, 10.8), yaw: Math.PI },
    ];
    this.fig = makeSilhouette(2.3, { color: '#030304', rim: '#2a2f38', alpha: 0.95, noise: 0.15 });
    this.fig.visible = false;
    w.scene.add(this.fig);
  }

  reset() {
    this.stage = 0;
    this.t = 0;
    this.cur = null;
    this.hissed = 0;
    this.fig.visible = false;
    this.vis = 0;
    if (this.target.taskName === 'visitor') this.target.abort();
    const d = this.w.house.doors.get('d_front')!;
    d.setState('closed');
  }

  protected onStage(s: number) {
    const w = this.w;
    if (s === 1) {
      this.cur = choose(this.entrances);
      this.knockT = 0;
    }
    if (s === 2 && this.cur) {
      this.knockT = 0;
      w.audio.voice(this.cur.knock, 10, 'call');
      setTimeout(() => {
        if (this.stage >= 2) w.hint(`“Clara... é a mamãe... abre ${this.cur?.id === 'front' ? 'a porta' : 'a janela'}...”`, 3.2);
      }, 300);
    }
    if (s === 3 && this.cur) this.sendOwner();
    if (s === 5 && this.cur) {
      w.fx.sting(0.7);
      this.target.addFear(38);
      if (this.cur.door) w.house.doors.get(this.cur.door)!.setState('open');
      w.audio.shriek(this.cur.knock, 0.5);
    }
  }

  private sendOwner() {
    const w = this.w;
    const e = this.cur!;
    this.target.run(
      'visitor',
      [
        { t: 'say', text: choose(['Mãe? A essa hora?', 'Quem é...? Mãe?', 'Já vai! Calma...']), dur: 2.6, kind: 'call' },
        { t: 'spot', spot: e.spot, style: 'normal' },
        { t: 'until', cond: () => this.stage === 0, pose: 'reach' },
      ],
      3,
    );
  }

  protected tick(dt: number) {
    const w = this.w;
    const e = this.cur;
    if (!e) return;
    this.knockT -= dt;
    if (this.hissed > 0) {
      this.hissT -= dt;
      if (this.hissT <= 0) this.hissed = 0;
    }
    if (this.stage <= 2 && this.knockT <= 0) {
      this.knockT = this.stage === 1 ? this.d(3.2) : this.d(2.2);
      w.audio.knock(e.knock, 3, this.stage === 1 ? 0.4 : 1);
    }
    if (this.stage === 1 && this.t > this.d(8)) this.setStage(2);
    else if (this.stage === 2 && this.t > this.d(9)) this.setStage(3);
    else if (this.stage === 3) {
      if (this.target.taskName !== 'visitor') {
        if (this.t > this.d(7)) {
          this.t = 0;
          this.sendOwner();
        }
      } else if (this.target.pos.distanceTo(new THREE.Vector3(...e.spot.p)) < 0.3 && this.mayAttack) {
        this.setStage(4);
        this.target.say('Já vai, mãe... só um segundo...', 2.6, 'call');
      }
      if (Math.random() < dt * 0.4) w.audio.knock(e.knock, 2, 0.7);
    } else if (this.stage === 4) {
      this.target.addFear(1.5 * dt);
      // the sceptic does not wait: he opens the door at once
      if (this.t > this.d(this.target.cfg.skeptic ? 3.2 : 6)) this.setStage(5);
      if (this.target.taskName !== 'visitor') this.setStage(3);
    } else if (this.stage === 5) {
      this.target.addFear(8 * dt);
    }
    // the figure waits outside
    this.vis = damp(this.vis, this.stage >= 2 ? 1 : 0, 2, dt);
    this.fig.visible = this.vis > 0.02;
    this.fig.position.copy(e.figure);
    if (this.stage >= 5 && e.door) this.fig.position.lerp(new THREE.Vector3(6.45, 0, 0.3), 0.5);
    this.fig.rotation.y = e.yaw;
    this.fig.rotation.z = Math.sin(performance.now() * 0.0007) * 0.05;
    (this.fig.userData.mat as THREE.ShaderMaterial).uniforms.uAlpha.value = 0.95 * this.vis;
  }

  canHiss(p: THREE.Vector3) {
    if (!this.cur || this.stage < 2) return false;
    return p.distanceTo(this.cur.knock.clone().setY(p.y)) < 2.4 && Math.abs(p.y - this.cur.spot.p[1]) < 1.6;
  }

  describeDeath() {
    return {
      title: `${this.target.name} abriu a porta`,
      why: `O Visitante imitou uma voz conhecida, ${this.target.name} foi atender e deixou entrar o que estava lá fora.`,
      tip: 'Chegue à porta antes da pessoa e bufe: o primeiro bufo faz ele trocar de entrada, o segundo (em até 20 s) o expulsa. Use a Visão de Gato para ver que não é humano.',
    };
  }

  onHiss(p: THREE.Vector3, strong: boolean) {
    if (!strong || !this.canHiss(p)) return false;
    const w = this.w;
    w.audio.shriek(this.cur!.knock, 0.6);
    w.fx.shake(0.4);
    if (this.hissed === 0) {
      // first hiss: it moves to another door and knocks harder
      this.hissed = 1;
      this.hissT = 20;
      const others = this.entrances.filter((e) => e !== this.cur);
      this.cur = choose(others);
      w.hint('Ele mudou de entrada! Bufe de novo em até 20 s.', 3.6);
      w.audio.knock(this.cur.knock, 5, 1);
      this.knockT = 0.5;
      if (this.stage >= 3) {
        if (this.target.taskName === 'visitor') this.target.abort();
        this.setStage(3);
        this.sendOwner();
      }
      return true;
    }
    const was = this.target.taskName === 'visitor';
    this.repel();
    if (was) {
      this.target.addFear(6);
      this.target.say(choose(['...Foi embora? Mãe?', 'Ninguém... não tem ninguém aí.', '{cat}, você bufou pra quem?']), 2.8, 'scared');
      this.target.goToBed(2);
    }
    return true;
  }

  focus() {
    if (!this.cur || this.stage === 0) return null;
    return this.cur.knock;
  }
  entity() {
    return this.cur && this.stage >= 2 ? this.cur.knock : null;
  }
}
