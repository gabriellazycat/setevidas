"""Wraps Portuguese format templates ("... %s ..." % x) in tr() so the translation is looked up before
the values go in. Splits each line into code and string literals (respecting escapes), so quotes never
pair up wrongly. Safe to run again: already wrapped literals are skipped.

usage: python tools/i18n/wrap_tr.py
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract import wanted  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
S = os.path.join(ROOT, "godot", "scripts")
FILES = ["game/game.gd", "ui/ui.gd", "game/interactions.gd", "actors/owner.gd", "world/house.gd"] + [
    "threats/" + f for f in ["shadow.gd", "whisperer.gd", "drowner.gd", "doll.gd", "visitor.gd", "thing.gd", "hound.gd", "decay.gd", "threat.gd", "director.gd"]]
BS = chr(92)


def fix(line):
    out = []
    i = 0
    n = len(line)
    changed = False
    while i < n:
        c = line[i]
        if c == "#":
            out.append(line[i:])
            break
        if c == '"':
            j = i + 1
            while j < n and line[j] != '"':
                j += 2 if line[j] == BS else 1
            lit = line[i:j + 1]
            rest = line[j + 1:]
            prev = "".join(out)
            if re.match(r"\s*%\s", rest) and wanted(lit[1:-1]) and not prev.endswith("tr("):
                out.append("tr(" + lit + ")")
                changed = True
            else:
                out.append(lit)
            i = j + 1
        else:
            out.append(c)
            i += 1
    return "".join(out), changed


def main():
    total = 0
    for f in FILES:
        p = os.path.join(S, f)
        lines = open(p, encoding="utf-8").read().split("\n")
        n = 0
        for k, ln in enumerate(lines):
            if "print(" in ln:
                continue
            nl, ch = fix(ln)
            if ch:
                lines[k] = nl
                n += 1
        if n:
            open(p, "w", encoding="utf-8", newline="").write("\n".join(lines))
        print(f, n)
        total += n
    print("wrapped", total)


if __name__ == "__main__":
    main()
