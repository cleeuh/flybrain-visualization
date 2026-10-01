// Translucent wing membrane: additive fresnel glass like shell.gdshader, but depth-tested
// against the solid fly so the body hides the wing behind it.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform vec4 color : source_color = vec4(0.62, 0.8, 1.0, 1.0);
uniform float fill = 0.04;
uniform float rim = 0.65;
uniform float rim_power = 3.0;

void fragment() {
	float f = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), rim_power);
	ALBEDO = color.rgb * (fill + rim * f) * color.a;
}
