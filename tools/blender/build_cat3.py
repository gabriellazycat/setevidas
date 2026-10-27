"""Mingau v3: a cat built from scratch (no generated base mesh, no photo texture), in styles to choose
from. The body is a skin-modifier skeleton (torso, neck, legs, tail) plus ellipsoids (skull, cheeks,
muzzle, chin) and flat cone ears, all fused by a voxel remesh and relaxed so the joins round off. The
coat is painted per vertex from body position (white muzzle / bib / belly / socks, tabby stripes,
patches). The eyes, nose and mouth are flat decals projected onto the face (painted anime eyes with a
thick rim, big pupil and one catchlight, like the cartoon cats this is styled after), not eyeballs.
Toon preview in EEVEE: 2-band ramp, inverted-hull outline tinted by the coat.

usage: blender -b -P tools/blender/build_cat3.py -- [--style NAME|all] [--preview DIR] [--out DIR]
Blender coords: the cat faces -Y, Z up, feet at z=0 (same frame as build_cat2.py).
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector as V
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(__file__))
import lib  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
STYLE = argv[argv.index("--style") + 1] if "--style" in argv else "all"
PREVIEW = argv[argv.index("--preview") + 1] if "--preview" in argv else None
OUT = argv[argv.index("--out") + 1] if "--out" in argv else None

# --- styles: body shape, coat, face. Lengths in metres; colours sRGB 0..1
BASE = {
    "head": (0.0, -0.205, 0.272), "head_r": 0.066, "head_s": (1.08, 0.95, 0.9),
    "cheek": 0.036, "cheek_out": 0.036, "muzzle": 0.021, "muzzle_y": 0.05, "chin": 0.017,
    "ear_h": 0.06, "ear_w": 0.03, "ear_spread": 0.036, "ear_tilt": 0.16, "ear_back": 0.012,
    "chest": 0.064, "belly": 0.06, "hips": 0.062, "back_z": 0.165, "body_len": 1.0,
    "leg": 0.025, "paw": 0.022, "leg_len": 0.9, "tail_r": 0.016, "tail_len": 1.0, "tail_curl": 0.5,
    "fluff": 0.0,
    "coat": "tabby_white", "base": (0.93, 0.55, 0.24), "dark": (0.8, 0.4, 0.15), "white": (0.99, 0.96, 0.9),
    "stripe": 0.35, "nose": (0.93, 0.55, 0.6), "inner_ear": (0.96, 0.7, 0.68),
    "eye": "round", "eye_size": 0.019, "eye_az": 0.48, "eye_el": 0.12, "iris": (0.45, 0.9, 0.3), "iris_dark": (0.12, 0.45, 0.1),
    "pupil": 0.45, "rim": (0.12, 0.07, 0.06), "mouth": "w", "whiskers": True, "outline": 0.35,
}
STYLES = {
    # kitten: big round head, short body, round flat eyes with big pupils, tabby with white
    "biscoito": {},
    # slim adult in solid ginger with a cream belly, almond anime eyes with a lid line
    "chama": {"head_r": 0.06, "head_s": (1.0, 1.0, 0.92), "cheek": 0.03, "ear_h": 0.07, "ear_w": 0.032,
              "chest": 0.058, "belly": 0.052, "hips": 0.056, "body_len": 1.15, "leg": 0.021, "paw": 0.019,
              "leg_len": 1.12, "tail_len": 1.25, "tail_r": 0.014, "coat": "solid_belly", "base": (0.95, 0.52, 0.2),
              "dark": (0.85, 0.42, 0.15), "white": (0.99, 0.88, 0.72), "eye": "almond", "eye_size": 0.017,
              "iris": (0.98, 0.72, 0.2), "iris_dark": (0.6, 0.3, 0.05), "pupil": 0.3, "mouth": "w"},
    # porridge ("mingau"): cream coat, warm orange ears/tail tip/mask, chubby, big blue-green eyes
    "creme": {"head_r": 0.07, "head_s": (1.12, 0.95, 0.88), "cheek": 0.04, "ear_h": 0.052, "chest": 0.07,
              "belly": 0.072, "hips": 0.07, "body_len": 0.9, "leg": 0.027, "paw": 0.024, "leg_len": 0.78,
              "tail_r": 0.019, "coat": "points", "base": (0.99, 0.92, 0.8), "dark": (0.93, 0.6, 0.32),
              "eye_size": 0.021, "iris": (0.35, 0.8, 0.85), "iris_dark": (0.1, 0.35, 0.5), "pupil": 0.5,
              "mouth": "ws", "outline": 0.45},
    # bold tabby: sharper ears, longer muzzle, slit pupils, dark rich stripes
    "tigre": {"head_r": 0.062, "head_s": (1.0, 1.02, 0.92), "muzzle_y": 0.058, "muzzle": 0.02, "ear_h": 0.068,
              "ear_w": 0.03, "ear_tilt": 0.22, "coat": "bold_tabby", "base": (0.9, 0.5, 0.2), "dark": (0.6, 0.27, 0.1),
              "stripe": 0.42, "eye": "slit", "eye_size": 0.018, "iris": (0.85, 0.9, 0.3), "iris_dark": (0.4, 0.55, 0.08),
              "pupil": 0.18, "mouth": "w", "body_len": 1.08, "leg_len": 1.05},
    # fluffy bicolour: cheek tufts, ruff, bushy tail, orange cap and saddle on white, amber eyes
    "bolinha": {"head_r": 0.068, "cheek": 0.04, "fluff": 1.0, "chest": 0.07, "belly": 0.066, "hips": 0.066,
                "tail_r": 0.024, "coat": "bicolor", "base": (0.95, 0.56, 0.22), "dark": (0.86, 0.45, 0.16),
                "eye_size": 0.02, "iris": (0.9, 0.62, 0.22), "iris_dark": (0.45, 0.22, 0.06), "pupil": 0.5,
                "mouth": "ws", "leg_len": 0.92},
}


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def ss_np(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def activate(ob):
    lib.deselect_all()
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def ellipsoid(name, c, r, s=(1, 1, 1), rot=(0, 0, 0)):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=20, radius=r)
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me))
    ob.location = c
    ob.scale = s
    ob.rotation_euler = rot
    return ob


def skin(name, verts, edges, radii):
    """a skin-modifier tube body (applied, subdivided once)"""
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], edges, [])
    ob = link(bpy.data.objects.new(name, me))
    ob.modifiers.new("skin", "SKIN")
    for i, r in enumerate(radii):
        rx, ry = (r, r) if not isinstance(r, tuple) else r
        me.skin_vertices[0].data[i].radius = (rx, ry)
    me.skin_vertices[0].data[0].use_root = True
    sub = ob.modifiers.new("sub", "SUBSURF")
    sub.levels = 2
    activate(ob)
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    return ob


def bezier(p0, p1, p2, p3, n):
    out = []
    for i in range(n):
        t = i / (n - 1)
        out.append(p0 * (1 - t) ** 3 + p1 * 3 * t * (1 - t) ** 2 + p2 * 3 * t * t * (1 - t) + p3 * t ** 3)
    return out


def ear(name, S, side):
    """a flat rounded cone, tilted outward and a little back, its base sunk into the skull"""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=S["ear_w"], radius2=0.0012, depth=S["ear_h"])
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me))
    hc = V(S["head"])
    r = S["head_r"]
    ob.location = hc + V((side * S["ear_spread"] * r / 0.066, S["ear_back"], r * S["head_s"][2] * 0.78 + S["ear_h"] * 0.35))
    ob.scale = (1.0, 0.34, 1.0)
    ob.rotation_euler = (-0.12, side * -S["ear_tilt"], side * -0.12)
    return ob


def build_body(S):
    hc = V(S["head"])
    r = S["head_r"]
    hs = S["head_s"]
    parts = [ellipsoid("skull", hc, r, hs)]
    my = hc.y - r * hs[1] * 0.62 - S["muzzle_y"] * 0.25
    mz = hc.z - r * 0.36
    for sd in (-1, 1):
        parts.append(ellipsoid("cheek", hc + V((sd * S["cheek_out"] * r / 0.066, -r * 0.45, -r * 0.38)), S["cheek"], (1.1, 0.9, 0.85)))
        parts.append(ellipsoid("muzzle", V((sd * S["muzzle"] * 0.55, my, mz)), S["muzzle"], (1.0, 0.9, 0.82)))
    parts.append(ellipsoid("chin", V((0, my + 0.006, mz - S["muzzle"] * 0.75)), S["chin"], (1.0, 0.9, 0.8)))
    if S["fluff"]:
        # cheek tufts: small pointed ellipsoids fanning back from the jaw, and a chest ruff
        for sd in (-1, 1):
            for k in range(3):
                a = 0.5 + k * 0.45
                parts.append(ellipsoid("tuft", hc + V((sd * (r * 1.0), -r * 0.05 + k * 0.012, -r * (0.42 + 0.15 * k))),
                                       0.016, (1.5, 0.6, 0.55), (0, sd * a, sd * 0.6)))
    parts += [ear("ear_L", S, 1), ear("ear_R", S, -1)]
    # torso, neck, legs and tail as one skin skeleton
    L = S["body_len"]
    bz = S["back_z"]
    ll = S["leg_len"]
    chest = V((0, -0.115, bz))
    belly = V((0, -0.115 + 0.11 * L, bz - 0.005))
    hips = V((0, -0.115 + 0.22 * L, bz - 0.002))
    neck = hc + V((0, 0.045, -0.05))
    verts = [hips, belly, chest, neck]
    radii = [S["hips"], S["belly"], S["chest"], 0.04]
    edges = [(0, 1), (1, 2), (2, 3)]

    limbs = []

    def chain(pts, rs, parent):
        # each limb is its own tube from inside the torso (one skeleton with branches folds the hulls)
        start = verts[parent] + (pts[0] - verts[parent]) * 0.3
        vs = [start] + list(pts)
        limbs.append(skin("limb", vs, [(i, i + 1) for i in range(len(vs) - 1)], [rs[0]] + list(rs)))

    lg, pw = S["leg"], S["paw"]
    sh = 0.13 * ll
    for sd in (-1, 1):
        x = sd * 0.036
        chain([V((x, chest.y - 0.005, bz - 0.035)), V((x, chest.y - 0.01, bz - 0.035 - sh * 0.5)),
               V((x, chest.y - 0.012, pw * 0.9)), V((x, chest.y - 0.022, pw * 0.75))],
              [lg * 1.35, lg, lg * 0.92, (pw, pw * 1.05)], 2)
        # thigh down and forward to the knee, shin back to a high hock, then the long foot down
        chain([V((x * 1.1, hips.y, bz - 0.025)), V((x * 1.12, hips.y - 0.022, bz - 0.06)),
               V((x * 1.05, hips.y + 0.022, pw * 3.0)), V((x * 1.05, hips.y + 0.014, pw * 0.75))],
              [lg * 1.6, lg * 1.05, lg * 0.82, (pw, pw * 1.1)], 0)
    tl = S["tail_len"]
    tc = S["tail_curl"]
    t0 = hips + V((0, 0.05, 0.012))
    tail = bezier(t0, t0 + V((0, 0.07 * tl, -0.02)), t0 + V((0, 0.16 * tl, 0.03 + 0.05 * tc)),
                  t0 + V((0, 0.2 * tl, 0.09 + 0.1 * tc)), 8)
    tr = S["tail_r"] * (1.4 if S["fluff"] else 1.0)
    chain(tail[1:], [tr * (1.0 - 0.25 * i / 7) for i in range(1, 8)], 0)
    parts.append(skin("trunk", verts, edges, radii))
    parts += limbs
    if S["fluff"]:
        parts.append(ellipsoid("ruff", chest + V((0, -0.035, 0.035)), 0.05, (1.15, 0.8, 1.0)))
    # fuse, then relax so the joins become soft fillets
    activate(parts[0])
    for p in parts:
        p.select_set(True)
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = "cat_body"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    rm = body.modifiers.new("remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = 0.0024
    sm = body.modifiers.new("smooth", "LAPLACIANSMOOTH")
    sm.lambda_factor = 0.8
    sm.iterations = 12
    bpy.ops.object.modifier_apply(modifier="remesh")
    bpy.ops.object.modifier_apply(modifier="smooth")
    for p in body.data.polygons:
        p.use_smooth = True
    return body


def ear_frame(S, side):
    """ear base centre, outward-up axis and its front normal (for the inner-ear paint)"""
    hc = V(S["head"])
    r = S["head_r"]
    base = hc + V((side * S["ear_spread"] * r / 0.066, S["ear_back"], r * S["head_s"][2] * 0.78 + S["ear_h"] * 0.35))
    rot = __import__("mathutils").Euler((-0.12, side * -S["ear_tilt"], side * -0.12)).to_matrix()
    return base, rot


def paint(body, S):
    me = body.data
    n = len(me.vertices)
    P = np.array([tuple(v.co) for v in me.vertices])
    N = np.array([tuple(v.normal) for v in me.vertices])
    x, y, z = P.T
    ax = np.abs(x)
    nz, ny = N[:, 2], N[:, 1]
    hc = np.array(S["head"])
    r = S["head_r"]
    base, dark, white = np.array(S["base"]), np.array(S["dark"]), np.array(S["white"])
    col = np.tile(base, (n, 1))
    head = (y < hc[1] + r * 0.6) & (z > S["back_z"] + 0.02)
    face = head & (y < hc[1] - r * 0.3)
    mz = hc[2] - r * 0.4
    muzzle = face & (((x / (r * 0.55)) ** 2 + ((z - mz) / (r * 0.45)) ** 2) < 1.0)
    blaze = face & (z > mz) & (z < hc[2] + r * 0.45) & (ax < r * 0.17 * (1 - (z - mz) / (r * 0.85)))
    chin = head & (z < mz - r * 0.15) & (nz < 0.3)
    bib = (y < -0.1) & (y > hc[1] - 0.02) & (z < hc[2] - r * 0.25) & (z > 0.07) & ((ny < -0.2) | (nz < -0.3)) & (ax < 0.03 + 0.03 * ss_np(0.22, 0.15, z))
    belly = (nz < -0.35) & (z < S["back_z"] - 0.02)
    socks = z < 0.035
    tip = (y > 0.2) & (z > 0.13)
    stripes_body = ((np.abs(np.mod((y - 0.3 * (0.2 - z)) / 0.032 + 0.15 * np.sin(x * 60), 1.0) - 0.5) * 2) < S["stripe"]) & (z > 0.12) & ~head & ~belly
    stripes_leg = ((np.abs(np.mod(z / 0.024, 1.0) - 0.5) * 2) < S["stripe"]) & (z < 0.12) & (z > 0.04)
    fore = head & (z > hc[2] + r * 0.5) & (ax < r * 0.4) & ((np.abs(np.mod(x / (r * 0.18) + 0.5, 1.0) - 0.5) * 2) < 0.35)
    c = S["coat"]
    W = np.zeros(n, bool)
    D = np.zeros(n, bool)
    if c == "tabby_white":
        W = muzzle | blaze | chin | bib | belly | socks
        D = stripes_body | stripes_leg | fore
    elif c == "solid_belly":
        W = (belly | bib | chin | (muzzle & (z < mz))) & ~socks
        D = fore
    elif c == "points":
        # cream body, warm ears, mask round the eyes/forehead, paws and tail
        D = ((z > hc[2] + r * 0.55) & head) | (y > 0.17) | (z < 0.03) | (face & ~muzzle & (z > mz + r * 0.2))
        D &= ~(muzzle | blaze)
    elif c == "bold_tabby":
        W = (muzzle & (z < mz + r * 0.1)) | chin
        D = stripes_body | stripes_leg | fore | (head & ~face & ((np.abs(np.mod((z - hc[2]) / (r * 0.2), 1.0) - 0.5) * 2) < 0.4) & (ax > r * 0.5))
    elif c == "bicolor":
        saddle = (z > S["back_z"] - 0.01 + 0.02 * np.sin(y * 40)) & ~head & (y > -0.08)
        cap = head & ((z > hc[2] + 0.004) | (ax > r * 0.55)) & ~(blaze | muzzle)
        tailc = y > 0.16
        W = np.ones(n, bool)
        D = np.zeros(n, bool)
        col[:] = white
        orange = saddle | cap | tailc
        col[orange] = base
        W = ~orange
        D = orange & stripes_body
    col[D] = dark if c != "points" else dark
    if c != "bicolor":
        col[W] = white
    # inner ears
    for sd in (1, -1):
        b0, rot = ear_frame(S, sd)
        q = (P - np.array(b0)) @ np.array(rot)
        inner = (q[:, 1] < -0.002) & (q[:, 2] > -S["ear_h"] * 0.35) & (np.abs(q[:, 0]) < S["ear_w"] * 0.7 * (1 - (q[:, 2] + S["ear_h"] * 0.35) / (S["ear_h"] * 0.95)))
        col[inner] = np.array(S["inner_ear"])
    # soften the borders: average with the neighbours twice (about two voxels of feather)
    e = np.array([tuple(ed.vertices) for ed in me.edges])
    for _ in range(2):
        acc = col.copy()
        cnt = np.ones(n)
        np.add.at(acc, e[:, 0], col[e[:, 1]])
        np.add.at(acc, e[:, 1], col[e[:, 0]])
        np.add.at(cnt, e[:, 0], 1)
        np.add.at(cnt, e[:, 1], 1)
        col = acc / cnt[:, None]
    ca = me.color_attributes.new("coat", "FLOAT_COLOR", "POINT")
    lin = np.where(col <= 0.04045, col / 12.92, ((col + 0.055) / 1.055) ** 2.4)   # attribute colours are linear
    rgba = np.concatenate([lin, np.ones((n, 1))], 1).astype(np.float32)
    ca.data.foreach_set("color", rgba.ravel())
    me.color_attributes.active_color = ca


# ---------------------------------------------------------------- painted face decals

TEX = 256


def _img(name, rgba):
    img = bpy.data.images.new(name, TEX, TEX, alpha=True)
    img.colorspace_settings.name = "sRGB"
    img.pixels.foreach_set(rgba.astype(np.float32).ravel())
    img.pack()
    return img


def eye_tex(S, side):
    """a flat anime cat eye: thick dark rim, bright iris darker at the top, big pupil, one catchlight
    (round), plus an upper lid line (almond) or a slit pupil (slit). Image y runs up."""
    g = (np.arange(TEX) + 0.5) / TEX * 2 - 1
    X, Y = np.meshgrid(g, g)
    st = S["eye"]
    if st == "almond":
        # lemon shape: the top lid flatter, the outer corner lifted
        Ys = Y - 0.12 * X * side
        d = np.sqrt((X / 0.98) ** 2 + (Ys / (0.8 + 0.12 * (Ys < 0))) ** 2)
    else:
        d = np.sqrt(X ** 2 + Y ** 2)
    a = ss_np(0.99, 0.95, d)
    iris_d, iris_l = np.array(S["iris_dark"]), np.array(S["iris"])
    t = ss_np(0.7, -0.5, Y)
    col = iris_d[None, None, :] * (1 - t[..., None]) + iris_l[None, None, :] * t[..., None]
    # lighter ring low in the iris
    col = col + (0.12 * ss_np(0.75, 0.2, np.abs(np.sqrt(X ** 2 + (Y + 0.25) ** 2) - 0.45)))[..., None]
    pw = S["pupil"]
    if st == "slit":
        pd = np.sqrt((X / max(pw, 0.08)) ** 2 + (Y / 0.75) ** 2)
    else:
        pd = np.sqrt(X ** 2 + Y ** 2) / (pw + 0.12)
    pup = ss_np(1.03, 0.97, pd)
    col = col * (1 - pup[..., None]) + np.array((0.05, 0.03, 0.04))[None, None, :] * pup[..., None]
    rim = ss_np(0.8, 0.86, d)
    col = col * (1 - rim[..., None]) + np.array(S["rim"])[None, None, :] * rim[..., None]
    if st == "almond":
        lid = ss_np(0.62, 0.7, Y - 0.12 * X * side) * ss_np(1.02, 0.9, d)
        col = col * (1 - lid[..., None]) + np.array(S["rim"])[None, None, :] * lid[..., None]
    hl = ss_np(0.27, 0.23, np.sqrt((X + 0.3) ** 2 + (Y - 0.32) ** 2))
    hl = np.maximum(hl, ss_np(0.11, 0.08, np.sqrt((X - 0.32) ** 2 + (Y + 0.36) ** 2)))
    col = col * (1 - hl[..., None]) + hl[..., None]
    return _img(f"eye_{st}_{side}", np.concatenate([np.clip(col, 0, 1), a[..., None]], 2))


def nose_tex(S):
    g = (np.arange(TEX) + 0.5) / TEX * 2 - 1
    X, Y = np.meshgrid(g, g)
    # rounded inverted triangle (the pad), a touch darker along its lower edge
    t = (0.75 - Y) / 1.5
    w = 0.95 * (1 - np.clip(t, 0, 1)) ** 0.75 + 0.08
    d = np.maximum(np.abs(X) / w, np.abs(Y) / 0.78)
    a = ss_np(1.0, 0.9, d)
    nc = np.array(S["nose"])
    col = np.tile(nc, (TEX, TEX, 1)) * (1 - 0.25 * ss_np(0.2, -0.6, Y))[..., None]
    col = col + 0.25 * ss_np(0.25, 0.0, np.sqrt((X + 0.2) ** 2 + (Y - 0.35) ** 2))[..., None]
    return _img("nose", np.concatenate([np.clip(col, 0, 1), a[..., None]], 2))


def mouth_tex(S):
    g = (np.arange(TEX) + 0.5) / TEX * 2 - 1
    X, Y = np.meshgrid(g, g)
    kind = S["mouth"]
    half = 0.75 if kind == "w" else 0.55
    dep = 0.35 if kind == "w" else 0.26
    # distance to the 'ω' (two arcs) and the short philtrum line above it
    tx = np.clip(np.abs(X) / half, 0, 1)
    cy = 0.15 - dep * np.sin(np.pi * tx) + 0.18 * tx * tx
    dd = np.where(np.abs(X) < half, np.abs(Y - cy), 1.0)
    dd = np.minimum(dd, np.where((Y > 0.15) & (Y < 0.7), np.abs(X) * 1.0, 1.0))
    a = ss_np(0.075, 0.045, dd)
    col = np.tile(np.array((0.32, 0.13, 0.12)), (TEX, TEX, 1))
    return _img("mouth", np.concatenate([col, a[..., None]], 2))


def decal(name, bvh, c, nrm, w, h, img, lift=0.0007, res=14):
    """a grid of res x res quads wrapped onto the surface around c, facing out along nrm"""
    f = -nrm.normalized()
    right = f.cross(V((0, 0, 1))).normalized()
    up = right.cross(f).normalized()
    verts, uvs = [], []
    for j in range(res + 1):
        for i in range(res + 1):
            u, v = i / res, j / res
            g = c + right * ((u - 0.5) * w) + up * ((v - 0.5) * h)
            loc, hn, _i, _d = bvh.ray_cast(g - f * 0.03, f)
            p = (loc + hn * lift) if loc is not None else g
            verts.append(p)
            uvs.append((u, v))
    faces = [(j * (res + 1) + i, j * (res + 1) + i + 1, (j + 1) * (res + 1) + i + 1, (j + 1) * (res + 1) + i)
             for j in range(res) for i in range(res)]
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(p) for p in verts], [], faces)
    uvl = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        poly.use_smooth = True
        for li in poly.loop_indices:
            uvl.data[li].uv = uvs[me.loops[li].vertex_index]
    ob = link(bpy.data.objects.new(name, me))
    ob.data.materials.append(decal_mat(name, img))
    return ob


def face(body, S):
    me = body.data
    bvh = BVHTree.FromPolygons([v.co.copy() for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
    hc = V(S["head"])
    out = []

    def hit_dir(d):
        loc, nr, _i, _dd = bvh.ray_cast(hc + d * 0.4, -d)
        return loc, nr

    for sd, nm in ((1, "L"), (-1, "R")):
        az, el = S["eye_az"] * sd, S["eye_el"]
        d = V((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el))).normalized()
        loc, nr = hit_dir(d)
        nr = (nr + V((0, -0.6, 0))).normalized()   # keep the painted eye facing mostly forward
        s = S["eye_size"]
        out.append(decal(f"cat_eye_{nm}", bvh, loc, nr, s * 2, s * 2, eye_tex(S, sd), lift=0.0009))
    # nose on the front of the muzzle, the mouth just below it
    loc, nr = hit_dir(V((0, -1, -0.28)).normalized())
    out.append(decal("cat_nose", bvh, loc + V((0, 0, 0.002)), V((0, -1, 0.15)), 0.014, 0.011, nose_tex(S), lift=0.0011))
    if S["mouth"]:
        out.append(decal("cat_mouthline", bvh, loc + V((0, 0, -0.0085)), V((0, -1, 0.05)), 0.02, 0.014, mouth_tex(S), lift=0.0009))
    if S["whiskers"]:
        out.append(whiskers(bvh, loc + V((0, 0, -0.004)), S))
    return out


def whiskers(bvh, root, S):
    objs = []
    for sd in (-1, 1):
        for k in range(3):
            st = root + V((sd * 0.012, 0.004, 0.002 - k * 0.003))
            loc, nr, _i, _d = bvh.ray_cast(st + V((0, -0.05, 0)), V((0, 1, 0)))
            st = loc if loc is not None else st
            d = V((sd, -0.25 + k * 0.12, 0.08 - k * 0.1)).normalized()
            pts = [st + d * (0.055 * t) + V((0, 0.01 * t * t, -0.008 * t * t)) for t in (0.0, 0.33, 0.66, 1.0)]
            cu = bpy.data.curves.new("wh", "CURVE")
            cu.dimensions = "3D"
            cu.bevel_depth = 0.0005
            sp = cu.splines.new("POLY")
            sp.points.add(len(pts) - 1)
            for i, p in enumerate(pts):
                sp.points[i].co = (p.x, p.y, p.z, 1)
            objs.append(link(bpy.data.objects.new("wh", cu)))
    activate(objs[0])
    for o in objs:
        o.select_set(True)
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    wh = bpy.context.view_layer.objects.active
    wh.name = "cat_whiskers"
    wh.data.materials.append(flat_mat("whisker", (0.95, 0.9, 0.86)))
    return wh


# ---------------------------------------------------------------- toon preview materials


def _nodes(m):
    try:
        m.use_nodes = True
    except Exception:  # noqa: BLE001
        pass
    nt = m.node_tree
    for nd in list(nt.nodes):
        nt.nodes.remove(nd)
    return nt


def toon_mat(S):
    m = bpy.data.materials.new("coat_toon")
    nt = _nodes(m)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    diff = nt.nodes.new("ShaderNodeBsdfDiffuse")
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "EASE"
    ramp.color_ramp.elements[0].position = 0.18
    ramp.color_ramp.elements[0].color = (0.62, 0.5, 0.52, 1)
    ramp.color_ramp.elements[1].position = 0.24
    ramp.color_ramp.elements[1].color = (1, 1, 1, 1)
    attr = nt.nodes.new("ShaderNodeAttribute")
    attr.attribute_name = "coat"
    mul = nt.nodes.new("ShaderNodeMixRGB")
    mul.blend_type = "MULTIPLY"
    mul.inputs[0].default_value = 1.0
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(diff.outputs[0], s2r.inputs[0])
    nt.links.new(s2r.outputs[0], ramp.inputs[0])
    nt.links.new(attr.outputs["Color"], mul.inputs[1])
    nt.links.new(ramp.outputs[0], mul.inputs[2])
    nt.links.new(mul.outputs[0], em.inputs[0])
    nt.links.new(em.outputs[0], out.inputs[0])
    return m


def outline_mat(S):
    m = bpy.data.materials.new("coat_outline")
    nt = _nodes(m)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    attr = nt.nodes.new("ShaderNodeAttribute")
    attr.attribute_name = "coat"
    mul = nt.nodes.new("ShaderNodeMixRGB")
    mul.blend_type = "MULTIPLY"
    mul.inputs[0].default_value = 1.0
    mul.inputs[2].default_value = (S["outline"] * 0.5, S["outline"] * 0.32, S["outline"] * 0.36, 1)
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(attr.outputs["Color"], mul.inputs[1])
    nt.links.new(mul.outputs[0], em.inputs[0])
    nt.links.new(em.outputs[0], out.inputs[0])
    m.use_backface_culling = True
    return m


def flat_mat(name, color):
    m = bpy.data.materials.new(name)
    nt = _nodes(m)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = (*[c ** 2.2 for c in color], 1)
    nt.links.new(em.outputs[0], out.inputs[0])
    return m


def decal_mat(name, img):
    m = bpy.data.materials.new(name + "_mat")
    nt = _nodes(m)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Linear"
    em = nt.nodes.new("ShaderNodeEmission")
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(tex.outputs["Color"], em.inputs[0])
    nt.links.new(tex.outputs["Alpha"], mix.inputs[0])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])
    for attr, val in (("blend_method", "BLEND"), ("surface_render_method", "BLENDED")):
        try:
            setattr(m, attr, val)
        except Exception:  # noqa: BLE001
            pass
    return m


def dress(body, S):
    body.data.materials.append(toon_mat(S))
    body.data.materials.append(outline_mat(S))
    so = body.modifiers.new("outline", "SOLIDIFY")
    so.thickness = 0.0016
    so.offset = 1.0
    so.use_flip_normals = True
    so.use_rim = False
    so.material_offset = 1


def render(name, objs, out_dir):
    scene = lib.setup_render((900, 900), 16)
    try:
        scene.view_settings.view_transform = "Standard"
    except Exception:  # noqa: BLE001
        pass
    scene.world.color = (0.55, 0.6, 0.68)
    try:
        scene.render.film_transparent = False
    except Exception:  # noqa: BLE001
        pass
    sun = link(bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")))
    sun.data.energy = 3.0
    sun.data.use_shadow = False   # toon ramp from N.L only (self-shadow acne drew a weave on the coat)
    sun.rotation_euler = (math.radians(50), 0, math.radians(-35))
    floor = ellipsoid("floor", (0, 0, -0.5), 1.0, (3, 3, 0.5))
    floor.data.materials.append(flat_mat("floor", (0.85, 0.8, 0.74)))
    cam = link(bpy.data.objects.new("cam", bpy.data.cameras.new("cam")))
    scene.camera = cam
    views = {"34": ((0.5, -0.66, 0.34), (0, -0.04, 0.17), 50), "side": ((-0.95, 0.0, 0.2), (0, -0.01, 0.17), 50),
             "face": ((-0.12, -0.55, 0.3), (0, -0.2, 0.26), 85), "front": ((0.0, -0.9, 0.22), (0, -0.05, 0.17), 50)}
    for k, (loc, tgt, lens) in views.items():
        cam.location = loc
        cam.data.lens = lens
        cam.rotation_euler = (V(tgt) - V(loc)).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(out_dir, f"{name}_{k}.png")
        bpy.ops.render.render(write_still=True)


def build(name):
    S = dict(BASE)
    S.update(STYLES[name])
    lib.reset_scene()
    body = build_body(S)
    paint(body, S)
    parts = face(body, S)
    dress(body, S)
    print("BUILT", name, "verts", len(body.data.vertices))
    if OUT:
        os.makedirs(OUT, exist_ok=True)
        lib.deselect_all()
        for o in [body] + parts:
            o.select_set(True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, f"cat3_{name}.glb"), export_format="GLB", use_selection=True,
                                  export_apply=False, export_yup=True, export_vertex_color="ACTIVE")
    if PREVIEW:
        render(name, [body] + parts, PREVIEW)


if __name__ == "__main__":   # build_cat4.py imports the face decals, materials and preview from here
    for _n in (STYLES if STYLE == "all" else [STYLE]):
        build(_n)
