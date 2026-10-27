"""Records one trailer shot with Godot's Movie Maker and cuts it to an MP4.

    python tools/dev/capture.py OUT.mp4 --size=1920x1080 --secs=6 --from=4 --path=CAM.json -- <game args>

--size     frame size; a temporary godot/override.cfg sets the window to it (Movie Maker keeps the
           size the window had at start) and is removed afterwards
--secs     length of the shot (the camera move's seconds)
--from     game time at which the camera move (and the shot) starts
--path     camera move JSON (autopilot --campath); without it the game camera is recorded
--fps      default 30
--keep     keep the raw AVI next to the MP4
Everything after "--" goes to the game (autopilot flags: --phase, --day, --threat...). --nohud is
always on. Game audio is kept (AAC). Never writes the save (dev args).
"""
import os
import re
import subprocess
import sys
import tempfile

GODOT = r"C:\Users\gabri\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PROJ = os.path.join(ROOT, "godot")


def main() -> int:
    argv = sys.argv[1:]
    game = []
    if "--" in argv:
        i = argv.index("--")
        argv, game = argv[:i], argv[i + 1:]
    out = [a for a in argv if not a.startswith("--")][0]
    opts = dict(a[2:].split("=", 1) if "=" in a else (a[2:], "1") for a in argv if a.startswith("--"))
    w, h = (int(v) for v in opts.get("size", "1920x1080").split("x"))
    secs = float(opts.get("secs", "6"))
    t0 = float(opts.get("from", "3"))
    fps = int(opts.get("fps", "30"))
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    avi = os.path.splitext(os.path.abspath(out))[0] + ".avi" if "keep" in opts else os.path.join(tempfile.gettempdir(), "sv_capture_%d.avi" % os.getpid())
    override = os.path.join(PROJ, "override.cfg")
    if os.path.exists(override):
        print("godot/override.cfg already exists; not touching it", file=sys.stderr)
        return 1
    with open(override, "w") as f:
        f.write("[display]\n\nwindow/size/viewport_width=%d\nwindow/size/viewport_height=%d\n" % (w, h))
    cmd = [GODOT, "--path", PROJ, "--write-movie", avi, "--fixed-fps", str(fps), "--", "--nohud",
           "--camfrom=%g" % t0, "--camsecs=%g" % secs]
    if "path" in opts:
        cmd.append("--campath=" + os.path.abspath(opts["path"]))
    else:
        cmd.append("--campath=none")
    cmd += game
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, errors="replace", timeout=1800)
    finally:
        os.remove(override)
    m0 = re.search(r"CAMSTART frame=(\d+)", r.stdout)
    m1 = re.search(r"CAMEND frame=(\d+)", r.stdout)
    if not m0 or not m1:
        print(r.stdout[-3000:], r.stderr[-3000:], sep="\n")
        print("CAPTURE FAIL: no CAMSTART/CAMEND", file=sys.stderr)
        return 1
    f0, f1 = int(m0.group(1)), int(m1.group(1))
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", "%.4f" % (f0 / fps), "-i", avi, "-t", "%.4f" % ((f1 - f0) / fps),
                    "-c:v", "libx264", "-crf", "14", "-preset", "slow", "-pix_fmt", "yuv420p",
                    "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-movflags", "+faststart", out], check=True)
    if "keep" not in opts:
        os.remove(avi)
    print("CAPTURE OK %s frames %d-%d (%.2f s)" % (out, f0, f1, (f1 - f0) / fps))
    return 0


if __name__ == "__main__":
    sys.exit(main())
