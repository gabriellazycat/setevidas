"""Mingau v2: a cute, realistically proportioned ginger kitten built from a generated base mesh
(tools/cache/cat_gen/cat_gen_src.glb, photographic fur texture) and re-rigged on the exact bone
names / hierarchy the procedural animation in cat_rig.gd drives, plus glass eyes (blink, pupil,
tapetum glow in the shader), whiskers and a per-vertex fur-length mask (vertex colour R) for the
shell fur.

usage: blender -b -P tools/blender/build_cat2.py -- [--preview out.png] [--no-export] [--stretch 1.2] [--out file.glb]
--stretch lengthens the torso (belly and back between shoulders and hips; default 1.75, the chosen look);
--out exports elsewhere.
Blender coords: the cat faces -Y, Z up (glTF export makes that game +Z forward). Feet at z=0.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Vector as V

sys.path.insert(0, os.path.dirname(__file__))
import lib  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIEW = argv[argv.index("--preview") + 1] if "--preview" in argv else None
EXPORT = "--no-export" not in argv
STRETCH = float(argv[argv.index("--stretch") + 1]) if "--stretch" in argv else 1.75  # chosen: torso +75%
OUT_FILE = argv[argv.index("--out") + 1] if "--out" in argv else None
# --look a|b|c: style studies over the same mesh, rig and weights (bigger kitten head, big flat anime
# eyes, shorter thicker legs, fuller tail, shorter rounder torso); reshaped after the weights are set
LOOKS = {
    "a": {"head": 1.12, "head_x": 1.05, "eye": 1.5, "eye_flat": 0.55, "eye_x": 0.004, "eye_z": -0.003,
          "leg": 1.0, "leg_w": 1.0, "tail": 1.15, "torso": 1.0, "girth": 1.0, "face_smooth": 6, "mouth": True},
    "b": {"head": 1.3, "head_x": 1.08, "eye": 1.85, "eye_flat": 0.5, "eye_x": 0.007, "eye_z": -0.005,
          "leg": 0.82, "leg_w": 1.25, "tail": 1.35, "torso": 1.0, "girth": 1.08},
    "c": {"head": 1.45, "head_x": 1.12, "eye": 2.0, "eye_flat": 0.5, "eye_x": 0.009, "eye_z": -0.006,
          "leg": 0.74, "leg_w": 1.35, "tail": 1.5, "torso": 0.55, "girth": 1.15},
}
LOOK = LOOKS[argv[argv.index("--look") + 1]] if "--look" in argv else None
# --face decal: no eyeballs; flat round eye decals (the game's anime eye shader draws them), plus a
# painted nose and mouth, wrapped onto the skin (the from-scratch studies' face on this body)
FACE_DECAL = "--face" in argv and argv[argv.index("--face") + 1] == "decal"
DECAL_EYE_R = 0.0135
SRC = os.path.join(lib.ROOT, "tools", "cache", "cat_gen", "cat_gen_src.glb")
OUT = os.path.join(lib.GODOT, "assets", "models", "cat")

# landmarks measured on the base mesh (see the session notes / measure() below)
EYE_C = [V((0.0236, -0.1898, 0.2948)), V((-0.0236, -0.1898, 0.2948))]
EYE_R = 0.0113
NOSE = V((0.0, -0.2135, 0.2675))

# bone name: (head, tail, parent) — same names and hierarchy as the v1 cat (cat_rig.gd drives them)
BONES = {
    "root": ((0, 0, 0), (0, 0.06, 0), None),
    "hips": ((0, 0.09, 0.19), (0, 0.03, 0.19), "root"),
    "spine": ((0, 0.03, 0.19), (0, -0.03, 0.195), "hips"),
    "chest": ((0, -0.03, 0.195), (0, -0.085, 0.205), "spine"),
    # the neck in two bones (base and top) so a bend spreads along it instead of folding at one joint
    "neck": ((0, -0.085, 0.212), (0, -0.1025, 0.23), "chest"),
    "neck1": ((0, -0.1025, 0.23), (0, -0.12, 0.248), "neck"),
    "head": ((0, -0.12, 0.248), (0, -0.2, 0.272), "neck1"),
    "jaw": ((0, -0.16, 0.232), (0, -0.2, 0.236), "head"),
    "ear.L": ((0.044, -0.149, 0.33), (0.06, -0.167, 0.369), "head"),
    "ear.R": ((-0.043, -0.146, 0.33), (-0.059, -0.162, 0.37), "head"),
}
TAIL = [V((0, 0.103, 0.195)), V((0, 0.122, 0.152)), V((0, 0.137, 0.105)), V((0, 0.156, 0.072)), V((0, 0.184, 0.066)), V((0, 0.214, 0.1))]
for _i in range(5):
    BONES[f"tail{_i}"] = (tuple(TAIL[_i]), tuple(TAIL[_i + 1]), "hips" if _i == 0 else f"tail{_i - 1}")
# legs (the base mesh stands with the right fore paw slightly forward)
LEGS = {
    "L": {"sh": (0.04, -0.09, 0.17), "el": (0.036, -0.078, 0.105), "wr": (0.035, -0.084, 0.03), "toe": (0.035, -0.114, 0.008),
          "hip": (0.04, 0.085, 0.18), "kn": (0.045, 0.06, 0.115), "ho": (0.036, 0.095, 0.045), "pa": (0.04, 0.08, 0.016), "htoe": (0.041, 0.058, 0.008)},
    "R": {"sh": (-0.04, -0.09, 0.17), "el": (-0.036, -0.086, 0.105), "wr": (-0.035, -0.102, 0.03), "toe": (-0.036, -0.135, 0.008),
          "hip": (-0.04, 0.085, 0.18), "kn": (-0.045, 0.058, 0.115), "ho": (-0.035, 0.09, 0.045), "pa": (-0.038, 0.075, 0.016), "htoe": (-0.039, 0.053, 0.008)},
}
for side, L in LEGS.items():
    s = 1 if side == "L" else -1
    BONES[f"shoulder.{side}"] = ((0.018 * s, -0.07, 0.205), L["sh"], "chest")
    BONES[f"upperarm.{side}"] = (L["sh"], L["el"], f"shoulder.{side}")
    BONES[f"forearm.{side}"] = (L["el"], L["wr"], f"upperarm.{side}")
    BONES[f"fpaw.{side}"] = (L["wr"], L["toe"], f"forearm.{side}")
    BONES[f"thigh.{side}"] = (L["hip"], L["kn"], "hips")
    BONES[f"shin.{side}"] = (L["kn"], L["ho"], f"thigh.{side}")
    BONES[f"hock.{side}"] = (L["ho"], L["pa"], f"shin.{side}")
    BONES[f"hpaw.{side}"] = (L["pa"], L["htoe"], f"hock.{side}")


# torso zone stretched by --stretch: behind the shoulders to in front of the hips
TORSO = (-0.06, 0.07)


def stretch_y(y):
    """front part moves forward, back part backward, the torso between them scales"""
    a, b = TORSO
    d = (STRETCH - 1.0) * (b - a)
    if y <= a:
        return y - d / 2
    if y >= b:
        return y + d / 2
    return a - d / 2 + (y - a) * STRETCH


def stretch_all():
    global NOSE
    for e in EYE_C:
        e.y = stretch_y(e.y)
    NOSE = V((NOSE.x, stretch_y(NOSE.y), NOSE.z))
    for k, (h, t, par) in list(BONES.items()):
        BONES[k] = ((h[0], stretch_y(h[1]), h[2]), (t[0], stretch_y(t[1]), t[2]), par)


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def fur_length(p):
    """relative fur length (0..1.6): velvet on the face and paws, fluffy cheeks and chest ruff,
    a soft coat on the body, a bushy tail, short on the ears, bare at the eyes and the nose."""
    x, y, z = p
    f = 1.0
    if y < -0.13:  # head
        f = 0.55
        f = max(f, 1.05 * smoothstep(0.038, 0.058, abs(x)) * smoothstep(0.31, 0.28, z))  # cheek fluff
        f += 0.25 * smoothstep(0.32, 0.345, z) * (1 - smoothstep(0.03, 0.045, abs(x)))  # crown
        f *= 0.45 + 0.55 * smoothstep(-0.212, -0.195, y)  # short muzzle
        for e in EYE_C:
            f *= 0.06 + 0.94 * smoothstep(EYE_R * 1.05, EYE_R * 1.9, (V(p) - e).length)
        f *= 0.1 + 0.9 * smoothstep(0.004, 0.011, (V(p) - NOSE).length)
        if z > 0.322 and abs(x) > 0.028:  # ears
            f = 0.28
    elif y < -0.06 and z > 0.11:
        f = 1.0 + 0.4 * smoothstep(-0.07, -0.12, y) * smoothstep(0.24, 0.15, z)  # chest ruff
    if y > 0.105 and abs(x) < 0.04 and z < 0.21:
        f = 1.55  # bushy tail
    if z < 0.035:
        f *= 0.4 + 0.6 * smoothstep(0.008, 0.035, z)  # neat paws
    return max(0.0, min(1.6, f))


def surf_front(body, x, z, tol=0.003):
    best = None
    for v in body.data.vertices:
        c = v.co
        if c.y < -0.15 and abs(c.x - x) < tol and abs(c.z - z) < tol:
            if best is None or c.y < best:
                best = c.y
    if best is None and tol < 0.012:
        return surf_front(body, x, z, tol * 2)
    return best if best is not None else -0.2


def simple_mat(name, color, rough=0.5):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:  # noqa: BLE001
        pass
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    return m


EYE_ROT = 0.12   # each eye turned outward (z), radians


def eye(side, c, r=EYE_R, flat=1.0):
    """flat < 1 squashes the ball along its view axis into a lens, so a big eye doesn't poke out the
    back or the side of the head"""
    me = bpy.data.meshes.new(f"eye_{side}")
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=16, radius=r)
    bm.to_mesh(me)
    bm.free()
    ob =bpy.data.objects.new(f"cat_eye_{'L' if side > 0 else 'R'}", me)
    bpy.context.scene.collection.objects.link(ob)
    for p in ob.data.polygons:
        p.use_smooth = True
    ob.location = c
    ob.rotation_euler = Euler((0.06, 0.0, side * -EYE_ROT), "XYZ")
    uvl = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li in range(poly.loop_start, poly.loop_start + poly.loop_total):
            co = me.vertices[me.loops[li].vertex_index].co.normalized()
            if flat != 1.0 and co.y >= 0:
                # a lens shows its back rim at the sides: paint it as the dark rim (eyeliner)
                xz = V((co.x, co.z))
                xz = xz.normalized() * 0.47 if xz.length > 1e-4 else V((0.47, 0.0))
                uvl.data[li].uv = (0.5 + xz.x, 0.5 + xz.y)
            else:
                uvl.data[li].uv = (0.5 + co.x * 0.5, 0.5 + co.z * 0.5) if co.y < 0 else (0.5 + co.x * 0.02, 0.5 + co.z * 0.02)
    if flat != 1.0:   # after the UVs, so the iris keeps its proportions on the lens
        for v in me.vertices:
            v.co.y *= flat
    ob.data.materials.append(simple_mat("cat_eye", (0.8, 0.65, 0.2), 0.05))
    return ob


def whiskers(body):
    objs = []
    for side in (-1, 1):
        for k in range(4):
            x, z = 0.011 * side, 0.262 - k * 0.0028
            root = V((x, surf_front(body, x, z) + 0.0025, z))
            d = V((side * 1.0, -0.15 + k * 0.08, 0.06 - k * 0.06)).normalized()
            pts = [root + d * (0.062 * t) + V((0, 0.012 * t * t, -0.01 * t * t)) for t in (0.0, 0.25, 0.5, 0.75, 1.0)]
            cu = bpy.data.curves.new("wh", "CURVE")
            cu.dimensions = "3D"
            cu.bevel_depth = 0.00026
            cu.bevel_resolution = 0
            sp = cu.splines.new("POLY")
            sp.points.add(len(pts) - 1)
            for i, p in enumerate(pts):
                sp.points[i].co = (p.x, p.y, p.z, 1)
            o = bpy.data.objects.new("wh", cu)
            bpy.context.scene.collection.objects.link(o)
            objs.append(o)
    bpy.context.view_layer.update()
    meshes = []
    for o in objs:
        me = bpy.data.meshes.new_from_object(o)
        mo = bpy.data.objects.new("whisker", me)
        bpy.context.scene.collection.objects.link(mo)
        meshes.append(mo)
        bpy.data.objects.remove(o, do_unlink=True)
    wh = lib.join(meshes, "cat_whiskers")
    wh.data.materials.append(simple_mat("cat_whisker", (0.95, 0.95, 0.92), 0.4))
    return wh


def armature():
    arm = bpy.data.armatures.new("cat_rig")
    ob = bpy.data.objects.new("cat_rig", arm)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    eb = {}
    for name, (h, t, parent) in BONES.items():
        b = arm.edit_bones.new(name)
        b.head = V(h)
        b.tail = V(t)
        b.roll = 0.0
        eb[name] = b
    for name, (h, t, parent) in BONES.items():
        if parent:
            eb[name].parent = eb[parent]
            eb[name].use_connect = (V(BONES[parent][1]) - V(h)).length < 1e-5
    bpy.ops.object.mode_set(mode="OBJECT")
    return ob


# side-view (y, z) lines bounding the neck on the stretched mesh: NECK_BASE runs from the chest ruff
# to the withers, HEAD_BASE from the throat to the back of the skull. Everything past HEAD_BASE is the
# head (eyes, whiskers, muzzle, cheeks, ear roots): rigid, weight 1.0; the bend blends only between them.
NECK_BASE = ((-0.200, 0.160), (-0.100, 0.262))
HEAD_BASE = ((-0.207, 0.203), (-0.143, 0.318))
HEAD_BONES = ("neck", "neck1", "head", "jaw", "ear.L", "ear.R")


def _side_dist(line, y, z):
    """signed distance in the side view, positive toward the head (forward / up)"""
    (y0, z0), (y1, z1) = line
    ny, nz = -(z1 - z0), (y1 - y0)   # left normal of the line seen from the side: points forward-up
    if ny > 0:
        ny, nz = -ny, -nz
    ln = math.hypot(ny, nz)
    return ((y - y0) * ny + (z - z0) * nz) / ln


def zone_weights(body):
    """replaces the heat weights of the neck and head by zones: legs, back and tail keep the automatic
    weights; along the neck the share blends chest -> neck -> neck1 -> head; the head is rigid, the jaw
    takes only the chin and the ears only above their root. Normalized, at most 4 influences."""
    vg = {g.name: g for g in body.vertex_groups}
    for n in HEAD_BONES:
        if n not in vg:
            vg[n] = body.vertex_groups.new(name=n)
    idx = {g.index: g.name for g in body.vertex_groups}
    knots = (("chest", 0.0), ("neck", 0.38), ("neck1", 0.72), ("head", 1.0))
    stats = {"head": 0, "neck": 0}
    for v in body.data.vertices:
        x, y, z = v.co
        auto = {idx[g.group]: g.weight for g in v.groups if g.weight > 1e-4}
        d0 = _side_dist(NECK_BASE, y, z)
        d1 = _side_dist(HEAD_BASE, y, z)
        if d0 <= 0:
            u = 0.0
        elif d1 >= 0:
            u = 1.0
        else:
            u = d0 / (d0 - d1)
        share = {}
        for (a, ua), (b, ub) in zip(knots, knots[1:]):
            if ua <= u <= ub:
                k = smoothstep(ua, ub, u)
                share[a] = share.get(a, 0.0) + 1.0 - k
                share[b] = share.get(b, 0.0) + k
                break
        out = {}
        # the body share keeps the automatic weights of the torso / legs (never the head chain)
        c = share.get("chest", 0.0)
        if c > 0:
            other = {n: w for n, w in auto.items() if n not in HEAD_BONES}
            tot = sum(other.values())
            if tot > 1e-4:
                for n, w in other.items():
                    out[n] = out.get(n, 0.0) + c * w / tot
            else:
                out["chest"] = out.get("chest", 0.0) + c
        for n in ("neck", "neck1"):
            if share.get(n, 0.0) > 0:
                out[n] = out.get(n, 0.0) + share[n]
        h = share.get("head", 0.0)
        if h > 0:
            # the chin follows the jaw: under the painted mouth, ahead of the throat, not the cheeks
            jw = smoothstep(0.247, 0.232, z) * smoothstep(-0.206, -0.224, y) * smoothstep(0.034, 0.02, abs(x))
            # ears from their root up (automatic weights there), the root itself stays on the head
            ear = 0.0
            for en in ("ear.L", "ear.R"):
                ew = auto.get(en, 0.0)
                if ew > 0 and abs(x) > 0.02:
                    sw = ew * smoothstep(0.322, 0.345, z)
                    if sw > 0:
                        out[en] = out.get(en, 0.0) + h * sw
                        ear += sw
            ear = min(ear, 1.0)
            jw *= 1.0 - ear
            if jw > 0:
                out["jaw"] = out.get("jaw", 0.0) + h * jw
            out["head"] = out.get("head", 0.0) + h * (1.0 - jw - ear)
        best = sorted(((w, n) for n, w in out.items() if w > 1e-3), reverse=True)[:4]
        tot = sum(w for w, _ in best)
        for gi in [g.group for g in v.groups]:
            body.vertex_groups[gi].remove([v.index])
        for w, n in best:
            vg[n].add([v.index], w / tot, "REPLACE")
        if u >= 1.0:
            stats["head"] += 1
        elif u > 0.0:
            stats["neck"] += 1
    print("zone weights: rigid head verts", stats["head"], "neck blend verts", stats["neck"])


def _nearest_on(poly, p):
    """nearest point on a polyline -> (point, distance, arc length from the first point)"""
    best = (poly[0], (p - poly[0]).length, 0.0)
    run = 0.0
    for a, b in zip(poly, poly[1:]):
        ab = b - a
        ln2 = ab.length_squared
        t = 0.0 if ln2 < 1e-12 else max(0.0, min(1.0, (p - a).dot(ab) / ln2))
        q = a + ab * t
        dd = (p - q).length
        if dd < best[1]:
            best = (q, dd, run + t * math.sqrt(ln2))
        run += math.sqrt(ln2)
    return best


def reshape(body, wh, rig, L):
    """--look: reshapes the weighted body, the whiskers and the rest skeleton together, in order:
    shorter / rounder torso, bigger head (rigid past HEAD_BASE, blended along the neck), thicker legs,
    shorter legs, fuller tail. Then builds the big flat eyes and pushes the skin in front of them back.
    Returns the eye objects."""
    global NOSE
    names = list(BONES)
    pts = [v.co.copy() for v in body.data.vertices]
    nb = len(pts)
    pts += [v.co.copy() for v in wh.data.vertices]
    nw = len(pts)
    for k in names:
        pts += [V(BONES[k][0]), V(BONES[k][1])]
    ne = len(pts)
    pts += [e.copy() for e in EYE_C] + [NOSE.copy()]
    orig = [p.copy() for p in pts]
    bi = {k: nw + 2 * i for i, k in enumerate(names)}   # bone head index (tail = +1)

    def bh(k):
        return pts[bi[k]]

    def bt(k):
        return pts[bi[k] + 1]

    # head weight (0 behind the neck base, 1 past HEAD_BASE), from the original side view
    hw = []
    for o in orig:
        d0, d1 = _side_dist(NECK_BASE, o.y, o.z), _side_dist(HEAD_BASE, o.y, o.z)
        hw.append(0.0 if d0 <= 0 else 1.0 if d1 >= 0 else smoothstep(0.0, 1.0, d0 / (d0 - d1)))
    # 1. torso: shorter along the back, rounder across
    a, b = TORSO
    d = (STRETCH - 1.0) * (b - a)
    za, zb = a - d / 2, b + d / 2
    k = L["torso"]
    half = (1 - k) * (zb - za) / 2
    for i, p in enumerate(pts):
        o = orig[i]
        wt = smoothstep(za - 0.04, za + 0.02, o.y) * smoothstep(zb + 0.04, zb - 0.02, o.y) * smoothstep(0.1, 0.14, o.z) * (1 - hw[i])
        g = 1 + (L["girth"] - 1) * wt
        p.x *= g
        p.z = 0.17 + (p.z - 0.17) * (1 + (g - 1) * 0.6)
        p.y = p.y + half if p.y <= za else p.y - half if p.y >= zb else za + half + (p.y - za) * k
    za, zb = za + half, zb - half
    # 2. head: scaled around a point under the head joint (chin level), a little wider than tall, so it
    # grows up and forward instead of dropping a double chin onto the chest
    piv = bh("head") + V((0, 0, -0.025))
    H, HX = L["head"], L["head"] * L["head_x"]
    for i, p in enumerate(pts):
        w = hw[i]
        if w > 0:
            dv = p - piv
            p.x, p.y, p.z = piv.x + dv.x * (1 + (HX - 1) * w), piv.y + dv.y * (1 + (H - 1) * w), piv.z + dv.z * (1 + (H - 1) * w)
    # 3. legs thicker around their bone chains (horizontal offsets only)
    chains = []
    for s in ("L", "R"):
        chains.append([bh(f"upperarm.{s}").copy(), bt(f"upperarm.{s}").copy(), bt(f"forearm.{s}").copy(), bt(f"fpaw.{s}").copy()])
        chains.append([bh(f"thigh.{s}").copy(), bt(f"thigh.{s}").copy(), bt(f"shin.{s}").copy(), bt(f"hock.{s}").copy(), bt(f"hpaw.{s}").copy()])
    if L["leg_w"] != 1.0:
        for i, p in enumerate(pts):
            wz = smoothstep(0.125, 0.095, orig[i].z)
            if wz <= 0 or hw[i] > 0:
                continue
            q, dd, _ = min((_nearest_on(c, p) for c in chains), key=lambda r: r[1])
            w = wz * smoothstep(0.048, 0.034, dd)
            s = 1 + (L["leg_w"] - 1) * w
            p.x, p.y = q.x + (p.x - q.x) * s, q.y + (p.y - q.y) * s
    # 4. legs shorter: everything under the belly line scales down, the rest drops with it
    lt = min((p.z for p in pts[:nb] if abs(p.x) < 0.012 and za < p.y < zb), default=0.12)
    if L["leg"] != 1.0:
        for p in pts:
            p.z = p.z * L["leg"] if p.z < lt else p.z - (1 - L["leg"]) * lt
    print("reshape: belly line", round(lt, 4))
    # 5. fuller tail, growing from its base
    tail = [bh(f"tail{i}").copy() for i in range(5)] + [bt("tail4").copy()]
    hind = [[bh(f"thigh.{s}").copy(), bt(f"thigh.{s}").copy(), bt(f"shin.{s}").copy(), bt(f"hock.{s}").copy(), bt(f"hpaw.{s}").copy()] for s in ("L", "R")]
    for i, p in enumerate(pts):
        if orig[i].y < orig[bi["tail0"]].y - 0.02:
            continue
        q, dt, arc = _nearest_on(tail, p)
        dl = min(_nearest_on(c, p)[1] for c in hind)
        if dt > 0.04 or dt > dl * 0.8:
            continue
        w = smoothstep(0.0, 0.03, arc) * smoothstep(0.04, 0.028, dt)
        p.x, p.y, p.z = (q + (p - q) * (1 + (L["tail"] - 1) * w))[:]
    # write back: body, whiskers, rest skeleton, landmarks
    for i, v in enumerate(body.data.vertices):
        v.co = pts[i]
    for i, v in enumerate(wh.data.vertices):
        v.co = pts[nb + i]
    for kk in names:
        BONES[kk] = (tuple(bh(kk)), tuple(bt(kk)), BONES[kk][2])
    lib.deselect_all()
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for kk in names:
        eb = rig.data.edit_bones[kk]
        eb.use_connect = False
    for kk in names:
        eb = rig.data.edit_bones[kk]
        eb.head, eb.tail = bh(kk), bt(kk)
        eb.roll = 0.0
    bpy.ops.object.mode_set(mode="OBJECT")
    for j in range(2):
        EYE_C[j] = pts[ne + j].copy()
    NOSE = pts[ne + 2].copy()
    if L.get("face_smooth"):
        # the generated head is lumpy (lip ridges, dents round the muzzle) and the toon ramp shows every
        # bump: relax the rigid head, ears excluded (plain averaging: the laplacian one threw a few
        # vertices to the floor)
        bm = bmesh.new()
        bm.from_mesh(body.data)
        bm.verts.ensure_lookup_table()
        # the ear roots are smoothed too (their jagged crease drew a zigzag outline), the ears are not
        sel = [bm.verts[i] for i in range(nb) if hw[i] >= 0.999 and not (orig[i].z > 0.338 and abs(orig[i].x) > 0.026)]
        for _ in range(L["face_smooth"]):
            bmesh.ops.smooth_vert(bm, verts=sel, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
        bm.to_mesh(body.data)
        bm.free()
        print("face smooth: verts", len(sel))
    # eyes: big lenses set into the face: the apex just out of the skin in front of it, so the rim of
    # the lens sinks under the curve of the head (no bug eyes); the skin over the lens is pushed behind it
    r = EYE_R * H * L["eye"]
    fl = L["eye_flat"]
    eyes = []
    for j, side in enumerate((1, -1)):
        c = EYE_C[j] + V((side * L["eye_x"], 0.0, L["eye_z"]))
        rot = Euler((0.06, 0.0, side * -EYE_ROT), "XYZ").to_matrix()
        inv = rot.inverted()
        fwd = rot @ V((0, -1, 0))
        front = [(inv @ (v.co - c)).y for v in body.data.vertices if math.hypot(*(inv @ (v.co - c)).xz) < r * 0.25 and (inv @ (v.co - c)).y < 0.01]
        skin = min(front) if front else -EYE_R * H
        c = c + fwd * (-skin + 0.12 * r * fl - r * fl)   # lens apex 12% of its depth out of the skin
        ob = eye(side, c, r, fl)
        eyes.append(ob)
        # set-in socket: under the lens the skin sinks just behind the lens rim and ramps back up to the
        # face over a third of a radius, so the visible edge is the clean circle of the lens, not the
        # triangles of the skin crossing it
        pushed = 0
        tgt = 0.15 * r * fl
        for v in body.data.vertices:
            q = inv @ (v.co - c)
            rad = math.hypot(q.x, q.z)
            if rad >= r * 1.35 or q.y > r * fl:
                continue
            w = 1.0 if rad <= r * 1.02 else smoothstep(1.35 * r, 1.02 * r, rad)
            ny = q.y + (tgt - q.y) * w
            if ny > q.y:
                q.y = ny
                v.co = c + rot @ q
                pushed += 1
        print("eye", side, "radius", round(r, 4), "skin pushed", pushed)
    if L.get("mouth"):
        eyes += mouth_lines(body, H)
    return eyes


def _ribbon(name, bvh, pts2d, width):
    """a thin strip lying on the face along front-projected (x, z) points, tapered at both ends"""
    hits = []
    for x, z in pts2d:
        loc, nrm, _i, _d = bvh.ray_cast(V((x, -1.0, z)), V((0, 1, 0)))
        if loc is not None:
            hits.append((loc, nrm))
    verts, faces = [], []
    n = len(hits)
    for i, (p, nr) in enumerate(hits):
        a, b = hits[max(i - 1, 0)][0], hits[min(i + 1, n - 1)][0]
        side = nr.cross((b - a).normalized()).normalized()
        w = width * (0.35 + 0.65 * math.sin(math.pi * i / (n - 1)) ** 0.5)
        base = p + nr * 0.0003
        verts += [base + side * w / 2, base - side * w / 2]
    for i in range(n - 1):
        faces.append((2 * i, 2 * i + 2, 2 * i + 3, 2 * i + 1))
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def mouth_lines(body, h):
    """painted-look mouth as separate thin meshes the game shows per style (cat_rig LOOK "mouth"):
    cat_mouthline_w (the 'ω' under the nose), cat_mouthline_ws (smaller, softer) and
    cat_mouthline_ph (the philtrum line from the nose down to the 'ω')"""
    from mathutils.bvhtree import BVHTree
    me = body.data
    bvh = BVHTree.FromPolygons([v.co.copy() for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
    top = NOSE.z - 0.0035 * h
    zm = NOSE.z - 0.0085 * h
    out = []

    def omega(half, depth, rise, steps=14):
        pts = []
        for i in range(-steps, steps + 1):
            t = abs(i) / steps
            pts.append((math.copysign(half * h * t, i), zm - depth * h * math.sin(math.pi * t) + rise * h * t * t))
        return pts

    out.append(_ribbon("cat_mouthline_w", bvh, omega(0.0075, 0.0022, 0.0016), 0.0009 * h))
    out.append(_ribbon("cat_mouthline_ws", bvh, omega(0.0055, 0.0014, 0.0010), 0.0007 * h))
    out.append(_ribbon("cat_mouthline_ph", bvh, [(0.0, top + (zm - top) * k / 6) for k in range(7)], 0.0008 * h))
    return out


def face_decals(body):
    """cat_eye_L/R: round decals with 0..1 UVs (the eye is drawn by cat_eye_anime.gdshader, so it
    still blinks and dilates); cat_decal_nose / cat_decal_mouth: painted textures (build_cat3)"""
    import build_cat3 as c3
    from mathutils.bvhtree import BVHTree
    me = body.data
    bvh = BVHTree.FromPolygons([v.co.copy() for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
    S = {"nose": (0.93, 0.55, 0.6), "mouth": "ws"}
    out = []
    for c, side in ((EYE_C[0], 1), (EYE_C[1], -1)):
        nrm = Euler((0.06, 0.0, side * -EYE_ROT), "XYZ").to_matrix() @ V((0, -1, 0))
        out.append(c3.decal(f"cat_eye_{'L' if side > 0 else 'R'}", bvh, c, nrm, DECAL_EYE_R * 2, DECAL_EYE_R * 2, None, lift=0.0006))
    out.append(c3.decal("cat_decal_nose", bvh, NOSE + V((0, 0, 0.001)), V((0, -1, 0.2)), 0.011, 0.0085, c3.nose_tex(S), lift=0.0008))
    out.append(c3.decal("cat_decal_mouth", bvh, NOSE + V((0, 0, -0.0072)), V((0, -1, 0.05)), 0.016, 0.011, c3.mouth_tex(S), lift=0.0007))
    for ob in out[2:]:
        img = next(n.image for n in ob.data.materials[0].node_tree.nodes if n.type == "TEX_IMAGE")
        ob.data.materials.clear()
        ob.data.materials.append(_decal_principled(ob.name, img))
    return out


def _decal_principled(name, img):
    """base colour and alpha from the painted image, so the glTF carries them (alpha mask)"""
    m = bpy.data.materials.new(name + "_mat")
    try:
        m.use_nodes = True
    except Exception:  # noqa: BLE001
        pass
    nt = m.node_tree
    b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], b.inputs["Base Color"])
    nt.links.new(tex.outputs["Alpha"], b.inputs["Alpha"])
    b.inputs["Roughness"].default_value = 1.0
    try:
        m.blend_method = "CLIP"
    except Exception:  # noqa: BLE001
        pass
    return m


def main():
    lib.reset_scene()
    bpy.ops.import_scene.gltf(filepath=SRC)
    body = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    body.name = "cat_body"
    body.parent = None
    lib.deselect_all()
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for p in body.data.polygons:
        p.use_smooth = True
    # weld the generated mesh so the automatic weights spread smoothly
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0004)
    bm.to_mesh(body.data)
    bm.free()
    # fur length mask as vertex colour (R)
    me = body.data
    ca = me.color_attributes.new("furlen", "FLOAT_COLOR", "POINT")
    for i, v in enumerate(me.vertices):
        fl = fur_length(v.co) / 1.6
        ca.data[i].color = (fl, fl, fl, 1.0)
    me.color_attributes.active_color = ca
    if STRETCH != 1.0:
        for v in me.vertices:
            v.co.y = stretch_y(v.co.y)
        stretch_all()
    eyes = [] if (LOOK or FACE_DECAL) else [eye(1, EYE_C[0]), eye(-1, EYE_C[1])]
    wh = whiskers(body)
    rig = armature()
    lib.deselect_all()
    body.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    groups = {g.index: g.name for g in body.vertex_groups}
    unweighted = sum(1 for v in body.data.vertices if not any(g.weight > 0.01 for g in v.groups))
    print("auto weights: groups", len(groups), "unweighted verts", unweighted)
    zone_weights(body)
    if LOOK:
        eyes = reshape(body, wh, rig, LOOK)
    if FACE_DECAL:
        eyes = face_decals(body)
    for ob in eyes + [wh]:
        vg = ob.vertex_groups.new(name="head")
        vg.add([v.index for v in ob.data.vertices], 1.0, "REPLACE")
        m = ob.modifiers.new("arm", "ARMATURE")
        m.object = rig
        ob.parent = rig
    if EXPORT:
        os.makedirs(OUT, exist_ok=True)
        lib.deselect_all()
        for o in (body, rig, wh, *eyes):
            o.select_set(True)
        bpy.ops.export_scene.gltf(filepath=OUT_FILE or os.path.join(OUT, "cat_mingau.glb"), export_format="GLB", use_selection=True, export_apply=False,
                                  export_yup=True, export_skins=True, export_animations=False, export_materials="EXPORT",
                                  export_vertex_color="ACTIVE", export_all_vertex_colors=False)
        print("EXPORTED cat v2")
    if PREVIEW:
        prev = lib.collection("_prev")
        scene = lib.setup_render((1280, 720), 32)
        scene.world.color = (0.08, 0.08, 0.09)
        key = bpy.data.objects.new("key", bpy.data.lights.new("key", "AREA"))
        key.data.energy = 30
        key.data.size = 0.6
        key.location = (0.5, -0.8, 0.8)
        key.rotation_euler = (0.9, 0, 0.5)
        prev.objects.link(key)
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        prev.objects.link(cam)
        scene.camera = cam
        cam.data.lens = 50
        for k, (loc, tgt) in enumerate((((0.55, -0.7, 0.35), (0, -0.02, 0.17)), ((0.0, -0.6, 0.3), (0, -0.15, 0.27)))):
            cam.location = loc
            cam.rotation_euler = (V(tgt) - V(loc)).to_track_quat("-Z", "Y").to_euler()
            scene.render.filepath = PREVIEW.replace(".png", f"_{k}.png")
            bpy.ops.render.render(write_still=True)


main()
