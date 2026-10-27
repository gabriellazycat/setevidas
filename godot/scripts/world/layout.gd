class_name Layout
extends RefCounted
## The house as data (rooms, walls, doors, windows, lights, navigation, spots), loaded from
## data/layout.json which is exported from the original web version's Layout.ts.

static var _d: Dictionary = {}


static func data() -> Dictionary:
	if _d.is_empty():
		var f := FileAccess.open("res://data/layout.json", FileAccess.READ)
		_d = JSON.parse_string(f.get_as_text())
	return _d


static func v3(a) -> Vector3:
	return Vector3(a[0], a[1], a[2])


static func rooms() -> Array:
	return data()["ROOMS"]


static func room(id: String) -> Dictionary:
	return data()["ROOM_BY_ID"][id]


static func spot(name: String) -> Dictionary:
	return data()["SPOTS"][name]


static func spot_pos(name: String) -> Vector3:
	return v3(spot(name)["p"])


## Which room contains a point (empty string if outside), same rules as the original roomAt().
static func room_at(p: Vector3) -> String:
	var best := ""
	var best_y := 0.0
	for r in rooms():
		if p.x < r["x0"] - 0.01 or p.x > r["x1"] + 0.01 or p.z < r["z0"] - 0.01 or p.z > r["z1"] + 0.01:
			continue
		if p.y < r["y"] - 0.45 or p.y > r["y"] + r["h"] + 0.1:
			continue
		if best == "" or absf(p.y - r["y"]) < absf(p.y - best_y):
			best = r["id"]
			best_y = r["y"]
	return best


## On a staircase or ladder between two floors (inside a floor hole, off both floors).
static func on_stairs(p: Vector3) -> bool:
	for rid in data()["FLOOR_HOLES"]:
		var top := floor_of(rid)
		if p.y < top - 2.9 or p.y > top - 0.1:
			continue
		for h in data()["FLOOR_HOLES"][rid]:
			if p.x >= h["x0"] and p.x <= h["x1"] and p.z >= h["z0"] and p.z <= h["z1"]:
				return true
	return false


static func room_name(id: String) -> String:
	if id == "":
		return TranslationServer.translate("fora de casa")
	return TranslationServer.translate(room(id)["name"])


static func floor_of(id: String) -> float:
	return float(room(id)["y"])
