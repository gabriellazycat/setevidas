// Light screen-space outline for the house (the MiSide-like painted look): a full-screen quad finds
// silhouettes and creases from the depth and normal buffers and darkens the scene colour there, so
// the line is a deeper shade of the surface (brown on wood, rose on the walls), never black. It fades
// with distance and in the dark. Toon characters write stencil 2 and keep their own hull outline.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;
stencil_mode read, compare_not_equal, 2;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D nr_tex : hint_normal_roughness_texture, filter_nearest;
uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform float strength = 1.0;
uniform float darken = 0.55;
uniform float depth_sens = 0.035;           // relative depth jump that starts a line
uniform float normal_sens = 0.35;           // 1 - cos between neighbour normals that starts a line
uniform bool use_normal = true;
uniform float fade_start = 7.0;
uniform float fade_end = 22.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

vec3 view_normal(vec2 uv) {
	vec4 nr = texture(nr_tex, uv);
	return normalize(nr.xyz * 2.0 - 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	// one pixel at 1080p, thicker on bigger screens
	vec2 px = max(1.0, VIEWPORT_SIZE.y / 1080.0) / VIEWPORT_SIZE;
	float c = lin_depth(uv, INV_PROJECTION_MATRIX);
	float d1 = lin_depth(uv + vec2(-px.x, -px.y), INV_PROJECTION_MATRIX);
	float d2 = lin_depth(uv + vec2(px.x, -px.y), INV_PROJECTION_MATRIX);
	float d3 = lin_depth(uv + vec2(-px.x, px.y), INV_PROJECTION_MATRIX);
	float d4 = lin_depth(uv + vec2(px.x, px.y), INV_PROJECTION_MATRIX);
	vec3 n = view_normal(uv);
	// grazing surfaces (floor far away) change depth fast without being an edge
	float graze = max(abs(n.z), 0.2);
	float dd = (abs(d1 - d4) + abs(d2 - d3)) / max(c, 0.05);
	float e = smoothstep(depth_sens, depth_sens * 2.0, dd * graze);
	if (use_normal) {
		vec3 n1 = view_normal(uv + vec2(-px.x, -px.y));
		vec3 n2 = view_normal(uv + vec2(px.x, -px.y));
		vec3 n3 = view_normal(uv + vec2(-px.x, px.y));
		vec3 n4 = view_normal(uv + vec2(px.x, px.y));
		float nd = (1.0 - dot(n1, n4)) + (1.0 - dot(n2, n3));
		e = max(e, smoothstep(normal_sens, normal_sens * 2.0, nd));
	}
	e *= 1.0 - smoothstep(fade_start, fade_end, c);
	vec3 col = texture(screen, uv).rgb;
	// the dark house keeps its gloom: lines melt away where there is little light
	float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
	e *= smoothstep(0.004, 0.05, l);
	ALBEDO = col * darken;
	ALPHA = clamp(e * strength, 0.0, 1.0);
}
