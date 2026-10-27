import type * as THREE from 'three';
import type { House } from '../world/House';
import type { Owner } from '../actors/Owner';
import type { Cat } from '../actors/Cat';
import type { AudioEngine } from '../audio/Audio';
import type { RoomId } from '../world/Layout';
import type { Household } from './Household';

export type ThreatId = 'shadow' | 'whisperer' | 'drowner' | 'doll' | 'visitor' | 'thing' | 'hound';

export interface Fx {
  shake(a: number): void;
  sting(a?: number): void;
  flash(a: number, color?: string): void;
  distort(a: number): void;
  ca(a: number): void;
}

/** Everything a threat (or a phase script) may touch. */
export interface World {
  scene: THREE.Scene;
  camera: THREE.PerspectiveCamera;
  house: House;
  owner: Owner;
  household: Household;
  pickTarget(id: ThreatId): Owner;
  cat: Cat;
  audio: AudioEngine;
  fx: Fx;
  night: number;
  /** global threat speed multiplier */
  speed: number;
  hour: number;
  roomOf(p: THREE.Vector3): RoomId | null;
  hops(a: THREE.Vector3, b: THREE.Vector3): number;
  isObserved(p: THREE.Vector3, needVisionOrLight: boolean): boolean;
  introduce(id: ThreatId): void;
  hint(text: string, dur?: number): void;
  repelled(id: ThreatId): void;
  catName: string;
}
