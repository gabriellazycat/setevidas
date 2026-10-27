"""The trailer's shot list: each shot is a game setup (autopilot flags) and a camera move, recorded
with tools/dev/capture.py in 16:9 (1920x1080) and 9:16 (1080x1920) into trailer/clips/<id>_<h|v>.mp4.

    python tools/dev/trailer_shots.py                 every shot, both formats
    python tools/dev/trailer_shots.py N05 N06 --fmt=v only those, only vertical
    python tools/dev/trailer_shots.py --list

A camera key is (t, pos, look[, fov][, extra dict]); fov is the 16:9 vertical fov, the 9:16 one is
widened so about the same width of the scene fits (Godot keeps the height).
"""
import json
import math
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "trailer", "clips")
CAMS = os.path.join(ROOT, "trailer", "cams")

AFT2 = ["--phase=afternoon", "--day=2"]
SHOTS = {
    # ---- afternoon (warm)
    "D01": dict(desc="sala, Clara e o gato no colo, aproxima", secs=6, frm=5, game=AFT2 + ["--scene=lap"],
                cam=[(0, (1.2, 1.55, 4.6), (2.5, 0.75, 1.6), 52), (6, (1.75, 1.3, 3.85), (2.55, 0.8, 1.65), 48)]),
    "D02": dict(desc="colo, plano médio 3/4", secs=5, frm=5, game=AFT2 + ["--scene=lap"],
                cam=[(0, (3.9, 1.0, 3.7), (2.55, 0.85, 1.65), 44), (5, (3.45, 0.95, 3.05), (2.55, 0.9, 1.7), 40)]),
    "D03": dict(desc="colo, de baixo (altura do gato)", secs=5, frm=5, game=AFT2 + ["--scene=lap"],
                cam=[(0, (3.0, 0.45, 2.75), (2.55, 1.1, 1.7), 50), (5, (2.85, 0.42, 2.55), (2.55, 1.15, 1.7), 46)]),
    "D04": dict(desc="cozinha, Clara agachada, gato comendo", secs=5, frm=5, game=AFT2 + ["--scene=bowl"],
                cam=[(0, (10.1, 0.3, 3.85), (8.65, 0.45, 4.25), 48), (5, (9.65, 0.27, 3.9), (8.65, 0.42, 4.25), 44)]),
    "D05": dict(desc="Clara chega e entra no hall", secs=7, frm=2, game=AFT2,
                cam=[(0, (6.7, 0.3, 4.6), (6.45, 1.1, 0.4), 55), (7, (6.65, 0.3, 4.2), (6.45, 1.1, 1.4), 52)]),
    "D06": dict(desc="sala de tarde, plano fixo (par com N01)", secs=4, frm=5, game=AFT2 + ["--scene=lap"],
                cam=[(0, (4.4, 1.3, 4.9), (0.5, 1.2, 2.2), 55), (4, (4.3, 1.28, 4.75), (0.5, 1.2, 2.2), 54)]),
    "D07": dict(desc="quarto de tarde, Clara deitada e o gato ronronando", secs=5, frm=5,
                game=AFT2 + ["--scene=bed"],
                cam=[(0, (2.8, 3.95, 3.7), (1.2, 3.45, 2.85), 50), (5, (2.55, 3.85, 3.45), (1.1, 3.5, 2.85), 46)]),
    # ---- night
    "N01": dict(desc="sala à noite com o Visitante na janela (par com D06)", secs=4, frm=7,
                game=["--phase=night", "--day=5", "--threat=visitor", "--stage=2", "--visitorat=sala", "--catpos=3.6,0,4.2"],
                cam=[(0, (4.4, 1.3, 4.9), (0.5, 1.2, 2.2), 55), (4, (4.3, 1.28, 4.75), (0.5, 1.2, 2.2), 54)]),
    "N02": dict(desc="Visitante na janela, aproxima devagar", secs=6, frm=7,
                game=["--phase=night", "--day=5", "--threat=visitor", "--stage=2", "--visitorat=sala", "--catpos=2.6,0,3.6"],
                cam=[(0, (1.75, 0.85, 3.3), (0.0, 1.45, 2.75), 50), (6, (1.15, 0.95, 3.0), (0.0, 1.5, 2.75), 44)]),
    "N03": dict(desc="gato de costas encarando o Visitante", secs=5, frm=7,
                game=["--phase=night", "--day=5", "--threat=visitor", "--stage=2", "--visitorat=sala", "--catpos=2.4,0,3.4"],
                cam=[(0, (3.25, 0.35, 3.65), (0.0, 1.35, 2.75), 50), (5, (3.0, 0.33, 3.55), (0.0, 1.4, 2.75), 47)]),
    "N04": dict(desc="Visitante lá fora, chuva, silhueta", secs=5, frm=7,
                game=["--phase=night", "--day=5", "--threat=visitor", "--stage=2", "--visitorat=sala", "--catpos=2.4,0,3.4"],
                cam=[(0, (-3.0, 0.6, 4.6), (-0.4, 0.9, 2.75), 50), (5, (-2.6, 0.7, 4.3), (-0.4, 0.95, 2.75), 47)]),
    "N05": dict(desc="Sombra no armário, esquenta até vermelho (push-in)", secs=8, frm=3,
                game=["--phase=night", "--day=3", "--threat=shadow", "--stage=2", "--scene=peek", "--nook=quarto_armario",
                      "--heat0=0", "--heat1=1", "--heatsecs=9", "--catat=2.6,3.6"],
                cam=[(0, (2.0, 3.4, 3.0), (3.72, 4.4, 4.69), 50, {"hand": 0.3}), (8, (2.55, 3.6, 3.6), (3.72, 4.45, 4.69), 40, {"hand": 0.3})]),
    "N06": dict(desc="Sombra surge atrás da Clara dormindo", secs=7, frm=3,
                game=["--phase=night", "--day=3", "--threat=shadow", "--stage=2", "--scene=peek", "--nook=quarto_cama",
                      "--heat0=0.05", "--heat1=0.8", "--heatsecs=8", "--catat=1.6,4.4"],
                cam=[(0, (1.05, 3.68, 3.45), (0.85, 3.45, 2.0), 50), (7, (0.95, 3.6, 3.0), (0.82, 3.5, 2.0), 44)]),
    "N07": dict(desc="da porta: gato encara a cama, olhos vermelhos", secs=5, frm=3,
                game=["--phase=night", "--day=3", "--threat=shadow", "--stage=2", "--scene=peek", "--nook=quarto_cama",
                      "--heat0=0.5", "--heat1=0.5", "--catat=1.7,4.3"],
                cam=[(0, (2.05, 3.42, 5.2), (0.85, 3.4, 2.0), 50), (5, (1.95, 3.4, 4.95), (0.85, 3.45, 2.0), 46)]),
    "N08": dict(desc="Sombra dispara no gato (jogo)", secs=12, frm=2,
                game=["--phase=night", "--day=2", "--threat=shadow", "--stage=2", "--shadowtest=2"], path=False),
    "N09a": dict(desc="Boneca longe", secs=2.5, frm=4,
                 game=["--phase=night", "--day=4", "--scene=doll", "--dollat=6.3,3.0,1.7", "--dollface=6.6,4.8"],
                 cam=[(0, (6.6, 3.25, 4.8), (6.3, 3.2, 2.0), 46), (2.5, (6.6, 3.25, 4.8), (6.3, 3.2, 2.0), 46)]),
    "N09b": dict(desc="Boneca meio caminho", secs=2.5, frm=4,
                 game=["--phase=night", "--day=4", "--scene=doll", "--dollat=6.35,3.0,2.9", "--dollface=6.6,4.8"],
                 cam=[(0, (6.6, 3.25, 4.8), (6.3, 3.2, 2.0), 46), (2.5, (6.6, 3.25, 4.8), (6.3, 3.2, 2.0), 46)]),
    "N09c": dict(desc="Boneca perto", secs=2.5, frm=4,
                 game=["--phase=night", "--day=4", "--scene=doll", "--dollat=6.45,3.0,4.0", "--dollface=6.6,4.8"],
                 cam=[(0, (6.6, 3.25, 4.8), (6.3, 3.2, 2.0), 46), (2.5, (6.6, 3.25, 4.8), (6.3, 3.2, 2.0), 46)]),
    "N10": dict(desc="Boneca close, olhos brilhando", secs=4, frm=4,
                game=["--phase=night", "--day=4", "--scene=doll", "--dollat=6.3,3.0,3.6", "--dollface=6.3,5.0"],
                cam=[(0, (6.3, 3.3, 4.45), (6.3, 3.24, 3.6), 40), (4, (6.3, 3.29, 4.3), (6.3, 3.27, 3.6), 34)]),
    "N11": dict(desc="Afogadora: braços saindo da poça", secs=6, frm=3,
                game=["--phase=night", "--day=3", "--threat=drowner", "--stage=3", "--catpos=10.3,0,7.3"],
                cam=[(0, (10.0, 0.8, 7.7), (8.8, 0.35, 8.85), 50), (6, (9.6, 0.6, 7.95), (8.8, 0.45, 8.9), 45)]),
    "N12": dict(desc="Afogadora andando (câmera segue)", secs=8, frm=3,
                game=["--phase=night", "--day=3", "--threat=drowner", "--stage=4", "--watch=drowner"], path=False),
    "N13": dict(desc="Cão (câmera segue)", secs=10, frm=4, game=["--phase=night", "--day=3", "--hound", "--watch=hound"], path=False),
    "N14": dict(desc="Sussurrador: bola com rosto sai do rádio", secs=8, frm=1.6, game=["--phase=night", "--day=2", "--orbtest"], path=False),
    "N15": dict(desc="a Coisa no porão (push-in)", secs=7, frm=4,
                game=["--phase=night", "--day=7", "--threat=thing", "--stage=2"],
                cam=[(0, (6.4, -2.3, 7.6), (3.6, -2.4, 4.4), 50, {"hand": 0.3}), (7, (5.4, -2.5, 6.6), (3.6, -2.3, 4.4), 44, {"hand": 0.3})]),
    "N16": dict(desc="ritual da noite 7", secs=8, frm=3, game=["--phase=night", "--day=7", "--ritualtest"], path=False),
    "N17": dict(desc="casa de noite, de fora (poste, chuva)", secs=6, frm=4, game=["--phase=night", "--day=1"],
                cam=[(0, (-6.5, 1.6, -5.0), (6.0, 3.0, 5.0), 50), (6, (-5.6, 1.5, -4.2), (6.0, 3.0, 5.0), 48)]),
    "D08": dict(desc="casa de tarde, de fora (par com N17)", secs=6, frm=4, game=AFT2,
                cam=[(0, (-6.5, 1.6, -5.0), (6.0, 3.0, 5.0), 50), (6, (-5.6, 1.5, -4.2), (6.0, 3.0, 5.0), 48)]),
    "N19": dict(desc="Cão vem pelo corredor, devagar", secs=6, frm=2,
                game=["--phase=night", "--day=3", "--scene=hound", "--houndat=6.3,3.0,9.3", "--houndyaw=180", "--houndspeed=0.6",
                      "--houndsnarl=0.5", "--catpos=6.6,3,2.6"],
                cam=[(0, (6.45, 3.28, 3.7), (6.3, 3.45, 8.0), 46), (6, (6.45, 3.26, 3.5), (6.3, 3.4, 7.0), 42)]),
    "N20": dict(desc="Cão dispara na câmera", secs=3, frm=2,
                game=["--phase=night", "--day=3", "--scene=hound", "--houndat=6.3,3.0,9.4", "--houndyaw=180", "--houndspeed=2.6",
                      "--houndsnarl=1", "--catpos=6.6,3,2.6"],
                cam=[(0, (6.45, 3.25, 3.4), (6.3, 3.4, 8.0), 48, {"hand": 0.6}), (3, (6.45, 3.25, 3.3), (6.3, 3.4, 6.0), 48, {"hand": 0.6})]),
    "N18": dict(desc="quarto à noite, Clara dorme, gato enrolado", secs=5, frm=5,
                game=["--phase=night", "--day=2", "--scene=bed"],
                cam=[(0, (2.8, 3.95, 3.7), (1.2, 3.45, 2.85), 50), (5, (2.55, 3.85, 3.45), (1.1, 3.5, 2.85), 46)]),
}


def v_fov(f):
    """9:16 vertical fov that shows the width of a 16:9 frame narrowed to 60%"""
    h = 2 * math.atan(math.tan(math.radians(f) / 2) * 16 / 9)
    return min(95.0, math.degrees(2 * math.atan(math.tan(h * 0.6 / 2) * 16 / 9)))


def cam_file(sid, fmt, keys):
    out = []
    for k in keys:
        t, pos, look = k[0], k[1], k[2]
        fov = k[3] if len(k) > 3 else 50
        d = {"t": t, "pos": list(pos), "look": list(look), "fov": fov if fmt == "h" else v_fov(fov)}
        if len(k) > 4:
            d.update(k[4])
        out.append(d)
    os.makedirs(CAMS, exist_ok=True)
    p = os.path.join(CAMS, "%s_%s.json" % (sid, fmt))
    with open(p, "w") as f:
        json.dump({"keys": out}, f, indent=1)
    return p


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = dict((a[2:].split("=", 1) + ["1"])[:2] for a in sys.argv[1:] if a.startswith("--"))
    if "list" in opts:
        for k, s in SHOTS.items():
            print(k, s["desc"])
        return
    fmts = {"h": ["h"], "v": ["v"]}.get(opts.get("fmt", "both"), ["h", "v"])
    ids = args or list(SHOTS)
    os.makedirs(OUT, exist_ok=True)
    for sid in ids:
        s = SHOTS[sid]
        for fmt in fmts:
            out = os.path.join(OUT, "%s_%s.mp4" % (sid, fmt))
            if os.path.exists(out) and "redo" not in opts:
                print("skip", out)
                continue
            cmd = [sys.executable, os.path.join(ROOT, "tools", "dev", "capture.py"), out,
                   "--size=" + ("1920x1080" if fmt == "h" else "1080x1920"), "--secs=%g" % s["secs"], "--from=%g" % s["frm"]]
            if s.get("path", True):
                cmd.append("--path=" + cam_file(sid, fmt, s["cam"]))
            cmd += ["--"] + s["game"]
            r = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
            print(sid, fmt, (r.stdout.strip().splitlines() or ["?"])[-1], r.stderr.strip()[-300:])


if __name__ == "__main__":
    main()
