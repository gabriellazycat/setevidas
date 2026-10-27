// Anime toon surface (opaque / alpha-cut parts: skin, clothes, hair, eye whites). See toon.gdshaderinc.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;
stencil_mode write, compare_always, 2;

#define TOON_SCISSOR
#include "res://shaders/toon.gdshaderinc"
