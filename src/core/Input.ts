export type Action =
  | 'jump'
  | 'interact'
  | 'vision'
  | 'meow'
  | 'hiss'
  | 'run'
  | 'sneak'
  | 'pause'
  | 'info'
  | 'confirm';

export type Device = 'kbm' | 'pad';

const KEYMAP: Record<string, Action> = {
  Space: 'jump',
  KeyE: 'interact',
  KeyQ: 'meow',
  KeyF: 'hiss',
  ShiftLeft: 'run',
  ShiftRight: 'run',
  ControlLeft: 'sneak',
  KeyC: 'sneak',
  Escape: 'pause',
  KeyP: 'pause',
  Tab: 'info',
  Enter: 'confirm',
  KeyV: 'vision',
};

// Standard gamepad mapping
const PADMAP: Partial<Record<number, Action>> = {
  0: 'jump',
  1: 'sneak',
  2: 'interact',
  3: 'meow',
  5: 'hiss',
  7: 'run',
  10: 'run',
  9: 'pause',
  8: 'info',
};

export class Input {
  private down = new Set<Action>();
  private pressed = new Set<Action>();
  private released = new Set<Action>();
  private keys = new Set<string>();
  private padPrev: boolean[] = [];
  private padDown = new Set<Action>();
  private mouseDownVision = false;
  private mouseDownInteract = false;

  move = { x: 0, y: 0 };
  look = { x: 0, y: 0 };
  padLook = { x: 0, y: 0 };
  lastDevice: Device = 'kbm';
  locked = false;
  enabled = true;
  onPointerLockChange?: (locked: boolean) => void;

  constructor(private el: HTMLElement) {
    window.addEventListener('keydown', (e) => {
      if (e.code === 'Tab') e.preventDefault();
      if (e.repeat) return;
      this.lastDevice = 'kbm';
      this.keys.add(e.code);
      const a = KEYMAP[e.code];
      if (a) this.setDown(a, true);
    });
    window.addEventListener('keyup', (e) => {
      this.keys.delete(e.code);
      const a = KEYMAP[e.code];
      if (a && !this.anyKeyFor(a)) this.setDown(a, false);
    });
    window.addEventListener('blur', () => {
      this.keys.clear();
      for (const a of [...this.down]) this.setDown(a, false);
    });
    el.addEventListener('mousedown', (e) => {
      this.lastDevice = 'kbm';
      if (e.button === 2) {
        this.mouseDownVision = true;
        this.setDown('vision', true);
      } else if (e.button === 0 && this.locked) {
        this.mouseDownInteract = true;
        this.setDown('interact', true);
      }
    });
    window.addEventListener('mouseup', (e) => {
      if (e.button === 2) {
        this.mouseDownVision = false;
        if (!this.anyKeyFor('vision')) this.setDown('vision', false);
      } else if (e.button === 0 && this.mouseDownInteract) {
        this.mouseDownInteract = false;
        if (!this.anyKeyFor('interact')) this.setDown('interact', false);
      }
    });
    el.addEventListener('contextmenu', (e) => e.preventDefault());
    window.addEventListener('mousemove', (e) => {
      if (!this.locked) return;
      this.look.x += e.movementX;
      this.look.y += e.movementY;
    });
    document.addEventListener('pointerlockchange', () => {
      this.locked = document.pointerLockElement === this.el;
      this.onPointerLockChange?.(this.locked);
    });
  }

  requestLock() {
    if (this.locked) return;
    const r = (this.el as any).requestPointerLock?.({ unadjustedMovement: true });
    if (r && typeof r.catch === 'function') {
      r.catch(() => (this.el as any).requestPointerLock?.());
    }
  }

  exitLock() {
    if (document.pointerLockElement) document.exitPointerLock();
  }

  private anyKeyFor(a: Action) {
    for (const k of this.keys) if (KEYMAP[k] === a) return true;
    if (a === 'vision' && this.mouseDownVision) return true;
    if (a === 'interact' && this.mouseDownInteract) return true;
    if (this.padDown.has(a)) return true;
    return false;
  }

  private setDown(a: Action, v: boolean) {
    if (v) {
      if (!this.down.has(a)) this.pressed.add(a);
      this.down.add(a);
    } else {
      if (this.down.has(a)) this.released.add(a);
      this.down.delete(a);
    }
  }

  /** Call once per frame before reading. */
  update() {
    // keyboard move vector
    let mx = 0;
    let my = 0;
    if (this.keys.has('KeyW') || this.keys.has('ArrowUp')) my += 1;
    if (this.keys.has('KeyS') || this.keys.has('ArrowDown')) my -= 1;
    if (this.keys.has('KeyA') || this.keys.has('ArrowLeft')) mx -= 1;
    if (this.keys.has('KeyD') || this.keys.has('ArrowRight')) mx += 1;

    this.padLook.x = 0;
    this.padLook.y = 0;
    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    const pad = Array.from(pads).find((p) => p && p.connected);
    if (pad) {
      const dz = (v: number) => (Math.abs(v) < 0.18 ? 0 : (v - Math.sign(v) * 0.18) / 0.82);
      const ax = dz(pad.axes[0] ?? 0);
      const ay = dz(pad.axes[1] ?? 0);
      const lx = dz(pad.axes[2] ?? 0);
      const ly = dz(pad.axes[3] ?? 0);
      if (ax || ay || lx || ly) this.lastDevice = 'pad';
      mx += ax;
      my -= ay;
      this.padLook.x = lx;
      this.padLook.y = ly;
      const newPadDown = new Set<Action>();
      pad.buttons.forEach((b, i) => {
        const isDown = b.pressed || b.value > 0.5;
        if (isDown && !this.padPrev[i]) this.lastDevice = 'pad';
        this.padPrev[i] = isDown;
        const a = i === 6 ? 'vision' : PADMAP[i];
        if (a && isDown) newPadDown.add(a);
      });
      // A also confirms in menus
      if (pad.buttons[0]?.pressed) newPadDown.add('confirm');
      const before = new Set(this.padDown);
      this.padDown = newPadDown;
      for (const a of newPadDown) if (!before.has(a)) this.setDown(a, true);
      for (const a of before) if (!newPadDown.has(a) && !this.anyKeyFor(a)) this.setDown(a, false);
    }

    const len = Math.hypot(mx, my);
    if (len > 1) {
      mx /= len;
      my /= len;
    }
    this.move.x = mx;
    this.move.y = my;
  }

  /** Call at end of frame. */
  endFrame() {
    this.pressed.clear();
    this.released.clear();
    this.look.x = 0;
    this.look.y = 0;
  }

  isDown(a: Action) {
    return this.enabled && this.down.has(a);
  }
  wasPressed(a: Action) {
    return this.enabled && this.pressed.has(a);
  }
  wasReleased(a: Action) {
    return this.enabled && this.released.has(a);
  }
  /** Raw edge check that ignores `enabled` (for menus/pause). */
  rawPressed(a: Action) {
    return this.pressed.has(a);
  }
  clearAll() {
    this.pressed.clear();
    this.released.clear();
  }
}

export const KEY_LABEL: Record<Action, { kbm: string; pad: string }> = {
  jump: { kbm: 'Espaço', pad: 'A' },
  interact: { kbm: 'E', pad: 'X' },
  vision: { kbm: 'Botão direito', pad: 'LT' },
  meow: { kbm: 'Q', pad: 'Y' },
  hiss: { kbm: 'F', pad: 'RB' },
  run: { kbm: 'Shift', pad: 'RT' },
  sneak: { kbm: 'Ctrl / C', pad: 'B' },
  pause: { kbm: 'Esc', pad: 'Start' },
  info: { kbm: 'Tab', pad: 'Select' },
  confirm: { kbm: 'Enter', pad: 'A' },
};
