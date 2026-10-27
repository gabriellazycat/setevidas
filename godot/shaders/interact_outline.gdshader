// What the cat can use: a soft cream outline around it (switch, outlet, faucet, door, things on the
// floor), drawn as a material_overlay shell pushed out a constant number of pixels, unshaded so it
// still reads in the dark. interact_marks.gd sets the strength (faint nearby, stronger on the one the
// button is for).
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.965, 0.91);
uniform float alpha = 0.3;
uniform float width_px = 1.6;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 vn = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);
	vec2 dir = (PROJECTION_MATRIX * vec4(vn, 0.0)).xy;
	float l = length(dir);
	if (l > 1e-5) {
		clip.xy += dir / l / VIEWPORT_SIZE * width_px * 2.0 * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	ALBEDO = color;
	ALPHA = alpha;
}
