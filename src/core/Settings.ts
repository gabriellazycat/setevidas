export type Quality = 'low' | 'medium' | 'high' | 'ultra';

export interface SettingsData {
  sensitivity: number;
  padSensitivity: number;
  invertY: boolean;
  fov: number;
  quality: Quality;
  renderScale: number;
  bloom: boolean;
  grain: boolean;
  brightness: number;
  master: number;
  music: number;
  sfx: number;
  ambience: number;
  subtitles: boolean;
  subtitleSize: 'm' | 'l';
  assist: boolean;
  reduceFlashes: boolean;
  cameraShake: boolean;
  nightSpeed: number;
  visionToggle: boolean;
  sneakToggle: boolean;
  catName: string;
}

const DEFAULTS: SettingsData = {
  sensitivity: 1,
  padSensitivity: 1,
  invertY: false,
  fov: 68,
  quality: 'high',
  renderScale: 1,
  bloom: true,
  grain: true,
  brightness: 1,
  master: 0.85,
  music: 0.7,
  sfx: 0.9,
  ambience: 0.8,
  subtitles: true,
  subtitleSize: 'm',
  assist: false,
  reduceFlashes: false,
  cameraShake: true,
  nightSpeed: 1,
  visionToggle: false,
  sneakToggle: true,
  catName: 'Mingau',
};

const KEY = 'setevidas.settings.v1';

class SettingsStore {
  data: SettingsData = { ...DEFAULTS };
  private listeners: ((s: SettingsData) => void)[] = [];

  constructor() {
    try {
      const raw = localStorage.getItem(KEY);
      if (raw) this.data = { ...DEFAULTS, ...JSON.parse(raw) };
    } catch {
      /* storage unavailable */
    }
  }

  get<K extends keyof SettingsData>(k: K): SettingsData[K] {
    return this.data[k];
  }

  set<K extends keyof SettingsData>(k: K, v: SettingsData[K]) {
    this.data[k] = v;
    this.persist();
    for (const l of this.listeners) l(this.data);
  }

  reset() {
    this.data = { ...DEFAULTS };
    this.persist();
    for (const l of this.listeners) l(this.data);
  }

  onChange(fn: (s: SettingsData) => void) {
    this.listeners.push(fn);
  }

  private persist() {
    try {
      localStorage.setItem(KEY, JSON.stringify(this.data));
    } catch {
      /* ignore */
    }
  }
}

export const Settings = new SettingsStore();
