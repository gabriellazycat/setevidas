"""Animalese-style voice (the way Animal Crossing does it): a bank of short syllables recorded by a
human voice (Kokoro TTS, offline), sped up so they rise in pitch, chained one per syllable of the
text. Builds the banks (voice_<who>_<syl>.wav) and demo lines.

usage: tools/vendor/kokoro_venv/Scripts/python.exe tools/audio/animalese.py bank OUT_DIR
       tools/vendor/kokoro_venv/Scripts/python.exe tools/audio/animalese.py demo BANK_DIR OUT_DIR
"""
import os
import re
import sys

import numpy as np
import soundfile as sf

SR = 24000
VOWELS = "aeiou"
CONS = ["", "b", "d", "f", "g", "k", "l", "m", "n", "p", "r", "s", "t", "v", "x", "j"]
VOICE = {"clara": "pf_dora", "davi": "pm_alex"}


def syl_text(c, v):
    # spelled so the Portuguese voice says one clean syllable
    return {"k": "c" if v in "aou" else "qu", "g": "g" if v in "aou" else "gu", "x": "ch", "j": "j"}.get(c, c) + v


def trim(y):
    a = np.abs(y)
    th = a.max() * 0.06
    idx = np.where(a > th)[0]
    if len(idx) == 0:
        return y
    y = y[max(0, idx[0] - int(0.004 * SR)): idx[-1] + int(0.01 * SR)]
    n = int(0.008 * SR)
    y[:n] *= np.linspace(0, 1, n)
    y[-n:] *= np.linspace(1, 0, n)
    return y / (np.abs(y).max() + 1e-9) * 0.9


def bank(out):
    from kokoro import KPipeline
    pipe = KPipeline(lang_code="p")
    os.makedirs(out, exist_ok=True)
    for who, voice in VOICE.items():
        for c in CONS:
            for v in VOWELS:
                t = syl_text(c, v)
                parts = [np.asarray(a) for _, _, a in pipe(t + ".", voice=voice, speed=1.1)]
                y = trim(np.concatenate(parts))
                sf.write(os.path.join(out, f"{who}_{c or '_'}{v}.wav"), y, SR)
        print(who, "ok")


def syllables(text):
    """the text cut into consonant+vowel pieces (accents dropped), like Animalese reads letters"""
    t = text.lower()
    for a, b in (("á", "a"), ("à", "a"), ("â", "a"), ("ã", "a"), ("é", "e"), ("ê", "e"), ("í", "i"), ("ó", "o"), ("ô", "o"),
                 ("õ", "o"), ("ú", "u"), ("ç", "s"), ("ch", "x"), ("qu", "k"), ("c", "k"), ("h", ""), ("w", "v"), ("y", "i"), ("z", "s"), ("lh", "l"), ("nh", "n")):
        t = t.replace(a, b)
    out = []
    for word in re.findall(r"[a-z]+|[?!.,]", t):
        if word in "?!.,":
            out.append(word)
            continue
        i = 0
        while i < len(word):
            c = word[i]
            if c in VOWELS:
                out.append(("", c))
                i += 1
            elif i + 1 < len(word) and word[i + 1] in VOWELS:
                out.append((c if c in CONS else "", word[i + 1]))
                i += 2
            else:
                i += 1
        out.append(" ")
    return out


def speak(bankdir, who, text, speed=1.7, step=0.075, gain=0.8):
    """sped-up syllables (speed = how much faster and higher), one every `step` seconds; a question
    rises at the end, a statement falls a little"""
    sy = syllables(text)
    n = sum(1 for s in sy if isinstance(s, tuple))
    q = text.strip().endswith("?")
    out = np.zeros(int(SR * (n * step + 1.5)))
    t = 0.0
    k = 0
    for s in sy:
        if s == " ":
            t += step * 0.35
            continue
        if s in ("?", "!", ".", ","):
            t += step * (2.5 if s != "," else 1.4)
            continue
        c, v = s
        y, _ = sf.read(os.path.join(bankdir, f"{who}_{c or '_'}{v}.wav"))
        u = k / max(1, n - 1)
        melody = 1.0 + 0.04 * np.sin(k * 1.7) + (0.18 * max(0.0, (u - 0.6) / 0.4) if q else -0.06 * max(0.0, (u - 0.65) / 0.35))
        f = speed * melody
        idx = np.arange(0, len(y) - 1, f)
        z = np.interp(idx, np.arange(len(y)), y)
        # each piece only lasts a little: the next one cuts in (that is what makes it flow)
        L = min(len(z), int(step * 1.6 * SR))
        z = z[:L].copy()
        fade = min(L, int(0.02 * SR))
        z[-fade:] *= np.linspace(1, 0, fade)
        a = int(t * SR)
        out[a:a + L] += z * gain
        t += step * np.random.uniform(0.9, 1.1)
        k += 1
    return out[: int((t + 0.3) * SR)]


def demo(bankdir, out):
    os.makedirs(out, exist_ok=True)
    np.random.seed(3)
    lines = {"clara": ["Vem, Mingau. Hora de dormir.", "Tá tudo certo, Mingau. Tá tudo certo.", "Você tá com fome?"],
             "davi": ["Então é aqui a casa barata? Gostei, mana."]}
    for who, ls in lines.items():
        for tag, speed, step in (("D2", 1.7, 0.072), ("D3", 1.35, 0.085)):
            sp = speed * (0.88 if who == "davi" else 1.0)
            for i, l in enumerate(ls):
                y = speak(bankdir, who, l, sp, step)
                sf.write(os.path.join(out, f"{tag}_{who}_{i}.wav"), y / (np.abs(y).max() + 1e-9) * 0.85, SR)
    print("demo ok")


if __name__ == "__main__":
    if sys.argv[1] == "bank":
        bank(sys.argv[2])
    else:
        demo(sys.argv[2], sys.argv[3])
