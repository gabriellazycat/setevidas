"""Print game-axis sizes of every cached Poly Haven model and render a front view sheet of chosen ones.
usage: blender -b -P ph_probe.py -- out_dir [ids...]"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bpy  # noqa: E402

import lib  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:]
out = argv[0]
ids = argv[1:] or sorted(os.listdir(lib.PH_MODELS))
lib.reset_scene()
sizes = {}
for mid in ids:
    try:
        (w, h, d), mn, mx = lib.ph_size(mid)
        sizes[mid] = [round(w, 3), round(h, 3), round(d, 3)]
        print("SIZE", mid, sizes[mid])
    except Exception as e:  # noqa: BLE001
        print("FAIL", mid, e)
with open(os.path.join(out, "ph_sizes.json"), "w") as f:
    json.dump(sizes, f, indent=1)
