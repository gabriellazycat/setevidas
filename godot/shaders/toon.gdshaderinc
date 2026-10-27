// Shared body of the anime toon shaders (Clara and Davi, VRoid models): a 2-band ramp with a soft
// edge and a configurable shade colour, a light-facing rim, the hair "angel ring" highlight, and a
// warm glow when the cat looks with Cat Vision.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, hint_default_white;
uniform vec4 albedo : source_color = vec4(1.0);
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 shade_color : source_color = vec3(0.78, 0.62, 0.66);
uniform float shade_amount = 0.55;     // how much light the shaded band keeps
uniform float shade_shift = 0.0;       // moves the terminator (-1..1 on N.L)
uniform float shade_soft = 0.06;       // width of the band edge
uniform vec3 rim_color : source_color = vec3(1.0, 0.86, 0.74);
uniform float rim_strength = 0.2;
uniform float rim_power = 4.0;
uniform float ring_strength = 0.0;     // hair angel ring
uniform float ring_height = 0.42;      // view-space normal.y where the ring sits
uniform float ring_width = 0.07;
uniform float alpha_cut = 0.5;
uniform float hide_v = 9.0;            // texels past this UV.y are cut (the towel skirt in the tub)

void fragment() {
	if (UV.y > hide_v) {
		discard;
	}
	vec4 t = texture(albedo_tex, UV) * albedo;
	ALBEDO = t.rgb * tint;
	ALPHA = t.a;
#ifdef TOON_SCISSOR
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
#endif
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float ramp = smoothstep(shade_shift - shade_soft, shade_shift + shade_soft, ndl);
	vec3 band = mix(shade_color * shade_amount, vec3(1.0), ramp);
	vec3 l = LIGHT_COLOR / PI * ATTENUATION;
	DIFFUSE_LIGHT += l * band;
	// rim: the silhouette catches the lights in front of it
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	SPECULAR_LIGHT += l * rim_color * rim_strength * fres * smoothstep(-0.2, 0.3, ndl) * ALBEDO;
	// hair ring: a thin band where the view-space normal points a little upward
	if (ring_strength > 0.0) {
		float ny = NORMAL.y;
		float ring = smoothstep(ring_height - ring_width, ring_height, ny) * (1.0 - smoothstep(ring_height, ring_height + ring_width, ny));
		SPECULAR_LIGHT += l * ring * ring_strength * ramp * mix(vec3(1.0), ALBEDO * 2.0, 0.35);
	}
}
