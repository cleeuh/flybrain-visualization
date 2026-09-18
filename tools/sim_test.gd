extends SceneTree
## Headless dynamics check:  godot --headless --path . -s tools/sim_test.gd

func _init() -> void:
	var neurons := Neurons.new()
	root.add_child(neurons)
	neurons.load_data()
	var sim := Sim.new()
	root.add_child(sim)
	sim.load_data(neurons)
	for cfg in [[0.4, 24.0, 1.0]]:
		sim.leak = cfg[0]; sim.adapt_step = cfg[2]
		sim.w_scale = cfg[1]
		var f := FileAccess.open("res://data/edges.bin", FileAccess.READ)
		var ne := f.get_32(); f.get_buffer(ne * 8)
		sim.wgt = f.get_buffer(ne * 4).to_float32_array()
		for e in ne:
			sim.wgt[e] = minf(sim.wgt[e], 3.0 * sim.w_scale) / sim.w_scale
		print("--- leak %.2f  w_scale %.0f  adapt %.1f" % cfg)
		_run(sim)
	quit()


func _run(sim: Sim) -> void:
	for tname in ["AL(R)", "ME(L)", "LegNp(T1)(L)", "descending neuron"]:
		for i in sim.targets.size():
			if sim.targets[i].name == tname:
				sim.target_idx = i
		sim.reset()
		sim.pulse()
		var trace := []
		var total := 0
		for t in 40:
			sim._tick()
			trace.append(sim.fired.size())
			total += sim.fired.size()
		print("%-18s members=%4d  spikes/tick: %s  total=%d" % [tname, sim.target().members.size(), str(trace.slice(0, 40)), total])
