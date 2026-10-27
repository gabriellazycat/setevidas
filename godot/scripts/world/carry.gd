class_name Carry
extends RefCounted
## Small objects the cat carries in its mouth: the old photograph, Breu's collar, the chest key and
## the toy mouse. Built from primitives with proper materials (they are tiny on screen).


static func _mat(c: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


## where the cat bites each thing and how it hangs from the mouth: [point in the item's own space,
## rotation (euler) of the item in the mouth frame (x across the snout, y up, z forward), optional
## shift of the bite point in the mouth frame (metres; the frame's origin sits under the chin)].
## Everything hangs down under the chin from the bite point (tuned from close shots with autopilot
## --carrytune). Flat things (photo, pages, letters, tapes, doll clothes) hang by the middle of their
## top edge, leaning a little forward of the chest; a yaw built into the mesh is undone so the edge
## stays level. Keys, the ring and the pin turn local +x down (z = -PI/2) and swing slightly forward.
const HANG := Vector3(PI / 2 - 0.45, 0, 0)
const GRIPS := {
	# by the top of the bow, which goes into the mouth
	"chave": [Vector3(-0.05, 0.004, -0.01), Vector3(-0.3, 0.4, -PI / 2), Vector3(0, 0.037, 0.011)],
	# like the chest key: the ring in the mouth, the tag hanging behind the blade
	"porao_key": [Vector3(-0.055, 0.003, 0), Vector3(-0.3, 0.4, -PI / 2), Vector3(0, 0.037, 0.011)],
	# by the scruff (head and ears in the mouth), the body and the tail dangling
	"toy": [Vector3(0, 0.045, 0.045), Vector3(-1.4, 0, 0), Vector3(0, 0.045, 0.004)],
	"foto": [Vector3(0, -0.0231, -0.0219), HANG],
	"page": [Vector3(-0.0183, -0.0271, -0.0591), Vector3(1.0357, -0.6182, -0.549)],
	"letter": [Vector3(0.0042, -0.0261, -0.0163), Vector3(1.0602, 0.5308, 0.4733)],
	"tape": [Vector3(0, -0.0211, 0.0001), HANG],
	"clothes": [Vector3(-0.0105, -0.0201, -0.0248), Vector3(0.978, -0.7712, -0.6785)],
	# by the top of the band, the bell at the bottom, turned so it is not edge-on from the side
	"coleira": [Vector3(0, 0.008, -0.05), Vector3(HANG.x, 0.6, 0)],
	"ring": [Vector3(-0.008, 0.0035, -0.008), Vector3(-0.25, 0.6, -PI / 2)],
	"pin": [Vector3(-0.021, 0.002, -0.004), Vector3(-0.35, 0.4, -PI / 2)],
	# the top of the ball in the mouth, the rest under the chin, the loose end dangling below
	"yarn": [Vector3(0, 0.088, 0), Vector3(0, 0.6, 0), Vector3(0, 0.037, 0.03)],
	# by the base's back rim, the bulb below
	"nightlight": [Vector3(0, 0.0, 0.03), Vector3(3.0, 0, 0)],
	# the doll (in the glb's own units) is as tall as the cat: bitten at the back of the dress under the
	# collar, carried across the chest face forward, so it neither covers the cat's face nor drags
	"doll": [Vector3(0, 0.23, -0.035), Vector3(-0.2, 0, -1.25)],
}
## dev: grips read from a file that win over GRIPS (autopilot --carrytune)
static var tune := {}


## the world transform of a carried thing held in the cat's mouth (mouth: the mouth frame; scale: the
## item node's own scale, so the bite point stays in the item's unscaled units)
static func held_transform(kind: String, mouth: Transform3D, scale := Vector3.ONE) -> Transform3D:
	var g: Array = tune.get(kind, GRIPS.get(kind, [Vector3.ZERO, Vector3.ZERO]))
	var b := mouth.basis * Basis.from_euler(g[1])
	var at := mouth.origin + mouth.basis * (g[2] as Vector3 if g.size() > 2 else Vector3.ZERO)
	return Transform3D(b.scaled_local(scale), at - b * ((g[0] as Vector3) * scale))


static func make(id: String) -> Node3D:
	var n := Node3D.new()
	n.name = "CARRY_" + id
	match id:
		"foto":
			var fb := BoxMesh.new()
			fb.size = Vector3(0.15, 0.012, 0.11)
			_mesh(n, fb, _mat(Color(0.28, 0.17, 0.1), 0.5), Vector3(0, 0.006, 0))
			var q := QuadMesh.new()
			q.size = Vector2(0.12, 0.085)
			var pm := StandardMaterial3D.new()
			pm.albedo_texture = load("res://assets/textures/gen/old_photo.png") if ResourceLoader.exists("res://assets/textures/gen/old_photo.png") else null
			pm.albedo_color = Color(0.9, 0.82, 0.68)
			pm.roughness = 0.75
			_mesh(n, q, pm, Vector3(0, 0.0125, 0), Vector3(-PI / 2, 0, 0))
		"coleira":
			var t := TorusMesh.new()
			t.inner_radius = 0.042
			t.outer_radius = 0.056
			t.rings = 24
			t.ring_segments = 8
			_mesh(n, t, _mat(Color(0.48, 0.09, 0.08), 0.55), Vector3(0, 0.008, 0), Vector3(0, 0, 0))
			var bell := SphereMesh.new()
			bell.radius = 0.013
			bell.height = 0.024
			_mesh(n, bell, _mat(Color(0.85, 0.66, 0.3), 0.25, 1.0), Vector3(0, 0.012, 0.064))
			var tag := CylinderMesh.new()
			tag.top_radius = 0.013
			tag.bottom_radius = 0.013
			tag.height = 0.002
			_mesh(n, tag, _mat(Color(0.8, 0.62, 0.3), 0.3, 1.0), Vector3(0.022, 0.004, 0.062))
		"chave":
			var bow := TorusMesh.new()
			bow.inner_radius = 0.014
			bow.outer_radius = 0.021
			var brass := _mat(Color(0.62, 0.46, 0.24), 0.45, 1.0)
			_mesh(n, bow, brass, Vector3(-0.042, 0.004, 0))
			var shaft := BoxMesh.new()
			shaft.size = Vector3(0.07, 0.007, 0.007)
			_mesh(n, shaft, brass, Vector3(0.01, 0.004, 0))
			var bit := BoxMesh.new()
			bit.size = Vector3(0.012, 0.007, 0.02)
			_mesh(n, bit, brass, Vector3(0.04, 0.004, 0.009))
			var bit2 := BoxMesh.new()
			bit2.size = Vector3(0.007, 0.007, 0.012)
			_mesh(n, bit2, brass, Vector3(0.028, 0.004, 0.006))
		"yarn":
			# Clara's ball of wool, a loose end trailing
			var wool := _mat(Color(0.78, 0.42, 0.45), 1.0)
			var ball := SphereMesh.new()
			ball.radius = 0.05
			ball.height = 0.1
			_mesh(n, ball, wool, Vector3(0, 0.05, 0))
			for k in 3:
				var band := TorusMesh.new()
				band.inner_radius = 0.046
				band.outer_radius = 0.052
				_mesh(n, band, _mat(Color(0.7, 0.36, 0.4), 1.0), Vector3(0, 0.05, 0), Vector3(0.5 + k * 1.1, k * 0.9, 0.3 * k))
			var end := CylinderMesh.new()
			end.top_radius = 0.003
			end.bottom_radius = 0.003
			end.height = 0.09
			# leaves the ball at its foot; the cat carries the ball by this end
			_mesh(n, end, wool, Vector3(0.0598, 0.01, -0.0253), Vector3(0, 0.4, PI / 2))
		"toy":
			var felt := _mat(Color(0.55, 0.55, 0.56), 0.95)
			var body := SphereMesh.new()
			body.radius = 0.034
			body.height = 0.055
			var b := _mesh(n, body, felt, Vector3(0, 0.026, 0))
			b.scale = Vector3(1.0, 0.85, 1.55)
			for s in [-1, 1]:
				var ear := SphereMesh.new()
				ear.radius = 0.012
				ear.height = 0.006
				_mesh(n, ear, _mat(Color(0.85, 0.55, 0.6), 0.8), Vector3(0.016 * s, 0.05, 0.03), Vector3(PI / 2, 0, 0))
			var tail := CylinderMesh.new()
			tail.top_radius = 0.002
			tail.bottom_radius = 0.003
			tail.height = 0.12
			_mesh(n, tail, _mat(Color(0.82, 0.42, 0.48), 0.6), Vector3(0, 0.016, -0.1), Vector3(PI / 2 - 0.15, 0, 0))
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return n


## a small plug-in night light: warm bulb on a white base
static func make_nightlight() -> Node3D:
	var n := Node3D.new()
	n.name = "NIGHTLIGHT"
	var base := CylinderMesh.new()
	base.top_radius = 0.035
	base.bottom_radius = 0.045
	base.height = 0.03
	_mesh(n, base, _mat(Color(0.93, 0.9, 0.84), 0.5), Vector3(0, 0.015, 0))
	var bulb := SphereMesh.new()
	bulb.radius = 0.035
	bulb.height = 0.06
	var bm := _mat(Color(1.0, 0.86, 0.6), 0.3)
	bm.emission_enabled = true
	bm.emission = Color(1.0, 0.78, 0.48)
	bm.emission_energy_multiplier = 2.5
	_mesh(n, bulb, bm, Vector3(0, 0.055, 0))
	return n


## an open cardboard box the cat pushes around in the morning and hides in at night
static func make_box() -> Node3D:
	var n := Node3D.new()
	n.name = "CAT_BOX"
	var card := _mat(Color(0.66, 0.5, 0.33), 0.9)
	var w := 0.56
	var d := 0.44
	var h := 0.36
	var t := 0.012
	var bottom := BoxMesh.new()
	bottom.size = Vector3(w, t, d)
	_mesh(n, bottom, card, Vector3(0, t / 2, 0))
	for sx in [-1.0, 1.0]:
		var side := BoxMesh.new()
		side.size = Vector3(t, h, d)
		_mesh(n, side, card, Vector3(sx * (w / 2 - t / 2), h / 2, 0))
	var back := BoxMesh.new()
	back.size = Vector3(w, h, t)
	_mesh(n, back, card, Vector3(0, h / 2, -(d / 2 - t / 2)))
	# the front is cut low: the way in
	var front := BoxMesh.new()
	front.size = Vector3(w, h * 0.35, t)
	_mesh(n, front, card, Vector3(0, h * 0.175, d / 2 - t / 2))
	for sx in [-1.0, 1.0]:
		var flap := BoxMesh.new()
		flap.size = Vector3(w / 2, t, d * 0.9)
		_mesh(n, flap, card, Vector3(sx * w / 2 * 1.35, h - 0.02, 0), Vector3(0, 0, sx * 0.5))
	return n


## Ivone's things the cat brings to the circle at night (one small mesh per kind)
static func make_relic(kind: String) -> Node3D:
	var n := Node3D.new()
	n.name = "RELIC_" + kind
	match kind:
		"page":
			var pg := BoxMesh.new()
			pg.size = Vector3(0.14, 0.004, 0.19)
			_mesh(n, pg, _mat(Color(0.86, 0.8, 0.66), 0.85), Vector3(0, 0.002, 0), Vector3(0, 0.3, 0))
			for i in 4:
				var ln := BoxMesh.new()
				ln.size = Vector3(0.1, 0.0005, 0.004)
				_mesh(n, ln, _mat(Color(0.25, 0.2, 0.25), 0.9), Vector3(-0.004, 0.0045, -0.05 + i * 0.03), Vector3(0, 0.3, 0))
		"tape":
			var tb := BoxMesh.new()
			tb.size = Vector3(0.1, 0.016, 0.064)
			_mesh(n, tb, _mat(Color(0.08, 0.07, 0.07), 0.4), Vector3(0, 0.008, 0))
			var lb := BoxMesh.new()
			lb.size = Vector3(0.08, 0.001, 0.03)
			_mesh(n, lb, _mat(Color(0.92, 0.86, 0.72), 0.8), Vector3(0, 0.0165, -0.008))
			for sx in [-0.022, 0.022]:
				var reel := CylinderMesh.new()
				reel.top_radius = 0.009
				reel.bottom_radius = 0.009
				reel.height = 0.0015
				_mesh(n, reel, _mat(Color(0.85, 0.85, 0.82), 0.5), Vector3(sx, 0.017, 0.012))
		"ring":
			var rg := TorusMesh.new()
			rg.inner_radius = 0.009
			rg.outer_radius = 0.0125
			rg.rings = 20
			rg.ring_segments = 8
			_mesh(n, rg, _mat(Color(0.86, 0.68, 0.32), 0.25, 1.0), Vector3(0, 0.0035, 0))
			var gem := SphereMesh.new()
			gem.radius = 0.004
			gem.height = 0.008
			_mesh(n, gem, _mat(Color(0.7, 0.1, 0.18), 0.1), Vector3(0.012, 0.006, 0))
		"pin":
			var bar := BoxMesh.new()
			bar.size = Vector3(0.06, 0.003, 0.006)
			_mesh(n, bar, _mat(Color(0.2, 0.18, 0.2), 0.35, 1.0), Vector3(0, 0.002, 0))
			var flower := SphereMesh.new()
			flower.radius = 0.009
			flower.height = 0.008
			_mesh(n, flower, _mat(Color(0.85, 0.55, 0.6), 0.5), Vector3(0.03, 0.004, 0))
		"clothes":
			var dress := BoxMesh.new()
			dress.size = Vector3(0.1, 0.018, 0.12)
			_mesh(n, dress, _mat(Color(0.62, 0.36, 0.42), 0.9), Vector3(0, 0.009, 0), Vector3(0, 0.4, 0))
			var lace := BoxMesh.new()
			lace.size = Vector3(0.104, 0.004, 0.014)
			_mesh(n, lace, _mat(Color(0.95, 0.92, 0.86), 0.9), Vector3(0, 0.017, 0.052), Vector3(0, 0.4, 0))
		"letter":
			var env := BoxMesh.new()
			env.size = Vector3(0.15, 0.006, 0.1)
			_mesh(n, env, _mat(Color(0.88, 0.82, 0.7), 0.85), Vector3(0, 0.003, 0), Vector3(0, -0.25, 0))
			var seal := CylinderMesh.new()
			seal.top_radius = 0.011
			seal.bottom_radius = 0.011
			seal.height = 0.003
			_mesh(n, seal, _mat(Color(0.55, 0.08, 0.08), 0.4), Vector3(0, 0.0075, 0))
	return n
