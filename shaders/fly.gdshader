// Solid body for the whole fly: opaque and depth-tested so its geometry reads, with simple
// view-space key / fill lighting and a soft fresnel rim that keeps it in the hologram style.
// Fading out (color.a < 1) dissolves it with an ordered screen-space dither rather than
// blending, so it never turns into overlapping glass.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec4 color : source_color = vec4(1.0, 0.72, 0.38, 1.0);
uniform float rim = 0.4;
uniform float rim_power = 2.5;

void fragment() {
	if (color.a < 0.999) {
		// interleaved gradient noise: a stable per-pixel threshold for the dissolve
		float t = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (t >= color.a) {
			discard;
		}
	}
	vec3 n = normalize(FRONT_FACING ? NORMAL : -NORMAL);   // view space
	vec3 v = normalize(VIEW);
	vec3 key = normalize(vec3(-0.45, 0.7, 0.55));
	float diff = max(dot(n, key), 0.0);
	float hemi = 0.5 + 0.5 * n.y;
	float spec = pow(max(dot(reflect(-key, n), v), 0.0), 28.0);
	float f = pow(1.0 - abs(dot(n, v)), rim_power);
	ALBEDO = color.rgb * (0.05 + 0.15 * hemi + 0.6 * diff * diff) + vec3(0.18 * spec) + color.rgb * rim * f;
}
