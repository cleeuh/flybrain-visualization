class_name Neurons
extends MultiMeshInstance3D
## Loads res://data/neurons.mm (MultiMesh buffer written by tools/fetch_data.py)
## and renders every skeleton segment as a screen-space ribbon.

const MAX_GROUPS := 16
const FADE_SECONDS := 0.8      ## class show / hide cross-fade
const REVEAL_SECONDS := 2.6    ## grow-in from the centre

# Superclass -> display color. Anything unlisted gets a hashed hue.
const GROUP_COLORS := {
	"descending_neuron": Color(1.00, 0.35, 0.25),
	"ascending_neuron": Color(1.00, 0.70, 0.20),
	"sensory_ascending": Color(1.00, 0.90, 0.40),
	"cb_intrinsic": Color(0.40, 0.75, 1.00),
	"cb_sensory": Color(0.30, 1.00, 0.85),
	"cb_motor": Color(1.00, 0.45, 0.85),
	"visual_projection": Color(0.65, 0.45, 1.00),
	"visual_centrifugal": Color(0.85, 0.60, 1.00),
	"ol_intrinsic": Color(0.30, 0.55, 1.00),
	"ol_sensory": Color(0.20, 0.90, 1.00),
	"vnc_intrinsic": Color(0.35, 1.00, 0.45),
	"vnc_sensory": Color(0.80, 1.00, 0.30),
	"vnc_motor": Color(1.00, 0.30, 0.55),
	"vnc_efferent": Color(1.00, 0.55, 0.45),
}

var groups: Array = []          # [{id, name, count}]
var index: Array = []           # per-neuron metadata
var segment_count := 0
var group_visible := PackedFloat32Array()   ## target state, 0 / 1
var material: ShaderMaterial
var _shown := PackedFloat32Array()          ## what the shader draws, easing toward group_visible
var _reveal_max := 3000.0
var _reveal_t := -1.0          ## seconds into the grow-in, -1 when not growing
var _reveal_len := REVEAL_SECONDS
var _mm_path := ""
var _offsets := PackedInt32Array()          ## first segment of each neuron (neurons are contiguous)
var _flow_img: Image                        ## per-neuron signal-flow start delay (R), -1 = not in it
var _flow_tex: ImageTexture
var _flow_set := PackedInt32Array()         ## neurons currently in the flow
var flow_length := {}                       ## neuron -> longest routed path (µm), for checks


func load_data(mm_path := "res://data/neurons.mm", json_path := "res://data/neurons.json") -> bool:
	var meta = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if meta == null:
		push_error("Neurons: missing %s (run tools/fetch_data.py)" % json_path)
		return false
	groups = meta.groups
	index = meta.index
	segment_count = int(meta.segments)

	var f := FileAccess.open(mm_path, FileAccess.READ)
	if f == null:
		push_error("Neurons: cannot open %s" % mm_path)
		return false
	var t := Time.get_ticks_msec()
	var floats := f.get_buffer(f.get_length()).to_float32_array()
	f.close()
	var count := floats.size() / 16

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _make_quad()
	mm.instance_count = count
	mm.buffer = floats
	var lo: Vector3 = Vector3(meta.aabb_min[0], meta.aabb_min[1], meta.aabb_min[2])
	var hi: Vector3 = Vector3(meta.aabb_max[0], meta.aabb_max[1], meta.aabb_max[2])
	mm.custom_aabb = AABB(lo, hi - lo)
	custom_aabb = AABB(lo, hi - lo)
	multimesh = mm
	_mm_path = mm_path
	_offsets.resize(index.size() + 1)
	var o := 0
	for i in index.size():
		_offsets[i] = o
		o += int(index[i].segments)
	_offsets[index.size()] = o
	_flow_img = Image.create(maxi(index.size(), 1), 1, false, Image.FORMAT_RF)
	_flow_img.fill(Color(-1, 0, 0))
	_flow_tex = ImageTexture.create_from_image(_flow_img)
	_reveal_max = maxf(lo.length(), hi.length()) + 100.0

	material = ShaderMaterial.new()
	material.shader = load("res://shaders/neuron_ribbon.gdshader")
	var colors := PackedColorArray()
	colors.resize(MAX_GROUPS)
	group_visible.resize(MAX_GROUPS)
	for g in groups:
		var name: String = g.name
		var c: Color = GROUP_COLORS.get(name, Color.from_hsv(fmod(hash(name) / 1000.0, 1.0), 0.7, 1.0))
		colors[int(g.id)] = c
		group_visible[int(g.id)] = 1.0
	material.set_shader_parameter("colors", colors)
	_shown = group_visible.duplicate()
	material.set_shader_parameter("visible_groups", _shown)
	material.set_shader_parameter("sweep_z", Vector2(lo.z, hi.z))
	material.set_shader_parameter("flow", _flow_tex)
	material_override = material
	print("Neurons: %d neurons, %d segments loaded in %d ms" % [index.size(), count, Time.get_ticks_msec() - t])
	return true


func set_group_visible(id: int, on: bool) -> void:
	group_visible[id] = 1.0 if on else 0.0


func toggle_group(id: int) -> void:
	set_group_visible(id, group_visible[id] < 0.5)


func set_all_visible(on: bool) -> void:
	for g in groups:
		group_visible[int(g.id)] = 1.0 if on else 0.0


## Grow the connectome out from the centre of the CNS, a bright front leading the way.
func reveal(seconds := REVEAL_SECONDS) -> void:
	_reveal_len = seconds
	_reveal_t = 0.0
	material.set_shader_parameter("reveal_radius", 0.0)


func _process(dt: float) -> void:
	if material == null:
		return
	if _reveal_t >= 0.0:
		# clamped step: the shader-compile hitch on the first frames must not skip the grow-in
		_reveal_t += minf(dt, 1.0 / 30.0)
		var k := clampf(_reveal_t / _reveal_len, 0.0, 1.0)
		var r := _reveal_max * (1.0 - pow(1.0 - k, 2.0))
		material.set_shader_parameter("reveal_radius", r if k < 1.0 else 1e9)
		if k >= 1.0:
			_reveal_t = -1.0
	var moved := false
	for i in _shown.size():
		if _shown[i] != group_visible[i]:
			_shown[i] = move_toward(_shown[i], group_visible[i], dt / FADE_SECONDS)
			moved = true
	if moved:
		material.set_shader_parameter("visible_groups", _shown)


func set_width(px: float) -> void:
	material.set_shader_parameter("width_px", px)


func set_brightness(b: float) -> void:
	material.set_shader_parameter("brightness", b)


func set_activity_texture(t: Texture2D) -> void:
	material.set_shader_parameter("activity", t)


func set_sim_active(on: bool) -> void:
	material.set_shader_parameter("sim_active", 1.0 if on else 0.0)


func set_highlight(neuron_idx: int) -> void:
	material.set_shader_parameter("highlight", float(neuron_idx))
	material.set_shader_parameter("dim_others", 1.0 if neuron_idx < 0 else 0.15)


# --------------------------------------------------------------------------- signal flow

## Segment endpoints of neuron `i`: [a0, b0, a1, b1, …] (read back from the data file).
func segments_of(i: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var f := FileAccess.open(_mm_path, FileAccess.READ)
	if f == null or i < 0 or i >= index.size():
		return out
	var first := _offsets[i]
	var k := _offsets[i + 1] - first
	f.seek(first * 64)
	var fl := f.get_buffer(k * 64).to_float32_array()
	out.resize(k * 2)
	for s in k:
		var b := s * 16
		var a := Vector3(fl[b + 3], fl[b + 7], fl[b + 11])
		out[s * 2] = a
		out[s * 2 + 1] = a + Vector3(fl[b], fl[b + 4], fl[b + 8])
	return out


## Store each segment's distance along the neuron's branches (µm, from wherever its signal
## enters) in the spare basis slot the ribbon shader reads as the path coordinate. The
## transform is rebuilt from the data file (start + direction), not read back from the
## renderer.
func set_path_distance(i: int, seg: PackedVector3Array, dist: PackedFloat32Array) -> void:
	var mm := multimesh
	var first := _offsets[i]
	var longest := 0.0
	for s in dist.size():
		var a := seg[s * 2]
		var b := Basis(seg[s * 2 + 1] - a, Vector3(dist[s], 1, 0), Vector3(0, 0, 1))
		mm.set_instance_transform(first + s, Transform3D(b, a))
		longest = maxf(longest, dist[s])
	flow_length[i] = longest


## Neurons taking part in the signal flow, with the delay (s) at which their pulse starts;
## every other neuron is dimmed while `strength` > 0.
func set_flow(delays: Dictionary) -> void:
	for i in _flow_set:
		_flow_img.set_pixel(i, 0, Color(-1, 0, 0))
	_flow_set = PackedInt32Array()
	for i in delays:
		_flow_img.set_pixel(i, 0, Color(float(delays[i]), 0, 0))
		_flow_set.append(i)
	_flow_tex.update(_flow_img)


func set_flow_params(strength: float, time: float, period: float, speed: float) -> void:
	material.set_shader_parameter("flow_strength", strength)
	material.set_shader_parameter("flow_time", time)
	material.set_shader_parameter("flow_period", period)
	material.set_shader_parameter("flow_speed", speed)


func group_color(id: int) -> Color:
	var colors: PackedColorArray = material.get_shader_parameter("colors")
	return colors[id]


static func _make_quad() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
