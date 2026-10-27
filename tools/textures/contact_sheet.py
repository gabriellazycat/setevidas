"""Download Poly Haven thumbnails for a list of asset ids and tile them into one labelled image.

usage: python contact_sheet.py out.jpg id1 id2 ...
"""
import io
import sys
import urllib.request

from PIL import Image, ImageDraw

out = sys.argv[1]
ids = sys.argv[2:]
S = 200
cols = 6
rows = (len(ids) + cols - 1) // cols
sheet = Image.new("RGB", (cols * S, rows * (S + 18)), (20, 20, 20))
draw = ImageDraw.Draw(sheet)
for i, a in enumerate(ids):
    url = f"https://cdn.polyhaven.com/asset_img/thumbs/{a}.png?width={S}&height={S}"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (sete-vidas asset tool)"})
        data = urllib.request.urlopen(req, timeout=30).read()
        im = Image.open(io.BytesIO(data)).convert("RGB")
        im.thumbnail((S, S))
    except Exception as e:  # noqa: BLE001
        im = Image.new("RGB", (S, S), (80, 0, 0))
        print("fail", a, e)
    x = (i % cols) * S
    y = (i // cols) * (S + 18)
    sheet.paste(im, (x, y))
    draw.text((x + 3, y + S + 2), a[:32], fill=(230, 230, 230))
sheet.save(out, quality=88)
print("saved", out)
