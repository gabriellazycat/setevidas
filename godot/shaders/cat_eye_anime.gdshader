// Mingau's anime eye: flat painted iris with a dark top and a bright lower
// band, a dark rim, crisp white catchlights, an optional upper lid (almond shape) with a lash line,
// toon-lit like Clara and Davi. Same blink / pupil / shine inputs as cat_eye.gdshader.
shader_type spatial;
render_mode blend_mix, cull_back;
stencil_mode write, compare_always, 2;

uniform vec3 iris_top : source_color = vec3(0.3, 0.5, 0.14);
uniform vec3 iris_bottom : source_color = vec3(0.75, 0.86, 0.32);
uniform vec3 rim_col : source_color = vec3(0.08, 0.06, 0.05);
uniform float rim = 0.12;             // width of the dark iris rim
uniform float pupil_min = 0.08;       // slit width at pupil 0
uniform float pupil_max = 0.55;       // width at pupil 1
uniform float pupil_h = 0.86;
uniform float pupil_round = 0.0;      // 1 = round pupil
uniform float hl = 0.24;              // main catchlight radius
uniform float hl2 = 0.1;
uniform float lid_rest = 0.0;         // upper lid covering the eye at rest (0..0.5)
uniform float lid_tilt = 0.0;         // outer corner down (sleepy) or up (sharp)
uniform float lash = 0.07;            // dark line under the lid
uniform float side = 1.0;             // +1 left eye, -1 right eye (mirrors highlights and tilt)
uniform vec3 lid_color : source_color = vec3(0.82, 0.47, 0.19);
uniform float pupil = 0.3;
uniform float blink = 0.0;
uniform float shine = 0.0;
uniform bool decal = false;            // flat round decal on the face (build_cat2.py --face decal): cut outside the circle

varying float v_lid;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;     // glTF flips V: the top of the eye is at negative p.y
	float r = length(p);
	float up = -p.y;
	vec3 iris = mix(iris_bottom, iris_top, smoothstep(-0.55, 0.65, up));
	// soft light band in the lower iris
	iris = mix(iris, iris_bottom * 1.25 + 0.05, smoothstep(0.75, 0.2, length(p - vec2(0.0, 0.42))) * 0.45);
	vec3 col = mix(iris, rim_col, smoothstep(1.0 - rim - 0.02, 1.0 - rim + 0.02, r));
	// pupil: slit to round
	float pw = mix(pupil_min, pupil_max, pupil);
	float ph = mix(pupil_h, pw * 1.05, pupil_round);
	float pd = length(vec2(p.x / pw, p.y / ph));
	float pup = 1.0 - smoothstep(0.94, 1.02, pd);
	col = mix(col, vec3(0.02, 0.015, 0.02), pup);
	// catchlights (mirrored per eye so both point to the same light)
	vec2 q = vec2(p.x * side, p.y);
	float cl = 1.0 - smoothstep(hl - 0.025, hl, length((q - vec2(-0.3, -0.38)) * vec2(1.0, 0.85)));
	cl = max(cl, 1.0 - smoothstep(hl2 - 0.02, hl2, length(q - vec2(0.3, 0.34))));
	col = mix(col, vec3(1.0), cl);
	// lid: rest position plus blink, tilted toward the outer corner, with a lash line
	float edge = 1.0 - 2.0 * clamp(lid_rest + blink * (1.0 - lid_rest), 0.0, 1.0) + lid_tilt * p.x * side;
	float lid = smoothstep(edge - 0.02, edge + 0.02, up);
	float line = smoothstep(edge - lash - 0.02, edge - lash + 0.02, up) * (1.0 - lid);
	col = mix(col, rim_col, line * step(0.001, lid_rest + blink));
	col = mix(col, lid_color, lid);
	ALBEDO = col;
	ALPHA = decal ? 1.0 - smoothstep(0.985, 1.0, r) : 1.0;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	v_lid = lid;
	float open = 1.0 - lid;
	EMISSION = vec3(0.55) * cl * open + (iris_bottom * 1.2 + 0.1) * pup * shine * open * 0.35;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float band = mix(0.7, 1.0, smoothstep(-0.1, 0.05, ndl));
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * ATTENUATION * band;
}
