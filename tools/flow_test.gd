extends SceneTree
## Headless check of the slide signal flows: per slide, how many real neurons each stage
## picked and the longest routed path (µm).
##   godot --headless --path . -s tools/flow_test.gd

func _initialize() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	for i in Story.SLIDES.size():
		var s: Dictionary = Story.SLIDES[i]
		if not s.has("illus"):
			continue
		main.story.goto_slide(i)
		await process_frame
		var img: Image = main.neurons._flow_img
		var by_delay := {}
		var longest := 0.0
		for n in main.neurons._flow_set:
			var d := img.get_pixel(n, 0).r
			by_delay[d] = int(by_delay.get(d, 0)) + 1
			longest = maxf(longest, float(main.neurons.flow_length.get(n, 0.0)))
		print("%-20s %-9s neurons=%3d  stages(delay:count)=%s  longest path=%.0f µm  active=%s" % [
			s.title, s.illus, main.neurons._flow_set.size(), str(by_delay), longest, main.flow.active()])
	quit()
