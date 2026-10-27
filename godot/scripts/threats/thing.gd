class_name ThingThreat
extends Threat
## A Coisa no Porão: stirs on the last night when half of the mission has been moved (at 03:00 at the
## latest). It never attacks: it only makes the house harder (faster ghosts, shorter relax, a floor
## to the tension) while the cat completes the ritual on the chalk circle. Every few seconds it rears
## up (the tell) and slams for the show. Port of Thing.ts.
## Its body (thing.glb, tools/blender/build_thing.py) is a mass of arms and tentacles out of the
## circle: the eye in the core opens during the tell, the limbs rear and slam the floor with the
## wave, the nearest reach for the cat, and when the ritual ends everything sinks back and collapses.

signal wave(hit_cat)

const TENTACLE := preload("res://shaders/tentacle.gdshader")

var center := Vector3(3.6, -3, 4.4)
var group := Node3D.new()
var tentacles: Array = []
var core: MeshInstance3D
var core_mat: StandardMaterial3D
var body: Node3D
var skel: Skeleton3D
var chains: Array = []      # [{bones: [idx], base: Vector3, len: float, out: Vector3, arm: bool, phase: float}]
var eye_i := -1
var lids: MeshInstance3D
var eye_mat: ShaderMaterial
var limb_mat: ShaderMaterial
var slam := 0.0            # 1 right after a wave: the limbs whip down flat
var collapse := 0.0        # the ritual is over: everything sinks back and falls
var open_eye := 0.0
const EYE_SHADER := """
shader_type spatial;
render_mode specular_schlick_ggx;
uniform vec3 eye_fwd = vec3(0.0, 0.0, 1.0);
uniform float glow = 0.0;
void fragment() {
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 f = normalize(eye_fwd);
	float c = dot(nw, f);
	vec3 up = abs(f.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 side = normalize(cross(f, up));
	float sx = dot(nw, side);
	float iris = smoothstep(0.78, 0.82, c);
	float pupil = smoothstep(0.92, 0.94, c) * (1.0 - smoothstep(0.035, 0.06, abs(sx)));
	vec3 sclera = vec3(0.78, 0.7, 0.62) * (0.8 + 0.2 * c);
	vec3 col = mix(sclera, vec3(0.75, 0.32, 0.05), iris);
	col = mix(col, vec3(0.01), max(pupil, smoothstep(0.995, 1.0, c) * 0.0));
	ALBEDO = col;
	ROUGHNESS = 0.08;
	SPECULAR = 0.9;
	EMISSION = vec3(1.0, 0.3, 0.05) * iris * (1.0 - pupil) * glow * 2.5;
}
"""
var smoke: GPUParticles3D
var embers: GPUParticles3D
var rumble = null
var vis := 0.0
var wave_t := 0.0
var tell := 0.0
var dead := false
var ritual_items := 0


func _init() -> void:
	threat_id = "thing"
	display_name = "A Coisa no Porão"


func setup(world: Game) -> void:
	super.setup(world)
	center = w.house.ritual_center
	add_child(group)
	group.global_position = center
	var noise: Texture2D = load("res://assets/textures/gen/noise.png")
	if ResourceLoader.exists("res://assets/models/thing.glb"):
		_build_body(noise)
	for i in (0 if body else 9):
		var a := float(i) / 9.0 * TAU
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		var ln := randf_range(1.9, 2.8)
		cm.height = ln
		cm.top_radius = 0.2
		cm.bottom_radius = 0.2
		cm.rings = 40
		cm.radial_segments = 12
		mi.mesh = cm
		var m := ShaderMaterial.new()
		m.shader = TENTACLE
		m.set_shader_parameter("length", ln)
		m.set_shader_parameter("phase", i * 1.7)
		m.set_shader_parameter("out_dir", Vector3(cos(a), 0, sin(a)))
		m.set_shader_parameter("noise_tex", noise)
		mi.material_override = m
		mi.position = Vector3(cos(a) * 1.25, ln / 2.0 - 0.05, sin(a) * 1.25)
		mi.extra_cull_margin = 3.0
		group.add_child(mi)
		tentacles.append([mi, m, ln])
	core = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.5
	core.mesh = sm
	core_mat = StandardMaterial3D.new()
	core_mat.albedo_color = Color(0.1, 0.0, 0.0)
	core_mat.emission_enabled = true
	core_mat.emission = Color(1.0, 0.18, 0.1)
	core_mat.emission_energy_multiplier = 0.0
	core_mat.roughness = 0.2
	core.material_override = core_mat
	core.position.y = -0.12
	group.add_child(core)
	smoke = FX.wisps(Color(0.05, 0.0, 0.0, 0.6), 1.6, 1.4, 70, false, 0.6)
	group.add_child(smoke)
	embers = FX.embers(1.3)
	group.add_child(embers)
	group.visible = false
	smoke.emitting = false
	embers.emitting = false


## the modelled body: limb chains, the core, the eye and the lids
func _build_body(noise: Texture2D) -> void:
	body = (load("res://assets/models/thing.glb") as PackedScene).instantiate()
	group.add_child(body)
	skel = body.find_children("*", "Skeleton3D", true, false)[0]
	limb_mat = ShaderMaterial.new()
	limb_mat.shader = TENTACLE
	limb_mat.set_shader_parameter("skinned", true)
	limb_mat.set_shader_parameter("noise_tex", noise)
	eye_mat = ShaderMaterial.new()
	var es := Shader.new()
	es.code = EYE_SHADER
	eye_mat.shader = es
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.extra_cull_margin = 4.0
		var n := str(m.name)
		if n.begins_with("THING_limbs"):
			m.material_override = limb_mat
		elif n.begins_with("THING_eye"):
			m.material_override = eye_mat
		elif n.begins_with("THING_lids"):
			lids = m
			m.material_override = limb_mat
		elif n.begins_with("THING_core"):
			core = m
	if core:
		core_mat = StandardMaterial3D.new()
		core_mat.albedo_color = Color(0.06, 0.012, 0.012)
		core_mat.roughness = 0.15
		core_mat.emission_enabled = true
		core_mat.emission = Color(1.0, 0.18, 0.1)
		core_mat.emission_energy_multiplier = 0.0
		core.material_override = core_mat
	eye_i = skel.find_bone("eye")
	var by_chain := {}
	for i in skel.get_bone_count():
		var bn := skel.get_bone_name(i)
		if bn == "root" or bn == "eye":
			continue
		var key := bn.get_slice("_", 0)
		if not by_chain.has(key):
			by_chain[key] = []
		by_chain[key].append(i)
	for key in by_chain:
		var bones: Array = by_chain[key]
		bones.sort_custom(func(a, b): return int(skel.get_bone_name(a).get_slice("_", 1)) < int(skel.get_bone_name(b).get_slice("_", 1)))
		var b0 := skel.get_bone_global_rest(bones[0]).origin
		var bl := skel.get_bone_global_rest(bones[1]).origin.distance_to(b0)
		var out := Vector3(b0.x, 0, b0.z).normalized()
		chains.append({"bones": bones, "base": b0, "len": bl * bones.size(), "seg": bl, "out": out, "arm": str(key).begins_with("a"), "phase": randf() * TAU})


## every limb bends along a curve: out from the circle and swaying, standing and curling in over
## it during the tell, flat on the floor in the slam, toward the cat when it is close
func _pose_body(dt: float) -> void:
	if skel == null:
		return
	var tt := Time.get_ticks_msec() / 1000.0
	var cat_l := group.global_transform.affine_inverse() * w.cat.global_position
	var cat_h := Vector3(cat_l.x, 0, cat_l.z)
	var near := []
	if cat_h.length() < 4.0 and absf(cat_l.y) < 1.5 and stage >= 2:
		var order := range(chains.size())
		order.sort_custom(func(a, b): return (chains[a]["base"] as Vector3).distance_to(cat_h) < (chains[b]["base"] as Vector3).distance_to(cat_h))
		near = order.slice(0, 2)
	var sink := (1.0 - vis) * 2.6 + collapse * 1.6
	skel.set_bone_pose_position(skel.find_bone("root"), skel.get_bone_rest(skel.find_bone("root")).origin + Vector3(0, -sink, 0))
	for ci in chains.size():
		var c: Dictionary = chains[ci]
		var bones: Array = c["bones"]
		var o: Vector3 = c["out"]
		var sd := Vector3(-o.z, 0, o.x)
		var L: float = c["len"]
		var ph: float = c["phase"]
		var reach := 1.0 if ci in near else 0.0
		c["reach"] = lerpf(float(c.get("reach", 0.0)), reach, 1.0 - exp(-3.0 * dt))
		var pts: Array = []
		for k in bones.size() + 1:
			var h := float(k) / bones.size()
			var up := h * L
			var out_bend := (0.45 - tell * 0.8) * h * h * L
			var sway := sin(tt * 1.6 + ph + h * 4.0) * 0.35 * h * (0.6 + tell * 0.6)
			var side := cos(tt * 1.3 + ph * 1.7 + h * 3.0) * 0.25 * h
			var p: Vector3 = (c["base"] as Vector3) + Vector3(0, up, 0) + o * (out_bend + sway) + sd * side
			# slam: whipped down flat, outward
			p = p.lerp((c["base"] as Vector3) + o * h * L * 0.95 + Vector3(0, 0.08, 0), slam * h)
			# reaching for the cat: low and long toward it
			var to_cat := cat_h - (c["base"] as Vector3)
			if to_cat.length() > 0.1:
				var rp: Vector3 = (c["base"] as Vector3) + to_cat.normalized() * h * minf(L * 1.1, to_cat.length() + 0.3) + Vector3(0, 0.35 * sin(h * PI), 0)
				p = p.lerp(rp, float(c["reach"]) * h * (1.0 - slam))
			# the end: it falls in a heap
			p = p.lerp((c["base"] as Vector3) + o * h * L * 0.5 + Vector3(0, 0.05, 0), collapse * h)
			pts.append(p)
		# turn each bone to point at the next point of the curve
		for k in bones.size():
			var bi: int = bones[k]
			var par := skel.get_bone_parent(bi)
			var pg := skel.get_bone_global_pose(par)
			var rest_g := pg * skel.get_bone_rest(bi)
			var want: Vector3 = (pts[k + 1] as Vector3) - (pts[k] as Vector3)
			var cur_dir := rest_g.basis.y.normalized()
			if want.length() < 1e-4:
				continue
			var q := Quaternion(cur_dir, want.normalized())
			var g := Basis(q) * rest_g.basis.orthonormalized()
			skel.set_bone_pose_rotation(bi, (pg.basis.orthonormalized().inverse() * g).get_rotation_quaternion())
	# the eye turns to the cat; the lids open with the tell
	if eye_i >= 0:
		var par2 := skel.get_bone_parent(eye_i)
		var pg2 := skel.get_bone_global_pose(par2)
		var rg := pg2 * skel.get_bone_rest(eye_i)
		var to := (cat_l + Vector3(0, 0.15, 0) - Vector3(0, -sink, 0)) - rg.origin
		var fwd := rg.basis.y.normalized()
		if to.length() > 0.2:
			var ang := fwd.angle_to(to.normalized())
			var ax := fwd.cross(to.normalized())
			if ax.length() > 1e-4:
				var q2 := Quaternion(ax.normalized(), minf(ang, 0.9))
				skel.set_bone_pose_rotation(eye_i, (pg2.basis.orthonormalized().inverse() * (Basis(q2) * rg.basis.orthonormalized())).get_rotation_quaternion())
				eye_mat.set_shader_parameter("eye_fwd", group.global_transform.basis * (Basis(q2) * fwd))
	open_eye = lerpf(open_eye, maxf(tell, 0.12 if stage >= 2 else 0.0) * (1.0 - collapse), 1.0 - exp(-6.0 * dt))
	if lids:
		var si := lids.find_blend_shape_by_name("open")
		if si >= 0:
			lids.set_blend_shape_value(si, open_eye)
	eye_mat.set_shader_parameter("glow", tell)
	limb_mat.set_shader_parameter("rear", tell)
	limb_mat.set_shader_parameter("alpha", clampf(vis * 1.4, 0, 1) * (1.0 - collapse * 0.7))
	slam = maxf(0.0, slam - dt * 1.8)


func reset() -> void:
	stage = 0
	t = 0.0
	vis = 0.0
	group.visible = false
	if smoke:
		smoke.emitting = false
		embers.emitting = false
	if rumble:
		rumble.stop(1.0)
	rumble = null
	tell = 0.0
	wave_t = 0.0
	dead = false
	slam = 0.0
	collapse = 0.0
	open_eye = 0.0
	if w:
		w.house.lights.get_light(15).set_on(false)


func tick_threat(dt: float) -> void:
	if not enabled or dead:
		return
	if stage == 0:
		# it stirs when half of the mission has been moved (the house gets harder; it never attacks)
		if w.thing_should_wake():
			set_stage(1)
		return
	t += dt
	tick(dt)


func on_stage(s: int, _prev: int) -> void:
	if s == 1:
		w.shake(1.6)
		w.sting(0.8)
		Sfx.thud(null, 1.0, 35)
		rumble = Sfx.loop("rumble", center + Vector3(0, 0.8, 0), 1.0)
		rumble.set_level(0.9)
		for l in w.house.lights.lights:
			l.flicker = 0.9
		get_tree().create_timer(3.0).timeout.connect(func():
			for l in w.house.lights.lights:
				l.flicker = 0.0)
		var fx = w.house.lights.get_light(15)
		fx.light.global_position = center + Vector3(0, 0.6, 0)
		fx.base_color = Color("#ff3b2f")
		fx.light.light_color = fx.base_color
		fx.set_on(true)
		target.say("O que... a casa tá tremendo!", 2.6, "scared")
		w.hint("Algo acordou no porão. Leve tudo ao círculo e complete o ritual.", 5.0)
		smoke.emitting = true
		embers.emitting = true


func tick(dt: float) -> void:
	vis = lerpf(vis, 1.0, 1.0 - exp(-0.6 * dt))
	group.visible = true
	for tt in tentacles:
		var m: ShaderMaterial = tt[1]
		m.set_shader_parameter("grow", vis)
		m.set_shader_parameter("alpha", clampf(vis * 1.4, 0, 1))
		m.set_shader_parameter("rear", tell)
	_pose_body(dt)
	core_mat.emission_energy_multiplier = 1.5 * vis + tell * 6.0
	w.house.ritual_glow = 1.0 + vis * 0.4 + tell
	var fx = w.house.lights.get_light(15)
	fx.scale = 0.5 + tell * 2.5 + sin(t * 3.0) * 0.15
	if stage == 1 and t > 6.0:
		set_stage(2)
	fear_all(0.1 * dt)
	if stage >= 2:
		wave_t += dt
		# it never hurts the cat: it rears and slams for the show, and the house trembles
		var interval := d(9.0)
		var tell_dur := 2.5
		if wave_t > interval - tell_dur:
			if tell == 0.0:
				Sfx.breath(center + Vector3(0, 1, 0), 0.9)
			tell = minf(1.0, (wave_t - (interval - tell_dur)) / tell_dur)
		if wave_t > interval:
			wave_t = 0.0
			tell = 0.0
			Sfx.thud(center, 0.9, 40)
			slam = 1.0
			w.shake(0.4)
			w.shockwave(center)
			wave.emit(false)


func describe_death() -> Dictionary:
	return {
		"title": "A casa não aguentou",
		"why": "O medo das assombrações, com a Coisa acordada no porão, chegou ao limite antes de o ritual terminar.",
		"tip": "Leve os cinco objetos ao círculo e segure o ritual. A Coisa não ataca: ela deixa a casa mais difícil, então não demore.",
	}


func kill() -> void:
	Sfx.shriek(center + Vector3(0, 1, 0), 1.0)
	w.flash(0.9, Color.WHITE)
	w.shake(1.5)
	w.burst_smoke(center + Vector3(0, 0.6, 0), Color(0.1, 0.0, 0.0, 0.7))
	dead = true
	w.house.ritual_glow = 0.0
	if body:
		# everything pulls back into the circle and falls, then it is gone
		var tw := create_tween()
		tw.tween_method(func(v: float):
			collapse = v
			tell = 0.0
			_pose_body(0.016), 0.0, 1.0, 1.8).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			reset()
			dead = true)
	else:
		reset()
		dead = true


func focus():
	return center if stage > 0 else null


func entity():
	return center if stage > 0 else null


func urgency() -> float:
	return 0.35 + tell * 0.4 if stage > 0 else 0.0
