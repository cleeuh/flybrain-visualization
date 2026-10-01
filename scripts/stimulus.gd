class_name Stimulus
extends Node3D
## The outside world for the signal-flow slides. The body parts that sense it or move — eyes,
## antennae, proboscis, legs — are the real flybody model from the opening slide, already
## placed around the connectome (Fly.show_parts) and animated through its own joints. What is
## not the fly — the moving object, odour, sun, song, sugar — is white line art with yellow
## accents. Both are labelled as not connectome data.
##
## Timed on SignalFlow's clock: each stimulus arrives at the start of a cycle, which is when the
## first stage of real neurons fires (photoreceptors, receptor neurons, Johnston's organ, …).

const LINE := Color(0.92, 0.92, 0.92)
const HI := Color(1.0, 0.85, 0.29)
const LABEL := Color(0.78, 0.78, 0.78)
const LINE_PX := 0.0016       ## ribbon half-width as a fraction of the distance to the eye
const LEAD := 1.4             ## s a stimulus takes to arrive before the cycle starts

## Fly parts shown on each slide (Fly.show_parts filters).
const PARTS := {
	"vision": ["head:eyes"],
	"smell": ["antenna"], "memory": ["antenna"], "instinct": ["antenna"], "hearing": ["antenna"],
	"taste": ["rostrum", "haustellum", "labrum", "coxa_T1", "femur_T1", "tibia_T1", "tarsus_T1",
		"tarsus2_T1", "tarsus3_T1", "tarsus4_T1", "claw_T1"],
	# whole legs, seen from above on this slide (from the side they reach past the camera)
	"gait": ["coxa", "femur", "tibia", "tarsus", "claw"],
}
const TRIPOD_A := ["T1_left", "T2_right", "T3_left"]
## Glass opacity of the fly parts per slide: lower where the slide's close framing puts them
## right in front of the camera.
const PARTS_ALPHA := {"vision": 1.0, "smell": 0.7, "memory": 0.7, "instinct": 0.7, "hearing": 0.45,
	"taste": 0.7, "gait": 0.6}

var flow: SignalFlow
var fly: Fly
var head: Node3D              ## the stereo head, for camera-facing ribbons
var rois: Dictionary = {}     ## ROI name -> MeshInstance3D (read only)

var _kind := ""
var _f := {}
var _mesh := ImmediateMesh.new()
var _labels: Array[Label3D] = []
var _used := 0
var _a := 0.0                 ## overall opacity (follows the flow's fade)
var _pts := {}


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 10
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.material_override = mat
	mi.extra_cull_margin = 1e5
	add_child(mi)


func _process(_dt: float) -> void:
	_mesh.clear_surfaces()
	_used = 0
	var kind := flow.kind() if flow != null else ""
	if kind != _kind:
		_kind = kind
		_f = _build(kind)
	_a = flow.strength() if flow != null else 0.0
	var pose := {}
	if _a > 0.01 and not _f.is_empty() and head != null:
		var c := fposmod(flow.time(), SignalFlow.PERIOD)       # 0 = stage 0 fires
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		match _kind:
			"vision": _vision(c)
			"smell", "memory", "instinct": _odour(c)
			"compass": _compass()
			"hearing": pose = _hearing(c)
			"taste": pose = _taste(c)
			"gait": pose = _gait(c)
		_mesh.surface_end()
	if fly != null:
		var parts: Array = PARTS.get(_kind, []) if not _f.is_empty() else []
		if _kind == "hearing" and not _f.is_empty():
			parts = [_f.body]       # just the antenna being stimulated
		fly.show_parts(parts, _a * float(PARTS_ALPHA.get(_kind, 1.0)))
		fly.set_part_pose(pose)
	for i in range(_used, _labels.size()):
		_labels[i].visible = false


# --------------------------------------------------------------------------- drawing

func _seg(a: Vector3, b: Vector3, col: Color, width := 1.0) -> void:
	var eye := head.global_position
	var mid := (a + b) * 0.5
	var side := (b - a).cross(eye - mid).normalized() * eye.distance_to(mid) * LINE_PX * width
	var c := Color(col, col.a * _a)
	for p in [a - side, a + side, b + side, a - side, b + side, b - side]:
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(p)


func _ring(c: Vector3, r: float, u: Vector3, v: Vector3, col: Color, n := 24, from := 0.0, to := TAU) -> void:
	for i in n:
		var a0 := lerpf(from, to, float(i) / n)
		var a1 := lerpf(from, to, float(i + 1) / n)
		_seg(c + (u * cos(a0) + v * sin(a0)) * r, c + (u * cos(a1) + v * sin(a1)) * r, col)


func _dot(p: Vector3, col: Color, size := 3.0) -> void:
	var eye := head.global_position
	var fwd := (eye - p).normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.5:
		right = Vector3.RIGHT
	var up := right.cross(fwd)
	var s := eye.distance_to(p) * LINE_PX * size
	var c := Color(col, col.a * _a)
	for q in [[up, right], [right, -up], [-up, -right], [-right, up]]:
		for v in [p, p + q[0] * s, p + q[1] * s]:
			_mesh.surface_set_color(c)
			_mesh.surface_add_vertex(v)


func _label(text: String, pos: Vector3, col := LABEL, size := 20) -> void:
	if _used >= _labels.size():
		var l := Label3D.new()
		l.font = UITheme.mono()
		l.outline_size = 6
		l.pixel_size = 0.0007
		l.fixed_size = true
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.render_priority = 11
		l.outline_render_priority = 10
		add_child(l)
		_labels.append(l)
	var l := _labels[_used]
	_used += 1
	l.visible = true
	l.text = text
	l.font_size = size
	l.position = pos
	l.modulate = Color(col, col.a * _a)
	l.outline_modulate = Color(0, 0, 0, 0.85 * _a)


# --------------------------------------------------------------------------- geometry

func _box(name: String) -> AABB:
	if not _pts.has(name):
		var mi: MeshInstance3D = rois.get(name)
		_pts[name] = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] if mi != null and mi.mesh != null else PackedVector3Array()
	var p: PackedVector3Array = _pts[name]
	if p.is_empty():
		return AABB()
	var b := AABB(p[0], Vector3.ZERO)
	for v in p:
		b = b.expand(v)
	return b


func _brain_box() -> AABB:
	var b := AABB()
	for n in ["AL(L)", "AL(R)", "GNG", "LO(L)", "LO(R)", "SMP(L)", "SMP(R)"]:
		var nb := _box(n)
		if nb.size != Vector3.ZERO:
			b = nb if b.size == Vector3.ZERO else b.merge(nb)
	return b


## "(L)" / "(R)" of the hemisphere away from the slide's camera (SignalFlow decides the facing
## one from the slide's yaw). Lateral things — the eye, an antenna — are in frame on that side.
func _far_side() -> String:
	return "(L)" if flow != null and flow.facing() == "(R)" else "(R)"


func _build(kind: String) -> Dictionary:
	if fly == null:
		return {}
	match kind:
		"vision":
			var b := _box("LA" + _far_side())
			if b.size == Vector3.ZERO:
				return {}
			var out := Vector3(signf(b.get_center().x), 0, 0)
			var eye := PackedVector3Array()
			for v in fly.part_vertices("head:eyes"):
				if signf(v.x) == out.x:
					eye.append(v)
			if eye.is_empty():
				return {}
			var ec := Vector3.ZERO
			for v in eye:
				ec += v
			return {"c": ec / eye.size(), "out": out, "size": b.size, "eye": eye}
		"smell", "memory", "instinct":
			var bb := _brain_box()
			if bb.size == Vector3.ZERO:
				return {}
			return {"tips": [fly.part_point("antenna_left", true), fly.part_point("antenna_right", true)],
				"src": Vector3(0, bb.get_center().y + 120.0, bb.position.z - 900.0)}
		"compass":
			var eb := _box("EB")
			return {} if eb.size == Vector3.ZERO else {"c": eb.get_center(), "r": maxf(eb.size.x, 300.0) * 1.6}
		"hearing":
			# the far side's antenna, like the eye (a near-side one would sit under the panel)
			var b := _box("AL" + _far_side())
			var body := "antenna_left" if b.get_center().x == fly.part_point("antenna_left").x or \
				signf(b.get_center().x) == signf(fly.part_point("antenna_left").x) else "antenna_right"
			return {"body": body, "tip": fly.part_point(body, true)}
		"taste":
			return {"foot": fly.part_point("claw_T1_left", true), "mouth": fly.part_point("haustellum", true)}
		"gait":
			return {"label": fly.part_point("coxa_T2_left") + Vector3(0, -300, 0)}
	return {}


# --------------------------------------------------------------------------- stimuli

## An object passes in front of the eye; the facets turned toward it see it. Its pass is
## centred on the cycle start, when the photoreceptor pulses begin.
func _vision(c: float) -> void:
	var out: Vector3 = _f.out
	var size: Vector3 = _f.size
	var ec: Vector3 = _f.c
	var u := wrapf(c, -SignalFlow.PERIOD * 0.5, SignalFlow.PERIOD * 0.5) / (SignalFlow.PERIOD * 0.5)
	var obj := ec + out * 420.0 + Vector3(0, size.y * 0.3, u * size.z * 1.6)
	_ring(obj, 45.0, Vector3.RIGHT, Vector3.UP, LINE)
	_ring(obj, 45.0, Vector3.UP, Vector3.BACK, LINE)
	_ring(obj, 45.0, Vector3.BACK, Vector3.RIGHT, LINE)
	_label("MOVING OBJECT", obj + Vector3(0, -80, 0), HI)
	var eye: PackedVector3Array = _f.eye
	var to_obj := (obj - ec).normalized()
	var hits := 0
	for i in range(0, eye.size(), maxi(eye.size() / 400, 1)):
		var v := eye[i]
		if (v - ec).normalized().dot(to_obj) > 0.93:
			hits += 1
			if hits % 3 == 0:
				_seg(obj, v, Color(HI, 0.35), 0.5)
			_dot(v, HI, 1.6)
	_label("COMPOUND EYE · fly model, not connectome", ec + out * 180.0 + Vector3(0, size.y * 0.7, 0))


## A puff of odour drifts to both antennae and arrives as the receptor neurons fire.
func _odour(c: float) -> void:
	var src: Vector3 = _f.src
	var arrive := fposmod(c + LEAD, SignalFlow.PERIOD) / LEAD        # 1 = arriving
	var name := "ODOUR"
	if _kind == "instinct":       # alternates with the panel figure
		name = "FOOD ODOUR" if int(floor(flow.time() / SignalFlow.PERIOD)) % 2 == 0 else "DANGER ODOUR (wasp)"
	_label(name, src + Vector3(0, 90, 0), HI)
	for tip in _f.tips:
		for i in 9:
			var u := arrive - i * 0.04
			if u <= 0.0 or u > 1.0:
				continue
			var p: Vector3 = src.lerp(tip, u) + Vector3(sin(u * 11.0 + i) * 60.0, cos(u * 7.0 + i) * 40.0, 0) * (1.0 - u)
			_dot(p, Color(HI, 0.9), 2.4)
	_label("ANTENNAE · fly model, not connectome", fly.part_point("antenna_left").lerp(fly.part_point("antenna_right"), 0.5) + Vector3(0, -260, 0))
	if _kind == "memory":
		_label("+ SUGAR reward", src + Vector3(0, 40, 0), HI, 18)


## The sun (or a landmark) the fly steers by; ring neurons see where it is.
func _compass() -> void:
	var ang := flow.time() * 0.3
	var sun: Vector3 = _f.c + Vector3(cos(ang), 0.55, sin(ang)) * float(_f.r)
	_ring(sun, 40.0, Vector3.RIGHT, Vector3.UP, HI, 20)
	for k in 8:
		var d := Vector3.RIGHT.rotated(Vector3.BACK, TAU * k / 8.0)
		_seg(sun + d * 55.0, sun + d * 80.0, HI, 0.8)
	_seg(sun, _f.c, Color(HI, 0.25), 0.6)
	_label("SUN / LANDMARK (visual cue)", sun + Vector3(0, 120, 0), HI)


## Courtship song: sound pulses reach the antenna and shake it at cycle start; the model's
## antenna turns about its own joint. Returns the joint pose for the fly.
func _hearing(c: float) -> Dictionary:
	var tip: Vector3 = _f.tip
	var src := tip + Vector3(0, 60, -600)
	var arrive := fposmod(c + LEAD, SignalFlow.PERIOD) / LEAD
	for k in 3:
		var u := arrive - k * 0.15
		if u > 0.0 and u <= 1.0:
			_ring(src.lerp(tip, u), 30.0 + 120.0 * u, Vector3.RIGHT, Vector3.UP, Color(HI, 1.0 - u * 0.6), 20, -0.9, 0.9)
	_label("COURTSHIP SONG", src + Vector3(0, 120, 0), HI)
	_label("ANTENNA · fly model, not connectome", fly.part_point(_f.body) + Vector3(0, -200, 0))
	var shake := exp(-c * 2.5) * 0.25 * sin(flow.time() * 30.0)
	return {_f.body: [0.0, 0.0, 0.15 + shake]}


## A front leg is on sugar (the leg taste neurons fire at cycle start); once the signal reaches
## the proboscis motor neurons, the model's proboscis extends through its rostrum and haustellum
## joints. Returns the joint pose for the fly.
func _taste(c: float) -> Dictionary:
	var foot: Vector3 = _f.foot
	var touch := exp(-c * 1.5)
	_ring(foot + Vector3(0, -12, 0), 22.0, Vector3.RIGHT, Vector3.BACK, Color(HI, 0.5 + 0.5 * touch), 14)
	_label("SUGAR", foot + Vector3(0, -55, 0), HI, 18)
	var ext := smoothstep(2.0, 2.8, c) * (1.0 - smoothstep(4.6, 5.4, c))
	_label("PROBOSCIS · fly model" + (" — extends" if ext > 0.1 else ""), (_f.mouth as Vector3) + Vector3(0, -70, 0),
		HI if ext > 0.1 else LABEL)
	_label("FRONT LEG · fly model", foot + Vector3(0, 60, 0))
	return {"rostrum": [0.0, 0.0, -0.9 * ext], "haustellum": [0.0, 0.0, -1.1 * ext]}


## Walking: the model's six legs step in two alternating tripods, in step with their motor
## neurons (tripod L1 R2 L3 pushes in the first half of the cycle). Returns the joint pose.
func _gait(c: float) -> Dictionary:
	var half := SignalFlow.PERIOD * 0.5
	var local := fmod(c, half) / half
	var a_stance := c < half
	var pose := {}
	for seg in ["T1", "T2", "T3"]:
		for side in ["left", "right"]:
			var leg := "%s_%s" % [seg, side]
			var stance := (leg in TRIPOD_A) == a_stance
			# stance: the leg sweeps back on the ground; swing: it lifts and returns forward
			var sweep := lerpf(0.25, -0.25, local) if stance else lerpf(-0.25, 0.25, local)
			var lift := 0.0 if stance else sin(local * PI)
			pose["coxa_" + leg] = [0.0, 0.0, sweep]
			pose["femur_" + leg] = [0.0, 0.0, 0.35 * lift]
			pose["tibia_" + leg] = [0.0, 0.0, -0.3 * lift]
	_label("LEGS · fly model, not connectome · tripod L1 R2 L3 ↔ R1 L2 R3", _f.label)
	return pose
