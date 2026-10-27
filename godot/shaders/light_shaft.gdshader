// A drawn light shaft: the prism from a window to where its light lands. Lit only by the sun / moon
// through its shadow (a tree outside or the sun behind the house hides it), brightest at the
// window and fading along the beam, soft at its edges and where it meets the floor and furniture,
// with slow drifting streaks. UV.x runs across a face, UV.y from the window (0) to the floor (1).
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, ambient_light_disabled, specular_disabled;

uniform float gain = 0.3;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 up = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	up.xyz /= up.w;
	float soft = clamp((VERTEX.z - up.z) / 0.35, 0.0, 1.0);
	float edge = smoothstep(0.0, 0.2, UV.x) * smoothstep(1.0, 0.8, UV.x);
	float len = (1.0 - UV.y) * smoothstep(0.0, 0.06, UV.y);
	// sides seen edge-on hold more light; near the camera (or inside the beam) it fades out
	float facing = mix(0.45, 1.0, 1.0 - abs(dot(NORMAL, VIEW)));
	float near_cam = smoothstep(0.4, 1.8, -VERTEX.z);
	float streaks = 0.7 + 0.3 * sin(UV.x * 21.0 + TIME * 0.25) * sin(UV.x * 6.0 - TIME * 0.13);
	ALBEDO = vec3(soft * edge * len * facing * near_cam * streaks);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * gain / PI;
	}
}
