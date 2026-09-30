class_name Sim
extends Node
## Spreading-activation simulation over the rendered subgraph of the connectome.
##
## Leaky integrate-and-fire on synapse-count-weighted edges (data/edges.bin), with the
## presynaptic neuron's predicted neurotransmitter setting the sign (ACh +, GABA/Glu/His -).
## Activity is written into a 1-D float texture indexed by neuron id for the ribbon shader.
## Stimulus targets are neuropil regions (geometric membership) or neuron superclasses.


const TICK_HZ := 5.0             # slow enough to follow a wave as it spreads
## At most this fraction of neurons fires per tick; the rest of an over-threshold burst is
## suppressed, so a pulse never floods the view with flashes (uncapped bursts reach ~12 %).
const MAX_FIRE_FRAC := 0.012
## The auto demo waits for the previous wave to die down before the next pulse.
const DEMO_QUIET_FRAC := 0.002
var leak := 0.4                # membrane potential retained per tick
var threshold := 1.0
var refractory := 4
var adapt_step := 1.0           # per-spike threshold increase (spike-frequency adaptation)
var adapt_decay := 0.92
var homeostasis := 15.0         # global threshold gain vs. fraction of neurons firing
const ACT_DECAY := 0.78
var w_scale := 24.0             # synapses for a "full strength" input
const STIM_DRIVE := 0.7
const MIN_TARGET_MEMBERS := 15

var n := 0
var regions: Array = []
var membership: Array = []
var nt_sign := PackedFloat32Array()
var row_start := PackedInt32Array()
var col := PackedInt32Array()
var wgt := PackedFloat32Array()

# targets: [{name, kind, members: PackedInt32Array}]
var targets: Array = []
var target_idx := 0
var auto_demo := false
var _auto_timer := 0.0

var v := PackedFloat32Array()
var act := PackedFloat32Array()
var refr := PackedInt32Array()
var adapt := PackedFloat32Array()
var fired := PackedInt32Array()
var spikes_per_s := 0.0
var _acc := 0.0
var _pending_pulse := false

var texture: ImageTexture
var _img: Image
var loaded := false


func load_data(neurons: Neurons, json_path := "res://data/sim.json", edges_path := "res://data/edges.bin") -> bool:
	var meta = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	var f := FileAccess.open(edges_path, FileAccess.READ)
	if meta == null or f == null:
		push_warning("Sim: data/sim.json or data/edges.bin missing (run tools/build_sim.py) — simulation disabled")
		return false
	n = neurons.index.size()
	regions = meta.regions
	membership = meta.membership
	nt_sign.resize(n)
	for i in n:
		nt_sign[i] = float(meta.nt_sign[i])

	var ne := f.get_32()
	var pre := f.get_buffer(ne * 4).to_int32_array()
	col = f.get_buffer(ne * 4).to_int32_array()
	wgt = f.get_buffer(ne * 4).to_float32_array()
	f.close()
	# CSR from pre-sorted rows
	row_start.resize(n + 1)
	var r := 0
	for e in ne:
		while r < pre[e]:
			r += 1
			row_start[r] = e
	while r < n:
		r += 1
		row_start[r] = ne
	for e in ne:
		wgt[e] = minf(wgt[e], 3.0 * w_scale) / w_scale

	_build_targets(neurons)
	v.resize(n); act.resize(n); refr.resize(n); adapt.resize(n)
	_img = Image.create(n, 1, false, Image.FORMAT_RF)
	texture = ImageTexture.create_from_image(_img)
	loaded = true
	print("Sim: %d neurons, %d edges, %d targets" % [n, ne, targets.size()])
	return true


func _build_targets(neurons: Neurons) -> void:
	var by_region: Dictionary = {}
	for i in membership.size():
		for pair in membership[i]:
			var rid := int(pair[0])
			if not by_region.has(rid):
				by_region[rid] = PackedInt32Array()
			by_region[rid].append(i)
	var region_targets: Array = []
	for rid in by_region:
		if by_region[rid].size() >= MIN_TARGET_MEMBERS:
			region_targets.append({"name": regions[rid].name, "kind": "region", "region": rid, "members": by_region[rid]})
	region_targets.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)
	var class_targets: Array = []
	for g in neurons.groups:
		var m := PackedInt32Array()
		for i in n:
			if int(neurons.index[i].group) == int(g.id):
				m.append(i)
		class_targets.append({"name": String(g.name).replace("_", " "), "kind": "class", "region": -1, "members": m})
	targets = region_targets + class_targets
	# start on something that produces a good show
	for i in targets.size():
		if targets[i].name == "AL(R)":
			target_idx = i


func target() -> Dictionary:
	return targets[target_idx] if targets.size() > 0 else {}


func pulse() -> void:
	_pending_pulse = true


func reset() -> void:
	v.fill(0.0); act.fill(0.0); refr.fill(0); adapt.fill(0.0)
	fired = PackedInt32Array()
	_push_texture()


func _process(dt: float) -> void:
	if not loaded:
		return
	if auto_demo:
		_auto_timer -= dt
		if _auto_timer <= 0.0 and fired.size() <= int(DEMO_QUIET_FRAC * n):
			_auto_timer = randf_range(8.0, 12.0)
			# favour region targets for the demo
			var k := randi() % targets.size()
			target_idx = k
			_pending_pulse = true
	_acc += dt
	while _acc >= 1.0 / TICK_HZ:
		_acc -= 1.0 / TICK_HZ
		_tick()
	_push_texture()


func _tick() -> void:
	# 1. synaptic input from neurons that fired last tick
	var input := PackedFloat32Array()
	input.resize(n)
	for i in fired:
		var s := nt_sign[i]
		for e in range(row_start[i], row_start[i + 1]):
			var j := col[e]
			input[j] += s * wgt[e]
	# 2. stimulus
	if _pending_pulse and not targets.is_empty():
		var drive := STIM_DRIVE * 1.6
		for i in target().members:
			input[i] += drive * randf_range(0.6, 1.4)
		_pending_pulse = false
	# 3. integrate, fire, decay
	var candidates := PackedInt32Array()
	var active_frac := float(fired.size()) / n
	var thr := threshold * (1.0 + homeostasis * active_frac)   # global damping against runaway bursts
	for i in n:
		var a := act[i] * ACT_DECAY
		var vi := v[i] * leak + input[i]
		var ad := adapt[i] * adapt_decay
		if refr[i] > 0:
			refr[i] -= 1
			vi = minf(vi, 0.0)
		elif vi > thr + ad:
			candidates.append(i)
		v[i] = maxf(vi, -2.0)
		act[i] = a
		adapt[i] = ad
	# 4. cap the burst: a random subset fires, the rest are reset without spiking
	var cap := maxi(int(MAX_FIRE_FRAC * n), 1)
	if candidates.size() > cap:
		var order := Array(candidates)
		order.shuffle()
		for k in range(cap, order.size()):
			v[order[k]] = 0.0
		candidates = PackedInt32Array(order.slice(0, cap))
	for i in candidates:
		act[i] = 1.0
		v[i] = 0.0
		refr[i] = refractory
		adapt[i] += adapt_step
	fired = candidates
	spikes_per_s = lerpf(spikes_per_s, fired.size() * TICK_HZ, 0.3)


func _push_texture() -> void:
	_img.set_data(n, 1, false, Image.FORMAT_RF, act.to_byte_array())
	texture.update(_img)
