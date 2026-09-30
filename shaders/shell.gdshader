// Translucent additive "glass" shell with a fresnel rim, for neuropil / brain outlines.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, depth_test_disabled;

global uniform float anim_level;
uniform vec4 color : source_color = vec4(0.3, 0.5, 0.9, 1.0);
uniform float rim_power = 3.0;
uniform float fill = 0.03;
uniform float rim = 0.35;
uniform float breathe = 0.0;      // slow brightness swell, 0..1 amplitude
uniform float scan = 0.0;         // brightness of the drifting contour lines
uniform float scan_spacing = 40.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float f = pow(1.0 - abs(dot(n, normalize(VIEW))), rim_power);
	float a = anim_level;
	float swell = 1.0 + a * breathe * sin(TIME * 2.0);
	// thin horizontal contours creeping upward: reads the surface's shape without a fill
	float line = pow(0.5 + 0.5 * sin(wpos.y / scan_spacing * 6.2832 - TIME * 1.5), 24.0);
	ALBEDO = color.rgb * ((fill + rim * f) * swell + a * scan * line * (0.3 + f)) * color.a;
}
