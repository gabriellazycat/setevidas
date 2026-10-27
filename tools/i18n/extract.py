"""Collects the player-facing Portuguese strings of the game into godot/i18n/strings.pot (msgid =
the Portuguese text, as the code has it) and reports which ones en.po does not translate yet.

usage: python tools/i18n/extract.py [--missing]
Heuristic: string literals in godot/scripts/**/*.gd with a space or an accented letter and at least
one lowercase letter, minus paths, node names, shader/bus/action names; plus room names from
layout.json. Strings that are only format codes are skipped.
"""
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SCRIPTS = os.path.join(ROOT, "godot", "scripts")
OUT = os.path.join(ROOT, "godot", "i18n")
LIT = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
SKIP_FILES = {"autopilot.gd", "lookdev.gd", "cat_anim.gd", "retarget.gd", "navcheck.gd", "check.gd"}
SKIP_LINE = re.compile(r'print\(|push_warning|push_error|load\(|preload\(|get_node|find_child|has_meta|set_meta|get_meta|Input\.|is_action|shader_parameter|\$"|@export')
NOT_WORDS = {"Mingau", "Clara", "Davi", "Ivone", "Breu", "Rafael", "Sfx", "Amb", "Music", "Voice", "Master", "Rain", "Colliders", "Skeleton", "Node", "Light", "Label", "Panel", "Button"}
ACCENT = re.compile(r"[áàâãéêíóôõúçÁÀÂÃÉÊÍÓÔÕÚÇ]")


UI_WORD = re.compile(r"[A-ZÀ-Ú][a-zà-ú]{2,}")


def wanted(s: str) -> bool:
    # single capitalised words are labels in the UI (menu buttons, tabs)
    if UI_WORD.fullmatch(s) and s not in NOT_WORDS:
        return True
    if len(s) < 2 or s.startswith(("res://", "user://", "#", "[")) and " " not in s:
        return False
    if re.fullmatch(r"[%\w./:-]*", s) and not ACCENT.search(s):
        return False
    if not re.search(r"[a-zà-ú]", s):
        return False
    if re.fullmatch(r"[\s%dsf.0-9:+\-]*", s):
        return False
    return " " in s or bool(ACCENT.search(s))


def collect():
    found = {}
    for dp, _, fs in os.walk(SCRIPTS):
        for f in fs:
            if not f.endswith(".gd") or f in SKIP_FILES:
                continue
            path = os.path.join(dp, f)
            for ln, line in enumerate(open(path, encoding="utf-8"), 1):
                code = line.split("#", 1)[0] if '"' not in line.split("#", 1)[0] else line
                if code.lstrip().startswith("#") or SKIP_LINE.search(code):
                    continue
                # anything the code hands to tr() is player-facing, single words included
                for m in re.finditer(r'tr\("((?:[^"\
]|\.)*)"\)', code):
                    if m.group(1).strip():
                        found.setdefault(m.group(1), f"{os.path.relpath(path, ROOT)}:{ln}")
                for m in LIT.finditer(code):
                    s = m.group(1).encode().decode("unicode_escape").encode("latin-1").decode("utf-8") if "\\" in m.group(1) else m.group(1)
                    if wanted(s):
                        found.setdefault(s, f"{os.path.relpath(path, ROOT)}:{ln}")
    lay = json.load(open(os.path.join(ROOT, "godot", "data", "layout.json"), encoding="utf-8"))
    for r in lay["ROOMS"]:
        found.setdefault(r["name"], "layout.json ROOMS")
    for d in lay["DOORS"]:
        if "name" in d:
            found.setdefault(d["name"], "layout.json DOORS")
    return found


def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def read_po(path):
    tr = {}
    if not os.path.exists(path):
        return tr
    cur_id = cur_str = None
    mode = None
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if line.startswith("msgid "):
            if cur_id is not None:
                tr[cur_id] = cur_str
            cur_id, cur_str, mode = json.loads(line[6:]), "", "id"
        elif line.startswith("msgstr "):
            cur_str, mode = json.loads(line[7:]), "str"
        elif line.startswith('"') and mode:
            if mode == "id":
                cur_id += json.loads(line)
            else:
                cur_str += json.loads(line)
    if cur_id is not None:
        tr[cur_id] = cur_str
    return tr


def main():
    os.makedirs(OUT, exist_ok=True)
    found = collect()
    with open(os.path.join(OUT, "strings.pot"), "w", encoding="utf-8") as f:
        f.write('msgid ""\nmsgstr ""\n"Content-Type: text/plain; charset=UTF-8\\n"\n\n')
        for s, where in sorted(found.items(), key=lambda kv: kv[1]):
            f.write(f'#: {where}\nmsgid "{esc(s)}"\nmsgstr ""\n\n')
    print("strings:", len(found))
    if "--missing" in sys.argv:
        en = read_po(os.path.join(OUT, "en.po"))
        miss = [s for s in found if not en.get(s)]
        print("missing in en.po:", len(miss))
        for s in miss:
            print("  ", found[s], "|", s)


if __name__ == "__main__":
    main()
