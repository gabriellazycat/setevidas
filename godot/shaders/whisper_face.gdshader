shader_type spatial;
// The Whisperer's face: a pale, glowing mask that always faces the camera, with deep black eye
// holes (a pinpoint of light inside each) and a mouth that stretches open; it flickers like a bad
// signal. Drawn procedurally on a quad (no texture).
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform float scream : hint_range(0.0, 1.0) = 0.0;   // 0 closed-ish, 1 jaw hanging open
uniform float glitch : hint_range(0.0, 1.0) = 0.3;
uniform vec3 tint : source_color = vec3(0.86, 0.94, 1.0);

float hash(float n) { return fract(sin(n) * 43758.5453); }

float ellipse(vec2 p, vec2 c, vec2 r, float rot) {
	vec2 q = p - c;
	float cs = cos(rot), sn = sin(rot);
	q = vec2(cs * q.x - sn * q.y, sn * q.x + cs * q.y);
	return length(q / r);
}

void vertex() {
	// billboard, keeping the node's scale
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
}

void fragment() {
	float tm = TIME;
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y;
	// bad-signal tearing: rows slide sideways now and then
	float row = floor((p.y + 1.0) * 18.0);
	float tear = step(1.0 - glitch * 0.35, hash(row + floor(tm * 14.0))) * (hash(row * 3.1 + floor(tm * 14.0)) - 0.5) * 0.18;
	p.x += tear;
	// the head: a long oval that breathes a little
	float head = ellipse(p, vec2(0.0, 0.02), vec2(0.62, 0.86 + scream * 0.06), 0.0);
	float inside = 1.0 - smoothstep(0.92, 1.0, head);
	float halo = (1.0 - smoothstep(0.85, 1.6, head)) * 0.55;
	vec3 col = tint * (1.05 - 0.25 * smoothstep(0.2, 1.0, head));
	// sunken sockets, then the black eye holes, slanted, with a cold pinpoint looking out
	for (int i = 0; i < 2; i++) {
		float sx = i == 0 ? -1.0 : 1.0;
		vec2 ec = vec2(0.26 * sx, 0.2);
		float sock = ellipse(p, ec, vec2(0.24, 0.27), 0.35 * sx);
		col *= mix(0.45, 1.0, smoothstep(0.55, 1.25, sock));
		float eye = ellipse(p, ec + vec2(0.0, -0.02), vec2(0.13, 0.19 + scream * 0.03), 0.3 * sx);
		col = mix(vec3(0.0), col, smoothstep(0.85, 1.0, eye));
		float pin = length(p - ec - vec2(0.015 * sx, -0.03));
		col += vec3(0.9, 0.97, 1.0) * (1.0 - smoothstep(0.0, 0.03, pin)) * (0.7 + 0.3 * sin(tm * 9.0 + sx));
	}
	// the mouth: a black hole that drops open and stretches
	float jaw = 0.12 + scream * 0.38 + sin(tm * 3.3) * 0.02;
	vec2 mc = vec2(0.0, -0.36 - scream * 0.16);
	float mouth = ellipse(p, mc, vec2(0.13 + scream * 0.03, jaw), 0.0);
	col *= mix(0.5, 1.0, smoothstep(0.9, 1.5, mouth));
	col = mix(vec3(0.0), col, smoothstep(0.88, 1.0, mouth));
	// flicker and scanlines
	float flick = 0.85 + 0.15 * step(0.5, hash(floor(tm * 20.0)));
	float scan = 0.92 + 0.08 * sin((p.y + tm * 0.6) * 90.0);
	ALBEDO = col * flick * scan;
	ALPHA = clamp(inside + halo * (1.0 - inside), 0.0, 1.0) * alpha * flick;
}
