// Packs the left/right eye renders into one frame for single-input 3D displays.
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D left_eye : filter_linear;
uniform sampler2D right_eye : filter_linear;
// 0 SBS, 1 top-bottom, 2 row-interleaved, 3 column-interleaved, 4 checkerboard,
// 5 frame-sequential (see frame_eye), 6 mono
uniform int pattern = 0;
uniform int frame_eye = 0;      // sequential: 0 = left this frame, 1 = right

void fragment() {
	vec2 uv = UV;
	ivec2 px = ivec2(FRAGCOORD.xy);
	bool right = false;
	if (pattern == 0) {
		right = uv.x >= 0.5;
		uv.x = fract(uv.x * 2.0);
	} else if (pattern == 1) {
		right = uv.y >= 0.5;
		uv.y = fract(uv.y * 2.0);
	} else if (pattern == 2) {
		right = (px.y & 1) == 1;
	} else if (pattern == 3) {
		right = (px.x & 1) == 1;
	} else if (pattern == 4) {
		right = ((px.x + px.y) & 1) == 1;
	} else if (pattern == 5) {
		right = frame_eye == 1;
	}
	COLOR = right ? texture(right_eye, uv) : texture(left_eye, uv);
}
