"""Client for the game's live dev controller (godot --path godot -- --devctl [--phase=... --day=N]).
python tools/dev/devctl.py "state" "ff clara.task.idx >= 30" "focus clara 34 1.6" "shot C:/tmp/a.png"
Each argument is one command (see godot/scripts/dev/devctl.gd); the replies print in order.
--port=N (7777), --timeout=SEC per command (600). --wait: retry the connection until the game is up."""
import socket
import sys
import time

sys.stdout.reconfigure(encoding="utf-8")

args = [a for a in sys.argv[1:] if not a.startswith("--")]
opts = dict((a[2:].split("=", 1) + ["1"])[:2] for a in sys.argv[1:] if a.startswith("--"))
port = int(opts.get("port", 7777))
deadline = time.time() + (90 if "wait" in opts else 0)
while True:
    try:
        s = socket.create_connection(("127.0.0.1", port), timeout=5)
        break
    except OSError:
        if time.time() > deadline:
            sys.exit("devctl: no game listening on port %d" % port)
        time.sleep(1)
s.settimeout(float(opts.get("timeout", 600)))
f = s.makefile("rwb")
for cmd in args:
    f.write((cmd + "\n").encode("utf-8"))
    f.flush()
    line = f.readline().decode("utf-8").rstrip("\n")
    print("> %s\n%s" % (cmd, line.replace(" | ", "\n")))
s.close()
