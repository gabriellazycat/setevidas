// Anime outline: an inverted hull drawn as next_pass of the toon material, pushed out along the
// normal and coloured with the piece's own (darkened) colour.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;
stencil_mode write, compare_always, 2;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 albedo : source_color = vec4(1.0);
uniform vec3 tint : source_color = vec3(1.0);
uniform float width = 0.0016;          // metres at arm's length
uniform float darken = 0.38;
uniform float alpha_cut = 0.5;
uniform float hide_v = 9.0;            // as in toon.gdshaderinc

void vertex() {
	// grow a little with distance so the line keeps reading, but never past 2.5x
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = clamp(length(CAMERA_POSITION_WORLD - wp) / 1.2, 0.6, 2.5);
	VERTEX += NORMAL * width * d;
}

void fragment() {
	vec4 t = texture(albedo_tex, UV) * albedo;
	if (t.a < alpha_cut || UV.y > hide_v) {
		discard;
	}
	ALBEDO = t.rgb * tint * darken;
}
