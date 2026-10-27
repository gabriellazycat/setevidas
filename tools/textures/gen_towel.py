"""A cream terry-cloth towel texture for Clara's bath outfit (the strapless towel "dress" made in
VRoid Studio, and the turban): rows of tiny cotton loops, a woven border band near one edge, soft
and warm (no pure white, see docs/ESTILO_VISUAL.md). Tileable horizontally.

usage: python tools/textures/gen_towel.py  ->  tools/vroid/towel_cream.png (imported in VRoid)
                                             and godot/assets/textures/gen/towel_cream.png
"""
import math
import os
import random

from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUTS = [os.path.join(ROOT, "tools", "vroid", "towel_cream.png"), os.path.join(ROOT, "godot", "assets", "textures", "gen", "towel_cream.png")]
N = 1024
BASE = (236, 224, 204)       # warm cream
SHADE = (205, 188, 164)
BAND = (214, 190, 170)       # a dusty rose-beige woven band


def main():
    rnd = random.Random(11)
    im = Image.new("RGB", (N, N), BASE)
    px = im.load()
    # loops: little bright blobs on a darker weave, in slightly irregular rows
    for y in range(N):
        for x in range(N):
            row = math.sin(y * 2 * math.pi / 6.0) * 0.5 + 0.5
            col = math.sin(x * 2 * math.pi / 6.0 + (y // 6) * 1.7) * 0.5 + 0.5
            k = 0.55 + 0.45 * row * col
            px[x, y] = tuple(int(SHADE[i] + (BASE[i] - SHADE[i]) * k) for i in range(3))
    for _ in range(N * N // 9):
        x = rnd.randrange(N)
        y = rnd.randrange(N)
        r, g, b = px[x, y]
        d = rnd.randint(-14, 10)
        px[x, y] = (max(0, min(255, r + d)), max(0, min(255, g + d)), max(0, min(255, b + d)))
    im = im.filter(ImageFilter.GaussianBlur(0.7))
    px = im.load()
    # the woven band across, 6% of the height, a little above the bottom (the hem)
    y0, y1 = int(N * 0.86), int(N * 0.92)
    for y in range(y0, y1):
        for x in range(N):
            stripe = 0.85 + 0.15 * math.sin(x * 2 * math.pi / 4.0)
            r, g, b = BAND
            px[x, y] = (int(r * stripe), int(g * stripe), int(b * stripe))
    for out in OUTS:
        os.makedirs(os.path.dirname(out), exist_ok=True)
        im.save(out)
        print("wrote", out)


if __name__ == "__main__":
    main()
