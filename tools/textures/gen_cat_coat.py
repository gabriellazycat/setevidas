"""Mingau's toon coat painted by body position: every texel of the atlas is coloured from where it sits
on the cat (tools/blender/bake_cat_pos.py bakes that), so the white muzzle, bib, belly and socks, the
tabby stripes, the nose, the inner ears and the dark rim round the eyes come out as clean shapes
instead of the noise of the old photo-derived coat (gen_cat_toon.py).

usage: python tools/textures/gen_cat_coat.py STYLE [--model cat_mingau_a] [--name mingau_a1]
STYLE: soft | anime | classic (see STYLES) -> godot/assets/models/cat/cat_<name>_toon.png
Blender coords from the bake: the cat faces -Y, Z up, feet at z=0.
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CACHE = os.path.join(ROOT, "tools", "cache", "cat_coat")
CAT = os.path.join(ROOT, "godot", "assets", "models", "cat")
ARGV = sys.argv[1:]
STYLE = ARGV[0]
MODEL = ARGV[ARGV.index("--model") + 1] if "--model" in ARGV else "cat_mingau_a"
NAME = ARGV[ARGV.index("--name") + 1] if "--name" in ARGV else "mingau_a1"

# edge: border softness (m); stripe: stripe tone (coat * stripe, 1 = none); stripe_w: stripe share of
# a period; rim: dark rim round the eyes (m, 0 = none); blaze: height of the white blaze up the nose
STYLES = {
    # the from-scratch studies' coats on the game body: cream with warm points / white with orange
    "creme": {"pattern": "points", "coat": (0.99, 0.93, 0.82), "dark": (0.93, 0.6, 0.32), "stripe": 1.0, "stripe_w": 0.3,
              "edge": 0.003, "rim": 0.0, "blaze": 0.02, "white": (1.0, 0.97, 0.92), "nose": (0.93, 0.55, 0.6),
              "socks": False, "tail_tip": False, "grad": 0.0},
    "bolinha": {"pattern": "bicolor", "coat": (0.95, 0.56, 0.22), "dark": (0.84, 0.44, 0.15), "stripe": 0.86, "stripe_w": 0.32,
                "edge": 0.002, "rim": 0.0, "blaze": 0.03, "white": (0.99, 0.96, 0.9), "nose": (0.93, 0.55, 0.6),
                "socks": False, "tail_tip": False, "grad": 0.0},
    "soft": {"coat": (0.87, 0.53, 0.26), "stripe": 0.9, "stripe_w": 0.32, "edge": 0.0025, "rim": 0.0012,
             "blaze": 0.022, "white": (0.97, 0.94, 0.89), "nose": (0.9, 0.55, 0.55), "socks": True, "tail_tip": False,
             "grad": 0.06},
    "anime": {"coat": (0.86, 0.49, 0.22), "stripe": 0.8, "stripe_w": 0.3, "edge": 0.0012, "rim": 0.0018,
              "blaze": 0.03, "white": (0.98, 0.95, 0.9), "nose": (0.92, 0.52, 0.55), "socks": True, "tail_tip": True,
              "grad": 0.0},
    "classic": {"coat": (0.82, 0.47, 0.21), "stripe": 0.78, "stripe_w": 0.4, "edge": 0.0022, "rim": 0.0009,
                "blaze": 0.026, "white": (0.96, 0.93, 0.87), "nose": (0.88, 0.58, 0.58), "socks": True, "tail_tip": True,
                "grad": 0.03},
}
S = STYLES[STYLE]


def ss(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def inside(d):
    """signed distance (m, negative inside) -> coverage with the style's soft edge"""
    e = S["edge"]
    return ss(e, -e, d)


def main():
    z_ = np.load(os.path.join(CACHE, f"{MODEL}_pos.npz"))
    pos, nrm, mask = z_["pos"], z_["nrm"], z_["mask"]
    marks = json.load(open(os.path.join(CACHE, f"{MODEL}_marks.json")))
    bones = {k: (np.array(v[0]), np.array(v[1])) for k, v in marks["bones"].items()}
    P, N = pos[mask], nrm[mask]
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    nx, ny, nz = N[:, 0], N[:, 1], N[:, 2]
    ax = np.abs(x)
    ph = np.array(marks["lines"].get("cat_mouthline_ph", [[0, -0.27, 0.27]]))
    nose_z = ph[:, 2].max() + 0.004    # nose pad centre, just above the philtrum line
    if "cat_decal_nose" in marks.get("decals", {}):   # the decal-face model (build_cat2.py --face decal)
        nose_z = marks["decals"]["cat_decal_nose"][2]
    mouth_z = ph[:, 2].min()
    eyes = marks["eyes"]
    ez = np.mean([e["center"][2] for e in eyes])
    er = eyes[0]["radius"]
    head_j = bones["head"][0]
    front = y < head_j[1] - 0.035                     # face, ahead of the cheeks
    head = (y < head_j[1] + 0.02) & (z > 0.2)

    # --- white: muzzle, blaze, chin and throat, bib, belly, socks, tail tip
    d_muz = (np.sqrt((x / 0.027) ** 2 + ((z - (nose_z - 0.009)) / 0.021) ** 2) - 1) * 0.019
    d_muz = np.where(front & (ny < 0.3), d_muz, 1.0)
    # blaze: a tapering wedge from the nose up between the eyes
    t = (z - nose_z) / S["blaze"]
    d_blz = np.where(front & (t > -0.2) & (t < 1.0), ax - 0.011 * (1 - np.clip(t, 0, 1)) ** 1.3, 1.0)
    # chin, throat and bib: the underside of the head and the front of the chest
    jaw = bones["jaw"][0]
    d_chin = np.where((y < jaw[1] + 0.05) & (z < jaw[2] + 0.02) & (nz < 0.5), -(jaw[2] + 0.02 - z), 1.0)
    chest = bones["chest"][0]
    bibw = 0.018 + 0.03 * ss(0.24, 0.16, z)           # wider low on the chest
    d_bib = np.where((y < chest[1] - 0.02) & (z < 0.245) & (z > 0.09) & ((ny < -0.15) | (nz < -0.3)), ax - bibw, 1.0)
    d_bel = np.where((nz < -0.25) & (z < 0.155) & (y > chest[1] - 0.06) & (y < bones["hips"][0][1] + 0.02), -(-nz - 0.25) * 0.05, 1.0)
    d = np.minimum.reduce([d_muz, d_blz, d_chin, d_bib, d_bel])
    if S["socks"]:
        fsock = 0.034 + 0.004 * np.sin(x * 300)
        hsock = 0.04 + 0.03 * ss(0.1, 0.15, y)      # higher up the heel
        d = np.minimum(d, np.where(y < 0, z - fsock, z - hsock))
    if S["tail_tip"]:
        tip = bones["tail4"][1]
        d = np.minimum(d, np.linalg.norm(P - tip, axis=1) - 0.022)
    white = inside(d)

    # --- stripes (darker ginger), fading toward the white and the belly
    coat = np.array(S["coat"])
    body = (y > chest[1] - 0.06) & (y < bones["hips"][0][1] + 0.03) & (z > 0.1) & ~head
    ph_b = (y - 0.35 * (0.26 - z)) / 0.034 + 0.12 * np.sin(x * 55)
    band = np.abs(np.mod(ph_b, 1.0) - 0.5) * 2               # 0 at the stripe centre
    sb = inside((band - S["stripe_w"]) * 0.01) * body * ss(0.13, 0.18, z)
    # legs: rings on the outer side above the socks
    legs = (z < 0.13) & (ax > 0.018)
    sl = inside((np.abs(np.mod(z / 0.024, 1.0) - 0.5) * 2 - S["stripe_w"]) * 0.01) * legs * ss(0.0, 0.5, nx * np.sign(x))
    # tail: rings along it
    t0 = bones["tail0"][0]
    tail = (y > t0[1] + 0.012) & (ax < 0.035) & (z > 0.04)
    st = inside((np.abs(np.mod(np.linalg.norm(P - t0, axis=1) / 0.026, 1.0) - 0.5) * 2 - S["stripe_w"]) * 0.01) * tail
    # head: the 'M' lines on the forehead and two lines back from the outer eye corners
    fore = head & (z > ez + er * 0.9) & (y < head_j[1] + 0.01) & (nz > 0.1)
    xm = np.abs(np.mod(x / 0.011 + 0.5, 1.0) - 0.5) * 2
    sf = inside((xm - 0.3) * 0.01) * fore * (ax < 0.03)
    cheek = head & (ax > 0.036) & (y > eyes[0]["center"][1] + 0.005) & (z < ez + 0.002) & (z > ez - 0.02)
    sc = inside((np.abs(np.mod((z - ez) / 0.011, 1.0) - 0.5) * 2 - 0.32) * 0.01) * cheek
    stripe = np.clip(sb + sl + st + sf + sc, 0, 1)
    tone = coat[None, :] * (1 - (1 - S["stripe"]) * stripe[:, None])
    # gentle top-to-belly gradient (the soft style lightens toward the white)
    tone = tone * (1 - S["grad"] * np.clip(nz, 0, 1))[:, None] + S["grad"] * ss(0.6, 0.0, nz)[:, None] * 0.6
    col = tone * (1 - white[:, None]) + np.array(S["white"])[None, :] * white[:, None]
    pat = S.get("pattern", "tabby")
    if pat != "tabby":
        earm = np.zeros(len(P), bool)
        for side in ("L", "R"):
            eh, et = bones[f"ear.{side}"]
            ae = et - eh
            u = np.clip(((P - eh) @ ae) / (ae @ ae), 0, 1.4)
            earm |= (z > eh[2] - 0.006) & (np.linalg.norm(P - (eh + np.outer(u, ae)), axis=1) < 0.032)
        muz = inside(d_muz)
        wcol, dark = np.array(S["white"]), np.array(S["dark"])
    if pat == "points":
        # cream, the points warm: ears, a soft mask round the eyes and nose bridge, paws, the tail
        # darkening toward its tip, a faint saddle
        k = earm * 1.0
        k = np.maximum(k, front * (z > nose_z - 0.004) * ss(0.045, 0.01, ax) * 0.8)
        k = np.maximum(k, ss(0.045, 0.02, z))
        k = np.maximum(k, tail * ss(0.0, 0.08, np.linalg.norm(P - t0, axis=1)))
        k = np.maximum(k, 0.2 * ss(0.4, 0.9, nz) * body)
        col = coat[None, :] * (1 - k[:, None]) + dark[None, :] * k[:, None]
        col = col * (1 - muz[:, None]) + wcol[None, :] * muz[:, None]
    elif pat == "bicolor":
        # white with an orange cap (the blaze and muzzle stay white), a saddle and the tail, striped
        blz = inside(d_blz)
        # the cap's lower edge dips down the cheeks (a mask), the muzzle and a wide blaze stay white
        cap = (head & (z > nose_z + 0.013 - 0.55 * ax)) | earm
        saddle = body & (z > 0.215 + 0.012 * np.sin(y * 45))
        orange = (cap | saddle | tail).astype(float)
        blz = np.maximum(blz, inside(np.where(front & (z > nose_z - 0.004), ax - 0.014 * np.clip(1 - (z - nose_z) / 0.04, 0, 1), 1.0)))
        orange = orange * (1 - np.maximum(blz, muz))
        col = wcol[None, :] * (1 - orange[:, None]) + tone * orange[:, None]

    # --- inner ears: pink skin with a white fringe toward the edges
    for side in ("L", "R"):
        eh, et = bones[f"ear.{side}"]
        ax_e = et - eh
        u = np.clip(((P - eh) @ ax_e) / (ax_e @ ax_e), 0, 1.4)
        near = np.linalg.norm(P - (eh + np.outer(u, ax_e)), axis=1)
        ear = (z > eh[2] - 0.004) & (near < 0.03) & (ny < -0.15)
        k = ear * ss(-0.15, -0.45, ny) * ss(0.0, 0.25, u)
        pink = np.array((0.93, 0.66, 0.64))
        col = col * (1 - k[:, None]) + pink[None, :] * k[:, None]

    # --- nose pad: a rounded inverted triangle
    tz = (nose_z + 0.0022 - z) / 0.0058      # 0 at the top edge, 1 at the tip
    d_nose = np.maximum(ax - 0.0062 * (1 - np.clip(tz, 0, 1)) ** 0.8, np.abs(tz - 0.5) * 0.0058 - 0.0029)
    kn = inside(np.where(front & (ny < -0.2), d_nose, 1.0) * 1.0) * (S["edge"] > 0)
    col = col * (1 - kn[:, None]) + np.array(S["nose"])[None, :] * kn[:, None]

    # --- dark rim round each eye lens (eyeliner, like a real cat)
    if S["rim"] > 0:
        for e in eyes:
            c = np.array(e["center"])
            side = 1 if c[0] > 0 else -1
            cz, sz = np.cos(side * -0.12), np.sin(side * -0.12)
            cx, sx = np.cos(0.06), np.sin(0.06)
            rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
            rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
            q = (P - c) @ (rz @ rx)          # into the lens frame (row vectors: v @ R = R^T v)
            rad = np.hypot(q[:, 0], q[:, 2])
            band = (rad > er * 1.02) & (q[:, 1] < 0.006) & head   # not the socket walls under the lens
            rim = band * inside(rad - (er + S["rim"])) * (S["edge"] > 0)
            dark = np.array((0.24, 0.12, 0.08))
            col = col * (1 - rim[:, None]) + dark[None, :] * rim[:, None]

    # write, then bleed the colours past the island borders so mipmaps don't pull in the gutter
    img = np.zeros(pos.shape, np.float32)
    img[mask] = col
    m = mask.astype(np.float32)
    for _ in range(10):
        if m.min() > 0:
            break
        acc = np.zeros_like(img)
        cnt = np.zeros_like(m)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            acc += np.roll(img * m[..., None], (dy, dx), (0, 1))
            cnt += np.roll(m, (dy, dx), (0, 1))
        fill = (m == 0) & (cnt > 0)
        img[fill] = acc[fill] / cnt[fill][:, None]
        m = np.where(fill, 1.0, m)
    out = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
    out = out.filter(ImageFilter.GaussianBlur(0.6))
    out.save(os.path.join(CAT, f"cat_{NAME}_toon.png"))
    print("wrote", f"cat_{NAME}_toon.png", out.size)


main()
