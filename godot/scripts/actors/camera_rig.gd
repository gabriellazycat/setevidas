class_name CameraRig
extends Node
## Third-person orbit camera built for a small, low character: collides with walls / doors /
## furniture marked for the camera, noise-based shake, run FOV kick, cinematic override.

var camera: Camera3D
var house: House
var yaw := PI
var pitch := -0.22
var distance := 1.55
var cur_dist := 1.55
var target := Vector3.ZERO
var smooth_target := Vector3.ZERO
var shake_amt := 0.0
var shake_t := 0.0
var fov_kick := 0.0
var override_pose = null   # {pos, look, blend, [roll] rad, [fov] deg, [hand] handheld sway 0..1}
var noise := FastNoiseLite.new()
var exclude: Array[RID] = []
var _probe := SphereShape3D.new()
var _probe_q := PhysicsShapeQueryParameters3D.new()


func _init(cam: Camera3D) -> void:
	camera = cam
	noise.frequency = 1.0
	_probe.radius = 0.09


func snap(t: Vector3, y = null) -> void:
	if y != null:
		yaw = y
	smooth_target = t
	target = t
	cur_dist = distance


func shake(amount: float) -> void:
	if not Settings.g("camera_shake"):
		amount *= 0.15
	shake_amt = maxf(shake_amt, amount)


func update(dt: float, focus: Vector3, controls: bool, running: bool) -> void:
	if controls:
		var sens := 0.0022 * float(Settings.g("sensitivity"))
		var look := Controls.consume_look()
		var inv := -1.0 if Settings.g("invert_y") else 1.0
		yaw -= look.x * sens
		pitch -= look.y * sens * inv
		var pl := Controls.pad_look()
		var ps := 2.6 * float(Settings.g("pad_sensitivity")) * dt
		yaw -= pl.x * ps
		pitch -= pl.y * ps * 0.75 * inv
	else:
		Controls.consume_look()
	pitch = clampf(pitch, -1.15, 0.65)
	target = focus
	smooth_target = smooth_target.lerp(target, 1.0 - exp(-14.0 * dt))
	var cp := cos(pitch)
	var dir := Vector3(-sin(yaw) * cp, -sin(pitch), -cos(yaw) * cp)
	var want := distance * (1.0 + maxf(0.0, -pitch - 0.3) * 0.25)
	var allowed := want
	if house:
		# a small sphere swept back from the cat: walls, doors and furniture all push the camera in
		_probe_q.shape = _probe
		_probe_q.transform = Transform3D(Basis.IDENTITY, smooth_target)
		_probe_q.motion = dir * (want + 0.15)
		_probe_q.collision_mask = HouseBuilder.LAYER_CAMERA | HouseBuilder.LAYER_WORLD
		_probe_q.exclude = exclude
		var frac := house.space.cast_motion(_probe_q)
		if frac.size() == 2 and frac[0] < 1.0:
			allowed = maxf(0.18, (want + 0.15) * frac[0] - 0.06)
	if allowed < cur_dist:
		cur_dist = lerpf(cur_dist, allowed, 1.0 - exp(-30.0 * dt))
	else:
		cur_dist = lerpf(cur_dist, allowed, 1.0 - exp(-3.5 * dt))
	var pos := smooth_target + dir * cur_dist
	shake_t += dt
	shake_amt = lerpf(shake_amt, 0.0, 1.0 - exp(-3.0 * dt))
	var roll := 0.0
	if shake_amt > 0.001:
		var a := shake_amt
		pos += Vector3(noise.get_noise_1d(shake_t * 18.0), noise.get_noise_1d(shake_t * 21.0 + 70.0), noise.get_noise_1d(shake_t * 19.0 + 30.0)) * 0.06 * a
		roll = noise.get_noise_1d(shake_t * 13.0 + 110.0) * 0.03 * a
	var look_at := smooth_target
	var fov_over = null
	if override_pose != null:
		var o: Dictionary = override_pose
		pos = pos.lerp(o["pos"], o["blend"])
		look_at = look_at.lerp(o["look"], o["blend"])
		roll += float(o.get("roll", 0.0))
		fov_over = o.get("fov")
		var hand := float(o.get("hand", 0.0))
		if hand > 0.0:
			# slow handheld sway (a person holding the camera), not the hit shake
			pos += Vector3(noise.get_noise_1d(shake_t * 1.7), noise.get_noise_1d(shake_t * 2.1 + 40.0), noise.get_noise_1d(shake_t * 1.9 + 80.0)) * 0.035 * hand
			look_at += Vector3(noise.get_noise_1d(shake_t * 1.3 + 150.0), noise.get_noise_1d(shake_t * 1.5 + 190.0), 0) * 0.05 * hand
			roll += noise.get_noise_1d(shake_t * 1.1 + 230.0) * 0.02 * hand
	camera.global_position = pos
	if pos.distance_to(look_at) > 0.001:
		camera.look_at(look_at, Vector3.UP)
	camera.rotate_object_local(Vector3.FORWARD, roll)
	fov_kick = lerpf(fov_kick, 6.0 if running else 0.0, 1.0 - exp(-3.0 * dt))
	camera.fov = float(fov_over) if fov_over != null else float(Settings.g("fov")) + fov_kick


var move_yaw: float:
	get:
		return yaw
