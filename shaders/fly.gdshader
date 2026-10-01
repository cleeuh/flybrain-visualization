// Solid body for the whole fly: opaque and depth-tested so its geometry reads, with soft
// view-space lighting (wrapped diffuse, broad sheen) and a fresnel rim that keeps it in the
// hologram style.
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
	// wrapped diffuse: light rolls softly round the curves instead of cutting off at a terminator
	float wrap = clamp((dot(n, key) + 0.5) / 1.5, 0.0, 1.0);
	float hemi = 0.5 + 0.5 * n.y;
	// broad, faint sheen like waxy cuticle rather than a sharp hotspot
	float spec = pow(max(dot(reflect(-key, n), v), 0.0), 10.0);
	float f = pow(1.0 - abs(dot(n, v)), rim_power);
	ALBEDO = color.rgb * (0.08 + 0.14 * hemi + 0.62 * wrap * wrap) + vec3(0.07 * spec) + color.rgb * rim * f;
}
