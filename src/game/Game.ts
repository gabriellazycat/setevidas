import * as THREE from 'three';
import { GameRenderer } from '../render/Renderer';
import { Sky, type SkyLook } from '../render/Sky';
import { Shared, updateSpectral } from '../render/Materials';
import { textures } from '../render/Textures';
import { House } from '../world/House';
import { InteractionSystem, type Interactable } from '../world/Interactables';
import type { HideSpot } from '../world/Layout';
import { roomAt } from '../world/NavGraph';
import { CAT_START, ROOM_BY_ID, SPOTS, RITUAL_CENTER, type RoomId } from '../world/Layout';
import { Cat } from '../actors/Cat';
import { CameraRig } from '../actors/CameraRig';
import { Owner, DAVI_CONFIG, type Step } from '../actors/Owner';
import { Household } from './Household';
import { Input } from '../core/Input';
import { Settings } from '../core/Settings';
import { AudioEngine, Music, type LoopHandle } from '../audio/Audio';
import { UI } from '../ui/UI';
import { Director } from '../threats/Director';
import { LAST_NIGHT, DAVI_DAY, NIGHT_LENGTH_MIN } from './Config';
import { registerInteractions, ritualSlot } from './Interactions';
import type { World, ThreatId, Fx } from './World';
import { INTRO_CARDS, THREAT_INFO, MORNING_TASKS, DAY_SCENES, DIARY_LINES, ENDINGS } from './Story';
import {
  type SaveData,
  type Snapshot,
  type WorldFlags,
  type ClueId,
  newGameSave,
  loadSave,
  writeSave,
  clone,
  freshFlags,
} from '../core/Save';
import { Weather, WEATHER, CLEAR_DAY } from '../render/Weather';
import { Atmosphere } from '../render/Atmosphere';
import { Ambient } from './Ambient';
import { clamp, damp, lerp, smoothstep, rand, choose, formatClock } from '../core/math';

type Phase = 'none' | 'morning' | 'afternoon' | 'night';
type Mode = 'boot' | 'menu' | 'play' | 'paused' | 'over';
type Env = 'night' | 'morning' | 'afternoon' | 'dawn' | 'menu';

const MOON_DIR = new THREE.Vector3(-0.42, 0.6, -0.68).normalize();
const SUN_MORNING = new THREE.Vector3(0.62, 0.6, -0.5).normalize();
const SUN_AFTERNOON = new THREE.Vector3(-0.82, 0.3, -0.48).normalize();
const MORNING_LEN = 240;
const CLUES: ClueId[] = ['foto', 'coleira', 'chave'];

interface AfternoonState {
  pets: number;
  petCd: number;
  fed: boolean;
  played: boolean;
  bowlFilled: boolean;
  scene: string;
  bathing: boolean;
  bathT: number;
  canSkip: boolean;
  ending: boolean;
}

export class Game {
  scene = new THREE.Scene();
  camera = new THREE.PerspectiveCamera(68, innerWidth / innerHeight, 0.08, 260);
  gr: GameRenderer;
  input: Input;
  audio: AudioEngine;
  music: Music;
  ui: UI;
  house!: House;
  cat!: Cat;
  owner!: Owner;
  davi!: Owner;
  household!: Household;
  rig: CameraRig;
  director!: Director;
  inter = new InteractionSystem();
  sky!: Sky;
  sun = new THREE.DirectionalLight('#9fb6ff', 1.4);
  hemi = new THREE.HemisphereLight('#5a6f9a', '#2a2420', 1.1);
  world!: World;
  save: SaveData = newGameSave();
  flags: WorldFlags = freshFlags();

  mode: Mode = 'boot';
  phase: Phase = 'none';
  day = 1;
  hour = 0;
  phaseT = 0;
  nightLen = 360;
  controls = false;
  private lastT = performance.now();
  private fx = { flash: 0, flashColor: new THREE.Color(1, 1, 1), distort: 0, ca: 0, fade: 1, fadeTarget: 1, fadeSpeed: 1.5, letterbox: 0, letterTarget: 0 };
  private lock = { active: false, t: 0 };
  private stats = { repelled: 0, maxFear: 0, locked: 0, caught: 0 };
  aft: AfternoonState = this.freshAft();
  private holdT = 0;
  private holdTarget: Interactable | null = null;
  private heartT = 0;
  private catHeartT = 0;
  pulse = 0;
  weather!: Weather;
  atmos!: Atmosphere;
  ambient!: Ambient;
  private sunBase = 1.35;
  private hemiBase = 1.05;
  private rainLoopOn = false;
  private tickT = 0;
  private creakT = 10;
  private lastHour = 0;
  private wind: LoopHandle | null = null;
  private fridge: LoopHandle | null = null;
  private purrLoop: LoopHandle | null = null;
  private introduced = new Set<ThreatId>();
  private hintsShown = new Set<string>();
  private failing = false;
  private winning = false;
  private ownerWakes: { who: Owner; at: number; kind: 'water' | 'toilet'; done: boolean }[] = [];
  private infoHeld = 0;
  private menuT = 0;
  private dawnT = 0;
  private envTarget: Env = 'night';
  private lockedOutPrompt = false;
  private transitioning = false;
  private passageT = 0;
  private envGamma = 1;

  constructor(private container: HTMLElement) {
    this.gr = new GameRenderer(container, this.scene, this.camera);
    this.gr.onResize = (w, h) => {
      this.camera.aspect = w / h;
      this.camera.updateProjectionMatrix();
    };
    this.gr.resize();
    this.input = new Input(this.gr.renderer.domElement);
    this.audio = new AudioEngine();
    this.music = new Music(this.audio);
    this.ui = new UI(container);
    this.ui.onSound = (k) => this.audio.ui(k);
    this.rig = new CameraRig(this.camera);
    this.gr.renderer.domElement.addEventListener('click', () => {
      if (this.mode === 'play' && !this.ui.overlayOpen) this.input.requestLock();
    });
    this.input.onPointerLockChange = (locked) => {
      if (!locked && this.mode === 'play' && !this.ui.overlayOpen) this.pause();
      this.ui.showClickToPlay(false);
    };
    document.addEventListener('visibilitychange', () => {
      if (document.hidden && this.mode === 'play') this.pause();
    });
  }

  private freshAft(): AfternoonState {
    return { pets: 0, petCd: 0, fed: false, played: false, bowlFilled: false, scene: '', bathing: false, bathT: 0, canSkip: false, ending: false };
  }

  /* ================================================================ boot */

  async boot() {
    this.ui.showLoading();
    const step = (p: number, msg: string) =>
      new Promise<void>((r) => {
        this.ui.loading(p, msg);
        setTimeout(r, 30);
      });
    await step(0.05, 'Pintando as paredes');
    textures();
    await step(0.2, 'Construindo a casa');
    this.house = new House(this.scene);
    await step(0.45, 'Acordando o gato');
    this.cat = new Cat(this.scene);
    this.owner = new Owner(this.scene, this.house.nav, [...this.house.doors.values()]);
    this.davi = new Owner(this.scene, this.house.nav, [...this.house.doors.values()], DAVI_CONFIG);
    this.davi.present = false;
    this.davi.hide();
    this.household = new Household(this.owner, this.davi);
    this.sky = new Sky(this.scene, textures().moon);
    this.weather = new Weather(this.scene, this.audio);
    this.atmos = new Atmosphere(this.scene);
    this.ambient = new Ambient(this.scene);
    this.weather.onFlash = (pw) => {
      if (Settings.data.reduceFlashes) return;
      this.fx.flash = Math.max(this.fx.flash, 0.12 * pw);
      this.fx.flashColor.set('#bcd0ff');
    };
    this.scene.add(this.sun, this.sun.target, this.hemi);
    this.sun.castShadow = true;
    this.sun.shadow.mapSize.set(this.gr.shadowSize(), this.gr.shadowSize());
    const sc = this.sun.shadow.camera;
    sc.left = -17;
    sc.right = 17;
    sc.top = 17;
    sc.bottom = -17;
    sc.near = 1;
    sc.far = 100;
    this.sun.shadow.bias = -0.0004;
    this.sun.shadow.normalBias = 0.025;
    this.sun.target.position.set(6, 1, 5);
    Settings.onChange(() => {
      const s = this.gr.shadowSize();
      if (this.sun.shadow.mapSize.x !== s) {
        this.sun.shadow.mapSize.set(s, s);
        this.sun.shadow.map?.dispose();
        this.sun.shadow.map = null as unknown as THREE.WebGLRenderTarget;
      }
      this.owner.catName = Settings.data.catName;
      this.davi.catName = Settings.data.catName;
    });
    this.owner.catName = Settings.data.catName;
    this.davi.catName = Settings.data.catName;
    await step(0.6, 'Chamando as assombrações');
    this.world = this.makeWorld();
    this.house.lights.onWarn = (l) => this.audio.buzz(l.light.position, 3.2);
    this.house.lights.onBurnOut = (l) => {
      this.audio.click(l.light.position, 0.6);
      this.hintOnce('burn', 'As lâmpadas queimam sozinhas depois de 10–20 s. Pule no interruptor de novo para religar.');
    };
    this.director = new Director(this.world);
    this.director.thing.onWave = (hit) => this.onThingWave(hit);
    this.director.hound.events.onCaught = (h) => this.onHoundCaught(h.pos);
    registerInteractions(this);
    this.wireEvents();
    await step(0.75, 'Compilando sombras');
    this.applyEnv('menu', true);
    this.setupMenuScene();
    // precompile every material so nothing hitches the first time it appears
    const hidden: THREE.Object3D[] = [];
    this.scene.traverse((o) => {
      if (!o.visible) {
        hidden.push(o);
        o.visible = true;
      }
    });
    try {
      await this.gr.renderer.compileAsync(this.scene, this.camera);
    } catch {
      this.gr.renderer.compile(this.scene, this.camera);
    }
    for (const o of hidden) o.visible = false;
    await step(0.95, 'Apagando as luzes');
    this.gr.render(0.016);
    await step(1, 'Pronto');
    this.ui.hideLoading();
    this.toMenu();
    this.loop();
  }

  private makeWorld(): World {
    const g = this;
    const fx: Fx = {
      shake: (a) => g.rig.shake(a),
      sting: (a = 0.6) => g.audio.sting(a),
      flash: (a, c = '#ffffff') => {
        if (Settings.data.reduceFlashes) a *= 0.2;
        g.fx.flash = Math.max(g.fx.flash, a);
        g.fx.flashColor.set(c);
      },
      distort: (a) => (g.fx.distort = Math.max(g.fx.distort, Settings.data.reduceFlashes ? a * 0.3 : a)),
      ca: (a) => (g.fx.ca = Math.max(g.fx.ca, a)),
    };
    return {
      scene: this.scene,
      camera: this.camera,
      house: this.house,
      owner: this.owner,
      household: this.household,
      pickTarget: (id) => this.household.pickTarget(id, this.director.all.filter((t) => t.enabled && t.stage >= 3).map((t) => t.target)),
      cat: this.cat,
      audio: this.audio,
      fx,
      night: 1,
      speed: 1,
      hour: 0,
      roomOf: (p) => roomAt(p),
      hops: (a, b) => {
        const ra = roomAt(a);
        const rb = roomAt(b);
        if (!ra || !rb) return 3;
        return this.house.nav.hops(ra, rb);
      },
      isObserved: (p, need) => this.isObserved(p, need),
      introduce: (id) => this.introduce(id),
      hint: (text, dur = 4) => this.ui.say('', text, dur, 'ghost'),
      repelled: (id) => {
        this.stats.repelled++;
        this.save.stats.threatsRepelled++;
        if (!this.hintsShown.has(`rep_${id}`) && this.day === 1) {
          this.hintsShown.add(`rep_${id}`);
          setTimeout(() => this.hintOnce('after_rep', 'Ela vai voltar. Proteja Clara até as <b>06:00</b>.'), 1500);
        }
      },
      get catName() {
        return Settings.data.catName;
      },
    };
  }

  private wireEvents() {
    const a = this.audio;
    const cat = this.cat;
    cat.events.step = (run, sneak) => {
      const room = roomAt(cat.pos);
      const floor = room ? ROOM_BY_ID[room].floor : 'floor_wood';
      const surface = floor.includes('tile') || floor.includes('checker') ? 'tile' : floor.includes('concrete') ? 'concrete' : 'wood';
      a.pawStep(cat.pos, run, sneak, surface);
      if (run && this.phase === 'night') {
        this.emitNoise(cat.pos, 0.12, 'run');
        this.director.hound.hearNoise(cat.pos, 0.22, 'run');
      }
    };
    cat.events.jump = () => a.pawStep(cat.pos, true, false);
    cat.events.land = (imp) => {
      a.thud(cat.pos, clamp(imp / 14, 0.05, 0.25), 120);
      if (imp > 7 && this.phase === 'night') this.emitNoise(cat.pos, 0.2, 'thud');
    };
    cat.events.meow = () => {
      a.meow(cat.head.clone(), cat.mode === 'purr' ? 0.9 : 1);
      if (this.phase === 'night') this.director.hearNoise(cat.pos, 0.7, 'meow');
      if (this.phase === 'night' || this.phase === 'afternoon') {
        for (const who of this.household.present) {
          const hops = this.world.hops(cat.pos, who.pos);
          const r = who.hearMeow(cat.pos, hops);
          if (r === 'trance') this.hintOnce('trance', `Seu miado tirou ${who.name} do transe. Mas o problema continua lá.`);
          if (r === 'coming' || r === 'woke') this.hintOnce('call', `Miar chama as pessoas até você. Use isso para tirá-las de perigo, mas elas andam pela casa escura.`);
        }
      }
    };
    cat.events.hiss = (strong) => {
      a.hiss(cat.head.clone(), strong);
      if (!strong) this.hintOnce('weakhiss', 'Pouco <b>Foco</b>: o bufo saiu fraco. O Foco recarrega quando você não usa a Visão de Gato.');
      const hit = this.director.hiss(cat.pos, strong);
      if (hit) this.fxCa(0.6);
    };
    for (const who of [this.owner, this.davi]) {
      who.events.say = (text, dur, kind, from) => {
        this.ui.say(from.name, text, dur, kind === 'read' ? 'narrator' : kind);
        a.voice(from.headPos(), Math.ceil(text.length / 5), kind, from.cfg.voicePitch);
      };
      who.events.step = (p) => a.humanStep(p, Math.random() < 0.12);
      who.events.door = (d) => a.creak(d.center(new THREE.Vector3()).add(new THREE.Vector3(0, 1, 0)), 0.3, 0.9);
      who.events.lamp = (from) => {
        const sh = this.director.shadow;
        if (sh.enabled && sh.stage >= 3 && sh.target === from && sh.room === from.cfg.bedRoom) return;
        const lamp = this.house.lights.get(from.cfg.lampIndex);
        if (!lamp.on && lamp.dead <= 0) {
          lamp.setOn(true);
          a.click(lamp.light.position, 0.4);
        }
      };
    }
    this.house.props.onNoise = (e) => {
      if (e.kind === 'break') a.glass(e.pos);
      else a.thud(e.pos, 0.3 * e.loudness + 0.1, 140);
      this.emitNoise(e.pos, e.loudness, e.kind);
    };
    for (const d of this.house.doors.values()) d.onMove = (door, opening) => {
      if (opening && Math.random() < 0.6) a.creak(door.center(new THREE.Vector3()).add(new THREE.Vector3(0, 1.2, 0)), 0.18, 0.7);
    };
  }

  /* ================================================================ environment */

  applyEnv(env: Env, instant = false) {
    this.envTarget = env;
    const s = this.sky;
    let look: SkyLook;
    let sunDir = MOON_DIR;
    const h = this.house;
    const u = this.gr.u;
    if (env === 'night' || env === 'menu') {
      look = { top: '#02040a', horizon: '#121a28', bottom: '#040508', stars: 1, sunDir: MOON_DIR, sunColor: '#8fa6ff', sunSize: 0, moon: 1 };
      this.sun.color.set('#9cb4ff');
      this.sun.intensity = 1.35;
      this.hemi.color.set('#7d8db4');
      this.hemi.groundColor.set('#2c251f');
      this.hemi.intensity = 1.05;
      this.envGamma = 1.1;
      this.scene.fog = new THREE.FogExp2('#0a0f17', 0.016);
      this.gr.renderer.toneMappingExposure = 1.15;
      h.buildShafts(MOON_DIR.clone().negate(), '#a9bfff', 0.055);
      h.lights.get(13).setOn(true);
      u.uTint.value.set(0.93, 0.98, 1.08);
      u.uLift.value.set(0.004, 0.009, 0.019);
      u.uSat.value = 0.92;
    } else if (env === 'morning') {
      sunDir = SUN_MORNING;
      look = { top: '#4f7fb8', horizon: '#c9d6de', bottom: '#4c5442', stars: 0, sunDir, sunColor: '#fff0d0', sunSize: 1, moon: 0 };
      this.sun.color.set('#ffefd6');
      this.sun.intensity = 4.6;
      this.hemi.color.set('#d6e2f0');
      this.hemi.groundColor.set('#8a7458');
      this.hemi.intensity = 3.1;
      this.envGamma = 1.1;
      this.scene.fog = new THREE.FogExp2('#b4c2cc', 0.006);
      this.gr.renderer.toneMappingExposure = 1.0;
      h.buildShafts(sunDir.clone().negate(), '#ffe9c2', 0.075);
      h.lights.get(13).setOn(false);
      u.uTint.value.set(1.03, 1.0, 0.95);
      u.uLift.value.set(0.006, 0.005, 0.004);
      u.uSat.value = 1.0;
    } else if (env === 'afternoon') {
      sunDir = SUN_AFTERNOON;
      look = { top: '#33467a', horizon: '#f2a464', bottom: '#3a302c', stars: 0.15, sunDir, sunColor: '#ffa860', sunSize: 1.6, moon: 0 };
      this.sun.color.set('#ffb070');
      this.sun.intensity = 3.6;
      this.hemi.color.set('#b4a2bc');
      this.hemi.groundColor.set('#6a4a36');
      this.hemi.intensity = 2.1;
      this.envGamma = 1.08;
      this.scene.fog = new THREE.FogExp2('#5f4f55', 0.01);
      this.gr.renderer.toneMappingExposure = 1.0;
      h.buildShafts(sunDir.clone().negate(), '#ffb066', 0.1);
      h.lights.get(13).setOn(true);
      u.uTint.value.set(1.08, 0.98, 0.9);
      u.uLift.value.set(0.008, 0.004, 0.002);
      u.uSat.value = 1.02;
    } else {
      // dawn
      sunDir = new THREE.Vector3(0.7, 0.18, -0.6).normalize();
      look = { top: '#2d3b66', horizon: '#e79a7c', bottom: '#2a2626', stars: 0.2, sunDir, sunColor: '#ffb28a', sunSize: 1.2, moon: 0.3 };
      this.sun.color.set('#ffc0a0');
      this.sun.intensity = 1.8;
      this.hemi.color.set('#8890b0');
      this.hemi.groundColor.set('#3a302a');
      this.hemi.intensity = 1.5;
      this.envGamma = 1.08;
      this.scene.fog = new THREE.FogExp2('#4a4450', 0.012);
      h.buildShafts(sunDir.clone().negate(), '#ffc0a0', 0.07);
      h.lights.get(13).setOn(false);
      u.uTint.value.set(1.05, 0.98, 0.96);
      u.uLift.value.set(0.006, 0.004, 0.004);
    }
    h.lights.get(16).setOn(env === 'night');
    s.setLook(look, env === 'night' || env === 'menu' || env === 'dawn' ? MOON_DIR : sunDir);
    this.sun.position.copy(this.sun.target.position).addScaledVector(env === 'night' || env === 'menu' ? MOON_DIR : sunDir, 45);
    this.scene.background = null;
    (h.dust.material as THREE.ShaderMaterial).uniforms.uAmt.value = env === 'morning' ? 1.2 : env === 'afternoon' ? 1.0 : 0.45;
    this.sunBase = this.sun.intensity;
    this.hemiBase = this.hemi.intensity;
    this.weather?.setWeather(env === 'night' ? WEATHER[this.world.night] ?? WEATHER[1] : env === 'menu' ? WEATHER[3] : CLEAR_DAY);
    if (this.atmos) this.atmos.fogAmount = env === 'night' ? Math.min(1, 0.3 + this.world.night * 0.1) : 0.2;
    void instant;
  }

  /* ================================================================ menu */

  private setupMenuScene() {
    this.director?.stopAll();
    this.house.lights.setAll(false);
    this.house.lights.get(8).setOn(true);
    this.house.lights.get(8).level = 1;
    this.owner.setNight(true);
    this.owner.putInBed(true);
    this.owner.show();
    this.house.setBlanket(true);
    this.cat.teleport(new THREE.Vector3(11.55, 4.02, 0.0), Math.PI * 0.9);
    this.cat.mode = 'frozen';
    this.cat.pose.sit = 1;
  }

  toMenu() {
    this.mode = 'menu';
    this.phase = 'none';
    this.controls = false;
    this.input.exitLock();
    this.audio.setMuffle(0);
    this.applyEnv('menu');
    this.setupMenuScene();
    this.music.setMode('menu');
    this.ensureAmbience();
    this.ui.hudVisible(false);
    this.ui.clearHints();
    this.fx.fadeTarget = 0;
    this.fx.letterTarget = 0;
    const save = loadSave();
    const unlocked = save?.unlockedNight ?? 1;
    const label = save ? (save.current.phase === 'night' ? `Noite ${save.current.day}` : `Dia ${save.current.day} · manhã`) : '';
    this.ui.showMenu({
      canContinue: !!save,
      continueLabel: label,
      unlocked,
      onNew: () => this.newGame(),
      onContinue: () => this.continueGame(),
      onNight: (n) => this.startAtNight(n),
      onSettings: () => this.ui.showSettings(() => this.toMenu()),
      onCredits: () => this.ui.showCredits(() => this.toMenu()),
    });
  }

  private ensureAmbience() {
    if (!this.wind) this.wind = this.audio.loop('wind', null, { bus: 'amb' });
    if (!this.fridge) this.fridge = this.audio.loop('fridge', new THREE.Vector3(7.9, 1.0, 3.9), { ref: 0.8, gain: 0.5, bus: 'amb' });
    this.wind.setLevel(this.phase === 'morning' ? 0.12 : 0.3);
    this.fridge.setLevel(0.25);
  }

  private newGame() {
    this.ui.closeOverlay();
    const prev = loadSave();
    this.save = newGameSave();
    if (prev) {
      this.save.unlockedNight = prev.unlockedNight;
      this.save.endingsSeen = prev.endingsSeen;
    }
    writeSave(this.save);
    this.fx.fade = 1;
    this.fx.fadeTarget = 1;
    this.music.setMode('none');
    this.ui.showCards(INTRO_CARDS, () => this.beginSnapshot(this.save.current));
  }

  private continueGame() {
    const s = loadSave();
    if (!s) return this.newGame();
    this.save = s;
    this.ui.closeOverlay();
    this.beginSnapshot(s.current.phase === 'morning' ? s.morning ?? s.current : s.night ?? s.current);
  }

  private startAtNight(n: number) {
    const s = loadSave() ?? newGameSave();
    this.save = s;
    // a reasonable world for that night
    const flags = freshFlags();
    if (n >= 3) flags.ductOpen = true;
    if (n >= 4) flags.basculanteOpen = true;
    if (n >= 6) flags.hatchOpen = true;
    const homes: Record<ClueId, [number, number, number]> = { foto: [6.75, -2.98, 0.55], coleira: [8.5, -3, 0.16], chave: [2.0, 6.8, 2.2] };
    for (const [id, at] of [
      ['foto', 3],
      ['coleira', 5],
      ['chave', 7],
    ] as [ClueId, number][])
      if (n >= at) flags.clues[id] = { x: homes[id][0], y: homes[id][1], z: homes[id][2], onCircle: false };
    const snap: Snapshot = { day: n, phase: 'night', flags, patience: 65, startFear: 0 };
    s.current = clone(snap);
    s.night = clone(snap);
    s.morning = null;
    this.ui.closeOverlay();
    this.beginSnapshot(snap);
  }

  private beginSnapshot(s: Snapshot) {
    this.flags = clone(s.flags);
    this.day = s.day;
    if (s.phase === 'morning') this.startMorning(s.day);
    else this.startNight(s.day, s);
  }

  /* ================================================================ world reset */

  private resetWorld() {
    const h = this.house;
    h.props.resetAll();
    for (const d of h.doors.values()) {
      d.locked = false;
      d.setState(d.def.state, true);
    }
    h.lights.setAll(false);
    for (const l of h.lights.lights) {
      l.flicker = 0;
      l.dead = 0;
      l.scale = 1;
    }
    h.setHatch(this.flags.hatchOpen, true);
    h.setDuct(this.flags.ductOpen, true);
    h.setBasculante(this.flags.basculanteOpen, true);
    h.setChest(false);
    h.ritualGlow = this.day === LAST_NIGHT ? 1 : 0;
    this.davi.present = this.phase === 'night' && this.day >= DAVI_DAY;
    h.setGuestMoveIn(this.day >= DAVI_DAY && (this.phase === 'night' || this.day > DAVI_DAY));
    this.davi.purring = false;
    this.davi.paralysis = false;
    this.davi.scripted = false;
    this.davi.paused = false;
    this.davi.following = false;
    this.owner.following = false;
    this.davi.abort();
    h.bowlFood.visible = false;
    for (const f of h.faucets) {
      f.running = 0;
      f.level = 0;
      f.puddle = 0;
    }
    // clues
    const homes: Record<string, THREE.Vector3> = {
      foto: new THREE.Vector3(6.75, -2.98, 0.55),
      coleira: new THREE.Vector3(8.5, -3, 0.16),
      chave: new THREE.Vector3(2.0, 6.8, 2.2),
      toy: new THREE.Vector3(3.6, 0, 4.0),
    };
    for (const [id, c] of h.carryables) {
      if (id === 'doll') continue;
      c.carried = false;
      c.enabled = true;
      c.mesh.visible = true;
      const saved = (CLUES as string[]).includes(id) ? this.flags.clues[id as ClueId] : null;
      if (saved) c.place(new THREE.Vector3(saved.x, saved.y, saved.z));
      else c.place(homes[id]);
    }
    this.cat.carrying = null;
    this.cat.mode = 'free';
    this.cat.lockedMovement = false;
    this.cat.focus = 100;
    this.cat.vision = 0;
    this.cat.visionToggled = false;
    this.owner.purring = false;
    this.owner.paralysis = false;
    this.owner.scripted = false;
    this.owner.paused = false;
    this.owner.abort();
    this.lock.active = false;
    this.audio.setMuffle(0);
    this.purrLoop?.stop();
    this.purrLoop = null;
    this.failing = false;
    this.winning = false;
    this.ui.clearHints();
    this.ui.tasks(null, []);
    this.holdT = 0;
    this.holdTarget = null;
    this.transitioning = false;
  }

  /* ================================================================ NIGHT */

  startNight(day: number, snap?: Snapshot) {
    this.ui.closeOverlay();
    this.day = day;
    this.phase = 'night';
    this.mode = 'play';
    this.phaseT = 0;
    this.hour = 0;
    this.lastHour = 0;
    this.world.night = day;
    this.nightLen = NIGHT_LENGTH_MIN[day] * 60;
    this.stats = { repelled: 0, maxFear: 0, locked: 0, caught: 0 };
    if (snap) this.flags = clone(snap.flags);
    this.resetWorld();
    this.applyEnv('night');
    this.ensureAmbience();
    this.owner.setNight(true);
    this.owner.show();
    this.owner.putInBed(true);
    this.owner.fear = snap?.startFear ?? 0;
    this.owner.patience = snap?.patience ?? 65;
    this.setupDavi();
    this.cat.teleport(new THREE.Vector3(...CAT_START), Math.PI);
    this.rig.snap(this.cat.pos.clone().add(new THREE.Vector3(0, 0.32, 0)), Math.PI * 0.85);
    this.rig.pitch = -0.25;
    this.director.startNight(day, Settings.data.nightSpeed);
    this.ambient.reset();
    this.music.setMode('night');
    this.ui.hudVisible(true);
    this.controls = true;
    this.input.requestLock();
    this.fx.fade = 1;
    this.fx.fadeTarget = 0;
    this.fx.fadeSpeed = 0.6;
    // owner trips (water / toilet)
    this.ownerWakes = [];
    if (day >= 2) this.ownerWakes.push({ who: this.owner, at: rand(1.2, 2.4), kind: 'water', done: false });
    if (day >= 4) this.ownerWakes.push({ who: this.owner, at: rand(3.4, 4.6), kind: 'toilet', done: false });
    if (day >= DAVI_DAY) this.ownerWakes.push({ who: this.davi, at: rand(2.8, 3.8), kind: 'water', done: false });
    // save checkpoint
    const s: Snapshot = { day, phase: 'night', flags: clone(this.flags), patience: this.owner.patience, startFear: this.owner.fear };
    this.save.current = clone(s);
    this.save.night = clone(s);
    this.save.unlockedNight = Math.max(this.save.unlockedNight, day);
    writeSave(this.save);
    setTimeout(() => this.ui.title(`Noite ${day}`, '00:00', 4), 600);
    if (day === 1) {
      setTimeout(() => this.owner.say('Primeira noite na casa nova, {cat}. Boa noite...', 3.5, 'whisper'), 2200);
      this.scheduleHint(5, 'move', `Mova-se com <span class="kbd">WASD</span> e olhe com o mouse. <span class="kbd">Shift</span> corre.`);
      this.scheduleHint(13, 'jump', `Quando aparecer um <b>círculo</b> no chão ou num móvel, <span class="kbd">Espaço</span> pula até ele.`);
    } else if (day === 2) {
      this.scheduleHint(4, 'meow', `<span class="kbd">${this.ui.key('meow')}</span> mia e <b>chama</b> as pessoas até você. Também tira alguém de um transe, mas irrita quem dorme.`);
      this.scheduleHint(14, 'noise', `Derrubar coisas faz barulho: quem caça pelo som vai até lá. Use isso como isca.`);
    } else if (day === 3) {
      this.scheduleHint(4, 'hiss', `<span class="kbd">${this.ui.key('hiss')}</span> bufa: espanta ou enfraquece o que estiver por perto. O botão aparece na tela quando adianta. Gasta Foco.`);
    } else if (day === 4) {
      this.scheduleHint(4, 'tab', `Segure <span class="kbd">${this.ui.key('info')}</span> para ver a hora.`);
      this.scheduleHint(11, 'two', `Agora são <b>dois</b> para proteger. Cada ameaça escolhe um alvo.`);
    }
  }

  private scheduleHint(at: number, id: string, html: string) {
    setTimeout(() => {
      if (this.phase === 'night' && this.mode !== 'menu') this.hintOnce(id, html, 7);
    }, at * 1000);
  }

  hintOnce(id: string, html: string, dur = 7) {
    if (this.hintsShown.has(id)) return;
    this.hintsShown.add(id);
    this.ui.hint(html, dur);
  }

  private introduce(id: ThreatId) {
    if (this.introduced.has(id)) return;
    this.introduced.add(id);
    const info = THREAT_INFO[id];
    this.ui.threat(info.name, info.hint);
    if (id === 'shadow' && this.day === 1) {
      setTimeout(() => this.hintOnce('ears', `Ouça. As <b>orelhas</b> do ${Settings.data.catName} apontam para o perigo.`), 2500);
      setTimeout(() => this.hintOnce('vision', `Segure <span class="kbd">${this.ui.key('vision')}</span> para a <b>Visão de Gato</b>: ela mostra o que Clara não vê, até através das paredes.`), 9000);
      setTimeout(() => this.hintOnce('switch', `Pule nos interruptores com <span class="kbd">${this.ui.key('interact')}</span>. Acenda a luz do cômodo onde a Sombra está.`), 17000);
    }
  }

  /** Davi stays up late working in the study, then goes to bed */
  private setupDavi() {
    const dv = this.davi;
    if (!dv.present) {
      dv.hide();
      return;
    }
    dv.setNight(true);
    dv.show();
    dv.fear = 0;
    dv.patience = 70;
    dv.inBed = false;
    dv.asleep = false;
    dv.place(SPOTS.desk);
    dv.model.snapPose('sit');
    const bedtime = rand(0.9, 1.3);
    dv.run(
      'work',
      [
        { t: 'until', cond: () => this.hour >= bedtime, pose: 'read' },
        { t: 'say', text: 'Chega por hoje. Boa noite, casa velha.', dur: 3, kind: 'whisper' },
        { t: 'pose', pose: 'stand', dur: 0.4 },
        { t: 'spot', spot: SPOTS.davBedside },
        { t: 'bed' },
      ],
      1,
    );
  }

  private nightUpdate(dt: number) {
    const people = this.household.present;
    this.phaseT += dt;
    this.hour = (this.phaseT / this.nightLen) * 6;
    this.world.hour = this.hour;
    for (const m of people) this.stats.maxFear = Math.max(this.stats.maxFear, m.fear);
    // hourly chime
    const hInt = Math.floor(this.hour);
    if (hInt > this.lastHour && hInt < 6) {
      this.lastHour = hInt;
      this.audio.bell(this.house.clockPos, hInt, 0.35);
      if (Settings.data.assist || this.infoHeld > 0) this.ui.clock(formatClock(this.hour), `Noite ${this.day}`);
    }
    // trips (water / toilet)
    for (const wk of this.ownerWakes) {
      if (wk.done || this.hour < wk.at || !wk.who.present) continue;
      if (!wk.who.inBed || wk.who.busy || wk.who.fear > 45 || this.director.tension() > 0.55) {
        wk.at += 0.15;
        continue;
      }
      wk.done = true;
      this.ownerTrip(wk.who, wk.kind);
    }
    // fear consequences
    const broken = this.household.anyBroken();
    if (broken && !this.failing) this.fail(broken);
    if (!this.lock.active && !this.failing) {
      const angry = people.find((m) => m.patience <= 0);
      if (angry) this.lockCat(angry);
    }
    if (this.lock.active) {
      this.lock.t -= dt;
      if (this.lock.t <= 0) this.releaseLock();
    }
    if (this.hour >= 6 && !this.winning && !this.failing) this.nightWon();
    const scared = people.reduce((m, p) => (p.fear > m.fear ? p : m), people[0]);
    // first fear hint
    if (scared.fear > 26) this.hintOnce('fear', 'Quando alguém tem medo, a casa perde a cor. Ouça o coração.');
    if (scared.fear > 45) this.hintOnce('purr', `Deite com ${scared.name} na cama (<span class="kbd">${this.ui.key('interact')}</span>) e ronrone para acalmar.`);
    const annoyed = people.reduce((m, p) => (p.patience < m.patience ? p : m), people[0]);
    if (annoyed.patience < 30) this.hintOnce('patience', `${annoyed.name} está perdendo a paciência. Se ficar irritado(a), vai te trancar no banheiro.`);
  }

  private ownerTrip(o: Owner, kind: 'water' | 'toilet') {
    const bedside = o.cfg.bedsideSpot;
    const steps: Step[] =
      kind === 'water'
        ? [
            { t: 'say', text: 'Que sede...', dur: 2, kind: 'whisper' },
            { t: 'spot', spot: SPOTS.kitchenSink },
            { t: 'pose', pose: 'drink', dur: 3 },
            { t: 'pose', pose: 'stand', dur: 0.4 },
            { t: 'spot', spot: bedside },
            { t: 'bed' },
          ]
        : [
            { t: 'say', text: 'Hmm... banheiro...', dur: 2, kind: 'whisper' },
            { t: 'spot', spot: SPOTS.bathroomUp },
            { t: 'wait', dur: 6 },
            { t: 'spot', spot: bedside },
            { t: 'bed' },
          ];
    o.run(kind, steps, 1);
  }

  private nightWon() {
    this.winning = true;
    this.controls = false;
    this.director.stopAll();
    this.audio.bell(this.house.clockPos, 6, 0.45);
    this.fx.letterTarget = 1;
    if (this.cat.mode === 'purr') this.togglePurr();
    if (this.day === LAST_NIGHT) {
      // survived without the ritual
      setTimeout(() => this.ending('bad'), 4000);
      return;
    }
    this.applyEnv('dawn');
    this.owner.say('Bom dia, {cat}... que noite estranha.', 3.5, 'whisper');
    this.ui.title('06:00', 'Amanhecer', 4);
    setTimeout(() => {
      this.fx.fadeTarget = 1;
      this.fx.fadeSpeed = 0.8;
    }, 4500);
    setTimeout(() => {
      this.input.exitLock();
      this.mode = 'over';
      this.ui.clearHints();
      this.ui.showSummary({
        title: `Noite ${this.day} sobrevivida`,
        lines: [
          ['Assombrações afastadas', String(this.stats.repelled)],
          ['Medo máximo', `${Math.round(this.stats.maxFear)}%`],
          ['Vezes trancado no banheiro', String(this.stats.locked)],
        ],
        onContinue: () => {
          this.fx.letterTarget = 0;
          this.startMorning(this.day + 1);
        },
      });
    }, 6200);
  }

  private fail(who: Owner) {
    this.failing = true;
    this.controls = false;
    const attackers = this.director.all.filter((t) => t.enabled && t.stage >= 3).sort((a, b) => b.stage - a.stage);
    const killer = attackers.find((t) => t.target === who) ?? attackers[0] ?? null;
    const info = killer
      ? killer.describeDeath()
      : {
          title: `${who.name} não aguentou o medo`,
          why: 'O medo foi se acumulando sem parar, até não restar coragem.',
          tip: 'Ronronar na cama acalma. Resolva as ameaças cedo, antes de o medo disparar.',
        };
    if (killer && killer.target !== who) info.title = `${who.name} foi levado(a) pelo medo`;
    const others = this.director.all.filter((t) => t.enabled && t.stage >= 2 && t !== killer).map((t) => t.name);
    const catRoom = roomAt(this.cat.pos);
    const facts: string[] = [`Medo de ${who.name}: ${Math.round(who.fear)}%`, catRoom ? `Você estava: ${ROOM_BY_ID[catRoom].name}` : 'Você estava fora de casa'];
    if (others.length) facts.push(`Também estavam ativas: ${others.join(', ')}`);
    const dead = this.house.lights.lights.filter((l) => l.ticks && l.dead > 0).length;
    if (dead > 1) facts.push(`Lâmpadas queimadas no momento: ${dead}`);
    this.audio.shriek(who.headPos(), 1);
    this.audio.sting(0.9);
    this.world.fx.flash(0.6, '#5a0000');
    this.world.fx.distort(1);
    this.rig.shake(1.4);
    this.director.stopAll();
    if (this.cat.mode === 'purr') this.togglePurr();
    this.fx.fadeTarget = 1;
    this.fx.fadeSpeed = 0.5;
    setTimeout(() => {
      who.hide();
      this.house.setBlanket(false);
      this.house.setDavBlanket(false);
    }, 1500);
    setTimeout(() => {
      this.input.exitLock();
      this.mode = 'over';
      this.ui.clearHints();
      this.music.setMode('none');
      const hasDay = this.day > 1 && !!this.save.morning;
      this.ui.showFail({
        title: info.title,
        sub: `Noite ${this.day} · ${formatClock(this.hour)}`,
        why: info.why,
        tip: info.tip,
        facts,
        onNight: () => this.startNight(this.day, this.save.night ?? undefined),
        onDay: hasDay ? () => this.beginSnapshot(this.save.morning!) : null,
        onMenu: () => this.toMenu(),
      });
    }, 3600);
  }

  /* ---------------------------------------------------------------- lock */

  private lockBy: Owner | null = null;

  private lockCat(who: Owner) {
    if (this.phase !== 'night') {
      who.patience = 5;
      return;
    }
    this.lockBy = who;
    this.lock.active = true;
    this.lock.t = this.nightLen / 6 + 1.7;
    this.stats.locked++;
    this.save.stats.timesLocked++;
    this.save.everLocked = true;
    this.controls = false;
    if (this.cat.mode === 'purr') this.togglePurr();
    who.say(who.cfg.skeptic ? '{cat}! Fora do meu quarto. Banheiro, já.' : '{cat}! CHEGA! Banheiro, agora.', 3, 'annoyed');
    this.fx.fadeTarget = 1;
    this.fx.fadeSpeed = 1.2;
    setTimeout(() => {
      if (this.cat.carrying) this.dropCarried();
      this.cat.teleport(new THREE.Vector3(9.4, 3, 7.6), -Math.PI / 2);
      this.rig.snap(this.cat.pos.clone().add(new THREE.Vector3(0, 0.32, 0)), -Math.PI / 2);
      const d = this.house.doors.get('d_banc')!;
      d.setState('closed', true);
      d.locked = true;
      this.audio.thud(d.center(new THREE.Vector3()).add(new THREE.Vector3(0, 1, 0)), 0.8, 90);
      this.audio.click(d.center(new THREE.Vector3()).add(new THREE.Vector3(0, 1, 0)), 0.8);
      who.putInBed(false);
      who.patience = 45;
      this.fx.fadeTarget = 0;
      this.controls = true;
      this.audio.setMuffle(0.15);
      this.ui.hint(
        `Você foi trancado no banheiro por uma hora. Arranhe a porta (segure <span class="kbd">${this.ui.key('interact')}</span>)${this.flags.basculanteOpen ? ' ou fuja pela janela basculante.' : '. Da próxima vez, abra a basculante de manhã.'}`,
        8,
      );
    }, 1700);
  }

  private releaseLock() {
    this.lock.active = false;
    this.audio.setMuffle(0);
    const d = this.house.doors.get('d_banc')!;
    if (d.locked) {
      d.locked = false;
      d.setState('ajar');
      (this.lockBy ?? this.owner).say('Tá... pode sair. Mas fica quieto, {cat}.', 3, 'annoyed');
    }
  }

  onEscapedLock() {
    if (this.lock.active) {
      this.lock.active = false;
      this.audio.setMuffle(0);
      (this.lockBy ?? this.owner).say('{cat}!! Para de arranhar essa porta!', 2.6, 'annoyed');
    }
  }

  /* ---------------------------------------------------------------- ritual & thing */

  ritualPlaced(id: string) {
    return (CLUES as string[]).includes(id) && !!this.flags.clues[id as ClueId]?.onCircle;
  }

  onRitualItem() {
    const n = CLUES.filter((k) => this.flags.clues[k]?.onCircle).length;
    this.house.ritualGlow = 1 + n * 0.15;
    this.director.thing.ritualItems = n;
    if (this.phase === 'morning') this.onTask('ritual');
    if (n === 3) this.ui.say('', 'O círculo está completo. Quando a Coisa acordar, termine o ritual.', 5, 'narrator');
  }

  private onThingWave(hit: boolean) {
    if (!hit) return;
    // knock the cat away from the circle
    const c = new THREE.Vector3(...RITUAL_CENTER);
    const dir = this.cat.pos.clone().sub(c).setY(0);
    if (dir.lengthSq() < 0.01) dir.set(1, 0, 0);
    dir.normalize();
    const to = c.clone().addScaledVector(dir, 4.2);
    to.x = clamp(to.x, 0.6, 7.4);
    to.z = clamp(to.z, 0.6, 9.4);
    to.y = this.house.col.groundHeight(to.x, to.z, -2.5, 0.05);
    if (this.cat.mode !== 'free') this.cat.mode = 'free';
    this.cat.arc = { from: this.cat.pos.clone(), to, t: 0, dur: 0.5, h: 0.6 };
    this.holdT = 0;
    this.holdTarget = null;
    this.audio.hiss(this.cat.head.clone(), false);
    this.hintOnce('wave', `Quando os tentáculos se erguerem, <b>bufe</b> (<span class="kbd">${this.ui.key('hiss')}</span>) para cancelar a onda.`);
  }

  completeRitual() {
    this.director.thing.kill();
    this.director.stopAll();
    this.controls = false;
    this.winning = true;
    for (const id of CLUES) {
      const c = this.house.carryables.get(id)!;
      c.mesh.visible = false;
    }
    setTimeout(() => {
      this.applyEnv('dawn');
      for (const m of this.household.present) m.fear = 0;
    }, 1200);
    setTimeout(() => this.ending(this.save.everLocked ? 'good' : 'secret'), 3500);
  }

  private ending(kind: 'good' | 'bad' | 'secret') {
    this.input.exitLock();
    this.mode = 'over';
    this.controls = false;
    this.director.stopAll();
    this.music.setMode('ending');
    this.ui.clearHints();
    if (!this.save.endingsSeen.includes(kind)) this.save.endingsSeen.push(kind);
    this.save.unlockedNight = LAST_NIGHT;
    writeSave(this.save);
    const e = ENDINGS[kind];
    const cat = Settings.data.catName;
    this.ui.showEnding(
      e.title,
      e.lines.map((l) => l.replace(/\{cat\}/g, cat)),
      () => this.ui.showCredits(() => this.toMenu()),
    );
  }

  /* ================================================================ MORNING */

  startMorning(day: number) {
    this.ui.closeOverlay();
    this.day = day;
    this.phase = 'morning';
    this.mode = 'play';
    this.phaseT = 0;
    this.resetWorld();
    this.director.stopAll();
    this.applyEnv('morning');
    this.ensureAmbience();
    this.owner.hide();
    this.owner.abort();
    this.owner.inBed = false;
    this.davi.hide();
    this.house.setBlanket(false);
    this.house.blanketOff.visible = true;
    this.cat.teleport(this.house.catBed.clone().add(new THREE.Vector3(0.2, 0, -0.5)), Math.PI);
    this.rig.snap(this.cat.pos.clone().add(new THREE.Vector3(0, 0.32, 0)), Math.PI * 0.8);
    this.music.setMode('morning');
    this.ui.hudVisible(true);
    this.controls = true;
    this.input.requestLock();
    this.fx.fade = 1;
    this.fx.fadeTarget = 0;
    this.fx.fadeSpeed = 0.7;
    this.fx.letterTarget = 0;
    const s: Snapshot = { day, phase: 'morning', flags: clone(this.flags), patience: 50, startFear: 0 };
    this.save.current = clone(s);
    this.save.morning = clone(s);
    writeSave(this.save);
    setTimeout(() => this.ui.title(`Dia ${day}`, 'Manhã · a casa está vazia', 4), 500);
    setTimeout(() => {
      this.refreshTasks();
      this.ui.tasksVisible(true);
      setTimeout(() => this.ui.tasksVisible(this.infoHeld > 0), 12000);
    }, 2500);
    if (day === 2) {
      this.scheduleMorningHint(6, 'morning', `De manhã a casa é segura. Prepare-se para a noite. Segure <span class="kbd">${this.ui.key('info')}</span> para ver as tarefas.`);
      this.scheduleMorningHint(14, 'morningvision', `Use a <b>Visão de Gato</b> para achar marcas que as assombrações deixaram.`);
    }
  }

  private scheduleMorningHint(at: number, id: string, html: string) {
    setTimeout(() => {
      if (this.phase === 'morning') this.hintOnce(id, html, 8);
    }, at * 1000);
  }

  private taskDone(id: string): boolean {
    const f = this.flags;
    if (id.startsWith('mark')) {
      const d = Number(id.slice(4));
      return this.house.marks.some((m) => m.day === d && f.marksSeen.includes(m.id));
    }
    if (id === 'duct') return f.ductOpen;
    if (id === 'basculante') return f.basculanteOpen;
    if (id === 'hatch') return f.hatchOpen;
    if (id === 'foto' || id === 'coleira' || id === 'chave') return !!f.clues[id];
    if (id === 'ritual') return CLUES.every((k) => f.clues[k]?.onCircle);
    return false;
  }

  refreshTasks() {
    if (this.phase !== 'morning') return;
    const list = (MORNING_TASKS[this.day] ?? []).map((t) => ({ text: t.text, done: this.taskDone(t.id) }));
    const left = Math.max(0, MORNING_LEN - this.phaseT);
    const mm = Math.floor(left / 60);
    const ss = Math.floor(left % 60);
    this.ui.tasks('Preparo da manhã', list, `Clara volta em ${mm}:${String(ss).padStart(2, '0')} · ou durma na caminha`);
  }

  onTask(_id: string) {
    this.refreshTasks();
    if (this.phase === 'morning') this.ui.tasksVisible(true);
    setTimeout(() => this.ui.tasksVisible(this.infoHeld > 0), 3500);
  }

  onClueFound(id: ClueId) {
    const names = { foto: 'uma foto antiga', coleira: 'uma coleira antiga', chave: 'uma chave pequena' };
    const lines = {
      foto: 'Dona Ivone, com um gato preto no colo. Atrás: “Sete anos juntos”.',
      coleira: 'Uma coleira vermelha com um sininho. No pingente: “Breu”.',
      chave: 'Uma chave pequena e enferrujada. Abre o baú do sótão.',
    };
    this.ui.say('', `Você encontrou ${names[id]}. ${lines[id]}`, 6, 'narrator');
    this.onTask(id);
  }

  private morningUpdate(dt: number) {
    this.phaseT += dt;
    if (Math.floor(this.phaseT) !== Math.floor(this.phaseT - dt)) this.refreshTasks();
    // investigate marks with cat vision
    if (this.cat.vision > 0.6) {
      for (const m of this.house.marks) {
        if (m.day !== this.day || this.flags.marksSeen.includes(m.id)) continue;
        const d = m.pos.distanceTo(this.camera.position);
        if (d > 4.5) continue;
        const v = m.pos.clone().project(this.camera);
        if (Math.abs(v.x) > 0.55 || Math.abs(v.y) > 0.55 || v.z > 1) continue;
        if (this.house.col.blocked(this.camera.position, m.pos)) continue;
        this.flags.marksSeen.push(m.id);
        this.ui.say('', m.text, 6, 'narrator');
        this.audio.bell(null, 1, 0.12);
        this.onTask(`mark${this.day}`);
      }
    }
    if (this.phaseT >= MORNING_LEN && !this.transitioning) {
      this.ui.say('', `${Settings.data.catName} cochilou no sol da janela...`, 3, 'narrator');
      this.skipPhase();
    }
  }

  /* ================================================================ AFTERNOON */

  startAfternoon() {
    const day = this.day;
    this.phase = 'afternoon';
    this.mode = 'play';
    this.phaseT = 0;
    this.aft = this.freshAft();
    this.aft.scene = DAY_SCENES[day] ?? '';
    this.applyEnv('afternoon');
    this.music.setMode('afternoon');
    this.ui.tasks(null, []);
    this.house.lights.setAll(false);
    const L = this.house.lights;
    L.byRoom.get('cozinha')!.setOn(true);
    L.byRoom.get('sala')!.setOn(true);
    L.byRoom.get('hall')!.setOn(true);
    const o = this.owner;
    o.setNight(false);
    o.show();
    o.fear = 0;
    o.patience = 45;
    o.inBed = false;
    o.place({ node: 'g_hall_front', p: [6.45, 0, -1.0], yaw: 0 });
    o.model.snapPose('stand');
    const front = this.house.doors.get('d_front')!;
    front.setState('open');
    this.audio.creak(front.center(new THREE.Vector3()).add(new THREE.Vector3(0, 1, 0)), 0.5, 1.2);
    const dv = this.davi;
    dv.present = day >= DAVI_DAY;
    this.house.setGuestMoveIn(day >= DAVI_DAY);
    if (dv.present) {
      dv.setNight(false);
      dv.show();
      dv.fear = 0;
      dv.patience = 60;
      dv.inBed = false;
      dv.place({ node: 'g_hall_front', p: [6.45, 0, -1.8], yaw: 0 });
      dv.model.snapPose('stand');
      dv.run('afternoon', this.daviAfternoon(day), 1);
    } else dv.hide();
    this.fx.fadeTarget = 0;
    this.controls = true;
    setTimeout(() => this.ui.title(`Dia ${day}`, day === DAVI_DAY ? 'Fim de tarde · Davi está se mudando' : 'Fim de tarde · Clara chegou', 3.5), 400);
    this.scheduleAftHint(5, 'aft', `Ganhe a <b>Paciência</b> de Clara para a noite: peça carinho, coma, brinque com o ratinho.`);
    const sceneSteps = this.sceneSteps(this.aft.scene);
    o.run(
      'afternoon',
      [
        { t: 'walk', node: 'g_hall_mid' },
        { t: 'do', fn: () => front.setState('closed') },
        { t: 'say', text: 'Cheguei, {cat}! Sentiu saudade?', dur: 3 },
        { t: 'spot', spot: SPOTS.bowl },
        { t: 'pose', pose: 'pet', dur: 1.6 },
        {
          t: 'do',
          fn: () => {
            this.house.bowlFood.visible = true;
            this.aft.bowlFilled = true;
          },
        },
        { t: 'say', text: 'Hora da janta!', dur: 2 },
        { t: 'pose', pose: 'stand', dur: 0.5 },
        { t: 'wait', dur: 12 },
        ...sceneSteps,
        { t: 'do', fn: () => (this.aft.canSkip = true) },
        { t: 'spot', spot: SPOTS.hallPhone },
        { t: 'wait', dur: 16 },
        { t: 'say', text: 'Bom... hora de dormir. Vem, {cat}.', dur: 3 },
        { t: 'do', fn: () => this.house.lights.setAll(false) },
        { t: 'spot', spot: SPOTS.bedside },
        { t: 'do', fn: () => this.endAfternoon() },
      ],
      1,
    );
  }

  private daviAfternoon(day: number): Step[] {
    const steps: Step[] = [];
    if (day === DAVI_DAY) {
      steps.push(
        { t: 'wait', dur: 4 },
        { t: 'walk', node: 'g_hall_mid' },
        { t: 'say', text: 'Então é aqui a casa barata? Gostei, Clara.', dur: 3.4 },
        { t: 'wait', dur: 4 },
        { t: 'say', text: 'Não acredito em fantasma. Mas acredito em preço bom.', dur: 3.4 },
        { t: 'spot', spot: SPOTS.davBedside },
        { t: 'wait', dur: 4 },
        { t: 'say', text: 'Quarto de hóspedes... cheio de caixa. Perfeito.', dur: 3 },
        { t: 'say', text: '{cat}, né? Espero que não solte muito pelo. Sou alérgico.', dur: 3.6 },
        { t: 'wait', dur: 3 },
      );
    } else {
      steps.push({ t: 'wait', dur: 7 }, { t: 'walk', node: 'g_hall_mid' }, { t: 'say', text: choose(['Cheguei! O trânsito tava infernal.', 'Boa noite, casa. ...ainda é tarde, né.', 'Alguém aí viu minhas chaves?']), dur: 2.8 });
    }
    steps.push({ t: 'spot', spot: SPOTS.sofaR }, { t: 'until', cond: () => this.aft.ending, pose: 'sit' });
    return steps;
  }

  private scheduleAftHint(at: number, id: string, html: string) {
    setTimeout(() => {
      if (this.phase === 'afternoon') this.hintOnce(id, html, 8);
    }, at * 1000);
  }

  private sceneSteps(scene: string): Step[] {
    const o = this.owner;
    if (scene === 'tv')
      return [
        { t: 'spot', spot: SPOTS.sofa },
        { t: 'pose', pose: 'sit', dur: 6 },
        {
          t: 'do',
          fn: () => {
            const tv = this.house.devices.find((d) => d.id === 'tv')!;
            tv.glow = 1;
            const st = this.audio.loop('static', tv.pos, { ref: 1.3 });
            st.setLevel(0.5);
            setTimeout(() => {
              tv.glow = 0;
              st.stop(0.3);
            }, 3500);
          },
        },
        { t: 'pose', pose: 'sit', dur: 2.5 },
        { t: 'say', text: 'Ué... essa TV velha liga sozinha? Hahaha.', dur: 3 },
        { t: 'pose', pose: 'sit', dur: 10 },
        { t: 'pose', pose: 'stand', dur: 0.6 },
      ];
    if (scene === 'bath')
      return [
        { t: 'say', text: 'Vou tomar um banho quentinho...', dur: 2.6 },
        { t: 'spot', spot: SPOTS.tub },
        {
          t: 'do',
          fn: () => {
            const tub = this.house.faucets.find((f) => f.id === 'tub')!;
            tub.level = 0.8;
            o.place(SPOTS.bathTubIn);
            this.aft.bathing = true;
            this.aft.bathT = 0;
            this.hintOnce('bath', `Algo se mexe na água. Use a <b>Visão de Gato</b> e tire Clara da banheira.`, 8);
            this.director.drowner['hands'].visible = true;
          },
        },
        { t: 'until', cond: () => !this.aft.bathing, pose: 'bath', timeout: 45 },
        {
          t: 'do',
          fn: () => {
            if (this.aft.bathing) this.endBath(false);
          },
        },
        { t: 'pose', pose: 'stand', dur: 0.5 },
      ];
    if (scene === 'davi')
      return [
        { t: 'say', text: 'Davi! O quarto de hóspedes é lá em cima, o da direita.', dur: 3.4 },
        { t: 'wait', dur: 4 },
        { t: 'say', text: 'Obrigada por vir. Eu não queria ficar sozinha aqui.', dur: 3.6 },
        { t: 'wait', dur: 4 },
        { t: 'say', text: 'Se ouvir barulho de noite, é a casa velha. Né?', dur: 3.2 },
        { t: 'wait', dur: 3 },
      ];
    if (scene === 'eve')
      return [
        { t: 'say', text: 'Hoje a gente dorme de luz acesa, Davi.', dur: 3.2 },
        { t: 'wait', dur: 4 },
        { t: 'say', text: 'Seja o que for... a gente passa por essa noite.', dur: 3.4 },
        { t: 'wait', dur: 4 },
        { t: 'say', text: '{cat}, fica de olho. Por favor.', dur: 3 },
        { t: 'wait', dur: 3 },
      ];
    if (scene === 'phone')
      return [
        { t: 'spot', spot: SPOTS.hallPhone },
        { t: 'pose', pose: 'phone', dur: 0.8 },
        { t: 'say', text: 'Oi, mãe! Tudo bem por aí?', dur: 2.6 },
        { t: 'pose', pose: 'phone', dur: 3 },
        { t: 'say', text: 'Vem sim! Vem me visitar, a casa é linda.', dur: 3 },
        { t: 'pose', pose: 'phone', dur: 3 },
        { t: 'say', text: 'Hoje à noite? Tá bom, mãe. Só vai ser tarde. Beijo.', dur: 3 },
        { t: 'pose', pose: 'phone', dur: 2 },
        { t: 'pose', pose: 'stand', dur: 0.6 },
      ];
    if (scene === 'diary')
      return [
        { t: 'say', text: 'Achei isso no baú do sótão... um diário.', dur: 3 },
        { t: 'spot', spot: SPOTS.desk },
        { t: 'pose', pose: 'read', dur: 2 },
        { t: 'say', text: DIARY_LINES[0], dur: 5, kind: 'read' },
        { t: 'pose', pose: 'read', dur: 5 },
        { t: 'say', text: DIARY_LINES[1], dur: 5, kind: 'read' },
        { t: 'pose', pose: 'read', dur: 5 },
        { t: 'say', text: DIARY_LINES[2], dur: 5, kind: 'read' },
        { t: 'pose', pose: 'read', dur: 5.5 },
        { t: 'say', text: 'Que estranho... vou dormir cedo hoje.', dur: 3 },
        { t: 'pose', pose: 'stand', dur: 0.6 },
      ];
    return [{ t: 'wait', dur: 10 }];
  }

  endBath(byCat: boolean) {
    if (!this.aft.bathing) return;
    this.aft.bathing = false;
    this.director.drowner['hands'].visible = false;
    const tub = this.house.faucets.find((f) => f.id === 'tub')!;
    tub.level = 0;
    this.owner.place(SPOTS.tub);
    if (byCat) {
      this.owner.say('Tá bom, tá bom! Já saí, chato.', 3, 'annoyed');
      this.flags.bathSceneDone = true;
    } else {
      this.owner.say('Brr... que água gelada de repente.', 3, 'scared');
      this.flags.bathSceneDone = false;
    }
  }

  petOwner() {
    const o = this.owner;
    this.aft.pets++;
    this.aft.petCd = 6;
    o.addPatience(12);
    this.audio.meow(this.cat.head.clone(), 1.15);
    const line = choose(['Quem é o gato mais lindo dessa casa?', 'Ownn, vem cá, {cat}.', 'Que carente você tá hoje!']);
    o.say(line, 2.6);
    o.paused = true;
    o.model.pose = 'pet';
    this.cat.pose.purr = 1;
    this.startPurr(0.6);
    setTimeout(() => {
      o.paused = false;
      o.model.pose = 'stand';
      this.stopPurr();
    }, 2600);
  }

  playWithOwner() {
    const o = this.owner;
    this.aft.played = true;
    this.dropCarried();
    o.addPatience(10);
    o.say('Pega! Pega o ratinho! Hahaha.', 2.6);
    o.paused = true;
    o.model.pose = 'pet';
    setTimeout(() => {
      o.paused = false;
      o.model.pose = 'stand';
    }, 2400);
  }

  eat() {
    this.aft.fed = true;
    this.house.bowlFood.visible = false;
    this.owner.addPatience(8);
    this.audio.pawStep(this.cat.pos, false, false);
  }

  private endAfternoon() {
    if (this.aft.ending) return;
    this.aft.ending = true;
    this.controls = false;
    this.fx.fadeTarget = 1;
    this.fx.fadeSpeed = 0.8;
    setTimeout(() => {
      const startFear = this.day === 3 && !this.flags.bathSceneDone ? 20 : 0;
      const snap: Snapshot = { day: this.day, phase: 'night', flags: clone(this.flags), patience: clamp(this.owner.patience, 30, 100), startFear };
      this.startNight(this.day, snap);
    }, 1500);
  }

  skipPhase() {
    if (this.transitioning) return;
    if (this.phase === 'morning') {
      this.transitioning = true;
      this.controls = false;
      this.fx.fadeTarget = 1;
      this.fx.fadeSpeed = 0.9;
      setTimeout(() => {
        this.transitioning = false;
        this.startAfternoon();
      }, 1400);
    } else if (this.phase === 'afternoon') {
      this.house.lights.setAll(false);
      this.owner.say('Já tá com sono, {cat}? Então vamos dormir.', 2.6);
      this.endAfternoon();
    }
  }

  /* ================================================================ purr */

  private purrWho: Owner | null = null;

  /** the sleeper whose bed is closest to the cat */
  nearestBedOwner(): Owner {
    let best = this.owner;
    let bd = Infinity;
    for (const m of this.household.present) {
      const p = m.cfg.bedSpot.p;
      const d = Math.hypot(p[0] - this.cat.pos.x, p[2] - this.cat.pos.z) + Math.abs(p[1] - this.cat.pos.y) * 3;
      if (d < bd) {
        bd = d;
        best = m;
      }
    }
    return best;
  }

  togglePurr(who?: Owner) {
    const c = this.cat;
    if (c.mode === 'purr') {
      const prev = this.purrWho ?? this.owner;
      c.mode = 'free';
      c.teleport(new THREE.Vector3(...prev.cfg.bedsideSpot.p), Math.PI / 2);
      prev.purring = false;
      this.purrWho = null;
      this.stopPurr();
      return;
    }
    const o = who ?? this.nearestBedOwner();
    if (o.paralysis) {
      // waking someone from sleep paralysis frightens them less but costs patience
      o.paralysis = false;
      o.addPatience(-6);
      o.addFear(-12);
      o.say('Ah! {cat}... eu não conseguia me mexer...', 3, 'scared');
      this.catHop();
      return;
    }
    c.mode = 'purr';
    c.modeTarget.set(...o.cfg.purrPos);
    c.modeYaw = o.cfg.purrYaw;
    o.purring = true;
    o.asleep = false;
    this.purrWho = o;
    this.startPurr(1);
    if (o.fear < 30) o.addPatience(-1);
    this.hintOnce('purrout', `Ronronar acalma ${o.name}, mas você não está patrulhando. <span class="kbd">${this.ui.key('interact')}</span> para levantar.`);
  }

  private startPurr(level: number) {
    if (!this.purrLoop) this.purrLoop = this.audio.purr();
    this.purrLoop.setLevel(level);
  }
  private stopPurr() {
    this.purrLoop?.setLevel(0);
  }

  /* ================================================================ helpers */

  catHop() {
    const c = this.cat;
    c.pose.jump = 1;
    c.model.root.position.y += 0.05;
    this.audio.pawStep(c.pos, false, false);
  }

  emitNoise(p: THREE.Vector3, loud: number, kind: string) {
    if (this.phase !== 'night' && this.phase !== 'afternoon') return;
    this.director?.hearNoise(p, loud, kind);
    for (const who of this.household.present) {
      const hops = this.world.hops(p, who.pos);
      who.hearNoise(p, loud, hops, kind);
    }
  }

  onLightToggled(index: number, on: boolean) {
    if (this.phase !== 'night') return;
    // lighting a bedroom while its sleeper is in bed annoys them (unless they are scared)
    const who = index === 7 || index === 8 ? this.owner : index === 9 || index === 17 ? this.davi : null;
    if (!who || !who.present) return;
    if (on && who.inBed && who.fear < 45) {
      who.addPatience(-4);
      if (who.asleep) who.say('Hmm... apaga isso, {cat}...', 2.4, 'annoyed');
    }
    if (on && who.fear >= 45) who.addFear(-6);
  }

  passage(to: THREE.Vector3, yaw: number, kind: 'duct' | 'window') {
    this.controls = false;
    this.fx.fadeTarget = 1;
    this.fx.fadeSpeed = 3.5;
    this.director.hound.catVanished();
    if (kind === 'duct') this.audio.crawl(0.5);
    else this.audio.pawStep(this.cat.pos, true, false);
    this.passageT = 0.45;
    setTimeout(() => {
      this.cat.teleport(to, yaw);
      this.rig.snap(to.clone().add(new THREE.Vector3(0, 0.32, 0)), yaw);
      this.fx.fadeTarget = 0;
      this.controls = !this.failing && !this.winning;
    }, kind === 'duct' ? 1100 : 450);
  }

  dropCarried() {
    const c = this.cat.carrying;
    if (!c) return;
    this.cat.carrying = null;
    c.carried = false;
    const f = this.cat.forward;
    const p = this.cat.pos.clone().addScaledVector(f, 0.25);
    p.y = this.house.col.groundHeight(p.x, p.z, this.cat.pos.y + 0.3, 0.02);
    if (p.y < this.cat.pos.y - 1) p.copy(this.cat.pos);
    c.place(p, this.cat.yaw);
    this.audio.thud(p, 0.1, 200);
    if (c.id === 'doll') this.director.doll.dropped(p);
    if ((CLUES as string[]).includes(c.id)) this.flags.clues[c.id as ClueId] = { x: p.x, y: p.y, z: p.z, onCircle: false };
  }

  private fxCa(a: number) {
    this.fx.ca = Math.max(this.fx.ca, a);
  }

  private isObserved(p: THREE.Vector3, need: boolean) {
    const cam = this.camera;
    if (p.distanceTo(cam.position) > 11) return false;
    const v = p.clone().project(cam);
    if (v.z > 1 || Math.abs(v.x) > 0.95 || Math.abs(v.y) > 0.95) return false;
    if (this.house.col.blocked(cam.position, p)) return false;
    if (need) {
      const room = roomAt(p);
      const lit = room ? this.house.lights.isRoomLit(room) : false;
      if (!(this.cat.vision > 0.5 || lit)) return false;
    }
    return true;
  }

  /* ================================================================ pause */

  pause() {
    if (this.mode !== 'play') return;
    this.mode = 'paused';
    this.input.exitLock();
    this.audio.setMuffle(0.7);
    const night = this.phase === 'night';
    this.ui.showPause({
      title: this.phase === 'night' ? `Noite ${this.day} · ${formatClock(this.hour)}` : `Dia ${this.day} · ${this.phase === 'morning' ? 'manhã' : 'fim de tarde'}`,
      onResume: () => this.resume(),
      onRestartNight: night && this.save.night ? () => this.startNight(this.day, this.save.night!) : null,
      onRestartDay: this.day > 1 && this.save.morning ? () => this.beginSnapshot(this.save.morning!) : null,
      onSettings: () => this.ui.showSettings(() => this.pauseRefresh()),
      onMenu: () => this.toMenu(),
    });
  }

  private pauseRefresh() {
    this.mode = 'play';
    this.pause();
  }

  resume() {
    this.ui.closeOverlay();
    this.mode = 'play';
    this.audio.setMuffle(this.lock.active ? 0.15 : 0);
    this.input.requestLock();
    this.lastT = performance.now();
  }

  /* ================================================================ loop */

  private loop = () => {
    requestAnimationFrame(this.loop);
    const now = performance.now();
    const dt = Math.min(0.05, Math.max(0, (now - this.lastT) / 1000));
    this.lastT = now;
    this.input.update();
    this.ui.device = this.input.lastDevice;
    this.ui.navUpdate(dt);
    if (this.mode === 'play') {
      if (this.input.rawPressed('pause') && !this.ui.overlayOpen) this.pause();
      else this.simulate(dt);
    } else if (this.mode === 'menu') {
      this.menuUpdate(dt);
    } else if (this.mode === 'over' || this.mode === 'paused') {
      // keep the world breathing behind the panels
      Shared.time.value += dt * (this.mode === 'paused' ? 0 : 1);
      this.house.update(this.mode === 'paused' ? 0 : dt, 0, this.day, this.phase);
    }
    this.postFx(dt);
    this.ui.showClickToPlay(this.mode === 'play' && !this.input.locked && !this.ui.overlayOpen && this.input.lastDevice === 'kbm' && this.controls);
    this.sky.follow(this.camera);
    this.gr.render(dt);
    this.input.endFrame();
  };

  /** Debug/testing: advance the simulation without requestAnimationFrame. */
  debugStep(sec: number, render = true) {
    const n = Math.max(1, Math.round(sec * 60));
    for (let i = 0; i < n; i++) {
      this.input.update();
      if (this.mode === 'play') this.simulate(1 / 60);
      else if (this.mode === 'menu') this.menuUpdate(1 / 60);
      this.postFx(1 / 60);
      this.input.endFrame();
    }
    if (render) {
      this.sky.follow(this.camera);
      this.gr.render(1 / 60);
    }
  }

  private menuUpdate(dt: number) {
    this.menuT += dt;
    Shared.time.value += dt;
    const t = this.menuT;
    const pos = new THREE.Vector3(4.2 + Math.sin(t * 0.045) * 3.2, 3.0 + Math.sin(t * 0.07) * 0.35, -15.2 + Math.cos(t * 0.045) * 1.2);
    this.camera.position.copy(pos);
    this.camera.lookAt(7.2 + Math.sin(t * 0.03) * 0.5, 3.3, 2);
    if (this.camera.fov !== 50) {
      this.camera.fov = 50;
      this.camera.updateProjectionMatrix();
    }
    this.house.update(dt, 0, 1, 'menu');
    this.owner.update(dt);
    this.cat.model.update(dt, { ...this.cat.pose, sit: 1, speed: 0, grounded: true, tailUp: 0.5 });
    this.music.update(dt, 0.1);
    this.audio.update(this.camera, () => ({ gain: 0.6, cutoff: 1800 }));
    this.ui.prompt(null);
  }

  private simulate(dt: number) {
    const cat = this.cat;
    const o = this.owner;
    const h = this.house;
    Shared.time.value += dt;
    this.infoHeld = this.input.isDown('info') ? this.infoHeld + dt : 0;

    // phase logic
    if (this.phase === 'night') this.nightUpdate(dt);
    else if (this.phase === 'morning') this.morningUpdate(dt);
    else if (this.phase === 'afternoon') {
      this.phaseT += dt;
      this.aft.petCd -= dt;
      if (this.aft.bathing) {
        this.aft.bathT += dt;
        const hands = this.director.drowner['hands'] as THREE.Group;
        hands.position.set(10.75, 3.25 + Math.sin(this.phaseT) * 0.05, 9.57);
        ((hands.userData.mat as THREE.ShaderMaterial).uniforms.uAlpha.value = 0.25);
      }
      if (o.patience <= 1) o.patience = 5;
    }

    // purr mode exit on movement
    if (cat.mode === 'purr' && (Math.hypot(this.input.move.x, this.input.move.y) > 0.5 || this.input.wasPressed('jump'))) this.togglePurr();
    if (cat.mode === 'purr' && !(this.purrWho ?? o).inBed) this.togglePurr();

    // cat
    cat.update(dt, this.input, this.rig.yaw, h.col, this.controls);
    if (cat.carrying) {
      const c = cat.carrying;
      const m = new THREE.Vector3();
      cat.model.mouthWorld(m);
      c.mesh.position.copy(m).add(new THREE.Vector3(0, -0.03, 0));
      c.mesh.rotation.set(0, cat.yaw + Math.PI / 2, c.id === 'doll' ? Math.PI / 2 : 0);
      c.pos.copy(cat.pos);
    }
    if (cat.mode === 'free') h.props.interactCat(cat.pos, cat.vel, 0.14);

    // threats / owner
    if (this.phase === 'night') this.director.update(dt);
    cat.hunted = damp(cat.hunted, this.phase === 'night' ? this.director.hound.threatLevel() * (cat.mode === 'hidden' ? 0.6 : 1) : 0, 3, dt);
    cat.slip = damp(cat.slip, this.phase === 'night' ? this.director.drowner.wetAt(cat.pos) : 0, 10, dt);
    this.rig.distance = damp(this.rig.distance, cat.mode === 'hidden' ? 0.85 : 1.55, 4, dt);
    o.update(dt);
    if (this.davi.present) this.davi.update(dt);
    h.setBlanket(o.inBed && o.model.pose === 'lie' && o.model.root.visible);
    h.setDavBlanket(this.davi.present && this.davi.inBed && this.davi.model.pose === 'lie' && this.davi.model.root.visible);
    h.update(dt, cat.vision, this.day, this.phase);
    this.envFx(dt);

    // threat awareness: ears + fur
    if (this.phase === 'night') {
      const urgent = this.director.mostUrgent();
      const f = urgent?.focus ?? null;
      cat.earTargetWorld = f;
      cat.alert = urgent ? clamp(urgent.urgency * 2.2) : 0;
      const nd = this.director.nearestEntity(cat.pos);
      cat.bristle = clamp(1 - nd / 3.2);
      if (cat.bristle > 0.6) this.rig.shake(0.05);
    } else {
      cat.earTargetWorld = null;
      cat.alert = 0;
      cat.bristle = 0;
    }
    updateSpectral(cat.vision);

    this.interactions(dt);

    // the cat's own night sight: a faint cool glow that follows it
    const sight = h.lights.get(16);
    if (sight.on) {
      sight.light.position.set(cat.pos.x, cat.pos.y + 0.55, cat.pos.z);
      const room = roomAt(cat.pos);
      if (room) h.lights.setRoomMask(16, room);
    }

    // camera
    const focus = cat.pos.clone().add(new THREE.Vector3(0, cat.mode === 'purr' ? 0.22 : 0.32, 0));
    this.rig.update(dt, this.input, focus, h.col, this.controls || cat.mode === 'purr', cat.running && Math.hypot(cat.vel.x, cat.vel.z) > 3);

    // audio
    this.audioUpdate(dt);
    this.hudUpdate();
  }

  /** weather, particles and ambient scares */
  private envFx(dt: number) {
    const cat = this.cat;
    const night = this.phase === 'night';
    const indoors = cat.pos.x > 0 && cat.pos.x < 12 && cat.pos.z > 0 && cat.pos.z < 10 && cat.pos.y < 9;
    this.weather.update(dt, this.camera, indoors);
    this.sun.intensity = this.sunBase + this.weather.boost * 5;
    this.hemi.intensity = this.hemiBase + this.weather.boost * 1.2;
    const maxFear = this.household.present.reduce((m, p) => Math.max(m, p.fear), 0);
    const dir = new THREE.Vector3(Math.sin(cat.yaw), 0, Math.cos(cat.yaw));
    const steamAt: THREE.Vector3[] = [];
    for (const f of this.house.faucets) if (f.running > 0.2 && f.id !== 'coz') steamAt.push(f.spout);
    this.atmos.setStreetLamp(this.house.lights.get(13).on);
    this.atmos.update(dt, { cam: this.camera.position, catPos: cat.pos, catDir: dir, fear: night ? maxFear : 0, hunted: cat.hunted, night, steamAt });
    if (night) {
      const cam = this.camera;
      this.ambient.update(dt, {
        house: this.house,
        camera: cam,
        catPos: cat.pos,
        night: this.world.night,
        observed: (p) => this.isObserved(p, false),
        angleTo: (p) => {
          const f = new THREE.Vector3();
          cam.getWorldDirection(f);
          const d = p.clone().sub(cam.position).normalize();
          return (Math.acos(clamp(f.dot(d), -1, 1)) * 180) / Math.PI;
        },
        creak: (p) => this.audio.creak(p, 0.3, 1.2),
      });
    }
  }

  /* ================================================================ hound */

  private hideSpot: HideSpot | null = null;

  hideAt(spot: HideSpot) {
    const c = this.cat;
    if (c.carrying) this.dropCarried();
    c.mode = 'hidden';
    c.modeTarget.set(...spot.p);
    c.modeYaw = spot.yaw;
    c.vel.set(0, 0, 0);
    this.hideSpot = spot;
    this.audio.pawStep(c.pos, false, true);
    this.hintOnce('hide', 'Parado e escondido, o cão não acha você. Ele fareja por perto e vai embora. Interagir para sair.');
  }

  unhide() {
    const c = this.cat;
    const spot = this.hideSpot;
    if (c.mode !== 'hidden') return;
    c.teleport(spot ? new THREE.Vector3(...spot.exit) : c.pos.clone(), c.yaw);
    this.hideSpot = null;
  }

  private onHoundCaught(from: THREE.Vector3) {
    const c = this.cat;
    this.dropCarried();
    c.stun(3.6, from);
    this.audio.catCry(c.head.clone(), 0.9);
    this.audio.bark(from.clone().add(new THREE.Vector3(0, 0.6, 0)), 0.8);
    this.rig.shake(1.2);
    this.world.fx.flash(0.35, '#7a0000');
    this.world.fx.distort(0.6);
    this.world.fx.ca(0.8);
    this.stats.caught++;
    // everyone in the house hears the cat scream
    for (const who of this.household.present) {
      const hops = this.world.hops(c.pos, who.pos);
      if (hops <= 3) {
        who.addFear(7);
        who.addPatience(-3);
        if (who.inBed && who.asleep) {
          who.asleep = false;
          who.say(who.cfg.skeptic ? 'Que grito foi esse?!' : '{cat}?! O que foi isso?!', 2.6, 'scared');
        }
      }
    }
    this.hintOnce('caught', 'O cão te pegou: você perdeu o Foco e foi jogado longe. Esconda-se, suba em móveis ou fuja pelo duto da próxima vez.');
  }

  private interactions(dt: number) {
    const cat = this.cat;
    if (!this.controls) {
      this.ui.prompt(null);
      this.holdT = 0;
      this.holdTarget = null;
      return;
    }
    if (cat.mode === 'hidden') {
      this.ui.prompt('Sair do esconderijo', 'interact', 0);
      if (this.input.wasPressed('interact') || this.input.wasPressed('jump')) this.unhide();
      return;
    }
    let best: Interactable | null =
      cat.mode === 'free' || cat.mode === 'purr'
        ? this.inter.best(cat.pos, cat.forward)
        : (cat.mode === 'scratch' || cat.mode === 'busy') && this.holdTarget && this.holdTarget.enabled()
          ? this.holdTarget
          : null;
    if (cat.mode === 'purr') best = this.inter.list.find((i) => i.id === `purr_${(this.purrWho ?? this.owner).cfg.id}`) ?? null;
    const swat = !best && !cat.carrying && cat.mode === 'free' ? this.house.props.nearSwattable(cat.pos) : null;
    const holding = this.input.isDown('interact');
    if (best) {
      const hold = typeof best.hold === 'function' ? best.hold() : best.hold ?? 0;
      if (hold > 0) {
        if (holding && (this.holdTarget === best || this.holdTarget === null)) {
          this.holdTarget = best;
          this.holdT += dt;
          cat.mode = best.pose === 'scratch' ? 'scratch' : 'busy';
          cat.modeTarget.copy(cat.pos);
          cat.modeYaw = Math.atan2(best.pos.x - cat.pos.x, best.pos.z - cat.pos.z);
          if (best.pose === 'scratch' && Math.random() < dt * 4) this.audio.pawStep(best.pos, true, false, 'wood');
          this.ui.prompt(best.holdLabel ? best.holdLabel() : best.prompt(), 'interact', clamp(this.holdT / hold));
          if (this.holdT >= hold) {
            this.holdT = 0;
            this.holdTarget = null;
            cat.mode = 'free';
            best.onInteract();
          }
        } else {
          if (this.holdTarget) {
            this.holdTarget = null;
            this.holdT = 0;
            if (cat.mode === 'scratch' || cat.mode === 'busy') cat.mode = 'free';
          }
          this.ui.prompt(best.prompt(), 'interact', 0);
        }
      } else {
        this.ui.prompt(best.prompt(), 'interact', 0);
        if (this.input.wasPressed('interact')) best.onInteract();
      }
    } else if (cat.carrying) {
      this.ui.prompt(`Soltar ${cat.carrying.name}`, 'interact', 0);
      if (this.input.wasPressed('interact')) this.dropCarried();
    } else if (swat) {
      this.ui.prompt('Derrubar', 'interact', 0);
      if (this.input.wasPressed('interact')) {
        this.catHop();
        this.house.props.swat(cat.pos, cat.forward);
      }
    } else {
      this.ui.prompt(null);
    }
    if (!holding && (cat.mode === 'scratch' || cat.mode === 'busy')) {
      cat.mode = 'free';
      this.holdT = 0;
      this.holdTarget = null;
    }
  }

  private audioUpdate(dt: number) {
    const a = this.audio;
    const o = this.owner;
    const lr = roomAt(this.camera.position) ?? roomAt(this.cat.pos);
    a.update(this.camera, (p) => {
      const sr = roomAt(p);
      if (!lr || !sr) {
        const outside = !sr;
        return { gain: outside && lr ? 0.55 : 1, cutoff: outside && lr ? 1400 : 20000 };
      }
      const hops = this.house.nav.hops(lr, sr);
      const g = [1, 0.75, 0.5, 0.36, 0.26][Math.min(4, hops)];
      const c = [20000, 2600, 1300, 750, 480][Math.min(4, hops)];
      return { gain: g, cutoff: c };
    });
    // heartbeat of the most frightened person
    const scared = this.household.present.reduce((m, p) => (p.fear > m.fear ? p : m), this.household.present[0] ?? o);
    if (this.phase === 'night' && scared.fear > 25 && scared.model.root.visible) {
      this.heartT -= dt;
      const k = (scared.fear - 25) / 75;
      if (this.heartT <= 0) {
        this.heartT = lerp(1.15, 0.42, k);
        a.heartbeat(0.25 + k * 0.6, scared.headPos());
      }
    }
    // the cat's own heart when it is hunted
    this.pulse = damp(this.pulse, 0, 7, dt);
    const hu = this.cat.hunted;
    if (hu > 0.25) {
      this.catHeartT -= dt;
      if (this.catHeartT <= 0) {
        this.catHeartT = lerp(0.85, 0.36, hu);
        a.heartbeat(0.3 + hu * 0.5, null);
        this.pulse = 1;
      }
    }
    // clock tick
    this.tickT -= dt;
    if (this.tickT <= 0) {
      this.tickT = 1;
      a.tick(this.house.clockPos);
    }
    // random house creaks at night
    if (this.phase === 'night') {
      this.creakT -= dt * (1 + scared.fear / 50);
      if (this.creakT <= 0) {
        this.creakT = rand(14, 30);
        const rooms: RoomId[] = ['corredor', 'hall', 'sotao', 'hospedes', 'escritorio', 'porao'];
        const r = ROOM_BY_ID[choose(rooms)];
        a.creak(new THREE.Vector3(rand(r.x0 + 0.5, r.x1 - 0.5), r.y + 2.2, rand(r.z0 + 0.5, r.z1 - 0.5)), 0.22, rand(0.6, 1.4), rand(0.7, 1.2));
      }
    }
    this.wind?.setLevel(this.phase === 'morning' ? 0.1 : this.phase === 'afternoon' ? 0.16 : 0.28);
    this.music.update(dt, this.phase === 'night' ? Math.max(this.director.tension(), scared.fear / 100) : 0);
  }

  private hudUpdate() {
    const s = Settings.data;
    const o = this.owner;
    // clock with Tab
    if (this.infoHeld > 0) {
      if (this.phase === 'night') this.ui.clock(formatClock(this.hour), `Noite ${this.day}`);
      else if (this.phase === 'morning') {
        this.refreshTasks();
        this.ui.clock('Manhã', `Dia ${this.day}`);
      } else this.ui.clock('Fim de tarde', `Dia ${this.day}`);
      if (this.phase === 'morning') this.ui.tasksVisible(true);
    } else {
      this.ui.clock(s.assist && this.phase === 'night' ? formatClock(this.hour) : null, `Noite ${this.day}`);
      if (this.phase === 'morning' && this.input.wasReleased('info')) this.ui.tasksVisible(false);
    }
    const night = this.phase === 'night';
    const urgent = night ? this.director.mostUrgent() : null;
    if (s.assist && (night || this.phase === 'afternoon')) {
      let arrow: number | null = null;
      const f = urgent?.focus;
      if (f && urgent!.stage >= 1) {
        const d = f.clone().sub(this.camera.position);
        const fwd = new THREE.Vector3();
        this.camera.getWorldDirection(fwd);
        fwd.y = 0;
        fwd.normalize();
        const right = new THREE.Vector3(-fwd.z, 0, fwd.x);
        arrow = Math.atan2(d.dot(right), d.setY(0).dot(fwd));
      }
      this.ui.assist({
        people: this.household.present.map((m) => ({ name: m.name, fear: m.fear, patience: m.patience })),
        focus: this.cat.focus,
        arrow,
      });
    } else this.ui.assist(null);
    // what is attacking whom (only once it is actually dangerous)
    if (night) {
      const att = this.director.all.filter((t) => t.enabled && t.stage >= 4 && t.id !== 'thing').sort((a, b) => b.stage - a.stage)[0];
      if (att) this.ui.alert(`${att.name} → ${att.target.name}`, THREAT_INFO[att.id].hint);
      else this.ui.alert(null);
      // contextual hiss prompt
      const can = this.controls && this.cat.mode === 'free' && this.director.canHissAt(this.cat.pos);
      this.ui.hiss(!can ? 'off' : this.cat.focus >= 22 ? 'ready' : 'weak');
    } else {
      this.ui.alert(null);
      this.ui.hiss('off');
    }
  }

  private postFx(dt: number) {
    const u = this.gr.u;
    const f = this.fx;
    f.fade = f.fade < f.fadeTarget ? Math.min(f.fadeTarget, f.fade + dt * f.fadeSpeed) : Math.max(f.fadeTarget, f.fade - dt * f.fadeSpeed);
    f.letterbox = damp(f.letterbox, f.letterTarget, 3, dt);
    f.flash = Math.max(0, f.flash - dt * 1.8);
    f.distort = Math.max(0, f.distort - dt * 0.9);
    f.ca = Math.max(0, f.ca - dt * 1.5);
    const maxFear = this.household.present.reduce((m, p) => Math.max(m, p.fear), 0);
    const fearK = this.phase === 'night' && this.mode !== 'menu' ? smoothstep(22, 100, maxFear) : 0;
    u.uFear.value = damp(u.uFear.value, fearK, 2, dt);
    u.uVision.value = this.mode === 'play' ? this.cat.vision : 0;
    u.uVignette.value = damp(u.uVignette.value, fearK * 0.7 + (this.lock.active ? 0.35 : 0) + (this.cat.mode === 'purr' ? 0.15 : 0), 2, dt);
    u.uHunt.value = damp(u.uHunt.value, this.mode === 'play' ? this.cat.hunted * 0.9 : 0, 3, dt);
    u.uPulse.value = this.pulse;
    u.uCA.value = f.ca + f.distort * 0.3;
    u.uDistort.value = f.distort;
    u.uFlash.value = f.flash;
    u.uFlashColor.value.copy(f.flashColor);
    u.uFade.value = f.fade;
    u.uLetterbox.value = f.letterbox;
    Shared.fear.value = fearK;
    u.uBright.value = Settings.data.brightness * this.envGamma;
    Shared.vision.value = this.cat.vision;
    // lights misbehave when Clara is terrified
    this.house.lights.ambientFlicker = this.phase === 'night' ? clamp((maxFear - 55) / 45) * 0.35 : 0;
    this.house.lights.lifetimes = this.phase === 'night' && this.mode === 'play';
  }
}
