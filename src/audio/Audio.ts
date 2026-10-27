import * as THREE from 'three';
import { Settings } from '../core/Settings';
import { clamp, rand, choose } from '../core/math';

/**
 * Everything you hear is synthesized here with the Web Audio API:
 * no audio files. Positional sounds use HRTF panners plus a cheap
 * room-hop occlusion filter so you can tell which room a sound is in.
 */

export type Bus = 'sfx' | 'amb' | 'music' | 'voice' | 'ui';

export interface SpatialOpts {
  ref?: number;
  max?: number;
  rolloff?: number;
  bus?: Bus;
  gain?: number;
  cheap?: boolean;
}

export class Spatial {
  panner: PannerNode;
  filter: BiquadFilterNode;
  gain: GainNode;
  input: GainNode;
  pos = new THREE.Vector3();
  baseGain: number;
  alive = true;

  constructor(
    public eng: AudioEngine,
    pos: THREE.Vector3,
    o: SpatialOpts,
  ) {
    const c = eng.ctx;
    this.input = c.createGain();
    this.filter = c.createBiquadFilter();
    this.filter.type = 'lowpass';
    this.filter.frequency.value = 20000;
    this.panner = c.createPanner();
    this.panner.panningModel = o.cheap ? 'equalpower' : 'HRTF';
    this.panner.distanceModel = 'inverse';
    this.panner.refDistance = o.ref ?? 1.2;
    this.panner.maxDistance = o.max ?? 40;
    this.panner.rolloffFactor = o.rolloff ?? 1.3;
    this.gain = c.createGain();
    this.baseGain = o.gain ?? 1;
    this.gain.gain.value = this.baseGain;
    this.input.connect(this.filter).connect(this.panner).connect(this.gain).connect(eng.bus(o.bus ?? 'sfx'));
    this.gain.connect(eng.reverbSend);
    this.setPos(pos);
    eng.spatials.add(this);
  }

  setPos(p: THREE.Vector3) {
    this.pos.copy(p);
    const t = this.eng.ctx.currentTime;
    this.panner.positionX.setTargetAtTime(p.x, t, 0.02);
    this.panner.positionY.setTargetAtTime(p.y, t, 0.02);
    this.panner.positionZ.setTargetAtTime(p.z, t, 0.02);
  }

  setGain(v: number, ramp = 0.1) {
    this.baseGain = v;
  }

  dispose(after = 0) {
    setTimeout(() => {
      this.alive = false;
      try {
        this.gain.disconnect();
      } catch {
        /* */
      }
      this.eng.spatials.delete(this);
    }, after * 1000);
  }
}

export interface LoopHandle {
  sp: Spatial | null;
  out: GainNode;
  setLevel: (v: number) => void;
  setPos: (p: THREE.Vector3) => void;
  stop: (fade?: number) => void;
  level: number;
}

export class AudioEngine {
  ctx: AudioContext;
  master: GainNode;
  private buses: Record<Bus, GainNode>;
  reverbSend: GainNode;
  private comp: DynamicsCompressorNode;
  white!: AudioBuffer;
  pink!: AudioBuffer;
  brown!: AudioBuffer;
  spatials = new Set<Spatial>();
  occlusion?: (p: THREE.Vector3) => number;
  started = false;
  muffled = 0;
  private muffle: BiquadFilterNode;

  constructor() {
    const AC = window.AudioContext || (window as any).webkitAudioContext;
    this.ctx = new AC({ latencyHint: 'interactive' });
    const c = this.ctx;
    this.master = c.createGain();
    this.comp = c.createDynamicsCompressor();
    this.comp.threshold.value = -16;
    this.comp.ratio.value = 3.5;
    this.comp.attack.value = 0.005;
    this.comp.release.value = 0.25;
    this.muffle = c.createBiquadFilter();
    this.muffle.type = 'lowpass';
    this.muffle.frequency.value = 20000;
    this.master.connect(this.muffle).connect(this.comp).connect(c.destination);
    this.buses = {
      sfx: c.createGain(),
      amb: c.createGain(),
      music: c.createGain(),
      voice: c.createGain(),
      ui: c.createGain(),
    };
    for (const b of Object.values(this.buses)) b.connect(this.master);
    // reverb
    const conv = c.createConvolver();
    conv.buffer = this.impulse(2.4, 2.8);
    this.reverbSend = c.createGain();
    this.reverbSend.gain.value = 0.18;
    const wet = c.createGain();
    wet.gain.value = 0.55;
    this.reverbSend.connect(conv).connect(wet).connect(this.master);
    this.makeNoise();
    this.applyVolumes();
    Settings.onChange(() => this.applyVolumes());
    const resume = () => {
      if (c.state !== 'running') c.resume();
      this.started = true;
    };
    window.addEventListener('pointerdown', resume);
    window.addEventListener('keydown', resume);
  }

  bus(b: Bus) {
    return this.buses[b];
  }

  applyVolumes() {
    const s = Settings.data;
    const t = this.ctx.currentTime;
    this.master.gain.setTargetAtTime(s.master, t, 0.05);
    this.buses.sfx.gain.setTargetAtTime(s.sfx, t, 0.05);
    this.buses.voice.gain.setTargetAtTime(s.sfx, t, 0.05);
    this.buses.ui.gain.setTargetAtTime(s.sfx * 0.7, t, 0.05);
    this.buses.amb.gain.setTargetAtTime(s.ambience, t, 0.05);
    this.buses.music.gain.setTargetAtTime(s.music * 0.8, t, 0.05);
  }

  /** muffle everything (pause menu, being locked in) */
  setMuffle(v: number) {
    this.muffled = v;
    this.muffle.frequency.setTargetAtTime(20000 * Math.pow(0.03, v), this.ctx.currentTime, 0.1);
  }

  private impulse(dur: number, decay: number) {
    const c = this.ctx;
    const len = Math.floor(c.sampleRate * dur);
    const b = c.createBuffer(2, len, c.sampleRate);
    for (let ch = 0; ch < 2; ch++) {
      const d = b.getChannelData(ch);
      for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, decay);
    }
    return b;
  }

  private makeNoise() {
    const c = this.ctx;
    const len = c.sampleRate * 3;
    this.white = c.createBuffer(1, len, c.sampleRate);
    this.pink = c.createBuffer(1, len, c.sampleRate);
    this.brown = c.createBuffer(1, len, c.sampleRate);
    const w = this.white.getChannelData(0);
    const p = this.pink.getChannelData(0);
    const br = this.brown.getChannelData(0);
    let b0 = 0,
      b1 = 0,
      b2 = 0,
      b3 = 0,
      b4 = 0,
      b5 = 0,
      b6 = 0,
      last = 0;
    for (let i = 0; i < len; i++) {
      const white = Math.random() * 2 - 1;
      w[i] = white;
      b0 = 0.99886 * b0 + white * 0.0555179;
      b1 = 0.99332 * b1 + white * 0.0750759;
      b2 = 0.969 * b2 + white * 0.153852;
      b3 = 0.8665 * b3 + white * 0.3104856;
      b4 = 0.55 * b4 + white * 0.5329522;
      b5 = -0.7616 * b5 - white * 0.016898;
      p[i] = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362) * 0.11;
      b6 = white * 0.115926;
      last = (last + 0.02 * white) / 1.02;
      br[i] = last * 3.5;
    }
  }

  get now() {
    return this.ctx.currentTime;
  }

  noiseSrc(kind: 'white' | 'pink' | 'brown' = 'white', loop = true) {
    const s = this.ctx.createBufferSource();
    s.buffer = kind === 'white' ? this.white : kind === 'pink' ? this.pink : this.brown;
    s.loop = loop;
    s.loopStart = Math.random();
    return s;
  }

  /** destination for a one-shot: positional or flat */
  dest(pos: THREE.Vector3 | null, o: SpatialOpts = {}): { node: AudioNode; sp: Spatial | null } {
    if (pos) {
      const sp = new Spatial(this, pos, o);
      return { node: sp.input, sp };
    }
    const g = this.ctx.createGain();
    g.gain.value = o.gain ?? 1;
    g.connect(this.bus(o.bus ?? 'sfx'));
    if ((o.bus ?? 'sfx') !== 'ui') g.connect(this.reverbSend);
    return { node: g, sp: null };
  }

  env(g: GainNode, t: number, a: number, peak: number, d: number, sustain = 0, rel = 0.05) {
    g.gain.cancelScheduledValues(t);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(peak, t + a);
    if (sustain > 0) {
      g.gain.setTargetAtTime(peak * 0.7, t + a, d / 3);
      g.gain.setTargetAtTime(0.0001, t + a + sustain, rel);
    } else g.gain.setTargetAtTime(0.0001, t + a, d / 4);
  }

  /** listener follows the camera */
  update(cam: THREE.Camera, listenerOcclusion: (p: THREE.Vector3) => { gain: number; cutoff: number }) {
    const l = this.ctx.listener;
    const t = this.ctx.currentTime;
    const p = cam.position;
    const f = new THREE.Vector3(0, 0, -1).applyQuaternion(cam.quaternion);
    const u = new THREE.Vector3(0, 1, 0).applyQuaternion(cam.quaternion);
    if (l.positionX) {
      l.positionX.setTargetAtTime(p.x, t, 0.02);
      l.positionY.setTargetAtTime(p.y, t, 0.02);
      l.positionZ.setTargetAtTime(p.z, t, 0.02);
      l.forwardX.setTargetAtTime(f.x, t, 0.02);
      l.forwardY.setTargetAtTime(f.y, t, 0.02);
      l.forwardZ.setTargetAtTime(f.z, t, 0.02);
      l.upX.setTargetAtTime(u.x, t, 0.02);
      l.upY.setTargetAtTime(u.y, t, 0.02);
      l.upZ.setTargetAtTime(u.z, t, 0.02);
    } else {
      (l as any).setPosition(p.x, p.y, p.z);
      (l as any).setOrientation(f.x, f.y, f.z, u.x, u.y, u.z);
    }
    for (const s of this.spatials) {
      const o = listenerOcclusion(s.pos);
      s.filter.frequency.setTargetAtTime(o.cutoff, t, 0.08);
      s.gain.gain.setTargetAtTime(s.baseGain * o.gain, t, 0.08);
    }
  }

  /* ============================================================ voices */

  meow(pos: THREE.Vector3 | null, pitch = 1) {
    const c = this.ctx;
    const t = this.now;
    const { node, sp } = this.dest(pos, { ref: 1.5, gain: 0.55 });
    const o = c.createOscillator();
    o.type = 'sawtooth';
    const f0 = rand(520, 640) * pitch;
    const dur = rand(0.45, 0.7);
    o.frequency.setValueAtTime(f0 * 0.85, t);
    o.frequency.linearRampToValueAtTime(f0 * 1.35, t + dur * 0.35);
    o.frequency.linearRampToValueAtTime(f0 * 0.75, t + dur);
    const vib = c.createOscillator();
    vib.frequency.value = 7;
    const vg = c.createGain();
    vg.gain.value = 9;
    vib.connect(vg).connect(o.frequency);
    const f1 = c.createBiquadFilter();
    f1.type = 'bandpass';
    f1.Q.value = 5;
    f1.frequency.setValueAtTime(700, t);
    f1.frequency.linearRampToValueAtTime(1300, t + dur * 0.4);
    f1.frequency.linearRampToValueAtTime(600, t + dur);
    const f2 = c.createBiquadFilter();
    f2.type = 'bandpass';
    f2.Q.value = 6;
    f2.frequency.setValueAtTime(1900, t);
    f2.frequency.linearRampToValueAtTime(2600, t + dur * 0.4);
    f2.frequency.linearRampToValueAtTime(1500, t + dur);
    const g = c.createGain();
    const g2 = c.createGain();
    g2.gain.value = 0.6;
    o.connect(f1).connect(g);
    o.connect(f2).connect(g2).connect(g);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(0.9, t + 0.06);
    g.gain.setValueAtTime(0.9, t + dur * 0.7);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    g.connect(node);
    o.start(t);
    vib.start(t);
    o.stop(t + dur + 0.05);
    vib.stop(t + dur + 0.05);
    sp?.dispose(dur + 2.5);
  }

  hiss(pos: THREE.Vector3 | null, strong: boolean) {
    const c = this.ctx;
    const t = this.now;
    const { node, sp } = this.dest(pos, { ref: 1.6, gain: strong ? 0.9 : 0.4 });
    const n = this.noiseSrc('white');
    const hp = c.createBiquadFilter();
    hp.type = 'highpass';
    hp.frequency.value = 1800;
    const bp = c.createBiquadFilter();
    bp.type = 'bandpass';
    bp.frequency.setValueAtTime(5200, t);
    bp.frequency.linearRampToValueAtTime(3800, t + 0.7);
    bp.Q.value = 0.8;
    const g = c.createGain();
    const dur = strong ? 0.9 : 0.5;
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(strong ? 1 : 0.6, t + 0.03);
    g.gain.setTargetAtTime(0.5, t + 0.08, 0.15);
    g.gain.setTargetAtTime(0.0001, t + dur * 0.75, 0.08);
    n.connect(hp).connect(bp).connect(g).connect(node);
    // a growly undertone
    if (strong) {
      const o = c.createOscillator();
      o.type = 'sawtooth';
      o.frequency.value = 95;
      const lp = c.createBiquadFilter();
      lp.type = 'lowpass';
      lp.frequency.value = 500;
      const og = c.createGain();
      og.gain.setValueAtTime(0.0001, t);
      og.gain.linearRampToValueAtTime(0.35, t + 0.05);
      og.gain.setTargetAtTime(0.0001, t + 0.4, 0.1);
      const am = c.createOscillator();
      am.frequency.value = 28;
      const amg = c.createGain();
      amg.gain.value = 0.25;
      am.connect(amg).connect(og.gain);
      o.connect(lp).connect(og).connect(node);
      o.start(t);
      am.start(t);
      o.stop(t + dur);
      am.stop(t + dur);
    }
    n.start(t);
    n.stop(t + dur + 0.3);
    sp?.dispose(dur + 2.5);
  }

  /** looping purr */
  purr(): LoopHandle {
    const c = this.ctx;
    const out = c.createGain();
    out.gain.value = 0;
    out.connect(this.bus('sfx'));
    const n = this.noiseSrc('brown');
    const lp = c.createBiquadFilter();
    lp.type = 'lowpass';
    lp.frequency.value = 260;
    const am = c.createOscillator();
    am.frequency.value = 26;
    const amg = c.createGain();
    amg.gain.value = 0.5;
    const body = c.createGain();
    body.gain.value = 0.5;
    am.connect(amg).connect(body.gain);
    // breathing: in/out every ~1.8 s
    const br = c.createOscillator();
    br.frequency.value = 0.55;
    const brg = c.createGain();
    brg.gain.value = 0.25;
    br.connect(brg).connect(body.gain);
    n.connect(lp).connect(body).connect(out);
    n.start();
    am.start();
    br.start();
    const h: LoopHandle = {
      sp: null,
      out,
      level: 0,
      setLevel: (v) => {
        h.level = v;
        out.gain.setTargetAtTime(v * 0.9, c.currentTime, 0.2);
      },
      setPos: () => {},
      stop: () => {
        out.gain.setTargetAtTime(0, c.currentTime, 0.1);
        setTimeout(() => {
          n.stop();
          am.stop();
          br.stop();
        }, 600);
      },
    };
    return h;
  }

  pawStep(pos: THREE.Vector3, run: boolean, sneak: boolean, surface: 'wood' | 'tile' | 'concrete' | 'carpet' = 'wood') {
    const c = this.ctx;
    const t = this.now;
    const vol = sneak ? 0.05 : run ? 0.22 : 0.11;
    const { node, sp } = this.dest(pos, { ref: 0.8, gain: vol, cheap: true });
    const n = this.noiseSrc('pink', false);
    const f = c.createBiquadFilter();
    f.type = 'bandpass';
    f.frequency.value = surface === 'tile' ? 2600 : surface === 'concrete' ? 1400 : surface === 'carpet' ? 500 : 900;
    f.Q.value = 1.2;
    const g = c.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(1, t + 0.004);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.06);
    n.connect(f).connect(g).connect(node);
    n.start(t, Math.random() * 2);
    n.stop(t + 0.1);
    sp?.dispose(1.5);
  }

  humanStep(pos: THREE.Vector3, creak = false) {
    const c = this.ctx;
    const t = this.now;
    const { node, sp } = this.dest(pos, { ref: 2, gain: 0.45, cheap: true });
    const n = this.noiseSrc('brown', false);
    const lp = c.createBiquadFilter();
    lp.type = 'lowpass';
    lp.frequency.value = 380;
    const g = c.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(1, t + 0.01);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.14);
    n.connect(lp).connect(g).connect(node);
    n.start(t, Math.random() * 2);
    n.stop(t + 0.2);
    if (creak) this.creak(pos, 0.25, 0.6);
    sp?.dispose(2);
  }

  click(pos: THREE.Vector3 | null, gain = 0.4) {
    const c = this.ctx;
    const t = this.now;
    const { node, sp } = this.dest(pos, { ref: 1, gain, bus: pos ? 'sfx' : 'ui' });
    const o = c.createOscillator();
    o.type = 'square';
    o.frequency.setValueAtTime(2400, t);
    o.frequency.exponentialRampToValueAtTime(600, t + 0.02);
    const g = c.createGain();
    g.gain.setValueAtTime(0.5, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.03);
    o.connect(g).connect(node);
    o.start(t);
    o.stop(t + 0.05);
    const n = this.noiseSrc('white', false);
    const hp = c.createBiquadFilter();
    hp.type = 'highpass';
    hp.frequency.value = 3000;
    const ng = c.createGain();
    ng.gain.setValueAtTime(0.6, t);
    ng.gain.exponentialRampToValueAtTime(0.0001, t + 0.025);
    n.connect(hp).connect(ng).connect(node);
    n.start(t);
    n.stop(t + 0.05);
    sp?.dispose(1);
  }

  creak(pos: THREE.Vector3 | null, gain = 0.5, len = 1.4, pitch = 1) {
    const c = this.ctx;
    const t = this.now;
    const { node, sp } = this.dest(pos, { ref: 2, gain });
    const o = c.createOscillator();
    o.type = 'sawtooth';
    const base = rand(150, 240) * pitch;
    o.frequency.setValueAtTime(base, t);
    for (let i = 1; i < 8; i++) o.frequency.linearRampToValueAtTime(base * rand(0.75, 1.5), t + (len * i) / 8);
    const bp = c.createBiquadFilter();
    bp.type = 'bandpass';
    bp.frequency.value = 900;
    bp.Q.value = 9;
    // stick-slip texture
    const am = c.createOscillator();
    am.type = 'square';
    am.frequency.value = rand(22, 40);
    const amg = c.createGain();
    amg.gain.value = 0.45;
    const g = c.createGain();
    g.gain.value = 0.5;
    am.connect(amg).connect(g.gain);
    const env = c.createGain();
    env.gain.setValueAtTime(0.0001, t);
    env.gain.linearRampToValueAtTime(1, t + 0.15);
    env.gain.setValueAtTime(1, t + len * 0.75);
    env.gain.linearRampToValueAtTime(0.0001, t + len);
    o.connect(bp).connect(g).connect(env).connect(node);
    o.start(t);
    am.start(t);
    o.stop(t + len + 0.1);
    am.stop(t + len + 0.1);
    sp?.dispose(len + 3);
  }

  thud(pos: THREE.Vector3 | null, gain = 0.6, low = 70) {
    const c = this.ctx;
    const t = this.now;
    const { node, sp } = this.dest(pos, { ref: 2, gain });
    const o = c.createOscillator();
    o.frequency.setValueAtTime(low * 2, t);
    o.frequency.exponentialRampToValueAtTime(low, t + 0.1);
    const g = c.createGain();
    g.gain.setValueAtTime(1, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.35);
    o.connect(g).connect(node);
    o.start(t);
    o.stop(t + 0.4);
    const n = this.noiseSrc('brown', false);
    const lp = c.createBiquadFilter();
    lp.type = 'lowpass';
    lp.frequency.value = 600;
    const ng = c.createGain();
    ng.gain.setValueAtTime(0.8, t);
    ng.gain.exponentialRampToValueAtTime(0.0001, t + 0.15);
    n.connect(lp).connect(ng).connect(node);
    n.start(t);
    n.stop(t + 0.2);
    sp?.dispose(3);
  }

  /** low, wet growl of the hound */
  growl(pos: THREE.Vector3 | null, gain = 0.6, dur = 1.5) {
    const c = this.ctx;
    const t = this.now;
    const { node, sp } = this.dest(pos, { ref: 2, gain, max: 40 });
    const o = c.createOscillator();
    o.type = 'sawtooth';
    o.frequency.setValueAtTime(70, t);
    o.frequency.linearRampToValueAtTime(52, t + dur);
    const lp = c.createBiquadFilter();
    lp.type = 'lowpass';
    lp.frequency.value = 420;
    const am = c.createOscillator();
    am.frequency.value = 24;
    const amg = c.createGain();
    amg.gain.value = 0.45;
    const g = c.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(0.7, t + 0.18);
    g.gain.setValueAtTime(0.7, t + dur * 0.7);
    g.gain.linearRampToValueAtTime(0.0001, t + dur);
    am.connect(amg).connect(g.gain);
    const n = this.noiseSrc('brown');
    const nb = c.createBiquadFilter();
    nb.type = 'bandpass';
    nb.frequency.value = 220;
    nb.Q.value = 1.2;
    const ng = c.createGain();
    ng.gain.value = 0.5;
    n.connect(nb).connect(ng).connect(g);
    o.connect(lp).connect(g).connect(node);
    o.start(t);
    am.start(t);
    n.start(t);
    o.stop(t + dur + 0.1);
    am.stop(t + dur + 0.1);
    n.stop(t + dur + 0.1);
    sp?.dispose(dur + 2);
  }

  /** nose snuffles */
  sniff(pos: THREE.Vector3 | null, gain = 0.4) {
    const c = this.ctx;
    const t = this.now;
    const { node, sp } = this.dest(pos, { ref: 1.5, gain });
    for (let i = 0; i < 3; i++) {
      const st = t + i * 0.16;
      const n = this.noiseSrc('white', false);
      const bp = c.createBiquadFilter();
      bp.type = 'bandpass';
      bp.frequency.value = 2400 + i * 300;
      bp.Q.value = 1.4;
      const g = c.createGain();
      g.gain.setValueAtTime(0.0001, st);
      g.gain.linearRampToValueAtTime(0.9, st + 0.01);
      g.gain.exponentialRampToValueAtTime(0.0001, st + 0.12);
      n.connect(bp).connect(g).connect(node);
      n.start(st, Math.random() * 2);
      n.stop(st + 0.15);
    }
    sp?.dispose(2);
  }

  /** claws on the floorboards */
  claws(pos: THREE.Vector3, gain = 0.4) {
    const c = this.ctx;
    const t = this.now;
    const { node, sp } = this.dest(pos, { ref: 1.8, gain, cheap: true });
    for (let i = 0; i < 2; i++) {
      const st = t + i * 0.07;
      const o = c.createOscillator();
      o.type = 'triangle';
      o.frequency.setValueAtTime(rand(1100, 1500), st);
      o.frequency.exponentialRampToValueAtTime(420, st + 0.04);
      const g = c.createGain();
      g.gain.setValueAtTime(0.7, st);
      g.gain.exponentialRampToValueAtTime(0.0001, st + 0.05);
      o.connect(g).connect(node);
      o.start(st);
      o.stop(st + 0.07);
    }
    sp?.dispose(1.5);
  }

  /** the lunge */
  bark(pos: THREE.Vector3 | null, gain = 0.8) {
    const c = this.ctx;
    const t = this.now;
    const { node, sp } = this.dest(pos, { ref: 3, gain, max: 50 });
    for (const f of [190, 380]) {
      const o = c.createOscillator();
      o.type = 'sawtooth';
      o.frequency.setValueAtTime(f * 1.3, t);
      o.frequency.exponentialRampToValueAtTime(f * 0.6, t + 0.35);
      const bp = c.createBiquadFilter();
      bp.type = 'bandpass';
      bp.frequency.value = 700;
      bp.Q.value = 1.6;
      const g = c.createGain();
      g.gain.setValueAtTime(0.0001, t);
      g.gain.linearRampToValueAtTime(0.9, t + 0.01);
      g.gain.exponentialRampToValueAtTime(0.0001, t + 0.4);
      o.connect(bp).connect(g).connect(node);
      o.start(t);
      o.stop(t + 0.45);
    }
    const n = this.noiseSrc('white', false);
    const bp2 = c.createBiquadFilter();
    bp2.type = 'bandpass';
    bp2.frequency.value = 1800;
    const ng = c.createGain();
    ng.gain.setValueAtTime(0.5, t);
    ng.gain.exponentialRampToValueAtTime(0.0001, t + 0.2);
    n.connect(bp2).connect(ng).connect(node);
    n.start(t);
    n.stop(t + 0.25);
    sp?.dispose(3);
  }

  /** the cat's own cry when caught */
  catCry(pos: THREE.Vector3 | null, gain = 0.8) {
    const c = this.ctx;
    const t = this.now;
    const { node, sp } = this.dest(pos, { ref: 2, gain, max: 40 });
    const o = c.createOscillator();
    o.type = 'sawtooth';
    o.frequency.setValueAtTime(900, t);
    o.frequency.linearRampToValueAtTime(1900, t + 0.12);
    o.frequency.linearRampToValueAtTime(700, t + 0.7);
    const f = c.createBiquadFilter();
    f.type = 'bandpass';
    f.frequency.value = 1700;
    f.Q.value = 3;
    const g = c.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(0.9, t + 0.03);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.8);
    o.connect(f).connect(g).connect(node);
    o.start(t);
    o.stop(t + 0.85);
    sp?.dispose(3);
  }

  /** distant thunder, `delay` seconds after the flash (sound travels) */
  thunder(delay: number, power = 1) {
    const c = this.ctx;
    const t = this.now + delay;
    const { node } = this.dest(null, { bus: 'amb', gain: 0.8 * power });
    const n = this.noiseSrc('brown');
    const lp = c.createBiquadFilter();
    lp.type = 'lowpass';
    lp.frequency.setValueAtTime(900 + 500 * power, t);
    lp.frequency.exponentialRampToValueAtTime(70, t + 3.4);
    const g = c.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(1.0, t + 0.08);
    g.gain.setTargetAtTime(0.55, t + 0.2, 0.5);
    g.gain.setTargetAtTime(0.0001, t + 1.6, 0.9);
    n.connect(lp).connect(g).connect(node);
    n.start(t);
    n.stop(t + 4.6);
    // the crack
    if (delay < 1.2) {
      const cr = this.noiseSrc('white', false);
      const bp = c.createBiquadFilter();
      bp.type = 'highpass';
      bp.frequency.value = 1500;
      const cg = c.createGain();
      cg.gain.setValueAtTime(0.0001, t);
      cg.gain.linearRampToValueAtTime(0.6 * power, t + 0.01);
      cg.gain.exponentialRampToValueAtTime(0.0001, t + 0.35);
      cr.connect(bp).connect(cg).connect(node);
      cr.start(t);
      cr.stop(t + 0.4);
    }
    // sub boom
    const o = c.createOscillator();
    o.frequency.setValueAtTime(48, t);
    o.frequency.exponentialRampToValueAtTime(28, t + 2);
    const og = c.createGain();
    og.gain.setValueAtTime(0.0001, t);
    og.gain.linearRampToValueAtTime(0.6 * power, t + 0.15);
    og.gain.exponentialRampToValueAtTime(0.0001, t + 2.4);
    o.connect(og).connect(node);
    o.start(t);
    o.stop(t + 2.6);
  }

  /** electrical buzz of a dying bulb */
  buzz(pos: THREE.Vector3, dur: number) {
    const c = this.ctx;
    const t = this.now;
    const { node, sp } = this.dest(pos, { ref: 1.5, gain: 0.4 });
    const o = c.createOscillator();
    o.type = 'sawtooth';
    o.frequency.value = 120;
    const bp = c.createBiquadFilter();
    bp.type = 'bandpass';
    bp.frequency.value = 1800;
    bp.Q.value = 2;
    const g = c.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(0.5, t + 0.2);
    const flick = c.createOscillator();
    flick.type = 'square';
    flick.frequency.value = 9;
    const fg = c.createGain();
    fg.gain.value = 0.35;
    flick.connect(fg).connect(g.gain);
    g.gain.setValueAtTime(0.5, t + dur * 0.8);
    g.gain.linearRampToValueAtTime(0.0001, t + dur);
    o.connect(bp).connect(g).connect(node);
    o.start(t);
    flick.start(t);
    o.stop(t + dur + 0.1);
    flick.stop(t + dur + 0.1);
    sp?.dispose(dur + 2);
  }

  knock(pos: THREE.Vector3, count = 3, strength = 1) {
    for (let i = 0; i < count; i++) setTimeout(() => this.thud(pos, 0.5 * strength + 0.2, 90), i * rand(180, 260));
  }

  glass(pos: THREE.Vector3) {
    const c = this.ctx;
    const t = this.now;
    const { node, sp } = this.dest(pos, { ref: 2, gain: 0.7 });
    for (let i = 0; i < 9; i++) {
      const o = c.createOscillator();
      o.type = 'sine';
      o.frequency.value = rand(2500, 7500);
      const g = c.createGain();
      const st = t + rand(0, 0.12);
      g.gain.setValueAtTime(0.0001, st);
      g.gain.linearRampToValueAtTime(0.25, st + 0.002);
      g.gain.exponentialRampToValueAtTime(0.0001, st + rand(0.08, 0.4));
      o.connect(g).connect(node);
      o.start(st);
      o.stop(st + 0.5);
    }
    const n = this.noiseSrc('white', false);
    const hp = c.createBiquadFilter();
    hp.type = 'highpass';
    hp.frequency.value = 2500;
    const ng = c.createGain();
    ng.gain.setValueAtTime(0.9, t);
    ng.gain.exponentialRampToValueAtTime(0.0001, t + 0.25);
    n.connect(hp).connect(ng).connect(node);
    n.start(t);
    n.stop(t + 0.3);
    sp?.dispose(3);
  }

  drip(pos: THREE.Vector3) {
    const c = this.ctx;
    const t = this.now;
    const { node, sp } = this.dest(pos, { ref: 1.2, gain: 0.35, cheap: true });
    const o = c.createOscillator();
    o.type = 'sine';
    const f = rand(900, 1500);
    o.frequency.setValueAtTime(f, t);
    o.frequency.exponentialRampToValueAtTime(f * 2.2, t + 0.04);
    const g = c.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(0.7, t + 0.005);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.12);
    o.connect(g).connect(node);
    o.start(t);
    o.stop(t + 0.15);
    sp?.dispose(2);
  }

  porcelain(pos: THREE.Vector3) {
    const c = this.ctx;
    const t = this.now;
    const { node, sp } = this.dest(pos, { ref: 1.2, gain: 0.5, cheap: true });
    for (const [f, d] of [
      [rand(2800, 3400), 0.25],
      [rand(4200, 5200), 0.15],
    ]) {
      const o = c.createOscillator();
      o.type = 'triangle';
      o.frequency.value = f;
      const g = c.createGain();
      g.gain.setValueAtTime(0.5, t);
      g.gain.exponentialRampToValueAtTime(0.0001, t + d);
      o.connect(g).connect(node);
      o.start(t);
      o.stop(t + d + 0.05);
    }
    sp?.dispose(2);
  }

  giggle(pos: THREE.Vector3) {
    const c = this.ctx;
    const t = this.now;
    const { node, sp } = this.dest(pos, { ref: 1.4, gain: 0.35 });
    for (let i = 0; i < 4; i++) {
      const st = t + i * 0.13;
      const o = c.createOscillator();
      o.type = 'sawtooth';
      o.frequency.setValueAtTime(rand(820, 980) - i * 40, st);
      o.frequency.linearRampToValueAtTime(rand(600, 700), st + 0.1);
      const f = c.createBiquadFilter();
      f.type = 'bandpass';
      f.frequency.value = 2200;
      f.Q.value = 4;
      const g = c.createGain();
      g.gain.setValueAtTime(0.0001, st);
      g.gain.linearRampToValueAtTime(0.6, st + 0.02);
      g.gain.exponentialRampToValueAtTime(0.0001, st + 0.11);
      o.connect(f).connect(g).connect(node);
      o.start(st);
      o.stop(st + 0.13);
    }
    sp?.dispose(3);
  }

  /** inhuman scream when a ghost is repelled */
  shriek(pos: THREE.Vector3 | null, gain = 0.7) {
    const c = this.ctx;
    const t = this.now;
    const { node, sp } = this.dest(pos, { ref: 3, gain });
    const dur = 1.3;
    for (let i = 0; i < 3; i++) {
      const o = c.createOscillator();
      o.type = 'sawtooth';
      const f = rand(380, 520) * (1 + i * 0.47);
      o.frequency.setValueAtTime(f, t);
      o.frequency.exponentialRampToValueAtTime(f * 2.4, t + 0.25);
      o.frequency.exponentialRampToValueAtTime(f * 0.35, t + dur);
      const g = c.createGain();
      g.gain.setValueAtTime(0.0001, t);
      g.gain.linearRampToValueAtTime(0.3, t + 0.05);
      g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      const bp = c.createBiquadFilter();
      bp.type = 'bandpass';
      bp.frequency.value = 1500 + i * 600;
      bp.Q.value = 2;
      o.connect(bp).connect(g).connect(node);
      o.start(t);
      o.stop(t + dur + 0.1);
    }
    const n = this.noiseSrc('white', false);
    const bp = c.createBiquadFilter();
    bp.type = 'bandpass';
    bp.frequency.setValueAtTime(4000, t);
    bp.frequency.exponentialRampToValueAtTime(300, t + dur);
    const ng = c.createGain();
    ng.gain.setValueAtTime(0.5, t);
    ng.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    n.connect(bp).connect(ng).connect(node);
    n.start(t);
    n.stop(t + dur + 0.1);
    sp?.dispose(dur + 3);
  }

  /** dissonant orchestral-ish stab */
  sting(gain = 0.6) {
    const c = this.ctx;
    const t = this.now;
    const { node } = this.dest(null, { bus: 'music', gain: gain * (Settings.data.reduceFlashes ? 0.5 : 1) });
    const freqs = [110, 116.5, 164.8, 233, 311, 466];
    for (const f of freqs) {
      const o = c.createOscillator();
      o.type = 'sawtooth';
      o.frequency.value = f * rand(0.995, 1.005);
      const lp = c.createBiquadFilter();
      lp.type = 'lowpass';
      lp.frequency.setValueAtTime(5000, t);
      lp.frequency.exponentialRampToValueAtTime(300, t + 2.5);
      const g = c.createGain();
      g.gain.setValueAtTime(0.0001, t);
      g.gain.linearRampToValueAtTime(0.12, t + 0.02);
      g.gain.exponentialRampToValueAtTime(0.0001, t + 2.8);
      o.connect(lp).connect(g).connect(node);
      o.start(t);
      o.stop(t + 3);
    }
    this.thud(null, gain * 0.8, 45);
  }

  heartbeat(gain: number, pos: THREE.Vector3 | null = null) {
    const c = this.ctx;
    const t = this.now;
    const { node, sp } = this.dest(pos, { ref: 2, gain, bus: 'sfx', max: 20, rolloff: 0.6 });
    for (const [dt, f, a] of [
      [0, 58, 1],
      [0.16, 50, 0.7],
    ]) {
      const o = c.createOscillator();
      o.frequency.setValueAtTime(f * 1.6, t + dt);
      o.frequency.exponentialRampToValueAtTime(f, t + dt + 0.05);
      const g = c.createGain();
      g.gain.setValueAtTime(0.0001, t + dt);
      g.gain.linearRampToValueAtTime(a, t + dt + 0.01);
      g.gain.exponentialRampToValueAtTime(0.0001, t + dt + 0.18);
      o.connect(g).connect(node);
      o.start(t + dt);
      o.stop(t + dt + 0.25);
    }
    sp?.dispose(2);
  }

  tick(pos: THREE.Vector3) {
    const c = this.ctx;
    const t = this.now;
    const { node, sp } = this.dest(pos, { ref: 0.7, gain: 0.12, cheap: true });
    const o = c.createOscillator();
    o.type = 'square';
    o.frequency.value = 3200;
    const g = c.createGain();
    g.gain.setValueAtTime(0.5, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.012);
    o.connect(g).connect(node);
    o.start(t);
    o.stop(t + 0.02);
    sp?.dispose(1);
  }

  bell(pos: THREE.Vector3 | null, count = 1, gain = 0.4) {
    const c = this.ctx;
    for (let k = 0; k < count; k++) {
      const t = this.now + k * 1.6;
      const { node, sp } = this.dest(pos, { ref: 3, gain });
      const base = 392;
      for (const [r, a, d] of [
        [0.5, 0.35, 5],
        [1, 0.6, 4],
        [2.0, 0.3, 2.5],
        [2.76, 0.2, 2],
        [5.4, 0.08, 1.2],
      ]) {
        const o = c.createOscillator();
        o.frequency.value = base * r;
        const g = c.createGain();
        g.gain.setValueAtTime(0.0001, t);
        g.gain.linearRampToValueAtTime(a, t + 0.005);
        g.gain.exponentialRampToValueAtTime(0.0001, t + d);
        o.connect(g).connect(node);
        o.start(t);
        o.stop(t + d + 0.1);
      }
      sp?.dispose(6);
    }
  }

  breath(pos: THREE.Vector3, gain = 0.5) {
    const c = this.ctx;
    const t = this.now;
    const { node, sp } = this.dest(pos, { ref: 2, gain });
    const n = this.noiseSrc('pink');
    const bp = c.createBiquadFilter();
    bp.type = 'bandpass';
    bp.frequency.setValueAtTime(400, t);
    bp.frequency.linearRampToValueAtTime(900, t + 1.2);
    bp.frequency.linearRampToValueAtTime(300, t + 2.6);
    bp.Q.value = 1.5;
    const g = c.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(0.9, t + 1.0);
    g.gain.linearRampToValueAtTime(0.2, t + 1.4);
    g.gain.linearRampToValueAtTime(0.7, t + 2.0);
    g.gain.linearRampToValueAtTime(0.0001, t + 2.8);
    n.connect(bp).connect(g).connect(node);
    n.start(t);
    n.stop(t + 3);
    sp?.dispose(5);
  }

  crawl(gain = 0.5) {
    const c = this.ctx;
    const t = this.now;
    const { node } = this.dest(null, { gain });
    for (let i = 0; i < 6; i++) {
      const st = t + i * 0.2 + rand(0, 0.05);
      const o = c.createOscillator();
      o.type = 'triangle';
      o.frequency.value = rand(180, 260);
      const g = c.createGain();
      g.gain.setValueAtTime(0.4, st);
      g.gain.exponentialRampToValueAtTime(0.0001, st + 0.15);
      o.connect(g).connect(node);
      o.start(st);
      o.stop(st + 0.2);
    }
  }

  /** soft murmur for Clara's lines (formant babble), positional */
  voice(pos: THREE.Vector3, syllables: number, kind: string, pitch = 1) {
    const c = this.ctx;
    let t = this.now;
    const { node, sp } = this.dest(pos, { ref: 1.6, gain: kind === 'whisper' ? 0.18 : kind === 'call' ? 0.42 : 0.3, bus: 'voice' });
    const base = (kind === 'scared' ? 260 : kind === 'call' ? 250 : 215) * pitch;
    const o = c.createOscillator();
    o.type = 'sawtooth';
    const f1 = c.createBiquadFilter();
    f1.type = 'bandpass';
    f1.Q.value = 6;
    const f2 = c.createBiquadFilter();
    f2.type = 'bandpass';
    f2.Q.value = 8;
    const g = c.createGain();
    g.gain.value = 0;
    const mix = c.createGain();
    o.connect(f1).connect(mix);
    o.connect(f2).connect(mix);
    mix.connect(g).connect(node);
    if (kind === 'whisper') {
      o.disconnect();
      const n = this.noiseSrc('white');
      n.connect(f1);
      n.connect(f2);
      n.start(t);
      n.stop(t + syllables * 0.2 + 0.4);
    }
    const formants: [number, number][] = [
      [800, 1200],
      [400, 2000],
      [300, 2300],
      [600, 1000],
      [500, 1700],
    ];
    o.frequency.setValueAtTime(base, t);
    const n = Math.min(14, syllables);
    for (let i = 0; i < n; i++) {
      const [a, b] = choose(formants);
      const st = t + i * 0.17;
      f1.frequency.setTargetAtTime(a, st, 0.02);
      f2.frequency.setTargetAtTime(b, st, 0.02);
      o.frequency.setTargetAtTime(base * (1 + Math.sin(i * 1.3) * 0.08) * (kind === 'call' && i === n - 1 ? 1.35 : 1), st, 0.03);
      g.gain.setTargetAtTime(0.5, st, 0.015);
      g.gain.setTargetAtTime(0.08, st + 0.11, 0.02);
    }
    const end = t + n * 0.17 + 0.1;
    g.gain.setTargetAtTime(0.0001, end, 0.04);
    o.start(t);
    o.stop(end + 0.3);
    sp?.dispose(n * 0.17 + 3);
    t = end;
  }

  /* ============================================================ loops */

  loop(kind: 'static' | 'whisper' | 'water' | 'fridge' | 'wind' | 'rumble' | 'drone' | 'hum' | 'rain', pos: THREE.Vector3 | null, o: SpatialOpts = {}): LoopHandle {
    const c = this.ctx;
    const out = c.createGain();
    out.gain.value = 0;
    let sp: Spatial | null = null;
    if (pos) {
      sp = new Spatial(this, pos, { ref: o.ref ?? 1.4, max: o.max, rolloff: o.rolloff, bus: o.bus ?? 'sfx', gain: o.gain ?? 1 });
      out.connect(sp.input);
    } else out.connect(this.bus(o.bus ?? 'amb'));
    const stoppers: AudioScheduledSourceNode[] = [];
    const start = (s: AudioScheduledSourceNode) => {
      s.start();
      stoppers.push(s);
    };
    if (kind === 'static') {
      const n = this.noiseSrc('white');
      const bp = c.createBiquadFilter();
      bp.type = 'bandpass';
      bp.frequency.value = 2600;
      bp.Q.value = 0.4;
      const crackle = c.createGain();
      const lfo = c.createOscillator();
      lfo.type = 'square';
      lfo.frequency.value = 11;
      const lg = c.createGain();
      lg.gain.value = 0.3;
      lfo.connect(lg).connect(crackle.gain);
      crackle.gain.value = 0.6;
      n.connect(bp).connect(crackle).connect(out);
      start(n);
      start(lfo);
    } else if (kind === 'whisper') {
      const n = this.noiseSrc('pink');
      const f1 = c.createBiquadFilter();
      f1.type = 'bandpass';
      f1.Q.value = 7;
      const f2 = c.createBiquadFilter();
      f2.type = 'bandpass';
      f2.Q.value = 9;
      const g = c.createGain();
      g.gain.value = 0.9;
      n.connect(f1).connect(g);
      n.connect(f2).connect(g);
      g.connect(out);
      const syll = c.createOscillator();
      syll.frequency.value = 4.5;
      const sg = c.createGain();
      sg.gain.value = 0.7;
      syll.connect(sg).connect(g.gain);
      const mod = c.createOscillator();
      mod.frequency.value = 0.9;
      const mg = c.createGain();
      mg.gain.value = 600;
      mod.connect(mg).connect(f1.frequency);
      f1.frequency.value = 900;
      const mod2 = c.createOscillator();
      mod2.frequency.value = 1.3;
      const mg2 = c.createGain();
      mg2.gain.value = 900;
      mod2.connect(mg2).connect(f2.frequency);
      f2.frequency.value = 2200;
      start(n);
      start(syll);
      start(mod);
      start(mod2);
    } else if (kind === 'water') {
      const n = this.noiseSrc('pink');
      const bp = c.createBiquadFilter();
      bp.type = 'bandpass';
      bp.frequency.value = 1200;
      bp.Q.value = 0.5;
      const hp = c.createBiquadFilter();
      hp.type = 'highpass';
      hp.frequency.value = 350;
      n.connect(bp).connect(hp).connect(out);
      start(n);
    } else if (kind === 'rain') {
      // a bed of drops on the roof and leaves, plus a hissy top
      const n = this.noiseSrc('pink');
      const hp = c.createBiquadFilter();
      hp.type = 'highpass';
      hp.frequency.value = 650;
      const lp = c.createBiquadFilter();
      lp.type = 'lowpass';
      lp.frequency.value = 7500;
      const g = c.createGain();
      g.gain.value = 0.9;
      const n2 = this.noiseSrc('white');
      const bp = c.createBiquadFilter();
      bp.type = 'bandpass';
      bp.frequency.value = 3800;
      bp.Q.value = 0.5;
      const g2 = c.createGain();
      g2.gain.value = 0.16;
      const lfo = c.createOscillator();
      lfo.frequency.value = 0.11;
      const lg = c.createGain();
      lg.gain.value = 0.18;
      lfo.connect(lg).connect(g.gain);
      n.connect(hp).connect(lp).connect(g).connect(out);
      n2.connect(bp).connect(g2).connect(out);
      start(n);
      start(n2);
      start(lfo);
    } else if (kind === 'fridge' || kind === 'hum') {
      for (const f of kind === 'fridge' ? [60, 120, 181] : [50, 100]) {
        const os = c.createOscillator();
        os.frequency.value = f;
        const g = c.createGain();
        g.gain.value = f === 60 || f === 50 ? 0.4 : 0.12;
        os.connect(g).connect(out);
        start(os);
      }
    } else if (kind === 'wind') {
      const n = this.noiseSrc('brown');
      const bp = c.createBiquadFilter();
      bp.type = 'bandpass';
      bp.frequency.value = 420;
      bp.Q.value = 0.7;
      const lfo = c.createOscillator();
      lfo.frequency.value = 0.07;
      const lg = c.createGain();
      lg.gain.value = 220;
      lfo.connect(lg).connect(bp.frequency);
      const g = c.createGain();
      g.gain.value = 0.8;
      const lfo2 = c.createOscillator();
      lfo2.frequency.value = 0.13;
      const lg2 = c.createGain();
      lg2.gain.value = 0.4;
      lfo2.connect(lg2).connect(g.gain);
      n.connect(bp).connect(g).connect(out);
      start(n);
      start(lfo);
      start(lfo2);
    } else if (kind === 'rumble') {
      const os = c.createOscillator();
      os.type = 'sawtooth';
      os.frequency.value = 33;
      const lp = c.createBiquadFilter();
      lp.type = 'lowpass';
      lp.frequency.value = 140;
      const ws = c.createWaveShaper();
      const curve = new Float32Array(256);
      for (let i = 0; i < 256; i++) {
        const x = (i / 255) * 2 - 1;
        curve[i] = Math.tanh(x * 3);
      }
      ws.curve = curve;
      const n = this.noiseSrc('brown');
      const nlp = c.createBiquadFilter();
      nlp.type = 'lowpass';
      nlp.frequency.value = 120;
      const lfo = c.createOscillator();
      lfo.frequency.value = 0.3;
      const lg = c.createGain();
      lg.gain.value = 4;
      lfo.connect(lg).connect(os.frequency);
      os.connect(ws).connect(lp).connect(out);
      n.connect(nlp).connect(out);
      start(os);
      start(n);
      start(lfo);
    } else if (kind === 'drone') {
      for (const f of [55, 55.4, 82.4]) {
        const os = c.createOscillator();
        os.type = 'sawtooth';
        os.frequency.value = f;
        const lp = c.createBiquadFilter();
        lp.type = 'lowpass';
        lp.frequency.value = 180;
        const g = c.createGain();
        g.gain.value = 0.18;
        os.connect(lp).connect(g).connect(out);
        start(os);
      }
    }
    const h: LoopHandle = {
      sp,
      out,
      level: 0,
      setLevel: (v: number) => {
        h.level = v;
        out.gain.setTargetAtTime(Math.max(0, v), c.currentTime, 0.15);
      },
      setPos: (p: THREE.Vector3) => sp?.setPos(p),
      stop: (fade = 0.3) => {
        out.gain.setTargetAtTime(0, c.currentTime, fade / 3);
        setTimeout(() => {
          for (const s of stoppers)
            try {
              s.stop();
            } catch {
              /* */
            }
          sp?.dispose(0);
        }, fade * 1000 + 200);
      },
    };
    return h;
  }

  ui(kind: 'hover' | 'select' | 'back') {
    if (!this.started) return;
    const c = this.ctx;
    const t = this.now;
    const { node } = this.dest(null, { bus: 'ui', gain: 0.25 });
    const o = c.createOscillator();
    o.type = 'sine';
    const f = kind === 'hover' ? 880 : kind === 'select' ? 660 : 440;
    o.frequency.setValueAtTime(f, t);
    if (kind === 'select') o.frequency.exponentialRampToValueAtTime(f * 1.5, t + 0.08);
    const g = c.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(kind === 'hover' ? 0.15 : 0.4, t + 0.005);
    g.gain.exponentialRampToValueAtTime(0.0001, t + (kind === 'hover' ? 0.06 : 0.2));
    o.connect(g).connect(node);
    o.start(t);
    o.stop(t + 0.25);
  }
}

/* ================================================================ music */

export class Music {
  private drone: LoopHandle | null = null;
  private tension: LoopHandle | null = null;
  private pianoTimer = 0;
  private mode: 'none' | 'menu' | 'morning' | 'afternoon' | 'night' | 'ending' = 'none';
  level = 0;
  private chord = 0;
  private padNodes: { o: OscillatorNode; g: GainNode }[] = [];

  constructor(private a: AudioEngine) {}

  setMode(m: Music['mode']) {
    if (m === this.mode) return;
    this.mode = m;
    this.stopPad();
    if (m === 'night' || m === 'menu') {
      if (!this.drone) this.drone = this.a.loop('drone', null, { bus: 'music' });
      this.drone.setLevel(m === 'menu' ? 0.35 : 0.5);
      if (!this.tension) this.tension = this.makeTension();
    } else {
      this.drone?.setLevel(0);
      this.tension?.setLevel(0);
    }
    if (m === 'afternoon') this.startPad();
  }

  private makeTension(): LoopHandle {
    const a = this.a;
    const c = a.ctx;
    const out = c.createGain();
    out.gain.value = 0;
    out.connect(a.bus('music'));
    const nodes: AudioScheduledSourceNode[] = [];
    for (const f of [466.2, 493.9, 698.5]) {
      const o = c.createOscillator();
      o.type = 'triangle';
      o.frequency.value = f;
      const g = c.createGain();
      g.gain.value = 0.05;
      const trem = c.createOscillator();
      trem.frequency.value = rand(3, 6);
      const tg = c.createGain();
      tg.gain.value = 0.03;
      trem.connect(tg).connect(g.gain);
      o.connect(g).connect(out);
      o.start();
      trem.start();
      nodes.push(o, trem);
    }
    const n = a.noiseSrc('pink');
    const bp = c.createBiquadFilter();
    bp.type = 'bandpass';
    bp.frequency.value = 3000;
    bp.Q.value = 3;
    const ng = c.createGain();
    ng.gain.value = 0.15;
    n.connect(bp).connect(ng).connect(out);
    n.start();
    nodes.push(n);
    out.connect(a.reverbSend);
    const h: LoopHandle = {
      sp: null,
      out,
      level: 0,
      setLevel: (v) => {
        h.level = v;
        out.gain.setTargetAtTime(v, c.currentTime, 0.6);
      },
      setPos: () => {},
      stop: () => nodes.forEach((s) => s.stop()),
    };
    return h;
  }

  private startPad() {
    const c = this.a.ctx;
    for (const f of [130.8, 196, 246.9, 329.6]) {
      const o = c.createOscillator();
      o.type = 'triangle';
      o.frequency.value = f;
      const g = c.createGain();
      g.gain.value = 0;
      g.gain.setTargetAtTime(0.035, c.currentTime, 2);
      o.connect(g).connect(this.a.bus('music'));
      g.connect(this.a.reverbSend);
      o.start();
      this.padNodes.push({ o, g });
    }
  }

  private stopPad() {
    const c = this.a.ctx;
    for (const p of this.padNodes) {
      p.g.gain.setTargetAtTime(0, c.currentTime, 0.8);
      const o = p.o;
      setTimeout(() => o.stop(), 4000);
    }
    this.padNodes = [];
  }

  private note(freq: number, vel: number, dur = 2.6) {
    const a = this.a;
    const c = a.ctx;
    const t = c.currentTime + 0.02;
    const { node } = a.dest(null, { bus: 'music', gain: vel });
    for (const [r, amp] of [
      [1, 0.6],
      [2, 0.22],
      [3, 0.08],
      [4.01, 0.04],
    ]) {
      const o = c.createOscillator();
      o.type = 'sine';
      o.frequency.value = freq * r;
      const g = c.createGain();
      g.gain.setValueAtTime(0.0001, t);
      g.gain.linearRampToValueAtTime(amp, t + 0.008);
      g.gain.exponentialRampToValueAtTime(0.0001, t + dur / r);
      o.connect(g).connect(node);
      o.start(t);
      o.stop(t + dur + 0.1);
    }
  }

  update(dt: number, tension: number) {
    this.level = tension;
    if (this.mode === 'night') {
      this.tension?.setLevel(clamp(tension) * 0.9);
      this.drone?.setLevel(0.35 + tension * 0.35);
    }
    if (this.mode === 'menu' || this.mode === 'morning' || this.mode === 'ending' || this.mode === 'afternoon') {
      this.pianoTimer -= dt;
      if (this.pianoTimer <= 0) {
        // gentle, slightly melancholic progression (Am - F - C - G)
        const chords = [
          [220, 261.6, 329.6],
          [174.6, 220, 261.6],
          [130.8, 196, 261.6],
          [196, 246.9, 293.7],
        ];
        const ch = chords[this.chord % chords.length];
        const mel = [440, 493.9, 523.3, 587.3, 659.3, 783.99];
        const v = this.mode === 'menu' ? 0.14 : 0.1;
        this.note(ch[0] / 2, v * 0.9, 4);
        setTimeout(() => this.note(choose(ch), v * 0.7), 450);
        setTimeout(() => this.note(choose(ch) * 2, v * 0.55), 900);
        if (Math.random() < 0.7) setTimeout(() => this.note(choose(mel), v * 0.6, 3), 1350);
        this.chord++;
        this.pianoTimer = this.mode === 'afternoon' ? 4.5 : 3.6;
      }
    }
  }
}
