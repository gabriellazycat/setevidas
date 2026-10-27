"""Voice samples (version A: real speech, Kokoro TTS, offline, Apache-2.0) for the voice choice.

usage: tools/vendor/kokoro_venv/Scripts/python.exe tools/audio/voices_kokoro.py OUT_DIR
Writes clara_<n>.wav / davi_<n>.wav in Portuguese (pf_dora / pm_alex) and English (af_heart / am_michael).
"""
import os
import sys

import numpy as np
import soundfile as sf
from kokoro import KPipeline

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
LINES = {
    "p": {"clara": ["Vem, Mingau. Hora de dormir.", "Tá tudo certo, Mingau. Tá tudo certo."],
          "davi": ["Então é aqui a casa barata? Gostei, mana."]},
    "a": {"clara": ["Come on, Mingau. Bedtime.", "It's all fine, Mingau. It's all fine."],
          "davi": ["So this is the cheap house? I like it, sis."]},
}
VOICES = {"p": {"clara": ("pf_dora", 0.95), "davi": ("pm_alex", 1.0)},
          "a": {"clara": ("af_heart", 0.95), "davi": ("am_michael", 1.0)}}

for lang, who_lines in LINES.items():
    pipe = KPipeline(lang_code=lang)
    for who, lines in who_lines.items():
        voice, speed = VOICES[lang][who]
        for i, text in enumerate(lines):
            audio = []
            for _, _, a in pipe(text, voice=voice, speed=speed):
                audio.append(np.asarray(a))
            y = np.concatenate(audio)
            name = f"A_{who}_{'pt' if lang == 'p' else 'en'}_{i}.wav"
            sf.write(os.path.join(OUT, name), y, 24000)
            print(name, round(len(y) / 24000, 2))
