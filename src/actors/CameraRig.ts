import * as THREE from 'three';
import type { Input } from '../core/Input';
import type { ColliderWorld, Box } from '../world/Colliders';
import { Settings } from '../core/Settings';
import { clamp, damp, dampV3, noise1 } from '../core/math';

const CAM_TAGS = new Set(['wall', 'floor', 'ceiling', 'roof', 'door', 'terrain', 'hatch', 'stair', 'porch', 'basculante']);

/** Third-person orbit camera with collision, built for a small, low character. */
export class CameraRig {
  yaw = Math.PI;
  pitch = -0.22;
  distance = 1.55;
  private curDist = 1.55;
  target = new THREE.Vector3();
  private smoothTarget = new THREE.Vector3();
  private shakeAmt = 0;
  private shakeT = 0;
  fovKick = 0;
  /** cinematic override */
  override: { pos: THREE.Vector3; look: THREE.Vector3; blend: number } | null = null;
  private filter = (b: Box) => b.camera || CAM_TAGS.has(b.tag);

  constructor(public camera: THREE.PerspectiveCamera) {}

  snap(target: THREE.Vector3, yaw?: number) {
    if (yaw !== undefined) this.yaw = yaw;
    this.smoothTarget.copy(target);
    this.target.copy(target);
    this.curDist = this.distance;
  }

  shake(amount: number) {
    if (!Settings.data.cameraShake) amount *= 0.15;
    this.shakeAmt = Math.max(this.shakeAmt, amount);
  }

  update(dt: number, input: Input, focus: THREE.Vector3, col: ColliderWorld, controls: boolean, running: boolean) {
    const s = Settings.data;
    if (controls) {
      const sens = 0.0022 * s.sensitivity;
      this.yaw -= input.look.x * sens;
      this.pitch -= input.look.y * sens * (s.invertY ? -1 : 1);
      const ps = 2.6 * s.padSensitivity * dt;
      this.yaw -= input.padLook.x * ps;
      this.pitch -= input.padLook.y * ps * 0.75 * (s.invertY ? -1 : 1);
    }
    this.pitch = clamp(this.pitch, -1.15, 0.65);

    this.target.copy(focus);
    dampV3(this.smoothTarget, this.target, 14, dt);
    // vertical smoothing is gentler (stairs, jumps)
    const tgt = this.smoothTarget;

    const cp = Math.cos(this.pitch);
    const dir = new THREE.Vector3(-Math.sin(this.yaw) * cp, -Math.sin(this.pitch), -Math.cos(this.yaw) * cp);
    // dir points from target to camera (behind the look direction)
    const want = this.distance * (1 + Math.max(0, -this.pitch - 0.3) * 0.25);
    const hit = col.raycast(tgt, dir, want + 0.2, this.filter);
    let allowed = want;
    if (hit !== Infinity) allowed = Math.max(0.22, hit - 0.16);
    this.curDist = allowed < this.curDist ? damp(this.curDist, allowed, 30, dt) : damp(this.curDist, allowed, 3.5, dt);
    const pos = tgt.clone().addScaledVector(dir, this.curDist);

    // shake (noise based)
    this.shakeT += dt;
    this.shakeAmt = damp(this.shakeAmt, 0, 3, dt);
    if (this.shakeAmt > 0.001) {
      const a = this.shakeAmt;
      pos.x += (noise1(this.shakeT * 18) - 0.5) * 0.08 * a;
      pos.y += (noise1(this.shakeT * 21 + 7) - 0.5) * 0.08 * a;
      pos.z += (noise1(this.shakeT * 19 + 3) - 0.5) * 0.08 * a;
    }

    const look = tgt.clone();
    if (this.override) {
      const o = this.override;
      pos.lerp(o.pos, o.blend);
      look.lerp(o.look, o.blend);
    }
    this.camera.position.copy(pos);
    this.camera.lookAt(look);
    if (this.shakeAmt > 0.001) this.camera.rotation.z += (noise1(this.shakeT * 13 + 11) - 0.5) * 0.03 * this.shakeAmt;
    this.fovKick = damp(this.fovKick, running ? 6 : 0, 3, dt);
    const fov = s.fov + this.fovKick;
    if (Math.abs(this.camera.fov - fov) > 0.01) {
      this.camera.fov = fov;
      this.camera.updateProjectionMatrix();
    }
  }

  /** Horizontal forward of the camera (for movement). */
  get moveYaw() {
    return this.yaw;
  }
}
