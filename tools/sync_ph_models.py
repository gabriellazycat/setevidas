"""Copy every Poly Haven model referenced by house_data.json (and the extra list below) from the
download cache into godot/assets/models/ph/ so Godot can import them."""
import json
import os
import shutil

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CACHE = os.path.join(ROOT, "tools", "cache", "polyhaven", "models")
DEST = os.path.join(ROOT, "godot", "assets", "models", "ph")
EXTRA = ["tea_set_01", "ceramic_vase_01", "ceramic_vase_02", "ceramic_vase_03", "antique_ceramic_vase_01",
         "standing_picture_frame_01", "book_encyclopedia_set_01", "wine_bottles_01", "potted_plant_02", "treasure_chest"]


def main():
    with open(os.path.join(ROOT, "godot", "assets", "models", "house", "house_data.json"), encoding="utf8") as f:
        data = json.load(f)
    ids = sorted(set([p["model"] for p in data["placements"]] + EXTRA))
    n = 0
    for mid in ids:
        src = os.path.join(CACHE, mid)
        dst = os.path.join(DEST, mid)
        if not os.path.isdir(src):
            print("missing in cache", mid)
            continue
        for dp, _, files in os.walk(src):
            for fn in files:
                s = os.path.join(dp, fn)
                d = os.path.join(dst, os.path.relpath(s, src))
                if os.path.exists(d) and os.path.getsize(d) == os.path.getsize(s):
                    continue
                os.makedirs(os.path.dirname(d), exist_ok=True)
                shutil.copy2(s, d)
                n += 1
    print("models", len(ids), "files copied", n)


if __name__ == "__main__":
    main()
