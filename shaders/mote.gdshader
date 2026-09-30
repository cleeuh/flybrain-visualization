// Faint drifting motes around the CNS: fixed pixel-size points, so they add stereo depth
// cues without growing into blobs when the camera flies in close.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled;

global uniform float anim_level;
uniform vec4 color : source_color = vec4(0.55, 0.75, 1.0, 1.0);
uniform float intensity = 0.3;
uniform float size_px = 3.0;

varying float fade;

void vertex() {
	float d = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	POINT_SIZE = size_px * VIEWPORT_SIZE.y / 1080.0;
	fade = smoothstep(40.0, 250.0, d) * COLOR.a;   // don't flare up right in front of the eye
}

void fragment() {
	float r = length(POINT_COORD - vec2(0.5)) * 2.0;
	float k = max(1.0 - r, 0.0);
	ALBEDO = color.rgb * k * k * intensity * fade * anim_level;
}
