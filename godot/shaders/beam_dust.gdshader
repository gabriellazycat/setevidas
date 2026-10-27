// Dust motes that only show where the sun or moon reaches them: no ambient, lit by the directional
// light through its shadow (so a grain in the shade of the wall vanishes), brighter looking into the
// light (forward scattering). Lamps light it a little. Additive billboards, soft round grains.
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, ambient_light_disabled, specular_disabled;

uniform float gain = 1.0;
uniform float lamp_gain = 0.12;
uniform float fwd = 5.0;
// a faint glow of their own, for the fine dust of the whole house (`FX.haze_mat`); 0 in the beams
uniform float amb = 0.0;
// grain look: `core` is where the soft edge reaches full strength (0 = all falloff, misty), `opacity`
// scales every grain, and grains closer than `near_fade` m to the camera fade out (0 = never)
uniform float core = 0.2;
uniform float opacity = 1.0;
uniform float near_fade = 0.0;

void vertex() {
	mat4 bb = mat4(MAIN_CAM_INV_VIEW_MATRIX[0], MAIN_CAM_INV_VIEW_MATRIX[1], MAIN_CAM_INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	bb = bb * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, length(MODEL_MATRIX[2].xyz), 0), vec4(0, 0, 0, 1));
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = smoothstep(1.0, core, d) * COLOR.a * opacity;
	if (near_fade > 0.0) {
		a *= smoothstep(near_fade * 0.3, near_fade, length(VERTEX));
	}
	ALBEDO = COLOR.rgb * a;
	EMISSION = COLOR.rgb * a * amb;
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		float f = pow(max(0.0, -dot(VIEW, LIGHT)), 4.0);
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * gain * (0.35 + fwd * f) / PI;
	} else {
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * lamp_gain / PI;
	}
}
