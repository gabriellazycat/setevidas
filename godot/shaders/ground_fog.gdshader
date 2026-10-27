// Drifting ground fog for a FogVolume: two layers of 3D noise moving with the wind, thick at the
// bottom and thinning upward, fading at the volume's edges.
shader_type fog;

uniform float density = 0.6;
uniform vec3 albedo : source_color = vec3(0.55, 0.6, 0.72);
uniform float height_falloff = 1.0;
uniform sampler3D noise3d;
uniform float speed = 0.06;

void fog() {
	vec3 p = WORLD_POSITION;
	float t = TIME * speed;
	float n = texture(noise3d, p * 0.08 + vec3(t, 0.0, t * 0.6)).r;
	float n2 = texture(noise3d, p * 0.21 - vec3(t * 1.3, t * 0.2, 0.0)).r;
	float h = clamp(1.0 - UVW.y, 0.0, 1.0);
	float edge = smoothstep(0.0, 0.12, UVW.x) * smoothstep(1.0, 0.88, UVW.x) * smoothstep(0.0, 0.12, UVW.z) * smoothstep(1.0, 0.88, UVW.z);
	DENSITY = density * pow(h, height_falloff) * smoothstep(0.35, 0.75, n * 0.7 + n2 * 0.5) * edge;
	ALBEDO = albedo;
}
