extends SceneTree
## Dev utility: renders one PNG per story slide to user:// (needs a display — under X, or
## `xvfb-run -s "-screen 0 1280x720x24" godot --path . -s tools/story_shots.gd ++ --3d=mono`).
## Neuron ribbons are hidden unless `--with-neurons` is passed, so it also finishes on a
## software rasteriser; it still checks the panel, the shell fade, the lit neuropils and the
## framing of every slide.

func _initialize() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	if not OS.get_cmdline_user_args().has("--with-neurons"):
		main.neurons.visible = false
	main.story.start()
	for i in Story.SLIDES.size():
		main.story.goto_slide(i)
		main.story._tween.custom_step(10.0)          # finish the fades
		var rig = main.rig                           # and the camera flight
		rig.position = rig._pivot_target
		rig.yaw_deg = rig._yaw_target
		rig.pitch_deg = rig._pitch_target
		rig.distance = rig._dist_target
		rig.rotation_degrees = Vector3(rig.pitch_deg, rig.yaw_deg, 0)
		rig.head.position = Vector3(0, 0, rig.distance)
		rig.auto_rotate = false
		await process_frame
		await RenderingServer.frame_post_draw
		var img = root.get_texture().get_image()
		img.save_png("user://slide_%02d.png" % (i + 1))
		print("slide %2d  %s" % [i + 1, main.story.slide().title])
	quit()
