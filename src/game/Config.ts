import type { ThreatId } from './World';

export const LAST_NIGHT = 7;
/** the day Davi moves in (afternoon) */
export const DAVI_DAY = 4;

/** which ghosts walk on each night (the hound is the cat's own enemy and is handled separately) */
export const NIGHT_THREATS: Record<number, ThreatId[]> = {
  1: ['shadow'],
  2: ['shadow', 'whisperer'],
  3: ['shadow', 'whisperer', 'drowner'],
  4: ['shadow', 'whisperer', 'drowner', 'doll'],
  5: ['shadow', 'whisperer', 'drowner', 'doll', 'visitor'],
  6: ['shadow', 'whisperer', 'drowner', 'doll', 'visitor'],
  7: ['shadow', 'whisperer', 'drowner', 'doll', 'visitor', 'thing'],
};

/** the threat that is new on each night */
export const NEW_ON_NIGHT: Record<number, ThreatId | null> = { 1: 'shadow', 2: 'whisperer', 3: 'drowner', 4: 'doll', 5: 'visitor', 6: null, 7: 'thing' };

export const NIGHT_LENGTH_MIN: Record<number, number> = { 1: 6, 2: 7.5, 3: 8.5, 4: 9.5, 5: 10.5, 6: 11, 7: 12 };
export const NIGHT_SPEED: Record<number, number> = { 1: 0.78, 2: 0.86, 3: 0.94, 4: 1.0, 5: 1.05, 6: 1.12, 7: 1.1 };

/** the hound hunts the cat from this night on */
export const HOUND_FROM = 2;
