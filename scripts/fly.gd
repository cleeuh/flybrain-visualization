class_name Fly
extends Node3D
## A stylised whole fly, built procedurally, for the opening slide of the tour.
##
## The connectome data is nervous system only — there is no body mesh — so this draws one
## around it: head, eyes, thorax, abdomen, wings, halteres and legs as scaled spheres and
## cylinders in the same additive "glass" shader as the brain shells. It is laid out in the
## data's own coordinates (micrometres, -Z anterior) so the brain sits inside the head and
## the ventral nerve cord inside the thorax, which is what makes the fade on slide 2 read as
## "the body dissolves and leaves the nervous system behind".
##
## `flying` hovers the whole animal on a lazy figure-of-eight and flaps the wings; turning it
## off eases the body back to the rest pose the CNS is aligned with.

const BODY := Color(1.0, 0.72, 0.38, 1.0)
const EYE := Color(1.0, 0.25, 0.18, 1.0)
const WING := Color(0.62, 0.80, 1.0, 1.0)

const FLAP_HZ := 7.0          ## visual flap rate (a real fly's 200 Hz just aliases)
const WANDER := 130.0         ## µm of hover drift

## Hovering on / off. Off eases the body back to rest, where it lines up with the CNS.
var flying := false

var _mats: Array[ShaderMaterial] = []
var _base_alpha := {}         # material -> alpha at full opacity
var _wings: Array[Node3D] = []
var _body: Node3D
var _t := 0.0
var _rest_box := AABB()       ## bounds of the whole animal in the rest pose
var _ease := 0.0              ## 0 at rest, 1 fully into the hover


func _ready() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)

	# Head, thorax and abdomen along -Z (anterior), so the brain lands inside the head and
	# the ventral nerve cord inside the thorax.
	_part(Vector3(0, 55, -560), Vector3(258, 238, 215), BODY, 0.035)         # head
	_part(Vector3(-200, 75, -600), Vector3(155, 185, 155), EYE, 0.07)        # compound eyes
	_part(Vector3(200, 75, -600), Vector3(155, 185, 155), EYE, 0.07)
	_part(Vector3(0, -140, -650), Vector3(75, 115, 80), BODY, 0.06)          # proboscis
	_part(Vector3(-75, -30, -740), Vector3(35, 55, 75), BODY, 0.06)          # antennae
	_part(Vector3(75, -30, -740), Vector3(35, 55, 75), BODY, 0.06)
	_part(Vector3(0, -45, 150), Vector3(330, 315, 380), BODY, 0.025)         # thorax
	_part(Vector3(0, -95, 760), Vector3(265, 245, 340), BODY, 0.025)         # abdomen, tapering
	_part(Vector3(0, -110, 1070), Vector3(205, 190, 265), BODY, 0.025)
	_part(Vector3(0, -120, 1300), Vector3(125, 115, 165), BODY, 0.025)
	_part(Vector3(-190, -140, 430), Vector3(45, 45, 55), BODY, 0.06)         # halteres
	_part(Vector3(190, -140, 430), Vector3(45, 45, 55), BODY, 0.06)

	# wings, on pivots at the top of the thorax so they can flap
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 70, 200, 90)
		_body.add_child(pivot)
		var wing := _part(Vector3(side * 430, 20, 640), Vector3(330, 14, 700), WING, 0.03, pivot)
		wing.rotation_degrees = Vector3(0, side * -14, 0)
		_wings.append(pivot)

	# three pairs of legs: coxa -> knee -> tarsus, splayed forward, out and back
	var legs := [
		[Vector3(215, -230, -130), Vector3(450, -560, -430), Vector3(520, -790, -230)],
		[Vector3(260, -240, 140), Vector3(540, -590, 130), Vector3(600, -820, 340)],
		[Vector3(250, -230, 390), Vector3(560, -560, 630), Vector3(630, -800, 900)],
	]
	for leg in legs:
		for side in [-1.0, 1.0]:
			var m := Vector3(side, 1, 1)
			_limb(leg[0] * m, leg[1] * m, 34.0, 22.0)
			_limb(leg[1] * m, leg[2] * m, 22.0, 10.0)

	set_alpha(0.0)


## One scaled sphere. `fill` is the shell shader's flat term; the rest is the fresnel rim.
func _part(pos: Vector3, radii: Vector3, color: Color, fill: float, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	mi.mesh = sphere
	mi.transform = Transform3D(Basis.IDENTITY.scaled(radii), pos)
	mi.material_override = _material(color, fill)
	var holder: Node3D = parent if parent != null else _body
	holder.add_child(mi)
	_grow((holder.transform if parent != null else Transform3D.IDENTITY) * mi.transform, mi.mesh)
	return mi


## A tapered cylinder from `a` to `b` — one leg segment.
func _limb(a: Vector3, b: Vector3, r_start: float, r_end: float) -> void:
	var span := b - a
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = r_start
	cyl.bottom_radius = r_end
	cyl.height = span.length()
	cyl.radial_segments = 8
	cyl.rings = 1
	mi.mesh = cyl
	# the mesh runs along +Y from its centre, so rotate +Y onto the segment
	var basis := Basis(Quaternion(Vector3.UP, -span.normalized()))
	mi.transform = Transform3D(basis, a + span * 0.5)
	mi.material_override = _material(BODY, 0.05)
	_body.add_child(mi)
	_grow(mi.transform, mi.mesh)


func _grow(xf: Transform3D, mesh: Mesh) -> void:
	var box := xf * mesh.get_aabb()
	_rest_box = box if _rest_box.size == Vector3.ZERO else _rest_box.merge(box)


## Bounds of the fly in its rest pose, for the tour's framing (the hover must not resize it).
func rest_aabb() -> AABB:
	return _rest_box


func _material(color: Color, fill: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/shell.gdshader")
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("fill", fill)
	m.set_shader_parameter("rim", 0.65)
	_mats.append(m)
	_base_alpha[m] = color.a
	return m


## 0 = fully transparent (and hidden), 1 = as built.
func set_alpha(a: float) -> void:
	for m in _mats:
		var c: Color = m.get_shader_parameter("color")
		c.a = _base_alpha[m] * a
		m.set_shader_parameter("color", c)
	visible = a > 0.001


func alpha() -> float:
	if _mats.is_empty():
		return 0.0
	var c: Color = _mats[0].get_shader_parameter("color")
	return c.a / maxf(_base_alpha[_mats[0]], 0.001)


func _process(dt: float) -> void:
	if not visible:
		return
	_ease = move_toward(_ease, 1.0 if flying else 0.0, dt * 1.2)
	if _ease <= 0.0:
		_body.transform = Transform3D.IDENTITY
		return
	_t += dt
	var drift := Vector3(sin(_t * 0.7) * WANDER, sin(_t * 1.27) * WANDER * 0.55,
		cos(_t * 0.52) * WANDER * 0.8) * _ease
	var tilt := Basis.from_euler(Vector3(deg_to_rad(sin(_t * 1.1) * 5.0 * _ease),
		deg_to_rad(sin(_t * 0.6) * 14.0 * _ease), deg_to_rad(sin(_t * 0.9) * 9.0 * _ease)))
	_body.transform = Transform3D(tilt, drift)
	var flap := sin(_t * TAU * FLAP_HZ) * 38.0 * _ease
	for i in _wings.size():
		var side := -1.0 if i == 0 else 1.0
		_wings[i].rotation_degrees = Vector3(0, 0, side * flap)
