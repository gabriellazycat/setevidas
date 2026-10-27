export type ClueId = 'foto' | 'coleira' | 'chave';

export interface WorldFlags {
  ductOpen: boolean;
  basculanteOpen: boolean;
  hatchOpen: boolean;
  /** Where each found clue currently rests (null = not found yet). */
  clues: Record<ClueId, { x: number; y: number; z: number; onCircle: boolean } | null>;
  marksSeen: string[];
  bathSceneDone: boolean;
}

export interface Snapshot {
  day: number;
  phase: 'morning' | 'night';
  flags: WorldFlags;
  patience: number;
  startFear: number;
}

export interface SaveData {
  version: 1;
  current: Snapshot;
  /** state at the start of the current day's morning (for "restart day") */
  morning: Snapshot | null;
  /** state at the start of the current night (for "restart night") */
  night: Snapshot | null;
  unlockedNight: number;
  everLocked: boolean;
  endingsSeen: string[];
  stats: { threatsRepelled: number; timesLocked: number };
}

const KEY = 'setevidas.save.v1';

export function freshFlags(): WorldFlags {
  return {
    ductOpen: false,
    basculanteOpen: false,
    hatchOpen: false,
    clues: { foto: null, coleira: null, chave: null },
    marksSeen: [],
    bathSceneDone: false,
  };
}

export function newGameSave(): SaveData {
  const snap: Snapshot = { day: 1, phase: 'night', flags: freshFlags(), patience: 70, startFear: 0 };
  return {
    version: 1,
    current: snap,
    morning: null,
    night: clone(snap),
    unlockedNight: 1,
    everLocked: false,
    endingsSeen: [],
    stats: { threatsRepelled: 0, timesLocked: 0 },
  };
}

export function clone<T>(v: T): T {
  return JSON.parse(JSON.stringify(v));
}

export function loadSave(): SaveData | null {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return null;
    const d = JSON.parse(raw) as SaveData;
    if (d.version !== 1) return null;
    return d;
  } catch {
    return null;
  }
}

export function writeSave(d: SaveData) {
  try {
    localStorage.setItem(KEY, JSON.stringify(d));
  } catch {
    /* ignore */
  }
}

export function loadMeta(): { unlockedNight: number; endingsSeen: string[] } {
  const s = loadSave();
  return { unlockedNight: s?.unlockedNight ?? 1, endingsSeen: s?.endingsSeen ?? [] };
}
