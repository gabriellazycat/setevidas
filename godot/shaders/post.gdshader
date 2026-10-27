// Full-screen grade on top of the 3D view: per-phase tint / lift / saturation, fear (the house loses
// its colour, the edges close in, a slow breathing distortion), a hunt or the Shadow's stare (red
// pulsing vignette with the heartbeat), chromatic aberration, flash,
// fade to black, letterbox and film grain.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform vec3 tint = vec3(1.0);
uniform vec3 lift = vec3(0.0);
uniform float sat = 1.0;
uniform float bright = 1.0;
uniform float fear = 0.0;
uniform float hunt = 0.0;
uniform float pulse = 0.0;
uniform float vignette = 0.0;
uniform float ca = 0.0;
uniform float distort = 0.0;
uniform float flash = 0.0;
uniform vec3 flash_color = vec3(1.0);
uniform float fade = 0.0;
uniform float letterbox = 0.0;
uniform float grain = 1.0;
// final light warm grade: warm highlights, a gentle S-curve
uniform float warm_grade = 0.3;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r = length(c * vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0));
	float t = TIME;
	// fear / ghost distortion: slow warping waves stronger at the edges
	float w = distort * 0.012 + fear * 0.0025;
	uv += vec2(sin(uv.y * 14.0 + t * 2.1), cos(uv.x * 11.0 - t * 1.7)) * w * (0.3 + r * 1.5);
	// chromatic aberration
	float k = ca * 0.006 + fear * 0.0012;
	vec2 dir = normalize(c + 1e-5) * k * (0.2 + r);
	vec3 col;
	col.r = texture(screen, uv + dir).r;
	col.g = texture(screen, uv).g;
	col.b = texture(screen, uv - dir).b;
	// grade
	col = col * tint + lift;
	float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(vec3(l), col, sat * (1.0 - fear * 0.75));
	col *= bright;
	vec3 sc = clamp(col, 0.0, 1.0);
	col = mix(col, sc * sc * (3.0 - 2.0 * sc), warm_grade * 0.35);
	col *= mix(vec3(1.0), mix(vec3(1.0, 0.98, 1.0), vec3(1.05, 1.0, 0.92), smoothstep(0.1, 0.8, l)), warm_grade);
	// vignette: base + fear + hunt (red, pulsing)
	float vig = smoothstep(0.35, 0.95, r) * (0.35 + vignette * 0.8 + fear * 0.35);
	col *= 1.0 - vig;
	float h = smoothstep(0.3, 0.9, r) * hunt * (0.55 + 0.45 * pulse);
	col = mix(col, vec3(0.32, 0.0, 0.0), h * 0.6);
	// flash and fade
	col = mix(col, flash_color, clamp(flash, 0.0, 1.0) * 0.85);
	col *= 1.0 - clamp(fade, 0.0, 1.0);
	// letterbox
	float lb = letterbox * 0.11;
	if (SCREEN_UV.y < lb || SCREEN_UV.y > 1.0 - lb) {
		col = vec3(0.0);
	}
	// grain (animated, luminance weighted)
	float g = hash(SCREEN_UV * vec2(1931.0, 1171.0) + fract(t * 7.13)) - 0.5;
	col += g * grain * (0.035 + fear * 0.04) * (1.0 - l * 0.5);
	COLOR = vec4(col, 1.0);
}
