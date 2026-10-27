// A tentacle of the Thing in the basement: a tapered tube bent in the vertex shader, writhing,
// rearing up during the "tell" before each shockwave. Wet black skin, red veins, red rim.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;

uniform float length = 2.0;
uniform float phase = 0.0;
uniform float rear = 0.0;     // 0..1 the tell
uniform float grow = 1.0;     // emerging from the floor
uniform float alpha = 1.0;
uniform vec3 out_dir = vec3(1.0, 0.0, 0.0);  // horizontal direction away from the circle centre
uniform bool skinned = false; // the limbs of thing.glb: the bones bend them, only the skin is drawn here
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

varying float vh;

void vertex() {
	if (skinned) {
		vh = UV.y;
	} else {
	float h = clamp((VERTEX.y + length * 0.5) / length, 0.0, 1.0);
	vh = h;
	float t = TIME;
	float taper = mix(1.0, 0.04, pow(h, 0.6)) * (1.0 + 0.06 * sin(h * 40.0 + phase));
	VERTEX.xz *= taper;
	float y = h * length * grow;
	// bend outward and sway; during the tell the tentacle stands up and curls over the circle
	float out_bend = (0.5 - rear * 0.75) * h * h * length;
	float sway = sin(t * 1.6 + phase + h * 4.0) * 0.35 * h * (0.6 + rear * 0.6);
	float side = cos(t * 1.3 + phase * 1.7 + h * 3.0) * 0.25 * h;
	vec3 o = normalize(out_dir);
	vec3 s = vec3(-o.z, 0.0, o.x);
	// the base stays on the floor while the tentacle grows out of it
	vec3 p = vec3(VERTEX.x, y - length * 0.5, VERTEX.z);
	p += (o * (out_bend + sway) + s * side) * grow;
	VERTEX = p;
	}
}

void fragment() {
	float n = texture(noise_tex, UV * vec2(2.0, 6.0) + vec2(0.0, TIME * 0.05)).g;
	float veins = smoothstep(0.7, 0.76, texture(noise_tex, UV * vec2(3.0, 10.0)).r) * (1.0 - smoothstep(0.76, 0.85, texture(noise_tex, UV * vec2(3.0, 10.0)).r));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = mix(vec3(0.015, 0.006, 0.006), vec3(0.08, 0.02, 0.02), n);
	ROUGHNESS = 0.12;
	SPECULAR = 0.8;
	ALPHA = alpha;
	EMISSION = vec3(0.5, 0.03, 0.015) * (veins * (0.25 + rear * 2.0) + fres * 0.25) * alpha;
}
