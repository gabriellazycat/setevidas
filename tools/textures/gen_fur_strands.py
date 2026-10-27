"""Fur strand tile for the cat's shell fur: thousands of soft round strands (R = height profile,
tapering to the tip; G = per-strand tint; B = soft clump noise). Seamless, 512x512.
usage: python tools/textures/gen_fur_strands.py"""
import os
import numpy as np
from PIL import Image

N = 512
rng = np.random.default_rng(11)
R = np.zeros((N, N), np.float32)
G = np.full((N, N), 0.5, np.float32)
count = 17000
xs = rng.uniform(0, N, count)
ys = rng.uniform(0, N, count)
rad = rng.uniform(1.5, 2.4, count)
hgt = np.clip(rng.normal(0.82, 0.12, count), 0.45, 1.0)
tint = rng.uniform(0.0, 1.0, count)
for x, y, r, h, t in zip(xs, ys, rad, hgt, tint):
    x0, x1 = int(np.floor(x - r - 1)), int(np.ceil(x + r + 1))
    y0, y1 = int(np.floor(y - r - 1)), int(np.ceil(y + r + 1))
    for yy in range(y0, y1 + 1):
        for xx in range(x0, x1 + 1):
            d = np.hypot(xx + 0.5 - x, yy + 0.5 - y) / r
            if d >= 1.0:
                continue
            v = h * (1.0 - d * d) ** 0.6
            px, py = xx % N, yy % N
            if v > R[py, px]:
                R[py, px] = v
                G[py, px] = t
# soft clumps
f = np.fft.fft2(rng.normal(size=(N, N)))
kx = np.fft.fftfreq(N)[None, :]
ky = np.fft.fftfreq(N)[:, None]
B = np.real(np.fft.ifft2(f * np.exp(-(kx ** 2 + ky ** 2) / (2 * 0.012 ** 2))))
B = (B - B.min()) / (B.max() - B.min())
img = np.stack([R, G, B], -1)
out = os.path.join(os.path.dirname(__file__), "..", "..", "godot", "assets", "textures", "gen", "fur_strands.png")
Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(out)
print("saved", out, "coverage", (R > 0.1).mean())
