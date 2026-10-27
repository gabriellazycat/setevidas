"""Procedural textures that Poly Haven does not have: period wallpapers, persian rugs, chalk circle,
claw / hand marks, footprints, the old photograph frame, dust and smoke sprites.

Everything is written into godot/assets/textures/gen/. Run with the normal Python (numpy + Pillow).
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "godot", "assets", "textures", "gen")
os.makedirs(OUT, exist_ok=True)


def save(img, name, q=92):
    p = os.path.join(OUT, name)
    if name.endswith(".png"):
        img.save(p)
    else:
        img.convert("RGB").save(p, quality=q)
    print("wrote", p)


# ------------------------------------------------------------------ noise helpers


def fbm(size, octaves=5, seed=0, base=4):
    """tileable fractal value noise in [0,1], shape (size,size)."""
    rs = np.random.RandomState(seed)
    out = np.zeros((size, size), np.float32)
    amp = 1.0
    tot = 0.0
    for o in range(octaves):
        n = base * (2 ** o)
        grid = rs.rand(n, n).astype(np.float32)
        # bicubic-ish upsample with wrap: use PIL on a 3x3 tiled grid then crop centre
        tile = np.tile(grid, (3, 3))
        im = Image.fromarray((tile * 255).astype(np.uint8)).resize((size * 3, size * 3), Image.BICUBIC)
        a = np.asarray(im, np.float32)[size:2 * size, size:2 * size] / 255.0
        out += a * amp
        tot += amp
        amp *= 0.5
    return out / tot


def lerp(a, b, t):
    return a + (b - a) * t


def colorize(mask, c0, c1):
    m = mask[..., None]
    return np.asarray(c0, np.float32) * (1 - m) + np.asarray(c1, np.float32) * m


def to_img(arr):
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


# ------------------------------------------------------------------ wallpaper motifs


def draw_tiled(draw_fn, size, offsets=((0, 0),)):
    """draw a motif with wrap-around so the tile repeats seamlessly."""
    im = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(im)
    for ox, oy in offsets:
        for dx in (-size, 0, size):
            for dy in (-size, 0, size):
                draw_fn(d, ox + dx, oy + dy)
    return im


def damask_motif(d, cx, cy, s, rnd_seed=3):
    """mirror-symmetric ornamental motif centred at cx, cy with scale s (half height)."""
    rnd = random.Random(rnd_seed)
    shapes = []
    # central spine
    for i in range(28):
        t = i / 27
        y = cy - s + t * 2 * s
        w = s * (0.1 + 0.42 * math.sin(math.pi * t) ** 1.4) * (0.7 + 0.3 * math.cos(t * 11))
        shapes.append(("e", cx, y, w * 0.6, s * 0.06))
    # leaves / curls mirrored
    for k in range(11):
        t = rnd.uniform(0.08, 0.92)
        y = cy - s + t * 2 * s
        ang = rnd.uniform(0.4, 1.4)
        ln = s * rnd.uniform(0.35, 0.75)
        wid = s * rnd.uniform(0.04, 0.09)
        for sgn in (-1, 1):
            pts = []
            for j in range(18):
                u = j / 17
                r = ln * u
                a = ang + u * 1.6
                px = cx + sgn * math.sin(a) * r
                py = y - math.cos(a) * r * 0.9
                pts.append((px, py, wid * (1 - u) + 1))
            for px, py, ww in pts:
                shapes.append(("e", px, py, ww, ww))
    # top flower
    for j in range(8):
        a = j / 8 * 2 * math.pi
        shapes.append(("e", cx + math.cos(a) * s * 0.16, cy - s * 0.78 + math.sin(a) * s * 0.12, s * 0.09, s * 0.07))
    for kind, x, y, rx, ry in shapes:
        d.ellipse((x - rx, y - ry, x + rx, y + ry), fill=255)


def wallpaper_damask(size=1024, bg=(46, 64, 52), fg=(98, 116, 86), seed=1):
    s = size / 2
    mask = draw_tiled(lambda d, ox, oy: damask_motif(d, ox + s * 0.5, oy + s * 0.5, s * 0.46, seed), size, ((0, 0), (s, s), (s, 0), (0, s)))
    mask = mask.filter(ImageFilter.GaussianBlur(1.2))
    m = np.asarray(mask, np.float32) / 255.0
    paper = fbm(size, 6, seed + 10, 8)
    stain = fbm(size, 4, seed + 20, 2)
    col = colorize(m, bg, fg)
    # print wear: the motif is lighter where the paper is rubbed
    col *= (0.86 + 0.22 * paper)[..., None]
    col = lerp(col, col * np.array([1.05, 0.98, 0.82]), (stain > 0.62)[..., None] * 0.5)
    return to_img(col)


def wallpaper_ogee(size=1024, bg=(44, 62, 50), fg=(132, 128, 84), seed=6):
    """Victorian ogee lattice: two families of sinusoids forming onion cells, a flower in each."""
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    P = size / 4
    Q = size / 2
    sx = xs / P
    sy = ys / Q
    wave = 0.27 * np.sin(2 * np.pi * sy)
    d1 = np.abs(((sx - wave) % 1.0) - 0.5)
    d2 = np.abs(((sx + wave) % 1.0) - 0.5)
    dm = np.maximum(d1, d2)
    line = np.clip((dm - 0.478) / 0.01, 0, 1)
    outline = np.clip(1 - np.abs(dm - 0.452) / 0.005, 0, 1)
    # flower in each cell centre
    cu = (sx % 1.0) - 0.5
    cv = (sy % 1.0) - 0.25
    cv2 = (sy % 1.0) - 0.75
    flower = np.zeros_like(xs)
    for cvv, shift in ((cv, 0.0), (cv2, 0.5)):
        u = ((sx + shift) % 1.0) - 0.5
        r = np.hypot(u * P, cvv * Q) / (P * 0.16)
        ang = np.arctan2(cvv * Q, u * P)
        petal = 0.75 + 0.35 * np.cos(ang * 4)
        flower = np.maximum(flower, np.clip((petal - r) * 4, 0, 1))
        flower = np.maximum(flower, np.clip((0.25 - r) * 8, 0, 1) * 0.6)
    m = np.clip(line + outline * 0.7 + flower, 0, 1)
    m = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.9)), np.float32) / 255
    paper = fbm(size, 6, seed, 8)
    col = colorize(m * 0.85, bg, fg)
    col *= (0.84 + 0.24 * paper)[..., None]
    return to_img(col)


def wallpaper_floral(size=1024, bg=(178, 132, 128), fg=(214, 178, 168), leaf=(118, 120, 96), seed=2):
    rnd = random.Random(seed)
    pos = [(rnd.uniform(0, size), rnd.uniform(0, size), rnd.uniform(0, 6.28)) for _ in range(26)]
    def flowers(d, ox, oy):
        for x, y, a in pos:
            x += ox
            y += oy
            r = size * 0.028
            for k in range(5):
                aa = a + k * 2 * math.pi / 5
                d.ellipse((x + math.cos(aa) * r - r * 0.7, y + math.sin(aa) * r - r * 0.7, x + math.cos(aa) * r + r * 0.7, y + math.sin(aa) * r + r * 0.7), fill=255)
    def leaves(d, ox, oy):
        for x, y, a in pos:
            x += ox
            y += oy
            for k in (-1, 1):
                aa = a + k * 1.1
                L = size * 0.06
                for j in range(10):
                    u = j / 9
                    rr = size * 0.012 * (1 - abs(u - 0.5) * 1.6)
                    px = x + math.cos(aa) * L * (0.4 + u)
                    py = y + math.sin(aa) * L * (0.4 + u)
                    d.ellipse((px - rr, py - rr, px + rr, py + rr), fill=255)
    mf = np.asarray(draw_tiled(flowers, size).filter(ImageFilter.GaussianBlur(1.0)), np.float32) / 255
    ml = np.asarray(draw_tiled(leaves, size).filter(ImageFilter.GaussianBlur(1.0)), np.float32) / 255
    paper = fbm(size, 6, seed + 3, 8)
    col = np.full((size, size, 3), bg, np.float32)
    col = lerp(col, np.asarray(leaf, np.float32), ml[..., None] * 0.8)
    col = lerp(col, np.asarray(fg, np.float32), mf[..., None])
    # fine vertical stripes behind
    xs = np.arange(size)[None, :]
    stripe = (np.sin(xs / size * 2 * math.pi * 32) > 0.92).astype(np.float32) * 0.06
    col *= (0.88 + 0.2 * paper - stripe)[..., None]
    return to_img(col)


def wallpaper_stripes(size=1024, c0=(112, 42, 46), c1=(196, 170, 132), seed=3):
    xs = np.arange(size, dtype=np.float32)[None, :].repeat(size, 0)
    period = size / 8
    f = (xs % period) / period
    m = ((f > 0.08) & (f < 0.42)).astype(np.float32)
    thin = (np.abs(f - 0.62) < 0.012).astype(np.float32)
    m = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8)), np.float32) / 255
    paper = fbm(size, 6, seed, 8)
    col = colorize(m, c1, c0)
    col = lerp(col, np.asarray(c0, np.float32) * 0.8, thin[..., None])
    col *= (0.84 + 0.24 * paper)[..., None]
    return to_img(col)


def wallpaper_navy(size=1024, bg=(34, 44, 66), fg=(150, 128, 84), seed=4):
    s = size / 4
    def fleur(d, ox, oy):
        for i in range(4):
            for j in range(4):
                cx = ox + i * s + (s / 2 if j % 2 else 0)
                cy = oy + j * s
                r = s * 0.1
                d.ellipse((cx - r * 0.4, cy - r * 1.4, cx + r * 0.4, cy + r * 0.6), fill=255)
                d.ellipse((cx - r * 1.3, cy - r * 0.5, cx - r * 0.3, cy + r * 0.3), fill=255)
                d.ellipse((cx + r * 0.3, cy - r * 0.5, cx + r * 1.3, cy + r * 0.3), fill=255)
                d.rectangle((cx - r * 0.9, cy + r * 0.5, cx + r * 0.9, cy + r * 0.75), fill=255)
    m = np.asarray(draw_tiled(fleur, size).filter(ImageFilter.GaussianBlur(0.9)), np.float32) / 255
    xs = np.arange(size, dtype=np.float32)[None, :].repeat(size, 0)
    pin = (np.abs((xs % (s / 2)) - s / 4) < 1.0).astype(np.float32) * 0.5
    paper = fbm(size, 6, seed, 8)
    col = colorize(np.maximum(m, pin), bg, fg)
    col *= (0.85 + 0.25 * paper)[..., None]
    return to_img(col)


def wallpaper_trellis(size=1024, bg=(196, 176, 128), fg=(150, 128, 86), seed=5):
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    n = 6
    u = (xs + ys) / size * n
    v = (xs - ys) / size * n
    du = np.abs(u - np.round(u))
    dv = np.abs(v - np.round(v))
    m = np.clip(1 - np.minimum(du, dv) / 0.035, 0, 1)
    dots = np.clip(1 - np.hypot(du - 0.5, dv - 0.5) / 0.06, 0, 1)
    paper = fbm(size, 6, seed, 8)
    col = colorize(np.maximum(m, dots), bg, fg)
    col *= (0.86 + 0.22 * paper)[..., None]
    return to_img(col)


# ------------------------------------------------------------------ rugs


def rug_persian(w=1024, h=1536, field=(118, 28, 30), border=(32, 36, 58), accent=(196, 152, 86), seed=7, medallions=1):
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    u = xs / w
    v = ys / h
    col = np.zeros((h, w, 3), np.float32)
    col[:] = field
    edge = np.minimum(np.minimum(u, 1 - u) * w / h, np.minimum(v, 1 - v))
    bmask = (edge < 0.11).astype(np.float32)
    inner = ((edge > 0.075) & (edge < 0.083)) | ((edge > 0.02) & (edge < 0.027))
    col = lerp(col, np.asarray(border, np.float32), bmask[..., None])
    col = lerp(col, np.asarray(accent, np.float32), inner[..., None].astype(np.float32))
    # border ornament (zig zag)
    t = np.where(np.minimum(u, 1 - u) * w / h < np.minimum(v, 1 - v), v, u)
    zig = np.abs(((t * 40) % 1) - 0.5) * 2
    bo = ((edge > 0.035) & (edge < 0.07) & (np.abs(zig - (edge - 0.035) / 0.035) < 0.25)).astype(np.float32)
    col = lerp(col, np.asarray(accent, np.float32) * 0.9, bo[..., None])
    # central medallion
    cx = 0.5
    cell = 1.0 / medallions
    cy = (np.floor(v / cell) + 0.5) * cell
    du = (u - cx) * w / h * medallions
    dv = (v - cy) * medallions
    r = np.hypot(du * 1.25, dv)
    ang = np.arctan2(dv, du)
    petal = 0.17 + 0.05 * np.cos(ang * 8)
    med = (r < petal).astype(np.float32)
    med2 = (r < petal * 0.55).astype(np.float32)
    col = lerp(col, np.asarray(border, np.float32) * 1.1, med[..., None] * (1 - bmask[..., None]))
    col = lerp(col, np.asarray(accent, np.float32), med2[..., None])
    ring = (np.abs(r - petal * 0.8) < 0.006).astype(np.float32)
    col = lerp(col, np.asarray(accent, np.float32), ring[..., None])
    # field pattern
    fu = (u * 12) % 1
    fv = (v * 18) % 1
    diamond = (np.abs(fu - 0.5) + np.abs(fv - 0.5) < 0.18).astype(np.float32) * (1 - bmask) * (1 - med)
    col = lerp(col, col * 0.62 + np.asarray(accent, np.float32) * 0.18, diamond[..., None])
    # wear: worn pile shows the warp threads (lighter, desaturated) and dirt
    wear = fbm(1024, 5, seed, 3)
    wear = np.asarray(Image.fromarray((wear * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC), np.float32) / 255
    fiber = np.random.RandomState(seed).rand(h, w).astype(np.float32)
    grey = col.mean(axis=2, keepdims=True)
    worn = np.clip((wear - 0.62) * 3, 0, 1)[..., None]
    col = lerp(col, grey * 1.15 + 20, worn * 0.6)
    col *= (0.82 + 0.3 * fiber[..., None] * 0.6)
    col *= (0.85 + 0.25 * wear[..., None])
    return to_img(col)


def rug_runner(w=512, h=2048, seed=8):
    return rug_persian(w, h, field=(40, 52, 78), border=(110, 34, 32), accent=(200, 168, 110), seed=seed, medallions=3)


# ------------------------------------------------------------------ decals


def chalk_circle(size=2048):
    im = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(im)
    c = size / 2
    rnd = random.Random(11)
    def wobbly_circle(r, width, n=720):
        pts = []
        for i in range(n + 1):
            a = i / n * 2 * math.pi
            rr = r * (1 + 0.006 * math.sin(a * 7 + 1) + 0.004 * math.sin(a * 13))
            pts.append((c + math.cos(a) * rr, c + math.sin(a) * rr))
        for i in range(len(pts) - 1):
            d.line((pts[i], pts[i + 1]), fill=rnd.randint(150, 255), width=int(width * rnd.uniform(0.7, 1.2)))
    wobbly_circle(size * 0.46, 14)
    wobbly_circle(size * 0.42, 8)
    wobbly_circle(size * 0.18, 9)
    # seven-pointed star (sete vidas)
    pts = [(c + math.cos(-math.pi / 2 + k * 2 * math.pi * 3 / 7) * size * 0.42, c + math.sin(-math.pi / 2 + k * 2 * math.pi * 3 / 7) * size * 0.42) for k in range(8)]
    for i in range(7):
        d.line((pts[i], pts[i + 1]), fill=230, width=10)
    # glyphs between the circles
    for k in range(21):
        a = k / 21 * 2 * math.pi
        x = c + math.cos(a) * size * 0.44
        y = c + math.sin(a) * size * 0.44
        g = rnd.randint(0, 3)
        s = 18
        if g == 0:
            d.line((x - s, y - s, x + s, y + s), fill=220, width=6)
            d.line((x + s, y - s, x - s, y + s), fill=220, width=6)
        elif g == 1:
            d.ellipse((x - s, y - s, x + s, y + s), outline=220, width=6)
        elif g == 2:
            d.line((x, y - s * 1.3, x, y + s * 1.3), fill=220, width=6)
            d.line((x - s, y, x + s, y), fill=220, width=6)
        else:
            d.polygon(((x, y - s), (x + s, y + s), (x - s, y + s)), outline=220, width=6)
    # paw print at the centre: the cat's own mark
    for (ox, oy, r) in ((0, 30, 70), (-80, -55, 30), (-28, -95, 30), (28, -95, 30), (80, -55, 30)):
        d.ellipse((c + ox - r, c + oy - r, c + ox + r, c + oy + r), fill=235)
    a = np.asarray(im.filter(ImageFilter.GaussianBlur(2.2)), np.float32) / 255
    grain = np.random.RandomState(4).rand(size, size).astype(np.float32)
    a = np.clip(a * (0.55 + 0.6 * grain), 0, 1)
    rgba = np.zeros((size, size, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(rgba)


def claw_marks(size=512):
    im = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(im)
    rnd = random.Random(3)
    for k in range(4):
        x0 = size * (0.25 + k * 0.15) + rnd.uniform(-8, 8)
        pts = []
        for i in range(30):
            t = i / 29
            pts.append((x0 + t * size * 0.12 + math.sin(t * 3) * 6, size * 0.15 + t * size * 0.7))
        for i in range(29):
            w = int(3 + 9 * math.sin(math.pi * i / 29))
            d.line((pts[i], pts[i + 1]), fill=255, width=w)
    a = np.asarray(im.filter(ImageFilter.GaussianBlur(1.4)), np.float32) / 255
    rgba = np.zeros((size, size, 4), np.uint8)
    rgba[..., 0] = 255
    rgba[..., 1] = 255
    rgba[..., 2] = 255
    rgba[..., 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(rgba)


def hand_print(size=512, small=False):
    im = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(im)
    c = size / 2
    s = size * (0.16 if small else 0.2)
    d.ellipse((c - s, c - s * 0.4, c + s, c + s * 1.3), fill=255)
    fingers = [(-0.75, -1.2, 0.95), (-0.25, -1.55, 1.1), (0.25, -1.5, 1.05), (0.72, -1.2, 0.9), (1.15, 0.0, 0.7)]
    for fx, fy, ln in fingers:
        x = c + fx * s
        y = c + fy * s
        for i in range(16):
            t = i / 15
            yy = y - t * s * ln * 0.9 + s * 0.6
            xx = x + fx * t * s * 0.15
            r = s * 0.2 * (1 - t * 0.3)
            d.ellipse((xx - r, yy - r, xx + r, yy + r), fill=255)
    a = np.asarray(im.filter(ImageFilter.GaussianBlur(3)), np.float32) / 255
    smear = fbm(size, 4, 9, 4)
    a = np.clip(a * (0.6 + 0.6 * smear), 0, 1)
    rgba = np.zeros((size, size, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(rgba)


def footprint(size=256):
    im = Image.new("L", (size, int(size * 1.6)), 0)
    d = ImageDraw.Draw(im)
    W, H = im.size
    d.ellipse((W * 0.25, H * 0.05, W * 0.75, H * 0.55), fill=255)
    d.ellipse((W * 0.3, H * 0.55, W * 0.7, H * 0.95), fill=255)
    for i, (x, y) in enumerate(((0.28, 0.02), (0.42, -0.02), (0.55, 0.0), (0.66, 0.05), (0.74, 0.12))):
        r = W * (0.07 - i * 0.008)
        d.ellipse((W * x - r, H * y + 12 - r, W * x + r, H * y + 12 + r), fill=255)
    a = np.asarray(im.filter(ImageFilter.GaussianBlur(4)), np.float32) / 255
    rgba = np.zeros((H, W, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = (a * 220).astype(np.uint8)
    return Image.fromarray(rgba)


def soft_dot(size=128, power=2.2):
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    r = np.hypot(xs - size / 2 + 0.5, ys - size / 2 + 0.5) / (size / 2)
    a = np.clip(1 - r, 0, 1) ** power
    rgba = np.zeros((size, size, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(rgba)


def smoke_puff(size=256, seed=21):
    n = fbm(size, 5, seed, 3)
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    r = np.hypot(xs - size / 2, ys - size / 2) / (size / 2)
    a = np.clip((1 - r) * 1.6, 0, 1) ** 1.5 * np.clip(n * 1.8 - 0.35, 0, 1)
    rgba = np.zeros((size, size, 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = (np.clip(a, 0, 1) * 255).astype(np.uint8)
    return Image.fromarray(rgba)


def noise_tex(size=512, seed=31):
    """tileable RGB noise: R = fbm low, G = fbm high, B = white noise (grime / dissolve masks)."""
    r = fbm(size, 5, seed, 2)
    g = fbm(size, 6, seed + 1, 8)
    b = np.random.RandomState(seed + 2).rand(size, size).astype(np.float32)
    return to_img(np.stack([r, g, b], -1) * 255)


def raindrops(size=512, seed=41):
    """normal-ish map of water drops on glass (rg = offset, b = mask)."""
    rnd = random.Random(seed)
    im = Image.new("RGB", (size, size), (128, 128, 0))
    d = ImageDraw.Draw(im)
    for _ in range(260):
        x = rnd.uniform(0, size)
        y = rnd.uniform(0, size)
        r = rnd.uniform(2, 9)
        for k in range(int(r), 0, -1):
            f = k / r
            col = (int(128 + 100 * (1 - f) * 0.5), int(128 + 100 * (1 - f) * 0.5), int(255 * (1 - f * 0.3)))
            d.ellipse((x - k, y - k * 1.15, x + k, y + k * 1.15), fill=col)
    return im


def main():
    save(wallpaper_ogee(), "wallpaper_damask.jpg")
    save(wallpaper_floral(), "wallpaper_floral.jpg")
    save(wallpaper_stripes(), "wallpaper_stripes.jpg")
    save(wallpaper_navy(), "wallpaper_navy.jpg")
    save(wallpaper_trellis(), "wallpaper_trellis.jpg")
    save(rug_persian(), "rug_red.jpg")
    save(rug_persian(field=(52, 66, 92), border=(120, 40, 36), accent=(206, 176, 120), seed=12), "rug_blue.jpg")
    save(rug_runner(), "rug_runner.jpg")
    save(chalk_circle(), "chalk_circle.png")
    save(claw_marks(), "mark_claw.png")
    save(hand_print(), "mark_hand.png")
    save(hand_print(small=True), "mark_hand_small.png")
    save(footprint(), "footprint.png")
    save(soft_dot(), "dot.png")
    save(soft_dot(64, 1.2), "spark.png")
    save(smoke_puff(), "smoke.png")
    save(smoke_puff(256, 22), "smoke2.png")
    save(noise_tex(), "noise.png")
    save(raindrops(), "raindrops.png")


if __name__ == "__main__":
    main()
