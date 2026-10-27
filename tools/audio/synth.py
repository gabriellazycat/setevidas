"""Offline sound design for Sete Vidas: every sound effect, ambience loop and music element is
synthesised here (numpy + scipy) and written as WAV into godot/assets/audio.

Techniques: additive glottal sources through time-varying formant filters (cat, people, ghosts),
stick-slip friction into wood resonator banks (creaks), modal synthesis (bells, porcelain, glass,
knocks, piano), shaped and filtered noise (rain, wind, hiss, water), seamless crossfaded loops.

usage: python tools/audio/synth.py [name-filter]
"""
import math
import os
import sys
import wave

import numpy as np
from scipy import signal

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "godot", "assets", "audio")
rng = np.random.default_rng(7)
FILTER = sys.argv[1] if len(sys.argv) > 1 else ""


# ---------------------------------------------------------------------- utilities


def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def white(n):
    return rng.uniform(-1, 1, n)


def pink(n):
    b, a = [0.049922035, -0.095993537, 0.050612699, -0.004408786], [1, -2.494956002, 2.017265875, -0.522189400]
    x = signal.lfilter(b, a, white(n + 2000))[2000:]
    return x / (np.abs(x).max() + 1e-9)


def brown(n):
    x = signal.lfilter([1.0], [1.0, -0.995], white(n + 4000))[4000:]
    x -= signal.lfilter([1.0], [1.0, -0.9995], x)
    return x / (np.abs(x).max() + 1e-9)


def bp(x, lo, hi, order=2):
    sos = signal.butter(order, [max(10, lo), min(SR / 2 - 100, hi)], "bandpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lp(x, f, order=2):
    sos = signal.butter(order, min(SR / 2 - 100, f), "lowpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def hp(x, f, order=2):
    sos = signal.butter(order, max(10, f), "highpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def peak_bank(x, freqs, qs, gains=None):
    """parallel resonant band-pass filters (modes of a body)."""
    y = np.zeros_like(x)
    for i, f in enumerate(freqs):
        if f >= SR / 2 - 200:
            continue
        q = qs[i] if hasattr(qs, "__len__") else qs
        b, a = signal.iirpeak(f, q, fs=SR)
        g = gains[i] if gains is not None else 1.0
        y += g * signal.lfilter(b, a, x)
    return y


def tv_bandpass(x, f_fn, q_fn, block=128):
    """time-varying RBJ band-pass (constant peak gain) with carried state."""
    y = np.zeros_like(x)
    zi = np.zeros(2)
    n = len(x)
    for s in range(0, n, block):
        e = min(n, s + block)
        tt = s / SR
        f = float(np.clip(f_fn(tt), 30, SR / 2 - 500))
        q = float(q_fn(tt))
        w0 = 2 * math.pi * f / SR
        alpha = math.sin(w0) / (2 * q)
        b = np.array([alpha, 0, -alpha]) / (1 + alpha)
        a = np.array([1, -2 * math.cos(w0) / (1 + alpha), (1 - alpha) / (1 + alpha)])
        y[s:e], zi = signal.lfilter(b, a, x[s:e], zi=zi)
    return y


def formants(x, tracks, block=128):
    """tracks: list of (freq_fn, bw_hz_fn or q, gain) -> sum of time-varying resonators."""
    y = np.zeros_like(x)
    for f_fn, q, g in tracks:
        qf = q if callable(q) else (lambda _t, q=q: q)
        y += g * tv_bandpass(x, f_fn, qf, block)
    return y


def interp_fn(points):
    """piecewise-linear function from [(t, v), ...]"""
    ts = np.array([p[0] for p in points])
    vs = np.array([p[1] for p in points])
    return lambda t: float(np.interp(t, ts, vs))


def env_ar(n, a, r, curve=3.0):
    """attack seconds, release (exp) to the end."""
    t = np.arange(n) / SR
    e = np.minimum(1.0, t / max(1e-4, a))
    rel = np.exp(-np.maximum(0.0, t - a) * curve / max(1e-3, r))
    return e * rel


def env_shape(n, points):
    t = np.arange(n) / SR
    return np.interp(t, [p[0] for p in points], [p[1] for p in points])


def glottal(f0_fn, dur, hmax=9000, tilt=1.25, jitter=0.004, shimmer=0.03):
    """band-limited pulse source from a pitch contour (additive, phase accumulated)."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    f0 = np.array([f0_fn(x) for x in t[::64]])
    f0 = np.interp(t, t[::64], f0)
    if jitter > 0:
        f0 = f0 * (1 + jitter * lp(white(n), 40) * 6)
    phase = 2 * np.pi * np.cumsum(f0) / SR
    y = np.zeros(n)
    kmax = int(hmax / max(60.0, f0.min()))
    for k in range(1, max(2, kmax)):
        amp = 1.0 / k ** tilt
        mask = (k * f0 < hmax).astype(float)
        y += amp * mask * np.sin(k * phase)
    if shimmer > 0:
        y *= 1 + shimmer * lp(white(n), 30) * 5
    return y


def fade(x, a=0.003, r=0.01):
    n = len(x)
    ai, ri = int(a * SR), int(r * SR)
    if ai > 0:
        x[:ai] *= np.linspace(0, 1, ai)
    if ri > 0:
        x[-ri:] *= np.linspace(1, 0, ri)
    return x


def norm(x, peak=0.89):
    m = np.abs(x).max()
    return x * (peak / m) if m > 1e-9 else x


def loopify(x, xf=0.6):
    """crossfade the tail into the head so the file loops seamlessly."""
    n = int(xf * SR)
    if x.ndim == 1:
        head, tail = x[:n].copy(), x[-n:].copy()
        w = np.linspace(0, 1, n)
        out = x[n:].copy()
        out[-n:] = tail * (1 - w) + head * w
        return out
    return np.stack([loopify(x[:, c], xf) for c in range(x.shape[1])], axis=1)


def reverb(x, dur=1.6, decay=3.0, wet=0.3, tone=5000, seed=1):
    r = np.random.default_rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    ir = r.uniform(-1, 1, n) * np.exp(-t * decay / dur * 2.3)
    ir = lp(ir, tone)
    ir[: int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))
    ir /= np.sqrt((ir ** 2).sum()) + 1e-9
    if x.ndim == 1:
        y = signal.fftconvolve(x, ir)
        y = np.pad(y, (0, len(x) + n - len(y)))
        dry = np.pad(x, (0, n))
        return dry * (1 - wet) + y * wet * 3
    return np.stack([reverb(x[:, c], dur, decay, wet, tone, seed + c) for c in range(x.shape[1])], axis=1)


def pad_to(x, dur):
    n = int(dur * SR)
    if len(x) >= n:
        return x[:n]
    return np.pad(x, (0, n - len(x)) if x.ndim == 1 else ((0, n - len(x)), (0, 0)))


def mix_at(dst, src, at):
    i = int(at * SR)
    e = min(len(dst), i + len(src))
    if e > i:
        dst[i:e] += src[: e - i]
    return dst


import importlib.util as _ilu
_spec = _ilu.spec_from_file_location("import_cc0", os.path.join(os.path.dirname(os.path.abspath(__file__)), "import_cc0.py"))
_cc0 = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(_cc0)
CC0_NAMES = set(_cc0.MAP.keys())


def write(name, x, peak=0.89, stereo=False):
    if FILTER and FILTER not in name:
        return
    # recorded CC0 sounds replace these (tools/audio/import_cc0.py): never overwrite them
    if name in CC0_NAMES:
        return
    os.makedirs(OUT, exist_ok=True)
    x = np.nan_to_num(x)
    x = norm(x, peak)
    data = np.clip(x, -1, 1)
    ch = 2 if data.ndim == 2 else 1
    pcm = (data * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"{name}.wav  {len(data) / SR:.2f}s")


def stereo_width(x, amount=0.6, delay_ms=11, seed=0):
    """mono -> stereo with a decorrelated side channel."""
    d = int(delay_ms * SR / 1000)
    side = np.roll(hp(x, 300), d) * amount
    return np.stack([x + side, x - side], axis=1)


# ---------------------------------------------------------------------- the cat


def meow(i):
    r = np.random.default_rng(100 + i)
    dur = r.uniform(0.55, 0.95)
    base = r.uniform(520, 640)
    peak = base * r.uniform(1.25, 1.5)
    end = base * r.uniform(0.62, 0.8)
    f0 = interp_fn([(0, base * 0.9), (dur * 0.25, peak), (dur * 0.55, peak * 0.96), (dur, end)])
    vib = lambda t: f0(t) * (1 + 0.012 * math.sin(2 * math.pi * 5.5 * t))
    src = glottal(vib, dur, hmax=10000, tilt=1.15, jitter=0.006)
    src += 0.06 * white(len(src))
    # "m" -> "i" -> "a" -> "u": formants of a small vocal tract
    f1 = interp_fn([(0, 500), (dur * 0.15, 900), (dur * 0.45, 1400), (dur * 0.8, 950), (dur, 700)])
    f2 = interp_fn([(0, 1800), (dur * 0.15, 2600), (dur * 0.45, 2100), (dur * 0.8, 1500), (dur, 1200)])
    f3 = interp_fn([(0, 3800), (dur * 0.5, 4300), (dur, 3600)])
    y = formants(src, [(f1, 4.0, 1.0), (f2, 6.0, 0.55), (f3, 8.0, 0.25)])
    y = hp(y, 250)
    n = len(y)
    e = env_shape(n, [(0, 0), (0.04, 0.5), (0.12, 1), (dur * 0.7, 0.85), (dur, 0)])
    return fade(y * e)


def mrrp(i):
    """the short trilled greeting (used while purring)."""
    r = np.random.default_rng(200 + i)
    dur = 0.32
    f0 = interp_fn([(0, 420), (0.12, 560), (dur, 480)])
    src = glottal(f0, dur, hmax=8000, tilt=1.3)
    n = len(src)
    t = np.arange(n) / SR
    src *= 0.55 + 0.45 * np.sign(np.sin(2 * np.pi * 26 * t)) * (t < 0.14)
    y = formants(src, [(interp_fn([(0, 600), (dur, 1000)]), 4.0, 1.0), (interp_fn([(0, 1900), (dur, 2300)]), 6.0, 0.5)])
    return fade(hp(y, 200) * env_shape(n, [(0, 0), (0.03, 1), (dur * 0.7, 0.8), (dur, 0)]))


def hiss(strong, i):
    r = np.random.default_rng(300 + i)
    dur = 0.85 if strong else 0.55
    n = int(dur * SR)
    x = white(n)
    y = bp(x, 2600, 10500, 3) * 1.0 + bp(x, 1200, 2600) * 0.25
    # spit at the start
    if strong:
        sp = int(0.04 * SR)
        y[:sp] += bp(white(sp), 400, 6000) * 2.0 * np.linspace(1, 0, sp)
    e = env_shape(n, [(0, 0), (0.015, 1.0), (0.12 if strong else 0.08, 0.9), (dur, 0)]) ** 1.4
    if not strong:
        e *= 0.6
        y = lp(y, 7000)
    y *= 1 + 0.15 * np.sin(2 * np.pi * r.uniform(9, 14) * np.arange(n) / SR)
    return fade(y * e)


def purr_loop():
    cycles = []
    total = 0.0
    r = np.random.default_rng(5)
    for k in range(4):
        for inhale in (True, False):
            dur = r.uniform(0.95, 1.2) if inhale else r.uniform(1.15, 1.45)
            n = int(dur * SR)
            t = np.arange(n) / SR
            rate = 22.0 if inhale else 26.0
            ph = (t * rate) % 1.0
            pulses = np.exp(-ph * 9.0)
            body = lp(white(n), 420) * 1.0 + lp(white(n), 160) * 1.4
            tone = np.sin(2 * np.pi * rate * t) * 0.3
            seg = (body + tone) * pulses
            seg *= env_shape(n, [(0, 0.15), (0.12, 1.0), (dur - 0.15, 0.95), (dur, 0.15)]) * (0.65 if inhale else 1.0)
            cycles.append(seg)
            total += dur
    y = np.concatenate(cycles)
    y = lp(y, 900) + 0.15 * bp(y, 900, 2500)
    return loopify(y, 0.15)


def cat_cry():
    dur = 0.95
    f0 = interp_fn([(0, 700), (0.12, 1150), (0.5, 1050), (dur, 600)])
    src = glottal(lambda t: f0(t) * (1 + 0.03 * math.sin(2 * math.pi * 11 * t)), dur, hmax=11000, tilt=0.95, jitter=0.02, shimmer=0.1)
    src = np.tanh(src * 2.5)
    y = formants(src, [(interp_fn([(0, 900), (0.3, 1500), (dur, 900)]), 3.0, 1.0), (lambda t: 2500, 5.0, 0.6), (lambda t: 4200, 6.0, 0.35)])
    y += 0.12 * bp(white(len(y)), 2000, 8000)
    return fade(hp(y, 300) * env_shape(len(y), [(0, 0), (0.03, 1), (0.6, 0.85), (dur, 0)]))


def paw(surface, run, i):
    r = np.random.default_rng(400 + i + (50 if run else 0) + hash(surface) % 97)
    dur = 0.09
    n = int(dur * SR)
    x = white(n) * np.exp(-np.arange(n) / SR * (70 if run else 110))
    if surface == "wood":
        y = bp(x, 150, 1400) + peak_bank(x, [r.uniform(170, 230), r.uniform(420, 520)], 12, [0.6, 0.3])
    elif surface == "tile":
        y = bp(x, 900, 6000) * 0.8 + peak_bank(x, [r.uniform(2400, 3000)], 20, [0.4])
    elif surface == "carpet":
        y = lp(x, 700)
    else:
        y = bp(x, 400, 4000) + 0.4 * bp(white(n) * (rng.uniform(0, 1, n) > 0.92), 2000, 7000) * np.exp(-np.arange(n) / SR * 60)
    y = fade(y, 0.001, 0.02)
    if run:
        y = np.concatenate([y * 0.7, np.zeros(int(0.025 * SR)), y])
    return y


# ---------------------------------------------------------------------- people


def human_step(i, creak=False):
    r = np.random.default_rng(500 + i)
    dur = 0.32
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = r.uniform(65, 95)
    thump = np.sin(2 * np.pi * f * t * (1 - 0.25 * t)) * np.exp(-t * 28)
    tr = bp(white(n), 250, 2200) * np.exp(-t * 60) * 0.5
    board = peak_bank(white(n) * np.exp(-t * 90), [r.uniform(140, 190), r.uniform(330, 420), r.uniform(780, 900)], [10, 14, 18], [0.5, 0.3, 0.12])
    y = thump + tr + board
    # toe roll
    y = mix_at(y, (bp(white(int(0.08 * SR)), 200, 1500) * np.exp(-np.arange(int(0.08 * SR)) / SR * 50)) * 0.25, 0.09)
    if creak:
        c = creak_sound(700 + i, 0.5, (240, 420), 0.4)
        y = mix_at(np.pad(y, (0, int(0.6 * SR))), c * 0.5, 0.05)
    return fade(lp(y, 5000), 0.001, 0.03)


VOWELS_F = {"a": (850, 1500, 2900), "e": (580, 2050, 2900), "i": (360, 2500, 3300), "o": (560, 950, 2700), "u": (380, 850, 2600), "ã": (700, 1350, 2700)}
VOWELS_M = {k: (v[0] * 0.84, v[1] * 0.86, v[2] * 0.88) for k, v in VOWELS_F.items()}
CONS = ["t", "k", "p", "s", "m", "n", "d", "v", "l", "ʃ"]


# soft "game language" syllables (the kind Animal Crossing / Undertale use): a short voiced vowel
# with a gentle attack, mostly soft consonants (m n l v) and only a hint of t/k/p/s, low-passed so
# nothing buzzes. Clara: warm mezzo, a little breath; Davi: a young tenor (not an old man).
SOFT_CONS = ["m", "n", "l", "v", "m", "n", "l", "d", "t", "k", "s", "b"]
VOICES = {
    "f": {"f0": (218, 236), "tilt": 1.75, "breath": 0.07, "hmax": 4200, "lp": 4300, "hp": 160, "form": 1.0},
    "m": {"f0": (142, 156), "tilt": 1.8, "breath": 0.05, "hmax": 3600, "lp": 3800, "hp": 100, "form": 0.88},
}


def soft_syllable(i, who):
    v = VOICES[who]
    r = np.random.default_rng(1600 + i + (300 if who == "m" else 0))
    vtab = {k: (a * v["form"], b * v["form"], c * v["form"]) for k, (a, b, c) in VOWELS_F.items()}
    vowel = r.choice(list(vtab.keys()))
    c = r.choice(SOFT_CONS)
    dur = r.uniform(0.09, 0.15)
    f0b = r.uniform(*v["f0"])
    # a tiny glide down inside the syllable and a soft vibrato read as a friendly voice
    f0 = interp_fn([(0, f0b * 1.03), (dur * 0.6, f0b), (dur + 0.05, f0b * 0.97)])
    src = glottal(f0, dur + 0.05, hmax=v["hmax"], tilt=v["tilt"], jitter=0.004, shimmer=0.02)
    src = src + lp(white(len(src)), 3000) * v["breath"]
    F = vtab[vowel]
    nxt = vtab[r.choice(list(vtab.keys()))]
    tracks = [
        (interp_fn([(0, F[0]), (dur, (F[0] * 3 + nxt[0]) / 4)]), 4.0, 1.0),
        (interp_fn([(0, F[1]), (dur, (F[1] * 3 + nxt[1]) / 4)]), 7.0, 0.45),
        (lambda t, f=F[2]: f, 10.0, 0.12),
    ]
    y = formants(src, tracks)
    n = len(y)
    y *= env_shape(n, [(0, 0), (0.018, 1), (dur * 0.7, 0.8), (dur + 0.05, 0)])
    cn = int(0.03 * SR)
    if c in ("m", "n", "l", "v", "b", "d"):
        burst = lp(glottal(lambda t: f0b, cn / SR, hmax=700, tilt=2.0) * 0.35, 450)[:cn]
        burst *= env_shape(len(burst), [(0, 0), (0.006, 1), (len(burst) / SR, 0.6)])
    elif c == "s":
        burst = bp(white(cn), 4000, 7500) * env_shape(cn, [(0, 0), (0.01, 1), (cn / SR, 0)]) * 0.12
    else:
        burst = bp(white(cn // 3), 1200, 4000) * np.exp(-np.arange(cn // 3) / SR * 200) * 0.15
    y = np.concatenate([burst, y])
    y = lp(hp(y, v["hp"]), v["lp"])
    return fade(y / (np.max(np.abs(y)) + 1e-9) * 0.8, 0.003, 0.03)


def syllable(i, male, whisper=False):
    r = np.random.default_rng(600 + i + (300 if male else 0) + (900 if whisper else 0))
    vtab = VOWELS_M if male else VOWELS_F
    v = r.choice(list(vtab.keys()))
    c = r.choice(CONS)
    dur = r.uniform(0.11, 0.2)
    f0b = (r.uniform(118, 138) if male else r.uniform(205, 245))
    f0 = interp_fn([(0, f0b * 1.04), (dur, f0b * r.uniform(0.9, 1.06))])
    src = glottal(f0, dur + 0.04, hmax=6000, tilt=1.45 if male else 1.35, jitter=0.008)
    if whisper:
        src = white(len(src)) * 0.6
    F = vtab[v]
    nxt = vtab[r.choice(list(vtab.keys()))]
    tracks = [
        (interp_fn([(0, F[0]), (dur, (F[0] * 2 + nxt[0]) / 3)]), 5.0, 1.0),
        (interp_fn([(0, F[1]), (dur, (F[1] * 2 + nxt[1]) / 3)]), 9.0, 0.5),
        (lambda t, f=F[2]: f, 12.0, 0.25),
    ]
    y = formants(src, tracks)
    n = len(y)
    y *= env_shape(n, [(0, 0), (0.025, 1), (dur * 0.75, 0.85), (dur + 0.04, 0)])
    # consonant onset
    cn = int(0.035 * SR)
    if c in ("s", "ʃ"):
        burst = bp(white(cn * 2), 3500 if c == "s" else 2000, 9000 if c == "s" else 5000) * env_shape(cn * 2, [(0, 0), (0.02, 1), (cn * 2 / SR, 0)]) * 0.5
    elif c in ("m", "n", "l", "v"):
        burst = lp(glottal(lambda t: f0b, cn / SR * 1.5, hmax=900) * 0.4, 500)[: int(cn * 1.5)]
        if whisper:
            burst *= 0.1
    else:
        burst = bp(white(cn // 2), 1500, 6000) * np.exp(-np.arange(cn // 2) / SR * 120) * 0.6
    y = np.concatenate([burst * (0.6 if whisper else 1.0), y])
    return fade(hp(y, 90 if male else 140), 0.002, 0.02)


def giggle(i):
    r = np.random.default_rng(700 + i)
    parts = []
    k = r.integers(3, 6)
    for j in range(k):
        dur = r.uniform(0.07, 0.11)
        base = r.uniform(390, 460) * (1 - j * 0.035)
        src = glottal(interp_fn([(0, base * 1.1), (dur, base)]), dur, hmax=8000, tilt=1.2) * 0.8 + white(int(dur * SR)) * 0.25
        y = formants(src, [(lambda t: 380, 5.0, 1.0), (lambda t: 2700, 8.0, 0.6), (lambda t: 3500, 10.0, 0.3)])
        h = bp(white(int(0.05 * SR)), 1500, 6000) * np.exp(-np.arange(int(0.05 * SR)) / SR * 50) * 0.4
        y = np.concatenate([h, y * env_shape(len(y), [(0, 0), (0.01, 1), (dur, 0)])])
        parts.append(y)
        parts.append(np.zeros(int(r.uniform(0.05, 0.09) * SR)))
    y = np.concatenate(parts)
    return fade(hp(y, 200))


# ---------------------------------------------------------------------- house


def creak_sound(seed, dur, pitch=(90, 260), roughness=0.5, modes=None):
    r = np.random.default_rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    # the friction pitch wanders: slow curve + jitter
    k = r.uniform(0.6, 1.4)
    curve = pitch[0] + (pitch[1] - pitch[0]) * (0.5 + 0.5 * np.sin(2 * np.pi * t / dur * k + r.uniform(0, 6)))
    curve *= 1 + 0.25 * lp(white(n), 6) * 8
    curve = np.clip(curve, 30, 900)
    ph = np.cumsum(curve / SR)
    idx = np.where(np.diff(np.floor(ph)) > 0)[0]
    exc = np.zeros(n)
    amps = 0.4 + 0.6 * np.abs(lp(white(n), 3) * 10)
    for j in idx:
        if r.random() < 0.94:
            exc[j] = amps[j] * (0.7 + 0.6 * r.random())
    exc += roughness * 0.02 * white(n)
    modes = modes or [r.uniform(280, 360), r.uniform(650, 800), r.uniform(1150, 1400), r.uniform(2000, 2400), r.uniform(3100, 3600)]
    y = peak_bank(exc, modes, [18, 24, 28, 30, 32], [1.0, 0.8, 0.5, 0.3, 0.15])
    y = hp(y, 120)
    e = env_shape(n, [(0, 0), (0.06, 1), (dur * 0.6, 0.8), (dur, 0)])
    return fade(y * e)


def thud(i, low=70):
    r = np.random.default_rng(800 + i)
    dur = 0.55
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = low * r.uniform(0.9, 1.1)
    y = np.sin(2 * np.pi * f * t * (1 - 0.35 * t)) * np.exp(-t * 14)
    y += lp(white(n), 380) * np.exp(-t * 22) * 0.8
    y += peak_bank(white(n) * np.exp(-t * 60), [f * 2.3, f * 4.1, f * 6.7], 8, [0.4, 0.2, 0.1])
    return fade(y, 0.001, 0.05)


def click(i):
    r = np.random.default_rng(900 + i)
    n = int(0.09 * SR)
    t = np.arange(n) / SR
    imp = np.zeros(n)
    imp[0] = 1.0
    imp[int(0.004 * SR)] = -0.6
    y = peak_bank(imp, [r.uniform(2800, 3500), r.uniform(1100, 1400), r.uniform(5200, 6500)], [12, 8, 15], [1.0, 0.6, 0.3])
    y += bp(white(n), 2000, 9000) * np.exp(-t * 400) * 0.3
    return fade(y * np.exp(-t * 35), 0.0005, 0.01)


def knock(i):
    r = np.random.default_rng(1000 + i)
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    exc = bp(white(n), 300, 5000) * np.exp(-t * 300)
    y = peak_bank(exc, [r.uniform(120, 150), r.uniform(240, 290), r.uniform(390, 450), r.uniform(700, 820), r.uniform(1300, 1500)], [7, 9, 11, 13, 15], [1.0, 0.8, 0.6, 0.35, 0.2])
    y += exc * 0.4
    return fade(y * np.exp(-t * 12), 0.0005, 0.03)


def glass(i):
    r = np.random.default_rng(1100 + i)
    dur = 1.6
    n = int(dur * SR)
    y = np.zeros(n)
    y = mix_at(y, bp(white(int(0.06 * SR)), 1500, 12000) * np.exp(-np.arange(int(0.06 * SR)) / SR * 50) * 1.2, 0)
    for j in range(60):
        at = r.exponential(0.12) if j < 40 else r.uniform(0.2, 1.1)
        f = r.uniform(2200, 9500)
        d = r.uniform(0.03, 0.18)
        m = int(d * SR)
        tt = np.arange(m) / SR
        ping = np.sin(2 * np.pi * f * tt + r.uniform(0, 6)) * np.exp(-tt / d * 4) * r.uniform(0.1, 0.5)
        ping += np.sin(2 * np.pi * f * 1.48 * tt) * np.exp(-tt / d * 6) * 0.2
        y = mix_at(y, ping * (1 - min(1, at)) ** 0.5, min(dur - d, at))
    return fade(hp(y, 900), 0.0005, 0.05)


def drip(i):
    r = np.random.default_rng(1200 + i)
    n = int(0.18 * SR)
    t = np.arange(n) / SR
    f0 = r.uniform(700, 1100)
    f = f0 * (1 + 1.4 * (1 - np.exp(-t / 0.012)))
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.sin(ph) * np.exp(-t * 38)
    y += bp(white(n), 2000, 8000) * np.exp(-t * 600) * 0.3
    return fade(y, 0.0005, 0.02)


def porcelain(i):
    r = np.random.default_rng(1300 + i)
    dur = 0.9
    n = int(dur * SR)
    t = np.arange(n) / SR
    base = r.uniform(1900, 2400)
    y = np.zeros(n)
    for ratio, amp, dec in ((1, 1, 6), (1.62, 0.6, 8), (2.71, 0.45, 11), (3.98, 0.25, 15), (5.4, 0.15, 20)):
        y += amp * np.sin(2 * np.pi * base * ratio * t + r.uniform(0, 6)) * np.exp(-t * dec)
    hit2 = int(r.uniform(0.06, 0.11) * SR)
    y[hit2:] += 0.35 * y[: n - hit2]
    y += bp(white(n), 3000, 10000) * np.exp(-t * 200) * 0.4
    return fade(y, 0.0005, 0.05)


def bell():
    dur = 5.5
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 196.0
    y = np.zeros(n)
    for ratio, amp, dec in ((0.5, 0.5, 0.5), (1.0, 1.0, 0.8), (1.19, 0.5, 1.1), (1.56, 0.4, 1.3), (2.0, 0.55, 1.4), (2.51, 0.3, 2.0), (2.66, 0.25, 2.2), (3.01, 0.2, 2.6), (4.1, 0.12, 3.5)):
        beat = 1 + 0.004 * np.sin(2 * np.pi * 1.3 * t * ratio)
        y += amp * np.sin(2 * np.pi * f * ratio * beat * t) * np.exp(-t * dec)
    y += bp(white(n), 800, 4000) * np.exp(-t * 120) * 0.25
    return fade(y, 0.001, 0.2)


def tick(tock=False):
    n = int(0.06 * SR)
    t = np.arange(n) / SR
    imp = np.zeros(n)
    imp[0] = 1
    y = peak_bank(imp, [2300 if not tock else 1700, 4100 if not tock else 3300, 800], [25, 25, 10], [1.0, 0.5, 0.3])
    return fade(y * np.exp(-t * 70), 0.0003, 0.01)


def buzz(dur=3.2):
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = np.zeros(n)
    for k in range(1, 30):
        y += np.sin(2 * np.pi * 120 * k * t) / k ** 0.8
    y = np.sign(y) * np.abs(y) ** 0.6
    crackle = (rng.uniform(0, 1, n) > 0.9993).astype(float)
    crackle = lp(crackle, 6000) * 30
    am = 0.6 + 0.4 * np.abs(lp(white(n), 8) * 12)
    am *= (rng.uniform(0, 1, n // 2205 + 1) > 0.2).repeat(2205)[:n] * 0.7 + 0.3
    y = bp(y * am, 200, 6000) + crackle
    return fade(y * env_shape(n, [(0, 0), (0.1, 1), (dur - 0.4, 1), (dur, 0)]))


def crawl():
    dur = 1.4
    n = int(dur * SR)
    y = np.zeros(n)
    r = np.random.default_rng(3)
    for j in range(9):
        at = j * 0.15 + r.uniform(-0.03, 0.03)
        m = int(0.25 * SR)
        exc = bp(white(m), 200, 4000) * np.exp(-np.arange(m) / SR * 80)
        hit = peak_bank(exc, [r.uniform(280, 340), r.uniform(560, 700), r.uniform(1150, 1400), r.uniform(2300, 2600)], [30, 40, 50, 50], [1.0, 0.7, 0.4, 0.2])
        y = mix_at(y, hit * r.uniform(0.4, 1.0), max(0, at))
    y += bp(white(n), 800, 3000) * 0.08 * (0.5 + 0.5 * np.sin(2 * np.pi * 3.3 * np.arange(n) / SR))
    return fade(y)


# ---------------------------------------------------------------------- creatures


def growl(i, dur=1.6):
    r = np.random.default_rng(1400 + i)
    f0 = interp_fn([(0, r.uniform(60, 70)), (dur * 0.4, r.uniform(80, 95)), (dur, r.uniform(55, 65))])
    src = glottal(f0, dur, hmax=4500, tilt=1.0, jitter=0.05, shimmer=0.25)
    src += glottal(lambda t: f0(t) * 0.5, dur, hmax=1500, tilt=1.1, jitter=0.05) * 0.6  # subharmonic
    n = len(src)
    t = np.arange(n) / SR
    src *= 0.6 + 0.4 * np.sin(2 * np.pi * r.uniform(18, 28) * t)
    src += lp(white(n), 2500) * 0.35
    y = formants(src, [(lambda t: 320, 3.0, 1.0), (lambda t: 850, 4.0, 0.7), (lambda t: 1900, 6.0, 0.35), (lambda t: 2900, 8.0, 0.15)])
    y = np.tanh(y * 3) * 0.6
    return fade(y * env_shape(n, [(0, 0), (0.15, 1), (dur * 0.75, 0.9), (dur, 0)]))


def sniff(i):
    r = np.random.default_rng(1500 + i)
    k = r.integers(2, 4)
    parts = []
    for j in range(k):
        d = r.uniform(0.06, 0.1)
        m = int(d * SR)
        x = bp(white(m), 1200, 6000) * env_shape(m, [(0, 0), (d * 0.7, 1), (d, 0)])
        parts += [x, np.zeros(int(r.uniform(0.04, 0.07) * SR))]
    return fade(np.concatenate(parts))


def claws(i):
    r = np.random.default_rng(1600 + i)
    n = int(0.05 * SR)
    t = np.arange(n) / SR
    imp = np.zeros(n)
    imp[0] = 1
    y = peak_bank(imp, [r.uniform(3200, 4500), r.uniform(6000, 7500), r.uniform(1400, 1800)], [15, 18, 8], [1.0, 0.5, 0.4])
    y += bp(white(n), 3000, 10000) * np.exp(-t * 500) * 0.3
    return fade(y * np.exp(-t * 80), 0.0003, 0.008)


def bark(i):
    r = np.random.default_rng(1700 + i)
    dur = 0.32
    f0 = interp_fn([(0, r.uniform(320, 380)), (0.06, r.uniform(420, 470)), (dur, r.uniform(200, 240))])
    src = glottal(f0, dur, hmax=7000, tilt=0.9, jitter=0.03, shimmer=0.2)
    src = np.tanh(src * 4)
    src += bp(white(len(src)), 600, 5000) * 0.4
    y = formants(src, [(interp_fn([(0, 700), (dur, 500)]), 3.0, 1.0), (lambda t: 1400, 4.0, 0.7), (lambda t: 2600, 6.0, 0.35)])
    y *= env_shape(len(y), [(0, 0), (0.012, 1), (0.1, 0.8), (dur, 0)])
    y = np.tanh(y * 2.5)
    # pitched down and roomy: it is not quite a dog
    out = np.concatenate([y, np.zeros(int(0.5 * SR))])
    return fade(lp(out, 6000))


def shriek(i):
    r = np.random.default_rng(1800 + i)
    dur = 1.5
    f0 = interp_fn([(0, 500), (0.15, 1300), (0.6, 1150), (dur, 380)])
    y = np.zeros(int(dur * SR))
    for v in range(4):
        det = 1 + r.uniform(-0.03, 0.03)
        src = glottal(lambda t, d=det: f0(t) * d * (1 + 0.02 * math.sin(2 * math.pi * 7 * t + v)), dur, hmax=10000, tilt=0.9, jitter=0.03, shimmer=0.2)
        y += src[: len(y)]
    y = np.tanh(y * 1.5)
    y = formants(y, [(interp_fn([(0, 900), (0.3, 1300), (dur, 800)]), 3.0, 1.0), (lambda t: 2400, 4.0, 0.7), (lambda t: 3600, 6.0, 0.4)])
    y += bp(white(len(y)), 2000, 9000) * 0.35
    y *= env_shape(len(y), [(0, 0), (0.05, 1), (0.8, 0.8), (dur, 0)])
    return fade(np.concatenate([y, np.zeros(int(0.3 * SR))]))


def breath(i):
    r = np.random.default_rng(1900 + i)
    dur = r.uniform(1.4, 2.0)
    n = int(dur * SR)
    x = pink(n)
    y = formants(x, [(interp_fn([(0, 500), (dur, 380)]), 3.0, 1.0), (interp_fn([(0, 1100), (dur, 850)]), 4.0, 0.6), (lambda t: 2500, 6.0, 0.25)])
    y += lp(white(n), 300) * 0.4
    return fade(y * env_shape(n, [(0, 0), (dur * 0.35, 1), (dur * 0.6, 0.85), (dur, 0)]))


# ---------------------------------------------------------------------- stingers & weather


def sting(i):
    r = np.random.default_rng(2000 + i)
    dur = 3.6
    n = int(dur * SR)
    t = np.arange(n) / SR
    boom = np.sin(2 * np.pi * 42 * t * (1 - 0.18 * t)) * np.exp(-t * 2.2) + lp(white(n), 160) * np.exp(-t * 6)
    cluster = np.zeros(n)
    root = r.choice([233.1, 246.9, 220.0])
    for semi in (0, 1, 6, 11, 13):
        f = root * 2 ** (semi / 12)
        for d in (-0.004, 0.004):
            ph = 2 * np.pi * f * (1 + d) * t
            saw = signal.sawtooth(ph)
            cluster += saw * 0.08
    cut = 300 + 5000 * np.exp(-t * 1.4)
    cl = np.zeros(n)
    zi = np.zeros(2)
    for s in range(0, n, 256):
        e = min(n, s + 256)
        b, a = signal.butter(2, cut[s] / (SR / 2), "low")
        cl[s:e], zi = signal.lfilter(b, a, cluster[s:e], zi=zi)
    cl *= env_shape(n, [(0, 0), (0.03, 1), (0.6, 0.55), (dur, 0)])
    scr = bp(white(n), 3000, 7000) * env_shape(n, [(0, 0), (0.02, 0.6), (0.4, 0.1), (dur, 0)])
    y = boom * 1.1 + cl + scr * 0.3
    st = stereo_width(y, 0.5)
    return reverb(st, 2.8, 3.0, 0.35)


def heartbeat():
    dur = 0.6
    n = int(dur * SR)
    t = np.arange(n) / SR

    def lub(f, at, dec):
        tt = np.maximum(0, t - at)
        return np.sin(2 * np.pi * f * tt) * np.exp(-tt * dec) * (t >= at)
    y = lub(52, 0.0, 30) + 0.7 * lub(44, 0.24, 26)
    y += lp(white(n), 120) * (np.exp(-t * 40) + 0.6 * np.exp(-np.maximum(0, t - 0.24) * 35) * (t > 0.24)) * 0.3
    return fade(lp(y, 200), 0.002, 0.05)


def thunder(i, near):
    r = np.random.default_rng(2100 + i)
    dur = r.uniform(7, 10)
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = np.zeros(n)
    if near:
        crack = bp(white(int(0.4 * SR)), 800, 12000) * np.exp(-np.arange(int(0.4 * SR)) / SR * 14)
        y = mix_at(y, crack * 1.2, 0)
    rum = brown(n)
    rum = lp(rum, 220 if not near else 380, 3)
    # several rolling swells
    envs = np.zeros(n)
    for k in range(r.integers(4, 7)):
        c = r.uniform(0.2, dur * 0.7)
        w = r.uniform(0.4, 1.6)
        envs += r.uniform(0.4, 1.0) * np.exp(-((t - c) / w) ** 2)
    envs += np.exp(-t * 0.6) * 0.8
    y += rum * envs * 2.5
    y += lp(white(n), 900) * envs * 0.08
    y *= env_shape(n, [(0, 0), (0.04, 1), (dur * 0.8, 0.6), (dur, 0)])
    return stereo_width(y, 0.7, 23)


# ---------------------------------------------------------------------- loops


def loop_static(dur=4.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = bp(white(n), 800, 9000) * 0.6
    y += np.sin(2 * np.pi * 60 * t) * 0.1 + np.sin(2 * np.pi * 15734 / 2 * t) * 0.015
    cr = (rng.uniform(0, 1, n) > 0.9996).astype(float)
    y += lp(cr, 7000) * 20
    y *= 0.85 + 0.15 * np.sin(2 * np.pi * 0.7 * t)
    return loopify(np.pad(y, (0, int(0.4 * SR)), mode="wrap"), 0.4)


def loop_whisper(dur=10.0):
    n = int(dur * SR)
    L = np.zeros(n)
    R = np.zeros(n)
    r = np.random.default_rng(31)
    for v in range(4):
        at = r.uniform(0, 0.4)
        pan = r.uniform(-0.8, 0.8)
        while at < dur - 0.3:
            s = syllable(int(r.integers(0, 40)), bool(r.integers(0, 2)), whisper=True)
            s = s * r.uniform(0.4, 1.0)
            for buf, g in ((L, 1 - max(0, pan)), (R, 1 + min(0, pan))):
                mix_at(buf, s * g, at)
            at += len(s) / SR + r.uniform(0.02, 0.25) + (r.uniform(0.6, 1.4) if r.random() < 0.15 else 0)
    y = np.stack([L, R], axis=1)
    y = reverb(y, 1.2, 3, 0.35)[: n + int(0.5 * SR)]
    return loopify(y, 0.5)


def loop_water(dur=5.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = bp(white(n), 400, 7000) * 0.35
    y *= 0.8 + 0.2 * lp(white(n), 20) * 10
    r = np.random.default_rng(41)
    for j in range(int(dur * 70)):
        d = drip(int(r.integers(0, 30))) * r.uniform(0.05, 0.25)
        f = r.uniform(0.7, 1.6)
        idx = np.clip((np.arange(int(len(d) / f)) * f).astype(int), 0, len(d) - 1)
        mix_at(y, d[idx], r.uniform(0, dur - 0.2))
    return loopify(np.pad(y, (0, int(0.4 * SR)), mode="wrap"), 0.4)


def loop_rain(dur=10.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    base = lp(pink(n), 6000) * 0.5 + bp(white(n), 2000, 9000) * 0.12
    out = []
    r = np.random.default_rng(51)
    for c in range(2):
        y = base * (0.9 + 0.1 * lp(white(n), 2) * 20)
        drops = np.zeros(n)
        idx = r.integers(0, n, int(dur * 900))
        drops[idx] = r.uniform(0.2, 1.0, len(idx))
        y += bp(drops, 1500, 9000) * 0.6
        roof = np.zeros(n)
        idx2 = r.integers(0, n, int(dur * 250))
        roof[idx2] = r.uniform(0.3, 1.0, len(idx2))
        y += peak_bank(roof, [r.uniform(500, 700), r.uniform(1100, 1300)], 6, [0.3, 0.2])
        out.append(y)
    y = np.stack(out, axis=1)
    return loopify(np.concatenate([y, y[: int(0.6 * SR)]]), 0.6)


def loop_fridge(dur=6.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = np.sin(2 * np.pi * 60 * t) * 0.5 + np.sin(2 * np.pi * 120 * t) * 0.35 + np.sin(2 * np.pi * 181 * t) * 0.12 + np.sin(2 * np.pi * 240 * t) * 0.08
    y *= 1 + 0.08 * np.sin(2 * np.pi * 0.5 * t)
    y += lp(white(n), 500) * 0.05
    return y


def loop_hum(dur=4.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = np.zeros(n)
    for k in range(1, 12):
        y += np.sin(2 * np.pi * 60 * k * t) / k ** 1.2
    return bp(y, 50, 3000) + lp(white(n), 2000) * 0.02


def loop_wind(dur=16.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = []
    for c in range(2):
        x = pink(n)
        g = 0.35 + 0.65 * np.clip(lp(white(n), 0.4) * 60 + 0.5, 0, 1)
        f = interp_fn([(0, 350), (dur * 0.3, 700), (dur * 0.55, 420), (dur * 0.8, 900), (dur, 350)])
        y = tv_bandpass(x, lambda tt, c=c: f(tt) * (1 + 0.1 * c), lambda tt: 1.2, 256) * g
        y += tv_bandpass(white(n), lambda tt: 1400 + 500 * math.sin(tt * 0.7 + c), lambda tt: 12.0, 256) * 0.05 * g ** 2
        y += lp(brown(n), 120) * 0.3
        out.append(y)
    y = np.stack(out, axis=1)
    return loopify(np.concatenate([y, y[: int(1.5 * SR)]]), 1.5)


def loop_rumble(dur=8.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = lp(brown(n), 90, 3) * 2.0
    y += np.sin(2 * np.pi * 31 * t) * 0.3 * (0.6 + 0.4 * np.sin(2 * np.pi * 0.25 * t))
    g = growl(5, dur)
    y += lp(g[:n], 500) * 0.35
    return loopify(np.concatenate([y, y[: int(1.0 * SR)]]), 1.0)


def loop_drone(dur=20.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = []
    for c in range(2):
        y = np.zeros(n)
        for f, a in ((55.0, 0.5), (82.4, 0.35), (110.0 * 1.003, 0.2), (130.8 * 0.997, 0.12)):
            ph = 2 * np.pi * f * (1 + 0.002 * c) * t + 0.3 * np.sin(2 * np.pi * 0.07 * t + c)
            y += a * signal.sawtooth(ph, 0.5)
        y = lp(y, 500)
        swell = 0.6 + 0.4 * np.sin(2 * np.pi * t / dur * 2 + c)
        y += bp(pink(n), 200, 1200) * 0.12 * swell
        out.append(y * (0.85 + 0.15 * np.sin(2 * np.pi * t / dur * 3)))
    y = np.stack(out, axis=1)
    return loopify(np.concatenate([y, y[: int(2 * SR)]]), 2.0)


def loop_tension(dur=10.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = []
    for c in range(2):
        y = np.zeros(n)
        for f in (466.2, 493.9, 698.5, 233.1):
            trem = 0.6 + 0.4 * np.sin(2 * np.pi * (3.5 + c * 0.7 + f / 500) * t)
            y += signal.sawtooth(2 * np.pi * f * (1 + 0.003 * c) * t, 0.5) * 0.12 * trem
        y = lp(y, 2500)
        y += bp(pink(n), 2500, 4500) * 0.15
        y += np.sin(2 * np.pi * 2 * t) ** 8 * lp(white(n), 120) * 0.0
        out.append(y)
    y = np.stack(out, axis=1)
    return loopify(np.concatenate([y, y[: int(1 * SR)]]), 1.0)


def loop_pad(dur=16.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = []
    for c in range(2):
        y = np.zeros(n)
        for f in (130.8, 196.0, 246.9, 329.6, 392.0):
            for d in (-0.003, 0.003):
                y += signal.sawtooth(2 * np.pi * f * (1 + d + c * 0.001) * t, 0.5) * 0.06
        y = lp(y, 1400)
        out.append(y * (0.8 + 0.2 * np.sin(2 * np.pi * t / dur * 2 + c * 2)))
    y = np.stack(out, axis=1)
    return loopify(np.concatenate([y, y[: int(2 * SR)]]), 2.0)


# ---------------------------------------------------------------------- afternoons


def car_arrive(dur=8.0):
    """an old car coming up the dirt road, gravel under the tyres, braking, the engine cut."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    near = interp_fn([(0, 0.05), (5.0, 1.0), (6.2, 1.0), (dur, 1.0)])
    rpm = interp_fn([(0, 32), (4.6, 34), (5.6, 22), (6.4, 14), (6.6, 0.1), (dur, 0.1)])
    on = np.clip(1.0 - (t - 6.55) * 6, 0.0, 1.0)
    f = np.array([rpm(x) for x in t])
    ph = np.cumsum(2 * np.pi * f / SR)
    eng = (signal.sawtooth(ph) * 0.5 + np.sin(ph * 2) * 0.3 + np.sin(ph * 0.5) * 0.4) * on
    eng = lp(eng, 900) + bp(white(n), 80, 400) * 0.25 * on
    tyre = interp_fn([(0, 0.6), (5.4, 0.7), (6.4, 0.2), (6.6, 0.0), (dur, 0.0)])
    ty = np.array([tyre(x) for x in t])
    gravel = bp(white(n), 1200, 6000) * ty
    pops = (rng.uniform(0, 1, n) > 0.997).astype(float) * ty
    gravel += lp(pops, 5000) * 3
    g = np.array([near(x) for x in t])
    y = (eng * 0.8 + gravel * 0.35) * g
    # the brakes squeak
    sq = bp(white(int(0.4 * SR)), 2500, 4200) * env_shape(int(0.4 * SR), [(0, 0), (0.05, 1), (0.4, 0)]) * 0.3
    mix_at(y, sq, 6.1)
    return fade(y, 0.4, 0.4)


def horn(dur=1.3):
    """two honks of an old car horn."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = np.zeros(n)
    for at, ln in ((0.0, 0.28), (0.45, 0.6)):
        m = (t >= at) & (t < at + ln)
        tt = t[m] - at
        tone = signal.square(2 * np.pi * 410 * tt, 0.42) + signal.square(2 * np.pi * 517 * tt, 0.42) * 0.8
        y[m] += tone * np.minimum(1, tt * 60) * np.minimum(1, (ln - tt) * 40)
    y = bp(y, 300, 3200)
    return reverb(fade(y, 0.002, 0.05), 1.2, 3, 0.25)


def sneeze(i):
    """a man sneezing: a sharp intake, the rising "a-a" and the burst."""
    r = np.random.default_rng(1500 + i)
    pre = glottal(interp_fn([(0, 140), (0.35, 175)]), 0.38, hmax=4000, tilt=1.5) * 0.35
    pre = formants(pre, [(lambda t: 750, 5.0, 1.0), (lambda t: 1200, 8.0, 0.4)])
    pre *= env_shape(len(pre), [(0, 0), (0.1, 0.8), (0.38, 1.0)])
    gap = np.zeros(int(r.uniform(0.08, 0.14) * SR))
    burst_n = int(0.32 * SR)
    burst = bp(white(burst_n), 1800, 8000) * env_shape(burst_n, [(0, 0), (0.005, 1), (0.06, 0.6), (0.32, 0)])
    voiced = glottal(interp_fn([(0, 230), (0.25, 160)]), 0.34, hmax=5000, tilt=1.3)
    voiced = formants(voiced, [(lambda t: 320, 5.0, 1.0), (lambda t: 2200, 9.0, 0.5)])[:burst_n]
    voiced = np.pad(voiced, (0, max(0, burst_n - len(voiced))))[:burst_n] * env_shape(burst_n, [(0, 0), (0.02, 0.8), (0.3, 0)])
    y = np.concatenate([pre, gap, burst + voiced * 0.6])
    return reverb(fade(hp(y, 120), 0.003, 0.05), 0.7, 3, 0.15)


def keys(i):
    """a ring of keys: small metal pieces clinking."""
    r = np.random.default_rng(1600 + i)
    n = int(0.7 * SR)
    y = np.zeros(n)
    for k in range(int(r.integers(6, 10))):
        at = r.uniform(0, 0.4)
        m = int(0.25 * SR)
        tt = np.arange(m) / SR
        part = sum(np.sin(2 * np.pi * r.uniform(2500, 7500) * tt + r.uniform(0, 6)) * np.exp(-tt * r.uniform(25, 60)) for _ in range(3))
        mix_at(y, part * r.uniform(0.3, 1.0), at)
    return fade(y, 0.001, 0.05)


def lock_turn():
    """a key turning in an old lock: grind, then the bolt."""
    n = int(0.6 * SR)
    y = bp(white(n), 1500, 5000) * env_shape(n, [(0, 0), (0.05, 0.5), (0.3, 0.4), (0.34, 0)]) * 0.3
    mix_at(y, click(5) * 0.6, 0.05)
    clunk = thud(9, 160)
    cl = click(6)
    clunk[: len(cl)] += cl * 0.8
    mix_at(y, clunk * 0.5, 0.34)
    return fade(y, 0.001, 0.05)


def puff():
    """a dust sheet pulled off a bed: a soft whoosh of cloth and dust."""
    n = int(1.1 * SR)
    y = bp(white(n), 300, 3000) * env_shape(n, [(0, 0), (0.12, 1), (0.35, 0.5), (1.1, 0)])
    y += lp(white(n), 250) * env_shape(n, [(0, 0), (0.1, 1), (0.6, 0)]) * 1.5
    return fade(y, 0.01, 0.1)


def bulb_pop():
    """an incandescent bulb burning out: a tick, a fizz and a soft pop."""
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    y = bp(white(n), 3000, 9000) * np.exp(-t * 30) * 0.4
    mix_at(y, click(7) * 0.7, 0.0)
    mix_at(y, glass(4)[: int(0.3 * SR)] * 0.25, 0.06)
    return fade(y, 0.0005, 0.05)


def loop_tv(dur=12.0):
    """the telenovela "Amor de Porteira" through an old TV speaker: a sentimental waltz and dialogue."""
    n = int(dur * SR)
    y = np.zeros(n)
    chords = [(196.0, 246.9, 293.7), (174.6, 220.0, 261.6), (164.8, 196.0, 246.9), (174.6, 220.0, 293.7)]
    for ci in range(int(dur / 1.5) + 1):
        ch = chords[ci % len(chords)]
        m = int(1.6 * SR)
        tt = np.arange(m) / SR
        part = sum(np.sin(2 * np.pi * f * tt) * 0.12 + np.sin(4 * np.pi * f * tt) * 0.04 for f in ch)
        mix_at(y, part * env_shape(m, [(0, 0), (0.08, 1), (1.4, 0.7), (1.6, 0)]), ci * 1.5)
    mel = [392.0, 440.0, 493.9, 440.0, 392.0, 329.6, 349.2, 392.0]
    for k in range(int(dur / 0.75)):
        m = int(0.7 * SR)
        tt = np.arange(m) / SR
        mix_at(y, np.sin(2 * np.pi * mel[k % len(mel)] * tt) * np.exp(-tt * 2.5) * 0.18, k * 0.75)
    r = np.random.default_rng(77)
    at = 0.4
    male = False
    while at < dur - 0.5:
        for s_i in range(int(r.integers(3, 7))):
            s = syllable(int(r.integers(0, 40)), male) * 0.5
            mix_at(y, s, at)
            at += len(s) / SR + r.uniform(0.0, 0.06)
        at += r.uniform(0.3, 0.8)
        male = not male
    y = bp(y, 250, 3200)
    y += bp(white(n), 2000, 8000) * 0.02
    return loopify(np.pad(y, (0, int(0.5 * SR)), mode="wrap"), 0.5)


def tv_vem():
    """the voice from the tapes, much too slow: "...vem aqui..."."""
    parts = []
    for i, (f0, form) in enumerate(((150, (700, 1200)), (130, (450, 1800)), (120, (700, 1200)), (110, (300, 2300)))):
        dur = 0.55
        src = glottal(interp_fn([(0, f0), (dur, f0 * 0.88)]), dur, hmax=4000, tilt=1.5, jitter=0.02, shimmer=0.08)
        src = src * 0.7 + white(len(src)) * 0.15
        v = formants(src, [(lambda t, a=form[0]: a, 4.0, 1.0), (lambda t, b=form[1]: b, 7.0, 0.5)])
        v *= env_shape(len(v), [(0, 0), (0.12, 1), (0.42, 0.8), (dur, 0)])
        parts.append(v)
        parts.append(np.zeros(int((0.35 if i == 1 else 0.08) * SR)))
    y = np.concatenate(parts)
    y = bp(y, 200, 3000) + bp(white(len(y)), 1500, 7000) * 0.05
    return reverb(fade(y, 0.01, 0.2), 1.8, 3, 0.45)


# ---------------------------------------------------------------------- piano


def piano(freq, dur=5.0, vel=0.8):
    n = int(dur * SR)
    t = np.arange(n) / SR
    B = 0.00035
    y = np.zeros(n)
    nmax = int(min(40, 9000 / freq))
    for k in range(1, nmax + 1):
        fk = k * freq * math.sqrt(1 + B * k * k)
        amp = (1.0 / k ** 1.05) * (0.6 + 0.4 * math.sin(math.pi * k * 0.12) ** 2) * (vel ** (0.4 + k * 0.05))
        d_fast = 2.5 + k * 0.9 + freq / 200
        d_slow = 0.35 + k * 0.12 + freq / 900
        e = 0.55 * np.exp(-t * d_fast) + 0.45 * np.exp(-t * d_slow)
        for s, det in ((0, 0.0), (1, 0.0007), (2, -0.0006)):
            y += amp * e * np.sin(2 * np.pi * fk * (1 + det) * t + s * 1.7) / 3
    ham = lp(white(int(0.02 * SR)), 2500) * np.exp(-np.arange(int(0.02 * SR)) / SR * 200) * 0.08
    y[: len(ham)] += ham
    y = lp(y, 7000)
    return fade(y, 0.0008, 0.3)


# ---------------------------------------------------------------------- ui


def ui_sound(kind):
    if kind == "hover":
        n = int(0.08 * SR)
        t = np.arange(n) / SR
        y = np.sin(2 * np.pi * 1760 * t) * np.exp(-t * 70) * 0.5 + np.sin(2 * np.pi * 2640 * t) * np.exp(-t * 90) * 0.2
    elif kind == "select":
        n = int(0.5 * SR)
        t = np.arange(n) / SR
        y = sum(a * np.sin(2 * np.pi * f * t) * np.exp(-t * d) for f, a, d in ((880, 0.5, 8), (1320, 0.35, 9), (1760, 0.2, 12), (2640, 0.1, 16)))
    else:
        n = int(0.4 * SR)
        t = np.arange(n) / SR
        y = sum(a * np.sin(2 * np.pi * f * t) * np.exp(-t * d) for f, a, d in ((587, 0.5, 9), (880, 0.3, 11), (1174, 0.15, 14)))
    return fade(y, 0.001, 0.02)


# ---------------------------------------------------------------------- main


def main():
    for i in range(5):
        write(f"cat_meow_{i}", meow(i))
    for i in range(2):
        write(f"cat_mrrp_{i}", mrrp(i))
    for i in range(2):
        write(f"cat_hiss_{i}", hiss(True, i))
    write("cat_hiss_weak", hiss(False, 9))
    write("cat_purr_loop", purr_loop())
    write("cat_cry", cat_cry())
    for s in ("wood", "tile", "concrete", "carpet"):
        for i in range(5):
            write(f"paw_{s}_{i}", paw(s, False, i), 0.6)
        for i in range(3):
            write(f"paw_{s}_run_{i}", paw(s, True, i), 0.75)
    for i in range(6):
        write(f"step_{i}", human_step(i))
    for i in range(2):
        write(f"step_creak_{i}", human_step(10 + i, True))
    for i in range(3):
        write(f"click_{i}", click(i))
    for i in range(4):
        write(f"creak_door_{i}", creak_sound(20 + i, 1.4 + i * 0.3, (70, 200)))
    for i in range(4):
        write(f"creak_floor_{i}", creak_sound(40 + i, 0.6 + i * 0.15, (120, 320), 0.7))
    write("creak_long", creak_sound(60, 2.6, (50, 160)))
    for i in range(3):
        write(f"thud_{i}", thud(i, 70 + i * 25))
    for i in range(3):
        write(f"knock_{i}", knock(i))
    for i in range(3):
        write(f"glass_{i}", glass(i))
    for i in range(4):
        write(f"drip_{i}", drip(i), 0.7)
    for i in range(3):
        write(f"porcelain_{i}", porcelain(i), 0.75)
    write("bell", bell())
    write("tick", tick(False), 0.5)
    write("tock", tick(True), 0.5)
    write("buzz", buzz())
    write("crawl", crawl())
    for i in range(3):
        write(f"growl_{i}", growl(i))
    for i in range(2):
        write(f"growl_short_{i}", growl(10 + i, 0.6))
    for i in range(3):
        write(f"sniff_{i}", sniff(i))
    for i in range(4):
        write(f"claws_{i}", claws(i), 0.6)
    for i in range(2):
        write(f"bark_{i}", bark(i))
    for i in range(3):
        write(f"giggle_{i}", giggle(i))
    for i in range(2):
        write(f"shriek_{i}", shriek(i))
    for i in range(2):
        write(f"breath_{i}", breath(i))
    for i in range(3):
        write(f"sting_{i}", sting(i))
    write("heartbeat", heartbeat())
    for i in range(3):
        write(f"thunder_{i}", thunder(i, i == 0))
    for i in range(24):
        write(f"voice_f_{i}", soft_syllable(i, "f"))
        write(f"voice_m_{i}", soft_syllable(i, "m"))
    for i in range(8):
        write(f"voice_w_{i}", syllable(i, False, True))
    write("loop_static", loop_static())
    write("loop_whisper", loop_whisper(), stereo=True)
    write("loop_water", loop_water())
    write("loop_rain", loop_rain(), 0.7)
    write("loop_fridge", loop_fridge(), 0.6)
    write("loop_hum", loop_hum(), 0.6)
    write("loop_wind", loop_wind(), 0.8)
    write("loop_rumble", loop_rumble())
    write("music_drone", loop_drone(), 0.7)
    write("music_tension", loop_tension(), 0.7)
    write("music_pad", loop_pad(), 0.6)
    notes = sorted({110.0, 87.3, 65.4, 98.0, 220.0, 261.6, 329.6, 174.6, 196.0, 246.9, 293.7, 440.0, 523.3, 659.3, 349.2, 392.0, 493.9, 587.3, 783.99})
    for f in notes:
        write(f"piano_{int(round(f * 10))}", piano(f), 0.8)
    for k in ("hover", "select", "back"):
        write(f"ui_{k}", ui_sound(k), 0.5)
    write("car_arrive", car_arrive(), 0.8)
    write("horn", horn(), 0.7)
    for i in range(2):
        write(f"sneeze_{i}", sneeze(i), 0.8)
    for i in range(2):
        write(f"keys_{i}", keys(i), 0.6)
    write("lock_turn", lock_turn(), 0.7)
    write("puff", puff(), 0.6)
    write("bulb_pop", bulb_pop(), 0.7)
    write("loop_tv", loop_tv(), 0.7)
    write("tv_vem", tv_vem(), 0.85)


if __name__ == "__main__":
    main()
