extends Node
## Male CNS connectome viewer — glue: loads data, builds the scene, handles keys and UI.
##
## Command line (after `++`):  --3d=half|full|wall|mono  --swap  --story[=N] / --no-story
##                              --wall  --wall-size=6.047x2.042  --wall-distance=2.282  --wall-eye=0.063  --wall-res=4800x1620
## satwatch2-compatible:         -- --stereo [4800 1620] [--swap-eyes]  --ipd=0.033  --conv=1.0  --fov=70
##                              --width=1.2  --brightness=0.02  --rois  --no-shells  --no-rotate
##                              --windowed  --help=0  --demo  --stim="AL(R)"   (starts fullscreen)

const CONFIG_PATH := "user://flyviz.cfg"

@onready var scene_root: Node3D = $Scene
@onready var rig: OrbitRig = $Rig
@onready var stereo: StereoRig = $Stereo

var neurons: Neurons
var shells: Node3D
var shell_nodes: Array[MeshInstance3D] = []
var story: Story
var fly: Fly
var story_panels: Array[PanelContainer] = []
var story_labels: Array[RichTextLabel] = []
var rois: Node3D
var legends: Array[Control] = []
var help_visible := true
var ribbon_width := 1.2
var brightness := 0.02
var highlight_idx := -1
var sim: Sim
var sim_on := false
var roi_by_name: Dictionary = {}
var show_rois := false
var _stim_material: ShaderMaterial
var _story_on_start := true


func _ready() -> void:
	get_viewport().disable_3d = true   # only the eye SubViewports render 3D
	stereo.head = rig.head
	_load_config()
	_build_environment()
	_build_meshes()
	neurons = Neurons.new()
	neurons.name = "Neurons"
	scene_root.add_child(neurons)
	neurons.load_data()
	sim = Sim.new()
	sim.name = "Sim"
	add_child(sim)
	if sim.load_data(neurons):
		neurons.set_activity_texture(sim.texture)
		sim.changed.connect(_on_sim_changed)
	_stim_material = _shell_material(Color(1.0, 0.95, 0.6, 1.0), 0.12, 0.9)
	story = Story.new()
	story.name = "Story"
	add_child(story)
	story.setup(rig, stereo, neurons, fly, shell_nodes, roi_by_name)
	story.changed.connect(_update_ui)
	_apply_cmdline()
	if _story_on_start and not story.active:
		story.start()                    # the tour is the default entry point (--no-story skips it)
	neurons.set_width(ribbon_width)
	neurons.set_brightness(brightness)
	_build_ui()
	_update_ui()


var _ui_timer := 0.0
var _shot_path := ""
var _shot_timer := 0.0


func _process(dt: float) -> void:
	stereo.target_distance = rig.distance
	if story != null and story.active:
		_place_story_panels()
	if _shot_path != "":
		_shot_timer -= dt
		if _shot_timer <= 0.0:
			_save_screenshot(_shot_path)
			get_tree().quit()
	if sim_on:
		_ui_timer -= dt
		if _ui_timer <= 0.0:
			_ui_timer = 0.25
			_update_ui()


# --------------------------------------------------------------------------- scene

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.02)
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	scene_root.add_child(we)


func _shell_material(color: Color, fill: float, rim: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/shell.gdshader")
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("fill", fill)
	m.set_shader_parameter("rim", rim)
	return m


func _build_meshes() -> void:
	shells = Node3D.new()
	shells.name = "Shells"
	scene_root.add_child(shells)
	for n in ["brain_shell", "vnc_shell"]:
		var mesh := BMesh.load("res://data/meshes/%s.bmesh" % n)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.name = n
		mi.material_override = _shell_material(Color(0.35, 0.55, 1.0, 0.25), 0.02, 0.35)
		shells.add_child(mi)
		shell_nodes.append(mi)

	fly = Fly.new()
	fly.name = "Fly"
	scene_root.add_child(fly)

	rois = Node3D.new()
	rois.name = "ROIs"
	scene_root.add_child(rois)
	var list = JSON.parse_string(FileAccess.get_file_as_string("res://data/rois.json"))
	if list == null:
		return
	var i := 0
	for r in list:
		var mesh := BMesh.load("res://data/meshes/%s" % r.file)
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = r.name
		mi.visible = false
		mi.mesh = mesh
		var hue := fmod(i * 0.618033988, 1.0)   # golden-ratio hue spread, L/R pairs adjacent
		mi.material_override = _shell_material(Color.from_hsv(hue, 0.6, 1.0, 0.7), 0.05, 0.5)
		rois.add_child(mi)
		roi_by_name[r.name] = mi
		i += 1
	print("ROIs: %d neuropil meshes" % i)


# --------------------------------------------------------------------------- input

func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	var k: int = e.keycode
	var shift: bool = e.shift_pressed
	match k:
		KEY_ESCAPE: get_tree().quit()
		KEY_V: _toggle_story()
		KEY_RIGHT, KEY_LEFT:
			if not story.active:
				return                       # arrows orbit in free flight (polled by OrbitRig)
			story.step(1 if k == KEY_RIGHT else -1)
		KEY_F11, KEY_F: _toggle_fullscreen()
		KEY_F12: _save_screenshot("user://screenshot_%s.png" % Time.get_datetime_string_from_system().replace(":", "-"))
		KEY_H: help_visible = not help_visible
		KEY_SPACE: rig.auto_rotate = not rig.auto_rotate
		KEY_B: shells.visible = not shells.visible
		KEY_R:
			if story.active:
				story.restart()
			else:
				show_rois = not show_rois; _refresh_rois()
		KEY_T: stereo.cycle_mode()
		KEY_X: stereo.swap_eyes = not stereo.swap_eyes
		KEY_BRACKETLEFT: stereo.ipd_ratio = maxf(stereo.ipd_ratio / 1.15, 0.001)
		KEY_BRACKETRIGHT: stereo.ipd_ratio = minf(stereo.ipd_ratio * 1.15, 0.2)
		KEY_MINUS: stereo.convergence_factor = maxf(stereo.convergence_factor / 1.1, 0.2)
		KEY_EQUAL: stereo.convergence_factor = minf(stereo.convergence_factor * 1.1, 5.0)
		KEY_COMMA: ribbon_width = maxf(ribbon_width - 0.5, 0.5); neurons.set_width(ribbon_width)
		KEY_PERIOD: ribbon_width = minf(ribbon_width + 0.5, 12.0); neurons.set_width(ribbon_width)
		KEY_SEMICOLON: brightness = maxf(brightness / 1.25, 0.005); neurons.set_brightness(brightness)
		KEY_APOSTROPHE: brightness = minf(brightness * 1.25, 2.0); neurons.set_brightness(brightness)
		KEY_N: _step_highlight(-1 if shift else 1)
		KEY_M: highlight_idx = -1; neurons.set_highlight(-1)
		KEY_C: _save_config()
		KEY_TAB: sim.select_target(-1 if shift else 1)
		KEY_ENTER, KEY_KP_ENTER: _set_sim(true); sim.pulse()
		KEY_L: _set_sim(true); sim.tonic = not sim.tonic
		KEY_G: _set_sim(true); sim.auto_demo = not sim.auto_demo
		KEY_P: sim.paused = not sim.paused
		KEY_K: sim.reset(); sim.auto_demo = false; _set_sim(false)
		KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			var n := (k - KEY_0 + 9) % 10          # 1..9 -> 0..8, 0 -> 9
			if shift:
				n += 10
			if n < neurons.groups.size():
				neurons.toggle_group(n)
		KEY_ASCIITILDE, KEY_QUOTELEFT:
			var any_hidden := false
			for g in neurons.groups:
				if neurons.group_visible[int(g.id)] < 0.5:
					any_hidden = true
			neurons.set_all_visible(any_hidden)
		_:
			return
	_update_ui()


func _toggle_story() -> void:
	if story.active:
		story.stop()
		_refresh_rois()
	else:
		shells.visible = true
		story.start()


func _set_sim(on: bool) -> void:
	if not sim.loaded:
		return
	sim_on = on
	neurons.set_sim_active(on)
	_on_sim_changed()


## Neuropil meshes: all shown when show_rois, the stimulation target always (highlighted).
func _refresh_rois() -> void:
	if story != null and story.active:
		return                               # the tour owns the neuropil meshes while it runs
	var t := sim.target() if sim.loaded else {}
	for name in roi_by_name:
		var mi: MeshInstance3D = roi_by_name[name]
		var is_target: bool = sim_on and t.get("kind", "") == "region" and t.name == name
		mi.visible = show_rois or is_target
		if is_target:
			mi.material_override = _stim_material
		elif mi.material_override == _stim_material:
			mi.material_override = _shell_material(Color.from_hsv(fmod(mi.get_index() * 0.618033988, 1.0), 0.6, 1.0, 0.7), 0.05, 0.5)


func _on_sim_changed() -> void:
	_refresh_rois()
	_update_ui()


func _step_highlight(dir: int) -> void:
	if neurons.index.is_empty():
		return
	highlight_idx = posmod(highlight_idx + dir, neurons.index.size())
	neurons.set_highlight(highlight_idx)


func _save_screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("screenshot %dx%d saved to %s" % [img.get_width(), img.get_height(), ProjectSettings.globalize_path(path)])


func _toggle_fullscreen() -> void:
	var w := get_window()
	if w.mode == Window.MODE_FULLSCREEN or w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		w.mode = Window.MODE_WINDOWED
	else:
		w.mode = Window.MODE_FULLSCREEN


# --------------------------------------------------------------------------- UI (drawn in each eye)

const STORY_PANEL_W := 560.0
const STORY_MARGIN := 40.0


func _build_ui() -> void:
	for layer in stereo.ui_layers():
		var lbl := RichTextLabel.new()
		lbl.bbcode_enabled = true
		lbl.scroll_active = false
		lbl.fit_content = true
		lbl.position = Vector2(24, 24)
		lbl.size = Vector2(560, 900)
		lbl.add_theme_font_size_override("normal_font_size", 18)
		lbl.add_theme_font_size_override("bold_font_size", 18)
		lbl.add_theme_font_size_override("mono_font_size", 18)
		layer.add_child(lbl)
		legends.append(lbl)

		var panel := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.02, 0.03, 0.05, 0.72)
		sb.border_color = Color(0.35, 0.55, 1.0, 0.35)
		sb.border_width_left = 2
		sb.set_content_margin_all(28)
		sb.set_corner_radius_all(6)
		panel.add_theme_stylebox_override("panel", sb)
		panel.visible = false
		var story_lbl := RichTextLabel.new()
		story_lbl.bbcode_enabled = true
		story_lbl.scroll_active = false
		story_lbl.fit_content = true
		story_lbl.custom_minimum_size = Vector2(STORY_PANEL_W, 0)
		story_lbl.add_theme_font_size_override("normal_font_size", 21)
		story_lbl.add_theme_font_size_override("bold_font_size", 21)
		story_lbl.add_theme_font_size_override("italics_font_size", 21)
		panel.add_child(story_lbl)
		layer.add_child(panel)
		story_panels.append(panel)
		story_labels.append(story_lbl)
	get_viewport().size_changed.connect(_update_ui)


func _update_story_panels() -> void:
	var text: String = story.panel_text() if story.active else ""
	for i in story_panels.size():
		story_panels[i].visible = story.active
		if story.active:
			story_labels[i].text = text
	_place_story_panels()


## Pin each eye's narration panel to the right-hand edge of its viewport. Run every frame
## while the tour is up: the label's fit_content height only settles after a layout pass.
func _place_story_panels() -> void:
	for panel in story_panels:
		if not panel.visible:
			continue
		var layer := panel.get_parent() as CanvasLayer
		var vp := layer.get_viewport()
		if vp == null:
			continue
		var sc: float = maxf(layer.scale.x, 0.01)
		panel.reset_size()
		panel.position = Vector2(vp.size.x / sc - panel.size.x - STORY_MARGIN, STORY_MARGIN)


func _update_ui() -> void:
	for layer in stereo.ui_layers():
		var vp := layer.get_viewport()
		layer.scale = Vector2.ONE * maxf(vp.size.y / 1080.0, 0.5) if vp else Vector2.ONE
	_update_story_panels()
	if story.active:
		# the tour owns the screen: everything, credits included, is in the panel on the right
		for l in legends:
			l.text = ""
		return
	var t := "[b]Drosophila male CNS connectome[/b]\n"
	t += "[color=#aaa]%d neurons · %d skeleton segments · %s%s[/color]\n\n" % [
		neurons.index.size(), neurons.segment_count, stereo.mode_name(), "  (eyes swapped)" if stereo.swap_eyes else ""]
	if stereo.mode == StereoRig.Mode.WALL:
		t += "[color=#aaa]wall %.2f × %.2f m at %.2f m, eyes %.0f mm, %d×%d per eye · 1 mm = %.1f µm[/color]\n" % [
			stereo.wall_width, stereo.wall_height, stereo.wall_distance, stereo.wall_eye_separation * 1000,
			stereo.wall_eye_width, stereo.wall_eye_height, stereo.wall_units_per_metre() / 1000.0]
	var i := 0
	for g in neurons.groups:
		var on: bool = neurons.group_visible[int(g.id)] > 0.5
		var key := str((i + 1) % 10) if i < 10 else "⇧%d" % ((i - 9) % 10)
		var c := neurons.group_color(int(g.id))
		var name: String = String(g.name).replace("_", " ")
		t += "[color=#%s]%s[/color] [color=#666]%s[/color] %s [color=#666](%d)[/color]\n" % [
			c.to_html(false) if on else "444", "■" if on else "□", key, name, int(g.count)]
		i += 1
	if sim.loaded:
		var tg := sim.target()
		t += "\n[b]stimulate:[/b] [color=#ffe]%s[/color] [color=#888](%s, %d neurons)[/color]" % [tg.name, tg.kind, tg.members.size()]
		if sim_on:
			t += "   [color=#8f8]%s%s%.0f spikes/s[/color]" % ["tonic · " if sim.tonic else "", "auto · " if sim.auto_demo else "", sim.spikes_per_s]
		t += "\n"
	if highlight_idx >= 0:
		var n = neurons.index[highlight_idx]
		t += "\n[color=#fff]highlight:[/color] body %d  %s  [%s]\n" % [int(n.bodyId), str(n.type), neurons.groups[int(n.group)].name]
	if help_visible:
		t += "\n[color=#777]Tab / ⇧Tab: choose region or class   Enter: pulse   L: tonic drive   G: auto demo   P: pause   K: stop sim\n"
		t += "drag / arrows: orbit   wheel / Q E: zoom   space: auto-rotate\n"
		t += "1-9 0 ⇧: toggle class   `: all   B: shells   R: neuropils\n"
		t += "T: 3D format   X: swap eyes   [ ]: eye separation (%.3f)   - =: convergence (%.2f)\n" % [stereo.ipd_ratio, stereo.convergence_factor]
		t += ", .: width (%.1f)   ; \': brightness (%.3f)   N / ⇧N: step neuron   M: clear   F: fullscreen   C: save config   H: hide help\n" % [ribbon_width, brightness]
		t += "V: guided tour of the brain (← → to step through it; its last slide has the credits)[/color]"
	for l in legends:
		l.text = t


# --------------------------------------------------------------------------- config

func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	# clamp: configs written before the non-SBS formats were removed may hold a stale index
	stereo.mode = clampi(int(cfg.get_value("stereo", "mode", stereo.mode)), 0, StereoRig.Mode.size() - 1) as StereoRig.Mode
	stereo.swap_eyes = cfg.get_value("stereo", "swap_eyes", stereo.swap_eyes)
	stereo.ipd_ratio = cfg.get_value("stereo", "ipd_ratio", stereo.ipd_ratio)
	stereo.convergence_factor = cfg.get_value("stereo", "convergence_factor", stereo.convergence_factor)
	stereo.hfov_deg = cfg.get_value("stereo", "hfov_deg", stereo.hfov_deg)
	stereo.wall_width = cfg.get_value("wall", "width_m", stereo.wall_width)
	stereo.wall_height = cfg.get_value("wall", "height_m", stereo.wall_height)
	stereo.wall_distance = cfg.get_value("wall", "distance_m", stereo.wall_distance)
	stereo.wall_eye_separation = cfg.get_value("wall", "eye_separation_m", stereo.wall_eye_separation)
	stereo.wall_eye_width = cfg.get_value("wall", "eye_width_px", stereo.wall_eye_width)
	stereo.wall_eye_height = cfg.get_value("wall", "eye_height_px", stereo.wall_eye_height)
	ribbon_width = cfg.get_value("view", "ribbon_width", ribbon_width)
	brightness = cfg.get_value("view", "brightness", brightness)
	rig.auto_rotate = cfg.get_value("view", "auto_rotate", rig.auto_rotate)
	rig.auto_rotate_speed = cfg.get_value("view", "auto_rotate_speed", rig.auto_rotate_speed)
	help_visible = cfg.get_value("view", "help", help_visible)
	stereo.set_mode(stereo.mode)
	if stereo.mode == StereoRig.Mode.WALL:
		stereo.apply_wall_window()


func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("stereo", "mode", stereo.mode)
	cfg.set_value("stereo", "swap_eyes", stereo.swap_eyes)
	cfg.set_value("stereo", "ipd_ratio", stereo.ipd_ratio)
	cfg.set_value("stereo", "convergence_factor", stereo.convergence_factor)
	cfg.set_value("stereo", "hfov_deg", stereo.hfov_deg)
	cfg.set_value("wall", "width_m", stereo.wall_width)
	cfg.set_value("wall", "height_m", stereo.wall_height)
	cfg.set_value("wall", "distance_m", stereo.wall_distance)
	cfg.set_value("wall", "eye_separation_m", stereo.wall_eye_separation)
	cfg.set_value("wall", "eye_width_px", stereo.wall_eye_width)
	cfg.set_value("wall", "eye_height_px", stereo.wall_eye_height)
	cfg.set_value("view", "ribbon_width", ribbon_width)
	cfg.set_value("view", "brightness", brightness)
	cfg.set_value("view", "auto_rotate", rig.auto_rotate)
	cfg.set_value("view", "auto_rotate_speed", rig.auto_rotate_speed)
	cfg.set_value("view", "help", help_visible)
	cfg.save(CONFIG_PATH)
	print("config saved to ", ProjectSettings.globalize_path(CONFIG_PATH))


func _apply_cmdline() -> void:
	var args := OS.get_cmdline_user_args()
	# satwatch2 / stereo_wall_display convention:  -- --stereo [W H] [--swap-eyes]
	var si := args.find("--stereo")
	if si >= 0:
		stereo.set_mode(StereoRig.Mode.WALL)
		if si + 2 < args.size() and args[si + 1].is_valid_int():
			stereo.wall_eye_width = int(args[si + 1])
			stereo.wall_eye_height = int(args[si + 2])
	if args.has("--swap-eyes"):
		stereo.swap_eyes = true
	for arg in args:
		var kv := arg.trim_prefix("--").split("=", true, 1)
		var key := kv[0]
		var val := kv[1] if kv.size() > 1 else ""
		match key:
			"sbs", "stereo", "3d": stereo.set_mode(StereoRig.MODE_KEYS.get(val, stereo.mode))
			"wall": stereo.set_mode(StereoRig.Mode.WALL)
			"wall-size":   # metres, e.g. --wall-size=6.047x2.042
				var p := val.split("x"); stereo.wall_width = float(p[0]); stereo.wall_height = float(p[1])
			"wall-distance": stereo.wall_distance = float(val)
			"wall-eye": stereo.wall_eye_separation = float(val)
			"wall-res":    # pixels per eye, e.g. --wall-res=4800x1620
				var p := val.split("x"); stereo.wall_eye_width = int(p[0]); stereo.wall_eye_height = int(p[1])
			"ipd": stereo.ipd_ratio = float(val)
			"conv": stereo.convergence_factor = float(val)
			"fov": stereo.hfov_deg = float(val)
			"width": ribbon_width = float(val)
			"brightness": brightness = float(val)
			"swap": stereo.swap_eyes = true
			"no-rotate": rig.auto_rotate = false
			"rois": show_rois = true; _refresh_rois()
			"demo": _set_sim(true); sim.auto_demo = true
			"simon": _set_sim(true)
			"stim":
				for i in sim.targets.size():
					if sim.targets[i].name == val:
						sim.target_idx = i
				_set_sim(true); sim.pulse()
			"no-shells": shells.visible = false
			"story": story.start(int(val) - 1 if val.is_valid_int() else 0)
			"no-story": _story_on_start = false
			"fullscreen": get_window().mode = Window.MODE_FULLSCREEN
			"windowed": get_window().mode = Window.MODE_WINDOWED
			"help": help_visible = val != "0"
			"screenshot": _shot_path = val; _shot_timer = 2.0   # save after 2 s and quit
	if stereo.mode == StereoRig.Mode.WALL:
		stereo.apply_wall_window()
