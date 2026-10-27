"""Bakes the rest-pose position and normal of every texel of a cat model's UV atlas, so the coat can be
painted by where each texel sits on the body (tools/textures/gen_cat_coat.py) instead of in the
scrambled atlas of the generated base mesh. Also writes the landmarks the coat is laid out from
(bones, eye lenses, nose, mouth lines).

usage: blender -b -P tools/blender/bake_cat_pos.py -- godot/assets/models/cat/cat_mingau_a.glb [--res 4096]
-> tools/cache/cat_coat/<name>_pos.npz (pos, nrm: HxWx3 float32; mask: HxW bool) and <name>_marks.json
Blender coords: the cat faces -Y, Z up, feet at z=0.
"""
import json
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import lib  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SRC = argv[0]
RES = int(argv[argv.index("--res") + 1]) if "--res" in argv else 4096
NAME = os.path.splitext(os.path.basename(SRC))[0]
OUT = os.path.join(lib.ROOT, "tools", "cache", "cat_coat")


def raster(body):
    me = body.data
    me.calc_loop_triangles()
    mw = body.matrix_world
    nmw = mw.to_3x3().inverted().transposed()
    uvl = me.uv_layers.active.data
    co = np.array([tuple(mw @ v.co) for v in me.vertices], np.float32)
    vn = np.array([tuple((nmw @ v.normal).normalized()) for v in me.vertices], np.float32)
    pos = np.zeros((RES, RES, 3), np.float32)
    nrm = np.zeros((RES, RES, 3), np.float32)
    mask = np.zeros((RES, RES), bool)
    for tri in me.loop_triangles:
        uv = np.array([tuple(uvl[li].uv) for li in tri.loops], np.float64)
        px = uv[:, 0] * RES - 0.5
        py = (1.0 - uv[:, 1]) * RES - 0.5   # glTF V runs down the image
        x0, x1 = max(int(np.floor(px.min())), 0), min(int(np.ceil(px.max())), RES - 1)
        y0, y1 = max(int(np.floor(py.min())), 0), min(int(np.ceil(py.max())), RES - 1)
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        d = (py[1] - py[2]) * (px[0] - px[2]) + (px[2] - px[1]) * (py[0] - py[2])
        if abs(d) < 1e-12:
            continue
        a = ((py[1] - py[2]) * (gx - px[2]) + (px[2] - px[1]) * (gy - py[2])) / d
        b = ((py[2] - py[0]) * (gx - px[2]) + (px[0] - px[2]) * (gy - py[2])) / d
        c = 1.0 - a - b
        e = -0.02   # a hair of overlap so the seams between triangles leave no holes
        ins = (a >= e) & (b >= e) & (c >= e)
        if not ins.any():
            continue
        vi = tri.vertices
        w = np.stack([a[ins], b[ins], c[ins]], 1).astype(np.float32)
        yy, xx = gy[ins], gx[ins]
        pos[yy, xx] = w @ co[list(vi)]
        nn = w @ vn[list(vi)]
        nrm[yy, xx] = nn / np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-6)
        mask[yy, xx] = True
    return pos, nrm, mask


def main():
    lib.reset_scene()
    bpy.ops.import_scene.gltf(filepath=SRC)
    objs = {o.name: o for o in bpy.context.scene.objects}
    body = next(o for o in objs.values() if o.type == "MESH" and o.name.lower().startswith("cat_body"))
    rig = next(o for o in objs.values() if o.type == "ARMATURE")
    pos, nrm, mask = raster(body)
    os.makedirs(OUT, exist_ok=True)
    np.savez_compressed(os.path.join(OUT, f"{NAME}_pos.npz"), pos=pos, nrm=nrm, mask=mask)
    marks = {"bones": {}, "eyes": [], "lines": {}}
    for b in rig.data.bones:
        marks["bones"][b.name] = [list(rig.matrix_world @ b.head_local), list(rig.matrix_world @ b.tail_local)]
    for o in objs.values():
        if o.type != "MESH":
            continue
        n = o.name.lower()
        vs = [o.matrix_world @ v.co for v in o.data.vertices]
        if n.startswith("cat_eye"):
            lo = [min(v[i] for v in vs) for i in range(3)]
            hi = [max(v[i] for v in vs) for i in range(3)]
            marks["eyes"].append({"name": o.name, "center": [(lo[i] + hi[i]) / 2 for i in range(3)],
                                  "radius": (hi[2] - lo[2]) / 2})
        elif n.startswith("cat_mouthline"):
            marks["lines"][o.name] = [list(v) for v in vs]
        elif n.startswith("cat_decal"):
            marks.setdefault("decals", {})[o.name] = [sum(v[i] for v in vs) / len(vs) for i in range(3)]
    marks["eyes"].sort(key=lambda e: -e["center"][0])   # +x first (the cat's left)
    with open(os.path.join(OUT, f"{NAME}_marks.json"), "w") as f:
        json.dump(marks, f, indent=1)
    print("BAKED", NAME, "texels", int(mask.sum()), "of", RES * RES)


main()
