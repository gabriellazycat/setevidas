"""Measure the anime proportions of a VRoid VRM against anime_proportions.json.

usage: blender -b -P tools/blender/measure_vrm.py -- file.vrm [clara|davi]

Prints each ratio, its target and the error; a ratio more than `tol` away is flagged OFF.
Definitions match the notes in anime_proportions.json: the head runs from the crown of the hair
mesh to the chin, the crotch is the lowest point of the body's centre line above the knees, eye
sizes come from the EyeWhite material and the face width from the face skin at the eye line.
"""
import json
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(__file__)


def world_verts(ob, mat_filter=None):
    me = ob.data
    out = []
    mats = [i for i, m in enumerate(me.materials) if m and (mat_filter is None or mat_filter in m.name)]
    if not mats:
        return out
    want = set(mats)
    vids = set()
    for p in me.polygons:
        if p.material_index in want:
            vids.update(p.vertices)
    mw = ob.matrix_world
    return [mw @ me.vertices[i].co for i in vids]


def measure(path):
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.import_scene.vrm(filepath=path)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    allv = [v for o in meshes for v in world_verts(o)]
    top = max(v.z for v in allv)
    ground = min(v.z for v in allv)
    height = top - ground
    face = next(o for o in meshes if any(m and "_Face_" in m.name for m in o.data.materials))
    skin = world_verts(face, "_Face_00_SKIN")
    chin = min(v.z for v in skin)
    head = top - chin
    whites = world_verts(face, "EyeWhite")
    left = [v for v in whites if v.x > 0]
    eye_w = max(v.x for v in left) - min(v.x for v in left)
    iris = [v for v in world_verts(face, "EyeIris") if v.x > 0]
    eye_h = max(v.z for v in iris) - min(v.z for v in iris)
    eye_c = (max(v.z for v in iris) + min(v.z for v in iris)) / 2
    band = [v for v in skin if abs(v.z - eye_c) < 0.004]
    face_w = max(v.x for v in band) - min(v.x for v in band)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    knee = (arm.matrix_world @ arm.data.bones["J_Bip_L_LowerLeg"].head_local).z
    body = next(o for o in meshes if any(m and "Body_00_SKIN" in m.name for m in o.data.materials))
    centre = [v for v in world_verts(body, "Body_00_SKIN") if abs(v.x) < 0.012 and knee < v.z < knee + 0.5 * height]
    crotch = min(v.z for v in centre) if centre else (arm.matrix_world @ arm.data.bones["J_Bip_L_UpperLeg"].head_local).z
    return {
        "height_m": height,
        "heads": height / head,
        "inseam_over_height": (crotch - ground) / height,
        "eye_w_over_face_w": eye_w / face_w,
        "eye_h_over_head_h": eye_h / head,
        "eye_line_over_head_h": (eye_c - chin) / head,
    }


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    path = argv[0]
    cid = argv[1] if len(argv) > 1 else "clara"
    with open(os.path.join(HERE, "anime_proportions.json"), encoding="utf8") as f:
        spec = json.load(f)
    tol = spec["tol"]
    tgt = spec["targets"][cid]
    got = measure(path)
    bad = 0
    for k, v in got.items():
        t = tgt[k]
        if k == "height_m":
            print("MEASURE %-22s %.3f (scaled to %.2f in build_vroid)" % (k, v, t))
            continue
        err = v / t - 1.0
        flag = "ok" if abs(err) <= tol else "OFF"
        bad += flag == "OFF"
        print("MEASURE %-22s %.3f target %.3f  %+5.1f%%  %s" % (k, v, t, err * 100, flag))
    print("MEASURE result:", "PASS" if bad == 0 else "%d off" % bad)


if __name__ == "__main__":
    main()
