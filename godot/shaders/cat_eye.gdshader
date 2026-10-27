// Cat eye: amber iris with radial fibres, a vertical slit pupil that dilates, a wet cornea and the
// tapetum shine that glows back at the camera in the dark (stronger in Cat Vision).
shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;
stencil_mode write, compare_always, 2;

uniform vec3 iris_inner : source_color = vec3(0.98, 0.78, 0.3);
uniform vec3 iris_outer : source_color = vec3(0.6, 0.7, 0.24);
uniform float pupil = 0.3;      // 0 = thin slit, 1 = round and wide
uniform float blink = 0.0;      // 1 = lid closed
uniform vec3 lid_color : source_color = vec3(0.82, 0.47, 0.19);
uniform float shine = 0.0;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;           // front pole at the centre
	float r = length(p);
	float ang = atan(p.y, p.x);
	// iris
	float fib = 0.5 + 0.5 * sin(ang * 40.0 + r * 9.0) * 0.5 + 0.25 * sin(ang * 13.0);
	vec3 iris = mix(iris_inner, iris_outer, smoothstep(0.15, 0.85, r));
	iris *= 0.82 + 0.3 * fib;
	iris *= 1.0 - smoothstep(0.82, 0.95, r) * 0.7;  // dark limbal ring
	// slit pupil (an ellipse whose width grows with dilation)
	float pw = mix(0.07, 0.62, pupil);
	float ph = mix(0.88, 0.7, pupil);
	float pd = length(vec2(p.x / pw, p.y / ph));
	float pup = 1.0 - smoothstep(0.92, 1.05, pd);
	vec3 col = mix(iris, vec3(0.01), pup);
	// sclera barely visible in cats: darken outside the iris
	col = mix(col, vec3(0.18, 0.15, 0.1), smoothstep(0.95, 1.05, r));
	// eyelid: the upper lid comes down with blink
	// glTF flips V, so the top of the eye is at negative p.y
	float lid = smoothstep(1.02 - blink * 2.15, 1.06 - blink * 2.15, -p.y * 0.5 + 0.5);
	// two soft catchlights: what makes an eye look alive (and a cat look sweet)
	float cl = smoothstep(0.2, 0.1, length(p - vec2(-0.3, -0.36))) + 0.6 * smoothstep(0.1, 0.05, length(p - vec2(0.22, 0.3)));
	col = mix(col, vec3(1.0), clamp(cl, 0.0, 1.0) * 0.85);
	col = mix(col, lid_color * 0.7, lid);
	ALBEDO = col;
	ROUGHNESS = mix(0.04, 0.8, lid);
	SPECULAR = mix(0.9, 0.3, lid);
	CLEARCOAT = 1.0 - lid;
	CLEARCOAT_ROUGHNESS = 0.02;
	// tapetum lucidum: the pupil reflects light back
	float back = pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 6.0);
	EMISSION = vec3(0.35) * clamp(cl, 0.0, 1.0) * (1.0 - lid) + (iris_inner * 1.4 + vec3(0.2, 0.25, 0.1)) * pup * back * shine * (1.0 - lid) * 0.6;
}
