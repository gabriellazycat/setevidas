extends Node
## Live dev controller (--devctl[=PORT], default 7777): the game stays open and takes one command per
## line on 127.0.0.1:PORT, replying with one line when the command is done. Client:
## python tools/dev/devctl.py "cmd" ["cmd" ...]
##   state                         phase, day, game time, Clara / Davi / cat: where, pose, step
##   steps clara|davi              the person's current task, one numbered step per line (joined by " | ")
##   phase afternoon|night|morning N   start that phase of day N
##   ff EXPR [max=SEC]             run fast (ffscale, default 8x) until EXPR is true (at most SEC game s, 120)
##   ffscale K                     the fast-forward speed
##   wait SEC                      let SEC game seconds pass
##   jump clara|davi N             put the person's task straight on step N (skips what is between)
##   eval EXPR                     a GDScript Expression; names g, ap, clara, davi, cat, rig (clara.model);
##                                 helpers idx("clara") (step number, -1 without a task), task("davi") (its name)
##   arg KEY[=VAL] / unarg KEY     set / clear an autopilot flag at runtime (any --flag of autopilot.gd)
##   rearm                         forget the autopilot's one-shot marks, so set flags run again
##   cam x,y,z,tx,ty,tz | cam off  fixed camera
##   focus clara|davi|cat VIEW [DIST] [H]  camera kept on them: front|back|side|left|34|34l|top; focus off
##   shot PATH                     save the next frame as PNG
##   timescale K                   Engine.time_scale
##   quit

var ap: Node
var g: Game
var server := TCPServer.new()
var peer: StreamPeerTCP = null
var buf := ""
var queue: Array[String] = []
var busy := {}                # the command waiting to finish: {kind, ...}
var focus := {}
var ff_scale := 8.0
var _scale0 := 1.0


func start(port: int) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var err := server.listen(port, "127.0.0.1")
	print("DEVCTL listening on 127.0.0.1:%d (%s)" % [port, error_string(err)])


func _process(dt: float) -> void:
	if g == null:
		return
	if server.is_connection_available():
		peer = server.take_connection()
		buf = ""
	if peer != null:
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			peer = null
		else:
			var n := peer.get_available_bytes()
			if n > 0:
				buf += peer.get_utf8_string(n)
				while buf.find("\n") >= 0:
					var k := buf.find("\n")
					var line := buf.substr(0, k).strip_edges()
					buf = buf.substr(k + 1)
					if line != "":
						queue.append(line)
	_update_focus()
	if not busy.is_empty():
		_tick_busy(dt)
	elif not queue.is_empty():
		_run(queue.pop_front())


func _reply(s: String) -> void:
	if peer != null and peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		peer.put_data((s.replace("\n", " | ") + "\n").to_utf8_buffer())


func _who(nm: String):
	match nm:
		"clara": return g.clara
		"davi": return g.davi
		"cat": return g.cat
	return null


func _expr(src: String):
	# 'single' quotes are easier to pass from a shell; Expression wants "double"
	src = src.replace("'", "\"")
	var e := Expression.new()
	var names := ["g", "ap", "clara", "davi", "cat", "rig"]
	if e.parse(src, PackedStringArray(names)) != OK:
		return ["ERR", e.get_error_text()]
	var r = e.execute([g, ap, g.clara, g.davi, g.cat, g.clara.model], self, true)
	if e.has_execute_failed():
		return ["ERR", e.get_error_text()]
	return ["OK", r]


## for expressions: the step number of someone's task (-1 without one) and the task's name
func idx(who: String) -> int:
	var o = _who(who)
	return int(o.task["idx"]) if o is Owner and o.task != null else -1


func task(who: String) -> String:
	var o = _who(who)
	return str(o.task["name"]) if o is Owner and o.task != null else ""


func _step_text(st: Dictionary) -> String:
	var s := str(st.get("t", "?"))
	for k in ["text", "pose", "node", "gesture", "clip", "dur"]:
		if st.has(k):
			s += " %s=%s" % [k, str(st[k]).left(50)]
	if st.has("spot"):
		s += " spot=%s" % [st["spot"].get("p")]
	return s


func _run(line: String) -> void:
	var sp := line.split(" ", false, 1)
	var cmd := sp[0]
	var rest := sp[1] if sp.size() > 1 else ""
	match cmd:
		"state":
			var out := "phase=%s day=%d mode=%s t=%.1f hour=%.2f scale=%.1f" % [g.phase, g.day, g.mode, ap.t, g.hour, Engine.time_scale]
			for o: Owner in [g.clara, g.davi]:
				var stp := "-"
				if o.task != null and o.task["idx"] < o.task["steps"].size():
					stp = "%s#%d %s" % [o.task["name"], o.task["idx"], _step_text(o.task["steps"][o.task["idx"]])]
				out += " || %s pos=%s yaw=%.2f pose=%s visible=%s step=%s" % [o.display_name, o.global_position, o.yaw, o.model.pose, o.visible, stp]
			out += " || cat pos=%s mode=%s" % [g.cat.global_position, g.cat.mode]
			_reply(out)
		"steps":
			var o: Owner = _who(rest.strip_edges())
			if o == null or o.task == null:
				_reply("no task")
				return
			var lines := ["%s (at %d)" % [o.task["name"], o.task["idx"]]]
			for i in (o.task["steps"] as Array).size():
				lines.append("%d %s" % [i, _step_text(o.task["steps"][i])])
			_reply(" | ".join(lines))
		"phase":
			var a := rest.split(" ", false)
			var d := int(a[1]) if a.size() > 1 else g.day
			match a[0]:
				"night":
					g.start_at_night(d)
				"morning":
					g.flags = SaveGame.fresh_flags()
					g.start_morning(d)
				_:
					g.day = d
					g.start_afternoon()
			_reply("OK phase=%s day=%d" % [g.phase, g.day])
		"ff":
			var a2 := rest.rsplit(" ", false, 1)
			var maxs := 120.0
			var src := rest
			if a2.size() == 2 and a2[1].begins_with("max="):
				src = a2[0]
				maxs = float(a2[1].substr(4))
			var r = _expr(src)
			if r[0] == "ERR":
				_reply("ERR " + str(r[1]))
				return
			_scale0 = Engine.time_scale
			Engine.time_scale = ff_scale
			busy = {"kind": "ff", "src": src, "left": maxs, "t0": ap.t}
		"ffscale":
			ff_scale = float(rest)
			_reply("OK")
		"wait":
			busy = {"kind": "wait", "left": float(rest)}
		"jump":
			var a3 := rest.split(" ", false)
			var o2: Owner = _who(a3[0])
			if o2 == null or o2.task == null:
				_reply("no task")
				return
			o2.task["idx"] = clampi(int(a3[1]), 0, (o2.task["steps"] as Array).size() - 1)
			o2.task["timer"] = 0.0
			o2.task["started"] = false
			o2._path = []
			_reply("OK %s" % _step_text(o2.task["steps"][o2.task["idx"]]))
		"eval":
			var r2 = _expr(rest)
			_reply(("ERR " if r2[0] == "ERR" else "") + str(r2[1]))
		"arg":
			var kv := rest.split("=", true, 1)
			ap.args[kv[0]] = kv[1] if kv.size() > 1 else "1"
			_reply("OK")
		"unarg":
			ap.args.erase(rest)
			_reply("OK")
		"rearm":
			for m in ap.get_meta_list():
				ap.remove_meta(m)
			_reply("OK")
		"cam":
			if rest == "off":
				g.rig.override_pose = {}
				focus = {}
			else:
				var c := rest.split(",")
				g.rig.override_pose = {"pos": Vector3(float(c[0]), float(c[1]), float(c[2])), "look": Vector3(float(c[3]), float(c[4]), float(c[5])), "blend": 1.0}
				focus = {}
			_reply("OK")
		"campath":
			# plays FILE's camera move from now (re-read every time); "campath off" stops it
			ap._campaths.clear()
			if rest == "off":
				ap.args.erase("campath")
				g.rig.override_pose = {}
			else:
				ap.args["campath"] = rest
				ap.args["camfrom"] = str(ap.t)
			focus = {}
			_reply("OK")
		"focus":
			var a4 := rest.split(" ", false)
			if a4[0] == "off":
				focus = {}
				g.rig.override_pose = {}
			else:
				focus = {"who": a4[0], "view": a4[1] if a4.size() > 1 else "34", "dist": float(a4[2]) if a4.size() > 2 else 2.0, "h": float(a4[3]) if a4.size() > 3 else 0.9}
				_update_focus()
			_reply("OK")
		"shot":
			busy = {"kind": "shot", "path": rest, "frames": 2}
		"timescale":
			Engine.time_scale = float(rest)
			_reply("OK")
		"quit":
			_reply("bye")
			get_tree().quit()
		_:
			_reply("ERR unknown command " + cmd)


func _tick_busy(dt: float) -> void:
	match busy["kind"]:
		"wait":
			busy["left"] -= dt
			if busy["left"] <= 0:
				busy = {}
				_reply("OK t=%.1f" % ap.t)
		"ff":
			busy["left"] -= dt
			var r = _expr(busy["src"])
			if (r[0] == "OK" and r[1]) or busy["left"] <= 0:
				Engine.time_scale = _scale0
				var hit: bool = r[0] == "OK" and r[1]
				_reply("%s after %.1f s (t=%.1f)" % ["OK" if hit else "TIMEOUT", ap.t - busy["t0"], ap.t])
				busy = {}
		"shot":
			busy["frames"] -= 1
			if busy["frames"] <= 0:
				var p: String = busy["path"]
				DirAccess.make_dir_recursive_absolute(p.get_base_dir())
				get_viewport().get_texture().get_image().save_png(p)
				busy = {}
				_reply("OK " + p)


## the camera kept on someone from one side, recomputed every frame (moves with them)
func _update_focus() -> void:
	if focus.is_empty():
		return
	var w = _who(focus["who"])
	if w == null:
		return
	var yaw: float = w.yaw if "yaw" in w else w.rotation.y
	var fw := Vector3(sin(yaw), 0, cos(yaw))
	var rt := Vector3(fw.z, 0, -fw.x)
	var dirs := {"front": fw, "back": -fw, "side": rt, "left": -rt, "34": (rt + fw).normalized(), "34l": (fw - rt).normalized(), "top": (fw * 0.3 + Vector3(0, 1, 0)).normalized()}
	var c: Vector3 = (w as Node3D).global_position + Vector3(0, focus["h"], 0)
	var d: Vector3 = dirs.get(focus["view"], fw)
	g.rig.override_pose = {"pos": c + d * float(focus["dist"]) + Vector3(0, 0.15, 0), "look": c, "blend": 1.0}
