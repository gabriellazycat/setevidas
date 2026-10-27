"""Clara's towel turban for the bath (day 3): a rigid shell over the skull with the towel's spiral
folds and the twisted end tucked at the front, textured with the cream terry cloth. Unit size
(the skull ~1 m wide): HumanRig scales and places it on the head bone, like Davi's glasses.

usage: blender -b -P tools/blender/build_turban.py
  -> godot/assets/models/people/turban.glb
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import lib  # noqa: E402

OUT = os.path.join(lib.GODOT, "assets", "models", "people", "turban.glb")
TEX = os.path.join(lib.GODOT, "assets", "textures", "gen", "towel_cream.png")


def shell():
    """a dome over the skull (forehead to nape), puffed by spiral folds that wind up to the top"""
    me = bpy.data.meshes.new("turban")
    bm = bmesh.new()
    rings, segs = 26, 64
    verts = []
    for i in range(rings + 1):
        v = i / rings                       # 0 at the rim, 1 at the top
        phi = (1.0 - v) * math.radians(100)  # angle from the top
        row = []
        for j in range(segs):
            u = j / segs
            th = u * 2 * math.pi
            # skull: wider than deep, taller at the back; the rim drops lower at the nape
            r = 0.5
            x = math.sin(phi) * math.sin(th) * r * 1.0
            z = math.sin(phi) * math.cos(th) * r * 1.12
            y = math.cos(phi) * r * 1.05
            back = max(0.0, -math.cos(th))
            if v < 0.25:
                y -= (0.25 - v) * back * 0.9
            # the folds: a spiral band that winds 2.5 times from the rim to the top
            fold = 0.5 + 0.5 * math.sin((u * 2.5 + v * 2.5) * 2 * math.pi)
            puff = 1.0 + 0.06 * fold * math.sin(phi) + 0.1 * math.sin(phi) ** 2
            p = Vector((x * puff, y * puff + 0.06, z * puff))
            row.append(bm.verts.new(p))
        verts.append(row)
    uvl = bm.loops.layers.uv.new()
    for i in range(rings):
        for j in range(segs):
            a, b = verts[i][j], verts[i][(j + 1) % segs]
            c, d = verts[i + 1][(j + 1) % segs], verts[i + 1][j]
            f = bm.faces.new((a, b, c, d))
            for lp, (uu, vv) in zip(f.loops, ((j, i), (j + 1, i), (j + 1, i + 1), (j, i + 1))):
                lp[uvl].uv = (uu / segs * 3.0, vv / rings * 1.5)
    # close the top
    top = bm.verts.new(Vector((0, 0.5 * 1.05 * 1.1 + 0.06, 0)))
    for j in range(segs):
        f = bm.faces.new((verts[rings][j], verts[rings][(j + 1) % segs], top))
        for lp in f.loops:
            lp[uvl].uv = (0.5, 1.5)
    # a thick rim: extrude the bottom ring inward a little
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("turban", me)
    bpy.context.scene.collection.objects.link(ob)
    mod = ob.modifiers.new("solid", "SOLIDIFY")
    mod.thickness = 0.04
    mod.offset = 1.0
    sub = ob.modifiers.new("sub", "SUBSURF")
    sub.levels = 1
    return ob


def twist():
    """the twisted end of the towel, a fat rope tucked over the forehead"""
    pts = []
    for k in range(40):
        s = k / 39
        a = s * math.pi * 1.1
        pts.append(Vector((math.sin(a) * 0.18 - 0.05, 0.42 + math.sin(s * math.pi) * 0.18, 0.5 + math.cos(a) * 0.08)))
    cu = bpy.data.curves.new("twist", "CURVE")
    cu.dimensions = "3D"
    sp = cu.splines.new("POLY")
    sp.points.add(len(pts) - 1)
    for p, v in zip(sp.points, pts):
        p.co = (v.x, v.y, v.z, 1.0)
        p.radius = 1.0
    cu.bevel_depth = 0.085
    cu.bevel_resolution = 4
    cu.use_fill_caps = True
    ob = bpy.data.objects.new("twist", cu)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.convert(target="MESH")
    return bpy.context.view_layer.objects.active


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    a = shell()
    b = twist()
    mat = bpy.data.materials.new("towel")
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(TEX)
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.95
    for ob in (a, b):
        ob.data.materials.append(mat)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in (a, b):
        ob.select_set(True)
    bpy.context.view_layer.objects.active = a
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    a = bpy.context.view_layer.objects.active
    # uv for the rope (smart project is enough at this scale)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.object.mode_set(mode="OBJECT")
    # Godot is +Y up / +Z forward: the shell was built that way, glTF export converts Blender axes
    a.rotation_euler = (math.pi / 2, 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    print("EXPORTED", OUT)


main()
