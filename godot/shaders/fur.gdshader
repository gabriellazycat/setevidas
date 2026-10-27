// Shell fur: the cat mesh is drawn several times, each pass pushed out along the normal and
// combed back along the body, cut by a soft strand-height texture with anti-aliased edges
// (alpha to coverage) so the coat reads as soft, dense and groomed rather than static noise.
// Layer 0 is the opaque undercoat. Bristle makes the coat stand up; wet clumps it.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
stencil_mode write, compare_always, 2;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, hint_default_white;
uniform sampler2D strands : filter_linear_mipmap, repeat_enable;
uniform sampler2D fur_mask : filter_linear, hint_default_white;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform bool use_normal = false;
uniform bool use_vertex_mask = false;   // fur length in the vertex colour (red) instead of a texture
uniform float shell = 0.0;            // 0 = skin, 1 = outermost shell
uniform float fur_length = 0.011;
uniform float density = 260.0;
uniform float bristle = 0.0;          // 0..1 fear / hiss: longer, stiffer fur
uniform float wet = 0.0;              // clumps & darkens the coat
uniform vec3 comb_dir = vec3(0.0, -0.45, -1.0); // model space: down and toward the tail
uniform float comb = 1.15;            // how flat the coat lies along the body

varying float v_shell;
varying float v_mask;

void vertex() {
	float h = shell;
	float mask = (use_vertex_mask ? COLOR.r : textureLod(fur_mask, UV, 0.0).r) * 1.6;
	v_mask = mask;
	float len = fur_length * mask * (1.0 + bristle * 0.9) * (1.0 - wet * 0.55);
	// comb direction projected on the surface: the outer shells slide back along the body,
	// so the strands lie down instead of sticking straight out
	vec3 c = normalize(comb_dir);
	c = c - NORMAL * dot(c, NORMAL);
	float k = comb * (1.0 - bristle * 0.8);
	VERTEX += NORMAL * len * h * (1.0 - 0.25 * h * (1.0 - bristle)) + c * len * k * h * h + vec3(0.0, -0.25, 0.0) * len * h * h;
	v_shell = h;
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;
	float h = v_shell;
	vec2 suv = UV * density;
	// keep the strands crisp up close but let them soften (not vanish) with distance
	vec2 tc = suv * 512.0;
	float lod = log2(max(max(length(dFdx(tc)), length(dFdy(tc))), 1e-4));
	// strands finer than a pixel (close-ups: ~25 texels per pixel) used to be point-sampled at lod 1.6 and
	// crawled with every breath; follow the real footprint and soften the cut so they blend instead
	float l = clamp(lod, 0.0, 5.0);
	vec4 s = textureLod(strands, suv, l);
	float soft = 0.08 + 0.05 * max(l - 1.5, 0.0);
	float clump = mix(1.0, 0.75 + 0.5 * s.b, wet);
	if (h > 0.001) {
		if (v_mask < 0.12) {
			discard;
		}
		// strands taper: only the taller ones reach the outer shells
		float v = s.r * clump * (1.0 + 0.25 * clamp(lod, 0.0, 1.6));
		float thr = h * 0.86 + 0.06;
		ALPHA = smoothstep(thr - soft, thr + soft, v);
		ALPHA_SCISSOR_THRESHOLD = 0.5;
		ALPHA_ANTIALIASING_EDGE = 0.35;
		ALPHA_TEXTURE_COORDINATE = tc;
	}
	// soft self shadowing toward the roots, gentle per-strand variation, lighter tips
	// (short velvet on the face and paws barely self-shadows)
	float ao = mix(1.0, mix(0.62, 1.0, smoothstep(0.0, 0.9, h)), clamp(v_mask, 0.0, 1.0));
	vec3 col = base * ao * (0.94 + 0.1 * s.g);
	col = mix(col, col * 1.08 + vec3(0.012), h * h * 0.5);
	col *= 1.0 - wet * 0.35;
	ALBEDO = col;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = mix(1.0, 0.4, h);
	}
	ROUGHNESS = mix(0.95, 0.82, h) - wet * 0.45;
	SPECULAR = 0.18 + wet * 0.4;
	// light passing through the fluffy edge, warm and subtle
	BACKLIGHT = base * 0.18 * h;
}
