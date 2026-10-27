"""Build the whole house for Godot.

usage: blender -b -P tools/blender/build_house.py -- [--preview] [--no-export] [--only shell]

Outputs (godot/assets/models/house/):
  house.glb          architecture + custom built furniture (materials by name, no images)
  house_data.json    Poly Haven placements, colliders and named markers for the game
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import importlib

import bpy

import lib

importlib.reload(lib)
import house_shell  # noqa: E402

importlib.reload(house_shell)

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIEW = "--preview" in argv
EXPORT = "--no-export" not in argv
ONLY = argv[argv.index("--only") + 1] if "--only" in argv else None
OUT = os.path.join(lib.GODOT, "assets", "models", "house")
PREV_DIR = os.environ.get("SV_PREVIEW_DIR", os.path.join(lib.ROOT, "tools", "previews"))


def main():
    lib.reset_scene()
    lib.REG.__init__()
    L = lib.load_layout()
    shell_coll = lib.collection("shell")
    house_shell.Shell(L, shell_coll).build()

    built = ["shell"]
    if ONLY != "shell":
        import house_furnish  # noqa: E402

        importlib.reload(house_furnish)
        furn = lib.collection("furniture")
        house_furnish.furnish(L, furn)
        built.append("furniture")
        import house_exterior  # noqa: E402

        importlib.reload(house_exterior)
        ext = lib.collection("exterior")
        house_exterior.build(L, ext)
        built.append("exterior")

    if EXPORT:
        # Poly Haven instances are placed by Godot from house_data.json; export only our geometry
        lib.export_glb(os.path.join(OUT, "house.glb"), [c for c in built], images=False, extra_objects=())
        lib.REG.save(os.path.join(OUT, "house_data.json"))
        print("colliders", len(lib.REG.colliders), "placements", len(lib.REG.placements))

    if PREVIEW:
        os.makedirs(PREV_DIR, exist_ok=True)
        prev = lib.collection("_preview")
        w = bpy.context.scene.world
        w.color = (0.02, 0.025, 0.04)
        lib.point_light("p_sala", prev, (2.5, 2.2, 2.75), (1, 0.82, 0.6), 220)
        lib.point_light("p_hall", prev, (6.6, 2.4, 3.4), (1, 0.85, 0.65), 160)
        lib.point_light("p_quarto", prev, (2.5, 5.4, 2.75), (1, 0.8, 0.6), 180)
        lib.point_light("p_coz", prev, (9.75, 2.5, 6.75), (1, 0.95, 0.85), 200)
        lib.point_light("p_porao", prev, (3.8, -0.6, 5.2), (1, 0.75, 0.5), 160)
        lib.point_light("p_out", prev, (-2, 6, -8), (0.6, 0.7, 1.0), 4000, radius=1.0)
        lib.preview(os.path.join(PREV_DIR, "sala.png"), (4.6, 1.5, 0.4), (1.0, 1.0, 4.5), lens=18)
        lib.preview(os.path.join(PREV_DIR, "hall.png"), (6.3, 1.5, 0.5), (6.3, 1.4, 9.0), lens=18)
        lib.preview(os.path.join(PREV_DIR, "quarto.png"), (4.5, 4.5, 4.8), (0.8, 3.6, 1.5), lens=18)
        lib.preview(os.path.join(PREV_DIR, "cozinha.png"), (7.9, 1.6, 4.0), (10.5, 0.8, 9.5), lens=18)
        lib.preview(os.path.join(PREV_DIR, "exterior.png"), (4.0, 3.0, -15.0), (6.5, 3.0, 4.0), lens=28)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(PREV_DIR, "house.blend"))


main()
