"""Export every procedural furniture piece of house_kit.KIT for Godot.

usage: blender -b -P tools/blender/build_kit.py -- [--only id,id] [--preview DIR] [--no-export]

Outputs godot/assets/models/kit/<id>.glb (materials named by materials.json key, no images).
--preview DIR renders one tile per piece and DIR/kit_sheet.png (contact sheet, labelled).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402

import house_kit  # noqa: E402
import lib  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = argv[argv.index("--only") + 1].split(",") if "--only" in argv else None
PREVIEW = argv[argv.index("--preview") + 1] if "--preview" in argv else None
EXPORT = "--no-export" not in argv
OUT = os.path.join(lib.GODOT, "assets", "models", "kit")
TILE = 300
COLS = 10


def bounds(objs):
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            mn = Vector((min(mn.x, w.x), min(mn.y, w.y), min(mn.z, w.z)))
            mx = Vector((max(mx.x, w.x), max(mx.y, w.y), max(mx.z, w.z)))
    return mn, mx


def render_tile(mid, objs, path):
    scene = lib.setup_render((TILE, TILE), samples=16)
    scene.world.color = (0.55, 0.52, 0.5)
    mn, mx = bounds(objs)
    centre = (mn + mx) / 2
    size = max((mx - mn).length, 0.05)
    prev = lib.collection("_kitprev")
    cam = bpy.data.objects.new("_kcam", bpy.data.cameras.new("_kcam"))
    prev.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = size * 1.15
    cam.data.clip_end = size * 20
    # front 3/4 view: game +z front -> blender -y, from up-right
    d = Vector((0.55, -1.0, 0.55)).normalized()
    cam.location = centre + d * size * 3
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    sun = bpy.data.objects.new("_ksun", bpy.data.lights.new("_ksun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    prev.objects.link(sun)
    txt = bpy.data.curves.new("_ktxt", "FONT")
    txt.body = mid
    txt.size = 0.055 * cam.data.ortho_scale
    txt.align_x = "CENTER"
    to = bpy.data.objects.new("_ktxt", txt)
    prev.objects.link(to)
    to.parent = cam
    to.location = (0, -0.45 * cam.data.ortho_scale, -size)
    tm = bpy.data.materials.new("_ktxt")
    tm.diffuse_color = (0, 0, 0, 1)
    try:
        bsdf = next(n for n in tm.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Base Color"].default_value = (0.02, 0.02, 0.02, 1)
    except Exception:  # noqa: BLE001
        pass
    txt.materials.append(tm)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def contact_sheet(ids, tiles_dir, out):
    rows = (len(ids) + COLS - 1) // COLS
    sheet = np.ones((rows * TILE, COLS * TILE, 4), dtype=np.float32)
    for i, mid in enumerate(ids):
        p = os.path.join(tiles_dir, mid + ".png")
        if not os.path.exists(p):
            continue
        img = bpy.data.images.load(p)
        px = np.array(img.pixels[:], dtype=np.float32).reshape(img.size[1], img.size[0], 4)
        r, c = i // COLS, i % COLS
        y0 = (rows - 1 - r) * TILE  # blender images start at the bottom row
        sheet[y0:y0 + TILE, c * TILE:(c + 1) * TILE] = px[:TILE, :TILE]
        bpy.data.images.remove(img)
    im = bpy.data.images.new("kit_sheet", COLS * TILE, rows * TILE, alpha=True)
    im.pixels.foreach_set(sheet.ravel())
    im.filepath_raw = out
    im.file_format = "PNG"
    im.save()
    print("SHEET", out)


def main():
    ids = ONLY or sorted(house_kit.KIT, key=str.lower)
    tiles = os.path.join(PREVIEW, "tiles") if PREVIEW else None
    if tiles:
        os.makedirs(tiles, exist_ok=True)
    for mid in ids:
        lib.reset_scene()
        coll = lib.collection("kit")
        objs = house_kit.build(mid, coll)
        if EXPORT:
            lib.export_glb(os.path.join(OUT, f"{mid}.glb"), ["kit"], images=False)
        if tiles:
            render_tile(mid, objs, os.path.join(tiles, mid + ".png"))
        mn, mx = bounds(objs)
        s = mx - mn
        print(f"KIT {mid} objs={len(objs)} size(game w,h,d)=({s.x:.3f}, {s.z:.3f}, {s.y:.3f})")
    if PREVIEW:
        contact_sheet(ids, tiles, os.path.join(PREVIEW, "kit_sheet.png"))
    print("KIT DONE", len(ids))


main()
