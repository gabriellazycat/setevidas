"""Mingau's toon coat: flattens the photographic albedo of the v2 cat (cat_mingau_albedo.png) into
three flat tones (ginger, darker ginger stripes, warm white) for the anime toon shader, keeping the
pink of the nose and inner ears (slightly desaturated so the toon ramp doesn't turn it red).

usage: python tools/textures/gen_cat_toon.py [--stripe 0.8] [--name mingau]   -> godot/assets/models/cat/cat_<name>_toon.png
--stripe is the stripe tone (1 = no stripes); --name writes a style-study variant (mingau_a/b/c).
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CAT = os.path.join(ROOT, "godot", "assets", "models", "cat")
COAT = np.array([0.80, 0.45, 0.20])
ARGV = sys.argv[1:]
STRIPE = float(ARGV[ARGV.index("--stripe") + 1]) if "--stripe" in ARGV else 0.8   # stripe tone = coat * STRIPE
NAME = ARGV[ARGV.index("--name") + 1] if "--name" in ARGV else "mingau"
WHITE = np.array([0.95, 0.92, 0.87])
PINK = np.array([0.88, 0.6, 0.6])


def ss(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def blur(a, r):
    img = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    return np.asarray(img.filter(ImageFilter.GaussianBlur(r))).astype(float) / 255


def main():
    im = np.asarray(Image.open(os.path.join(CAT, "cat_mingau_albedo.png")).convert("RGB")).astype(float) / 255
    mx, mn = im.max(2), im.min(2)
    s = (mx - mn) / (mx + 1e-5)
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    pink = ((g - b) < 0.12 * mx) & (r > g)
    w = ss(0.22, 0.45, s) * (1 - pink)                    # 1 = ginger coat, 0 = white
    d = np.clip(mx / ((mx * w).sum() / w.sum()), 0.4, 1.4)
    db = blur(d / 1.4, 10) * 1.4                          # stripes only, no strands
    stripe = blur((db < 0.8).astype(float), 1.5)
    tone = COAT * (1 - (1 - STRIPE) * stripe)[..., None]
    wh = blur((blur(w, 6) > 0.5).astype(float), 1.5)[..., None]
    pk = np.where(pink[..., None], im * 0.4 + PINK * 0.6, WHITE)
    out = pk * (1 - wh) + tone * wh
    Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).save(os.path.join(CAT, f"cat_{NAME}_toon.png"))
    print(f"wrote cat_{NAME}_toon.png")


main()
