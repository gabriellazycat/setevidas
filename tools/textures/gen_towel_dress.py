"""Clara's towel dress texture for VRoid (template "Sleeveless Dress" = long-sleeve dress whose sleeves
are cut out by alpha). Terry cloth from towel_cream.png; everything above the armpits (bodice top,
collar, sleeves, cuffs, bow) is transparent so the dress becomes a towel wrapped from the armpits down.

usage: python tools/textures/gen_towel_dress.py [--cut 0.43]
  -> tools/vroid/towel_dress.png (load in VRoid's texture editor as a new layer, hide the others)
UV regions measured with a labelled stripe layer: bodice in the middle (u 0.265-0.735, v 0-0.52),
sleeves at the sides of the same band, skirt below v 0.52; the armholes bottom out near v 0.42.
"""
import argparse
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ap = argparse.ArgumentParser()
ap.add_argument("--cut", type=float, default=0.43)
a = ap.parse_args()
S = 1024
towel = Image.open(os.path.join(ROOT, "tools", "vroid", "towel_cream.png")).convert("RGBA")
# finer terry: the dress UV is large, tile the towel twice
tile = towel.resize((S // 2, S // 2), Image.LANCZOS)
im = Image.new("RGBA", (S, S))
for x in range(0, S, S // 2):
    for y in range(0, S, S // 2):
        im.paste(tile, (x, y))
d = ImageDraw.Draw(im)
cut = int(a.cut * S)
# the folded top edge: a slightly darker, tighter band just under the cut
band = Image.new("RGBA", (S, int(0.03 * S)), (196, 178, 152, 255))
im.alpha_composite(Image.blend(im.crop((0, cut, S, cut + band.height)), band, 0.45), (0, cut))
d.line([0, cut + band.height, S, cut + band.height], fill=(180, 160, 134, 255), width=3)
# transparent: everything above the armpits, and the sleeve/cuff columns of the top band
alpha = Image.new("L", (S, S), 255)
ad = ImageDraw.Draw(alpha)
ad.rectangle([0, 0, S, cut - 1], fill=0)
top_band = int(0.535 * S)
ad.rectangle([0, 0, int(0.265 * S), top_band], fill=0)
ad.rectangle([int(0.735 * S), 0, S, top_band], fill=0)
im.putalpha(alpha)
out = os.path.join(ROOT, "tools", "vroid", "towel_dress.png")
im.save(out)
print("saved", out)
