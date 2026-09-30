class_name Story
extends Node
## Guided slide tour of the fly CNS, stepped with the left / right arrow keys.
##
## Each slide names the neuropils it is about, and the tour flies the orbit rig to frame
## them, fades the outer brain / VNC shells to the slide's opacity, lights the slide's
## neuropil meshes and (optionally) shows only some neuron superclasses. The narration is
## drawn by main.gd in a panel down the right-hand edge of each eye.
##
## Slide fields
##   title     heading
##   sci       scientific / formal name
##   abbr      neuropil abbreviations quoted in the text
##   body      narration (bbcode)
##   rois      neuropil base names; "(L)" / "(R)" variants are added automatically
##   focus     "fly" | "cns" | "brain" | "vnc" | "rois" (frame the slide's ROIs) — default "rois"
##   shell     outer shell opacity 0..1 (1 = as in free-flight mode, 0 = fully transparent)
##   fly       opacity of the stylised whole fly, 0..1 (default 0)
##   hover     true to let the fly hover and flap; false / omitted parks it on the CNS
##   neurons   false to hide the neuron ribbons (default true)
##   yaw/pitch camera angles in degrees
##   zoom      padding on the computed framing distance (>1 pulls back, <1 crops in)
##   classes   neuron superclasses to show; omitted / empty = all
##   credits   true on the closing slide: appends CREDITS; → from it starts over

const SHELL_BASE_ALPHA := 0.25
const ROI_ALPHA := 0.75   ## lit neuropil opacity, scaled down when a slide lights many
const FLY_SECONDS := 1.6      ## shell / neuropil cross-fade time; the rig eases in on its own
## Fraction of the frame width the narration panel covers on the right; the rendered image
## is lens-shifted left by this much so the subject stays clear of it.
const VIEW_SHIFT := 0.16

const SLIDES: Array[Dictionary] = [
	{
		"title": "Meet the fruit fly",
		"sci": "Drosophila melanogaster (Meigen, 1830)",
		"abbr": "≈ 2.5 mm · ≈ 140 000 neurons",
		"body": "Two and a half millimetres of animal, hovering in front of you. It walks, flies, "
			+ "courts, learns and remembers, tastes with its feet and hears with its antennae.\n\n"
			+ "A century of genetics has made it the animal we understand best — and the first one "
			+ "whose entire nervous system has been traced, neuron by neuron, from electron "
			+ "microscopy.",
		"focus": "fly", "fly": 1.0, "neurons": false, "shell": 0.0,
		"yaw": 200.0, "pitch": -10.0, "zoom": 1.2, "hover": true,
	},
	{
		"title": "Inside the fly",
		"sci": "Central nervous system · Systema nervosum centrale",
		"abbr": "brain + ventral nerve cord",
		"body": "The body turns to glass. What is left is everything the fly does its thinking "
			+ "with: a brain filling the head and a ventral nerve cord running through the thorax, "
			+ "joined by the neck connective.\n\n"
			+ "Every line here is a real, reconstructed neuron, placed where it sits in the animal.",
		# same camera angle as the fly slide, so the body dissolves in place before we move
		"focus": "cns", "fly": 0.0, "shell": 1.0, "yaw": 200.0, "pitch": -10.0, "zoom": 1.25,
	},
	{
		"title": "The brain",
		"sci": "Cerebrum — supraoesophageal + gnathal ganglia",
		"abbr": "≈ 3 × 10⁵ µm³",
		"body": "The outer shell dissolves and we drop into the head. What is left is the wiring: "
			+ "neurons whose branches respect invisible boundaries called [i]neuropils[/i] — dense "
			+ "tangles of synapses, each one a functional district of the brain.\n\n"
			+ "The next slides visit those districts one at a time.",
		"focus": "brain", "shell": 0.0, "yaw": 0.0, "pitch": -8.0, "zoom": 1.25,
	},
	{
		"title": "Vision",
		"sci": "Optic lobes · Lobus opticus — lamina, medulla, lobula, lobula plate",
		"abbr": "LA · ME · LO · LOP · AME",
		"body": "More than half the brain is devoted to seeing. Each compound eye feeds ~800 "
			+ "retinotopic columns that stack through the lamina and medulla into the lobula complex.\n\n"
			+ "The lobula plate (LOP) holds the wide-field motion detectors that keep the fly's "
			+ "gaze and flight path stable; the lobula (LO) carries object and feature channels "
			+ "onward to the central brain.",
		"rois": ["LA", "ME", "LO", "LOP", "AME"], "shell": 0.0, "yaw": 35.0, "pitch": -10.0, "zoom": 1.25,
		"classes": ["ol_intrinsic", "ol_sensory", "visual_projection", "visual_centrifugal"],
	},
	{
		"title": "Smell",
		"sci": "Antennal lobe · Lobus antennalis",
		"abbr": "AL",
		"body": "The first olfactory relay, the insect counterpart of the vertebrate olfactory bulb. "
			+ "Olfactory receptor neurons on the antenna and maxillary palp sort themselves by "
			+ "receptor type into ~58 spherical [i]glomeruli[/i].\n\n"
			+ "Local interneurons sharpen and normalise the odour code there; projection neurons "
			+ "carry it to the mushroom body and the lateral horn.",
		"rois": ["AL"], "shell": 0.0, "yaw": 0.0, "pitch": 5.0, "zoom": 1.25,
	},
	{
		"title": "Learning and memory",
		"sci": "Mushroom body · Corpus pedunculatum",
		"abbr": "CA · PED · αL · α'L · βL · β'L · γL",
		"body": "About 2 000 Kenyon cells per side take a sparse, near-random sample "
			+ "of projection-neuron input in the calyx (CA), then run in a tight bundle down the "
			+ "peduncle (PED) and split into the α/β, α'/β' and γ lobes.\n\n"
			+ "Dopaminergic neurons write reward and punishment onto those lobes compartment by "
			+ "compartment, so the same odour can drive approach or avoidance depending on what the "
			+ "fly has learned.",
		"rois": ["CA", "PED", "aL", "a'L", "bL", "b'L", "gL"], "shell": 0.0, "yaw": -20.0, "pitch": 0.0, "zoom": 1.25,
	},
	{
		"title": "Instinct",
		"sci": "Lateral horn · Cornu laterale",
		"abbr": "LH",
		"body": "The innate half of the olfactory system. The same projection neurons that teach the "
			+ "mushroom body also terminate here, in a stereotyped map that is wired before the fly "
			+ "has ever smelled anything.\n\n"
			+ "The lateral horn assigns hard-wired valence — food, a mate, a parasitoid wasp — and "
			+ "hands it to descending pathways without waiting for experience.",
		"rois": ["LH"], "shell": 0.0, "yaw": -35.0, "pitch": 0.0, "zoom": 1.25,
	},
	{
		"title": "Finding the way",
		"sci": "Central complex · Complexus centralis",
		"abbr": "EB · FB · PB · NO",
		"body": "The fly's compass and steering committee, straddling the midline. Ring neurons and "
			+ "EPG cells in the ellipsoid body (EB) hold a single bump of activity that tracks "
			+ "heading — a working head-direction signal, updated by vision and by the animal's own "
			+ "turns.\n\n"
			+ "The protocerebral bridge (PB) keeps the bump in register, the fan-shaped body (FB) "
			+ "turns it into goal-directed steering, and the noduli (NO) fold in self-motion.",
		"rois": ["EB", "FB", "PB", "NO"], "shell": 0.0, "yaw": 0.0, "pitch": -5.0, "zoom": 1.25,
	},
	{
		"title": "Hearing and touch",
		"sci": "AMMC and wedge · Centrum mechanosensorium antennale et motorium",
		"abbr": "AMMC · WED · SAD",
		"body": "The antenna is also an ear. Johnston's organ, at its base, converts the vibration of "
			+ "the arista into spikes that arrive here, in the antennal mechanosensory and motor "
			+ "centre (AMMC).\n\n"
			+ "Courtship song, wind direction and gravity are all read out of this input; the wedge "
			+ "(WED) and saddle (SAD) pass it on to circuits that steer the fly toward a singing male "
			+ "or into the wind.",
		"rois": ["AMMC", "WED", "SAD"], "shell": 0.0, "yaw": 15.0, "pitch": 10.0, "zoom": 1.25,
	},
	{
		"title": "Taste and eating",
		"sci": "Gnathal ganglia · Ganglion gnathale (subesophageal zone)",
		"abbr": "GNG · PRW · FLA",
		"body": "The mouth's brain, fused to the underside of the rest. Taste bristles on the "
			+ "proboscis, legs and wing margins report here, and the motor neurons that extend the "
			+ "proboscis and pump food leave from here.\n\n"
			+ "It is also a bottleneck: most descending neurons heading for the nerve cord pass "
			+ "through this region, which is why feeding, grooming and locomotion are so tightly "
			+ "interlocked.",
		"rois": ["GNG", "PRW", "FLA"], "shell": 0.0, "yaw": 0.0, "pitch": 20.0, "zoom": 1.25,
	},
	{
		"title": "From brain to body",
		"sci": "Neck connective · Connectivum cervicale — descending neurons",
		"abbr": "≈ 1 300 DNs",
		"body": "Only about 1 300 descending neurons per side carry the brain's decisions into the "
			+ "body — a famously narrow channel. Each one is closer to a command than to a wire: "
			+ "single DNs can trigger a turn, a takeoff, a song bout or a backward walk.\n\n"
			+ "Ascending neurons run the other way, telling the brain what the legs and wings are "
			+ "actually doing.",
		"focus": "cns", "shell": 0.2, "yaw": 90.0, "pitch": 0.0, "zoom": 1.25,
		"classes": ["descending_neuron", "ascending_neuron", "sensory_ascending"],
	},
	{
		"title": "Walking and flying",
		"sci": "Ventral nerve cord · Ganglion thoracicoabdominale",
		"abbr": "LegNp(T1–T3) · WTct · HTct · NTct · ANm",
		"body": "The fly's spinal cord, and the place where movement is actually produced. Three leg "
			+ "neuropils (T1–T3) each hold the sensory input and motor neurons of one pair of legs, "
			+ "with local circuits that run the step cycle without the brain.\n\n"
			+ "Above them the tectulum drives the wings and halteres — wing (WTct), haltere (HTct) "
			+ "and neck (NTct) control — and the abdominal neuromere (ANm) handles the rest of the body.",
		"rois": ["LegNp(T1)", "LegNp(T2)", "LegNp(T3)", "WTct(UTct-T2)", "HTct(UTct-T3)", "NTct(UTct-T1)", "ANm", "IntTct", "LTct"],
		"shell": 0.35, "yaw": 25.0, "pitch": -10.0, "zoom": 1.25,
		"classes": ["vnc_intrinsic", "vnc_sensory", "vnc_motor", "vnc_efferent", "descending_neuron", "ascending_neuron"],
	},
	{
		"title": "The whole picture",
		"sci": "Drosophila melanogaster — male CNS connectome v1.0",
		"body": "Back out to the whole animal. Smell, sight, hearing, memory, a compass and six legs, "
			+ "all in a volume smaller than a poppy seed — and all of it now traced synapse by synapse.",
		"focus": "cns", "shell": 1.0, "yaw": -25.0, "pitch": -15.0, "zoom": 1.25, "credits": true,
	},
]

## Shown on the closing slide — the only place the dataset and tooling are credited.
const CREDITS := [
	["Data", "FlyEM / Janelia male adult CNS connectome, male-cns v1.0 (CC-BY 4.0)"],
	["", "male-cns.janelia.org/download"],
	["Rendering", "Godot 4.7 · additive screen-space ribbons, one MultiMesh"],
	["Stereo", "off-axis side-by-side"],
]

signal changed

var active := false
var index := 0

var _rig: OrbitRig
var _stereo: StereoRig
var _neurons: Neurons
var _fly: Fly
var _shell_mats: Array[ShaderMaterial] = []
var _rois: Dictionary = {}            # name -> MeshInstance3D
var _roi_mats: Dictionary = {}        # name -> story material (created lazily)
var _orig_mats: Dictionary = {}       # name -> material the ROI had before the tour lit it
var _lit: Array[String] = []          # ROI names lit by the current slide
var _fading: Array[String] = []       # ROI names on their way out
var _shell_nodes: Array[MeshInstance3D] = []
var _tween: Tween


func setup(rig: OrbitRig, stereo: StereoRig, neurons: Neurons, fly: Fly,
		shell_nodes: Array[MeshInstance3D], roi_by_name: Dictionary) -> void:
	_rig = rig
	_stereo = stereo
	_fly = fly
	_neurons = neurons
	_shell_nodes = shell_nodes
	_shell_mats.clear()
	for mi in shell_nodes:
		_shell_mats.append(mi.material_override as ShaderMaterial)
	_rois = roi_by_name


func slide() -> Dictionary:
	return SLIDES[clampi(index, 0, SLIDES.size() - 1)]


func start(from := 0) -> void:
	active = true
	_stereo.view_shift = VIEW_SHIFT
	index = clampi(from, 0, SLIDES.size() - 1)
	_apply()


## → past the closing slide loops back to the opening one; ← stops at the first.
func step(dir: int) -> void:
	var n := index + dir
	if n >= SLIDES.size():
		n = 0
	elif n < 0:
		return
	index = n
	_apply()


func goto_slide(i: int) -> void:
	index = clampi(i, 0, SLIDES.size() - 1)
	if active:
		_apply()


# --------------------------------------------------------------------------- applying a slide

func _apply() -> void:
	var s := slide()
	_kill_tween()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# outer shells
	var shell_a: float = float(s.get("shell", 0.0)) * SHELL_BASE_ALPHA
	for m in _shell_mats:
		_tween.tween_method(_set_alpha.bind(m), _alpha(m), shell_a, FLY_SECONDS)

	# neuropils: fade out what this slide does not use, fade in what it does
	var want := _resolve_rois(s.get("rois", []))
	var roi_a: float = ROI_ALPHA if want.size() <= 6 else maxf(ROI_ALPHA * 6.0 / want.size(), 0.35)
	for name in _lit:
		if want.has(name):
			continue
		if not _fading.has(name):
			_fading.append(name)
		_tween.tween_method(_set_alpha.bind(_story_mat(name)), _alpha(_story_mat(name)), 0.0, FLY_SECONDS * 0.6)\
			.finished.connect(_unlight.bind(name))
	for name in want:
		var mi: MeshInstance3D = _rois[name]
		var m := _story_mat(name)
		_fading.erase(name)
		if not _lit.has(name):
			_orig_mats[name] = mi.material_override
			_set_alpha(0.0, m)
		mi.material_override = m
		mi.visible = true
		_tween.tween_method(_set_alpha.bind(m), _alpha(m), roi_a, FLY_SECONDS)
	_lit = want

	# the stylised body, and whether the connectome itself is drawn at all
	_tween.tween_method(_fly.set_alpha, _fly.alpha(), float(s.get("fly", 0.0)), FLY_SECONDS)
	_fly.flying = bool(s.get("hover", false))
	var show_neurons := bool(s.get("neurons", true))
	if show_neurons and not _neurons.visible:
		_neurons.reveal()                # the connectome grows out of the body as it dissolves
	_neurons.visible = show_neurons

	# neuron superclasses
	var classes: Array = s.get("classes", [])
	for g in _neurons.groups:
		_neurons.set_group_visible(int(g.id), classes.is_empty() or classes.has(String(g.name)))

	# camera
	var box := _focus_aabb(s, want)
	var yaw := float(s.get("yaw", 0.0))
	var pitch := float(s.get("pitch", -10.0))
	_rig.auto_rotate = true
	_rig.goto(box.get_center(), yaw, pitch, _framing_distance(box, yaw, pitch, float(s.get("zoom", 1.25))))
	changed.emit()


## Distance at which `box` just fits the usable part of one eye image, from that eye's own
## aspect and field of view, with the box measured along the camera axes it will be seen from.
func _framing_distance(box: AABB, yaw: float, pitch: float, pad: float) -> float:
	var basis := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0))
	var half := box.size * 0.5
	var axes := [basis.x, basis.y, basis.z]      # camera right / up / back, in world space
	var ext := Vector3.ZERO                      # half-extents of the box along each of them
	for i in 3:
		var a: Vector3 = axes[i]
		ext[i] = absf(half.x * a.x) + absf(half.y * a.y) + absf(half.z * a.z)
	var half_h := deg_to_rad(_stereo.hfov_deg) * 0.5
	var half_v := atan(tan(half_h) / maxf(_stereo.eye_aspect(), 0.1))
	if _stereo.view_shift > 0.0:
		half_h = atan(tan(half_h) * maxf(1.0 - 2.0 * _stereo.view_shift, 0.2))   # panel takes the right edge
	# framed on the box's mid-plane (+ a little of its depth): framing the front face as well
	# would push the camera back far enough to make every subject look small.
	var dist := maxf(ext.x / tan(half_h), ext.y / tan(half_v)) * pad + ext.z * 0.3
	return maxf(dist, _stereo.near * 4.0)


## World-space box the slide wants framed.
func _focus_aabb(s: Dictionary, lit: Array[String]) -> AABB:
	match String(s.get("focus", "rois")):
		"fly":
			return _fly.global_transform * _fly.rest_aabb()
		"cns":
			return _shell_aabb(["brain_shell", "vnc_shell"])
		"brain":
			return _shell_aabb(["brain_shell"])
		"vnc":
			return _shell_aabb(["vnc_shell"])
	var box := AABB()
	var first := true
	for name in lit:
		var mi: MeshInstance3D = _rois[name]
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box if not first else _shell_aabb(["brain_shell"])


func _shell_aabb(names: Array) -> AABB:
	var box := AABB()
	var first := true
	for mi in _shell_nodes:
		if not names.has(mi.name):
			continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box if not first else AABB(Vector3(-600, -600, -600), Vector3(1200, 1200, 1200))


## "AL" -> ["AL(L)", "AL(R)"] (or "EB" -> ["EB"]); unknown names are dropped.
func _resolve_rois(bases: Array) -> Array[String]:
	var out: Array[String] = []
	for b in bases:
		for n in [String(b), "%s(L)" % b, "%s(R)" % b]:
			if _rois.has(n) and not out.has(n):
				out.append(n)
	return out


func _story_mat(name: String) -> ShaderMaterial:
	if not _roi_mats.has(name):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/shell.gdshader")
		# warm highlight, brighter than the plain neuropil material
		m.set_shader_parameter("color", Color(1.0, 0.82, 0.45, 0.0))
		m.set_shader_parameter("fill", 0.09)
		m.set_shader_parameter("rim", 0.8)
		m.set_shader_parameter("breathe", 0.18)
		m.set_shader_parameter("scan", 0.35)
		m.set_shader_parameter("scan_spacing", 18.0)
		_roi_mats[name] = m
	return _roi_mats[name]


func _unlight(name: String) -> void:
	_fading.erase(name)
	var mi: MeshInstance3D = _rois.get(name)
	if mi == null:
		return
	mi.material_override = _orig_mats.get(name, mi.material_override)
	mi.visible = false


static func _alpha(m: ShaderMaterial) -> float:
	var c: Color = m.get_shader_parameter("color")
	return c.a


static func _set_alpha(a: float, m: ShaderMaterial) -> void:
	var c: Color = m.get_shader_parameter("color")
	c.a = a
	m.set_shader_parameter("color", c)


## Killing a tween drops its "finished" callbacks, so retire anything still fading out here.
func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	for name in _fading.duplicate():
		_unlight(name)


# --------------------------------------------------------------------------- narration

func panel_text() -> String:
	var s := slide()
	var title := "THE FLY BRAIN"
	var count := "SLIDE %02d/%02d" % [index + 1, SLIDES.size()]
	# monospace, so padding with spaces right-aligns the counter against the end of the rule
	var t := "[color=#%s]%s[/color]%s[color=#%s]%s[/color]\n" % [UITheme.H_HI, title,
		" ".repeat(RULE_CHARS - title.length() - count.length()), UITheme.H_DIM, count]
	t += _rule() + "\n"
	t += "[font_size=30][b]%s[/b][/font_size]\n" % s.title.to_upper()
	t += "[color=#%s][i]%s[/i][/color]\n" % [UITheme.H_SUB, s.sci]
	if s.has("abbr"):
		t += "[color=#%s]%s[/color]\n" % [UITheme.H_HI, s.abbr]
	t += "\n%s\n" % s.body
	if s.get("credits", false):
		t += _credits_text()
	t += "\n%s\n" % _progress_bar()
	if s.get("credits", false):
		t += "[color=#%s]→ START OVER[/color]" % UITheme.H_HI
	else:
		t += "[color=#%s]← → SLIDES[/color]" % UITheme.H_DIM
	return t


const RULE_CHARS := 50   ## panel text width in monospace characters


static func _rule() -> String:
	return "[color=#%s]%s[/color]\n" % [UITheme.H_FAINT, "─".repeat(RULE_CHARS)]


## The attributions live here, on the closing slide, rather than on screen the whole time.
func _credits_text() -> String:
	var t := "\n" + _rule()
	t += "[color=#%s]%d NEURONS · %d SKELETON SEGMENTS RENDERED[/color]\n\n" % [
		UITheme.H_SUB, _neurons.index.size(), _neurons.segment_count]
	for c in CREDITS:
		if c[0] == "":
			t += "[color=#%s]%s[/color]\n" % [UITheme.H_DIM, c[1]]
		else:
			t += "[color=#%s]%s[/color]  [color=#%s]%s[/color]\n" % [
				UITheme.H_HI, String(c[0]).to_upper(), UITheme.H_SUB, c[1]]
	t += "\n[color=#%s]The flashes are simulated activity: random regions are stimulated and spikes " % UITheme.H_DIM
	t += "spread across the real synaptic graph.[/color]\n"
	return t


## Segmented progress strip: slides seen are half-lit, the current one bright.
func _progress_bar() -> String:
	var out := ""
	for i in SLIDES.size():
		var c: String = UITheme.H_HI if i == index else (UITheme.H_HI + "66" if i < index else UITheme.H_FAINT)
		out += "[color=#%s]▮[/color]" % c
	return out
