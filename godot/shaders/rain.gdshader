// Rain streak: a thin quad that faces the camera around its vertical axis, stretched along the fall;
// never drawn inside the house footprint (the roof keeps it dry).
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float amount = 1.0;
uniform float wind = 0.0;
uniform vec4 color : source_color = vec4(0.62, 0.72, 0.9, 0.22);

varying vec3 wpos;

void vertex() {
	// billboard around Y, keep the particle position from the instance transform
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 to_cam = CAMERA_POSITION_WORLD - center;
	to_cam.y = 0.0;
	vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam + vec3(1e-4, 0.0, 0.0)));
	vec3 p = center + side * VERTEX.x + vec3(wind * 0.12 * VERTEX.y, VERTEX.y, 0.0);
	wpos = p;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(p, 1.0);
}

void fragment() {
	// main house, the one-storey back wing (dining room, pantry) and the porch roof
	if (wpos.x > -0.3 && wpos.x < 12.3 && wpos.z > -0.3 && wpos.z < 13.4 && wpos.y < 9.6) {
		discard;
	}
	if (wpos.x > 4.9 && wpos.x < 8.1 && wpos.z > -2.1 && wpos.z <= -0.3 && wpos.y < 2.9) {
		discard;
	}
	if (wpos.y < -0.95) {
		discard;
	}
	float edge = 1.0 - abs(UV.x - 0.5) * 2.0;
	float tip = smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.6, UV.y);
	ALBEDO = color.rgb;
	ALPHA = color.a * amount * edge * tip;
}
