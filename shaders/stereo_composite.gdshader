// Packs the left/right eye renders into one frame for single-input 3D displays.
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D left_eye : filter_linear;
uniform sampler2D right_eye : filter_linear;
// 0 side by side (SBS half / full / wall), 1 mono
uniform int pattern = 0;

void fragment() {
	vec2 uv = UV;
	bool right = false;
	if (pattern == 0) {
		right = uv.x >= 0.5;
		uv.x = fract(uv.x * 2.0);
	}
	COLOR = right ? texture(right_eye, uv) : texture(left_eye, uv);
}
