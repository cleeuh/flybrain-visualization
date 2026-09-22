extends SceneTree
## Headless smoke test: run every story slide and print the framing it produces.

func _initialize() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var story = main.story
	story.start()
	for i in Story.SLIDES.size():
		story.goto_slide(i)
		for f in 4:
			await process_frame
		var s = story.slide()
		print("%2d  %-22s pivot=%s dist=%6.0f  lit=%d  panel=%d chars" % [
			i + 1, s.title, str(main.rig._pivot_target.round()), main.rig._dist_target,
			story._lit.size(), story.panel_text().length()])
		if s.has("rois") and story._lit.is_empty():
			push_error("slide %d matched no ROIs: %s" % [i + 1, str(s.rois)])
	story.stop()
	await process_frame
	print("stopped; shells back to alpha ", story._alpha(main.shell_nodes[0].material_override))
	quit()
