// Ghost flesh: near-black body that breathes and wavers, edges that dissolve into smoke and a cold
// rim light. heat (the Shadow about to strike) turns it ember red: wine-dark flesh, a red rim and
// glowing cracks that spread over it.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform vec3 body_color : source_color = vec3(0.004, 0.004, 0.006);
uniform vec3 rim_color : source_color = vec3(0.1, 0.12, 0.16);
uniform float alpha = 1.0;
uniform float wobble = 0.03;
uniform float dissolve = 0.32;
uniform float foot_fade = 0.75;   // the lower legs trail off into smoke (model-space height)
uniform float fade_y0 = 0.0;      // where that fade starts (the Shadow's head and hands: their cut ends)
uniform float fade_noise = 1.0;
uniform float wet = 0.0;         // the Drowner: glossy, dripping
uniform float heat = 0.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

varying vec3 wpos;
varying float ly;

void vertex() {
	float t = TIME;
	vec3 p = VERTEX;
	float n = sin(p.y * 7.0 + t * 1.7) * 0.5 + sin(p.y * 13.0 - t * 2.3 + p.x * 9.0) * 0.5;
	ly = VERTEX.y;
	VERTEX += NORMAL * n * wobble * (1.0 + 2.0 * clamp(1.0 - VERTEX.y / max(foot_fade, 0.01), 0.0, 1.0));
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	float n = texture(noise_tex, wpos.xy * 0.9 + vec2(0.0, -t * 0.12)).g * 0.6 + texture(noise_tex, wpos.zy * 1.7 + vec2(t * 0.07, -t * 0.2)).r * 0.4;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	// edges dissolve: low-alpha where the noise is low near the silhouette
	float edge = smoothstep(dissolve, dissolve + 0.25, n + (1.0 - fres) * 0.6);
	float legs = foot_fade > 0.0 ? smoothstep(fade_y0, fade_y0 + foot_fade, ly + (n - 0.5) * 0.35 * fade_noise) : 1.0;
	float a = alpha * edge * legs;
	if (a < 0.02) {
		discard;
	}
	ALBEDO = mix(mix(body_color, vec3(0.05, 0.08, 0.09), wet * 0.6), vec3(0.09, 0.0, 0.0), heat * 0.8);
	ROUGHNESS = mix(0.9, 0.05, wet);
	SPECULAR = mix(0.1, 0.9, wet);
	ALPHA = a;
	// cracks: thin ridges of the noise that widen and brighten with the heat, pulsing faster near 1
	float cn = texture(noise_tex, wpos.xy * 0.55 + wpos.zx * 0.35 + vec2(0.0, t * 0.03)).b;
	float ridge = 1.0 - abs(cn * 2.0 - 1.0);
	float crack = smoothstep(1.0 - 0.12 * heat, 1.0, ridge) * smoothstep(0.05, 0.4, heat);
	float pulse = 0.7 + 0.3 * sin(t * mix(4.0, 16.0, heat));
	vec3 red = vec3(1.0, 0.025, 0.01);
	EMISSION = mix(rim_color, red, heat) * fres * (1.2 + heat * 1.3) + red * (crack * 1.8 + 0.12 * heat) * pulse * heat;
}
