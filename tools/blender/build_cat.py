"""Mingau, the cat: organic body from metaballs, remeshed to clean quads, separate ears/eyes/nose/
whiskers, a quadruped armature with automatic weights and a baked fur-pattern texture.

usage: blender -b -P tools/blender/build_cat.py -- [--preview out.png] [--variant mingau|breu] [--no-export]

Coordinates here are BLENDER (the cat faces -Y, Z up); glTF export turns that into game +Z forward.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import lib  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIEW = argv[argv.index("--preview") + 1] if "--preview" in argv else None
VARIANT = argv[argv.index("--variant") + 1] if "--variant" in argv else "mingau"
EXPORT = "--no-export" not in argv
OUT = os.path.join(lib.GODOT, "assets", "models", "cat")

V = Vector

# ---------------------------------------------------------------------- body shape
# skin-modifier skeleton: (point, (radius_x, radius_z)) chains. Blender coords: -Y forward, Z up.
SPINE = [
    ((0.0, 0.236, 0.178), (0.014, 0.016)),  # rounded end
    ((0.0, 0.222, 0.181), (0.04, 0.045)),
    ((0.0, 0.19, 0.185), (0.056, 0.062)),   # rump
    ((0.0, 0.135, 0.183), (0.075, 0.084)),  # hips
    ((0.0, 0.055, 0.18), (0.073, 0.084)),   # waist (a soft round belly)
    ((0.0, -0.03, 0.182), (0.078, 0.09)),   # ribs
    ((0.0, -0.105, 0.18), (0.071, 0.09)),   # chest
    ((0.0, -0.152, 0.192), (0.054, 0.072)), # breast
    ((0.0, -0.192, 0.228), (0.05, 0.053)),  # neck (hidden in the ruff)
    ((0.0, -0.228, 0.258), (0.046, 0.046)), # nape
]
FRONT_LEG = [((0.036, -0.115, 0.15), 0.036), ((0.034, -0.104, 0.092), 0.027), ((0.031, -0.112, 0.034), 0.0195), ((0.031, -0.124, 0.015), 0.021), ((0.031, -0.14, 0.013), 0.019)]
HIND_LEG = [((0.042, 0.125, 0.16), 0.05), ((0.044, 0.085, 0.1), 0.035), ((0.039, 0.15, 0.058), 0.021), ((0.036, 0.156, 0.025), 0.019), ((0.036, 0.142, 0.015), 0.021), ((0.036, 0.128, 0.013), 0.019)]
TAIL = []
for _i in range(11):
    _t = _i / 10
    TAIL.append(((0.0, 0.2 + 0.27 * _t, 0.195 + 0.03 * _t + 0.11 * _t * _t), 0.022 - 0.008 * _t))
HEAD_C = V((0.0, -0.27, 0.29))
HEAD_R = V((0.0505, 0.049, 0.047))


def catmull(pts, n):
    """sample a Catmull-Rom spline through pts (Vectors) with n samples per segment."""
    out = []
    P = [pts[0] + (pts[0] - pts[1])] + list(pts) + [pts[-1] + (pts[-1] - pts[-2])]
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(pts[-1])
    return out


def loft_torso():
    """smooth elliptical tube along the spine (rump -> nape), capped."""
    cs = [V(c) for c, r in SPINE]
    rs = [V((r[0], r[1], 0)) for c, r in SPINE]
    samples = catmull(cs, 8)
    radii = catmull(rs, 8)
    ring_n = 40
    bm = bmesh.new()
    rings = []
    for i, c in enumerate(samples):
        nxt = samples[min(i + 1, len(samples) - 1)]
        prv = samples[max(i - 1, 0)]
        t = (nxt - prv).normalized()
        side = V((1, 0, 0))
        up = t.cross(side).normalized() * -1
        if up.z < 0:
            up = -up
        rx, rz = radii[i].x, radii[i].y
        ring = []
        for k in range(ring_n):
            a = 2 * math.pi * k / ring_n
            # belly slightly flatter than the back
            zz = math.sin(a)
            rzz = rz * (1.0 if zz > 0 else 0.92)
            ring.append(bm.verts.new(c + side * math.cos(a) * rx + up * zz * rzz))
        rings.append(ring)
    for j in range(len(rings) - 1):
        for k in range(ring_n):
            l = (k + 1) % ring_n
            bm.faces.new((rings[j][k], rings[j][l], rings[j + 1][l], rings[j + 1][k]))
    for ring, rev in ((rings[0], True), (rings[-1], False)):
        c = bm.verts.new(sum((v.co for v in ring), V()) / len(ring))
        for k in range(ring_n):
            l = (k + 1) % ring_n
            f = (ring[l], ring[k], c) if rev else (ring[k], ring[l], c)
            bm.faces.new(f)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("cat_torso")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("cat_torso", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def skin_chain(name, pts):
    bm = bmesh.new()
    sk = bm.verts.layers.skin.verify()
    prev = None
    first = None
    for p, r in pts:
        v = bm.verts.new(V(p))
        v[sk].radius = (r, r) if not isinstance(r, tuple) else r
        if prev is not None:
            bm.edges.new((prev, v))
        else:
            first = v
        prev = v
    first[sk].use_root = True
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    m = ob.modifiers.new("skin", "SKIN")
    m.branch_smoothing = 1.0
    sub = ob.modifiers.new("sub", "SUBSURF")
    sub.levels = 2
    lib.apply_mods(ob)
    return ob


def skin_body():
    parts = [loft_torso()]
    for side in (-1, 1):
        f = [((p[0] * side, p[1], p[2]), r) for p, r in FRONT_LEG]
        # start inside the chest so the leg fuses into the body
        parts.append(skin_chain(f"leg_f{side}", [((0.026 * side, -0.11, 0.18), 0.036)] + f))
        h = [((p[0] * side, p[1], p[2]), r) for p, r in HIND_LEG]
        parts.append(skin_chain(f"leg_h{side}", [((0.03, 0.13, 0.18) if side > 0 else (-0.03, 0.13, 0.18), 0.05)] + h))
    parts.append(skin_chain("tail", [((0.0, 0.17, 0.185), 0.03)] + TAIL))
    # a full throat and chest ruff: the chin rests on fluff instead of a thin neck
    me = bpy.data.meshes.new("ruff")
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=20, radius=1.0)
    for v in bm.verts:
        v.co = V((v.co.x * 0.044, v.co.y * 0.048, v.co.z * 0.04)) + V((0.0, -0.236, 0.242))
    bm.to_mesh(me)
    bm.free()
    ruff = bpy.data.objects.new("ruff", me)
    bpy.context.scene.collection.objects.link(ruff)
    parts.append(ruff)
    return lib.join(parts, "cat_body")


def sculpt_head():
    """a cat head from a dense sphere: round skull, full cheeks, short muzzle, chin, eye sockets."""
    me = bpy.data.meshes.new("cat_head")
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=64, v_segments=48, radius=1.0)
    for v in bm.verts:
        x, y, z = v.co
        fwd = max(0.0, -y)
        side = abs(x)
        p = V((x * HEAD_R.x, y * HEAD_R.y, z * HEAD_R.z))
        if z > 0:
            p.z *= 0.97
        ch = math.exp(-((z + 0.08) / 0.35) ** 2) * math.exp(-((y + 0.3) / 0.55) ** 2) * side
        p.x += math.copysign(0.007 * ch, x)
        # round whisker pads either side of the nose: the soft "M" of a cat's muzzle
        pad = math.exp(-(((side - 0.17) / 0.16) ** 2 + ((z + 0.4) / 0.16) ** 2)) * fwd ** 3
        p.y -= 0.008 * pad
        p.z -= 0.002 * pad
        mz = math.exp(-((z + 0.32) / 0.32) ** 2) * fwd ** 3 * math.exp(-(x / 0.45) ** 2)
        p.y -= 0.019 * mz
        p.z -= 0.004 * mz
        p.x *= 1.0 - 0.14 * mz
        cn = math.exp(-((z + 0.75) / 0.25) ** 2) * fwd ** 2 * math.exp(-(x / 0.35) ** 2)
        p.y -= 0.01 * cn
        brow = math.exp(-((z - 0.2) / 0.2) ** 2) * fwd ** 2
        p.y -= 0.004 * brow
        sock = math.exp(-(((side - 0.45) / 0.18) ** 2 + ((z - 0.1) / 0.17) ** 2)) * fwd ** 2
        p.y += 0.007 * sock
        br = math.exp(-((z + 0.02) / 0.12) ** 2) * math.exp(-(x / 0.2) ** 2) * fwd ** 4
        p.y += 0.003 * br
        v.co = p + HEAD_C
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("cat_head", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def remesh(ob, faces=14000):
    ctx = bpy.context
    lib.deselect_all()
    ctx.view_layer.objects.active = ob
    ob.select_set(True)
    m = ob.modifiers.new("vox", "REMESH")
    m.mode = "VOXEL"
    m.voxel_size = 0.0028
    m.use_smooth_shade = True
    lib.apply_mods(ob)
    ls = ob.modifiers.new("lap", "LAPLACIANSMOOTH")
    ls.lambda_factor = 0.9
    ls.iterations = 12
    ls.use_volume_preserve = True
    lib.apply_mods(ob)
    d = ob.modifiers.new("dec", "DECIMATE")
    d.ratio = faces / max(1, len(ob.data.polygons))
    lib.apply_mods(ob)
    print("decimated to", len(ob.data.polygons))
    sm = ob.modifiers.new("smooth", "SMOOTH")
    sm.factor = 0.5
    sm.iterations = 4
    lib.apply_mods(ob)
    for p in ob.data.polygons:
        p.use_smooth = True


# ---------------------------------------------------------------------- features


def ear(side):
    """a slightly cupped triangular ear with thickness; returns object with origin at the ear base."""
    bm = bmesh.new()
    base_w = 0.037
    height = 0.036
    cup = 0.008
    rows = 6
    cols = 6
    verts = []
    for j in range(rows + 1):
        t = j / rows
        w = base_w * (1 - t ** 1.6) ** 0.9 * (1 - 0.15 * t)
        row = []
        for i in range(cols + 1):
            u = i / cols - 0.5
            x = u * w
            y = -cup * (1 - (2 * u) ** 2) * (1 - t)  # cupped toward the front (-y)
            z = t * height
            row.append(bm.verts.new((x, y, z)))
        verts.append(row)
    for j in range(rows):
        for i in range(cols):
            bm.faces.new((verts[j][i], verts[j][i + 1], verts[j + 1][i + 1], verts[j + 1][i]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    me = bpy.data.meshes.new(f"ear_{side}")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(f"cat_ear_{'L' if side > 0 else 'R'}", me)
    bpy.context.scene.collection.objects.link(ob)
    sol = ob.modifiers.new("sol", "SOLIDIFY")
    sol.thickness = 0.004
    sol.offset = 1.0
    sub = ob.modifiers.new("sub", "SUBSURF")
    sub.levels = 1
    lib.apply_mods(ob)
    for p in ob.data.polygons:
        p.use_smooth = True
    # place on the head: tilted out and slightly back
    ob.location = V((0.03 * side, -0.262, 0.322))
    ob.rotation_euler = Euler((-0.2, side * 0.42, side * 0.38), "XYZ")
    return ob


def eye(side):
    me = bpy.data.meshes.new(f"eye_{side}")
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=16, radius=0.0132)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(f"cat_eye_{'L' if side > 0 else 'R'}", me)
    bpy.context.scene.collection.objects.link(ob)
    for p in ob.data.polygons:
        p.use_smooth = True
    ob.location = FEAT["eye_l" if side > 0 else "eye_r"]
    # the sphere's -Y pole looks forward and a little outward
    ob.rotation_euler = Euler((0.0, 0.0, side * -0.14), "XYZ")
    # uv: spherical around the forward axis so the iris sits at the front pole
    uvl = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li in range(poly.loop_start, poly.loop_start + poly.loop_total):
            co = me.vertices[me.loops[li].vertex_index].co.normalized()
            uvl.data[li].uv = (0.5 + co.x * 0.5, 0.5 + co.z * 0.5) if co.y < 0 else (0.5 + co.x * 0.02, 0.5 + co.z * 0.02)
    return ob


def nose():
    bm = bmesh.new()
    pts = [V((0.0, -0.0, -0.006)), V((0.0075, 0.0, 0.003)), V((-0.0075, 0.0, 0.003))]
    a = [bm.verts.new(p) for p in pts]
    b = [bm.verts.new(p + V((0, 0.006, 0.002))) for p in pts]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    for i in range(3):
        j = (i + 1) % 3
        bm.faces.new((a[j], a[i], b[i], b[j]))
    me = bpy.data.meshes.new("nose")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("cat_nose", me)
    bpy.context.scene.collection.objects.link(ob)
    sub = ob.modifiers.new("sub", "SUBSURF")
    sub.levels = 2
    lib.apply_mods(ob)
    for p in ob.data.polygons:
        p.use_smooth = True
    ob.location = FEAT["nose"]
    ob.scale = V((1.3, 1.3, 1.25))
    ob.rotation_euler = Euler((0.35, 0, 0), "XYZ")
    return ob


def whiskers():
    objs = []
    for side in (-1, 1):
        for k in range(4):
            root = FEAT["whisker"][(side, k)]
            d = V((side * 1.0, -0.25 + k * 0.08, 0.05 - k * 0.06)).normalized()
            pts = [root + d * (0.07 * t) + V((0, 0.012 * t * t, -0.012 * t * t)) for t in (0.0, 0.25, 0.5, 0.75, 1.0)]
            cu = bpy.data.curves.new("wh", "CURVE")
            cu.dimensions = "3D"
            cu.bevel_depth = 0.00028
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
    return lib.join(meshes, "cat_whiskers")


def mouth_interior():
    me = bpy.data.meshes.new("mouth")
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=0.012)
    for v in bm.verts:
        v.co.y *= 1.4
        v.co.z *= 0.6
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("cat_mouth", me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = V((0.0, -0.295, 0.262))
    return ob


# ---------------------------------------------------------------------- armature

BONES = {
    # name: (head, tail, parent)
    "root": ((0, 0, 0), (0, 0.06, 0), None),
    "hips": ((0, 0.135, 0.183), (0, 0.055, 0.18), "root"),
    "spine": ((0, 0.055, 0.18), (0, -0.03, 0.182), "hips"),
    "chest": ((0, -0.03, 0.182), (0, -0.15, 0.19), "spine"),
    "neck": ((0, -0.15, 0.198), (0, -0.24, 0.265), "chest"),
    "head": ((0, -0.24, 0.265), (0, -0.33, 0.28), "neck"),
    "jaw": ((0, -0.27, 0.258), (0, -0.318, 0.254), "head"),
    "ear.L": ((0.03, -0.262, 0.322), (0.038, -0.268, 0.355), "head"),
    "ear.R": ((-0.03, -0.262, 0.322), (-0.038, -0.268, 0.355), "head"),
}
for i in range(5):
    BONES[f"tail{i}"] = (TAIL[i * 2][0], TAIL[i * 2 + 2][0], "hips" if i == 0 else f"tail{i - 1}")
for side, s in (("L", 1), ("R", -1)):
    f = [(p[0] * s, p[1], p[2]) for p, r in FRONT_LEG]
    BONES[f"shoulder.{side}"] = ((0.02 * s, -0.085, 0.205), f[0], "chest")
    BONES[f"upperarm.{side}"] = (f[0], f[1], f"shoulder.{side}")
    BONES[f"forearm.{side}"] = (f[1], f[3], f"upperarm.{side}")
    BONES[f"fpaw.{side}"] = (f[3], (f[4][0], f[4][1] - 0.012, f[4][2]), f"forearm.{side}")
    h = [(p[0] * s, p[1], p[2]) for p, r in HIND_LEG]
    BONES[f"thigh.{side}"] = (h[0], h[1], "hips")
    BONES[f"shin.{side}"] = (h[1], h[2], f"thigh.{side}")
    BONES[f"hock.{side}"] = (h[2], h[3], f"shin.{side}")
    BONES[f"hpaw.{side}"] = (h[3], (h[5][0], h[5][1] - 0.01, h[5][2]), f"hock.{side}")


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


def skin(body, rig, rigid):
    ctx = bpy.context
    lib.deselect_all()
    body.select_set(True)
    rig.select_set(True)
    ctx.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    print("auto weights groups", len(body.vertex_groups))
    # rigid parts follow one bone
    for ob, bone in rigid:
        lib.deselect_all()
        vg = ob.vertex_groups.new(name=bone)
        vg.add([v.index for v in ob.data.vertices], 1.0, "REPLACE")
        m = ob.modifiers.new("arm", "ARMATURE")
        m.object = rig
        ob.parent = rig


# ---------------------------------------------------------------------- fur pattern bake


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def fur_color(p):
    """bicolour ginger & cream: ginger back, tail and crown, white blaze, muzzle, chest, belly and socks."""
    from mathutils import noise as mn
    x, y, z = p
    n1 = mn.noise(V((x, y, z)) * 28.0)
    n2 = mn.noise(V((x, y, z)) * 70.0 + V((3, 1, 2)))
    ax = abs(x)
    m = 0.0
    if y > -0.205:  # body + tail
        line = 0.205 - 0.012 * smoothstep(-0.1, 0.18, y) + 0.018 * n1  # the boundary dips toward the rump
        m = smoothstep(line - 0.008, line + 0.008, z)
        if y > 0.2:
            m = max(m, smoothstep(0.205, 0.22, y))  # tail ginger
        if y > 0.44:
            m *= 1.0 - smoothstep(0.445, 0.46, y)  # white tail tip
        # a ginger saddle patch on the flank
        flank = smoothstep(0.2, 0.45, n1 * 0.8 + 0.5 - abs(y - 0.02) * 4)
        m = max(m, flank * smoothstep(0.14, 0.17, z))
    else:  # head and neck
        crown = smoothstep(0.272, 0.29, z + 0.01 * n1)
        cheeks = smoothstep(0.016, 0.03, ax) * smoothstep(0.262, 0.278, z)
        m = max(crown, cheeks * smoothstep(-0.31, -0.25, y) * 1.0)
        m = max(m, smoothstep(0.235, 0.26, z) * smoothstep(-0.24, -0.215, y))  # nape
        blaze_w = 0.004 + 0.035 * smoothstep(0.31, 0.26, z)
        blaze = 1.0 - smoothstep(blaze_w - 0.003, blaze_w + 0.003, ax)
        m *= 1.0 - blaze * smoothstep(-0.27, -0.31, y)
        m *= 1.0 - smoothstep(0.275, 0.262, z) * smoothstep(-0.3, -0.32, y)  # muzzle & chin white
    m = max(0.0, min(1.0, m))
    white = V((0.93, 0.89, 0.81))
    ginger = V((0.82, 0.47, 0.19))
    # tabby bands on the ginger: around the body / tail, swirls on the head
    band_coord = y * 62.0 + 2.2 * n1 if y > -0.2 else (z * 90.0 + x * 20 + 2.0 * n1)
    stripe = 0.5 + 0.5 * math.sin(band_coord)
    ginger = ginger * (1.0 - 0.32 * smoothstep(0.55, 0.9, stripe))
    col = white.lerp(ginger, m)
    col = col * (0.93 + 0.1 * n2)
    if VARIANT == "breu":
        col = V((0.022, 0.02, 0.02)) * (0.9 + 0.2 * n2)
    return col


EYES = [V((0.0215, -0.302, 0.2925)), V((-0.0215, -0.302, 0.2925))]


def fur_length(p):
    """relative fur length: short and velvety on the face, soft cheek fluff, a fluffy chest ruff
    and a bushy tail, neat paws."""
    x, y, z = p
    q = V(p)
    f = 1.0
    if y < -0.24:  # face
        f = 0.6 - 0.32 * smoothstep(-0.28, -0.315, y)
        f += 0.25 * smoothstep(0.305, 0.325, z)  # crown keeps some length
        for e in EYES:
            d = (q - e).length
            f *= smoothstep(0.0125, 0.022, d) * 0.92 + 0.08
        f *= 0.55 + 0.45 * smoothstep(-0.328, -0.312, y)  # muzzle tip
        if FEAT:
            dnose = (q - FEAT["nose"]).length
            dm = min((q - pp).length for pp in FEAT["philtrum"] + FEAT["mouth"][-1] + FEAT["mouth"][1])
            f *= smoothstep(0.0025, 0.0065, dnose)            # bare nose leather
            f *= 0.45 + 0.55 * smoothstep(0.002, 0.01, dm)    # short velvet around the lips
        f = max(f, 1.05 * smoothstep(0.024, 0.046, abs(x)) * smoothstep(-0.295, -0.262, y) * (1 - smoothstep(0.3, 0.315, z)))  # cheek fluff
    elif y < -0.13:
        f = 1.0 + 0.55 * smoothstep(0.25, 0.16, z)  # chest ruff
    if y > 0.2:
        f = 1.6  # bushy tail
    if z < 0.03:
        f *= 0.45 + 0.55 * smoothstep(0.012, 0.03, z)  # neat paws
    return max(0.0, min(1.6, f))


def fur_material(body):
    me = body.data
    attr = me.color_attributes.new("fur", "FLOAT_COLOR", "POINT")
    lattr = me.color_attributes.new("furlen", "FLOAT_COLOR", "POINT")
    for i, v in enumerate(me.vertices):
        c = fur_color(v.co)
        attr.data[i].color = (c.x, c.y, c.z, 1.0)
        fl = fur_length(v.co) / 1.6
        lattr.data[i].color = (fl, fl, fl, 1.0)
    mat = bpy.data.materials.new("cat_fur")
    try:
        mat.use_nodes = True
    except Exception:  # noqa: BLE001
        pass
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    at = nt.nodes.new("ShaderNodeAttribute")
    at.attribute_name = "fur"
    fine = nt.nodes.new("ShaderNodeTexNoise")
    fine.inputs["Scale"].default_value = 420.0
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nt.links.new(tc.outputs["Object"], fine.inputs["Vector"])
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["To Min"].default_value = 0.88
    mr.inputs["To Max"].default_value = 1.06
    nt.links.new(fine.outputs["Fac"], mr.inputs["Value"])
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs[0].default_value = 1.0
    nt.links.new(at.outputs["Color"], mul.inputs[6])
    nt.links.new(mr.outputs["Result"], mul.inputs[7])
    nt.links.new(mul.outputs[2], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85
    me.materials.clear()
    me.materials.append(mat)
    return mat


def bake_color(body, mat, size=2048):
    ctx = bpy.context
    lib.deselect_all()
    ctx.view_layer.objects.active = body
    body.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")
    img = bpy.data.images.new(f"cat_{VARIANT}_albedo", size, size)
    nt = mat.node_tree
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.nodes.active = tex
    scene = ctx.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 4
    try:
        scene.cycles.device = "GPU"
    except Exception:  # noqa: BLE001
        pass
    scene.render.bake.use_pass_direct = False
    scene.render.bake.use_pass_indirect = False
    scene.render.bake.margin = 8
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
    path = os.path.join(OUT, f"cat_{VARIANT}_albedo.png")
    os.makedirs(OUT, exist_ok=True)
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    # fur length mask: bake the furlen attribute through the same material
    attr_node = next(n for n in nt.nodes if n.type == "ATTRIBUTE")
    mul = next(n for n in nt.nodes if n.type == "MIX")
    attr_node.attribute_name = "furlen"
    bsdf0 = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    nt.links.new(attr_node.outputs["Color"], bsdf0.inputs["Base Color"])
    mimg = bpy.data.images.new(f"cat_{VARIANT}_furmask", 1024, 1024)
    mimg.colorspace_settings.name = "Non-Color"
    tex.image = mimg
    nt.nodes.active = tex
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
    mimg.filepath_raw = os.path.join(OUT, f"cat_{VARIANT}_furmask.png")
    mimg.file_format = "PNG"
    mimg.save()
    tex.image = img
    # rebuild the material as a simple image material for export
    for n in list(nt.nodes):
        if n.type not in ("BSDF_PRINCIPLED", "OUTPUT_MATERIAL", "TEX_IMAGE"):
            nt.nodes.remove(n)
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return path


def simple_mat(name, color, rough=0.5, emit=None):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:  # noqa: BLE001
        pass
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    return m


FEAT = {}
NOSE_Z = 0.2785


def surf_front(body, x, z, tol=0.003):
    """y of the frontmost body vertex near (x, z): where the face surface really is."""
    best = None
    for v in body.data.vertices:
        c = v.co
        if c.y < -0.22 and abs(c.x - x) < tol and abs(c.z - z) < tol:
            if best is None or c.y < best:
                best = c.y
    if best is None and tol < 0.01:
        return surf_front(body, x, z, tol * 2)
    return best if best is not None else -0.32


def snap_features(body):
    """eyes, nose, whiskers and the mouth sit on the actual (remeshed) face, not inside it."""
    for side, key in ((1, "eye_l"), (-1, "eye_r")):
        x, z = 0.0215 * side, 0.2925
        FEAT[key] = V((x, surf_front(body, x, z) + 0.0132 * 0.52, z))
    yn = surf_front(body, 0.0, NOSE_Z)
    FEAT["nose"] = V((0.0, yn - 0.0005, NOSE_Z))
    FEAT["whisker"] = {}
    for side in (-1, 1):
        for k in range(4):
            x, z = 0.012 * side, 0.27 - k * 0.003
            FEAT["whisker"][(side, k)] = V((x, surf_front(body, x, z) + 0.002, z))
    # the little "Y" of the mouth under the nose
    pts_c = []
    for t in (0.0, 0.5, 1.0):
        z = NOSE_Z - 0.006 - 0.006 * t
        pts_c.append(V((0.0, surf_front(body, 0.0, z) - 0.0013, z)))
    FEAT["philtrum"] = pts_c
    FEAT["mouth"] = {}
    for side in (-1, 1):
        pts = []
        for t in (0.0, 0.35, 0.7, 1.0):
            x = 0.0075 * t * side
            z = NOSE_Z - 0.012 - 0.0025 * math.sin(t * math.pi) + 0.001 * t
            pts.append(V((x, surf_front(body, x, z) - 0.0013, z)))
        FEAT["mouth"][side] = pts


def mouth_line():
    objs = []
    for pts in [FEAT["philtrum"], FEAT["mouth"][-1], FEAT["mouth"][1]]:
        cu = bpy.data.curves.new("ml", "CURVE")
        cu.dimensions = "3D"
        cu.bevel_depth = 0.00065
        cu.bevel_resolution = 1
        sp = cu.splines.new("POLY")
        sp.points.add(len(pts) - 1)
        for i, p in enumerate(pts):
            sp.points[i].co = (p.x, p.y, p.z, 1)
        o = bpy.data.objects.new("ml", cu)
        bpy.context.scene.collection.objects.link(o)
        objs.append(o)
    bpy.context.view_layer.update()
    meshes = []
    for o in objs:
        me = bpy.data.meshes.new_from_object(o)
        mo = bpy.data.objects.new("cat_mouthline", me)
        bpy.context.scene.collection.objects.link(mo)
        meshes.append(mo)
        bpy.data.objects.remove(o, do_unlink=True)
    return lib.join(meshes, "cat_mouthline")


def main():
    lib.reset_scene()
    body = skin_body()
    head = sculpt_head()
    body = lib.join([body, head], "cat_body")
    remesh(body, 9000)
    snap_features(body)
    ears = [ear(1), ear(-1)]
    eyes = [eye(1), eye(-1)]
    nz = nose()
    wh = whiskers()
    mouth = mouth_interior()
    mline = mouth_line()
    mat = fur_material(body)
    if EXPORT or PREVIEW:
        bake_color(body, mat)
    ear_col = (0.78, 0.42, 0.16) if VARIANT == "mingau" else (0.03, 0.026, 0.024)
    for e in ears:
        m_out = simple_mat("cat_ear", ear_col, 0.85)
        m_in = simple_mat("cat_ear_inner", (0.86, 0.6, 0.58), 0.6)
        e.data.materials.append(m_out)
        e.data.materials.append(m_in)
        for p in e.data.polygons:
            p.material_index = 1 if p.normal.y < 0 else 0
    for e in eyes:
        e.data.materials.append(simple_mat("cat_eye", (0.75, 0.62, 0.2), 0.05))
    nz.data.materials.append(simple_mat("cat_nose", (0.82, 0.52, 0.52) if VARIANT == "mingau" else (0.08, 0.06, 0.06), 0.35))
    wh.data.materials.append(simple_mat("cat_whisker", (0.95, 0.95, 0.92), 0.4))
    mouth.data.materials.append(simple_mat("cat_mouth", (0.35, 0.08, 0.1), 0.4))
    mline.data.materials.append(simple_mat("cat_mouthline", (0.2, 0.09, 0.08) if VARIANT == "mingau" else (0.01, 0.01, 0.01), 0.6))
    rig = armature()
    rigid = [(ears[0], "ear.L"), (ears[1], "ear.R"), (eyes[0], "head"), (eyes[1], "head"), (nz, "head"), (wh, "head"), (mouth, "jaw"), (mline, "head")]
    skin(body, rig, rigid)
    body.name = "cat_body"
    if EXPORT:
        ctx = bpy.context
        lib.deselect_all()
        for o in bpy.data.objects:
            if o.name.startswith("cat_"):
                o.select_set(True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, f"cat_{VARIANT}.glb"), export_format="GLB", use_selection=True, export_apply=False,
                                  export_yup=True, export_skins=True, export_animations=False, export_materials="EXPORT")
        print("EXPORTED cat")
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
        fill = bpy.data.objects.new("fill", bpy.data.lights.new("fill", "AREA"))
        fill.data.energy = 8
        fill.data.size = 1
        fill.location = (-0.8, -0.3, 0.4)
        fill.rotation_euler = (1.2, 0, -1.0)
        prev.objects.link(fill)
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        prev.objects.link(cam)
        scene.camera = cam
        cam.data.lens = 50
        for k, (loc, tgt) in enumerate((((0.55, -0.7, 0.35), (0, -0.02, 0.17)), ((0.0, -0.75, 0.32), (0, -0.2, 0.26)), ((-0.8, 0.0, 0.25), (0, 0.0, 0.17)))):
            cam.location = loc
            cam.rotation_euler = (V(tgt) - V(loc)).to_track_quat("-Z", "Y").to_euler()
            scene.render.filepath = PREVIEW.replace(".png", f"_{k}.png")
            bpy.ops.render.render(write_still=True)
        bpy.ops.wm.save_as_mainfile(filepath=PREVIEW.replace(".png", ".blend"))


main()
