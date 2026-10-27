class_name HouseDecay
extends RefCounted
## The house wears down on its own at night, so the quiet between ghosts is for maintenance, not
## waiting: a faucet starts to leak (then the basin overflows) and a plugged-in device overheats and
## hums. Both are audible from far away and get worse the longer they are ignored; every neglected
## item speeds the ghosts up a little (`pressure`). Bulbs already burn out on their own (lights.gd).
## Items a ghost is using (drowner source, whisperer device) are left to that ghost.

const MAX_PRESSURE := 0.3
const GROW_SECONDS := 45.0

var w: Game
var items: Array = []   # {kind, ref, sev, loop}
var night := 1
var _next := 40.0
var _t := 0.0


func setup(world: Game) -> void:
	w = world


func start_night(n: int) -> void:
	stop()
	night = n
	_next = randf_range(32.0, 48.0) / maxf(0.5, w.threat_speed)


func stop() -> void:
	for it: Dictionary in items:
		_release(it, true)
	items.clear()


## extra ghost speed from what was left broken, 0..MAX_PRESSURE
func pressure() -> float:
	var s := 0.0
	for it: Dictionary in items:
		s += 0.4 + 0.6 * float(it["sev"])
	return minf(MAX_PRESSURE, s * 0.08)


func _cap() -> int:
	if night <= 2:
		return 1
	return 2 if night <= 5 else 3


func tick(dt: float) -> void:
	_t += dt
	for i in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[i]
		if _taken(it):
			_release(it, false)
			items.remove_at(i)
		elif _fixed(it):
			_release(it, true)
			items.remove_at(i)
		else:
			it["sev"] = minf(1.0, float(it["sev"]) + dt / GROW_SECONDS)
			_apply(it, dt)
	_next -= dt
	if _next <= 0.0:
		_next = randf_range(22.0, 40.0) / maxf(0.5, w.threat_speed)
		var dr: Director = w.director
		if items.size() < _cap() and dr.phase() in ["calm", "buildup"] and dr._since_wake >= 20.0:
			_spawn()


func _taken(it: Dictionary) -> bool:
	if it["kind"] == "faucet":
		var d: DrownerThreat = w.director.drowner
		return d.stage > 0 and d.source == it["ref"]
	var wh: WhispererThreat = w.director.whisperer
	return wh.stage > 0 and wh.dev == it["ref"]


func _fixed(it: Dictionary) -> bool:
	if it["kind"] == "faucet":
		return (it["ref"] as House.Faucet).running <= 0.04
	return not (it["ref"] as House.Device).plugged


func _apply(it: Dictionary, dt: float) -> void:
	var sev: float = it["sev"]
	var lp = it["loop"]
	if it["kind"] == "faucet":
		var f: House.Faucet = it["ref"]
		f.running = 0.3 + 0.3 * sev
		f.level = minf(1.0, f.level + dt * 0.012 * (0.5 + sev))
		if f.level >= 1.0:
			f.puddle = minf(1.0, f.puddle + dt * 0.02)
		if lp:
			lp.set_level(0.25 + 0.35 * sev)
	else:
		var dv: House.Device = it["ref"]
		dv.glow = lerpf(dv.glow, (0.2 + 0.35 * sev) * (0.7 + 0.3 * randf()), 1.0 - exp(-8.0 * dt))
		if lp:
			lp.set_level(0.2 + 0.4 * sev)


## stop the sound; `clean` also switches the fault itself off
func _release(it: Dictionary, clean: bool) -> void:
	var lp = it["loop"]
	if lp:
		lp.stop(0.5)
	it["loop"] = null
	if not clean:
		return
	if it["kind"] == "faucet":
		(it["ref"] as House.Faucet).running = 0.0
	else:
		(it["ref"] as House.Device).glow = 0.0


func _in_items(ref) -> bool:
	for it: Dictionary in items:
		if it["ref"] == ref:
			return true
	return false


func _spawn() -> void:
	var cp := w.cat.global_position
	var cands := []
	var dr: DrownerThreat = w.director.drowner
	var wh: WhispererThreat = w.director.whisperer
	for f: House.Faucet in w.house.faucets:
		if f.running > 0.04 or f.puddle > 0.1 or _in_items(f):
			continue
		if dr.stage > 0 and dr.source == f:
			continue
		cands.append(["faucet", f, f.handle])
	for dv: House.Device in w.house.devices:
		if not dv.plugged or dv.hidden or _in_items(dv):
			continue
		if wh.stage > 0 and wh.dev == dv:
			continue
		cands.append(["device", dv, dv.pos])
	if cands.is_empty():
		return
	# make it an errand: prefer something away from the cat
	var far := cands.filter(func(c): return (c[2] as Vector3).distance_to(cp) > 5.0)
	var pool: Array = far if not far.is_empty() else cands
	var pk: Array = pool[randi() % pool.size()]
	var it := {"kind": pk[0], "ref": pk[1], "sev": 0.0, "loop": null}
	if pk[0] == "faucet":
		var f: House.Faucet = pk[1]
		f.running = 0.3
		it["loop"] = Sfx.loop("water", f.spout, 0.7)
		Sfx.creak(f.handle, 0.2, 0.4, 2.4)
		w.hint_once("decay_faucet", "Uma torneira começou a pingar sozinha. Feche antes que alague.")
	else:
		var dv: House.Device = pk[1]
		it["loop"] = Sfx.loop("static", dv.pos, 0.8)
		w.hint_once("decay_device", "Um aparelho está esquentando sozinho. Puxe o fio.")
	items.append(it)
