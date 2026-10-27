import * as THREE from 'three';

/** Procedural canvas textures. Everything is generated at load, no image files. */

type Ctx = CanvasRenderingContext2D;

let seed = 1337;
const rnd = () => {
  seed = (seed * 16807) % 2147483647;
  return (seed - 1) / 2147483646;
};
const rr = (a: number, b: number) => a + rnd() * (b - a);

function canvas(w: number, h = w): [HTMLCanvasElement, Ctx] {
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  return [c, c.getContext('2d')!];
}

function hsl(h: number, s: number, l: number, a = 1) {
  return `hsla(${h},${s}%,${l}%,${a})`;
}

function speckle(ctx: Ctx, w: number, h: number, count: number, alpha: number, dark = true, size = 1.5) {
  for (let i = 0; i < count; i++) {
    ctx.fillStyle = dark ? `rgba(0,0,0,${rr(0, alpha)})` : `rgba(255,255,255,${rr(0, alpha)})`;
    const s = rr(0.5, size);
    ctx.fillRect(rr(0, w), rr(0, h), s, s);
  }
}

function grime(ctx: Ctx, w: number, h: number, blots: number, alpha: number) {
  for (let i = 0; i < blots; i++) {
    const x = rr(0, w);
    const y = rr(0, h);
    const r = rr(w * 0.05, w * 0.25);
    const g = ctx.createRadialGradient(x, y, 0, x, y, r);
    g.addColorStop(0, `rgba(30,20,10,${rr(0, alpha)})`);
    g.addColorStop(1, 'rgba(30,20,10,0)');
    ctx.fillStyle = g;
    ctx.fillRect(x - r, y - r, r * 2, r * 2);
  }
}

function toTex(c: HTMLCanvasElement, srgb = true) {
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 8;
  t.generateMipmaps = true;
  t.minFilter = THREE.LinearMipmapLinearFilter;
  return t;
}

function woodPlanks(base: [number, number, number], plankCount = 6, gaps = true) {
  const [c, ctx] = canvas(512);
  const [h, s, l] = base;
  const pw = 512 / plankCount;
  for (let i = 0; i < plankCount; i++) {
    const offset = rr(0, 512);
    const lightness = l + rr(-6, 6);
    ctx.fillStyle = hsl(h, s, lightness);
    ctx.fillRect(i * pw, 0, pw, 512);
    // stagger plank ends with slightly different boards
    const y0 = offset % 512;
    const len = 512 * rr(0.35, 0.6);
    ctx.fillStyle = hsl(h + rr(-4, 4), s + rr(-6, 6), lightness + rr(-4, 4));
    ctx.fillRect(i * pw, y0, pw, len);
    if (y0 + len > 512) ctx.fillRect(i * pw, 0, pw, y0 + len - 512);
    // grain
    for (let g = 0; g < 26; g++) {
      ctx.strokeStyle = `rgba(40,20,5,${rr(0.04, 0.16)})`;
      ctx.lineWidth = rr(0.5, 2);
      ctx.beginPath();
      const x = i * pw + rr(2, pw - 2);
      ctx.moveTo(x, 0);
      for (let y = 0; y <= 512; y += 32) ctx.lineTo(x + Math.sin(y * 0.02 + g) * rr(1, 4), y);
      ctx.stroke();
    }
    // knots
    if (rnd() < 0.6) {
      const kx = i * pw + rr(8, pw - 8);
      const ky = rr(0, 512);
      ctx.strokeStyle = 'rgba(50,25,8,0.35)';
      for (let k = 1; k < 4; k++) {
        ctx.beginPath();
        ctx.ellipse(kx, ky, k * 2.5, k * 6, 0, 0, Math.PI * 2);
        ctx.stroke();
      }
    }
    if (gaps) {
      ctx.fillStyle = 'rgba(20,10,4,0.75)';
      ctx.fillRect(i * pw, 0, 2, 512);
      const endY = rr(0, 512);
      ctx.fillRect(i * pw, endY, pw, 2);
    }
  }
  grime(ctx, 512, 512, 10, 0.12);
  return toTex(c);
}

function plaster(h: number, s: number, l: number, noise = 0.08) {
  const [c, ctx] = canvas(256);
  ctx.fillStyle = hsl(h, s, l);
  ctx.fillRect(0, 0, 256, 256);
  speckle(ctx, 256, 256, 4000, noise);
  speckle(ctx, 256, 256, 1500, noise * 0.6, false);
  grime(ctx, 256, 256, 6, 0.06);
  return toTex(c);
}

function wallpaperDamask(bg: string, fg: string) {
  const [c, ctx] = canvas(256);
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, 256, 256);
  ctx.fillStyle = fg;
  const motif = (x: number, y: number, sc: number) => {
    ctx.save();
    ctx.translate(x, y);
    ctx.scale(sc, sc);
    ctx.beginPath();
    ctx.moveTo(0, -40);
    ctx.bezierCurveTo(22, -22, 22, 10, 0, 40);
    ctx.bezierCurveTo(-22, 10, -22, -22, 0, -40);
    ctx.fill();
    ctx.beginPath();
    ctx.arc(0, -48, 5, 0, Math.PI * 2);
    ctx.arc(0, 48, 5, 0, Math.PI * 2);
    ctx.fill();
    for (const sx of [-1, 1]) {
      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.quadraticCurveTo(sx * 30, -10, sx * 36, 10);
      ctx.quadraticCurveTo(sx * 24, 4, 0, 6);
      ctx.fill();
    }
    ctx.restore();
  };
  motif(64, 64, 0.8);
  motif(192, 192, 0.8);
  motif(192, -64, 0.8);
  motif(64, 320, 0.8);
  motif(-64, 192, 0.8);
  motif(320, 64, 0.8);
  speckle(ctx, 256, 256, 2500, 0.07);
  grime(ctx, 256, 256, 8, 0.08);
  return toTex(c);
}

function wallpaperStripes(a: string, b: string, n = 8) {
  const [c, ctx] = canvas(256);
  for (let i = 0; i < n; i++) {
    ctx.fillStyle = i % 2 ? a : b;
    ctx.fillRect((i * 256) / n, 0, 256 / n, 256);
  }
  ctx.fillStyle = 'rgba(255,255,255,0.06)';
  for (let i = 0; i < n; i += 2) ctx.fillRect((i * 256) / n + 4, 0, 2, 256);
  speckle(ctx, 256, 256, 2500, 0.07);
  grime(ctx, 256, 256, 8, 0.08);
  return toTex(c);
}

function wallpaperFloral(bg: string, petal: string, leaf: string) {
  const [c, ctx] = canvas(256);
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, 256, 256);
  const flower = (x: number, y: number) => {
    ctx.fillStyle = leaf;
    ctx.beginPath();
    ctx.ellipse(x - 8, y + 8, 6, 3, -0.6, 0, Math.PI * 2);
    ctx.ellipse(x + 8, y + 9, 6, 3, 0.6, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = petal;
    for (let i = 0; i < 5; i++) {
      const a = (i / 5) * Math.PI * 2;
      ctx.beginPath();
      ctx.arc(x + Math.cos(a) * 5, y + Math.sin(a) * 5, 4, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.fillStyle = 'rgba(240,200,120,0.9)';
    ctx.beginPath();
    ctx.arc(x, y, 2.5, 0, Math.PI * 2);
    ctx.fill();
  };
  for (let y = 0; y < 4; y++) for (let x = 0; x < 4; x++) flower(x * 64 + (y % 2) * 32 + 16, y * 64 + 24);
  speckle(ctx, 256, 256, 2500, 0.06);
  grime(ctx, 256, 256, 6, 0.08);
  return toTex(c);
}

function tiles(a: string, b: string | null, grout: string, n = 8, jitter = 4) {
  const [c, ctx] = canvas(256);
  ctx.fillStyle = grout;
  ctx.fillRect(0, 0, 256, 256);
  const s = 256 / n;
  for (let y = 0; y < n; y++)
    for (let x = 0; x < n; x++) {
      ctx.fillStyle = b && (x + y) % 2 ? b : a;
      ctx.fillRect(x * s + 1.5, y * s + 1.5, s - 3, s - 3);
      ctx.fillStyle = `rgba(255,255,255,${rr(0, 0.08)})`;
      ctx.fillRect(x * s + 3, y * s + 3, s - 6, (s - 6) * 0.35);
      ctx.fillStyle = `rgba(0,0,0,${rr(0, jitter / 40)})`;
      ctx.fillRect(x * s + 1.5, y * s + 1.5, s - 3, s - 3);
    }
  grime(ctx, 256, 256, 8, 0.1);
  return toTex(c);
}

function concrete() {
  const [c, ctx] = canvas(512);
  ctx.fillStyle = '#5d5953';
  ctx.fillRect(0, 0, 512, 512);
  speckle(ctx, 512, 512, 14000, 0.18);
  speckle(ctx, 512, 512, 6000, 0.1, false);
  grime(ctx, 512, 512, 30, 0.22);
  ctx.strokeStyle = 'rgba(20,18,15,0.35)';
  for (let i = 0; i < 6; i++) {
    ctx.beginPath();
    let x = rr(0, 512);
    let y = rr(0, 512);
    ctx.moveTo(x, y);
    for (let k = 0; k < 12; k++) {
      x += rr(-20, 20);
      y += rr(-20, 20);
      ctx.lineTo(x, y);
    }
    ctx.lineWidth = rr(0.5, 1.5);
    ctx.stroke();
  }
  return toTex(c);
}

function bricks(base: string) {
  const [c, ctx] = canvas(256);
  ctx.fillStyle = '#3a3530';
  ctx.fillRect(0, 0, 256, 256);
  const bw = 64;
  const bh = 24;
  for (let y = 0; y < 256 / bh + 1; y++)
    for (let x = -1; x < 256 / bw + 1; x++) {
      const ox = (y % 2) * (bw / 2);
      ctx.fillStyle = base;
      ctx.fillRect(x * bw + ox + 2, y * bh + 2, bw - 4, bh - 4);
      ctx.fillStyle = `rgba(0,0,0,${rr(0, 0.3)})`;
      ctx.fillRect(x * bw + ox + 2, y * bh + 2, bw - 4, bh - 4);
    }
  speckle(ctx, 256, 256, 3000, 0.2);
  grime(ctx, 256, 256, 12, 0.25);
  return toTex(c);
}

function siding(color: string) {
  const [c, ctx] = canvas(256);
  ctx.fillStyle = color;
  ctx.fillRect(0, 0, 256, 256);
  for (let y = 0; y < 8; y++) {
    const g = ctx.createLinearGradient(0, y * 32, 0, y * 32 + 32);
    g.addColorStop(0, 'rgba(255,255,255,0.08)');
    g.addColorStop(0.85, 'rgba(0,0,0,0.05)');
    g.addColorStop(1, 'rgba(0,0,0,0.45)');
    ctx.fillStyle = g;
    ctx.fillRect(0, y * 32, 256, 32);
  }
  speckle(ctx, 256, 256, 3000, 0.08);
  grime(ctx, 256, 256, 14, 0.15);
  return toTex(c);
}

function shingles() {
  const [c, ctx] = canvas(256);
  ctx.fillStyle = '#26221f';
  ctx.fillRect(0, 0, 256, 256);
  for (let y = 0; y < 8; y++)
    for (let x = 0; x < 9; x++) {
      const ox = (y % 2) * 16;
      ctx.fillStyle = hsl(15, 8, rr(13, 22));
      ctx.fillRect(x * 32 + ox - 16 + 1, y * 32 + 1, 30, 30);
      ctx.fillStyle = 'rgba(0,0,0,0.5)';
      ctx.fillRect(x * 32 + ox - 16, y * 32 + 28, 32, 4);
    }
  speckle(ctx, 256, 256, 3000, 0.2);
  return toTex(c);
}

function grass() {
  const [c, ctx] = canvas(512);
  ctx.fillStyle = '#2c3a22';
  ctx.fillRect(0, 0, 512, 512);
  for (let i = 0; i < 9000; i++) {
    ctx.strokeStyle = hsl(rr(75, 110), rr(20, 40), rr(14, 32), rr(0.3, 0.8));
    ctx.beginPath();
    const x = rr(0, 512);
    const y = rr(0, 512);
    ctx.moveTo(x, y);
    ctx.lineTo(x + rr(-2, 2), y - rr(3, 8));
    ctx.stroke();
  }
  grime(ctx, 512, 512, 20, 0.25);
  return toTex(c);
}

function asphalt() {
  const [c, ctx] = canvas(256);
  ctx.fillStyle = '#26262a';
  ctx.fillRect(0, 0, 256, 256);
  speckle(ctx, 256, 256, 9000, 0.3);
  speckle(ctx, 256, 256, 3000, 0.12, false);
  return toTex(c);
}

function fabric(color: string, weave = 0.08) {
  const [c, ctx] = canvas(128);
  ctx.fillStyle = color;
  ctx.fillRect(0, 0, 128, 128);
  for (let i = 0; i < 128; i += 2) {
    ctx.fillStyle = `rgba(0,0,0,${weave})`;
    ctx.fillRect(i, 0, 1, 128);
    ctx.fillStyle = `rgba(255,255,255,${weave * 0.5})`;
    ctx.fillRect(0, i, 128, 1);
  }
  speckle(ctx, 128, 128, 800, 0.1);
  return toTex(c);
}

function carpet(color: string, border: string) {
  const [c, ctx] = canvas(256);
  ctx.fillStyle = color;
  ctx.fillRect(0, 0, 256, 256);
  ctx.strokeStyle = border;
  ctx.lineWidth = 10;
  ctx.strokeRect(14, 14, 228, 228);
  ctx.lineWidth = 3;
  ctx.strokeRect(32, 32, 192, 192);
  ctx.save();
  ctx.translate(128, 128);
  ctx.rotate(Math.PI / 4);
  ctx.strokeRect(-50, -50, 100, 100);
  ctx.fillStyle = border;
  ctx.fillRect(-18, -18, 36, 36);
  ctx.restore();
  speckle(ctx, 256, 256, 6000, 0.15);
  speckle(ctx, 256, 256, 2000, 0.06, false);
  return toTex(c);
}

function paintingTex(kind: number) {
  const [c, ctx] = canvas(128, 160);
  if (kind === 0) {
    // landscape
    const g = ctx.createLinearGradient(0, 0, 0, 160);
    g.addColorStop(0, '#6d7c8a');
    g.addColorStop(0.55, '#c9b28a');
    g.addColorStop(0.56, '#4c5a3a');
    g.addColorStop(1, '#2c3424');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, 128, 160);
    ctx.fillStyle = '#1f2619';
    ctx.beginPath();
    ctx.moveTo(0, 95);
    ctx.lineTo(40, 70);
    ctx.lineTo(70, 88);
    ctx.lineTo(128, 60);
    ctx.lineTo(128, 160);
    ctx.lineTo(0, 160);
    ctx.fill();
  } else if (kind === 1) {
    // portrait of an old woman (Dona Ivone)
    ctx.fillStyle = '#2b2420';
    ctx.fillRect(0, 0, 128, 160);
    ctx.fillStyle = '#6d5a4a';
    ctx.beginPath();
    ctx.ellipse(64, 150, 50, 50, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#c9a98a';
    ctx.beginPath();
    ctx.ellipse(64, 70, 24, 30, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#d8d4cc';
    ctx.beginPath();
    ctx.ellipse(64, 46, 28, 18, 0, Math.PI, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#1a1512';
    ctx.fillRect(52, 66, 6, 3);
    ctx.fillRect(70, 66, 6, 3);
  } else {
    // flowers still life
    ctx.fillStyle = '#3a3f2f';
    ctx.fillRect(0, 0, 128, 160);
    for (let i = 0; i < 9; i++) {
      ctx.fillStyle = hsl(rr(0, 50), 50, rr(40, 60));
      ctx.beginPath();
      ctx.arc(rr(34, 94), rr(30, 80), rr(8, 14), 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.fillStyle = '#6b5a45';
    ctx.fillRect(48, 90, 32, 50);
  }
  speckle(ctx, 128, 160, 1500, 0.15);
  return toTex(c);
}

function staticNoise() {
  const [c, ctx] = canvas(128);
  const img = ctx.createImageData(128, 128);
  for (let i = 0; i < img.data.length; i += 4) {
    const v = rnd() * 255;
    img.data[i] = img.data[i + 1] = img.data[i + 2] = v;
    img.data[i + 3] = 255;
  }
  ctx.putImageData(img, 0, 0);
  return toTex(c, false);
}

function radialBlob() {
  const [c, ctx] = canvas(128);
  const g = ctx.createRadialGradient(64, 64, 0, 64, 64, 64);
  g.addColorStop(0, 'rgba(0,0,0,1)');
  g.addColorStop(0.5, 'rgba(0,0,0,0.5)');
  g.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, 128, 128);
  const t = toTex(c, false);
  t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping;
  return t;
}

function softDot() {
  const [c, ctx] = canvas(64);
  const g = ctx.createRadialGradient(32, 32, 0, 32, 32, 32);
  g.addColorStop(0, 'rgba(255,255,255,1)');
  g.addColorStop(0.35, 'rgba(255,255,255,0.45)');
  g.addColorStop(1, 'rgba(255,255,255,0)');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, 64, 64);
  const t = toTex(c, false);
  t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping;
  return t;
}

function clawMarks() {
  const [c, ctx] = canvas(128);
  ctx.clearRect(0, 0, 128, 128);
  ctx.strokeStyle = 'rgba(255,255,255,1)';
  ctx.lineCap = 'round';
  for (let i = 0; i < 4; i++) {
    ctx.lineWidth = 5 - i * 0.6;
    ctx.beginPath();
    ctx.moveTo(30 + i * 18, 14);
    ctx.bezierCurveTo(40 + i * 18, 50, 30 + i * 16, 80, 44 + i * 14, 116);
    ctx.stroke();
  }
  const t = toTex(c, false);
  t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping;
  return t;
}

function handprint() {
  const [c, ctx] = canvas(128);
  ctx.fillStyle = 'rgba(255,255,255,1)';
  ctx.beginPath();
  ctx.ellipse(64, 80, 22, 26, 0, 0, Math.PI * 2);
  ctx.fill();
  const fingers: [number, number, number][] = [
    [36, 46, -0.5],
    [50, 30, -0.15],
    [66, 26, 0],
    [82, 32, 0.15],
    [96, 60, 0.7],
  ];
  for (const [x, y, a] of fingers) {
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(a);
    ctx.beginPath();
    ctx.ellipse(0, 0, 6, 18, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }
  const t = toTex(c, false);
  t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping;
  return t;
}

function chalkCircle() {
  const [c, ctx] = canvas(512);
  ctx.clearRect(0, 0, 512, 512);
  ctx.strokeStyle = 'rgba(240,240,230,0.9)';
  ctx.lineWidth = 6;
  ctx.beginPath();
  ctx.arc(256, 256, 230, 0, Math.PI * 2);
  ctx.stroke();
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.arc(256, 256, 200, 0, Math.PI * 2);
  ctx.stroke();
  // triangle
  ctx.beginPath();
  for (let i = 0; i <= 3; i++) {
    const a = -Math.PI / 2 + (i / 3) * Math.PI * 2;
    const x = 256 + Math.cos(a) * 200;
    const y = 256 + Math.sin(a) * 200;
    if (i === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
  ctx.stroke();
  ctx.font = '28px serif';
  ctx.fillStyle = 'rgba(240,240,230,0.85)';
  const glyphs = ['ᚠ', 'ᚢ', 'ᚦ', 'ᚨ', 'ᚱ', 'ᚲ', 'ᚷ', 'ᚹ', 'ᚺ', 'ᚾ', 'ᛁ', 'ᛃ'];
  glyphs.forEach((g, i) => {
    const a = (i / glyphs.length) * Math.PI * 2;
    ctx.fillText(g, 248 + Math.cos(a) * 215, 266 + Math.sin(a) * 215);
  });
  const t = toTex(c, false);
  t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping;
  return t;
}

function porcelainFace() {
  const [c, ctx] = canvas(128);
  ctx.fillStyle = '#efe8e0';
  ctx.fillRect(0, 0, 128, 128);
  // cheeks
  ctx.fillStyle = 'rgba(220,120,120,0.35)';
  ctx.beginPath();
  ctx.arc(40, 78, 12, 0, Math.PI * 2);
  ctx.arc(88, 78, 12, 0, Math.PI * 2);
  ctx.fill();
  // eyes
  ctx.fillStyle = '#0b0b0d';
  ctx.beginPath();
  ctx.ellipse(44, 58, 9, 11, 0, 0, Math.PI * 2);
  ctx.ellipse(84, 58, 9, 11, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = 'rgba(255,255,255,0.8)';
  ctx.fillRect(46, 52, 3, 3);
  ctx.fillRect(86, 52, 3, 3);
  // mouth
  ctx.fillStyle = '#7a2a2a';
  ctx.beginPath();
  ctx.ellipse(64, 92, 6, 3, 0, 0, Math.PI * 2);
  ctx.fill();
  // crack
  ctx.strokeStyle = 'rgba(40,30,30,0.8)';
  ctx.lineWidth = 1.2;
  ctx.beginPath();
  ctx.moveTo(84, 10);
  ctx.lineTo(80, 30);
  ctx.lineTo(88, 42);
  ctx.lineTo(82, 50);
  ctx.stroke();
  return toTex(c);
}

function photoTex() {
  const [c, ctx] = canvas(128, 96);
  ctx.fillStyle = '#d6cbb3';
  ctx.fillRect(0, 0, 128, 96);
  ctx.fillStyle = '#7a6d58';
  ctx.fillRect(8, 8, 112, 80);
  ctx.fillStyle = '#4a3f33';
  ctx.beginPath();
  ctx.ellipse(52, 50, 14, 18, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillRect(36, 64, 32, 24);
  ctx.fillStyle = '#121010';
  ctx.beginPath();
  ctx.ellipse(76, 74, 14, 9, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.beginPath();
  ctx.arc(86, 64, 6, 0, Math.PI * 2);
  ctx.fill();
  speckle(ctx, 128, 96, 900, 0.25);
  return toTex(c);
}

function moonTex() {
  const [c, ctx] = canvas(256);
  const g = ctx.createRadialGradient(128, 128, 0, 128, 128, 128);
  g.addColorStop(0, 'rgba(255,250,235,1)');
  g.addColorStop(0.22, 'rgba(240,238,225,1)');
  g.addColorStop(0.25, 'rgba(200,215,240,0.35)');
  g.addColorStop(0.6, 'rgba(120,150,200,0.08)');
  g.addColorStop(1, 'rgba(80,100,160,0)');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, 256, 256);
  ctx.fillStyle = 'rgba(160,160,150,0.35)';
  for (let i = 0; i < 9; i++) {
    ctx.beginPath();
    ctx.arc(128 + rr(-22, 22), 128 + rr(-22, 22), rr(3, 9), 0, Math.PI * 2);
    ctx.fill();
  }
  const t = toTex(c);
  t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping;
  return t;
}

function cobwebTex() {
  const [c, ctx] = canvas(256);
  ctx.clearRect(0, 0, 256, 256);
  ctx.strokeStyle = 'rgba(235,235,225,0.7)';
  ctx.lineWidth = 1.2;
  const corner = [0, 256];
  const spokes = 7;
  const pts: number[][] = [];
  for (let i = 0; i <= spokes; i++) {
    const p = i / spokes;
    pts.push([256 * p, 256 * p]);
    ctx.beginPath();
    ctx.moveTo(corner[0], corner[1]);
    ctx.lineTo(256 * p, 256 * p);
    ctx.stroke();
  }
  for (const r of [0.28, 0.46, 0.62, 0.78, 0.92]) {
    ctx.beginPath();
    pts.forEach(([x, y], i) => {
      const px = corner[0] + (x - corner[0]) * r + (rnd() - 0.5) * 3;
      const py = corner[1] + (y - corner[1]) * r + (rnd() - 0.5) * 3;
      if (i === 0) ctx.moveTo(px, py);
      else ctx.quadraticCurveTo((px + corner[0]) / 2 + (rnd() - 0.5) * 6 + 6, (py + corner[1]) / 2 - 6, px, py);
    });
    ctx.stroke();
  }
  const t = toTex(c);
  t.wrapS = t.wrapT = THREE.ClampToEdgeWrapping;
  return t;
}

export interface TextureLib {
  [k: string]: THREE.Texture;
}

let LIB: TextureLib | null = null;

export function textures(): TextureLib {
  if (LIB) return LIB;
  seed = 1337;
  LIB = {
    woodFloor: woodPlanks([28, 38, 34], 6),
    woodFloorDark: woodPlanks([22, 32, 24], 7),
    woodFurniture: woodPlanks([24, 36, 30], 4, false),
    woodDarkFurniture: woodPlanks([18, 30, 18], 4, false),
    woodPaint: plaster(40, 18, 82, 0.05),
    plasterCeiling: plaster(40, 10, 86, 0.04),
    plasterBeige: plaster(38, 22, 70),
    plasterHall: plaster(30, 18, 62),
    papSala: wallpaperDamask('#4f5a45', 'rgba(170,150,95,0.35)'),
    papQuarto: wallpaperStripes('#b88f86', '#c9a39a'),
    papHospedes: wallpaperFloral('#c8c0a2', '#9a6a7a', '#6b7a55'),
    papEscritorio: wallpaperStripes('#3e4a52', '#46535c', 12),
    tileWhite: tiles('#d9dcd8', null, '#9fa49f', 10),
    tileBlue: tiles('#8fb0bf', '#e3e6e0', '#8c9293', 8),
    tileChecker: tiles('#e2ddd0', '#2a2a2c', '#77746c', 6, 2),
    tileKitchenWall: tiles('#d8cfb8', null, '#a59c88', 12),
    concrete: concrete(),
    brick: bricks('#7a4a3a'),
    brickBasement: bricks('#5e4a40'),
    siding: siding('#7d8b93'),
    shingles: shingles(),
    grass: grass(),
    asphalt: asphalt(),
    sofa: fabric('#6e3b36'),
    fabricBlue: fabric('#5d6f86'),
    fabricCream: fabric('#d9cfbd', 0.05),
    fabricGreen: fabric('#55654a'),
    blanket: fabric('#8a6a8e', 0.1),
    sheet: fabric('#cfcac0', 0.04),
    carpetRed: carpet('#6a2a26', '#c9a25e'),
    carpetBlue: carpet('#2f3d55', '#b8a77a'),
    painting0: paintingTex(0),
    painting1: paintingTex(1),
    painting2: paintingTex(2),
    staticNoise: staticNoise(),
    blob: radialBlob(),
    dot: softDot(),
    claw: clawMarks(),
    hand: handprint(),
    chalk: chalkCircle(),
    porcelain: porcelainFace(),
    photo: photoTex(),
    moon: moonTex(),
    cobweb: cobwebTex(),
  };
  return LIB;
}
