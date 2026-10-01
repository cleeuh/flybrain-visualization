class_name SignalFlow
extends Node
## Slide illustrations drawn on the real connectome: for each region slide, real neurons of the
## cell types that do the job are picked from the data, and pulses run along their actual
## branches, starting where each neuron receives its input — so activity visibly hands off
## through the circuit the slide describes (photoreceptors -> lamina -> medulla -> T4 / T5 and
## lobula columns; receptor neurons -> projection neurons; …).
##
## A stage = cell types (regex on the type name) + where their signal enters + a delay. The
## timing is illustrative (slowed so it can be followed), not measured; the panel's
## illustration caption says so. Everything not in the flow is dimmed.

const PERIOD := 6.0          ## s per cycle of the whole hand-off
const SPEED := 450.0         ## µm / s along the branches
const FADE := 0.8

## kind -> stages: [type regex, entry, delay s, max neurons, side]
##   entry: "roi:NAME" (NAME may hold {S} = the slide's facing side, or list "A|B" = nearest of)
##          "anterior" / "posterior" / "lateral" = the neuron's extreme point in that direction
##   side:  "facing" (the hemisphere facing the camera), "both"
const STAGES := {
	"vision": [
		["^R1-R6$|^R7|^R8", "lateral", 0.0, 10, "facing"],
		["^L[1-3]$", "roi:LA{S}", 0.5, 10, "facing"],
		["^Mi1$|^Tm[1-3]$|^Mi4$|^Mi9$", "roi:ME{S}", 1.1, 12, "facing"],
		["^T4[a-d]$", "roi:ME{S}", 1.7, 8, "facing"],
		["^T5[a-d]$", "roi:LO{S}", 1.7, 8, "facing"],
		["^LC1[0-2]|^LPLC2$", "roi:LO{S}", 2.3, 6, "facing"],
		["^LPT|^LLPC", "roi:LOP{S}", 2.4, 5, "facing"],
	],
	"smell": [
		["^ORN_", "anterior", 0.0, 18, "both"],
		["^(?!WEDPN).*PN", "roi:AL(L)|AL(R)", 1.0, 14, "both"],
	],
	"memory": [
		["^(?!WEDPN).*PN", "roi:AL(L)|AL(R)", 0.0, 8, "both"],
		["^KC", "roi:CA{S}", 1.0, 16, "facing"],
		["^MBON", "roi:aL{S}|bL{S}|gL{S}|a'L{S}|b'L{S}", 2.2, 5, "both"],
		["^PAM", "roi:CRE{S}|SMP{S}", 2.0, 6, "both"],
	],
	"instinct": [
		["^(?!WEDPN).*PN", "roi:AL(L)|AL(R)", 0.0, 10, "both"],
		["^LH", "roi:LH(L)|LH(R)", 1.1, 14, "both"],
	],
	"compass": [
		["^ER", "roi:BU(L)|BU(R)", 0.0, 6, "both"],
		["^EPG$", "roi:EB", 0.7, 4, "both"],
		["^PFN", "roi:PB", 1.3, 8, "both"],
		["^hDelta|^vDelta", "roi:FB", 1.9, 8, "both"],
	],
	"hearing": [
		["^JO-", "anterior", 0.0, 14, "both"],
		["^AMMC", "roi:AMMC(L)|AMMC(R)", 0.8, 6, "both"],
		["^WED|^SAD", "roi:AMMC(L)|AMMC(R)|WED(L)|WED(R)", 1.4, 10, "both"],
	],
	"taste": [
		["^LgLG", "posterior", 0.0, 12, "both"],
		["^GNG", "roi:GNG", 0.9, 8, "both"],
		["^MN\\d", "roi:GNG", 1.6, 10, "both"],
	],
	"descend": [
		["^DN", "anterior", 0.0, 18, "both"],
		["^AN", "posterior", 0.6, 12, "both"],
	],
}

var neurons: Neurons
var sim: Sim
var rois: Dictionary = {}        ## ROI name -> MeshInstance3D

var _kind := ""
var _strength := 0.0
var _target := 0.0
var _t := 0.0
var _centres := {}


## Set up the flow for `slide` (its "illus" kind); kinds without stages clear it.
func show_slide(slide: Dictionary) -> void:
	var kind: String = slide.get("illus", "")
	if kind == _kind:
		return
	_kind = kind
	_t = 0.0
	var delays := {}
	if kind == "gait":
		delays = _build_gait()
	elif STAGES.has(kind):
		delays = _build(STAGES[kind], deg_to_rad(float(slide.get("yaw", 0.0))))
	neurons.set_flow(delays)
	_target = 1.0 if not delays.is_empty() else 0.0


## True while a slide's flow is showing (the random stimulation pauses meanwhile).
func active() -> bool:
	return _target > 0.0


func _process(dt: float) -> void:
	if neurons == null:
		return
	_strength = move_toward(_strength, _target, dt / FADE)
	_t += dt
	neurons.set_flow_params(_strength, _t, PERIOD, SPEED)


# --------------------------------------------------------------------------- building

func _build(stages: Array, yaw: float) -> Dictionary:
	var facing := _facing_suffix(yaw)
	var delays := {}
	for st in stages:
		var re := RegEx.create_from_string(st[0])
		var picked := 0
		for i in neurons.index.size():
			if picked >= int(st[3]):
				break
			var n: Dictionary = neurons.index[i]
			var type = n.get("type")
			if type == null or re.search(String(type)) == null:
				continue
			if st[4] == "facing" and not _on_side(i, facing):
				continue
			var entry := String(st[1]).replace("{S}", facing)
			if _route(i, entry):
				delays[i] = float(st[2])
				picked += 1
	return delays


## Tripod gait: leg motor neurons of L1, R2, L3 fire together, then R1, L2, R3 half a cycle
## later. Which leg a motor neuron drives comes from the leg neuropil holding its synapses.
func _build_gait() -> Dictionary:
	var delays := {}
	if sim == null or not sim.loaded:
		return delays
	var leg_rois := {}
	for r in sim.regions:
		var name: String = r.name
		if name.begins_with("LegNp("):
			leg_rois[int(r.id)] = name
	var per_leg := {}
	for i in neurons.index.size():
		if String(neurons.groups[int(neurons.index[i].group)].name) != "vnc_motor":
			continue
		var best := ""
		var most := 0
		for pair in sim.membership[i]:
			var rid := int(pair[0])
			if leg_rois.has(rid) and int(pair[1]) > most:
				most = int(pair[1])
				best = leg_rois[rid]
		if best == "" or int(per_leg.get(best, 0)) >= 4:
			continue
		var tripod_a := best in ["LegNp(T1)(L)", "LegNp(T2)(R)", "LegNp(T3)(L)"]
		if _route(i, "roi:" + best):
			delays[i] = 0.0 if tripod_a else PERIOD * 0.5
			per_leg[best] = int(per_leg.get(best, 0)) + 1
	return delays


## Compute neuron i's path distances from its entry point; false if the entry can't be found.
func _route(i: int, entry: String) -> bool:
	var seg := neurons.segments_of(i)
	var k := seg.size() / 2
	if k == 0:
		return false
	# the skeleton is a tree whose segments share endpoints; the file stores start + direction,
	# so an end recomputed from them differs from the next start by float rounding — match
	# endpoints on a 0.01 µm grid
	var node_of := {}
	var nodes := PackedVector3Array()
	var ends := PackedInt32Array()
	ends.resize(k * 2)
	for s in k * 2:
		var p := seg[s]
		var key := Vector3i((p * 100.0).round())
		var id: int = node_of.get(key, -1)
		if id < 0:
			id = nodes.size()
			node_of[key] = id
			nodes.append(p)
		ends[s] = id
	var adj := []
	adj.resize(nodes.size())
	for n in nodes.size():
		adj[n] = []
	for s in k:
		adj[ends[s * 2]].append(s)
		adj[ends[s * 2 + 1]].append(s)
	# entry node
	var target: Variant = _entry_point(entry, nodes)
	if target == null:
		return false
	var start := 0
	var bd := INF
	for n in nodes.size():
		var d: float
		match entry:
			"anterior": d = nodes[n].z
			"posterior": d = -nodes[n].z
			"lateral": d = -absf(nodes[n].x)
			_: d = nodes[n].distance_squared_to(target)
		if d < bd:
			bd = d
			start = n
	# distances along the tree from the entry node
	var dist_node := PackedFloat32Array()
	dist_node.resize(nodes.size())
	dist_node.fill(-1.0)
	dist_node[start] = 0.0
	var stack := [start]
	var seg_dist := PackedFloat32Array()
	seg_dist.resize(k)
	while not stack.is_empty():
		var n: int = stack.pop_back()
		for s in adj[n]:
			var other := ends[s * 2] if ends[s * 2 + 1] == n else ends[s * 2 + 1]
			if dist_node[other] >= 0.0:
				continue
			dist_node[other] = dist_node[n] + nodes[n].distance_to(nodes[other])
			seg_dist[s] = dist_node[n]
			stack.push_back(other)
	neurons.set_path_distance(i, seg, seg_dist)
	return true


## A point the entry rule refers to (the ROI centre), or Vector3.ZERO for directional rules.
func _entry_point(entry: String, _nodes: PackedVector3Array) -> Variant:
	if not entry.begins_with("roi:"):
		return Vector3.ZERO
	var names := entry.substr(4).split("|")
	var found := []
	for n in names:
		if rois.has(n):
			found.append(_centre(n))
	if found.is_empty():
		return null
	if found.size() == 1:
		return found[0]
	# several candidates (either hemisphere, or a set of lobes): the neuron picks its nearest,
	# approximated by the candidate nearest its first node
	var p0: Vector3 = _nodes[0]
	var best: Vector3 = found[0]
	for c in found:
		if p0.distance_squared_to(c) < p0.distance_squared_to(best):
			best = c
	return best


func _centre(name: String) -> Vector3:
	if not _centres.has(name):
		var mi: MeshInstance3D = rois[name]
		_centres[name] = mi.global_transform * mi.mesh.get_aabb().get_center()
	return _centres[name]


## "(L)" or "(R)": the hemisphere facing a camera at `yaw` (decided from ROI positions, since
## the data's left may be either sign of X).
func _facing_suffix(yaw: float) -> String:
	var want := signf(sin(yaw)) if absf(sin(yaw)) > 0.05 else 1.0
	if rois.has("LA(L)") and signf(_centre("LA(L)").x) == want:
		return "(L)"
	return "(R)"


func _on_side(i: int, suffix: String) -> bool:
	var side := int(neurons.index[i].side)          # 0 = L, 1 = R, 2 = midline, 3 = unknown
	return side >= 2 or (side == 0) == (suffix == "(L)")
