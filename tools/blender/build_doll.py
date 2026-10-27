"""A Boneca: an antique porcelain doll (~38 cm). Porcelain head with painted glass eyes, rosy
cheeks and a hairline crack, dark ringlets with a ribbon, a faded rose dress with lace collar,
puffed sleeves and a ruffled hem, stockings and buttoned shoes.

usage: blender -b -P tools/blender/build_doll.py -- [--preview out.png] [--no-export]
Blender coords: faces -Y, Z up (glTF export makes that game +Z forward). Origin at the feet.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Vector

sys.path.insert(0, os.path.dirname(__file__))
import lib  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIEW = argv[argv.index("--preview") + 1] if "--preview" in argv else None
EXPORT = "--no-export" not in argv
OUT = os.path.join(lib.GODOT, "assets", "models", "ghosts")
V = Vector
COLL = None


def mat(name, color, rough=0.5, metal=0.0, sss=0.0, coat=0.0):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:  # noqa: BLE001
        pass
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if coat > 0 and "Coat Weight" in b.inputs:
        b.inputs["Coat Weight"].default_value = coat
    return m


def obj(name, me):
    o = bpy.data.objects.new(name, me)
    COLL.objects.link(o)
    return o


def smooth(o, sub=0):
    for p in o.data.polygons:
        p.use_smooth = True
    if sub:
        m = o.modifiers.new("sub", "SUBSURF")
        m.levels = sub
        lib.apply_mods(o)
    return o


def sphere(name, c, r, sc=(1, 1, 1), m=None, seg=32, rings=20):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=r)
    for v in bm.verts:
        v.co = V((v.co.x * sc[0], v.co.y * sc[1], v.co.z * sc[2]))
    bm.to_mesh(me)
    bm.free()
    o = obj(name, me)
    o.location = V(c)
    if m:
        o.data.materials.append(m)
    return smooth(o)


def lathe(name, profile, m, seg=48, wave=None):
    """profile: [(r, z)] bottom->top; wave(theta, z) -> radius multiplier (ruffles)."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        ring = []
        for k in range(seg):
            a = 2 * math.pi * k / seg
            rr = r * (wave(a, z) if wave else 1.0)
            ring.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, z)))
        rings.append(ring)
    for j in range(len(rings) - 1):
        for k in range(seg):
            l = (k + 1) % seg
            bm.faces.new((rings[j][k], rings[j][l], rings[j + 1][l], rings[j + 1][k]))
    top = rings[-1]
    c = bm.verts.new((0, 0, profile[-1][1]))
    for k in range(seg):
        bm.faces.new((top[k], top[(k + 1) % seg], c))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = obj(name, me)
    o.data.materials.append(m)
    return smooth(o)


def tube(name, pts, r, m, seg=10, r_end=None):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    rings = []
    n = len(pts)
    for i, p in enumerate(pts):
        p = V(p)
        t = (V(pts[min(i + 1, n - 1)]) - V(pts[max(i - 1, 0)])).normalized()
        a = t.cross(V((0, 0, 1)))
        if a.length < 1e-4:
            a = t.cross(V((1, 0, 0)))
        a.normalize()
        b = t.cross(a).normalized()
        rr = r if r_end is None else r + (r_end - r) * i / (n - 1)
        rings.append([bm.verts.new(p + (a * math.cos(2 * math.pi * k / seg) + b * math.sin(2 * math.pi * k / seg)) * rr) for k in range(seg)])
    for j in range(n - 1):
        for k in range(seg):
            l = (k + 1) % seg
            bm.faces.new((rings[j][k], rings[j][l], rings[j + 1][l], rings[j + 1][k]))
    for ring, rev in ((rings[0], True), (rings[-1], False)):
        c = bm.verts.new(sum((v.co for v in ring), V()) / seg)
        for k in range(seg):
            f = (ring[(k + 1) % seg], ring[k], c) if rev else (ring[k], ring[(k + 1) % seg], c)
            bm.faces.new(f)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = obj(name, me)
    o.data.materials.append(m)
    return smooth(o)


def build():
    porcelain = mat("doll_porcelain", (0.86, 0.8, 0.76), 0.22, coat=0.6)
    blush = mat("doll_blush", (0.88, 0.55, 0.52), 0.25, coat=0.5)
    lips = mat("doll_lips", (0.62, 0.12, 0.14), 0.2, coat=0.6)
    white = mat("doll_eyewhite", (0.92, 0.9, 0.86), 0.08, coat=1.0)
    iris = mat("doll_iris", (0.12, 0.2, 0.32), 0.05, coat=1.0)
    pupil = mat("doll_pupil", (0.01, 0.01, 0.012), 0.05, coat=1.0)
    brow = mat("doll_brow", (0.18, 0.1, 0.06), 0.6)
    hair = mat("doll_hair", (0.16, 0.09, 0.05), 0.55)
    dress = mat("doll_dress", (0.36, 0.2, 0.21), 0.88)
    dress_dark = mat("doll_dress_dark", (0.22, 0.1, 0.12), 0.88)
    lace = mat("doll_lace", (0.74, 0.68, 0.56), 0.85)
    ribbon = mat("doll_ribbon", (0.42, 0.06, 0.08), 0.4)
    stocking = mat("doll_stocking", (0.88, 0.86, 0.8), 0.7)
    shoe = mat("doll_shoe", (0.03, 0.025, 0.025), 0.25, coat=0.8)
    crack = mat("doll_crack", (0.05, 0.04, 0.04), 0.7)
    parts = []
    H = 0.30  # neck height
    # ---- legs, stockings, shoes
    for s in (-1, 1):
        parts.append(tube(f"leg{s}", [(0.022 * s, 0.0, 0.03), (0.022 * s, 0.0, 0.1)], 0.011, stocking))
        sh = sphere(f"shoe{s}", (0.022 * s, -0.008, 0.016), 0.016, (0.85, 1.45, 0.75), shoe)
        parts.append(sh)
        parts.append(sphere(f"button{s}", (0.022 * s + 0.012 * s, -0.012, 0.022), 0.0025, (1, 1, 1), lace, 8, 6))
    # ---- skirt: bell with ruffled hem, petticoat lace under it
    wave = lambda a, z: 1.0 + (0.06 * math.sin(a * 18) if z < 0.07 else 0.0)  # noqa: E731
    parts.append(lathe("petticoat", [(0.078, 0.055), (0.07, 0.075), (0.05, 0.12)], lace, 64, lambda a, z: 1.0 + 0.08 * math.sin(a * 26)))
    parts.append(lathe("skirt", [(0.074, 0.068), (0.073, 0.08), (0.064, 0.12), (0.048, 0.17), (0.034, 0.2), (0.03, 0.21)], dress, 64, wave))
    parts.append(lathe("hem_band", [(0.0752, 0.085), (0.0744, 0.092)], dress_dark, 64))
    # ---- bodice
    parts.append(lathe("bodice", [(0.031, 0.2), (0.033, 0.23), (0.034, 0.26), (0.03, 0.285), (0.02, 0.297)], dress, 40))
    parts.append(lathe("sash", [(0.0335, 0.198), (0.034, 0.212)], ribbon, 40))
    bow = sphere("sash_bow", (0.0, 0.034, 0.205), 0.014, (1.6, 0.6, 0.9), ribbon)
    parts.append(bow)
    # lace collar
    parts.append(lathe("collar", [(0.042, 0.281), (0.032, 0.293), (0.018, 0.3)], lace, 48, lambda a, z: 1.0 + 0.07 * math.sin(a * 20)))
    # ---- arms: puff sleeves + porcelain forearms and hands
    for s in (-1, 1):
        parts.append(sphere(f"puff{s}", (0.04 * s, 0.0, 0.272), 0.017, (1, 1, 1.1), dress))
        parts.append(tube(f"arm{s}", [(0.046 * s, 0.0, 0.262), (0.052 * s, -0.004, 0.225), (0.05 * s, -0.012, 0.19)], 0.0075, porcelain, r_end=0.0062))
        parts.append(sphere(f"hand{s}", (0.049 * s, -0.014, 0.182), 0.009, (0.8, 0.6, 1.15), porcelain))
        parts.append(lathe(f"cuff{s}", [(0.0105, 0.0), (0.0095, 0.006)], lace, 16))
        parts[-1].location = V((0.0475 * s, 0.0, 0.252))
    # ---- head: a porcelain shoulder-head, full cheeks, small chin
    hc = V((0.0, 0.0, H + 0.047))
    R = V((0.046, 0.045, 0.049))

    def surf(x, z):
        """point on the face surface at (x, z) offsets from the head centre (front)."""
        yy = -R.y * math.sqrt(max(0.0, 1 - (x / R.x) ** 2 - (z / R.z) ** 2))
        return hc + V((x, yy, z))

    me = bpy.data.meshes.new("doll_head")
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=48, v_segments=36, radius=1.0)
    for v in bm.verts:
        x, y, z = v.co
        fwd = max(0.0, -y)
        p = V((x * R.x, y * R.y, z * R.z))
        if z < 0:
            p.x *= 1.0 - 0.12 * z * z     # narrower jaw
        cheek = math.exp(-(((abs(x) - 0.5) / 0.32) ** 2 + ((z + 0.3) / 0.3) ** 2)) * fwd
        p.y -= 0.003 * cheek
        sock = math.exp(-(((abs(x) - 0.38) / 0.16) ** 2 + ((z - 0.08) / 0.14) ** 2)) * fwd
        p.y += 0.0035 * sock
        v.co = p + hc
    bm.to_mesh(me)
    bm.free()
    head = obj("doll_head", me)
    head.data.materials.append(porcelain)
    smooth(head)
    parts.append(head)
    parts.append(tube("neck", [(0, 0, H - 0.006), (0, 0, H + 0.012)], 0.012, porcelain))
    # glass eyes set into the sockets, half covered by porcelain lids: they seem to watch
    for s in (-1, 1):
        ec = surf(0.017 * s, 0.006) + V((0, 0.0045, 0))
        parts.append(sphere(f"eye{s}", ec, 0.0078, (1, 1, 1), white, 20, 14))
        look = V((-0.0012 * s, 0, -0.0006))
        parts.append(sphere(f"iris{s}", ec + V((0, -0.0058, 0)) + look, 0.0052, (1, 0.35, 1), iris, 20, 10))
        parts.append(sphere(f"pupil{s}", ec + V((0, -0.0077, 0)) + look, 0.0024, (1, 0.3, 1), pupil, 12, 8))
        lid = sphere(f"lid{s}", ec, 0.0086, (1, 1, 1), porcelain, 24, 16)
        bm = bmesh.new()
        bm.from_mesh(lid.data)
        kill = [v for v in bm.verts if v.co.z < 0.0028]
        bmesh.ops.delete(bm, geom=kill, context="VERTS")
        bm.to_mesh(lid.data)
        bm.free()
        parts.append(lid)
        lash = [surf(x * s, 0.0105 - abs(x - 0.017) * 0.18) + V((0, -0.0012, 0)) for x in (0.009, 0.013, 0.017, 0.021, 0.025)]
        parts.append(tube(f"lash{s}", lash, 0.0006, pupil, 5))
        bw = [surf(x * s, 0.022 + 0.004 * math.sin((x - 0.008) / 0.02 * math.pi)) + V((0, 0.0004, 0)) for x in (0.008, 0.013, 0.018, 0.023, 0.028)]
        parts.append(tube(f"brow{s}", bw, 0.0006, brow, 5))
        bl = sphere(f"blush{s}", surf(0.024 * s, -0.013) + V((0, 0.0028, 0)), 0.0085, (1.0, 0.3, 0.7), blush, 16, 10)
        bl.rotation_euler = Euler((0, 0, -0.5 * s), "XYZ")
        parts.append(bl)
    for s in (-1, 1):
        parts.append(sphere(f"lip_top{s}", surf(0.0028 * s, -0.025) + V((0, 0.0012, 0)), 0.0034, (1.15, 0.5, 0.55), lips, 14, 8))
    parts.append(sphere("lip_bot", surf(0.0, -0.0295) + V((0, 0.0014, 0)), 0.0036, (1.25, 0.5, 0.55), lips, 14, 8))
    parts.append(sphere("nose", surf(0.0, -0.009) + V((0, 0.0016, 0)), 0.0028, (0.9, 0.9, 1.0), porcelain, 12, 8))
    # the crack: a fine jagged line from the hairline over the left eye, following the surface
    pts = []
    for i in range(14):
        t = i / 13
        x = -0.004 - t * 0.016 + (0.0012 if i % 2 else -0.0012)
        z = 0.038 - t * 0.03
        pts.append(surf(x, z) + V((0, 0.0002, 0)))
    parts.append(tube("crack", pts, 0.00035, crack, 4))
    # ---- hair: a shell grown from the skull (not over the face), ringlets and a ribbon bow
    me = bpy.data.meshes.new("doll_hair")
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=48, v_segments=32, radius=1.0)
    kill = []
    for v in bm.verts:
        x, y, z = v.co
        face = y < -0.2 and z < 0.55 - 0.25 * abs(x)
        if face or z < -0.55 + 0.4 * max(0.0, -y):
            kill.append(v)
        v.co = hc + V((x * (R.x + 0.004), y * (R.y + 0.004), z * (R.z + 0.0045)))
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bm.to_mesh(me)
    bm.free()
    cap = obj("doll_hair", me)
    cap.data.materials.append(hair)
    sol = cap.modifiers.new("sol", "SOLIDIFY")
    sol.thickness = 0.004
    sol.offset = -1.0
    lib.apply_mods(cap)
    smooth(cap, 1)
    parts.append(cap)
    for k in range(11):
        a = math.radians(-135 + k * 27)
        base = hc + V((math.sin(a) * (R.x + 0.002), math.cos(a) * (R.y + 0.002), -0.006))
        if base.y < -0.028:
            continue
        pts = []
        ln = 0.075 + 0.012 * (k % 3)
        for i in range(32):
            t = i / 31
            rr = 0.0055 * (1 - 0.3 * t)
            pts.append(base + V((math.cos(t * 20 + k) * rr + math.sin(a) * 0.008 * t, math.sin(t * 20 + k) * rr + math.cos(a) * 0.008 * t, -t * ln)))
        parts.append(tube(f"curl{k}", pts, 0.0038, hair, 8, r_end=0.0022))
    for s in (-1, 1):
        b = sphere(f"bow{s}", hc + V((0.017 * s, 0.022, 0.05)), 0.014, (1.4, 0.45, 0.85), ribbon)
        b.rotation_euler = Euler((0.5, 0.25 * s, 0.35 * s), "XYZ")
        parts.append(b)
    parts.append(sphere("bow_knot", hc + V((0, 0.024, 0.052)), 0.0055, (1, 1, 1), ribbon))
    return parts


def main():
    global COLL
    lib.reset_scene()
    COLL = bpy.context.scene.collection
    parts = build()
    doll = lib.join(parts, "doll")
    for p in doll.data.polygons:
        p.use_smooth = True
    if EXPORT:
        os.makedirs(OUT, exist_ok=True)
        lib.deselect_all()
        doll.select_set(True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "doll.glb"), export_format="GLB", use_selection=True, export_yup=True, export_materials="EXPORT")
        print("EXPORTED doll")
    if PREVIEW:
        prev = lib.collection("_prev")
        scene = lib.setup_render((900, 1200), 48)
        scene.world.color = (0.05, 0.05, 0.06)
        key = bpy.data.objects.new("key", bpy.data.lights.new("key", "AREA"))
        key.data.energy = 12
        key.data.size = 0.4
        key.location = (0.35, -0.5, 0.6)
        key.rotation_euler = (0.9, 0, 0.6)
        prev.objects.link(key)
        rim = bpy.data.objects.new("rim", bpy.data.lights.new("rim", "AREA"))
        rim.data.energy = 6
        rim.location = (-0.3, 0.4, 0.5)
        rim.rotation_euler = (-0.9, 0, -2.5)
        prev.objects.link(rim)
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        prev.objects.link(cam)
        scene.camera = cam
        cam.data.lens = 70
        for k, (loc, tgt) in enumerate((((0.25, -0.7, 0.3), (0, 0, 0.19)), ((0.08, -0.32, 0.37), (0, 0, 0.35)), ((-0.4, 0.45, 0.3), (0, 0, 0.19)))):
            cam.location = loc
            cam.rotation_euler = (V(tgt) - V(loc)).to_track_quat("-Z", "Y").to_euler()
            scene.render.filepath = PREVIEW.replace(".png", f"_{k}.png")
            bpy.ops.render.render(write_still=True)


main()
