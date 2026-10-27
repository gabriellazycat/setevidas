// Anime toon surface with alpha blending (irises, eye highlights, eyebrows, eyelines): drawn in
// render_priority order over the face. See toon.gdshaderinc.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

#include "res://shaders/toon.gdshaderinc"
