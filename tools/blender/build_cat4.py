"""Mingau v4: the from-scratch cat (build_cat3.py) remodelled with cat anatomy instead of tubes and
balls. Every part is lofted through cross-sections: a deep narrow chest, tucked waist, low belly
pouch and round croup; a skull with flat brow, cheeks wider than the crown, a short muzzle with whisker
pads and a small chin; cupped triangular ears; shoulder blades, elbows, thin forearms, broad thighs,
a high hock and long hind feet; oval paws with toes. Fused by a voxel remesh and lightly relaxed.
Face decals (painted slit-pupil eyes, nose, mouth), toon materials and the preview come from
build_cat3.py.

usage: blender -b -P tools/blender/build_cat4.py -- [--style creme|bolinha|all] [--preview DIR] [--out DIR]
Blender coords: the cat faces -Y, Z up, feet at z=0.
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Vector as V

sys.path.insert(0, os.path.dirname(__file__))
import build_cat3 as c3  # noqa: E402
import lib  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
STYLE = argv[argv.index("--style") + 1] if "--style" in argv else "all"
PREVIEW = argv[argv.index("--preview") + 1] if "--preview" in argv else None
OUT = argv[argv.index("--out") + 1] if "--out" in argv else None

# face: the slit eyes of the "tigre" study
FACE = {"eye": "slit", "eye_size": 0.0165, "eye_az": 0.5, "eye_el": 0.1, "iris": (0.85, 0.9, 0.3),
        "iris_dark": (0.4, 0.55, 0.08), "pupil": 0.18, "rim": (0.12, 0.07, 0.06), "nose": (0.93, 0.55, 0.6),
        "mouth": "ws", "whiskers": True}
STYLES = {
    # porridge: cream with warm orange points, chubby and short-legged, small rounded ears
    "creme": {"girth": 1.16, "dz": -0.016, "ys": 0.86, "head_k": 1.24, "cheek_k": 1.06, "ear_k": 0.88, "ear_round": 0.5,
              "tail_r": 0.0135, "fluff": 0.0, "coat": "points", "base": (0.99, 0.93, 0.82),
              "dark": (0.93, 0.6, 0.32), "white": (1.0, 0.97, 0.92), "outline": 0.45},
    # fluffy bicolour: ruff, cheek tufts, breeches, plume tail; orange cap and saddle on white
    "bolinha": {"girth": 1.06, "dz": -0.004, "ys": 0.88, "head_k": 1.2, "cheek_k": 1.1, "ear_k": 1.0, "ear_round": 0.25,
                "tail_r": 0.019, "fluff": 1.0, "coat": "bicolor", "base": (0.95, 0.56, 0.22),
                "dark": (0.84, 0.44, 0.15), "white": (0.99, 0.96, 0.9), "outline": 0.35},
}


def ss(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def catmull(pts, n):
    """Catmull-Rom through pts, n samples per span, ends included"""
    P = [pts[0] + (pts[0] - pts[1])] + list(pts) + [pts[-1] + (pts[-1] - pts[-2])]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for k in range(n):
            t = k / n
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(pts[-1])
    return out


def loft(name, keys, sub=6, ring=36, e=2.2, cap=(True, True)):
    """a closed body through cross-sections. keys: (centre, w_up, w_down, h_up, h_down): half-widths
    (sideways) on the upper / lower half and half-heights up / down; 'up' is the side facing +Z (or
    backward, +Y, for near-vertical parts such as legs). e > 2 squares the sections a little."""
    cs = catmull([k[0] for k in keys], sub)
    dims = []
    for i in range(len(keys) - 1):
        for k in range(sub):
            t = k / sub
            t = t * t * (3 - 2 * t)
            dims.append([a + (b - a) * t for a, b in zip(keys[i][1:], keys[i + 1][1:])])
    dims.append(list(keys[-1][1:]))
    rings = []
    X = V((1, 0, 0))
    vprev = None
    for i, c in enumerate(cs):
        tg = (cs[min(i + 1, len(cs) - 1)] - cs[max(i - 1, 0)]).normalized()
        u = (X - tg * X.dot(tg)).normalized()
        v = u.cross(tg).normalized()
        if vprev is None:
            if (abs(v.z) > 0.3 and v.z < 0) or (abs(v.z) <= 0.3 and v.y < 0):
                v = -v
        elif v.dot(vprev) < 0:   # keep the frame continuous (a sudden flip twisted tails and legs)
            v = -v
        vprev = v
        wu, wd, hu, hd = dims[i]
        pts = []
        for j in range(ring):
            th = 2 * math.pi * j / ring
            co, si = math.cos(th), math.sin(th)
            w = wd + (wu - wd) * ss(-0.6, 0.6, si)
            h = hu if si >= 0 else hd
            pts.append(c + u * (w * math.copysign(abs(co) ** (2 / e), co)) + v * (h * math.copysign(abs(si) ** (2 / e), si)))
        rings.append((pts, c, tg))
    verts, faces = [], []
    for pts, _c, _t in rings:
        verts += pts
    n = len(rings)
    for i in range(n - 1):
        for j in range(ring):
            a, b = i * ring + j, i * ring + (j + 1) % ring
            faces.append((a, b, b + ring, a + ring))
    # rounded caps: two shrinking rings and a pole
    for end, ok in ((0, cap[0]), (n - 1, cap[1])):
        if not ok:
            continue
        pts, c, tg = rings[end]
        out = -tg if end == 0 else tg
        size = sum((p - c).length for p in pts) / ring
        prev = list(range(end * ring, end * ring + ring))
        for k, (sc, push) in enumerate(((0.78, 0.45), (0.42, 0.85))):
            base = len(verts)
            verts += [c + (p - c) * sc + out * (size * push * 0.6) for p in pts]
            cur = list(range(base, base + ring))
            for j in range(ring):
                faces.append((prev[j], prev[(j + 1) % ring], cur[(j + 1) % ring], cur[j]))
            prev = cur
        pole = len(verts)
        verts.append(c + out * size * 0.62)
        for j in range(ring):
            faces.append((prev[j], prev[(j + 1) % ring], pole))
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(p) for p in verts], [], faces)
    return c3.link(bpy.data.objects.new(name, me))


def cone(name, base, direction, length, radius, flat=1.0):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=radius, radius2=radius * 0.08, depth=length)
    bm.to_mesh(me)
    bm.free()
    for v in me.vertices:
        v.co.y *= flat
        v.co.z += length / 2
    ob = c3.link(bpy.data.objects.new(name, me))
    ob.location = base
    ob.rotation_euler = V((0, 0, 1)).rotation_difference(direction.normalized()).to_euler()
    return ob


def ear(name, S, side):
    """a cupped triangle: a flat cone whose front face is hollowed, rounded at the tip by ear_round"""
    k = S["ear_k"]
    H, W = 0.048 * k, 0.04 * k
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=28, radius1=W / 2, radius2=W * 0.06 * (1 + 3 * S["ear_round"]), depth=H)
    bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) > 1e-6], cuts=6)
    bm.to_mesh(me)
    bm.free()
    for v in me.vertices:
        x, y, z = v.co
        t = min(max((z + H / 2) / H, 0.0), 1.0)   # 0 base .. 1 tip
        y *= 0.32
        if y < 0:                               # front: hollow, deepest low in the middle
            w = max(W / 2 * (1 - t), 1e-4)
            y += 0.009 * k * (1 - min(1.0, (x / w) ** 2)) * (1 - t) ** 0.7
        v.co = V((x, y, z + H / 2))
    ob = c3.link(bpy.data.objects.new(name, me))
    ob.location, ob.rotation_euler = ear_frame(S, side)
    return ob


def ear_frame(S, side):
    hc = V(S["head"])
    hk = S["head_k"]
    base = hc + V((side * 0.031 * hk, 0.012, 0.024 * hk))
    rot = Euler((-0.22, side * -0.3, side * -0.32))
    return base, rot


def Z(p, S):
    """shorter legs: everything above the knees drops by dz, the paws stay on the floor; ys shortens
    the body front to back"""
    return V((p[0], p[1] * S["ys"], p[2] + S["dz"] * ss(0.03, 0.12, p[2])))


def build_body(S):
    g, hk, ck = S["girth"], S["head_k"], S["cheek_k"]
    parts = []
    # torso: (y, half width top, half width bottom, back z, belly z)
    T = [(-0.163, 0.022, 0.016, 0.182, 0.125), (-0.14, 0.04, 0.03, 0.203, 0.09), (-0.09, 0.05, 0.04, 0.207, 0.078),
         (-0.03, 0.054, 0.05, 0.198, 0.084), (0.03, 0.05, 0.05, 0.195, 0.1), (0.085, 0.052, 0.05, 0.199, 0.098),
         (0.125, 0.048, 0.042, 0.196, 0.108), (0.158, 0.026, 0.022, 0.183, 0.135)]
    keys = []
    for y, wt, wb, zt, zb in T:
        zb2 = zb - (g - 1) * 0.04 * ss(-0.12, 0.0, y) * ss(0.16, 0.05, y)
        zc = (zt + zb2) / 2
        keys.append((Z(V((0, y, zc)), S), wt * g, wb * g, zt - zc, zc - zb2))
    parts.append(loft("torso", keys, e=2.3))
    hc = Z(V((0, -0.19 / S["ys"], 0.256)), S)
    S["head"] = tuple(hc)
    # neck: from inside the chest up to the back of the skull, thick (cats have no thin neck)
    parts.append(loft("neck", [(Z(V((0, -0.11, 0.165)), S), 0.042 * g, 0.04 * g, 0.038, 0.04),
                               (Z(V((0, -0.15, 0.205)), S), 0.043, 0.041, 0.038, 0.036),
                               (hc + V((0, 0.03 * hk, -0.016)), 0.04, 0.037, 0.034, 0.03)], e=2.1))
    # skull, back to nose: (dy from head centre, w top, w bottom (cheeks), h up, h down, dz)
    Hs = [(0.045, 0.022, 0.024, 0.016, 0.018, 0.012), (0.03, 0.042, 0.046, 0.032, 0.034, 0.008),
          (0.01, 0.048, 0.056 * ck, 0.04, 0.038, 0.004), (-0.01, 0.046, 0.057 * ck, 0.04, 0.038, 0.0),
          (-0.028, 0.037, 0.046 * ck, 0.032, 0.036, -0.004), (-0.041, 0.024, 0.03, 0.021, 0.03, -0.012),
          (-0.05, 0.013, 0.016, 0.011, 0.018, -0.014)]
    parts.append(loft("skull", [(hc + V((0, dy * hk, dz * hk)), wt * hk, wb * hk, hu * hk, hd * hk)
                                for dy, wt, wb, hu, hd, dz in Hs], e=2.15))
    # whisker pads and chin
    for sd in (-1, 1):
        parts.append(c3.ellipsoid("pad", hc + V((sd * 0.011 * hk, -0.043 * hk, -0.03 * hk)), 0.0125 * hk, (1.05, 0.85, 0.8)))
    parts.append(c3.ellipsoid("chin", hc + V((0, -0.034 * hk, -0.038 * hk)), 0.009 * hk, (1.0, 0.95, 0.7)))
    parts += [ear("ear_L", S, 1), ear("ear_R", S, -1)]
    # legs: (point, half width sideways, half depth back, half depth front)
    for sd in (-1, 1):
        def leg(pts, name):
            parts.append(loft(name, [(Z(V((sd * x, y, z)), S), w, w * 0.95, db, df) for (x, y, z), w, db, df in pts], sub=5, ring=24, e=2.1))
        leg([((0.02, -0.105, 0.15), 0.014, 0.022, 0.018), ((0.033, -0.112, 0.13), 0.018, 0.024, 0.019),
             ((0.036, -0.1, 0.098), 0.017, 0.02, 0.014), ((0.035, -0.112, 0.06), 0.013, 0.012, 0.013),
             ((0.034, -0.118, 0.03), 0.0115, 0.011, 0.012), ((0.034, -0.121, 0.016), 0.012, 0.012, 0.012)], "foreleg")
        leg([((0.026, 0.1, 0.16), 0.028, 0.036, 0.036), ((0.04, 0.074, 0.115), 0.023, 0.026, 0.031),
             ((0.039, 0.085, 0.09), 0.014, 0.016, 0.018), ((0.037, 0.128, 0.052), 0.011, 0.01, 0.012),
             ((0.036, 0.12, 0.024), 0.0105, 0.011, 0.011), ((0.036, 0.116, 0.015), 0.011, 0.011, 0.011)], "hindleg")
        for (y, zf) in ((-0.13, 0), (0.105, 1)):
            pw = 0.0145 if zf == 0 else 0.0135
            parts.append(c3.ellipsoid("paw", V((sd * 0.035, y, 0.011)), pw, (1.0, 1.35, 0.78)))
            for k in range(4):
                a = (k - 1.5) * 0.42
                parts.append(c3.ellipsoid("toe", V((sd * 0.035 + math.sin(a) * pw * 0.72, y - math.cos(a) * pw * 1.15, 0.0085)),
                                          pw * 0.42, (1.0, 1.1, 0.85)))
    # tail: down from the croup, then a lazy curve up
    tr = S["tail_r"]
    tp = [Z(V(p), S) for p in ((0, 0.15, 0.178), (0, 0.18, 0.15), (0, 0.215, 0.12), (0, 0.255, 0.12), (0, 0.285, 0.15), (0, 0.3, 0.19))]
    parts.append(loft("tail", [(p, tr * (1 - 0.3 * i / 5) * (1 + 0.15 * S["fluff"] * math.sin(math.pi * i / 5)),
                                tr * (1 - 0.3 * i / 5), tr * (1 - 0.3 * i / 5), tr * (1 - 0.3 * i / 5)) for i, p in enumerate(tp)],
                      sub=5, ring=20))
    if S["fluff"]:
        parts += fluff(S, hc)
    c3.activate(parts[0])
    for p in parts:
        p.select_set(True)
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = "cat_body"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    rm = body.modifiers.new("remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = 0.0018
    sm = body.modifiers.new("smooth", "LAPLACIANSMOOTH")
    sm.lambda_factor = 0.7
    sm.iterations = 20
    bpy.ops.object.modifier_apply(modifier="remesh")
    bpy.ops.object.modifier_apply(modifier="smooth")
    for p in body.data.polygons:
        p.use_smooth = True
    return body


def fluff(S, hc):
    """tufts: a ruff round the cheeks and down the chest, breeches behind the thighs"""
    out = []
    rnd = np.random.default_rng(3)
    for sd in (-1, 1):
        for k in range(3):
            a = -0.4 + k * 0.32
            base = hc + V((sd * 0.052 * S["head_k"], 0.012 + 0.004 * k, (-0.012 + a * 0.035) * S["head_k"]))
            d = V((sd * 0.8, 0.55, -0.35 + a * 0.4))
            out.append(cone("tuft", base, d, 0.014 + 0.003 * rnd.random(), 0.013, 0.9))
        for k in range(4):
            base = Z(V((sd * 0.03, 0.135, 0.09 + k * 0.022)), S)
            out.append(cone("breech", base, V((sd * 0.3, 1.0, -0.5)), 0.016, 0.012, 0.85))
    # the chest ruff as a soft bib of volume, a point only at its lower edge
    out.append(c3.ellipsoid("ruff", Z(V((0, -0.15, 0.15)), S), 0.042, (1.15, 0.7, 1.0)))
    for k in range(3):
        out.append(cone("ruff", Z(V(((k - 1) * 0.016, -0.165, 0.118)), S), V(((k - 1) * 0.3, -0.5, -1.0)), 0.016, 0.014, 0.9))
    return out


def paint(body, S):
    me = body.data
    n = len(me.vertices)
    P = np.array([tuple(v.co) for v in me.vertices])
    N = np.array([tuple(v.normal) for v in me.vertices])
    x, y, z = P.T
    ax = np.abs(x)
    nz = N[:, 2]
    hc = np.array(S["head"])
    base, dark, white = np.array(S["base"]), np.array(S["dark"]), np.array(S["white"])
    head = (y < hc[1] + 0.05) & (z > hc[2] - 0.06)
    ears = head & (z > hc[2] + 0.03) & (ax > 0.012) & (y > hc[1] - 0.03)
    zn = hc[2] - 0.016                                   # nose level
    front = head & (y < hc[1] - 0.025)
    muzzle = front & (((x / 0.024) ** 2 + ((z - (zn - 0.012)) / 0.02) ** 2) < 1)
    blaze = front & (z > zn) & (ax < 0.011 * np.clip(1 - (z - zn) / 0.055, 0, 1))
    col = np.tile(base, (n, 1))
    if S["coat"] == "points":
        # cream, the points warm: ears, a soft mask on the face, the paws and the tail growing darker
        k = np.zeros(n)
        k = np.maximum(k, ears * 1.0)
        mask = front & ~muzzle & (z > zn - 0.006)
        k = np.maximum(k, mask * 0.75 * np.clip(1 - np.abs(x) / 0.05, 0, 1))
        k = np.maximum(k, c3.ss_np(0.04, 0.02, z))
        k = np.maximum(k, c3.ss_np(0.16, 0.3, y) * (z > 0.06))
        k = np.maximum(k, 0.22 * c3.ss_np(0.4, 0.9, nz) * ~head)        # a faint warm saddle
        col = base * (1 - k[:, None]) + dark * k[:, None]
        col[muzzle] = white
    else:
        col[:] = white
        cap = head & (z > zn + 0.012) & ~blaze
        saddle = ~head & (z > 0.17 + S["dz"] + 0.012 * np.sin(y * 45)) & (y > -0.1)
        tail = y > 0.16
        orange = cap | saddle | tail
        stripes = (np.abs(np.mod((y - 0.3 * (0.2 - z)) / 0.03, 1.0) - 0.5) * 2) < 0.32
        col[orange] = base
        col[orange & stripes] = dark
    for sd in (1, -1):
        b0, rot = ear_frame(S, sd)
        q = (P - np.array(b0)) @ np.array(rot.to_matrix())
        hh = 0.048 * S["ear_k"]
        inner = (q[:, 1] < 0.0015) & (q[:, 2] > 0.004) & (q[:, 2] < hh * 0.9) & (np.abs(q[:, 0]) < 0.02 * S["ear_k"] * 0.75 * (1 - q[:, 2] / hh))
        col[inner] = (0.96, 0.7, 0.68)
    e = np.array([tuple(ed.vertices) for ed in me.edges])
    for _ in range(2):
        acc, cnt = col.copy(), np.ones(n)
        np.add.at(acc, e[:, 0], col[e[:, 1]])
        np.add.at(acc, e[:, 1], col[e[:, 0]])
        np.add.at(cnt, e[:, 0], 1)
        np.add.at(cnt, e[:, 1], 1)
        col = acc / cnt[:, None]
    ca = me.color_attributes.new("coat", "FLOAT_COLOR", "POINT")
    lin = np.where(col <= 0.04045, col / 12.92, ((col + 0.055) / 1.055) ** 2.4)
    ca.data.foreach_set("color", np.concatenate([lin, np.ones((n, 1))], 1).astype(np.float32).ravel())
    me.color_attributes.active_color = ca


def soften_ramp(body):
    """the preview toon ramp a little wider, like the game's shade_soft, so small bumps don't patch"""
    for m in body.data.materials:
        if m and m.node_tree:
            for nd in m.node_tree.nodes:
                if nd.type == "VALTORGB":
                    nd.color_ramp.elements[0].position = 0.12
                    nd.color_ramp.elements[1].position = 0.32


def build(name):
    S = dict(FACE)
    S.update(STYLES[name])
    S["eye_size"] = FACE["eye_size"] * S["head_k"]
    lib.reset_scene()
    body = build_body(S)
    paint(body, S)
    parts = c3.face(body, S)
    c3.dress(body, S)
    soften_ramp(body)
    print("BUILT", name, "verts", len(body.data.vertices))
    if OUT:
        os.makedirs(OUT, exist_ok=True)
        lib.deselect_all()
        for o in [body] + parts:
            o.select_set(True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, f"cat4_{name}.glb"), export_format="GLB", use_selection=True,
                                  export_apply=False, export_yup=True, export_vertex_color="ACTIVE")
    if PREVIEW:
        c3.render(name, [body] + parts, PREVIEW)


for _n in (STYLES if STYLE == "all" else [STYLE]):
    build(_n)
