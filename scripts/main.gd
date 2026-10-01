extends Node
## Male CNS connectome viewer — glue: loads data, builds the scene, runs the guided tour.
## The tour is the whole app: ← → step slides, drag / WASD orbit, wheel / Q E zoom,
## T cycles the 3D format, F toggles fullscreen.
##
## Command line (after `++`):  --3d=half|full|mono  --swap  --story=N  --windowed (starts fullscreen)
##                              --ipd=0.033  --conv=1.0  --fov=70  --width=1.2  --brightness=0.02
##                              --no-anim  --screenshot=path

const CONFIG_PATH := "user://flyviz.cfg"

@onready var scene_root: Node3D = $Scene
@onready var rig: OrbitRig = $Rig
@onready var stereo: StereoRig = $Stereo

var neurons: Neurons
var shell_nodes: Array[MeshInstance3D] = []
var story: Story
var fly: Fly
var story_panels: Array[PanelContainer] = []
var story_labels: Array[RichTextLabel] = []
var illustrations: Array[Illustration] = []   ## per-slide schematic under each eye's narration
var flow: SignalFlow                         ## slide illustrations as pulses on real neurons
var stimulus: Stimulus                       ## the outside world for those slides (sketches)
var rois: Node3D
var hints: Array[RichTextLabel] = []         ## key strip, bottom left of each eye
var ribbon_width := 1.2
var brightness := 0.02
var sim: Sim
var roi_by_name: Dictionary = {}
var animations := true               ## ambient motion (waves, motes, fades); --no-anim turns it off
var _start_slide := 0
var _panel_tween: Tween
var _panel_slide := 0.0              ## narration panel's slide-in offset, px
var _panel_slide_index := -1


func _ready() -> void:
	get_viewport().disable_3d = true   # only the eye SubViewports render 3D
	stereo.head = rig.head
	_load_config()
	_build_environment()
	_build_meshes()
	var motes := Motes.new()
	motes.name = "Motes"
	scene_root.add_child(motes)
	neurons = Neurons.new()
	neurons.name = "Neurons"
	scene_root.add_child(neurons)
	neurons.load_data()
	sim = Sim.new()
	sim.name = "Sim"
	add_child(sim)
	if sim.load_data(neurons):
		neurons.set_activity_texture(sim.texture)
		neurons.set_sim_active(true)
		sim.auto_demo = true             # random stimuli keep the connectome alive through the tour
	story = Story.new()
	story.name = "Story"
	add_child(story)
	story.setup(rig, stereo, neurons, fly, shell_nodes, roi_by_name)
	story.changed.connect(_update_ui)
	flow = SignalFlow.new()
	flow.name = "SignalFlow"
	flow.neurons = neurons
	flow.sim = sim
	flow.rois = roi_by_name
	add_child(flow)
	stimulus = Stimulus.new()
	stimulus.name = "Stimulus"
	stimulus.flow = flow
	stimulus.fly = fly
	stimulus.head = rig.head
	stimulus.rois = roi_by_name
	scene_root.add_child(stimulus)
	story.changed.connect(_on_slide_changed)
	_apply_cmdline()
	story.start(_start_slide)
	RenderingServer.global_shader_parameter_set("anim_level", 1.0 if animations else 0.0)
	neurons.set_width(ribbon_width)
	neurons.set_brightness(brightness)
	_build_ui()
	_update_ui()


var _shot_path := ""
var _shot_timer := 0.0


func _process(dt: float) -> void:
	stereo.target_distance = rig.distance
	_place_story_panels()
	if _shot_path != "":
		_shot_timer -= dt
		if _shot_timer <= 0.0:
			_save_screenshot(_shot_path)
			get_tree().quit()


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
	var shells := Node3D.new()
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

## A slide with a signal-flow illustration takes over the neurons; the random stimulation
## pauses (and its activity clears) so the two are never on screen together.
func _on_slide_changed() -> void:
	flow.show_slide(story.slide())
	if sim.loaded:
		sim.auto_demo = not flow.active()
		if flow.active():
			sim.reset()


func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	match e.keycode:
		KEY_ESCAPE: get_tree().quit()
		KEY_RIGHT: story.step(1)
		KEY_LEFT: story.step(-1)
		KEY_T: stereo.cycle_mode(); _save_config()
		KEY_F, KEY_F11: _toggle_fullscreen()
		_:
			return
	_update_ui()


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
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		lbl.add_theme_font_override("normal_font", UITheme.mono())
		lbl.add_theme_font_size_override("normal_font_size", 15)
		var plate := UITheme.panel(12)           # keeps the strip legible over bright tissue
		plate.content_margin_left = 18
		plate.content_margin_right = 18
		lbl.add_theme_stylebox_override("normal", plate)
		UITheme.add_brackets(lbl)
		layer.add_child(lbl)
		hints.append(lbl)

		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UITheme.panel(28))
		UITheme.add_brackets(panel)
		panel.visible = false
		var story_lbl := RichTextLabel.new()
		story_lbl.bbcode_enabled = true
		story_lbl.scroll_active = false
		story_lbl.fit_content = true
		story_lbl.custom_minimum_size = Vector2(STORY_PANEL_W, 0)
		story_lbl.add_theme_font_override("normal_font", UITheme.mono())
		story_lbl.add_theme_font_override("bold_font", UITheme.mono(700))
		story_lbl.add_theme_font_override("italics_font", UITheme.mono(400, true))
		for f in ["normal_font_size", "bold_font_size", "italics_font_size"]:
			story_lbl.add_theme_font_size_override(f, 18)
		story_lbl.add_theme_color_override("default_color", Color(UITheme.H_TEXT))
		story_lbl.add_theme_constant_override("line_separation", 3)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 18)
		col.add_child(story_lbl)
		var fig := Illustration.new()
		fig.flow = flow
		col.add_child(fig)
		panel.add_child(col)
		illustrations.append(fig)
		layer.add_child(panel)
		story_panels.append(panel)
		story_labels.append(story_lbl)
	get_viewport().size_changed.connect(_update_ui)


func _update_story_panels() -> void:
	var text: String = story.panel_text()
	var new_slide := story.index != _panel_slide_index
	_panel_slide_index = story.index
	for i in story_panels.size():
		story_panels[i].visible = true
		story_labels[i].text = text
		illustrations[i].kind = story.slide().get("illus", "")
	if new_slide:
		_animate_panel_in()
	_place_story_panels()


## Each slide's narration eases in from the right instead of snapping over the old one.
func _animate_panel_in() -> void:
	if _panel_tween != null and _panel_tween.is_valid():
		_panel_tween.kill()
	if not animations:
		_panel_slide = 0.0
		for p in story_panels:
			p.modulate.a = 1.0
		return
	_panel_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_panel_tween.tween_property(self, "_panel_slide", 0.0, 0.55).from(36.0)
	for p in story_panels:
		_panel_tween.tween_property(p, "modulate:a", 1.0, 0.45).from(0.0)


## Pin each eye's narration panel to the right-hand edge of its viewport and the key hints to
## the bottom left. Run every frame: fit_content heights only settle after a layout pass.
func _place_story_panels() -> void:
	for i in story_panels.size():
		var panel := story_panels[i]
		var layer := panel.get_parent() as CanvasLayer
		var vp := layer.get_viewport()
		if vp == null:
			continue
		var sc: float = maxf(layer.scale.x, 0.01)
		panel.reset_size()
		panel.position = Vector2(vp.size.x / sc - panel.size.x - STORY_MARGIN + _panel_slide, STORY_MARGIN)
		if i < hints.size():
			hints[i].reset_size()
			hints[i].position = Vector2(STORY_MARGIN, vp.size.y / sc - hints[i].size.y - STORY_MARGIN * 0.6)


func _update_ui() -> void:
	for layer in stereo.ui_layers():
		var vp := layer.get_viewport()
		layer.scale = Vector2.ONE * maxf(vp.size.y / 1080.0, 0.5) if vp else Vector2.ONE
	_update_story_panels()
	var full := get_window().mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
	var key := func(k: String, what: String) -> String:
		return "[color=#%s]%s[/color] [color=#%s]%s[/color]" % [UITheme.H_HI, k, UITheme.H_DIM, what]
	var val := func(v: String) -> String:
		return " [color=#%s]%s[/color]" % [UITheme.H_TEXT, v.to_upper()]
	var gap := "   [color=#%s]|[/color]   " % UITheme.H_FAINT
	var t: String = key.call("DRAG", "ROTATE") + gap + key.call("WHEEL", "ZOOM") + gap
	t += key.call("T", "3D FORMAT") + val.call(stereo.mode_name()) + gap
	t += key.call("F", "FULLSCREEN") + val.call("on" if full else "off")
	for h in hints:
		h.text = t


# --------------------------------------------------------------------------- config

## Only the 3D format is remembered; T saves it as soon as it changes.
func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	# clamp: configs from older builds may hold an index for a format that no longer exists
	stereo.mode = clampi(int(cfg.get_value("stereo", "mode", stereo.mode)), 0, StereoRig.Mode.size() - 1) as StereoRig.Mode
	stereo.set_mode(stereo.mode)


func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("stereo", "mode", stereo.mode)
	cfg.save(CONFIG_PATH)


func _apply_cmdline() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		var kv := arg.trim_prefix("--").split("=", true, 1)
		var key := kv[0]
		var val := kv[1] if kv.size() > 1 else ""
		match key:
			"sbs", "3d": stereo.set_mode(StereoRig.MODE_KEYS.get(val, stereo.mode))
			"ipd": stereo.ipd_ratio = float(val)
			"conv": stereo.convergence_factor = float(val)
			"fov": stereo.hfov_deg = float(val)
			"width": ribbon_width = float(val)
			"brightness": brightness = float(val)
			"swap": stereo.swap_eyes = true
			"story": _start_slide = int(val) - 1 if val.is_valid_int() else 0
			"fullscreen": get_window().mode = Window.MODE_FULLSCREEN
			"windowed": get_window().mode = Window.MODE_WINDOWED
			"no-anim": animations = false
			"screenshot": _shot_path = val; _shot_timer = 2.0   # save after 2 s and quit
