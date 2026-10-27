import * as THREE from 'three';
import { Threat, Wisps } from './Threat';
import type { World } from '../game/World';
import type { LoopHandle } from '../audio/Audio';
import { RITUAL_CENTER } from '../world/Layout';
import { spectralMat } from '../render/Materials';
import { damp } from '../core/math';

/**
 * A Coisa no Porão — wakes at 03:00 on the fifth night. Everything else keeps
 * going while the cat tries to complete the ritual on the chalk circle.
 * Every few seconds it rears up (the tell) and sends a shockwave; a strong
 * hiss during the tell cancels it.
 */
export class Thing extends Threat {
  readonly id = 'thing' as const;
  readonly name = 'A Coisa no Porão';
  center = new THREE.Vector3(...RITUAL_CENTER);
  group = new THREE.Group();
  private tentacles: THREE.Group[] = [];
  private core: THREE.Mesh;
  private wisps: Wisps;
  private rumble: LoopHandle | null = null;
  private vis = 0;
  waveT = 0;
  tell = 0;
  /** set by the game when a wave hits the cat */
  onWave?: (hitCat: boolean) => void;
  dead = false;
  private cancelled = false;
  /** how many ritual items sit on the circle (the clímax speeds up from 2) */
  ritualItems = 0;

  constructor(w: World) {
    super(w);
    const m = spectralMat({ color: '#080102', rim: '#5a0a0a', vision: '#ff5a4a', alpha: 0, noise: 0.12, wobble: 0.05 });
    for (let i = 0; i < 9; i++) {
      const tg = new THREE.Group();
      const a = (i / 9) * Math.PI * 2;
      tg.position.set(Math.cos(a) * 1.25, 0, Math.sin(a) * 1.25);
      tg.rotation.y = -a;
      let parent: THREE.Object3D = tg;
      for (let k = 0; k < 7; k++) {
        const seg = new THREE.Group();
        seg.position.y = k === 0 ? 0 : 0.28;
        const r = 0.16 * (1 - k / 8.5);
        const mesh = new THREE.Mesh(new THREE.CylinderGeometry(r * 0.8, r, 0.3, 7), m);
        mesh.position.y = 0.14;
        seg.add(mesh);
        parent.add(seg);
        parent = seg;
      }
      this.tentacles.push(tg);
      this.group.add(tg);
    }
    this.core = new THREE.Mesh(new THREE.IcosahedronGeometry(0.35, 1), new THREE.MeshBasicMaterial({ color: new THREE.Color('#ff3020').multiplyScalar(2), transparent: true, opacity: 0 }));
    this.core.position.y = -0.1;
    this.group.add(this.core);
    this.group.userData.mat = m;
    this.group.position.copy(this.center);
    this.group.visible = false;
    w.scene.add(this.group);
    this.wisps = new Wisps(w.scene, 50, '#200303', 0.5, 1.4);
    this.wisps.opacity = 0;
  }

  reset() {
    this.stage = 0;
    this.t = 0;
    this.vis = 0;
    this.group.visible = false;
    this.wisps.opacity = 0;
    this.rumble?.stop(1);
    this.rumble = null;
    this.tell = 0;
    this.waveT = 0;
    this.dead = false;
    const fx = this.w.house.lights.get(15);
    fx.setOn(false);
  }

  override update(dt: number) {
    if (!this.enabled || this.dead) return;
    if (this.stage === 0) {
      if (this.w.hour >= 3) this.setStage(1);
      return;
    }
    this.t += dt;
    this.tick(dt);
  }

  protected onStage(s: number) {
    const w = this.w;
    if (s === 1) {
      w.fx.shake(1.6);
      w.fx.sting(0.8);
      w.audio.thud(null, 1, 35);
      this.rumble = w.audio.loop('rumble', this.center.clone().add(new THREE.Vector3(0, 0.8, 0)), { ref: 3, max: 60, rolloff: 0.5, gain: 1 });
      this.rumble.setLevel(0.9);
      for (const l of w.house.lights.lights) l.flicker = 0.9;
      setTimeout(() => {
        for (const l of w.house.lights.lights) l.flicker = 0;
      }, 3000);
      const fx = w.house.lights.get(15);
      fx.light.position.copy(this.center).add(new THREE.Vector3(0, 0.6, 0));
      fx.light.color.set('#ff3b2f');
      fx.baseColor.set('#ff3b2f');
      w.house.lights.setRoomMask(15, 'porao');
      fx.setOn(true);
      this.target.say('O que... a casa tá tremendo!', 2.6, 'scared');
      w.hint('Algo acordou no porão. Leve os três objetos ao círculo.', 5);
    }
  }

  protected tick(dt: number) {
    const w = this.w;
    this.vis = damp(this.vis, 1, 0.6, dt);
    this.group.visible = true;
    (this.group.userData.mat as THREE.ShaderMaterial).uniforms.uAlpha.value = 0.9 * this.vis;
    const coreMat = this.core.material as THREE.MeshBasicMaterial;
    coreMat.opacity = 0.5 * this.vis + this.tell * 0.5;
    this.wisps.opacity = 0.5 * this.vis;
    this.wisps.update(dt, this.center.clone().add(new THREE.Vector3(0, -0.1, 0)), 1.6);
    w.house.ritualGlow = 1 + this.vis * 0.4 + this.tell;
    const fx = w.house.lights.get(15);
    fx.scale = 0.5 + this.tell * 2.5 + Math.sin(this.t * 3) * 0.15;
    if (this.stage === 1 && this.t > 6) this.setStage(2);
    this.fearAll(0.1 * dt);

    // shockwave cycle
    if (this.stage >= 2) {
      this.waveT += dt;
      const interval = this.d(this.ritualItems >= 2 ? 5 : 7.5);
      const tellDur = 1.7;
      if (this.waveT > interval - tellDur) {
        if (this.tell === 0) {
          this.cancelled = false;
          w.audio.breath(this.center.clone().add(new THREE.Vector3(0, 1, 0)), 0.9);
        }
        this.tell = Math.min(1, (this.waveT - (interval - tellDur)) / tellDur);
      }
      if (this.waveT > interval) {
        this.waveT = 0;
        this.tell = 0;
        if (!this.cancelled) {
          const d = w.cat.pos.distanceTo(this.center);
          const hit = d < 4.6 && Math.abs(w.cat.pos.y - this.center.y) < 1.5;
          w.audio.thud(this.center, 0.9, 40);
          w.fx.shake(hit ? 1.1 : 0.4);
          this.onWave?.(hit);
        }
      }
    }
    // tentacles writhe; rear up during the tell
    const time = this.t;
    this.tentacles.forEach((tg, i) => {
      let seg: THREE.Object3D = tg.children[0];
      let k = 0;
      while (seg) {
        const sway = Math.sin(time * 1.6 + i * 1.7 + k * 0.6) * 0.22;
        seg.rotation.x = (k === 0 ? -0.5 : 0.18) + sway * (0.4 + this.tell * 0.4) - this.tell * (k === 0 ? 0.4 : 0.08);
        seg.rotation.z = Math.cos(time * 1.3 + i + k) * 0.12;
        seg.scale.setScalar(this.vis * (1 + this.tell * 0.15));
        seg = seg.children.find((c) => (c as THREE.Group).isGroup) as THREE.Object3D;
        k++;
      }
    });
  }

  onHiss(p: THREE.Vector3, strong: boolean) {
    if (this.stage < 2 || !strong || this.tell <= 0.05) return false;
    if (p.distanceTo(this.center) > 5) return false;
    this.cancelled = true;
    this.tell = 0;
    this.waveT = 0;
    this.w.audio.shriek(this.center.clone().add(new THREE.Vector3(0, 0.8, 0)), 0.4);
    return true;
  }

  canHiss(p: THREE.Vector3) {
    return this.stage >= 2 && this.tell > 0.05 && p.distanceTo(this.center) < 5;
  }

  describeDeath() {
    return {
      title: 'A Coisa no Porão venceu',
      why: 'As ondas e o caos das outras assombrações deixaram o medo chegar ao limite antes de o ritual terminar.',
      tip: 'Leve a foto, a coleira e a chave ao círculo e segure o ritual. Bufe quando os tentáculos se erguerem para cancelar a onda, e resolva o resto entre uma onda e outra.',
    };
  }

  /** the ritual is complete */
  kill() {
    const w = this.w;
    w.audio.shriek(this.center.clone().add(new THREE.Vector3(0, 1, 0)), 1);
    w.fx.flash(0.9, '#ffffff');
    w.fx.shake(1.5);
    this.reset();
    this.dead = true;
    w.house.ritualGlow = 0;
  }

  focus() {
    return this.stage > 0 ? this.center : null;
  }
  entity() {
    return this.stage > 0 ? this.center : null;
  }
  urgency() {
    return this.stage > 0 ? 0.35 + this.tell * 0.4 : 0;
  }
}
