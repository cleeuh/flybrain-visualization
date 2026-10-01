class_name Fly
extends Node3D
## The whole fly for the opening slide of the tour.
##
## The connectome data is nervous system only, so the body comes from flybody (Vaxenburg et al.
## 2024, TuragaLab/flybody, Apache-2.0; see THIRD_PARTY_NOTICES.md), converted by
## tools/fetch_fly_body.py into data/meshes/fly/*.bmesh + data/fly.json, already placed in the data's own
## coordinates (micrometres, -Z anterior) with the brain inside the head. The body is drawn
## solid (shaders/fly.gdshader) so its anatomy reads, and dissolves on slide 2 to leave the
## nervous system behind; only the wing membranes are translucent (shaders/fly_glass.gdshader,
## depth-tested so the body hides them).
##
## The model is rigged from flybody's own body tree (67 segments). `flying` hovers the animal on
## a lazy figure-of-eight, flaps the wings about their hinges, tucks the legs into the flight
## posture (where they drift slowly, each on its own timing), twitches the antennae,
## pumps the abdomen and beats the halteres; turning it off eases everything back to the rest
## pose the CNS is aligned with.

const BODY := Color(1.0, 0.72, 0.38, 1.0)
const EYE := Color(1.0, 0.25, 0.18, 1.0)
const WING := Color(0.62, 0.80, 1.0, 1.0)

const FLAP_HZ := 7.0          ## visual flap rate (a real fly's 200 Hz just aliases)
const WANDER := 130.0         ## µm of hover drift
## Flight posture, [abduct (Z), twist (Y), extend (X)] in radians per flybody segment, from
## FlyGym's flybody flight pose (NeLy-EPFL/flygym, Apache-2.0): front legs folded up under the
## head, middle legs rolled in, hind legs trailing, proboscis retracted. Both sides use the same
## values; the model's mirrored joint frames make them symmetric.
const FLIGHT_POSE := {
	"coxa_T1": [0.0, 0.0, 0.0584], "femur_T1": [0.0, 0.0, -0.142],
	"tibia_T1": [0.0, 0.0, -1.29], "tarsus_T1": [0.0, 0.0, -0.242],
	"coxa_T2": [-0.292, -0.742, 0.408], "femur_T2": [0.0, 0.608, 0.208],
	"tibia_T2": [0.0, 0.0, -1.34], "tarsus_T2": [0.0, 0.0, 0.608],
	"coxa_T3": [0.0, 0.00841, 0.158], "femur_T3": [0.0, 0.558, 0.258],
	"tibia_T3": [0.0, 0.0, -0.292], "tarsus_T3": [0.0, 0.0, 0.258],
	"rostrum": [0.0, 0.0, 0.8], "haustellum": [0.0, 0.0, 0.8],
}
## Amplitude (radians) of each leg segment's slow drift around the flight posture.
const LEG_DRIFT := {"coxa": 0.04, "femur": 0.07, "tibia": 0.09, "tarsus_": 0.07}
## Per-leg timing offsets, so no two legs move together.
const LEG_PHASE := {"T1_left": 0.0, "T1_right": 2.1, "T2_left": 4.3, "T2_right": 1.2, "T3_left": 3.4, "T3_right": 5.5}

## Hovering on / off. Off eases the body back to rest, where it lines up with the CNS.
var flying := false

var _mats: Array[ShaderMaterial] = []
var _base_alpha := {}         # material -> alpha at full opacity
var _mat_part := {}           # material -> "body:kind" (e.g. "antenna_left:body", "head:eyes")
var _alpha := 0.0             ## whole-fly opacity (the tour's fly slides)
var _parts: Array = []        ## part filters shown on their own (see show_parts)
var _parts_alpha := 0.0
var _overrides := {}          ## body name -> [abduct, twist, extend] at rest (see set_part_pose)
var _nodes := {}              ## body name -> Node3D
var _part_mesh := {}          ## "body:kind" -> Mesh
var _inst: Array[Dictionary] = []   ## {mi, solid, glass, tag}: parts are shown as glass
var _body: Node3D
var _t := 0.0
var _rest_box := AABB()       ## bounds of the whole animal in the rest pose
var _ease := 0.0              ## 0 at rest, 1 fully into the hover
var _joints: Array[Dictionary] = []   ## {node, rest (local), name}
var _wings: Array[Dictionary] = []    ## {node, rest_world, parent_inv, side}


func _ready() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var meta = JSON.parse_string(FileAccess.get_file_as_string("res://data/fly.json"))
	if meta == null:
		push_warning("Fly: data/fly.json missing (run tools/fetch_fly_body.py) — no fly")
		return
	# the MJCF body tree: every node's rest transform is stored in body space; parents come first
	var nodes := {}
	var world := {}
	for b in meta.bodies:
		var bs: Array = b.basis
		var o: Array = b.origin
		var w := Transform3D(Basis(Vector3(bs[0][0], bs[0][1], bs[0][2]), Vector3(bs[1][0], bs[1][1], bs[1][2]),
			Vector3(bs[2][0], bs[2][1], bs[2][2])), Vector3(o[0], o[1], o[2]))
		var parent: Node3D = nodes.get(b.parent, _body)
		var parent_w: Transform3D = world.get(b.parent, Transform3D.IDENTITY)
		var n := Node3D.new()
		n.name = b.name
		n.transform = parent_w.affine_inverse() * w
		parent.add_child(n)
		nodes[b.name] = n
		world[b.name] = w
		_nodes[b.name] = n
		for m in b.meshes:
			_part(m.file, m.kind, n, w, "%s:%s" % [b.name, m.kind])
		var name: String = b.name
		if name.begins_with("wing_"):
			_wings.append({"node": n, "rest_world": w, "parent_inv": parent_w.affine_inverse(),
				"side": signf(w.origin.x)})             # flap direction follows which side it is on
		elif b.parent != "":
			var key := name.trim_suffix("_left").trim_suffix("_right")
			_joints.append({"node": n, "rest": n.transform, "name": name, "pose": FLIGHT_POSE.get(key, [0.0, 0.0, 0.0])})
	set_alpha(0.0)


## One converted mesh on body node `parent` (rest pose `rest` in body space).
func _part(file: String, kind: String, parent: Node3D, rest: Transform3D, tag: String) -> void:
	var mesh := BMesh.load("res://data/meshes/%s" % file)
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	match kind:
		"eyes": mi.material_override = _material(EYE, false)
		"membrane": mi.material_override = _material(WING, true)
		"veins": mi.material_override = _material(WING, false)
		_: mi.material_override = _material(BODY, false)
	_mat_part[mi.material_override] = tag
	_part_mesh[tag] = mesh
	# shown on its own (show_parts) a part is drawn as translucent glass like the brain shells,
	# so it gives the anatomy's shape without covering the neurons
	var glass := ShaderMaterial.new()
	glass.shader = load("res://shaders/fly_glass.gdshader")
	var gc: Color = (mi.material_override as ShaderMaterial).get_shader_parameter("color")
	glass.set_shader_parameter("color", Color(gc, 0.0))
	glass.set_shader_parameter("fill", 0.03)
	glass.set_shader_parameter("rim", 0.7)
	_inst.append({"mi": mi, "solid": mi.material_override, "glass": glass, "tag": tag})
	parent.add_child(mi)
	_grow(rest, mesh)


func _grow(xf: Transform3D, mesh: Mesh) -> void:
	var box := xf * mesh.get_aabb()
	_rest_box = box if _rest_box.size == Vector3.ZERO else _rest_box.merge(box)


## Bounds of the fly in its rest pose, for the tour's framing (the hover must not resize it).
func rest_aabb() -> AABB:
	return _rest_box


## Solid (shaders/fly.gdshader), or depth-tested translucent glass for the wing membranes.
func _material(color: Color, glass: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/fly_glass.gdshader" if glass else "res://shaders/fly.gdshader")
	m.set_shader_parameter("color", color)
	_mats.append(m)
	_base_alpha[m] = color.a
	return m


## 0 = fully transparent (and hidden), 1 = as built.
func set_alpha(a: float) -> void:
	_alpha = a
	_apply_alpha()


func alpha() -> float:
	return _alpha


## Show only some body parts, at opacity `a`, independently of the whole-fly fade — the slides
## use this to put the real eyes, antennae, proboscis or legs next to the brain. A filter
## matches a body name prefix ("antenna", "coxa_T1"), optionally with a kind ("head:eyes").
func show_parts(filters: Array, a: float) -> void:
	if filters == _parts and absf(a - _parts_alpha) < 0.002:
		return                      # called every frame; only re-apply on a real change
	_parts = filters
	_parts_alpha = a
	_apply_alpha()


## Rest-pose joint angles [abduct (Z), twist (Y), extend (X)] per body, used while the fly is
## not hovering; bodies not listed sit at rest. Called every frame by an animation.
func set_part_pose(poses: Dictionary) -> void:
	_overrides = poses


## World position of a point on a part: its mesh's bounds centre, or (tip) the bounds corner
## farthest from the body's joint.
func part_point(tag: String, tip := false) -> Vector3:
	var body := tag.get_slice(":", 0)
	var n: Node3D = _nodes.get(body)
	var mesh: Mesh = _part_mesh.get(tag if tag.contains(":") else tag + ":body")
	if n == null or mesh == null:
		return Vector3.ZERO
	var box := mesh.get_aabb()
	if not tip:
		return n.global_transform * box.get_center()
	var best := box.get_center()
	for i in 8:
		var c := box.get_endpoint(i)
		if c.length_squared() > best.length_squared():
			best = c
	return n.global_transform * best


## World-space vertices of a part (e.g. "head:eyes"), for aiming stimuli at its surface.
func part_vertices(tag: String) -> PackedVector3Array:
	var body := tag.get_slice(":", 0)
	var n: Node3D = _nodes.get(body)
	var mesh: Mesh = _part_mesh.get(tag)
	var out := PackedVector3Array()
	if n == null or mesh == null:
		return out
	var xf := n.global_transform
	for v in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		out.append(xf * v)
	return out


func _apply_alpha() -> void:
	var any := false
	for it in _inst:
		var mi: MeshInstance3D = it.mi
		var solid: ShaderMaterial = it.solid
		var glass: ShaderMaterial = it.glass
		if _alpha > 0.001:
			if mi.material_override != solid:
				mi.material_override = solid
			var c: Color = solid.get_shader_parameter("color")
			c.a = _base_alpha[solid] * _alpha
			solid.set_shader_parameter("color", c)
			mi.visible = true
		elif _parts_alpha > 0.001 and _matches(it.tag):
			if mi.material_override != glass:
				mi.material_override = glass
			var g: Color = glass.get_shader_parameter("color")
			g.a = _parts_alpha
			glass.set_shader_parameter("color", g)
			mi.visible = true
		else:
			mi.visible = false
		any = any or mi.visible
	visible = any


func _matches(tag: String) -> bool:
	for f in _parts:
		var fs := String(f)
		if fs.contains(":"):
			if tag == fs or (tag.begins_with(fs.get_slice(":", 0)) and tag.ends_with(":" + fs.get_slice(":", 1))):
				return true
		elif tag.begins_with(fs) and not tag.ends_with(":eyes"):
			return true
	return false


func _process(dt: float) -> void:
	if not visible:
		return
	_ease = move_toward(_ease, 1.0 if flying else 0.0, dt * 1.2)
	if _ease <= 0.0:
		_body.transform = Transform3D.IDENTITY
		for j in _joints:
			var o: Array = _overrides.get(j.name, [])
			if o.is_empty():
				j.node.transform = j.rest
			else:
				var b := Basis(Vector3.BACK, o[0]) * Basis(Vector3.UP, o[1]) * Basis(Vector3.RIGHT, o[2])
				j.node.transform = j.rest * Transform3D(b, Vector3.ZERO)
		for w in _wings:
			w.node.transform = w.parent_inv * w.rest_world
		return
	_t += dt
	var e := _ease
	var drift := Vector3(sin(_t * 0.7) * WANDER, sin(_t * 1.27) * WANDER * 0.55,
		cos(_t * 0.52) * WANDER * 0.8) * e

	var tilt := Basis.from_euler(Vector3(deg_to_rad(sin(_t * 1.1) * 5.0 * e),
		deg_to_rad(sin(_t * 0.6) * 14.0 * e), deg_to_rad(sin(_t * 0.9) * 9.0 * e)))
	_body.transform = Transform3D(tilt, drift)

	# wings flap about the body's long axis through their hinge
	var flap := sin(_t * TAU * FLAP_HZ) * deg_to_rad(38.0) * e
	for w in _wings:
		var rw: Transform3D = w.rest_world
		var about := Transform3D(Basis(Vector3.BACK, w.side * flap), Vector3.ZERO)
		var world := Transform3D(Basis.IDENTITY, rw.origin) * about * Transform3D(Basis.IDENTITY, -rw.origin) * rw
		w.node.transform = w.parent_inv * world

	# flight posture, eased in, plus the segment's own motion about its bend axis (local X);
	# abduct / twist / extend compose in the MJCF joint order Z, Y, X
	for j in _joints:
		var p: Array = j.pose
		var extend: float = p[2] + _joint_angle(j.name)
		var b := Basis(Vector3.BACK, p[0] * e) * Basis(Vector3.UP, p[1] * e) * Basis(Vector3.RIGHT, extend * e)
		j.node.transform = j.rest * Transform3D(b, Vector3.ZERO)


## Motion of one body segment on top of its flight posture (radians about local X).
func _joint_angle(name: String) -> float:
	# legs: a slow, small drift around the tucked pose, each leg on its own timing, the
	# distal segments trailing the proximal ones so the leg moves as one limb
	for k in LEG_DRIFT:
		if name.begins_with(k):
			var leg := name.substr(name.find("_T") + 1)
			var ph: float = LEG_PHASE.get(leg, 0.0)
			var lag := 0.5 if k == "tibia" or k == "tarsus_" else 0.0
			var t := _t + ph
			return LEG_DRIFT[k] * (0.7 * sin(t * 1.1 - lag) + 0.3 * sin(t * 2.3 + ph - lag))
	if name.begins_with("antenna"):
		var side := 0.0 if name.ends_with("left") else 1.7
		return 0.12 + 0.12 * sin(_t * TAU * 0.8 + side) + 0.05 * sin(_t * TAU * 2.3 + side * 2.0)
	if name == "head":
		return 0.06 * sin(_t * TAU * 0.35)
	if name.begins_with("abdomen"):
		var i := name.trim_prefix("abdomen").trim_prefix("_").to_int()
		return -0.025 + 0.035 * sin(_t * TAU * 0.6 - i * 0.4)
	if name.begins_with("haltere"):
		return 0.18 * sin(_t * TAU * FLAP_HZ + PI)  # beat in antiphase to the wings
	return 0.0
