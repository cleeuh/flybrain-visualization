// Screen-space ribbon for neuron skeleton segments rendered through a MultiMesh.
// Each instance is one segment: instance transform origin = A, basis column 0 = B - A.
// The quad's UV.x picks the end (A or B), UV.y picks the side (-1 / +1).
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, depth_test_disabled, skip_vertex_transform;

uniform float width_px = 2.0;
uniform float brightness = 1.0;
uniform vec4 colors[16];
uniform float visible_groups[16];
uniform float highlight = -1.0;   // neuron index, -1 = none
uniform float dim_others = 1.0;   // brightness multiplier for non-highlighted neurons
uniform sampler2D activity : filter_nearest, repeat_disable;   // 1-D, indexed by neuron id
uniform float sim_active = 0.0;   // 1 = simulation running: rest neurons dimmed, spikes flash
uniform float rest_level = 0.2;

varying vec4 col;

void vertex() {
	vec3 a = MODEL_MATRIX[3].xyz;
	vec3 d = MODEL_MATRIX[0].xyz;
	vec3 b = a + d;

	int g = int(INSTANCE_CUSTOM.x + 0.5);
	float jitter = INSTANCE_CUSTOM.w;
	float vis = visible_groups[g];
	float nid = INSTANCE_CUSTOM.z;
	float hl = highlight < 0.0 ? 1.0 : (abs(nid - highlight) < 0.5 ? 3.0 : dim_others);
	col = colors[g] * (0.75 + 0.5 * jitter) * brightness * hl;
	if (sim_active > 0.5) {
		float a = texelFetch(activity, ivec2(int(nid + 0.5), 0), 0).r;
		vec4 flash = (colors[g] * 2.0 + vec4(0.25)) * brightness * 2.0;
		col = mix(col * rest_level, flash, a);
	}
	col.a = vis;

	mat4 vp = PROJECTION_MATRIX * VIEW_MATRIX;
	vec4 ca = vp * vec4(a, 1.0);
	vec4 cb = vp * vec4(b, 1.0);
	// screen-space direction (guard against points behind the camera)
	vec2 sa = ca.xy / max(ca.w, 1e-4);
	vec2 sb = cb.xy / max(cb.w, 1e-4);
	vec2 dir = (sb - sa) * VIEWPORT_SIZE;
	float len = length(dir);
	dir = len > 1e-6 ? dir / len : vec2(1.0, 0.0);
	vec2 nrm = vec2(-dir.y, dir.x);

	vec4 c = mix(ca, cb, UV.x);
	float side = UV.y * 2.0 - 1.0;
	c.xy += nrm * side * (width_px / VIEWPORT_SIZE) * c.w;
	if (vis < 0.5) { c = vec4(0.0, 0.0, -10.0, 1.0); }  // cull hidden groups
	POSITION = c;
}

void fragment() {
	ALBEDO = col.rgb;
	ALPHA = col.a;
}
