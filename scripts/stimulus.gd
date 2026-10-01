class_name Stimulus
extends Node3D
## The outside world for the signal-flow slides: what the fly sees, smells, hears or tastes,
## and the body parts that sense it or move — none of which is in the connectome. Drawn as
## white line-art sketches with yellow accents and monospace labels marked "(not in data)",
## so they read as illustration next to the real neurons.
##
## Timed on SignalFlow's clock: each stimulus arrives at the start of a cycle, which is when the
## first stage of real neurons fires (photoreceptors, receptor neurons, Johnston's organ, …).

const LINE := Color(0.92, 0.92, 0.92)
const HI := Color(1.0, 0.85, 0.29)
const LABEL := Color(0.78, 0.78, 0.78)
const LINE_PX := 0.0016       ## ribbon half-width as a fraction of the distance to the eye
const LEAD := 1.4             ## s a stimulus takes to arrive before the cycle starts

var flow: SignalFlow
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
	if _a > 0.01 and not _f.is_empty() and head != null:
		var c := fposmod(flow.time(), SignalFlow.PERIOD)       # 0 = stage 0 fires
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		match _kind:
			"vision": _vision(c)
			"smell", "memory", "instinct": _odour(c)
			"compass": _compass()
			"hearing": _hearing(c)
			"taste": _taste(c)
			"gait": _gait(c)
		_mesh.surface_end()
	for i in range(_used, _labels.size()):
		_labels[i].visible = false


## Seconds until the next cycle start (stimulus arrival), 0..PERIOD.
static func _until(c: float) -> float:
	return SignalFlow.PERIOD - c if c > 0.0 else 0.0


# --------------------------------------------------------------------------- drawing

func _seg(a: Vector3, b: Vector3, col: Color, width := 1.0) -> void:
	var eye := head.global_position
	var mid := (a + b) * 0.5
	var side := (b - a).cross(eye - mid).normalized() * eye.distance_to(mid) * LINE_PX * width
	var c := Color(col, col.a * _a)
	for p in [a - side, a + side, b + side, a - side, b + side, b - side]:
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(p)


func _poly(pts: Array, col: Color, width := 1.0) -> void:
	for i in pts.size() - 1:
		_seg(pts[i], pts[i + 1], col, width)


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

func _verts(name: String) -> PackedVector3Array:
	if not _pts.has(name):
		var mi: MeshInstance3D = rois.get(name)
		_pts[name] = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] if mi != null and mi.mesh != null else PackedVector3Array()
	return _pts[name]


func _box(name: String) -> AABB:
	var p := _verts(name)
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


## An antenna in front of the head above its antennal lobe: [base, joint 2, joint 3, arista tip].
func _antenna(al: String) -> Array:
	var bb := _brain_box()
	var c := _box(al).get_center()
	var out := Vector3(signf(c.x), 0, 0)
	var base := Vector3(c.x * 0.55, c.y + 70.0, bb.position.z - 120.0)
	var j2 := base + Vector3(0, 10, -70) + out * 25.0
	var j3 := j2 + Vector3(0, -40, -70) + out * 20.0
	return [base, j2, j3, j3 + Vector3(0, 70, -60) + out * 90.0]


func _draw_antenna(ant: Array, wobble := 0.0) -> void:
	_poly(ant.slice(0, 3), LINE, 1.1)
	var j3: Vector3 = ant[2]
	var axis := (j3 - (ant[1] as Vector3)).normalized()
	var tip: Vector3 = j3 + ((ant[3] as Vector3) - j3).rotated(axis, wobble)
	_seg(j3, tip, HI if absf(wobble) > 0.05 else LINE, 0.7)
	for k in 5:
		var p := j3.lerp(tip, (k + 1) / 6.0)
		_seg(p, p + Vector3(0, 25, -10).rotated(axis, wobble), Color(LINE, 0.6), 0.5)


## base + the hemisphere facing the slide's camera, as chosen by SignalFlow.
func _facing(base: String) -> String:
	var side := flow.facing() if flow != null else "(R)"
	return base + side if _box(base + side).size != Vector3.ZERO else base + "(R)"


func _build(kind: String) -> Dictionary:
	match kind:
		"vision":
			# the far lobe: its outer face (and so the eye) is inside the frame; SignalFlow
			# runs the optic flow on the same side
			var la := _facing("LA")
			la = la.replace("(L)", "(#)").replace("(R)", "(L)").replace("(#)", "(R)")
			var b := _box(la)
			if b.size == Vector3.ZERO:
				return {}
			var out := Vector3(signf(b.get_center().x), 0, 0)
			var facets := []
			for iu in 7:
				for iv in 5:
					var u := lerpf(-1.0, 1.0, iu / 6.0)
					var v := lerpf(-1.0, 1.0, iv / 4.0)
					var axis := (out + Vector3(0, v * 0.8, -u * 1.0)).normalized()
					var p := b.get_center() + out * (b.size.x * 0.5 + 110.0) \
						+ Vector3(0, v * b.size.y * 0.42, -u * b.size.z * 0.42) + axis * 50.0
					facets.append([p, axis])
			return {"c": b.get_center(), "out": out, "size": b.size, "facets": facets}
		"smell", "memory", "instinct":
			if _box("AL(L)").size == Vector3.ZERO:
				return {}
			var bb := _brain_box()
			return {"ants": [_antenna("AL(L)"), _antenna("AL(R)")],
				"src": Vector3(0, bb.get_center().y + 120.0, bb.position.z - 900.0)}
		"compass":
			var eb := _box("EB")
			return {} if eb.size == Vector3.ZERO else {"c": eb.get_center(), "r": maxf(eb.size.x, 300.0) * 1.6}
		"hearing":
			# the far side, like the eye: a near-side antenna would sit under the panel
			var al := _facing("AL").replace("(L)", "(#)").replace("(R)", "(L)").replace("(#)", "(R)")
			return {} if _box(al).size == Vector3.ZERO else {"ant": _antenna(al)}
		"taste":
			var g := _box("GNG")
			if g.size == Vector3.ZERO:
				return {}
			# kept close to the GNG so they stay inside the slide's tight framing
			return {"base": Vector3(0, g.position.y + g.size.y * 0.1, g.position.z - 30.0),
				"hip": Vector3(-g.size.x * 0.45, g.position.y + g.size.y * 0.1, g.get_center().z), "s": g.size.y / 300.0}
		"gait":
			var legs := []
			for seg in ["T1", "T2", "T3"]:
				for s in ["(L)", "(R)"]:
					var b := _box("LegNp(%s)%s" % [seg, s])
					if b.size == Vector3.ZERO:
						return {}
					var out := Vector3(signf(b.get_center().x), 0, 0)
					legs.append({"name": s.substr(1, 1) + seg.substr(1), "seg": seg, "out": out,
						"exit": b.get_center() + out * b.size.x * 0.6 + Vector3(0, -b.size.y * 0.2, 0),
						"tripod": 0 if (seg == "T2") == (s == "(R)") else 1})
			return {"legs": legs}
	return {}


# --------------------------------------------------------------------------- stimuli

## An object passes in front of the eye; the facets whose optical axis points at it see it.
## Its pass is centred on the cycle start, when the photoreceptor pulses begin.
func _vision(c: float) -> void:
	var out: Vector3 = _f.out
	var size: Vector3 = _f.size
	var u := (wrapf(c, -SignalFlow.PERIOD * 0.5, SignalFlow.PERIOD * 0.5)) / (SignalFlow.PERIOD * 0.5)
	var obj: Vector3 = _f.c + out * 420.0 + Vector3(0, size.y * 0.3, u * size.z * 1.6)
	_ring(obj, 45.0, Vector3.RIGHT, Vector3.UP, LINE)
	_ring(obj, 45.0, Vector3.UP, Vector3.BACK, LINE)
	_ring(obj, 45.0, Vector3.BACK, Vector3.RIGHT, LINE)
	_label("MOVING OBJECT", obj + Vector3(0, -80, 0), HI)
	var centre := Vector3.ZERO
	for f in _f.facets:
		var p: Vector3 = f[0]
		var axis: Vector3 = f[1]
		centre += p
		var seen := clampf(1.0 - axis.angle_to(obj - p) / 0.35, 0.0, 1.0)
		var b1 := axis.cross(Vector3.UP).normalized()
		_ring(p, 16.0, b1, axis.cross(b1), HI if seen > 0.0 else Color(LINE, 0.4), 6)
		if seen > 0.0:
			_seg(obj, p, Color(HI, 0.45 * seen), 0.6)
	centre /= maxf(_f.facets.size(), 1.0)
	_label("COMPOUND EYE (not in data)", centre + out * 140.0 + Vector3(0, size.y * 0.6, 0))


## A puff of odour drifts to both antennae and arrives as the receptor neurons fire.
func _odour(c: float) -> void:
	var src: Vector3 = _f.src
	var arrive := fposmod(c + LEAD, SignalFlow.PERIOD) / LEAD        # 1 = arriving
	var name := "ODOUR"
	if _kind == "instinct":       # alternates with the panel figure
		name = "FOOD ODOUR" if int(floor(flow.time() / SignalFlow.PERIOD)) % 2 == 0 else "DANGER ODOUR (wasp)"
	_label(name, src + Vector3(0, 90, 0), HI)
	for ant in _f.ants:
		_draw_antenna(ant)
		var tip: Vector3 = ant[3]
		for i in 9:
			var u := clampf(arrive - i * 0.04, 0.0, 1.2)
			if u <= 0.0 or u > 1.0:
				continue
			var p := src.lerp(tip, u) + Vector3(sin(u * 11.0 + i) * 60.0, cos(u * 7.0 + i) * 40.0, 0) * (1.0 - u)
			_dot(p, Color(HI, 0.9), 2.4)
	var a0: Array = _f.ants[0]
	_label("ANTENNAE (not in data)", (a0[3] as Vector3) + Vector3(0, 120, 0))
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


## Courtship song: pulses of sound arrive at the antenna and shake the arista at cycle start.
func _hearing(c: float) -> void:
	var ant: Array = _f.ant
	var src: Vector3 = (ant[3] as Vector3) + Vector3(0, 60, -600)
	var arrive := fposmod(c + LEAD, SignalFlow.PERIOD) / LEAD
	for k in 3:
		var u := arrive - k * 0.15
		if u > 0.0 and u <= 1.0:
			_ring(src.lerp(ant[2], u), 30.0 + 120.0 * u, Vector3.RIGHT, Vector3.UP, Color(HI, 1.0 - u * 0.6), 20, -0.9, 0.9)
	var shake := exp(-c * 2.5) * 0.4
	_draw_antenna(ant, sin(flow.time() * 30.0) * shake)
	_label("COURTSHIP SONG", src + Vector3(0, 120, 0), HI)
	_label("ANTENNA (not in data)", (ant[3] as Vector3) + Vector3(0, 110, 0))


## A front leg steps on sugar (the leg taste neurons fire at cycle start); once the signal has
## reached the proboscis motor neurons, the proboscis extends.
func _taste(c: float) -> void:
	var k: float = _f.s
	var hip: Vector3 = _f.hip
	var foot := hip + Vector3(-60, -210, -130) * k
	_poly([hip, hip + Vector3(-40, -80, -30) * k, foot], LINE, 1.4)
	var touch := exp(-c * 1.5)
	_ring(foot + Vector3(0, -10, 0) * k, 13.0 * k, Vector3.RIGHT, Vector3.BACK, Color(HI, 0.5 + 0.5 * touch), 14)
	_label("SUGAR", foot + Vector3(0, -40, 0) * k, HI, 18)
	_label("FRONT LEG (not in data)", foot + Vector3(-30, 30, -60) * k)
	var ext := smoothstep(2.0, 2.8, c) * (1.0 - smoothstep(4.6, 5.4, c))
	var base: Vector3 = _f.base
	var knee := base + Vector3(0, -70, -30).lerp(Vector3(0, -80, -75), ext) * k
	var tip := knee + Vector3(0, -20, 60).lerp(Vector3(0, -75, -20), ext) * k
	_poly([base, knee, tip], HI if ext > 0.1 else LINE, 1.6)
	_ring(tip, 18.0 * k, Vector3.RIGHT, Vector3.BACK, HI if ext > 0.1 else LINE, 16)
	_label("PROBOSCIS (not in data)" + (" — extends" if ext > 0.1 else ""), tip + Vector3(0, -45, 0) * k, HI if ext > 0.1 else LABEL)


## The six legs, swinging and pushing in step with their motor neurons' tripods.
func _gait(c: float) -> void:
	var half := SignalFlow.PERIOD * 0.5
	var stance_tripod := 0 if c < half else 1
	var local := fmod(c, half) / half
	for leg in _f.legs:
		var out: Vector3 = leg.out
		var stance: bool = leg.tripod == stance_tripod
		var swing := 0.0 if stance else sin(local * PI)
		# short stubs, not to scale: real legs are several times the nerve cord's length and
		# would sweep across the whole view
		var fore := (-1.0 if leg.seg == "T1" else (1.0 if leg.seg == "T3" else 0.0)) * 50.0
		var sweep := lerpf(-35.0, 35.0, local) * (1.0 if stance else -1.0)
		var e: Vector3 = leg.exit
		# mostly downward: sideways legs point at the camera on this view and blow up in size
		var knee := e + out * 60.0 + Vector3(0, -40 + 20 * swing, fore * 0.4)
		var foot := e + out * 85.0 + Vector3(0, -170 + 45 * swing, fore + sweep)
		_poly([e, knee, foot], Color(LINE, 0.85), 1.2)
		if stance:
			_ring(foot, 10.0, Vector3.RIGHT, Vector3.BACK, HI, 10)
		_label(leg.name, foot + out * 25.0, HI if stance else Color(0.6, 0.6, 0.6), 16)
	var any: Dictionary = _f.legs[0]
	var mid := Vector3(0, (any.exit as Vector3).y, (any.exit as Vector3).z)
	_label("LEGS (not in data, not to scale) — ring = foot down", mid + Vector3(0, -220, 0))
