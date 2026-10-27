"""D1: the current synthesized babble without the nasal sound. What made it "fanha": the cut of the
low end (high-pass at 100-160 Hz), narrow resonances (Q 4-10) and a strong second formant around
1-3 kHz. Here: the fundamental is kept and doubled with a soft sine, wide resonances (Q 1.6-3),
the second formant halved, everything above 2.6 kHz rolled off.

usage: python tools/audio/voice_d1.py OUT_DIR   (writes D1_*.wav, and the bank godot would use)
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import synth as S  # noqa: E402

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
V = {"f": {"f0": (220, 238), "form": 1.0, "hp": 70},
     "m": {"f0": (128, 142), "form": 0.88, "hp": 55}}


def warm_syllable(i, who):
    v = V[who]
    r = np.random.default_rng(3100 + i + (500 if who == "m" else 0))
    vt = {k: (a * v["form"], b * v["form"], c * v["form"]) for k, (a, b, c) in S.VOWELS_F.items() if k in "aeou"}
    vowel = r.choice(list(vt.keys()))
    dur = r.uniform(0.085, 0.13)
    f0b = r.uniform(*v["f0"])
    f0 = S.interp_fn([(0, f0b * 1.04), (dur * 0.5, f0b), (dur + 0.05, f0b * 0.96)])
    src = S.glottal(f0, dur + 0.05, hmax=2600, tilt=2.1, jitter=0.002, shimmer=0.01)
    F = vt[vowel]
    tracks = [
        (lambda t, f=F[0]: f, 1.6, 1.0),
        (lambda t, f=F[1]: f, 2.2, 0.35),
        (lambda t, f=F[2]: f, 3.0, 0.06),
    ]
    y = S.formants(src, tracks)
    n = len(y)
    # a pure tone at the pitch underneath: warmth, the "hum" of a voice
    t = np.arange(n) / S.SR
    ph = np.cumsum([f0(tt) for tt in t]) * 2 * np.pi / S.SR
    y = y / (np.abs(y).max() + 1e-9) + 0.55 * np.sin(ph)
    y *= S.env_shape(n, [(0, 0), (0.02, 1), (dur * 0.65, 0.85), (dur + 0.05, 0)])
    # soft onset like m/n/l instead of a burst
    y = S.lp(S.hp(y, v["hp"]), 2600)
    return S.fade(y / (np.abs(y).max() + 1e-9) * 0.8, 0.004, 0.03)


def chain(sylls, step, pitch_q):
    n = len(sylls)
    out = np.zeros(int(S.SR * (n * step + 1.0)))
    tt = 0.0
    for k, y in enumerate(sylls):
        u = k / max(1, n - 1)
        f = 1.0 + 0.035 * np.sin(k * 1.7) + (0.16 * max(0, (u - 0.6) / 0.4) if pitch_q else -0.05 * max(0, (u - 0.65) / 0.35))
        idx = np.arange(0, len(y) - 1, f)
        z = np.interp(idx, np.arange(len(y)), y)
        a = int(tt * S.SR)
        out[a:a + len(z)] += z * 0.8
        tt += step * np.random.uniform(0.92, 1.12)
    return out[: int((tt + 0.25) * S.SR)]


bank = {w: [warm_syllable(i, w) for i in range(16)] for w in V}
for w in V:
    for i, y in enumerate(bank[w]):
        S.write(f"voice_{w}_warm_{i}", y)   # S.write saves into godot/assets/audio (not used by the game yet)
np.random.seed(5)
demo = {"clara": [("f", 9, False), ("f", 6, True)], "davi": [("m", 10, True)]}
import wave
for who, ls in demo.items():
    for j, (w, n, q) in enumerate(ls):
        sy = [bank[w][np.random.randint(16)] for _ in range(n)]
        y = chain(sy, 0.105, q)
        y = (y / (np.abs(y).max() + 1e-9) * 0.85 * 32767).astype(np.int16)
        with wave.open(os.path.join(OUT, f"D1_{who}_{j}.wav"), "w") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(S.SR)
            wf.writeframes(y.tobytes())
print("D1 ok")
