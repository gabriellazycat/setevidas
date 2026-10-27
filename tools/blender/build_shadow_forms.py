"""The Shadow's other two bodies, made from its walking body (godot/assets/models/people/shadow.glb):

  shadow_run.glb   the body it runs in, spider-like on its back: limbs, neck and fingers far too long,
                   a thin chest. Same skeleton and bone names (the game poses it procedurally).
  shadow_peek.glb  what shows of it in a hiding place: the head and two hands, no skeleton. Each
                   piece sits in its own frame so the game can place it by points:
                     head    origin at the top of the neck, face along +Z, up +Y (Godot axes)
                     hand_l  origin at the wrist, fingers along +Y, back of the hand +Z,
                     hand_r  fingers long and curled to grip an edge
                   The cut ends (neck, wrist) point to -Y, where spectral.gdshader fades them out.
                   Empties eye_l / eye_r under the head mark where the eyes glow.

usage: blender -b -P tools/blender/build_shadow_forms.py -- [--only run|peek] [--preview DIR]
"""
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "godot", "assets", "models", "people", "shadow.glb")
OUT = os.path.join(ROOT, "godot", "assets", "models", "people")

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(name, default=None):
    return argv[argv.index(name) + 1] if name in argv else default


FINGERS = ["index", "middle", "ring", "pinky", "thumb"]
# runner proportions: scale along each bone (Y), applied to the rest pose
RUN_STRETCH = {
    "upperarm": 1.45, "lowerarm": 1.5, "hand": 1.35,
    "thigh": 1.3, "calf": 1.35, "foot": 1.15,
    "neck_01": 1.9,
}
RUN_THIN = {"spine_01": 0.8, "spine_02": 0.76, "spine_03": 0.8}   # chest width/depth
FINGER_LONG = 1.4
# grip: each finger joint curls this much (radians, about the bone's X)
CURL = {"01": 0.75, "02": 1.0, "03": 0.75}
THUMB_CURL = {"01": 0.15, "02": 0.35, "03": 0.35}


def load():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    body = bpy.data.objects["shadow_body"]
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o != body:
            bpy.data.objects.remove(o, do_unlink=True)
    if body.data.shape_keys:
        body.shape_key_clear()
    return arm, body


def activate(ob, mode="OBJECT"):
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    if mode != "OBJECT":
        bpy.ops.object.mode_set(mode=mode)


def bake_pose(arm, body):
    """the current pose becomes the rest pose, the mesh deformed with it"""
    activate(body)
    mod = next(m for m in body.modifiers if m.type == "ARMATURE")
    bpy.ops.object.modifier_apply(modifier=mod.name)
    activate(arm, "POSE")
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    m = body.modifiers.new("Armature", "ARMATURE")
    m.object = arm


def finger_bones(side):
    out = []
    for f in FINGERS:
        for k in ("01", "02", "03"):
            out.append(("%s_%s_%s" % (f, k, side), f, k))
    return out


def stretch_fingers(arm):
    for side in ("l", "r"):
        for name, f, k in finger_bones(side):
            if k == "01":
                arm.pose.bones[name].scale = (1.0, FINGER_LONG, 1.0)


def export(objs, path):
    for o in bpy.context.scene.objects:
        o.select_set(o in objs)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False, export_yup=True,
                              export_skins=True, export_morph=False, export_animations=False, export_materials="EXPORT")
    print("EXPORTED", path)


# ------------------------------------------------------------------------------------ runner


def build_run():
    arm, body = load()
    activate(arm, "POSE")
    for b in arm.data.bones:
        b.inherit_scale = "NONE"
    for pb in arm.pose.bones:
        base = pb.name.rsplit("_", 1)[0] if pb.name.endswith(("_l", "_r")) else pb.name
        if base in RUN_STRETCH:
            pb.scale = (1.0, RUN_STRETCH[base], 1.0)
        elif pb.name in RUN_THIN:
            k = RUN_THIN[pb.name]
            pb.scale = (k, 1.0, k)
    # finger chains keep inheriting from their first joint: the whole finger gets longer
    for side in ("l", "r"):
        for name, f, k in finger_bones(side):
            if k != "01":
                arm.data.bones[name].inherit_scale = "FULL"
    stretch_fingers(arm)
    bpy.context.view_layer.update()
    bake_pose(arm, body)
    for b in arm.data.bones:
        b.inherit_scale = "FULL"
    # the longer legs reach under the floor: everything up so the soles stand on it again
    low = min((body.matrix_world @ v.co).z for v in body.data.vertices)
    activate(arm)
    arm.location.z -= low
    body.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    print("RUN lifted", round(-low, 3))
    body.name = "shadow_run_body"
    body.data.materials[0].name = "shadow_run_body"
    export([arm, body], os.path.join(OUT, "shadow_run.glb"))
    for n in ("head", "hand_l", "hand_r", "foot_l", "thigh_l"):
        b = arm.data.bones[n]
        print("RUN", n, tuple(round(v, 3) for v in arm.matrix_world @ b.head_local))
    return arm, body


# ------------------------------------------------------------------------------------ peek


def weight_sets(body, groups):
    idx = {g.index: g.name for g in body.vertex_groups}
    out = {}
    for v in body.data.vertices:
        tot = {}
        for ge in v.groups:
            tot[idx[ge.group]] = ge.weight
        out[v.index] = tot
    return out


def extract(body, keep, name):
    """a new object with the faces whose vertices all pass keep(index, co)"""
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    gone = [f for f in bm.faces if not all(keep(v.index, v.co) for v in f.verts)]
    bmesh.ops.delete(bm, geom=gone, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in body.data.materials:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


# Godot's +Z (forward) is Blender's -Y, Godot's +Y (up) is Blender's +Z: a piece whose Godot frame
# should be (fingers +Y, back +Z) is built in Blender with fingers along +Z and the back along -Y.
def place(ob, world_frame):
    """bake the mesh into world_frame's local space, so the object's origin and axes are that frame"""
    inv = world_frame.inverted()
    ob.data.transform(inv)
    ob.matrix_world = Matrix.Identity(4)


def build_peek():
    arm, body = load()
    activate(arm, "POSE")
    stretch_fingers(arm)
    for side in ("l", "r"):
        for name, f, k in finger_bones(side):
            ang = (THUMB_CURL if f == "thumb" else CURL)[k]
            pb = arm.pose.bones[name]
            pb.rotation_mode = "XYZ"
            pb.rotation_euler = (ang, 0.0, 0.0)
    bpy.context.view_layer.update()
    mw = arm.matrix_world

    def pbw(n, tail=False):
        pb = arm.pose.bones[n]
        return mw @ (pb.tail if tail else pb.head)

    # posed points, before the mesh is baked
    neck_top = pbw("head")
    neck_base = pbw("neck_01")
    head_top = pbw("head", True)
    hands = {}
    for side in ("l", "r"):
        wrist = pbw("hand_" + side)
        knuckles = sum((pbw("%s_01_%s" % (f, side)) for f in ("index", "middle", "ring", "pinky")), Vector()) / 4
        tips = sum((pbw("%s_03_%s" % (f, side), True) for f in ("index", "middle", "ring", "pinky")), Vector()) / 4
        elbow = pbw("lowerarm_" + side)
        hands[side] = (wrist, knuckles, tips, elbow)
    activate(body)
    mod = next(m for m in body.modifiers if m.type == "ARMATURE")
    bpy.ops.object.modifier_apply(modifier=mod.name)
    W = weight_sets(body, None)
    co_w = {v.index: body.matrix_world @ v.co for v in body.data.vertices}

    def wsum(i, names):
        d = W[i]
        return sum(d.get(n, 0.0) for n in names)

    neck_mid_z = neck_base.z + (neck_top.z - neck_base.z) * 0.35
    pieces = []
    head = extract(body, lambda i, co: wsum(i, ["head"]) > 0.25 or (wsum(i, ["neck_01"]) > 0.4 and co_w[i].z > neck_mid_z), "head")
    # head frame: origin at the top of the neck; Blender's own axes already are Godot's (face -Y, up +Z)
    place(head, Matrix.Translation(neck_top))
    pieces.append(head)
    for side in ("l", "r"):
        wrist, knuckles, tips, elbow = hands[side]
        names = ["hand_" + side] + [n for n, _, _ in finger_bones(side)]
        fdir = (knuckles - wrist).normalized()
        palm = tips - knuckles
        palm = (palm - fdir * palm.dot(fdir)).normalized()   # the side the fingers curl to
        back = -palm

        def keep(i, co, names=names, wrist=wrist, fdir=fdir):
            if wsum(i, names) > 0.45:
                return True
            # a short stub of the forearm under the cut, faded by the shader
            p = co_w[i]
            return wsum(i, ["lowerarm_" + side]) > 0.4 and -0.1 < (p - wrist).dot(fdir) < 0.02
        hand = extract(body, keep, "hand_" + side)
        # Godot frame (fingers +Y, back +Z) == Blender (fingers +Z, back -Y)
        z_b = fdir
        y_b = -back
        y_b = (y_b - z_b * y_b.dot(z_b)).normalized()
        x_b = y_b.cross(z_b)
        m = Matrix((x_b, y_b, z_b)).transposed().to_4x4()
        m.translation = wrist
        place(hand, m)
        pieces.append(hand)
    # the head piece in Blender axes stays as it was (Blender -Y forward == Godot +Z): only moved
    eyes = []
    for side, sx in (("l", 1.0), ("r", -1.0)):
        # the game's pin-prick eyes: GhostBody puts them at head + up 0.075, fwd 0.085, side 0.032
        e = bpy.data.objects.new("eye_" + side, None)
        bpy.context.scene.collection.objects.link(e)
        e.parent = head
        e.location = Vector((0.032 * sx, -0.085, 0.075))
        eyes.append(e)
    bpy.data.objects.remove(body, do_unlink=True)
    bpy.data.objects.remove(arm, do_unlink=True)
    for p in pieces:
        p.data.materials.clear()
    export(pieces + eyes, os.path.join(OUT, "shadow_peek.glb"))
    for p in pieces:
        bb = [Vector(c) for c in p.bound_box]
        print("PEEK", p.name, len(p.data.vertices), "min", tuple(round(min(c[i] for c in bb), 3) for i in range(3)), "max", tuple(round(max(c[i] for c in bb), 3) for i in range(3)))
    return pieces


def preview(objs, out_dir, name):
    import math
    os.makedirs(out_dir, exist_ok=True)
    scene = bpy.context.scene
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "BLENDER_WORKBENCH"):
        try:
            scene.render.engine = eng
            break
        except TypeError:
            continue
    scene.render.resolution_x, scene.render.resolution_y = 900, 900
    mn = Vector((1e9,) * 3)
    mx = Vector((-1e9,) * 3)
    for o in objs:
        if o.type != "MESH":
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            mn = Vector(map(min, mn, w))
            mx = Vector(map(max, mx, w))
    c = (mn + mx) / 2
    r = (mx - mn).length
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    scene.collection.objects.link(sun)
    sun.rotation_euler = (0.8, 0.2, 0.6)
    if scene.world is None:
        scene.world = bpy.data.worlds.new("w")
    for view, d in (("front", Vector((0, -1, 0.15))), ("side", Vector((1, 0, 0.15))), ("top", Vector((0.2, -0.3, 1)))):
        cam.location = c + d.normalized() * r * 1.3
        cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(out_dir, "%s_%s.png" % (name, view))
        bpy.ops.render.render(write_still=True)


only = arg("--only")
pv = arg("--preview")
if only in (None, "run"):
    a, b = build_run()
    if pv:
        preview([b], pv, "run")
if only in (None, "peek"):
    ps = build_peek()
    if pv:
        # spread the pieces apart to look at them
        for i, p in enumerate(ps):
            p.location.x = (i - 1) * 0.45
        preview(ps, pv, "peek")
