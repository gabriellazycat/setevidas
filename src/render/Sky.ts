import * as THREE from 'three';
import { Shared } from './Materials';

export interface SkyLook {
  top: THREE.ColorRepresentation;
  horizon: THREE.ColorRepresentation;
  bottom: THREE.ColorRepresentation;
  stars: number;
  sunDir: THREE.Vector3;
  sunColor: THREE.ColorRepresentation;
  sunSize: number;
  moon: number;
}

export class Sky {
  mesh: THREE.Mesh;
  mat: THREE.ShaderMaterial;
  moon: THREE.Sprite;

  constructor(scene: THREE.Scene, moonTex: THREE.Texture) {
    this.mat = new THREE.ShaderMaterial({
      uniforms: {
        uTop: { value: new THREE.Color('#05070d') },
        uHorizon: { value: new THREE.Color('#1a2433') },
        uBottom: { value: new THREE.Color('#06080b') },
        uStars: { value: 1 },
        uSunDir: { value: new THREE.Vector3(0, 1, 0) },
        uSunColor: { value: new THREE.Color('#ffffff') },
        uSunSize: { value: 0 },
        uTime: Shared.time,
      },
      vertexShader: /* glsl */ `
        varying vec3 vDir;
        void main() {
          vDir = normalize(position);
          vec4 p = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
          gl_Position = p.xyww;
        }
      `,
      fragmentShader: /* glsl */ `
        uniform vec3 uTop, uHorizon, uBottom, uSunColor, uSunDir;
        uniform float uStars, uSunSize, uTime;
        varying vec3 vDir;
        float hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
        void main() {
          vec3 d = normalize(vDir);
          float h = d.y;
          vec3 col = h > 0.0 ? mix(uHorizon, uTop, pow(clamp(h, 0.0, 1.0), 0.55)) : mix(uHorizon, uBottom, clamp(-h * 4.0, 0.0, 1.0));
          // stars
          if (uStars > 0.0 && h > 0.02) {
            vec3 g = d * 260.0;
            vec3 cell = floor(g);
            float s = hash(cell);
            vec3 c = cell + 0.5 + (vec3(hash(cell + 1.7), hash(cell + 3.1), hash(cell + 5.3)) - 0.5) * 0.6;
            float r = length(g - c);
            float tw = 0.55 + 0.45 * sin(uTime * (1.0 + s * 3.0) + s * 40.0);
            float bright = step(0.993, s) * (0.5 + 0.9 * hash(cell + 9.0));
            float star = bright * tw * smoothstep(0.42, 0.0, r) * smoothstep(0.02, 0.25, h);
            col += vec3(0.82, 0.88, 1.0) * star * uStars * 2.2;
          }
          // sun glow
          if (uSunSize > 0.0) {
            float sd = max(dot(d, normalize(uSunDir)), 0.0);
            col += uSunColor * (pow(sd, 900.0) * 6.0 + pow(sd, 12.0) * 0.35 * uSunSize);
          }
          gl_FragColor = vec4(col, 1.0);
          #include <colorspace_fragment>
        }
      `,
      side: THREE.BackSide,
      depthWrite: false,
      fog: false,
    });
    this.mesh = new THREE.Mesh(new THREE.SphereGeometry(400, 32, 16), this.mat);
    this.mesh.renderOrder = -10;
    this.mesh.frustumCulled = false;
    scene.add(this.mesh);

    this.moon = new THREE.Sprite(
      new THREE.SpriteMaterial({ map: moonTex, color: '#ffffff', transparent: true, depthWrite: false, fog: false }),
    );
    this.moon.scale.set(60, 60, 1);
    this.moon.renderOrder = -9;
    scene.add(this.moon);
  }

  setLook(l: SkyLook, moonDir: THREE.Vector3) {
    const u = this.mat.uniforms;
    u.uTop.value.set(l.top);
    u.uHorizon.value.set(l.horizon);
    u.uBottom.value.set(l.bottom);
    u.uStars.value = l.stars;
    u.uSunDir.value.copy(l.sunDir);
    u.uSunColor.value.set(l.sunColor);
    u.uSunSize.value = l.sunSize;
    this.moon.visible = l.moon > 0;
    (this.moon.material as THREE.SpriteMaterial).opacity = l.moon;
    this.moon.position.copy(moonDir).normalize().multiplyScalar(350);
  }

  follow(cam: THREE.Camera) {
    this.mesh.position.copy(cam.position);
    const d = this.moon.position.clone().normalize();
    this.moon.position.copy(cam.position).addScaledVector(d, 350);
  }
}
