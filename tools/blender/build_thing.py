"""The Thing in the basement (night 7): a mass of arms and tentacles coming out of the chalk circle,
with one eye in the core that opens during the tell.

usage: blender -b -P tools/blender/build_thing.py
  -> godot/assets/models/thing.glb

  thing_rig     armature: root, t<i>_<k> (6 tentacles) and a<i>_<k> (4 arms), 8 bones each from the
                floor up, plus "eye" (the eyeball turns to look at the cat)
  THING_limbs   tapered tubes (the arms end in a hand), skinned to their chains by height
  THING_core    the lumpy mass in the middle
  THING_eye     the eyeball (Godot paints the iris)
  THING_lids    two lids over the eye, shape key "open"
Godot (threats/thing.gd) bends the chains every frame and keeps the tentacle skin shader.
Built in Blender coordinates (z up, the front of the eye toward -y, which is +z in Godot).
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import lib  # noqa: E402

OUT = os.path.join(lib.GODOT, "assets", "models", "thing.glb")
BONES = 8
R = random.Random(7)


def tube_profile(kind, h):
    """radius along the limb (h 0 at the floor, 1 at the tip)"""
    if kind == "t":
        return 0.2 * (1.0 - h) ** 0.75 + 0.012
    # an arm: shoulder, a thin forearm after an elbow bulge, a wrist, then the hand
    r = 0.13 * (1.0 - h * 0.55)
    r += 0.03 * math.exp(-((h - 0.5) / 0.06) ** 2)
    if h > 0.86:
        r = 0.05 + (h - 0.86) * 0.25
    return r


def limb(bm, deform, kind, idx, base, yaw, length):
    """a tube straight up from `base`, weights per bone by height; the arms get four fingers"""
    rings, segs = 44, 12
    names = [f"{kind}{idx}_{k}" for k in range(BONES)]
    ring_verts = []
    for i in range(rings + 1):
        h = i / rings
        r = tube_profile(kind, h)
        z = h * length
        row = []
        for j in range(segs):
            a = j / segs * 2 * math.pi
            # a little lumpy so it does not look turned on a lathe
            rr = r * (1.0 + 0.08 * math.sin(a * 3 + idx + h * 9))
            v = bm.verts.new((base.x + math.cos(a) * rr, base.y + math.sin(a) * rr, z))
            f = h * (BONES - 1)
            k0 = min(BONES - 1, int(f))
            k1 = min(BONES - 1, k0 + 1)
            w1 = f - k0
            v[deform][groups[names[k0]]] = 1.0 - w1
            if k1 != k0:
                v[deform][groups[names[k1]]] = w1
            row.append(v)
        ring_verts.append(row)
    for i in range(rings):
        for j in range(segs):
            bm.faces.new((ring_verts[i][j], ring_verts[i][(j + 1) % segs], ring_verts[i + 1][(j + 1) % segs], ring_verts[i + 1][j]))
    tip = bm.verts.new((base.x, base.y, length + 0.01))
    tip[deform][groups[names[-1]]] = 1.0
    for j in range(segs):
        bm.faces.new((ring_verts[rings][j], ring_verts[rings][(j + 1) % segs], tip))
    if kind == "a":
        # four long fingers fanning out of the hand
        for fi in range(4):
            fa = yaw + (fi - 1.5) * 0.45
            d = Vector((math.cos(fa) * 0.35, math.sin(fa) * 0.35, 1.0)).normalized()
            start = Vector((base.x, base.y, length * 0.97))
            pts = [start + d * (s * 0.32) for s in range(5)]
            prev = None
            for si, p in enumerate(pts):
                rr = 0.022 * (1.0 - si / 5.0) + 0.006
                row = []
                for j in range(6):
                    a = j / 6 * 2 * math.pi
                    v = bm.verts.new(p + Vector((math.cos(a) * rr, math.sin(a) * rr, 0)))
                    v[deform][groups[names[-1]]] = 1.0
                    row.append(v)
                if prev:
                    for j in range(6):
                        bm.faces.new((prev[j], prev[(j + 1) % 6], row[(j + 1) % 6], row[j]))
                prev = row


groups = {}


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    coll = bpy.context.scene.collection
    # ---- armature
    arm_data = bpy.data.armatures.new("thing_rig")
    rig = bpy.data.objects.new("thing_rig", arm_data)
    coll.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    root = arm_data.edit_bones.new("root")
    root.head = (0, 0, 0)
    root.tail = (0, 0, 0.2)
    limbs = []
    for i in range(6):
        a = i / 6 * 2 * math.pi + 0.3
        rr = R.uniform(0.9, 1.25)
        limbs.append(("t", i, Vector((math.cos(a) * rr, math.sin(a) * rr, 0)), a, R.uniform(2.0, 2.8)))
    for i in range(4):
        a = i / 4 * 2 * math.pi + 0.8
        rr = R.uniform(0.55, 0.8)
        limbs.append(("a", i, Vector((math.cos(a) * rr, math.sin(a) * rr, 0)), a, R.uniform(1.6, 1.9)))
    for kind, idx, base, yaw, length in limbs:
        prev = root
        for k in range(BONES):
            b = arm_data.edit_bones.new(f"{kind}{idx}_{k}")
            b.head = (base.x, base.y, length * k / BONES)
            b.tail = (base.x, base.y, length * (k + 1) / BONES)
            b.roll = 0.0
            b.parent = prev
            b.use_connect = k > 0
            prev = b
    eye = arm_data.edit_bones.new("eye")
    eye.head = (0, -0.28, 0.42)
    eye.tail = (0, -0.48, 0.42)
    eye.parent = root
    bpy.ops.object.mode_set(mode="OBJECT")
    # ---- limbs mesh
    me = bpy.data.meshes.new("THING_limbs")
    ob = bpy.data.objects.new("THING_limbs", me)
    coll.objects.link(ob)
    for b in arm_data.bones:
        if b.name not in ("root", "eye"):
            ob.vertex_groups.new(name=b.name)
    for vg in ob.vertex_groups:
        groups[vg.name] = vg.index
    bm = bmesh.new()
    deform = bm.verts.layers.deform.verify()
    for kind, idx, base, yaw, length in limbs:
        limb(bm, deform, kind, idx, base, yaw, length)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob.parent = rig
    mod = ob.modifiers.new("arm", "ARMATURE")
    mod.object = rig
    # UVs: cylindrical-ish projection for the skin shader noise
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.cylinder_project()
    bpy.ops.object.mode_set(mode="OBJECT")
    # ---- core: a lumpy mass half under the floor
    bpy.ops.mesh.primitive_uv_sphere_add(segments=40, ring_count=24, radius=0.62, location=(0, 0, 0.05))
    core = bpy.context.active_object
    core.name = "THING_core"
    core.scale = (1.0, 1.0, 0.62)
    for v in core.data.vertices:
        n = v.co.normalized()
        v.co *= 1.0 + 0.12 * math.sin(n.x * 7 + n.y * 3) * math.cos(n.y * 6 - n.z * 4)
    bpy.ops.object.transform_apply(scale=True)
    core.parent = rig
    cm = core.modifiers.new("arm", "ARMATURE")
    cm.object = rig
    vg = core.vertex_groups.new(name="root")
    vg.add([v.index for v in core.data.vertices], 1.0, "REPLACE")
    # ---- the eye and its lids, on the eye bone
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=20, radius=0.17, location=(0, -0.28, 0.42))
    eyeb = bpy.context.active_object
    eyeb.name = "THING_eye"
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=24, radius=0.185, location=(0, -0.28, 0.42))
    lids = bpy.context.active_object
    lids.name = "THING_lids"
    # keep only the front half of the shell
    bm = bmesh.new()
    bm.from_mesh(lids.data)
    c = Vector((0, -0.28, 0.42))
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if (v.co - c).y > 0.03], context="VERTS")
    bm.to_mesh(lids.data)
    bm.free()
    lids.shape_key_add(name="Basis")
    sk = lids.shape_key_add(name="open")
    for i, v in enumerate(lids.data.vertices):
        p = v.co - c
        up = p.z >= 0.0
        ang = math.radians(75) * (1.0 if up else -1.0) * min(1.0, 0.4 + abs(p.z) / 0.185)
        rot = Matrix.Rotation(ang, 3, "X")
        sk.data[i].co = c + rot @ p
    for part in (eyeb, lids):
        part.parent = rig
        m = part.modifiers.new("arm", "ARMATURE")
        m.object = rig
        g = part.vertex_groups.new(name="eye")
        g.add([v.index for v in part.data.vertices], 1.0, "REPLACE")
    for part, colr in ((ob, (0.03, 0.01, 0.01, 1)), (core, (0.05, 0.01, 0.01, 1)), (eyeb, (0.9, 0.85, 0.8, 1)), (lids, (0.06, 0.015, 0.015, 1))):
        mat = bpy.data.materials.new(part.name + "_mat")
        mat.diffuse_color = colr
        part.data.materials.append(mat)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in (rig, ob, core, eyeb, lids):
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=False, export_yup=True,
                              export_skins=True, export_morph=True, export_animations=False)
    print("EXPORTED", OUT, "bones", len(arm_data.bones))


main()
