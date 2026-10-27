/**
 * The house, as data. Units are meters. Front facade at z = 0 (street at -z).
 * Floors: basement y=-3, ground y=0, first y=3, attic y=6. Room height 2.8, slab 0.2.
 */

export type RoomId =
  | 'porao'
  | 'lavanderia'
  | 'sala'
  | 'escritorio'
  | 'hall'
  | 'cozinha'
  | 'banheiro_baixo'
  | 'quarto'
  | 'hospedes'
  | 'corredor'
  | 'banheiro_cima'
  | 'varanda'
  | 'sotao';

export const ROOM_H = 2.8;
export const TERRAIN_Y = -0.9;

export interface RoomDef {
  id: RoomId;
  name: string;
  y: number;
  x0: number;
  x1: number;
  z0: number;
  z1: number;
  h: number;
  wall: string;
  floor: string;
  ceiling: boolean;
  exterior?: boolean;
  light: number | null;
}

export const ROOMS: RoomDef[] = [
  { id: 'porao', name: 'Porão', y: -3, x0: 0, x1: 8, z0: 0, z1: 10, h: ROOM_H, wall: 'wall_brick', floor: 'floor_concrete', ceiling: true, light: 0 },
  { id: 'lavanderia', name: 'Lavanderia', y: -3, x0: 8, x1: 12, z0: 0, z1: 10, h: ROOM_H, wall: 'wall_lavanderia', floor: 'floor_concrete', ceiling: true, light: 1 },
  { id: 'sala', name: 'Sala', y: 0, x0: 0, x1: 5, z0: 0, z1: 5.5, h: ROOM_H, wall: 'wall_sala', floor: 'floor_wood', ceiling: true, light: 2 },
  { id: 'escritorio', name: 'Escritório', y: 0, x0: 0, x1: 5, z0: 5.5, z1: 10, h: ROOM_H, wall: 'wall_escritorio', floor: 'floor_wood_dark', ceiling: true, light: 3 },
  { id: 'hall', name: 'Hall', y: 0, x0: 5, x1: 7.5, z0: 0, z1: 10, h: ROOM_H, wall: 'wall_hall', floor: 'floor_wood', ceiling: true, light: 4 },
  { id: 'cozinha', name: 'Cozinha', y: 0, x0: 7.5, x1: 12, z0: 3.5, z1: 10, h: ROOM_H, wall: 'wall_cozinha', floor: 'floor_checker', ceiling: true, light: 5 },
  { id: 'banheiro_baixo', name: 'Banheiro de baixo', y: 0, x0: 7.5, x1: 12, z0: 0, z1: 3.5, h: ROOM_H, wall: 'wall_banheiro', floor: 'floor_tile', ceiling: true, light: 6 },
  { id: 'quarto', name: 'Quarto da Clara', y: 3, x0: 0, x1: 5, z0: 0, z1: 5.5, h: ROOM_H, wall: 'wall_quarto', floor: 'floor_wood', ceiling: true, light: 7 },
  { id: 'hospedes', name: 'Quarto de hóspedes', y: 3, x0: 0, x1: 5, z0: 5.5, z1: 10, h: ROOM_H, wall: 'wall_hospedes', floor: 'floor_wood', ceiling: true, light: 9 },
  { id: 'corredor', name: 'Corredor', y: 3, x0: 5, x1: 7.5, z0: 0, z1: 10, h: ROOM_H, wall: 'wall_corredor', floor: 'floor_wood', ceiling: true, light: 10 },
  { id: 'banheiro_cima', name: 'Banheiro de cima', y: 3, x0: 7.5, x1: 12, z0: 6, z1: 10, h: ROOM_H, wall: 'wall_banheiro', floor: 'floor_tile', ceiling: true, light: 11 },
  { id: 'varanda', name: 'Varanda', y: 3, x0: 7.5, x1: 12, z0: 0, z1: 6, h: ROOM_H, wall: 'exterior', floor: 'floor_wood_dark', ceiling: false, exterior: true, light: null },
  { id: 'sotao', name: 'Sótão', y: 6, x0: 0, x1: 7.5, z0: 0, z1: 10, h: 2.4, wall: 'wall_attic', floor: 'floor_attic', ceiling: false, light: 12 },
];

export const ROOM_BY_ID = Object.fromEntries(ROOMS.map((r) => [r.id, r])) as Record<RoomId, RoomDef>;

/** Holes cut out of floors (and the ceilings below them). */
export interface Rect {
  x0: number;
  x1: number;
  z0: number;
  z1: number;
}
export const STAIR_MAIN: Rect = { x0: 5, x1: 6.1, z0: 4.0, z1: 8.5 }; // ground -> first, rising +z
export const STAIR_BASE: Rect = { x0: 11, x1: 12, z0: 5.2, z1: 9.2 }; // basement -> kitchen, rising +z
export const HATCH: Rect = { x0: 6.3, x1: 7.4, z0: 1.0, z1: 2.3 }; // corridor ceiling -> attic

export const FLOOR_HOLES: Partial<Record<RoomId, Rect[]>> = {
  corredor: [STAIR_MAIN],
  cozinha: [STAIR_BASE],
  sotao: [HATCH],
};
export const CEILING_HOLES: Partial<Record<RoomId, Rect[]>> = {
  hall: [STAIR_MAIN],
  lavanderia: [STAIR_BASE],
  corredor: [HATCH],
};

/* ------------------------------------------------------------ walls */

export interface WallDef {
  /** 'z' = the wall runs along z (constant x). 'x' = runs along x (constant z). */
  axis: 'x' | 'z';
  fixed: number;
  a: number;
  b: number;
  y: number;
  h: number;
  t: number;
  neg: string | null;
  pos: string | null;
}

const EXT = 'exterior';
const EXB = 'exterior_base';
const T_EXT = 0.2;
const T_INT = 0.12;

export const WALLS: WallDef[] = [
  // basement perimeter (outer face is the stone base of the house)
  { axis: 'x', fixed: 0, a: -0.1, b: 8, y: -3, h: ROOM_H, t: T_EXT, neg: EXB, pos: 'wall_brick' },
  { axis: 'x', fixed: 0, a: 8, b: 12.1, y: -3, h: ROOM_H, t: T_EXT, neg: EXB, pos: 'wall_lavanderia' },
  { axis: 'x', fixed: 10, a: -0.1, b: 8, y: -3, h: ROOM_H, t: T_EXT, neg: 'wall_brick', pos: EXB },
  { axis: 'x', fixed: 10, a: 8, b: 12.1, y: -3, h: ROOM_H, t: T_EXT, neg: 'wall_lavanderia', pos: EXB },
  { axis: 'z', fixed: 0, a: 0, b: 10, y: -3, h: ROOM_H, t: T_EXT, neg: EXB, pos: 'wall_brick' },
  { axis: 'z', fixed: 12, a: 0, b: 10, y: -3, h: ROOM_H, t: T_EXT, neg: 'wall_lavanderia', pos: EXB },
  { axis: 'z', fixed: 8, a: 0, b: 10, y: -3, h: ROOM_H, t: T_INT, neg: 'wall_brick', pos: 'wall_lavanderia' },
  // basement slab edge between -0.2 and 0 (outside face)
  // ground floor perimeter
  { axis: 'x', fixed: 0, a: -0.1, b: 5, y: -0.2, h: 3.0, t: T_EXT, neg: EXT, pos: 'wall_sala' },
  { axis: 'x', fixed: 0, a: 5, b: 7.5, y: -0.2, h: 3.0, t: T_EXT, neg: EXT, pos: 'wall_hall' },
  { axis: 'x', fixed: 0, a: 7.5, b: 12.1, y: -0.2, h: 3.0, t: T_EXT, neg: EXT, pos: 'wall_banheiro' },
  { axis: 'x', fixed: 10, a: -0.1, b: 5, y: -0.2, h: 3.0, t: T_EXT, neg: 'wall_escritorio', pos: EXT },
  { axis: 'x', fixed: 10, a: 5, b: 7.5, y: -0.2, h: 3.0, t: T_EXT, neg: 'wall_hall', pos: EXT },
  { axis: 'x', fixed: 10, a: 7.5, b: 11, y: -0.2, h: 3.0, t: T_EXT, neg: 'wall_cozinha', pos: EXT },
  { axis: 'x', fixed: 10, a: 11, b: 12.1, y: -0.2, h: 3.0, t: T_EXT, neg: 'wall_corredor', pos: EXT },
  { axis: 'z', fixed: 0, a: 0, b: 5.5, y: -0.2, h: 3.0, t: T_EXT, neg: EXT, pos: 'wall_sala' },
  { axis: 'z', fixed: 0, a: 5.5, b: 10, y: -0.2, h: 3.0, t: T_EXT, neg: EXT, pos: 'wall_escritorio' },
  { axis: 'z', fixed: 12, a: 0, b: 3.5, y: -0.2, h: 3.0, t: T_EXT, neg: 'wall_banheiro', pos: EXT },
  { axis: 'z', fixed: 12, a: 3.5, b: 5.2, y: -0.2, h: 3.0, t: T_EXT, neg: 'wall_cozinha', pos: EXT },
  { axis: 'z', fixed: 12, a: 5.2, b: 10, y: -0.2, h: 3.0, t: T_EXT, neg: 'wall_corredor', pos: EXT },
  // ground floor interior
  { axis: 'z', fixed: 5, a: 0, b: 5.5, y: 0, h: ROOM_H, t: T_INT, neg: 'wall_sala', pos: 'wall_hall' },
  { axis: 'z', fixed: 5, a: 5.5, b: 10, y: 0, h: ROOM_H, t: T_INT, neg: 'wall_escritorio', pos: 'wall_hall' },
  { axis: 'z', fixed: 7.5, a: 0, b: 3.5, y: 0, h: ROOM_H, t: T_INT, neg: 'wall_hall', pos: 'wall_banheiro' },
  { axis: 'z', fixed: 7.5, a: 3.5, b: 10, y: 0, h: ROOM_H, t: T_INT, neg: 'wall_hall', pos: 'wall_cozinha' },
  { axis: 'x', fixed: 5.5, a: 0, b: 5, y: 0, h: ROOM_H, t: T_INT, neg: 'wall_sala', pos: 'wall_escritorio' },
  { axis: 'x', fixed: 3.5, a: 7.5, b: 12, y: 0, h: ROOM_H, t: T_INT, neg: 'wall_banheiro', pos: 'wall_cozinha' },
  // basement stairwell enclosure (inside kitchen)
  { axis: 'z', fixed: 11, a: 5.2, b: 10, y: 0, h: ROOM_H, t: T_INT, neg: 'wall_cozinha', pos: 'wall_corredor' },
  { axis: 'x', fixed: 5.2, a: 11, b: 12, y: 0, h: ROOM_H, t: T_INT, neg: 'wall_cozinha', pos: 'wall_corredor' },
  // first floor perimeter
  { axis: 'x', fixed: 0, a: -0.1, b: 5, y: 2.8, h: 3.0, t: T_EXT, neg: EXT, pos: 'wall_quarto' },
  { axis: 'x', fixed: 0, a: 5, b: 7.6, y: 2.8, h: 3.0, t: T_EXT, neg: EXT, pos: 'wall_corredor' },
  { axis: 'x', fixed: 10, a: -0.1, b: 5, y: 2.8, h: 3.0, t: T_EXT, neg: 'wall_hospedes', pos: EXT },
  { axis: 'x', fixed: 10, a: 5, b: 7.5, y: 2.8, h: 3.0, t: T_EXT, neg: 'wall_corredor', pos: EXT },
  { axis: 'x', fixed: 10, a: 7.5, b: 12.1, y: 2.8, h: 3.0, t: T_EXT, neg: 'wall_banheiro', pos: EXT },
  { axis: 'z', fixed: 0, a: 0, b: 5.5, y: 2.8, h: 3.0, t: T_EXT, neg: EXT, pos: 'wall_quarto' },
  { axis: 'z', fixed: 0, a: 5.5, b: 10, y: 2.8, h: 3.0, t: T_EXT, neg: EXT, pos: 'wall_hospedes' },
  { axis: 'z', fixed: 12, a: 5.9, b: 10, y: 2.8, h: 3.0, t: T_EXT, neg: 'wall_banheiro', pos: EXT },
  // walls facing the balcony
  { axis: 'z', fixed: 7.5, a: 0, b: 6, y: 3, h: ROOM_H, t: T_EXT, neg: 'wall_corredor', pos: EXT },
  { axis: 'x', fixed: 6, a: 7.6, b: 12.1, y: 3, h: ROOM_H, t: T_EXT, neg: EXT, pos: 'wall_banheiro' },
  // first floor interior
  { axis: 'z', fixed: 5, a: 0, b: 5.5, y: 3, h: ROOM_H, t: T_INT, neg: 'wall_quarto', pos: 'wall_corredor' },
  { axis: 'z', fixed: 5, a: 5.5, b: 10, y: 3, h: ROOM_H, t: T_INT, neg: 'wall_hospedes', pos: 'wall_corredor' },
  { axis: 'x', fixed: 5.5, a: 0, b: 5, y: 3, h: ROOM_H, t: T_INT, neg: 'wall_quarto', pos: 'wall_hospedes' },
  { axis: 'z', fixed: 7.5, a: 6, b: 10, y: 3, h: ROOM_H, t: T_INT, neg: 'wall_corredor', pos: 'wall_banheiro' },
];

/* ------------------------------------------------------------ doors / windows */

export type DoorStyle = 'interior' | 'front' | 'basement' | 'glass';
export type DoorState = 'closed' | 'ajar' | 'open';

export interface DoorDef {
  id: string;
  axis: 'x' | 'z';
  fixed: number;
  s0: number;
  s1: number;
  y: number;
  h: number;
  hinge: 0 | 1;
  swing: 1 | -1;
  state: DoorState;
  style: DoorStyle;
  name: string;
}

export const DOORS: DoorDef[] = [
  { id: 'd_sala', axis: 'z', fixed: 5, s0: 1.5, s1: 2.4, y: 0, h: 2.1, hinge: 0, swing: -1, state: 'open', style: 'interior', name: 'porta da sala' },
  { id: 'd_esc', axis: 'z', fixed: 5, s0: 8.6, s1: 9.5, y: 0, h: 2.1, hinge: 1, swing: -1, state: 'ajar', style: 'interior', name: 'porta do escritório' },
  { id: 'd_banb', axis: 'z', fixed: 7.5, s0: 1.5, s1: 2.3, y: 0, h: 2.1, hinge: 0, swing: 1, state: 'ajar', style: 'interior', name: 'porta do banheiro' },
  { id: 'd_front', axis: 'x', fixed: 0, s0: 6.0, s1: 6.9, y: 0, h: 2.15, hinge: 1, swing: 1, state: 'closed', style: 'front', name: 'porta da frente' },
  { id: 'd_porao', axis: 'z', fixed: 11, s0: 9.2, s1: 10, y: 0, h: 2.05, hinge: 1, swing: -1, state: 'closed', style: 'basement', name: 'porta do porão' },
  { id: 'd_quarto', axis: 'z', fixed: 5, s0: 1.2, s1: 2.1, y: 3, h: 2.1, hinge: 0, swing: -1, state: 'ajar', style: 'interior', name: 'porta do quarto' },
  { id: 'd_hosp', axis: 'z', fixed: 5, s0: 8.7, s1: 9.6, y: 3, h: 2.1, hinge: 1, swing: -1, state: 'ajar', style: 'interior', name: 'porta dos hóspedes' },
  { id: 'd_banc', axis: 'z', fixed: 7.5, s0: 8.7, s1: 9.5, y: 3, h: 2.1, hinge: 1, swing: 1, state: 'open', style: 'interior', name: 'porta do banheiro' },
  { id: 'd_varanda', axis: 'z', fixed: 7.5, s0: 3.3, s1: 4.2, y: 3, h: 2.1, hinge: 0, swing: 1, state: 'ajar', style: 'glass', name: 'porta da varanda' },
];

export interface OpeningDef {
  axis: 'x' | 'z';
  fixed: number;
  s0: number;
  s1: number;
  y0: number;
  y1: number;
}

export interface WindowDef extends OpeningDef {
  id: string;
  exterior: boolean;
  curtains?: boolean;
  /** which side is inside: -1 = negative side of the wall, +1 = positive */
  inside: 1 | -1;
  small?: boolean;
}

export const WINDOWS: WindowDef[] = [
  // basement light wells
  { id: 'w_porao1', axis: 'x', fixed: 0, s0: 2, s1: 3.2, y0: -0.82, y1: -0.35, exterior: true, inside: 1, small: true },
  { id: 'w_porao2', axis: 'x', fixed: 0, s0: 5, s1: 6.2, y0: -0.82, y1: -0.35, exterior: true, inside: 1, small: true },
  { id: 'w_lav', axis: 'x', fixed: 0, s0: 9, s1: 10, y0: -0.82, y1: -0.35, exterior: true, inside: 1, small: true },
  // ground
  { id: 'w_sala_f', axis: 'x', fixed: 0, s0: 1.2, s1: 3.8, y0: 0.85, y1: 2.25, exterior: true, inside: 1, curtains: true },
  { id: 'w_sala_w', axis: 'z', fixed: 0, s0: 2.0, s1: 3.5, y0: 0.85, y1: 2.25, exterior: true, inside: 1, curtains: true },
  { id: 'w_banb', axis: 'x', fixed: 0, s0: 9.6, s1: 10.6, y0: 1.55, y1: 2.25, exterior: true, inside: 1, curtains: true, small: true },
  { id: 'w_esc_b', axis: 'x', fixed: 10, s0: 1.5, s1: 3.5, y0: 0.95, y1: 2.25, exterior: true, inside: -1, curtains: true },
  { id: 'w_esc_w', axis: 'z', fixed: 0, s0: 7.0, s1: 8.5, y0: 0.85, y1: 2.25, exterior: true, inside: 1, curtains: true },
  { id: 'w_hall_b', axis: 'x', fixed: 10, s0: 6.2, s1: 7.0, y0: 1.0, y1: 2.25, exterior: true, inside: -1 },
  { id: 'w_coz_b', axis: 'x', fixed: 10, s0: 7.8, s1: 8.8, y0: 1.2, y1: 2.25, exterior: true, inside: -1, curtains: true },
  { id: 'w_coz_e', axis: 'z', fixed: 12, s0: 3.8, s1: 4.9, y0: 1.15, y1: 2.25, exterior: true, inside: -1, curtains: true },
  // first
  { id: 'w_quarto_f', axis: 'x', fixed: 0, s0: 1.5, s1: 3.5, y0: 3.85, y1: 5.25, exterior: true, inside: 1, curtains: true },
  { id: 'w_quarto_w', axis: 'z', fixed: 0, s0: 4.2, s1: 5.0, y0: 3.85, y1: 5.25, exterior: true, inside: 1, curtains: true },
  { id: 'w_cor_f', axis: 'x', fixed: 0, s0: 5.5, s1: 6.2, y0: 3.9, y1: 5.25, exterior: true, inside: 1, curtains: true },
  { id: 'w_hosp_b', axis: 'x', fixed: 10, s0: 2.0, s1: 3.5, y0: 3.9, y1: 5.25, exterior: true, inside: -1, curtains: true },
  { id: 'w_hosp_w', axis: 'z', fixed: 0, s0: 7.0, s1: 8.5, y0: 3.85, y1: 5.25, exterior: true, inside: 1, curtains: true },
  { id: 'w_banc_e', axis: 'z', fixed: 12, s0: 7.3, s1: 8.3, y0: 4.3, y1: 5.3, exterior: true, inside: -1 },
  // the basculante: from the upper bathroom out onto the balcony
  { id: 'w_basculante', axis: 'x', fixed: 6, s0: 10.0, s1: 10.8, y0: 4.6, y1: 5.3, exterior: true, inside: 1, small: true },
];

/** Openings without a door leaf. */
export const ARCHES: OpeningDef[] = [
  { axis: 'z', fixed: 7.5, s0: 5.6, s1: 6.8, y0: 0, y1: 2.3 }, // hall -> kitchen
  { axis: 'z', fixed: 8, s0: 7.0, s1: 7.9, y0: -3, y1: -0.9 }, // porão -> lavanderia
];

/* ------------------------------------------------------------ lights */

export interface LightDef {
  index: number;
  room: RoomId | 'exterior' | 'dynamic';
  pos: [number, number, number];
  color: string;
  intensity: number;
  distance: number;
  fixture: 'pendant' | 'bulb' | 'flush' | 'lamp' | 'chandelier' | 'street' | 'none';
  /** switch location + facing (normal) */
  sw?: { p: [number, number, number]; n: [number, number, number] };
  name: string;
}

export const LIGHTS: LightDef[] = [
  { index: 0, room: 'porao', pos: [3.8, -0.55, 5.2], color: '#ffc985', intensity: 16.8, distance: 12, fixture: 'bulb', sw: { p: [7.93, -1.9, 6.6], n: [-1, 0, 0] }, name: 'luz do porão' },
  { index: 1, room: 'lavanderia', pos: [10.0, -0.42, 3.0], color: '#e4ecff', intensity: 15.0, distance: 11, fixture: 'flush', sw: { p: [8.07, -1.9, 6.6], n: [1, 0, 0] }, name: 'luz da lavanderia' },
  { index: 2, room: 'sala', pos: [2.5, 2.2, 2.75], color: '#ffd59a', intensity: 22.4, distance: 12, fixture: 'chandelier', sw: { p: [4.93, 1.1, 2.65], n: [-1, 0, 0] }, name: 'luz da sala' },
  { index: 3, room: 'escritorio', pos: [2.5, 2.4, 7.75], color: '#ffe2b0', intensity: 18.7, distance: 11, fixture: 'pendant', sw: { p: [4.93, 1.1, 8.35], n: [-1, 0, 0] }, name: 'luz do escritório' },
  { index: 4, room: 'hall', pos: [6.6, 2.45, 3.4], color: '#ffd9a0', intensity: 18.7, distance: 12, fixture: 'pendant', sw: { p: [5.07, 1.1, 1.2], n: [1, 0, 0] }, name: 'luz do hall' },
  { index: 5, room: 'cozinha', pos: [9.75, 2.5, 6.75], color: '#fff0d4', intensity: 22.4, distance: 12, fixture: 'flush', sw: { p: [7.57, 1.1, 5.3], n: [1, 0, 0] }, name: 'luz da cozinha' },
  { index: 6, room: 'banheiro_baixo', pos: [9.75, 2.5, 1.75], color: '#f2f5ff', intensity: 15.0, distance: 9, fixture: 'flush', sw: { p: [7.57, 1.1, 1.15], n: [1, 0, 0] }, name: 'luz do banheiro' },
  { index: 7, room: 'quarto', pos: [2.5, 5.45, 2.75], color: '#ffd6a2', intensity: 18.7, distance: 11, fixture: 'pendant', sw: { p: [4.93, 4.1, 2.35], n: [-1, 0, 0] }, name: 'luz do quarto' },
  { index: 8, room: 'quarto', pos: [0.3, 3.98, 1.68], color: '#ffad66', intensity: 7.2, distance: 6.5, fixture: 'lamp', name: 'abajur' },
  { index: 9, room: 'hospedes', pos: [2.5, 5.45, 7.75], color: '#ffdcae', intensity: 16.8, distance: 11, fixture: 'pendant', sw: { p: [4.93, 4.1, 8.45], n: [-1, 0, 0] }, name: 'luz dos hóspedes' },
  { index: 10, room: 'corredor', pos: [6.4, 5.5, 5.2], color: '#ffe0b0', intensity: 18.7, distance: 12, fixture: 'flush', sw: { p: [6.9, 4.1, 9.89], n: [0, 0, -1] }, name: 'luz do corredor' },
  { index: 11, room: 'banheiro_cima', pos: [9.75, 5.5, 8.0], color: '#f2f5ff', intensity: 15.0, distance: 9, fixture: 'flush', sw: { p: [7.57, 4.1, 8.45], n: [1, 0, 0] }, name: 'luz do banheiro' },
  { index: 12, room: 'sotao', pos: [3.75, 7.75, 5.0], color: '#ffc27a', intensity: 15.0, distance: 11, fixture: 'bulb', sw: { p: [5.5, 6.55, 1.8], n: [0, 0, 1] }, name: 'luz do sótão' },
  { index: 13, room: 'exterior', pos: [-1.8, 4.3, -7.0], color: '#ffb560', intensity: 120.0, distance: 27.5, fixture: 'street', name: 'poste' },
  { index: 14, room: 'dynamic', pos: [0, -50, 0], color: '#9fc8ff', intensity: 9, distance: 6, fixture: 'none', name: 'tela' },
  { index: 15, room: 'dynamic', pos: [0, -50, 0], color: '#ff3b2f', intensity: 22, distance: 9, fixture: 'none', name: 'fx' },
  { index: 16, room: 'dynamic', pos: [0, -50, 0], color: '#9db8ff', intensity: 2.4, distance: 3.6, fixture: 'none', name: 'visão noturna' },
  { index: 17, room: 'hospedes', pos: [0.3, 3.98, 9.2], color: '#ffb066', intensity: 6.5, distance: 6.5, fixture: 'lamp', name: 'abajur de Davi' },
];

/* ------------------------------------------------------------ navigation */

export interface NavNodeDef {
  id: string;
  p: [number, number, number];
  room: RoomId;
}

export const NAV_NODES: NavNodeDef[] = [
  // ground
  { id: 'g_hall_front', p: [6.45, 0, 1.0], room: 'hall' },
  { id: 'g_d_sala_h', p: [5.6, 0, 1.95], room: 'hall' },
  { id: 'g_sala_door', p: [4.4, 0, 1.95], room: 'sala' },
  { id: 'g_sala_mid', p: [2.5, 0, 2.35], room: 'sala' },
  { id: 'g_sala_tv', p: [2.5, 0, 4.45], room: 'sala' },
  { id: 'g_sala_win', p: [0.7, 0, 2.75], room: 'sala' },
  { id: 'g_hall_mid', p: [6.75, 0, 3.0], room: 'hall' },
  { id: 'g_d_banb_h', p: [6.9, 0, 1.9], room: 'hall' },
  { id: 'g_banb_door', p: [8.1, 0, 1.9], room: 'banheiro_baixo' },
  { id: 'g_banb_mid', p: [9.3, 0, 1.4], room: 'banheiro_baixo' },
  { id: 'g_stairs_b', p: [5.55, 0, 3.8], room: 'hall' },
  { id: 'g_hall_kitchen', p: [6.85, 0, 6.2], room: 'hall' },
  { id: 'g_hall_back', p: [6.6, 0, 9.05], room: 'hall' },
  { id: 'g_d_esc_h', p: [5.6, 0, 9.05], room: 'hall' },
  { id: 'g_esc_door', p: [4.4, 0, 9.05], room: 'escritorio' },
  { id: 'g_esc_mid', p: [2.5, 0, 8.6], room: 'escritorio' },
  { id: 'g_coz_arch', p: [8.1, 0, 6.2], room: 'cozinha' },
  { id: 'g_coz_n', p: [8.1, 0, 8.5], room: 'cozinha' },
  { id: 'g_coz_sink', p: [8.8, 0, 8.95], room: 'cozinha' },
  { id: 'g_coz_bowl', p: [8.65, 0, 4.7], room: 'cozinha' },
  { id: 'g_coz_e', p: [10.05, 0, 5.0], room: 'cozinha' },
  { id: 'g_coz_radio', p: [10.05, 0, 6.4], room: 'cozinha' },
  { id: 'g_coz_bdoor', p: [10.6, 0, 9.6], room: 'cozinha' },
  { id: 'g_bst_top', p: [11.5, 0, 9.4], room: 'cozinha' },
  // basement
  { id: 'b_bst_bot', p: [11.5, -3, 5.0], room: 'lavanderia' },
  { id: 'b_lav_mid', p: [10.2, -3, 3.4], room: 'lavanderia' },
  { id: 'b_lav_door', p: [8.6, -3, 7.45], room: 'lavanderia' },
  { id: 'b_porao_door', p: [7.4, -3, 7.45], room: 'porao' },
  { id: 'b_porao_mid', p: [4.6, -3, 6.0], room: 'porao' },
  { id: 'b_porao_circle', p: [3.6, -3, 4.4], room: 'porao' },
  // first
  { id: 'f_stairs_t', p: [5.55, 3, 8.7], room: 'corredor' },
  { id: 'f_d_hosp_c', p: [5.55, 3, 9.15], room: 'corredor' },
  { id: 'f_hosp_door', p: [4.4, 3, 9.15], room: 'hospedes' },
  { id: 'f_hosp_mid', p: [3.0, 3, 8.4], room: 'hospedes' },
  { id: 'f_hosp_bed', p: [2.65, 3, 8.3], room: 'hospedes' },
  { id: 'f_cor_back', p: [6.65, 3, 9.15], room: 'corredor' },
  { id: 'f_d_banc_c', p: [6.95, 3, 9.1], room: 'corredor' },
  { id: 'f_banc_door', p: [8.1, 3, 9.1], room: 'banheiro_cima' },
  { id: 'f_banc_mid', p: [9.5, 3, 7.9], room: 'banheiro_cima' },
  { id: 'f_banc_tub', p: [10.6, 3, 8.75], room: 'banheiro_cima' },
  { id: 'f_cor_mid', p: [6.8, 3, 6.0], room: 'corredor' },
  { id: 'f_cor_s', p: [6.8, 3, 3.75], room: 'corredor' },
  { id: 'f_var_door', p: [8.2, 3, 3.75], room: 'varanda' },
  { id: 'f_var_mid', p: [9.8, 3, 2.2], room: 'varanda' },
  { id: 'f_cor_front', p: [5.75, 3, 3.3], room: 'corredor' },
  { id: 'f_d_quarto_c', p: [5.6, 3, 1.65], room: 'corredor' },
  { id: 'f_quarto_door', p: [4.4, 3, 1.65], room: 'quarto' },
  { id: 'f_quarto_bed', p: [2.7, 3, 2.85], room: 'quarto' },
  { id: 'f_ladder', p: [6.85, 3, 3.3], room: 'corredor' },
  // attic (ghost only)
  { id: 'a_hatch', p: [5.9, 6, 1.6], room: 'sotao' },
  { id: 'a_mid', p: [3.75, 6, 5.0], room: 'sotao' },
  { id: 'a_chest', p: [3.1, 6, 8.1], room: 'sotao' },
];

export const NAV_EDGES: [string, string, boolean?][] = [
  ['g_hall_front', 'g_d_sala_h'],
  ['g_d_sala_h', 'g_sala_door'],
  ['g_sala_door', 'g_sala_mid'],
  ['g_sala_mid', 'g_sala_tv'],
  ['g_sala_mid', 'g_sala_win'],
  ['g_hall_front', 'g_hall_mid'],
  ['g_d_sala_h', 'g_hall_mid'],
  ['g_hall_mid', 'g_d_banb_h'],
  ['g_hall_front', 'g_d_banb_h'],
  ['g_d_banb_h', 'g_banb_door'],
  ['g_banb_door', 'g_banb_mid'],
  ['g_hall_mid', 'g_stairs_b'],
  ['g_hall_mid', 'g_hall_kitchen'],
  ['g_hall_kitchen', 'g_coz_arch'],
  ['g_hall_kitchen', 'g_hall_back'],
  ['g_hall_back', 'g_d_esc_h'],
  ['g_d_esc_h', 'g_esc_door'],
  ['g_esc_door', 'g_esc_mid'],
  ['g_coz_arch', 'g_coz_n'],
  ['g_coz_n', 'g_coz_sink'],
  ['g_coz_arch', 'g_coz_bowl'],
  ['g_coz_bowl', 'g_coz_e'],
  ['g_coz_e', 'g_coz_radio'],
  ['g_coz_sink', 'g_coz_bdoor'],
  ['g_coz_bdoor', 'g_bst_top'],
  ['g_bst_top', 'b_bst_bot'],
  ['b_bst_bot', 'b_lav_mid'],
  ['b_bst_bot', 'b_lav_door'],
  ['b_lav_mid', 'b_lav_door'],
  ['b_lav_door', 'b_porao_door'],
  ['b_porao_door', 'b_porao_mid'],
  ['b_porao_mid', 'b_porao_circle'],
  ['g_stairs_b', 'f_stairs_t'],
  ['f_stairs_t', 'f_d_hosp_c'],
  ['f_stairs_t', 'f_cor_back'],
  ['f_d_hosp_c', 'f_hosp_door'],
  ['f_hosp_door', 'f_hosp_mid'],
  ['f_hosp_mid', 'f_hosp_bed'],
  ['f_d_hosp_c', 'f_cor_back'],
  ['f_cor_back', 'f_d_banc_c'],
  ['f_d_banc_c', 'f_banc_door'],
  ['f_banc_door', 'f_banc_mid'],
  ['f_banc_mid', 'f_banc_tub'],
  ['f_cor_back', 'f_cor_mid'],
  ['f_cor_mid', 'f_cor_s'],
  ['f_cor_s', 'f_var_door'],
  ['f_var_door', 'f_var_mid'],
  ['f_cor_s', 'f_cor_front'],
  ['f_cor_front', 'f_d_quarto_c'],
  ['f_d_quarto_c', 'f_quarto_door'],
  ['f_quarto_door', 'f_quarto_bed'],
  ['f_cor_s', 'f_ladder', true],
  ['f_ladder', 'a_hatch', true],
  ['a_hatch', 'a_mid', true],
  ['a_mid', 'a_chest', true],
];

/* ------------------------------------------------------------ owner spots */

export interface Spot {
  node: string;
  p: [number, number, number];
  /** yaw the character faces (radians, 0 = +z) */
  yaw: number;
}

export const SPOTS: Record<string, Spot> = {
  bed: { node: 'f_quarto_bed', p: [1.2, 3.05, 2.8], yaw: Math.PI / 2 },
  bedside: { node: 'f_quarto_bed', p: [2.65, 3, 2.8], yaw: -Math.PI / 2 },
  kitchenSink: { node: 'g_coz_sink', p: [8.8, 0, 8.95], yaw: 0 },
  kitchenWindow: { node: 'g_coz_sink', p: [8.3, 0, 9.0], yaw: 0 },
  bathroomUp: { node: 'f_banc_mid', p: [9.8, 3, 7.6], yaw: Math.PI / 2 },
  tub: { node: 'f_banc_tub', p: [10.6, 3, 8.75], yaw: 0 },
  tv: { node: 'g_sala_tv', p: [2.5, 0, 4.45], yaw: 0 },
  radio: { node: 'g_coz_radio', p: [10.05, 0, 6.4], yaw: Math.PI / 2 },
  laptop: { node: 'g_esc_mid', p: [2.45, 0, 8.85], yaw: 0 },
  frontDoor: { node: 'g_hall_front', p: [6.45, 0, 0.75], yaw: Math.PI },
  salaWindow: { node: 'g_sala_win', p: [0.75, 0, 2.75], yaw: -Math.PI / 2 },
  bowl: { node: 'g_coz_bowl', p: [8.65, 0, 4.6], yaw: Math.PI },
  sofa: { node: 'g_sala_mid', p: [2.5, 0, 1.45], yaw: 0 },
  desk: { node: 'g_esc_mid', p: [2.45, 0, 8.85], yaw: 0 },
  hallPhone: { node: 'g_hall_mid', p: [6.75, 0, 3.0], yaw: Math.PI / 2 },
  davBed: { node: 'f_hosp_bed', p: [1.2, 3.05, 8.3], yaw: Math.PI / 2 },
  davBedside: { node: 'f_hosp_bed', p: [2.65, 3, 8.3], yaw: -Math.PI / 2 },
  sofaR: { node: 'g_sala_mid', p: [3.35, 0, 1.45], yaw: 0 },
  bathTubIn: { node: 'f_banc_tub', p: [10.75, 3.12, 9.57], yaw: -Math.PI / 2 },
};

/** Where the cat sleeps in the morning/afternoon to skip time. */
export const CAT_BED: [number, number, number] = [4.25, 0, 4.6];
export const CAT_START: [number, number, number] = [2.9, 3, 3.9];

export const RITUAL_CENTER: [number, number, number] = [3.6, -3, 4.4];


export interface HideSpot {
  id: string;
  name: string;
  p: [number, number, number];
  exit: [number, number, number];
  room: RoomId;
  yaw: number;
}

/** places where the cat can wait out the hound */
export const HIDE_SPOTS: HideSpot[] = [
  { id: 'sofa', name: 'atrás do sofá', p: [2.5, 0, 0.6], exit: [2.5, 0, 0.62], room: 'sala', yaw: 0 },
  { id: 'mesa', name: 'sob a mesa da cozinha', p: [9.2, 0, 6.7], exit: [8.35, 0, 6.7], room: 'cozinha', yaw: 0 },
  { id: 'escrivaninha', name: 'sob a escrivaninha', p: [2.4, 0, 9.6], exit: [1.2, 0, 9.5], room: 'escritorio', yaw: Math.PI },
  { id: 'caixas', name: 'entre as caixas', p: [2.18, -3, 9.3], exit: [2.2, -3, 8.5], room: 'porao', yaw: 0 },
  { id: 'tabua', name: 'sob a tábua de passar', p: [9.9, -3, 4.45], exit: [9.9, -3, 3.8], room: 'lavanderia', yaw: 0 },
];
