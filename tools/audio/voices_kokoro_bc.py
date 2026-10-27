"""Voice samples B (only short expressive sounds) and C (game-language babble in a real voice), both
with Kokoro's human voices, for the voice choice.

usage: tools/vendor/kokoro_venv/Scripts/python.exe tools/audio/voices_kokoro_bc.py OUT_DIR
"""
import os
import random
import sys

import numpy as np
import soundfile as sf
from kokoro import KPipeline

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
pipe = KPipeline(lang_code="p")
VOICE = {"clara": "pf_dora", "davi": "pm_alex"}


def say(text, voice, speed=1.0):
    parts = [np.asarray(a) for _, _, a in pipe(text, voice=voice, speed=speed)]
    return np.concatenate(parts) if parts else np.zeros(1)


# B: little human sounds, one per line, the text goes in the subtitle
B = {"clara": ["Hmm?", "Ahh.", "Hehe.", "Aham."], "davi": ["Hã?", "Opa!", "Heh."]}
for who, ws in B.items():
    for i, w in enumerate(ws):
        y = say(w, VOICE[who], 0.95)
        sf.write(os.path.join(OUT, f"B_{who}_{i}.wav"), y, 24000)

# C: invented words with soft consonants, spoken as a sentence (a question rises by itself)
random.seed(7)
SYL = ["ma", "na", "lo", "mi", "ne", "la", "vi", "do", "ni", "le", "mo", "ta", "be", "ri"]


def word(n):
    return "".join(random.choice(SYL) for _ in range(n))


C = {"clara": [f"{word(2).capitalize()} {word(2)}, {word(3)}. {word(2).capitalize()} {word(2)}.",
               f"{word(2).capitalize()} {word(3)} {word(2)}?"],
     "davi": [f"{word(2).capitalize()} {word(2)} {word(3)}? {word(2).capitalize()}, {word(2)}."]}
for who, ls in C.items():
    for i, t in enumerate(ls):
        y = say(t, VOICE[who], 1.05)
        sf.write(os.path.join(OUT, f"C_{who}_{i}.wav"), y, 24000)
        print(who, t)
