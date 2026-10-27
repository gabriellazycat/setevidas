class_name Cat
extends CharacterBody3D
## Mingau. Camera-relative movement, sneak / run, Stray-style assisted jumps onto whatever surface is
## ahead, meow & hiss, Cat Vision draining Focus, purring in bed, hiding, scratching. Port of Cat.ts.

signal stepped(run, sneak)
signal jumped(big)
signal landed(impact)
signal meowed
signal hissed(strong)
signal startled(from)

const G := 22.0
const MAX_JUMP := 1.72
## the body (cat-local, +Z = forward): a sphere on the paws (floor contact, turns freely), a capsule lying
## along the trunk and a sphere for the head, both turned with the cat; in a jump only a short capsule
## (FLY_*) flies, so the leap clears the edge it lands on
const FEET_R := 0.1
const BODY_R := 0.07
const BODY_Y := 0.19
const BODY_Z0 := -0.2
const BODY_Z1 := 0.16
const HEAD_R := 0.07
const HEAD_P := Vector3(0, 0.25, 0.17)
const FLY_R := 0.075
const FLY_LEN := 0.22
const FLY_Y := 0.13
## the yard ends at the fence; anything past it (or under the ground) sends the cat back to where it last stood
const YARD_MARGIN := 0.35

var rig: CatRig
var house: House
var yaw := 0.0
var grounded := true
var vy := 0.0
var vel := Vector3.ZERO
var focus := 100.0
## energy through the night: running, Cat Vision and hissing burn it, purring on the bed restores it.
## Low sleep caps the Focus, slows the cat and finally drops it into short micro-naps.
var sleep := 100.0
var fatigue_on := false
var sneaking := false
var running := false
var carrying = null           # PropSystem.Carryable
var mode := "free"            # free | purr | scratch | busy | frozen | hidden
var stun_t := 0.0
var knock := Vector3.ZERO
var hunted := 0.0
var slip := 0.0
var mode_target := Vector3.ZERO
var mode_yaw := 0.0
var arc = null                # {from, to, t, dur, h}
var jump_target = null        # Vector3 or null
var extra_targets: Array = []  # Callables -> Vector3 or null: jump spots that are not furniture (a lap)
var ear_target_world = null
var alert := 0.0
var bristle := 0.0
var locked_movement := false
var speed_scale := 1.0
var wet := 0.0
var eating := 0.0
var _nap_cd := 0.0
var _meow_t := 0.0
var _hiss_t := 0.0
var _meow_cd := 0.0
var _hiss_cd := 0.0
var _idle_t := 0.0
var _step_acc := 0.0
var _land_t := 0.0
var _target_hold = null
var _marker_t := 0.0
var _jt_frame := 0
var _jt_lap := false
var col_yaw := 0.0            # where the trunk and head shapes point (lags `yaw` while turning is blocked)
var _cs_feet: CollisionShape3D
var _cs_body: CollisionShape3D
var _cs_head: CollisionShape3D
var _cs_fly: CollisionShape3D
var _xf_body := Transform3D.IDENTITY
var _xf_head := Transform3D.IDENTITY
var _xf_fly := Transform3D.IDENTITY
var _flying := false
var _test_q := PhysicsShapeQueryParameters3D.new()
var _feet_test := SphereShape3D.new()
var _sweeps: Array = []       # recent jump-arc sweeps: [{from, to, ok, t}]
var _sweep_t := -1.0
var _safe_pos = null          # last place the cat stood inside the yard
var _safe_t := 0.0
var marker: MeshInstance3D
var hide_marker := false     # trailer capture (--nohud)
var _marker_mat: StandardMaterial3D
## acting (see swat_at / pounce_at / startle / tilt_to / slow_blink)
const SWAT_SECS := 0.95
const SWAT_HIT := 0.46        # the paw meets the object
const SWAT_FREE := 0.62       # the player can walk again (the paw comes back on the way)
const SWAT_STEP := 0.28
const EDGE_CLEAR := 0.27     # cat centre to a furniture side when reared up against it
const POUNCE_WIGGLE := [0.3, 1.0]
const POUNCE_LEAP := 1.05
const STARTLE_SECS := 1.5
const STARTLE_HOP := 0.36
const STARTLE_CD := 6.0
const TILT_SECS := 2.6
const BLINK_SECS := 1.9
var _act := ""                 # swat | pounce
var _act_t := 0.0
var _act_target = null
var _act_point := Vector3.ZERO
var _act_cb := Callable()
var _act_done := false
var _act_leapt := false
var _act_land_t := 0.0
var _act_yaw := 0.0
var _act_side := "L"
var _act_step := Vector3.ZERO  # swat: how far it steps in toward the object (over SWAT_STEP)
var _startle_t := -1.0
var _startle_from := Vector3.ZERO
var _startle_cd := 0.0
var _tilt_t := -1.0
var _tilt_at = null
var _tilt_dir := 1.0
var _blink_t := -1.0
var _blink_at = null


func _ready() -> void:
	collision_layer = 16   # the cat
	collision_mask = HouseBuilder.LAYER_WORLD | 8 | HouseBuilder.LAYER_CAT_BLOCK
	floor_max_angle = deg_to_rad(62.0)
	floor_snap_length = 0.34
	floor_stop_on_slope = true
	floor_block_on_wall = true
	wall_min_slide_angle = deg_to_rad(5.0)
	safe_margin = 0.004
	var feet := SphereShape3D.new()
	feet.radius = FEET_R
	_cs_feet = _add_shape(feet, Transform3D(Basis.IDENTITY, Vector3(0, FEET_R + 0.002, 0)))
	var body := CapsuleShape3D.new()
	body.radius = BODY_R
	body.height = BODY_Z1 - BODY_Z0
	_xf_body = Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, BODY_Y, (BODY_Z0 + BODY_Z1) / 2))
	_cs_body = _add_shape(body, _xf_body)
	var hd := SphereShape3D.new()
	hd.radius = HEAD_R
	_xf_head = Transform3D(Basis.IDENTITY, HEAD_P)
	_cs_head = _add_shape(hd, _xf_head)
	var fly := CapsuleShape3D.new()
	fly.radius = FLY_R
	fly.height = FLY_LEN
	_xf_fly = Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, FLY_Y, 0))
	_cs_fly = _add_shape(fly, _xf_fly)
	_cs_fly.disabled = true
	_feet_test.radius = FEET_R - 0.02
	rig = CatRig.new(Settings.g("cat_variant") if Settings.data.has("cat_variant") else CatRig.GAME)
	add_child(rig)
	marker = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.105
	tm.outer_radius = 0.14
	tm.rings = 40
	tm.ring_segments = 4
	marker.mesh = tm
	marker.scale = Vector3(1, 0.04, 1)
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.albedo_color = Color(1.0, 0.95, 0.84, 0.0)
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_mat.no_depth_test = false
	_marker_mat.emission_enabled = true
	_marker_mat.emission = Color(1.0, 0.92, 0.75)
	_marker_mat.emission_energy_multiplier = 1.4
	marker.material_override = _marker_mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.top_level = true
	add_child(marker)


func _add_shape(sh: Shape3D, xf: Transform3D) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = sh
	cs.transform = xf
	add_child(cs)
	return cs


var forward: Vector3:
	get:
		return Vector3(sin(yaw), 0, cos(yaw))


var pos: Vector3:
	get:
		return global_position
	set(v):
		global_position = v


func head() -> Vector3:
	return global_position + Vector3(0, 0.3, 0)


func teleport(p: Vector3, y := yaw) -> void:
	global_position = p
	vel = Vector3.ZERO
	velocity = Vector3.ZERO
	vy = 0.0
	yaw = y
	arc = null
	grounded = true
	mode = "free"
	rotation.y = yaw
	col_yaw = yaw
	_set_flying(false)
	_apply_col()
	reset_physics_interpolation()


func stun(sec: float, from: Vector3) -> void:
	stun_t = sec
	focus = maxf(0.0, focus - 60.0)
	arc = null
	vy = 0.0
	var away := Vector3(global_position.x - from.x, 0, global_position.z - from.z)
	if away.length_squared() < 1e-4:
		away = forward
	knock = away.normalized() * 5.5
	vel = Vector3.ZERO


## the cat's walking pace right now (slower while carrying or drowsy); what the ghosts that must not outpace it use
func walk_speed() -> float:
	return 2.1 * speed_scale * (0.85 if carrying != null else 1.0) * (1.0 - 0.18 * drowsy())


## 0 = rested .. 1 = about to drop, grows below 40 sleep
func drowsy() -> float:
	return clampf((40.0 - sleep) / 40.0, 0.0, 1.0) if fatigue_on else 0.0


func _tick_sleep(dt: float) -> void:
	if not fatigue_on:
		return
	if mode == "purr" or mode == "lap":
		sleep = minf(100.0, sleep + 3.5 * dt)
	else:
		var drain := 0.12
		if running and Vector2(vel.x, vel.z).length() > 0.5:
			drain += 0.6
		sleep = maxf(0.0, sleep - drain * dt)
	var dz := drowsy()
	if dz > 0.0:
		focus = minf(focus, 100.0 - 55.0 * dz)
	# micro-nap: a short freeze, only when nearly out, never while hidden or held by something
	_nap_cd -= dt
	if sleep < 10.0 and _nap_cd <= 0.0 and mode == "free" and stun_t <= 0.0:
		_nap_cd = randf_range(7.0, 12.0)
		stun_t = 0.9
		knock = Vector3.ZERO


func meow() -> bool:
	if _meow_cd > 0:
		return false
	_meow_cd = 1.1
	_meow_t = 0.65
	_idle_t = 0.0
	meowed.emit()
	return true


func hiss():
	if _hiss_cd > 0 or (carrying != null and carrying.id == "doll"):
		return null
	_hiss_cd = 1.3
	_hiss_t = 0.9
	_idle_t = 0.0
	var strong := focus >= 22.0
	if strong:
		focus -= 22.0
		sleep = maxf(0.0, sleep - 2.0)
	hissed.emit(strong)
	return strong


# ---------------------------------------------------------------------- acting
# One-off animations over the cat's own movement (picked from the variations in tools/review/gato_anim).
# Targets are a Node3D (followed while it moves) or a Vector3.


static func _ramp(x: float, a: float, b: float, c := INF, d := INF) -> float:
	if c == INF:
		return smoothstep(a, b, x)
	return smoothstep(a, b, x) * (1.0 - smoothstep(c, d, x))


static func _at(target) -> Vector3:
	if target is Node3D:
		return (target as Node3D).global_position if is_instance_valid(target) else Vector3.INF
	return target if target is Vector3 else Vector3.INF


func acting() -> bool:
	return _act != ""


## seconds the cat has stood still (0 while moving, acting or busy)
func idle_secs() -> float:
	return _idle_t


## the paw goes to the object, eyes on it the whole time, and knocks it at SWAT_HIT (on_contact is called
## then); the cat turns only as far as the paw cannot reach sideways. Movement is held until SWAT_FREE.
func swat_at(target, on_contact := Callable()) -> bool:
	if _act != "" or mode != "free" or not grounded or arc != null or stun_t > 0:
		return false
	var p := _at(target)
	if p == Vector3.INF:
		return false
	var rel := wrapf(atan2(p.x - global_position.x, p.z - global_position.z) - yaw, -PI, PI)
	_act = "swat"
	_act_t = 0.0
	_act_target = target
	_act_point = p
	_act_cb = on_contact
	_act_done = false
	_act_yaw = yaw + rel - clampf(rel, -0.55, 0.55)
	_act_side = "L" if rel >= 0.0 else "R"
	# out of the paw's reach: a little step toward it while turning
	var sh := global_position + Basis(Vector3.UP, _act_yaw) * Vector3(rig._shoulder_rest.x * (1.0 if _act_side == "L" else -1.0), 0, rig._shoulder_rest.z)
	var to := Vector3(p.x - sh.x, 0, p.z - sh.z)
	var want := to.length() - rig._fore_reach * 0.8
	# up on furniture: it rears up against the side, so the head must stay clear of the edge (it may back off)
	var edge := _edge_toward(p, target)
	if edge < INF:
		want = minf(want, edge - EDGE_CLEAR)
	_act_step = to.normalized() * clampf(want, -0.2, 0.35) if to.length() > 0.01 else Vector3.ZERO
	_idle_t = 0.0
	return true


## short butt wiggle (variation B), then the leap onto the target; on_land is called as the paws come down
func pounce_at(target, on_land := Callable()) -> bool:
	if _act != "" or mode != "free" or not grounded or arc != null or stun_t > 0:
		return false
	var p := _at(target)
	if p == Vector3.INF:
		return false
	_act = "pounce"
	_act_t = 0.0
	_act_target = target
	_act_point = p
	_act_cb = on_land
	_act_done = false
	_act_yaw = atan2(p.x - global_position.x, p.z - global_position.z)
	_idle_t = 0.0
	return true


## jumps up arched and puffed, facing the scare (variation A); never stops the player walking (moving, the
## hump and the hiss are smaller). Has its own cooldown, so the game can call it freely.
func startle(from: Vector3) -> bool:
	if _startle_cd > 0.0 or mode not in ["free", "busy"] or arc != null or stun_t > 0.0:
		return false
	_startle_t = 0.0
	_startle_cd = STARTLE_CD
	_startle_from = from
	_idle_t = 0.0
	startled.emit(from)
	return true


## the head tilt only plays over standing, sitting or lying still: never over another animation
## (eating, a meow or hiss, a swat or pounce, a startle, a jump, a stun, something in its mouth)
func _tilt_ok() -> bool:
	return mode == "free" and _act == "" and _startle_t < 0.0 and eating <= 0.0 and _meow_t <= 0.0 		and _hiss_t <= 0.0 and stun_t <= 0.0 and arc == null and grounded and carrying == null 		and Vector2(vel.x, vel.z).length() <= 0.6


## a slow curious head tilt toward someone (variation A): Clara talking, a sound
func tilt_to(at) -> bool:
	if _tilt_t >= 0.0 or not _tilt_ok():
		return false
	_tilt_t = 0.0
	_tilt_at = at
	_tilt_dir = 1.0 if randf() < 0.5 else -1.0
	return true


## the slow blink of a cat that trusts you, the head dipping with it (variation B)
func slow_blink(at = null) -> bool:
	if _blink_t >= 0.0 or _act != "" or _startle_t >= 0.0:
		return false
	_blink_t = 0.0
	_blink_at = at
	return true


## how far (from the cat, level) the side of the furniture a high target stands on is; INF when the
## target is not up on something
func _edge_toward(p: Vector3, target) -> float:
	if house == null or p.y - global_position.y < 0.22:
		return INF
	var ex: Array[RID] = [get_rid()]
	if target is CollisionObject3D and is_instance_valid(target):
		ex.append((target as CollisionObject3D).get_rid())
	# a few heights from just under the object down: a thin table top, an apron, the legs
	var best := INF
	var y := p.y - 0.02
	while y > global_position.y + 0.08:
		var from := Vector3(global_position.x, y, global_position.z)
		var q := PhysicsRayQueryParameters3D.create(from, Vector3(p.x, y, p.z), collision_mask & ~HouseBuilder.LAYER_CAT_BLOCK)
		q.exclude = ex
		var hit := house.space.intersect_ray(q)
		if hit:
			best = minf(best, Vector2(hit["position"].x - from.x, hit["position"].z - from.z).length())
		y -= 0.05
	return best


## yaw/pitch (rig pose values) that point the head at p from where the head is now
func _look_angles(p: Vector3) -> Vector2:
	var h := rig.head_world()
	var rel := wrapf(atan2(p.x - h.x, p.z - h.z) - yaw, -PI, PI)
	var flat := Vector2(p.x - h.x, p.z - h.z).length()
	return Vector2(clampf(rel, -1.3, 1.3), clampf(atan2(h.y - p.y, maxf(flat, 0.05)), -0.55, 0.95))


func _act_locks() -> bool:
	return (_act == "swat" and _act_t < SWAT_FREE) or _act == "pounce"


func _tick_acting(dt: float) -> void:
	_startle_cd -= dt
	if _act != "":
		_act_t += dt
		var p := _at(_act_target)
		match _act:
			"swat":
				if not _act_done and p != Vector3.INF:
					_act_point = p
				if _act_t < 0.3:
					yaw = lerp_angle(yaw, _act_yaw, 1.0 - exp(-14.0 * dt))
				if _act_t < SWAT_STEP and _act_step != Vector3.ZERO:
					move_and_collide(_act_step * (dt / SWAT_STEP))
				if not _act_done and _act_t >= SWAT_HIT:
					_act_done = true
					if _act_cb.is_valid():
						_act_cb.call()
				if _act_t >= SWAT_SECS or (_act_t > SWAT_FREE and Vector2(vel.x, vel.z).length() > 0.3):
					_act = ""
			"pounce":
				if not _act_done and p != Vector3.INF:
					_act_point = p
				if _act_t < POUNCE_LEAP:
					yaw = lerp_angle(yaw, _act_yaw, 1.0 - exp(-10.0 * dt))
				elif arc == null and not _act_leapt:
					_act_leapt = true
					var me := global_position
					var d := Vector3(_act_point.x - me.x, 0, _act_point.z - me.z)
					var dist := clampf(d.length() - 0.12, 0.0, 1.4)
					var dir := d.normalized() if d.length() > 0.01 else forward
					var to := me + dir * dist
					if house:
						to.y = house.ground_height(to.x, to.z, me.y + 0.3, 0.02)
					yaw = atan2(dir.x, dir.z)
					arc = {"from": me, "to": to, "t": 0.0, "dur": 0.3 + dist * 0.12, "h": 0.1 + dist * 0.06, "kind": ""}
					jumped.emit(false)
				elif arc == null and _act_leapt and not _act_done:
					_act_done = true
					_act_land_t = _act_t
					if _act_cb.is_valid():
						_act_cb.call()
				if _act_done and _act_t - _act_land_t > 0.55:
					_act = ""
					_act_leapt = false
	if _act == "":
		_act_leapt = false
	if _startle_t >= 0.0:
		_startle_t += dt
		# the jump itself: the model springs up off the paws (the body stays where it is)
		var s := _startle_t / STARTLE_HOP
		rig.position.y = 0.17 * 4.0 * s * (1.0 - s) if s < 1.0 else 0.0
		if _startle_t >= STARTLE_SECS:
			_startle_t = -1.0
			rig.position.y = 0.0
	if _tilt_t >= 0.0:
		_tilt_t += dt
		# walking off or starting anything else (eating, a meow, a jump...) ends it at once: the rig's
		# damping eases the head back
		if _tilt_t >= TILT_SECS or not _tilt_ok():
			_tilt_t = -1.0
	if _blink_t >= 0.0:
		_blink_t += dt
		if _blink_t >= BLINK_SECS:
			_blink_t = -1.0


## lays the acting over the pose the cat would have anyway
func _act_pose(pose: Dictionary, speed: float) -> void:
	var look_w := 0.0
	var look := Vector2.ZERO
	if _blink_t >= 0.0:
		var b := _ramp(_blink_t, 0.0, 0.7, 1.2, BLINK_SECS)
		pose["slowblink"] = b
		pose["head_pitch"] = float(pose.get("head_pitch", 0.0)) + 0.25 * b
		pose["tilt"] = float(pose.get("tilt", 0.0)) + 0.12 * b
		pose["ear_alert"] = float(pose["ear_alert"]) * (1.0 - b)
		var bp := _at(_blink_at) if _blink_at != null else Vector3.INF
		if bp != Vector3.INF:
			look = _look_angles(bp + Vector3(0, 0.0, 0))
			look_w = _ramp(_blink_t, 0.0, 0.3, BLINK_SECS - 0.3, BLINK_SECS)
	if _tilt_t >= 0.0:
		var e := _ramp(_tilt_t, 0.1, 0.9, 1.9, TILT_SECS - 0.1)
		pose["tilt"] = float(pose.get("tilt", 0.0)) + 0.5 * _tilt_dir * e
		pose["ear_alert"] = maxf(float(pose["ear_alert"]), e)
		pose["ear_yaw"] = 0.0
		var tp := _at(_tilt_at)
		if tp != Vector3.INF:
			look = _look_angles(tp)
			look.y -= 0.08
			look_w = _ramp(_tilt_t, 0.0, 0.5, TILT_SECS - 0.5, TILT_SECS)
	if _startle_t >= 0.0:
		var sc := _ramp(_startle_t, 0.0, 0.05, STARTLE_SECS - 0.5, STARTLE_SECS)
		var still := 1.0 - clampf(speed / 1.5, 0.0, 1.0)
		pose["arch"] = sc * lerpf(0.5, 1.3, still)
		pose["hiss"] = maxf(float(pose["hiss"]), sc * lerpf(0.35, 0.9, still))
		pose["bristle"] = maxf(float(pose["bristle"]), sc)
		pose["pupil"] = lerpf(float(pose["pupil"]), 1.0, sc)
		pose["tail_up"] = lerpf(float(pose["tail_up"]), 1.0, sc)
		pose["sit"] = 0.0
		pose["lie"] = 0.0 if mode == "free" else pose["lie"]
		look = _look_angles(_startle_from + Vector3(0, 0.3, 0))
		look_w = sc * lerpf(0.4, 1.0, still)
		# in the air the body turns side-on to the scare (only the model, the body keeps its heading)
		var side := signf(look.x) if absf(look.x) > 0.05 else 1.0
		rig.rotation.y = clampf(look.x - side * PI * 0.5, -0.6, 0.6) * _ramp(_startle_t, 0.0, 0.15, 0.9, 1.4) * still
	elif rig.rotation.y != 0.0:
		rig.rotation.y = 0.0
	match _act:
		"swat":
			var t := _act_t
			var lift := _ramp(t, 0.1, 0.36)
			var push := _ramp(t, 0.36, SWAT_HIT + 0.03)
			var amt := lift * (1.0 - _ramp(t, SWAT_FREE, SWAT_SECS))
			var me := global_position
			var d := Vector3(_act_point.x - me.x, 0, _act_point.z - me.z)
			var dir := d.normalized() if d.length() > 0.01 else forward
			# hovers behind and above it, then strikes through it
			var hover := _act_point - dir * 0.07 + Vector3.UP * 0.07
			var through := _act_point + dir * 0.035 + Vector3.UP * 0.025
			pose["swat"] = amt
			if t < SWAT_STEP and _act_step != Vector3.ZERO:
				pose["speed"] = _act_step.length() / SWAT_STEP
			pose["swat_side"] = _act_side
			pose["swat_target"] = rig.to_local(hover.lerp(through, push))
			pose["crouch"] = maxf(float(pose["crouch"]), 0.3 * _ramp(t, 0.0, 0.15, 0.5, 0.8))
			pose["ear_alert"] = 1.0
			pose["ear_yaw"] = 0.0
			pose["pupil"] = lerpf(float(pose["pupil"]), 0.85, _ramp(t, 0.0, 0.2))
			pose["sit"] = 0.0
			# eyes on the object, following it when it falls
			var lp := _at(_act_target)
			look = _look_angles(lp if lp != Vector3.INF else _act_point)
			look_w = _ramp(t, 0.0, 0.12, SWAT_SECS - 0.2, SWAT_SECS + 0.2)
		"pounce":
			var t := _act_t
			var pre := t < POUNCE_LEAP or not _act_leapt
			pose["crouch"] = _ramp(t, 0.05, 0.3) if pre else (0.7 * _ramp(t - _act_land_t, 0.0, 0.08, 0.35, 0.55) if _act_done else 0.0)
			pose["wiggle"] = _ramp(t, POUNCE_WIGGLE[0], POUNCE_WIGGLE[0] + 0.15, POUNCE_WIGGLE[1] - 0.1, POUNCE_WIGGLE[1])
			pose["wiggle_rate"] = 10.0
			pose["pupil"] = 1.0
			pose["ear_alert"] = 1.0
			pose["ear_yaw"] = 0.0
			pose["tail_up"] = 0.3
			pose["sit"] = 0.0
			look = _look_angles(_act_point)
			look.y += 0.15
			look_w = 1.0
	if look_w > 0.0:
		pose["head_yaw"] = lerpf(float(pose["head_yaw"]), look.x, look_w)
		pose["head_pitch"] = lerpf(float(pose.get("head_pitch", 0.0)), look.y, look_w)


func tick(dt: float, cam_yaw: float, controls: bool) -> void:
	_meow_cd -= dt
	_hiss_cd -= dt
	_meow_t = maxf(0.0, _meow_t - dt)
	_hiss_t = maxf(0.0, _hiss_t - dt)
	_land_t = maxf(0.0, _land_t - dt)
	stun_t = maxf(0.0, stun_t - dt)
	_tick_acting(dt)

	var mv := Vector2.ZERO
	if controls and mode == "free" and not locked_movement and stun_t <= 0 and not _act_locks():
		mv = Controls.move_vector()
		if Settings.g("sneak_toggle"):
			if Input.is_action_just_pressed("sneak"):
				sneaking = not sneaking
		else:
			sneaking = Input.is_action_pressed("sneak")
		running = Input.is_action_pressed("run") and carrying == null
		if running:
			sneaking = false
	# Focus (the strong hiss) comes back on its own, faster purring
	focus = minf(100.0, focus + (9.0 if mode == "purr" or mode == "lap" else 5.5) * dt)
	_tick_sleep(dt)
	if controls and mode != "frozen":
		if Input.is_action_just_pressed("meow"):
			meow()
		if Input.is_action_just_pressed("hiss") and mode == "free":
			hiss()

	# camera-relative move
	var fx := sin(cam_yaw)
	var fz := cos(cam_yaw)
	var dx := fx * mv.y - fz * mv.x
	var dz := fz * mv.y + fx * mv.x
	var mag := minf(1.0, Vector2(dx, dz).length())
	if mag > 1e-3:
		var l := Vector2(dx, dz).length()
		dx /= l
		dz /= l
	var max_speed := (0.95 if sneaking else (4.4 if running else 2.1)) * speed_scale * (0.85 if carrying != null else 1.0) * (1.0 - 0.18 * drowsy())
	var target := mag * max_speed
	var accel := (11.0 if target > Vector2(vel.x, vel.z).length() else 9.0) * lerpf(1.0, 0.28, slip)
	vel.x = lerpf(vel.x, dx * target, 1.0 - exp(-accel * dt))
	vel.z = lerpf(vel.z, dz * target, 1.0 - exp(-accel * dt))
	var speed := Vector2(vel.x, vel.z).length()
	if speed > 0.08 and mode == "free":
		yaw = lerp_angle(yaw, atan2(vel.x, vel.z), 1.0 - exp(-12.0 * dt))

	if arc == null and _flying:
		_set_flying(false)
	if mode in ["purr", "lap", "scratch", "busy", "hidden", "nap"]:
		vel = Vector3.ZERO
		velocity = Vector3.ZERO
		var k := 1.0 - exp(-8.0 * dt)
		global_position = global_position.lerp(mode_target, k)
		yaw = lerp_angle(yaw, mode_yaw, k)
		arc = null
		grounded = true
		vy = 0.0
	elif arc != null:
		arc["t"] += dt / arc["dur"]
		var t := minf(1.0, arc["t"])
		var p := arc_point(arc, t)
		var prev := global_position
		var bumped := false
		if arc.get("kind", "") == "lap":
			# into Clara's lap: she is not solid, and the sofa under her must not stop it
			global_position = p
		else:
			_set_flying(true)
			bumped = move_and_collide(p - prev) != null
		vy = (global_position.y - prev.y) / maxf(dt, 1e-4)
		grounded = false
		if bumped:
			# hit something mid-air (a shelf edge, a lintel, a railing): the leap ends, it falls from here
			arc = null
			_set_flying(false)
			vy = minf(vy, 0.0)
			vel = Vector3.ZERO
		elif t >= 1.0:
			global_position = arc["to"]
			arc = null
			_set_flying(false)
			_fit_landing()
			grounded = true
			_land_t = 0.18
			landed.emit(maxf(0.0, -vy))
			vy = 0.0
	elif mode == "free":
		var hv := Vector3(vel.x, 0, vel.z)
		if knock.length_squared() > 0.001:
			hv += knock
			knock *= maxf(0.0, 1.0 - 5.0 * dt)
		var was_floor := is_on_floor()
		if was_floor and vy < 1.0:   # a fresh jump (vy > 0) must survive its first frame on the floor
			vy = minf(vy, 0.0)
		else:
			vy -= G * dt
		velocity = Vector3(hv.x, vy, hv.z)
		move_and_slide()
		# push props we walk into
		for i in get_slide_collision_count():
			var c := get_slide_collision(i)
			var col := c.get_collider()
			if col is RigidBody3D and house:
				for pr in house.props.props:
					if pr.body == col:
						house.props.wake(pr)
				(col as RigidBody3D).apply_central_impulse(-c.get_normal() * maxf(0.4, hv.length()) * 0.08)
		var on := is_on_floor()
		if on and _perched():
			on = false
		if on and not grounded:
			var impact := -vy
			if impact > 2.0:
				_land_t = 0.18
				landed.emit(impact)
		grounded = on
		if on:
			vy = 0.0
		else:
			vy = velocity.y
		_safety_net(dt, on)

	# jump
	_jt_frame += 1
	if _jt_frame % 2 == 0 or Input.is_action_just_pressed("jump"):
		_find_jump_target(Vector3(dx, 0, dz) if mag > 0.1 else Vector3.ZERO, Input.is_action_just_pressed("jump"))
	if controls and mode == "free" and Input.is_action_just_pressed("jump") and grounded and arc == null and not _act_locks():
		if jump_target != null:
			var to: Vector3 = jump_target
			var dist := Vector2(to.x - global_position.x, to.z - global_position.z).length()
			var dyv := to.y - global_position.y
			var kind := "lap" if _jt_lap else ("up" if dyv > 0 else "down")
			arc = {"from": global_position, "to": to, "t": 0.0, "dur": 0.3 + dist * 0.09 + absf(dyv) * 0.07, "h": _arc_h(kind, dyv), "kind": kind}
			yaw = atan2(to.x - global_position.x, to.z - global_position.z)
			jumped.emit(dyv > 0.6)
		else:
			vy = 6.0
			grounded = false
			global_position.y += 0.02
			jumped.emit(false)
		_idle_t = 0.0

	# footsteps
	if grounded and arc == null and mode == "free" and speed > 0.2:
		_step_acc += speed * dt
		var stride := 0.42 if running else 0.24
		if _step_acc > stride:
			_step_acc = 0.0
			stepped.emit(running, sneaking)

	# pose
	if speed > 0.15 or not grounded or mode != "free" or alert > 0.5:
		_idle_t = 0.0
	else:
		_idle_t += dt
	var pupil := clampf(0.48 + alert * 0.3 + hunted * 0.4, 0, 1)
	var ear_yaw := 0.0
	var head_yaw := 0.0
	if ear_target_world != null:
		var tw: Vector3 = ear_target_world
		var ang := atan2(tw.x - global_position.x, tw.z - global_position.z)
		var rel := wrapf(ang - yaw, -PI, PI)
		ear_yaw = -rel
		head_yaw = clampf(-rel * 0.35 * alert * (1.0 if speed < 0.3 else 0.3), -0.7, 0.7)
	var pose := {
		"speed": speed if mode == "free" else 0.0,
		"grounded": grounded and arc == null,
		"vy": vy,
		"run": running,
		"crouch": 1.0 if sneaking or mode == "hidden" else (0.6 if arc != null and arc["t"] < 0.12 else 0.0),
		"sit": 1.0 if mode == "free" and _idle_t > 2.5 and _idle_t < 25.0 else 0.0,
		"lie": 1.0 if mode == "purr" or mode == "lap" or mode == "nap" or stun_t > 0 or (mode == "free" and _idle_t >= 25.0) else 0.0,
		"meow": 1.0 if _meow_t > 0 else 0.0,
		"hiss": 1.0 if _hiss_t > 0 else 0.0,
		"bristle": bristle,
		"tail_up": clampf(focus / 100.0, 0, 1) * (1.0 - bristle * 0.3),
		"land": 1.0 if _land_t > 0 else 0.0,
		"purr": 1.0 if mode == "purr" or mode == "lap" else 0.0,
		"curl": 1.0 if mode == "purr" or mode == "nap" else 0.0,
		"scratch": 1.0 if mode == "scratch" else 0.0,
		"carry": carrying != null,
		"pupil": pupil,
		"ear_alert": alert,
		"ear_yaw": -ear_yaw,
		"head_yaw": -head_yaw,
		"head_pitch": 0.0,
		"wet": wet,
		"eat": eating,
	}
	_act_pose(pose, speed)
	_turn_body()
	rotation.y = yaw
	_apply_col()
	rig.update_pose(dt, pose)

	# jump marker
	_marker_t += dt
	var show: bool = jump_target != null and grounded and arc == null and mode == "free"
	var a := _marker_mat.albedo_color.a
	a = lerpf(a, (0.55 + 0.2 * sin(_marker_t * 6.0)) if show else 0.0, 1.0 - exp(-12.0 * dt))
	_marker_mat.albedo_color.a = a
	marker.visible = a > 0.02 and not hide_marker
	if jump_target != null:
		marker.global_position = (jump_target as Vector3) + Vector3(0, 0.012, 0)
	var sc := 1.0 + 0.08 * sin(_marker_t * 6.0)
	marker.scale = Vector3(sc, 0.04, sc)


## Stray-style assisted jump: find a surface ahead (up onto furniture, or down to the floor). Floor
## raycasts list the candidates; only the best one gets its whole arc swept with the flying body
## (cached, ~10 Hz; always fresh on the frame the jump is pressed).
func _find_jump_target(move_dir: Vector3, force := false) -> void:
	if not grounded or arc != null or mode != "free" or house == null:
		jump_target = null
		_jt_lap = false
		return
	var dir := move_dir.normalized() if move_dir.length() > 0.01 else forward
	var side := Vector3(dir.z, 0, -dir.x)
	var ups: Array = []
	var downs: Array = []
	var p0 := global_position
	var y0 := p0.y
	var d := 0.35
	while d <= 2.05 and ups.size() < 3:
		for lat: float in [0.0, 0.14, -0.14]:
			var px := p0.x + dir.x * d + side.x * lat
			var pz := p0.z + dir.z * d + side.z * lat
			var top := house.ground_height(px, pz, y0 + MAX_JUMP, 0.02)
			var dy := top - y0
			var up := dy > 0.3
			var down := dy < -0.45 and dy > -3.2
			if not up and not down:
				continue
			if down and (not downs.is_empty() or d > 1.6):
				continue
			if not _landing_ok(px, pz, top):
				continue
			# land a little further in when the top goes on: the leap should not end right on the edge
			var p := Vector3(px, top, pz)
			var q := p + dir * 0.12
			var list: Array = ups if up else downs
			if _landing_ok(q.x, q.z, top):
				list.append(q)
			list.append(p)
			if up:
				break
		d += 0.1
	var best = null
	_jt_lap = false
	for c in ups + downs:
		if _arc_clear(p0, c, force) != 0:
			best = c
			break
	# spots offered by the game (Clara's lap): ahead, within reach, above the floor; no sweep, she is soft
	for fn in extra_targets:
		var ep = (fn as Callable).call()
		if ep == null:
			continue
		var ev: Vector3 = ep
		var to_e := Vector3(ev.x - p0.x, 0, ev.z - p0.z)
		if to_e.length() < 2.2 and to_e.length() > 0.2 and to_e.normalized().dot(dir) > 0.5 and ev.y - y0 > 0.25:
			best = ev
			_jt_lap = true
	var th = _target_hold
	if best == null and th != null:
		var thv: Vector3 = th
		var facing := (thv.x - p0.x) * dir.x + (thv.z - p0.z) * dir.z > 0.25
		if facing and thv.distance_to(p0) < 2.2:
			var top2 := house.ground_height(thv.x, thv.z, thv.y + 0.02)
			if absf(top2 - thv.y) < 0.01 and absf(top2 - y0) > 0.3 and _arc_clear(p0, thv, force) != 0:
				best = th
	jump_target = best
	_target_hold = best


## landed where the long body does not fit as it flew (a narrow sill, facing the glass): turn sideways
func _fit_landing() -> void:
	if house == null or _fits(global_position, yaw):
		col_yaw = yaw
		return
	for yy: float in [yaw + PI / 2, yaw - PI / 2, yaw + PI]:
		if _fits(global_position, yy):
			yaw = yy
			col_yaw = yy
			return


## standing on its belly or chin on a ledge (a sill, a step edge) with the paws in the air: the long body
## would let it hang there, so it slides off toward the lower side
func _perched() -> bool:
	var p := global_position
	if _floor_below(p) < 0.1:
		return false
	var best := Vector3.ZERO
	var low := -INF
	var f := Vector3(sin(col_yaw), 0, cos(col_yaw))
	for dv: Vector3 in [f, -f, Vector3(f.z, 0, -f.x), Vector3(-f.z, 0, f.x)]:
		var drop := _floor_below(p + dv * 0.22, 0.3)
		if drop > low:
			low = drop
			best = dv
	knock = best * 1.6
	return true


## how far below the paws the ground is at p (world and props; not the cat-only walls)
func _floor_below(p: Vector3, from := 0.06) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, from, 0), p + Vector3(0, -1.0, 0), collision_mask & ~HouseBuilder.LAYER_CAT_BLOCK)
	q.exclude = [get_rid()]
	var hit := house.space.intersect_ray(q) if house else {}
	return p.y - float(hit["position"].y) if hit else 1.0


## a flat top with room above it for a cat
func _landing_ok(px: float, pz: float, top: float) -> bool:
	if house.ceiling_height(px, pz, top + 0.01) - top < 0.32:
		return false
	for o in [Vector2(0.07, 0), Vector2(-0.07, 0), Vector2(0, 0.07), Vector2(0, -0.07)]:
		if absf(house.ground_height(px + o.x, pz + o.y, top + 0.05) - top) > 0.06:
			return false
	return true


static func _arc_h(kind: String, dy: float) -> float:
	if kind == "up":
		return 0.14 + dy * 0.1
	return 0.14


## where a leap is at t (0..1). Up: it springs up first (height eases out, distance eases in and out),
## so it clears the edge it lands on; down: it steps out first, then drops. Other arcs (the game's
## knock-backs) go in a plain parabola.
static func arc_point(a: Dictionary, t: float) -> Vector3:
	var from: Vector3 = a["from"]
	var to: Vector3 = a["to"]
	var kind: String = a.get("kind", "")
	var txz := t
	var ty := t
	if kind == "up":
		txz = t * t * (3.0 - 2.0 * t)
		ty = 1.0 - pow(1.0 - t, 3.0)
	elif kind == "down":
		txz = 1.0 - (1.0 - t) * (1.0 - t)
		ty = t * t
	var p := from.lerp(to, txz)
	p.y = lerpf(from.y, to.y, ty) + float(a["h"]) * 4.0 * t * (1.0 - t)
	return p


## 1 = the flying body gets from p0 to `to` along the leap, 0 = it hits something on the way,
## -1 = not swept yet (throttled; treated as possible until the jump is pressed)
func _arc_clear(p0: Vector3, to: Vector3, force: bool) -> int:
	var now := Time.get_ticks_msec() / 1000.0
	for sw in _sweeps:
		if now - float(sw["t"]) < 0.3 and (sw["from"] as Vector3).distance_to(p0) < 0.06 and (sw["to"] as Vector3).distance_to(to) < 0.06:
			return 1 if sw["ok"] else 0
	if not force and now - _sweep_t < 0.1:
		return -1
	_sweep_t = now
	var dy := to.y - p0.y
	var kind := "up" if dy > 0 else "down"
	var a := {"from": p0, "to": to, "h": _arc_h(kind, dy), "kind": kind}
	var basis := Basis(Vector3.UP, atan2(to.x - p0.x, to.z - p0.z))
	_test_q.shape = _cs_fly.shape
	_test_q.collision_mask = collision_mask
	_test_q.exclude = [get_rid()]
	_test_q.motion = Vector3.ZERO
	var ok := true
	for i in range(1, 13):
		_test_q.transform = Transform3D(basis, arc_point(a, i / 12.0)) * _xf_fly
		if not house.space.intersect_shape(_test_q, 1).is_empty():
			ok = false
			break
	_sweeps.push_front({"from": p0, "to": to, "ok": ok, "t": now})
	if _sweeps.size() > 8:
		_sweeps.resize(8)
	return 1 if ok else 0


# ---------------------------------------------------------------------- body shapes


## in the air only the short flying capsule collides
func _set_flying(on: bool) -> void:
	if on == _flying:
		return
	_flying = on
	_cs_fly.disabled = not on
	_cs_feet.disabled = on
	_cs_body.disabled = on
	_cs_head.disabled = on


## the trunk and head shapes point along col_yaw while the node itself turns with `yaw` (the model);
## the flying capsule always points where the cat looks (yaw is set toward the target at take-off)
func _apply_col() -> void:
	var rel := Transform3D(Basis(Vector3.UP, col_yaw - yaw), Vector3.ZERO)
	_cs_body.transform = rel * _xf_body
	_cs_head.transform = rel * _xf_head


## do the trunk + head fit at p turned to y? (the paws too when the cat would be moved)
func _fits(p: Vector3, y: float, feet := false) -> bool:
	var space := house.space
	var xf := Transform3D(Basis(Vector3.UP, y), p)
	_test_q.collision_mask = collision_mask
	_test_q.exclude = [get_rid()]
	_test_q.motion = Vector3.ZERO
	for pair in [[_cs_body.shape, _xf_body], [_cs_head.shape, _xf_head]]:
		_test_q.shape = pair[0]
		_test_q.transform = xf * (pair[1] as Transform3D)
		if not space.intersect_shape(_test_q, 1).is_empty():
			return false
	if feet:
		# a little smaller and higher than the paw sphere, so the floor (or a stair ramp) does not count
		_test_q.shape = _feet_test
		_test_q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, FEET_R + 0.05, 0))
		if not space.intersect_shape(_test_q, 1).is_empty():
			return false
	return true


## turn the long body with the cat, but only where it fits: when the nose or the rump would go into a
## wall it shuffles back (or forward) a few centimetres, or turns halfway; otherwise it keeps its old
## heading for now (no jitter, never pushed inside something)
func _turn_body() -> void:
	var diff := wrapf(yaw - col_yaw, -PI, PI)
	if absf(diff) < 0.002 or mode != "free" or arc != null or house == null:
		col_yaw = yaw
		return
	for frac: float in [1.0, 0.5]:
		var cand := col_yaw + diff * frac
		if _fits(global_position, cand):
			col_yaw = cand
			return
		var f := Vector3(sin(cand), 0, cos(cand))
		var sd := Vector3(f.z, 0, -f.x)
		for off: Vector3 in [-f * 0.04, -f * 0.08, f * 0.04, f * 0.08, sd * 0.04, -sd * 0.04]:
			if _fits(global_position + off, cand, true):
				global_position += off
				col_yaw = cand
				return


## outside the fence or under the ground: back to the last place it stood (generalises the old
## "fell below -12" reset)
func _safety_net(dt: float, on_floor: bool) -> void:
	var L := Layout.data()
	var yard: Dictionary = L["YARD"]
	var ty := float(L["TERRAIN_Y"])
	var p := global_position
	var in_house := p.x > -0.1 and p.x < 12.1 and p.z > -0.1 and p.z < 13.1
	var floor_min := ty - 0.5
	if in_house:
		floor_min = -3.6 if p.z < 10.1 else -0.5
	var out := p.x < float(yard["x0"]) - YARD_MARGIN or p.x > float(yard["x1"]) + YARD_MARGIN
	out = out or p.z < float(yard["z0"]) - YARD_MARGIN or p.z > float(yard["z1"]) + YARD_MARGIN
	if out or p.y < floor_min:
		teleport(_safe_pos if _safe_pos != null else Vector3(2.5, 0.05, 3.5), yaw)
		return
	_safe_t -= dt
	if on_floor and _safe_t <= 0.0:
		_safe_t = 0.3
		_safe_pos = p + Vector3(0, 0.02, 0)
