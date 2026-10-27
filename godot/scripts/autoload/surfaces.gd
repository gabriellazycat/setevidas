extends Node
## Builds the house surface materials from data/materials.json (the same file the Blender build
## previews with) and swaps them onto imported meshes by material name.

const TEX := "res://assets/textures/"
const SURFACE_SHADER := preload("res://shaders/surface.gdshader")
## default pull of every textured surface towards its flat colour (clean, painted look)
const FLATTEN := 0.85

var specs: Dictionary = {}
var _cache: Dictionary = {}
var _textures: Dictionary = {}
var _stylized: Dictionary = {}
var _origin: Dictionary = {}
var noise: Texture2D


func _ready() -> void:
	var f := FileAccess.open("res://data/materials.json", FileAccess.READ)
	specs = JSON.parse_string(f.get_as_text())
	noise = load(TEX + "gen/noise.png")


func tex(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_textures[path] = t
	return t


func _ph(id: String, map: String) -> Texture2D:
	return tex("%s%s/%s_%s.jpg" % [TEX, id, id, map])


func has(key: String) -> bool:
	return specs.has(key)


func get_material(key: String) -> Material:
	if _cache.has(key):
		return _cache[key]
	var m: Material
	if not specs.has(key):
		push_warning("unknown surface material: %s" % key)
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(1, 0, 1)
		m = sm
	else:
		m = _build(key, specs[key])
	_cache[key] = m
	return m


func _color(v, fallback := Color(1, 1, 1)) -> Color:
	if v == null:
		return fallback
	return Color(v[0], v[1], v[2])


func _build(key: String, s: Dictionary) -> Material:
	if s.has("alpha"):
		return _build_transparent(key, s)
	var m := ShaderMaterial.new()
	m.shader = SURFACE_SHADER
	var albedo: Texture2D = null
	var normal: Texture2D = null
	var arm: Texture2D = null
	if s.has("albedo"):
		albedo = tex(TEX + s["albedo"])
	elif s.has("tex"):
		albedo = _ph(s["tex"], "diff")
	var nid: String = s.get("normal_from", s.get("tex", ""))
	var aid: String = s.get("arm_from", s.get("tex", ""))
	if nid != "":
		normal = _ph(nid, "nor")
	if aid != "":
		arm = _ph(aid, "arm")
	var tint := _color(s.get("tint"), Color(1, 1, 1))
	if not s.has("tex") and not s.has("albedo"):
		tint = _color(s.get("color"), Color(0.8, 0.8, 0.8))
	if albedo:
		m.set_shader_parameter("albedo_tex", albedo)
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	m.set_shader_parameter("use_normal", normal != null)
	if normal:
		m.set_shader_parameter("normal_tex", normal)
	m.set_shader_parameter("use_arm", arm != null)
	if arm:
		m.set_shader_parameter("arm_tex", arm)
	m.set_shader_parameter("noise_tex", noise)
	m.set_shader_parameter("tile", float(s.get("tile", 1.0)))
	m.set_shader_parameter("uv_rot", deg_to_rad(float(s.get("rot", 0.0))))
	m.set_shader_parameter("unit_uv", s.get("uv", "") == "unit")
	m.set_shader_parameter("rough_mul", float(s.get("rough", 1.0)) if arm else 1.0)
	m.set_shader_parameter("rough_base", float(s.get("rough", 0.7)))
	m.set_shader_parameter("metal", float(s.get("metal", 0.0)))
	m.set_shader_parameter("grime", float(s.get("grime", 0.0)))
	m.set_shader_parameter("normal_strength", float(s.get("normal", 1.0)))
	m.set_shader_parameter("flatten", float(s.get("flatten", FLATTEN)))
	if s.has("base"):
		var b := _color(s["base"])
		m.set_shader_parameter("use_base", true)
		m.set_shader_parameter("base", Vector3(b.r, b.g, b.b))
	if s.has("pattern"):
		var p: Dictionary = s["pattern"]
		var pc := _color(p.get("color"), Color(1, 1, 1))
		m.set_shader_parameter("pattern", ["", "diamond", "stripe", "dot"].find(str(p.get("kind", ""))))
		m.set_shader_parameter("pattern_color", Vector3(pc.r, pc.g, pc.b))
		m.set_shader_parameter("pattern_scale", float(p.get("scale", 0.35)))
		m.set_shader_parameter("pattern_amt", float(p.get("amt", 0.06)))
	if s.has("emit"):
		var e: Array = s["emit"]
		m.set_shader_parameter("emission_color", Vector3(e[0], e[1], e[2]))
		m.set_shader_parameter("emission_energy", float(e[3]) if e.size() > 3 else 0.0)
	m.resource_name = key
	return m


func _build_transparent(key: String, s: Dictionary) -> Material:
	var m := StandardMaterial3D.new()
	var c := _color(s.get("color"), Color(0.9, 0.9, 0.9))
	m.albedo_color = Color(c.r, c.g, c.b, float(s["alpha"]))
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS if key == "water" else BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = float(s.get("rough", 0.05))
	m.metallic = float(s.get("metal", 0.0))
	m.metallic_specular = 0.35 if key.begins_with("glass") else 0.8
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.resource_name = key
	return m


## Replace every surface material of the imported scene by our own, matched by material name.
func apply_to(root: Node) -> int:
	var count := 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			if src == null:
				continue
			var key := _strip(src.resource_name)
			if specs.has(key):
				(mi as MeshInstance3D).set_surface_override_material(i, get_material(key))
				count += 1
	return count


## Convert an imported StandardMaterial3D (Poly Haven furniture, untextured Blender parts) into the
## stylised surface shader, reusing its albedo, normal and roughness maps. Transparent, alpha-cut,
## emissive and vertex-coloured materials are returned unchanged.
func stylize_standard(mat: Material) -> Material:
	var sm := mat as StandardMaterial3D
	if sm == null:
		return mat
	if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or sm.emission_enabled or sm.vertex_color_use_as_albedo:
		return mat
	var id := sm.get_instance_id()
	if _stylized.has(id):
		return _stylized[id]
	var m := ShaderMaterial.new()
	m.shader = SURFACE_SHADER
	m.resource_name = sm.resource_name
	var c := sm.albedo_color
	m.set_shader_parameter("tint", Vector3(c.r, c.g, c.b))
	if sm.albedo_texture:
		m.set_shader_parameter("albedo_tex", sm.albedo_texture)
	m.set_shader_parameter("unit_uv", true)
	m.set_shader_parameter("use_normal", sm.normal_enabled and sm.normal_texture != null)
	if sm.normal_enabled and sm.normal_texture:
		m.set_shader_parameter("normal_tex", sm.normal_texture)
		m.set_shader_parameter("normal_strength", sm.normal_scale)
	var rt := sm.roughness_texture
	m.set_shader_parameter("use_arm", rt != null)
	if rt:
		m.set_shader_parameter("arm_tex", rt)
		var ch := sm.roughness_texture_channel
		m.set_shader_parameter("arm_rough_ch", 0 if ch == BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE else int(ch))
		m.set_shader_parameter("arm_ao", sm.ao_enabled and sm.ao_texture == rt)
		m.set_shader_parameter("arm_metal", sm.metallic_texture == rt)
	m.set_shader_parameter("rough_mul", sm.roughness)
	m.set_shader_parameter("rough_base", sm.roughness)
	m.set_shader_parameter("metal", sm.metallic if sm.metallic_texture == null else 0.0)
	m.set_shader_parameter("noise_tex", noise)
	m.set_shader_parameter("grime", 0.0)
	m.set_shader_parameter("flatten", FLATTEN)
	m.set_shader_parameter("normal_strength", 0.25 * (sm.normal_scale if sm.normal_enabled else 1.0))
	_stylized[id] = m
	_origin[m] = sm
	return m


## the imported material a stylised one was made from (or the material itself)
func original_of(mat: Material) -> Material:
	return _origin.get(mat, mat)


func _strip(n: String) -> String:
	# blender may suffix duplicated material names with .001
	var dot := n.find(".")
	return n.substr(0, dot) if dot > 0 else n
