"""Brings the recorded CC0 sounds into the game under the names the code already plays (Sfx groups
"name_N" files), replacing the synthesized ones; the synthesized originals are kept in
tools/backup/audio_synth/. Every file: mono, 44.1 kHz, leading silence trimmed, loudness evened out.

usage: python tools/audio/import_cc0.py      (needs ffmpeg on the PATH)
Sources and licences: godot/assets/audio/LICENSES.md
"""
import os
import shutil
import subprocess

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "tools", "vendor", "sfx_cc0")
OUT = os.path.join(ROOT, "godot", "assets", "audio")
BAK = os.path.join(ROOT, "tools", "backup", "audio_synth")

LAL = "laleksic"            # "Various Sound Effects" by laleksic (OpenGameArt, CC0)
WM = "wood_metal"           # "100 CC0 metal and wood SFX" (OpenGameArt, CC0)

# game name -> (pack, file, loudness LUFS)
MAP = {
    "lock_turn": (LAL, "lock.wav", -16),
    "keys_0": (WM, "keys_01.ogg", -18),
    "keys_1": (WM, "keys_03.ogg", -18),
    "creak_door_0": (LAL, "door_creak_open.wav", -18),
    "creak_door_1": (LAL, "door_creak_close.wav", -18),
    "creak_door_2": (WM, "wood_squeak_01.ogg", -19),
    "creak_door_3": (WM, "wood_squeak_02.ogg", -19),
    "creak_floor_0": (LAL, "floor_creak1.wav", -19),
    "creak_floor_1": (LAL, "floor_creak2.wav", -19),
    "creak_floor_2": (LAL, "floor_creak3.wav", -19),
    "creak_floor_3": (WM, "wood_cracking_03.ogg", -20),
    "click_0": (LAL, "switch_on.wav", -18),
    "click_1": (LAL, "switch_off.wav", -18),
    "knock_0": (WM, "wood_hit_01.ogg", -15),
    "knock_1": (WM, "wood_hit_02.ogg", -15),
    "knock_2": (WM, "wood_hit_03.ogg", -15),
    "thud_0": (LAL, "door_close.wav", -16),
    "thud_1": (WM, "wood_close_01.ogg", -16),
    "thud_2": (WM, "wood_close_02.ogg", -16),
}


def find(pack, name):
    for dp, _, fs in os.walk(os.path.join(SRC, pack)):
        if name in fs:
            return os.path.join(dp, name)
    raise FileNotFoundError(f"{pack}/{name}")


def main():
    os.makedirs(BAK, exist_ok=True)
    for game, (pack, name, lufs) in MAP.items():
        src = find(pack, name)
        dst = os.path.join(OUT, game + ".wav")
        if os.path.exists(dst) and not os.path.exists(os.path.join(BAK, game + ".wav")):
            shutil.copy2(dst, os.path.join(BAK, game + ".wav"))
        af = f"silenceremove=start_periods=1:start_threshold=-48dB,loudnorm=I={lufs}:TP=-1.5:LRA=11,afade=t=out:st=0:d=0.01:curve=tri"
        # the fade-out has to sit at the end: apply it on the reversed clip
        af = f"silenceremove=start_periods=1:start_threshold=-48dB,loudnorm=I={lufs}:TP=-1.5:LRA=11,areverse,afade=t=in:d=0.02,areverse"
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", src, "-ac", "1", "-ar", "44100", "-af", af, "-c:a", "pcm_s16le", dst], check=True)
        print(f"{game:14s} <- {pack}/{name}")


if __name__ == "__main__":
    main()
