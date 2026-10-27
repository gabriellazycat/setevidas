// CRT / laptop screen / radio dial. Dark glass when off; when the Whisperer powers it, rolling
// static, scanlines and a face-like ghost shape that swims in the noise.
shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx;

uniform float glow = 0.0;
uniform vec3 tint : source_color = vec3(0.6, 0.78, 1.0);
uniform bool dial = false;
// the Whisperer's traffic light (green / yellow / red) over the static and the dial
uniform vec3 light_col : source_color = vec3(1.0);
uniform float light_mix = 0.0;
// "programa": a broadcast from the frame atlas (3x2), with a freeze / glitch and a face flash
uniform float program = 0.0;
uniform sampler2D program_tex : source_color, filter_linear;
uniform float frame = 0.0;
uniform float freeze = 0.0;
uniform float face_flash = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	vec3 col;
	if (dial) {
		// warm radio dial with tick marks and a needle that wobbles while the voice speaks
		float ticks = step(0.92, fract(uv.x * 18.0)) * step(0.55, uv.y) * step(uv.y, 0.75);
		float needle = 1.0 - smoothstep(0.0, 0.012, abs(uv.x - (0.5 + 0.25 * sin(t * 1.7) * glow)));
		col = mix(tint, light_col, light_mix) * (0.25 + 0.75 * max(glow, light_mix * 0.6)) * (0.6 + 0.4 * (1.0 - abs(uv.y - 0.5) * 2.0));
		col = mix(col, vec3(0.05), ticks * 0.8);
		col = mix(col, vec3(0.6, 0.1, 0.05), needle * 0.9);
		ALBEDO = col * 0.3;
		EMISSION = col * (0.15 + glow * 3.0);
		ROUGHNESS = 0.2;
	} else {
		float n = hash(floor(uv * vec2(160.0, 120.0)) + floor(t * 30.0));
		float scan = 0.75 + 0.25 * sin(uv.y * 420.0 + t * 12.0);
		float roll = smoothstep(0.0, 0.08, abs(fract(uv.y - t * 0.17) - 0.5));
		// a pale face shape that appears in the noise when the signal is strong
		vec2 c = (uv - vec2(0.5, 0.48)) * vec2(1.4, 1.0);
		float face = smoothstep(0.32, 0.18, length(c)) * smoothstep(0.75, 1.0, glow);
		float eyes = (1.0 - smoothstep(0.02, 0.05, length(c - vec2(-0.1, -0.05)))) + (1.0 - smoothstep(0.02, 0.05, length(c - vec2(0.1, -0.05))));
		float mouth = 1.0 - smoothstep(0.02, 0.06, length((c - vec2(0.0, 0.14)) * vec2(1.0, 2.2)));
		float img = n * scan * roll;
		img = mix(img, 0.9 - (eyes + mouth) * 0.85, face * 0.55);
		col = mix(tint, light_col, light_mix) * img;
		float vign = smoothstep(0.75, 0.3, length(uv - 0.5));
		vec3 em = col * max(glow, light_mix * 0.5) * 2.4 * vign;
		if (program > 0.001) {
			// the show: one atlas cell, soft scanlines, the picture tearing sideways when it freezes
			vec2 pu = uv;
			float tear = freeze * (hash(vec2(floor(uv.y * 40.0), floor(t * 12.0))) - 0.5) * 0.12;
			pu.x = fract(pu.x + tear);
			float fi = face_flash > 0.5 ? 5.0 : frame;
			vec2 cell = vec2(mod(fi, 3.0), floor(fi / 3.0));
			vec3 pic = texture(program_tex, (cell + vec2(pu.x, pu.y)) / vec2(3.0, 2.0)).rgb;
			pic *= 0.88 + 0.12 * sin(uv.y * 420.0 + t * 8.0);
			pic = mix(pic, vec3(n) * tint, freeze * 0.35);
			em = mix(em, pic * 1.6 * vign, program);
		}
		ALBEDO = vec3(0.02, 0.025, 0.03);
		ROUGHNESS = 0.08;
		METALLIC = 0.2;
		EMISSION = em;
	}
}
