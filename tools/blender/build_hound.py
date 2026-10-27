"""O Cão Fantasma: a gaunt spectral hound. Lofted deep-chested torso with ribs showing, long skin-
modifier legs, a wolfish head with a snarling jaw and fangs, tall pointed ears, a thin whip tail.
Voxel-remeshed into one clean skin, rigged with a quadruped armature for procedural animation in
Godot (the spectral look is a shader there).

usage: blender -b -P tools/blender/build_hound.py -- [--preview out.png] [--no-export]

Blender coords: the hound faces -Y, Z up; glTF export turns that into game +Z forward.
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

SPINE = [
    ((0.0, 0.5, 0.71), (0.02, 0.02)),
    ((0.0, 0.47, 0.715), (0.075, 0.075)),
    ((0.0, 0.40, 0.71), (0.1, 0.1)),      # rump
    ((0.0, 0.28, 0.715), (0.112, 0.108)), # hips
    ((0.0, 0.12, 0.725), (0.088, 0.08)),  # tucked waist
    ((0.0, -0.05, 0.69), (0.118, 0.155)), # ribs
    ((0.0, -0.2, 0.675), (0.125, 0.185)), # deep chest
    ((0.0, -0.32, 0.715), (0.1, 0.13)),   # breast
    ((0.0, -0.41, 0.81), (0.064, 0.074)), # neck
    ((0.0, -0.47, 0.88), (0.052, 0.055)), # nape
]
# shoulder, elbow, wrist, pastern, paw, toe
FRONT_LEG = [((0.085, -0.23, 0.66), 0.066), ((0.08, -0.205, 0.45), 0.04), ((0.072, -0.225, 0.14), 0.024), ((0.072, -0.245, 0.055), 0.023), ((0.072, -0.285, 0.026), 0.033), ((0.072, -0.32, 0.02), 0.026)]
# hip, knee (stifle), hock, pastern, paw, toe
HIND_LEG = [((0.088, 0.3, 0.66), 0.095), ((0.1, 0.19, 0.42), 0.056), ((0.082, 0.39, 0.17), 0.026), ((0.078, 0.37, 0.055), 0.023), ((0.078, 0.33, 0.026), 0.032), ((0.078, 0.295, 0.02), 0.026)]
TAIL = []
for _i in range(9):
    _t = _i / 8
    TAIL.append(((0.0, 0.48 + 0.2 * _t - 0.04 * _t * _t, 0.73 - 0.1 * _t - 0.28 * _t * _t), 0.03 - 0.022 * _t))
HEAD_C = V((0.0, -0.555, 0.975))
HEAD_R = V((0.078, 0.092, 0.075))


def catmull(pts, n):
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
    """elliptical tube along the spine with the ribcage and the vertebrae pressing through the skin."""
    cs = [V(c) for c, r in SPINE]
    rs = [V((r[0], r[1], 0)) for c, r in SPINE]
    samples = catmull(cs, 12)
    radii = catmull(rs, 12)
    ring_n = 48
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
        y = c.y
        ring = []
        for k in range(ring_n):
            a = 2 * math.pi * k / ring_n
            ca, sa = math.cos(a), math.sin(a)
            rzz = rz * (1.0 if sa > 0 else 0.94)
            r_k = 1.0
            # ribs: ridges around the flanks of the ribcage, fading toward spine and belly
            if -0.3 < y < 0.06:
                rib = max(0.0, math.cos((y + 0.3) / 0.052 * 2 * math.pi)) ** 3
                along = math.sin(min(1.0, (y + 0.3) / 0.36) * math.pi)
                flank = max(0.0, abs(ca)) ** 0.7 * (1.0 - max(0.0, sa) ** 1.5)
                r_k += 0.085 * rib * along * flank
                # sunken between ribs and behind them
                r_k -= 0.03 * along * flank
            # vertebrae along the top line
            if sa > 0.9 and y > -0.35:
                r_k += 0.07 * max(0.0, math.cos(y / 0.045 * 2 * math.pi)) ** 4 * (sa - 0.9) * 10
            # hip bones
            ang = math.pi * (0.3 if ca > 0 else 0.7)
            hb = math.exp(-((y - 0.3) / 0.04) ** 2) * math.exp(-((a - ang) / 0.25) ** 2)
            r_k += 0.08 * hb
            ring.append(bm.verts.new(c + side * ca * rx * r_k + up * sa * rzz * r_k))
        rings.append(ring)
    for j in range(len(rings) - 1):
        for k in range(ring_n):
            l = (k + 1) % ring_n
            bm.faces.new((rings[j][k], rings[j][l], rings[j + 1][l], rings[j + 1][k]))
    for ring, rev in ((rings[0], True), (rings[-1], False)):
        c = bm.verts.new(sum((v.co for v in ring), V()) / len(ring))
        for k in range(ring_n):
            l = (k + 1) % ring_n
            bm.faces.new((ring[l], ring[k], c) if rev else (ring[k], ring[l], c))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("hound_torso")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("hound_torso", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def skin_chain(name, pts, subdiv=2):
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
    sub.levels = subdiv
    lib.apply_mods(ob)
    return ob


def sculpt_head():
    """long wolfish skull: brow ridge, deep eye sockets, sunken cheeks, flat forehead."""
    me = bpy.data.meshes.new("hound_head")
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=64, v_segments=48, radius=1.0)
    for v in bm.verts:
        x, y, z = v.co
        fwd = max(0.0, -y)
        side = abs(x)
        p = V((x * HEAD_R.x, y * HEAD_R.y, z * HEAD_R.z))
        if z > 0.2:
            p.z -= 0.012 * (z - 0.2)  # flatter forehead
        sock = math.exp(-(((side - 0.5) / 0.2) ** 2 + ((z - 0.15) / 0.2) ** 2)) * fwd ** 1.5
        p.y += 0.012 * sock
        p.x -= math.copysign(0.008 * sock, x)
        brow = math.exp(-((z - 0.42) / 0.16) ** 2) * fwd ** 2 * math.exp(-((side - 0.45) / 0.3) ** 2)
        p.y -= 0.01 * brow
        p.z += 0.006 * brow
        cheek = math.exp(-((z + 0.2) / 0.3) ** 2) * math.exp(-((y + 0.2) / 0.5) ** 2) * side
        p.x -= math.copysign(0.01 * cheek, x)
        # occipital bump at the back of the skull
        occ = math.exp(-((y - 0.8) / 0.25) ** 2) * math.exp(-((z - 0.5) / 0.3) ** 2) * math.exp(-(x / 0.3) ** 2)
        p.z += 0.012 * occ
        v.co = p + HEAD_C
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("hound_head", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def muzzle():
    upper = skin_chain("muzzle", [((0.0, -0.585, 0.975), (0.058, 0.056)), ((0.0, -0.66, 0.962), (0.045, 0.044)), ((0.0, -0.73, 0.952), (0.034, 0.034)), ((0.0, -0.775, 0.948), (0.026, 0.027))])
    jaw = skin_chain("jaw", [((0.0, -0.585, 0.925), (0.046, 0.03)), ((0.0, -0.67, 0.912), (0.034, 0.022)), ((0.0, -0.745, 0.908), (0.022, 0.016))])
    return [upper, jaw]


def remesh(ob, voxel=0.0055, faces=16000):
    ctx = bpy.context
    lib.deselect_all()
    ctx.view_layer.objects.active = ob
    ob.select_set(True)
    m = ob.modifiers.new("vox", "REMESH")
    m.mode = "VOXEL"
    m.voxel_size = voxel
    m.use_smooth_shade = True
    lib.apply_mods(ob)
    ls = ob.modifiers.new("lap", "LAPLACIANSMOOTH")
    ls.lambda_factor = 0.7
    ls.iterations = 6
    ls.use_volume_preserve = True
    lib.apply_mods(ob)
    d = ob.modifiers.new("dec", "DECIMATE")
    d.ratio = min(1.0, faces / max(1, len(ob.data.polygons)))
    lib.apply_mods(ob)
    sm = ob.modifiers.new("smooth", "SMOOTH")
    sm.factor = 0.4
    sm.iterations = 3
    lib.apply_mods(ob)
    for p in ob.data.polygons:
        p.use_smooth = True
    print("hound faces", len(ob.data.polygons))


def ear(side):
    bm = bmesh.new()
    base_w, height, cup, rows, cols = 0.07, 0.13, 0.016, 7, 6
    verts = []
    for j in range(rows + 1):
        t = j / rows
        w = base_w * (1 - t) ** 1.1
        row = []
        for i in range(cols + 1):
            u = i / cols - 0.5
            row.append(bm.verts.new((u * w, -cup * (1 - (2 * u) ** 2) * (1 - t * 0.6), t * height)))
        verts.append(row)
    for j in range(rows):
        for i in range(cols):
            bm.faces.new((verts[j][i], verts[j][i + 1], verts[j + 1][i + 1], verts[j + 1][i]))
    me = bpy.data.meshes.new(f"hear_{side}")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(f"hound_ear_{'L' if side > 0 else 'R'}", me)
    bpy.context.scene.collection.objects.link(ob)
    sol = ob.modifiers.new("sol", "SOLIDIFY")
    sol.thickness = 0.007
    sol.offset = 1.0
    sub = ob.modifiers.new("sub", "SUBSURF")
    sub.levels = 1
    lib.apply_mods(ob)
    for p in ob.data.polygons:
        p.use_smooth = True
    ob.location = V((0.05 * side, -0.53, 1.03))
    ob.rotation_euler = Euler((-0.25, side * 0.2, side * 0.22), "XYZ")
    return ob


def sphere(name, loc, r, scale=(1, 1, 1)):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=r)
    for v in bm.verts:
        v.co = V((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2]))
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = V(loc)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def fang(name, loc, length, down=True):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.006, radius2=0.0005, depth=length)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = V(loc)
    ob.rotation_euler = Euler((math.pi if down else 0.0, 0, 0), "XYZ")
    return ob


def teeth():
    parts = []
    for s in (-1, 1):
        parts.append(fang("f", (0.02 * s, -0.755, 0.93), 0.034, True))
        parts.append(fang("f", (0.024 * s, -0.715, 0.934), 0.016, True))
        parts.append(fang("f", (0.027 * s, -0.68, 0.936), 0.014, True))
    upper = lib.join(parts, "hound_teeth")
    low = [fang("f", (0.016 * s, -0.735, 0.912), 0.026, False) for s in (-1, 1)]
    lower = lib.join(low, "hound_teeth_low")
    return upper, lower


BONES = {
    "root": ((0, 0, 0), (0, 0.12, 0), None),
    "hips": ((0, 0.3, 0.72), (0, 0.12, 0.725), "root"),
    "spine": ((0, 0.12, 0.725), (0, -0.05, 0.7), "hips"),
    "chest": ((0, -0.05, 0.7), (0, -0.32, 0.73), "spine"),
    "neck": ((0, -0.33, 0.77), (0, -0.5, 0.93), "chest"),
    "head": ((0, -0.5, 0.93), (0, -0.78, 0.95), "neck"),
    "jaw": ((0, -0.58, 0.935), (0, -0.75, 0.905), "head"),
    "ear.L": ((0.05, -0.53, 1.03), (0.065, -0.55, 1.15), "head"),
    "ear.R": ((-0.05, -0.53, 1.03), (-0.065, -0.55, 1.15), "head"),
}
for i in range(4):
    BONES[f"tail{i}"] = (TAIL[i * 2][0], TAIL[i * 2 + 2][0], "hips" if i == 0 else f"tail{i - 1}")
for side, s in (("L", 1), ("R", -1)):
    f = [(p[0] * s, p[1], p[2]) for p, r in FRONT_LEG]
    BONES[f"shoulder.{side}"] = ((0.04 * s, -0.2, 0.78), f[0], "chest")
    BONES[f"upperarm.{side}"] = (f[0], f[1], f"shoulder.{side}")
    BONES[f"forearm.{side}"] = (f[1], f[2], f"upperarm.{side}")
    BONES[f"fpaw.{side}"] = (f[2], f[5], f"forearm.{side}")
    h = [(p[0] * s, p[1], p[2]) for p, r in HIND_LEG]
    BONES[f"thigh.{side}"] = (h[0], h[1], "hips")
    BONES[f"shin.{side}"] = (h[1], h[2], f"thigh.{side}")
    BONES[f"hock.{side}"] = (h[2], h[3], f"shin.{side}")
    BONES[f"hpaw.{side}"] = (h[3], h[5], f"hock.{side}")


def armature():
    arm = bpy.data.armatures.new("hound_rig")
    ob = bpy.data.objects.new("hound_rig", arm)
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
    for ob, bone in rigid:
        vg = ob.vertex_groups.new(name=bone)
        vg.add([v.index for v in ob.data.vertices], 1.0, "REPLACE")
        m = ob.modifiers.new("arm", "ARMATURE")
        m.object = rig
        ob.parent = rig


def fix_jaw_weights(body):
    """the voxel remesh fused the jaw into the muzzle: give the lower lip region to the jaw bone."""
    jaw = body.vertex_groups.get("jaw")
    head = body.vertex_groups.get("head")
    if jaw is None or head is None:
        return
    for v in body.data.vertices:
        x, y, z = v.co
        if y < -0.6 and abs(x) < 0.06:
            k = max(0.0, min(1.0, (0.935 - z) / 0.02))
            if k > 0:
                jaw.add([v.index], k, "REPLACE")
                head.add([v.index], 1.0 - k, "REPLACE")


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


def main():
    lib.reset_scene()
    parts = [loft_torso()]
    for side in (-1, 1):
        f = [((p[0] * side, p[1], p[2]), r) for p, r in FRONT_LEG]
        parts.append(skin_chain(f"leg_f{side}", [((0.05 * side, -0.22, 0.72), 0.07)] + f))
        h = [((p[0] * side, p[1], p[2]), r) for p, r in HIND_LEG]
        parts.append(skin_chain(f"leg_h{side}", [((0.05 * side, 0.3, 0.72), 0.08)] + h))
    parts.append(skin_chain("tail", [((0.0, 0.45, 0.72), 0.04)] + TAIL))
    parts.append(skin_chain("neck", [((0.0, -0.36, 0.78), (0.064, 0.078)), ((0.0, -0.45, 0.86), (0.05, 0.056)), ((0.0, -0.52, 0.93), (0.05, 0.05))]))
    parts.append(sculpt_head())
    parts += muzzle()
    body = lib.join(parts, "hound_body")
    remesh(body)
    ears = [ear(1), ear(-1)]
    eyes = [sphere(f"hound_eye_{'L' if s > 0 else 'R'}", (0.04 * s, -0.635, 0.995), 0.013, (1.25, 0.8, 0.7)) for s in (1, -1)]
    for e, s in zip(eyes, (1, -1)):
        e.rotation_euler = Euler((0.0, 0.0, s * 0.3), "XYZ")
    nose = sphere("hound_nose", (0.0, -0.772, 0.957), 0.018, (1.15, 0.8, 0.75))
    t_up, t_low = teeth()
    body.data.materials.append(simple_mat("hound_skin", (0.012, 0.01, 0.012), 0.7))
    for e in ears:
        e.data.materials.append(simple_mat("hound_skin", (0.012, 0.01, 0.012), 0.7))
    for e in eyes:
        e.data.materials.append(simple_mat("hound_eye", (1.0, 0.25, 0.1), 0.2))
    nose.data.materials.append(simple_mat("hound_nose", (0.02, 0.015, 0.015), 0.3))
    for t in (t_up, t_low):
        t.data.materials.append(simple_mat("hound_teeth", (0.75, 0.72, 0.62), 0.35))
    rig = armature()
    rigid = [(ears[0], "ear.L"), (ears[1], "ear.R"), (eyes[0], "head"), (eyes[1], "head"), (nose, "head"), (t_up, "head"), (t_low, "jaw")]
    skin(body, rig, rigid)
    fix_jaw_weights(body)
    if EXPORT:
        os.makedirs(OUT, exist_ok=True)
        lib.deselect_all()
        for o in bpy.data.objects:
            if o.name.startswith("hound_"):
                o.select_set(True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "hound.glb"), export_format="GLB", use_selection=True, export_apply=False,
                                  export_yup=True, export_skins=True, export_animations=False, export_materials="EXPORT")
        print("EXPORTED hound")
    if PREVIEW:
        prev = lib.collection("_prev")
        scene = lib.setup_render((1280, 720), 32)
        scene.world.color = (0.3, 0.3, 0.32)
        for o in [body] + ears:
            o.data.materials.clear()
            o.data.materials.append(simple_mat("prev_clay", (0.55, 0.52, 0.5), 0.6))
        key = bpy.data.objects.new("key", bpy.data.lights.new("key", "AREA"))
        key.data.energy = 200
        key.data.size = 1.5
        key.location = (1.4, -1.8, 2.0)
        key.rotation_euler = (0.8, 0, 0.6)
        prev.objects.link(key)
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        prev.objects.link(cam)
        scene.camera = cam
        cam.data.lens = 45
        for k, (loc, tgt) in enumerate((((1.9, -1.9, 1.0), (0, -0.05, 0.6)), ((0.0, -2.2, 0.95), (0, -0.4, 0.75)), ((-2.4, 0.0, 0.7), (0, 0.0, 0.55)), ((0.5, -1.2, 1.05), (0, -0.62, 0.95)))):
            cam.location = loc
            cam.rotation_euler = (V(tgt) - V(loc)).to_track_quat("-Z", "Y").to_euler()
            scene.render.filepath = PREVIEW.replace(".png", f"_{k}.png")
            bpy.ops.render.render(write_still=True)


main()
