// Water for the house: kind 0 = still water in a basin / tub, 1 = falling stream, 2 = a puddle
// spreading on the floor (soft edge, dark wet look, mirror-like reflections).
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;

uniform int kind = 0;
uniform vec3 water_color : source_color = vec3(0.32, 0.42, 0.45);
uniform float murk = 0.0;  // the Drowner darkens the water
uniform float foam = 0.0;  // bath foam on still water: soft white clumps of bubbles

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float t = TIME;
	vec3 col = mix(water_color, vec3(0.06, 0.09, 0.08), murk);
	if (kind == 1) {
		float flow = vnoise(vec2(UV.x * 6.0, UV.y * 30.0 + t * 18.0));
		ALBEDO = vec3(0.75, 0.85, 0.9);
		ALPHA = 0.35 + 0.35 * flow;
		ROUGHNESS = 0.05;
		SPECULAR = 0.9;
		EMISSION = vec3(0.02, 0.025, 0.03) * flow;
	} else {
		vec2 p = UV * 8.0;
		float n1 = vnoise(p + vec2(t * 0.4, t * 0.31));
		float n2 = vnoise(p * 2.3 - vec2(t * 0.52, t * 0.2));
		vec3 nrm = normalize(vec3((n1 - 0.5) * 0.25, 1.0, (n2 - 0.5) * 0.25));
		NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
		ALBEDO = col * 0.4;
		ROUGHNESS = 0.03;
		SPECULAR = 0.8;
		METALLIC = 0.0;
		ALPHA = 0.55 + murk * 0.35;
		if (kind == 0 && foam > 0.001) {
			// clumps drifting slowly over most of the surface, bubbles inside, a creamy shade between them
			float c = vnoise(UV * 4.0 + vec2(t * 0.05, -t * 0.04)) * 0.65 + vnoise(UV * 11.0 - t * 0.03) * 0.35;
			float clump = smoothstep(0.3, 0.5, c) * foam * (1.0 - murk * 0.6);
			float bub = vnoise(UV * 70.0 + c * 4.0);
			float h = c + bub * 0.15;
			vec3 fnrm = normalize(vec3(dFdx(h) * -40.0, 1.0, dFdy(h) * -40.0));
			vec3 fc = mix(vec3(0.82, 0.78, 0.72), vec3(0.98, 0.96, 0.92), smoothstep(0.35, 0.75, c)) * (0.88 + 0.12 * bub);
			ALBEDO = mix(ALBEDO, fc, clump);
			ALPHA = mix(ALPHA, 1.0, clump);
			ROUGHNESS = mix(ROUGHNESS, 0.75, clump);
			SPECULAR = mix(SPECULAR, 0.2, clump);
			NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(fnrm, 0.0)).xyz, clump));
		}
		if (kind == 2) {
			float r = length(UV - vec2(0.5)) * 2.0;
			float edge = 0.78 + 0.12 * vnoise(UV * 9.0) + 0.06 * sin(atan(UV.y - 0.5, UV.x - 0.5) * 5.0);
			float m = 1.0 - smoothstep(edge - 0.12, edge, r);
			if (m < 0.01) {
				discard;
			}
			ALBEDO = vec3(0.01, 0.012, 0.012);
			ALPHA = m * 0.75;
		}
	}
}
