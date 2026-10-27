"""Shrinks screenshots for review: python tools/dev/shrink.py OUT.png W IN1.png [IN2.png ...]
One input: resized to width W. Several: a grid (up to 4 per row, --cols=N) of width W.
--crop=x0,y0,x1,y1 (fractions 0..1) crops every input first."""
import sys
from PIL import Image

args = [a for a in sys.argv[1:] if not a.startswith("--")]
opts = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--"))
out, w, ins = args[0], int(args[1]), args[2:]
ims = [Image.open(p).convert("RGB") for p in ins]
if "crop" in opts:
    c = [float(v) for v in opts["crop"].split(",")]
    ims = [im.crop((int(c[0] * im.width), int(c[1] * im.height), int(c[2] * im.width), int(c[3] * im.height))) for im in ims]
cols = min(int(opts.get("cols", 4)), len(ims))
rows = (len(ims) + cols - 1) // cols
cw = w // cols
ch = int(ims[0].height * cw / ims[0].width)
sheet = Image.new("RGB", (cw * cols, ch * rows))
for i, im in enumerate(ims):
    sheet.paste(im.resize((cw, ch), Image.LANCZOS), ((i % cols) * cw, (i // cols) * ch))
sheet.save(out)
