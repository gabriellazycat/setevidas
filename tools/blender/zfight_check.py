"""Finds z-fighting in the built house: faces that lie in the same plane, face the same way and
overlap (the renderer flickers between them). Axis-aligned faces only (the house is boxes).

usage: blender -b -P tools/blender/zfight_check.py -- [--glb godot/assets/models/house/house.glb] [--min 0.0004]
Prints one line per overlapping pair: plane, overlap area, the two objects/materials, the overlap box.
"""
import os
import sys
from collections import defaultdict

import bpy

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GLB = argv[argv.index("--glb") + 1] if "--glb" in argv else os.path.join(ROOT, "godot", "assets", "models", "house", "house.glb")
MIN = float(argv[argv.index("--min") + 1]) if "--min" in argv else 0.0004

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)
# glTF comes in triangulated: join the triangles back into the quads of the boxes
import bmesh
for ob in bpy.data.objects:
    if ob.type == "MESH":
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.join_triangles(bm, faces=bm.faces, angle_face_threshold=0.01, angle_shape_threshold=3.2)
        bm.to_mesh(ob.data)
        bm.free()

planes = defaultdict(list)   # (axis, sign, coord mm) -> [(u0, u1, v0, v1, obj, mat)]
for ob in bpy.data.objects:
    if ob.type != "MESH":
        continue
    me = ob.data
    mw = ob.matrix_world
    for poly in me.polygons:
        n = (mw.to_3x3() @ poly.normal).normalized()
        ax = max(range(3), key=lambda i: abs(n[i]))
        if abs(n[ax]) < 0.999:
            continue
        pts = [mw @ me.vertices[i].co for i in poly.vertices]
        c = sum(p[ax] for p in pts) / len(pts)
        if max(abs(p[ax] - c) for p in pts) > 1e-4:
            continue
        o = [i for i in range(3) if i != ax]
        us = [p[o[0]] for p in pts]
        vs = [p[o[1]] for p in pts]
        # rectangles only (the boxes of the house): a bounding box says nothing about a big polygon
        if abs(poly.area - (max(us) - min(us)) * (max(vs) - min(vs))) > 1e-3 * max(1.0, poly.area):
            continue
        mat = me.materials[poly.material_index].name if me.materials else "-"
        planes[(ax, 1 if n[ax] > 0 else -1, round(c * 1000))].append((min(us), max(us), min(vs), max(vs), ob.name, mat))

AX = "xyz"
hits = []
for key, fs in planes.items():
    if len(fs) < 2:
        continue
    fs.sort()
    for i in range(len(fs)):
        a = fs[i]
        for j in range(i + 1, len(fs)):
            b = fs[j]
            if b[0] >= a[1]:
                break
            du = min(a[1], b[1]) - max(a[0], b[0])
            dv = min(a[3], b[3]) - max(a[2], b[2])
            if du <= 1e-4 or dv <= 1e-4:
                continue
            if a[4] == b[4] and a[5] == b[5] and du * dv < MIN * 4:
                continue
            area = du * dv
            if area < MIN:
                continue
            hits.append((area, key, a, b, (max(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), min(a[3], b[3]))))
hits.sort(key=lambda h: -h[0])
print("ZFIGHT %d overlapping coplanar pairs" % len(hits))
for area, (ax, sg, c), a, b, box in hits[:2000]:
    o = [AX[i] for i in range(3) if i != ax]
    print("ZF %s%s=%.3f area=%.4f  %s[%s] x %s[%s]  %s %.2f..%.2f  %s %.2f..%.2f" % ("+" if sg > 0 else "-", AX[ax], c / 1000, area, a[4], a[5], b[4], b[5], o[0], box[0], box[1], o[1], box[2], box[3]))
