"""Frames of "Amor de Porteira", the made-up telenovela on Clara's old TV (day 2), plus the face
that flashes on it when the signal goes wrong. One 3x2 atlas of 256x192 frames:
  0 title card at sunset      1 the cowboy at the gate      2 the heroine, close
  3 the two of them by the gate  4 the farmhouse at night    5 the face (glitch)

usage: python tools/textures/gen_tv_show.py  ->  godot/assets/textures/gen/tv_show.png
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "godot", "assets", "textures", "gen", "tv_show.png")
W, H = 256, 192


def sky(d, top, bottom, horizon=0.62):
    for y in range(H):
        k = min(1.0, y / (H * horizon))
        c = tuple(int(top[i] + (bottom[i] - top[i]) * k) for i in range(3))
        d.line([(0, y), (W, y)], fill=c)


def hills(d, y0, col):
    pts = [(0, H)]
    for x in range(0, W + 8, 8):
        pts.append((x, y0 + 8 * math.sin(x * 0.03) + 5 * math.sin(x * 0.11)))
    pts.append((W, H))
    d.polygon(pts, fill=col)


def gate(d, x, y, col, s=1.0):
    for k in range(5):
        d.line([(x, y - k * 9 * s), (x + 70 * s, y - k * 9 * s - 6 * s)], fill=col, width=int(3 * s))
    d.line([(x, y + 2), (x, y - 44 * s)], fill=col, width=int(5 * s))
    d.line([(x + 70 * s, y - 4), (x + 70 * s, y - 50 * s)], fill=col, width=int(5 * s))
    d.line([(x, y), (x + 70 * s, y - 40 * s)], fill=col, width=int(3 * s))


def person(d, x, y, col, hat=False, s=1.0, hair=False):
    d.ellipse([x - 7 * s, y - 62 * s, x + 7 * s, y - 47 * s], fill=col)
    d.polygon([(x - 11 * s, y - 46 * s), (x + 11 * s, y - 46 * s), (x + 8 * s, y - 14 * s), (x - 8 * s, y - 14 * s)], fill=col)
    d.polygon([(x - 7 * s, y - 14 * s), (x - 1 * s, y - 14 * s), (x - 3 * s, y), (x - 8 * s, y)], fill=col)
    d.polygon([(x + 1 * s, y - 14 * s), (x + 7 * s, y - 14 * s), (x + 8 * s, y), (x + 3 * s, y)], fill=col)
    if hat:
        d.ellipse([x - 14 * s, y - 63 * s, x + 14 * s, y - 57 * s], fill=col)
        d.rectangle([x - 7 * s, y - 70 * s, x + 7 * s, y - 59 * s], fill=col)
    if hair:
        d.polygon([(x - 8 * s, y - 60 * s), (x + 8 * s, y - 60 * s), (x + 10 * s, y - 38 * s), (x - 10 * s, y - 38 * s)], fill=col)


def frame(i):
    im = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(im)
    sun_sky = ((70, 40, 90), (250, 150, 80))
    if i == 0:
        sky(d, *sun_sky)
        d.ellipse([150, 80, 200, 130], fill=(255, 210, 120))
        hills(d, 128, (60, 40, 40))
        gate(d, 30, 160, (35, 20, 20))
        try:
            f = ImageFont.truetype("georgiab.ttf", 26)
            f2 = ImageFont.truetype("georgia.ttf", 12)
        except OSError:
            f = f2 = ImageFont.load_default()
        d.text((W / 2, 40), "Amor de Porteira", fill=(255, 235, 200), font=f, anchor="mm", stroke_width=2, stroke_fill=(90, 30, 40))
        d.text((W / 2, 64), "capítulo 112", fill=(255, 225, 190), font=f2, anchor="mm")
    elif i == 1:
        sky(d, *sun_sky)
        hills(d, 130, (70, 50, 45))
        gate(d, 120, 170, (45, 28, 25), 1.2)
        person(d, 80, 178, (30, 20, 22), hat=True, s=1.5)
    elif i == 2:
        sky(d, (120, 70, 90), (240, 170, 120), 1.0)
        # a close-up: shoulders and a head with long hair, warm light on one side
        d.ellipse([88, 30, 168, 130], fill=(80, 45, 40))
        d.ellipse([98, 42, 158, 122], fill=(225, 175, 140))
        d.polygon([(70, 192), (186, 192), (170, 140), (86, 140)], fill=(150, 60, 70))
        d.ellipse([112, 72, 122, 78], fill=(60, 35, 30))
        d.ellipse([134, 72, 144, 78], fill=(60, 35, 30))
        d.arc([118, 92, 140, 104], 20, 160, fill=(150, 70, 70), width=2)
        d.polygon([(88, 60), (98, 42), (100, 140), (84, 150)], fill=(80, 45, 40))
        d.polygon([(168, 60), (158, 42), (156, 140), (172, 150)], fill=(80, 45, 40))
    elif i == 3:
        sky(d, *sun_sky)
        d.ellipse([110, 100, 146, 136], fill=(255, 200, 120))
        hills(d, 132, (55, 38, 38))
        gate(d, 150, 172, (35, 22, 22))
        person(d, 105, 176, (28, 18, 20), hat=True, s=1.25)
        person(d, 128, 176, (28, 18, 20), s=1.15, hair=True)
    elif i == 4:
        sky(d, (10, 12, 30), (40, 45, 80))
        for k in range(30):
            x = (k * 73) % W
            y = (k * 37) % 90
            d.point((x, y), fill=(200, 200, 230))
        hills(d, 140, (15, 18, 25))
        d.polygon([(80, 150), (176, 150), (176, 110), (128, 82), (80, 110)], fill=(30, 28, 35))
        d.rectangle([100, 120, 116, 136], fill=(240, 190, 90))
        d.rectangle([140, 120, 156, 136], fill=(240, 190, 90))
    else:
        # the face: pale, too long, black eyes and mouth, smeared like a bad signal
        im = Image.new("RGB", (W, H), (8, 8, 10))
        d = ImageDraw.Draw(im)
        d.ellipse([86, 14, 170, 182], fill=(205, 205, 200))
        d.ellipse([104, 66, 124, 92], fill=(5, 5, 5))
        d.ellipse([132, 66, 152, 92], fill=(5, 5, 5))
        d.ellipse([114, 128, 142, 168], fill=(5, 5, 5))
        im = im.filter(ImageFilter.GaussianBlur(1.6))
        px = im.load()
        for y in range(0, H, 3):
            off = int(6 * math.sin(y * 0.21))
            row = [px[(x - off) % W, y] for x in range(W)]
            for x in range(W):
                px[x, y] = row[x]
        return im
    return im.filter(ImageFilter.GaussianBlur(0.6))


def main():
    atlas = Image.new("RGB", (W * 3, H * 2))
    for i in range(6):
        atlas.paste(frame(i), ((i % 3) * W, (i // 3) * H))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    atlas.save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
