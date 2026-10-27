// Every architectural and built-in surface of the house: PBR maps tiled in metres plus world-space
// ageing (dirt creeping up from the floor, damp stains under the ceiling, blotchy grime).
// Clean painted look: `flatten` pulls each texel towards the texture's average (or a `base` colour)
// so only a ghost of the grain is left, an optional procedural low-contrast pattern replaces the
// wallpapers, and light() is a wide, soft wrapped lambert with tinted shadow fill and a faint specular.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform bool use_normal = true;
uniform bool use_arm = true;
// imported (glTF) maps: which channel holds roughness, and whether R / B really are AO / metal
uniform int arm_rough_ch = 1;
uniform bool arm_ao = true;
uniform bool arm_metal = true;
uniform vec3 tint : source_color = vec3(1.0);
uniform float tile = 1.0;
uniform float uv_rot = 0.0;
uniform bool unit_uv = false;
uniform float rough_mul = 1.0;
uniform float rough_base = 0.7;
uniform float metal = 0.0;
uniform float normal_strength = 1.0;
uniform float grime = 0.4;
uniform vec3 emission_color : source_color = vec3(1.0, 0.7, 0.4);
uniform float emission_energy = 0.0;
// wet look (puddles / dripping walls) driven per material
uniform float wet = 0.0;
// stylisation
uniform float detail = 1.2;                 // mip bias: higher = fewer fine texture details
uniform float sat = 1.0;
uniform float warm = 0.2;
uniform float grime_scale = 0.6;            // global reduction of the ageing
uniform float flatten = 0.0;                // 0 = texture as is, 1 = flat average / base colour
uniform bool use_base = false;
uniform vec3 base : source_color = vec3(0.8);
// procedural pattern in metres: 0 none, 1 diamonds, 2 wide stripes, 3 dots
uniform int pattern = 0;
uniform vec3 pattern_color : source_color = vec3(1.0);
uniform float pattern_scale = 0.35;
uniform float pattern_amt = 0.0;
uniform float wrap = 0.45;                 // wrapped lambert: light reaches past the terminator
uniform float soft = 0.35;                 // widens the terminator into a soft gradient
uniform vec3 shadow_tint : source_color = vec3(0.42, 0.33, 0.36);
uniform float shadow_fill = 0.03;
uniform float spec_mul = 0.2;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float tri_noise(vec3 p, vec3 w, float s, int ch) {
	vec4 a = texture(noise_tex, p.zy * s);
	vec4 b = texture(noise_tex, p.xz * s);
	vec4 c = texture(noise_tex, p.xy * s);
	return a[ch] * w.x + b[ch] * w.y + c[ch] * w.z;
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// 1 on the pattern's motif, 0 on the ground; antialiased with the screen-space derivative
float motif(vec2 m) {
	vec2 p = m / pattern_scale;
	float fw = max(fwidth(p.x) + fwidth(p.y), 1e-4);
	if (pattern == 1) {
		vec2 q = vec2(p.x + p.y, p.x - p.y) * 0.7071;
		vec2 g = abs(fract(q) - 0.5);
		return 1.0 - smoothstep(0.035 - fw, 0.035 + fw, 0.5 - max(g.x, g.y));
	} else if (pattern == 2) {
		float s = abs(fract(p.x) - 0.5);
		return 1.0 - smoothstep(0.25 - fw, 0.25 + fw, s);
	} else if (pattern == 3) {
		vec2 c = fract(p + vec2(0.5 * step(0.5, fract(p.y * 0.5)), 0.0)) - 0.5;
		return 1.0 - smoothstep(0.12 - fw, 0.12 + fw, length(c));
	}
	return 0.0;
}

void fragment() {
	vec2 uv = unit_uv ? UV : UV / tile;
	float cr = cos(uv_rot);
	float sr = sin(uv_rot);
	uv = mat2(vec2(cr, sr), vec2(-sr, cr)) * uv;
	vec3 tx = texture(albedo_tex, uv, detail).rgb;
	vec3 col = tx;
	if (flatten > 0.0 || use_base) {
		vec3 avg = textureLod(albedo_tex, uv, 10.0).rgb;
		float ratio = luma(tx) / max(luma(avg), 0.02);
		vec3 ground = use_base ? base : avg;
		col = mix(use_base ? base * ratio : tx, ground, flatten);
	}
	col *= tint;
	if (pattern > 0) {
		col = mix(col, pattern_color, motif(UV) * pattern_amt);
	}
	vec3 arm = use_arm ? texture(arm_tex, uv, detail).rgb : vec3(1.0, rough_base, 0.0);

	// ---- ageing
	vec3 bw = pow(abs(wnrm), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	float n_low = tri_noise(wpos, bw, 0.19, 0);
	float n_mid = tri_noise(wpos, bw, 0.73, 1);
	float n_fine = tri_noise(wpos, bw, 3.1, 1);
	float storey = mod(wpos.y + 3.0, 3.0);           // 0 at each floor, ~2.8 under each ceiling
	float vertical = 1.0 - abs(wnrm.y);
	float floor_dirt = smoothstep(0.45, 0.0, storey) * vertical * (0.6 + 0.6 * n_mid);
	float damp = smoothstep(2.0, 2.8, storey) * vertical * smoothstep(0.45, 0.75, n_low);
	float blotch = smoothstep(0.5, 0.85, n_low * 0.65 + n_mid * 0.5);
	float gr = grime * grime_scale;
	float g = clamp((blotch * 0.55 + floor_dirt * 0.75 + damp * 0.9) * gr, 0.0, 1.0);
	col *= mix(1.0, 0.5 + 0.3 * n_fine, g);
	col = mix(col, col * vec3(1.02, 0.9, 0.72), damp * gr * 0.6);
	// floors: worn walkways are a little lighter and smoother, corners darker
	float up = max(wnrm.y, 0.0);
	col *= mix(1.0, 0.85 + 0.25 * n_mid, up * gr * 0.5);
	// cohesive palette: a touch more saturation, pulled warm
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = max(mix(vec3(lum), col, sat), vec3(0.0));
	col *= mix(vec3(1.0), vec3(1.07, 1.0, 0.9), warm);

	ALBEDO = col;
	float rough = clamp(arm[arm_rough_ch] * rough_mul + g * 0.12, 0.03, 1.0);
	// painted look: satin at most, so floors keep their colour instead of mirroring the sky and walls
	rough = mix(rough, max(rough, 0.55), flatten);
	rough = mix(rough, 0.08, wet);
	ROUGHNESS = rough;
	METALLIC = clamp(max(arm_metal ? arm.b : 0.0, metal), 0.0, 1.0);
	SPECULAR = mix(0.5, 0.2, flatten);
	AO = arm_ao ? arm.r : 1.0;
	AO_LIGHT_AFFECT = 0.25;
	if (use_normal) {
		vec3 nm = texture(normal_tex, uv, detail).rgb;
		vec2 nxy = nm.xy * 2.0 - 1.0;
		nxy = mat2(vec2(cr, -sr), vec2(sr, cr)) * nxy;
		NORMAL_MAP = vec3(nxy * 0.5 + 0.5, nm.z);
		NORMAL_MAP_DEPTH = normal_strength;
	}
	EMISSION = emission_color * emission_energy;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float d = smoothstep(-soft, 1.0, clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0));
	float lit = d * ATTENUATION;
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * (lit + shadow_tint * (1.0 - lit) * shadow_fill);
	vec3 h = normalize(VIEW + LIGHT);
	float ndh = max(dot(NORMAL, h), 0.0);
	float a = max(ROUGHNESS, 0.06);
	a *= a;
	float a2 = a * a;
	float k = ndh * ndh * (a2 - 1.0) + 1.0;
	float dist = a2 / (PI * k * k);
	vec3 f0 = mix(vec3(0.04), ALBEDO, METALLIC);
	SPECULAR_LIGHT += f0 * min(dist * 0.25, 8.0) * spec_mul * max(ndl, 0.0) * ATTENUATION * LIGHT_COLOR / PI;
}
