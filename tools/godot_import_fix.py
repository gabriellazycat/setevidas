"""Set proper import options on textures that are loaded from code (Godot cannot auto-detect them):
VRAM compression + mipmaps for 3D textures, BC5 for normal maps. Re-run after adding textures,
then run `godot --headless --path godot --import`.
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GODOT = os.path.join(ROOT, "godot")
DIRS = ["assets/textures", "assets/models/cat", "assets/models/ph", "assets/models/people", "assets/models/house", "assets/models/ghosts"]
SKIP_2D = ("assets/textures/ui",)


def patch(path):
    with open(path, encoding="utf8") as f:
        s = f.read()
    if 'importer="texture"' not in s:
        return False
    rel = os.path.relpath(path, GODOT).replace("\\", "/")
    if rel.startswith(SKIP_2D):
        return False
    is_normal = "_nor" in rel.rsplit("/", 1)[-1]
    want = {
        "compress/mode": "2",
        "compress/high_quality": "false",
        "mipmaps/generate": "true",
        "compress/normal_map": "1" if is_normal else "2",
        "detect_3d/compress_to": "0",
    }
    if "fur_strands" in rel or "furmask" in rel:
        want["compress/mode"] = "0"  # fine strands and the length mask must stay lossless
    if rel.endswith(".png.import") and "/gen/" in rel and not rel.endswith("noise.png.import"):
        # sprites with alpha: keep high quality
        want["compress/high_quality"] = "true"
    changed = False
    for k, v in want.items():
        pat = re.compile(r"^" + re.escape(k) + r"=.*$", re.M)
        line = f"{k}={v}"
        if pat.search(s):
            if pat.search(s).group(0) != line:
                s = pat.sub(line, s)
                changed = True
        else:
            s = s.replace("[params]\n", "[params]\n\n" + line + "\n", 1)
            changed = True
    if changed:
        with open(path, "w", encoding="utf8") as f:
            f.write(s)
    return changed


def main():
    n = 0
    for d in DIRS:
        for dp, _, files in os.walk(os.path.join(GODOT, d)):
            for fn in files:
                if fn.endswith(".import") and patch(os.path.join(dp, fn)):
                    n += 1
    print("patched", n)


if __name__ == "__main__":
    main()
