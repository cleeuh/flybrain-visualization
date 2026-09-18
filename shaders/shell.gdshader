// Translucent additive "glass" shell with a fresnel rim, for neuropil / brain outlines.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, depth_test_disabled;

uniform vec4 color : source_color = vec4(0.3, 0.5, 0.9, 1.0);
uniform float rim_power = 3.0;
uniform float fill = 0.03;
uniform float rim = 0.35;

void fragment() {
	vec3 n = normalize(NORMAL);
	float f = pow(1.0 - abs(dot(n, normalize(VIEW))), rim_power);
	ALBEDO = color.rgb * (fill + rim * f) * color.a;
}
