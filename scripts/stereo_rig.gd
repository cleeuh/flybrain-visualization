class_name StereoRig
extends Control
## Stereo output for 3D display walls.
##
## Renders the shared 3D world twice (left / right eye) into SubViewports with
## off-axis (asymmetric-frustum) projections, then packs both into the window with
## shaders/stereo_composite.gdshader in the format the display expects:
##   SBS_HALF     one frame, eyes squeezed side by side        ("single input" 3D TVs / walls)
##   SBS_FULL     window two frames wide, each eye full-res     (dual-output walls, or one 2x-wide input)
##   MONO         single camera

enum Mode { SBS_HALF, SBS_FULL, MONO }
const MODE_NAMES := ["SBS half", "SBS full", "mono"]
const MODE_KEYS := {"half": Mode.SBS_HALF, "sbs": Mode.SBS_HALF, "full": Mode.SBS_FULL,
	"mono": Mode.MONO}

@export var mode: Mode = Mode.SBS_HALF
@export var swap_eyes := false
## Eye separation as a fraction of the convergence distance (1/30 ~ 6.5 cm eyes at 2 m).
@export var ipd_ratio := 1.0 / 30.0
## Multiplier on the target distance to place the zero-parallax plane.
@export var convergence_factor := 1.0
@export var hfov_deg := 70.0
## Fraction of the frame width to push the rendered image left, so the story panel on the
## right does not sit on top of the subject. Lens shift, not a camera move, so it survives
## the rig rotating.
var view_shift := 0.0
@export var near := 2.0
@export var far := 20000.0

## Node3D whose global transform is the "head" (between the eyes).
var head: Node3D
## Distance from head to the object of interest; sets convergence.
var target_distance := 1000.0

var _views: Array[SubViewport] = []
var _cams: Array[Camera3D] = []
var _ui_layers: Array[CanvasLayer] = []
var _out: ColorRect
var _mat: ShaderMaterial


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 2:
		var vp := SubViewport.new()
		vp.world_3d = get_viewport().world_3d
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.msaa_3d = Viewport.MSAA_4X
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		var cam := Camera3D.new()
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.near = near
		cam.far = far
		vp.add_child(cam)
		var ui := CanvasLayer.new()
		vp.add_child(ui)
		add_child(vp)
		_views.append(vp)
		_cams.append(cam)
		_ui_layers.append(ui)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/stereo_composite.gdshader")
	_mat.set_shader_parameter("left_eye", _views[0].get_texture())
	_mat.set_shader_parameter("right_eye", _views[1].get_texture())
	_out = ColorRect.new()
	_out.material = _mat
	_out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_out.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_out)
	get_viewport().size_changed.connect(_layout)
	_layout()


## Per-eye CanvasLayers: add UI here so it appears in both eyes at screen depth.
func ui_layers() -> Array[CanvasLayer]:
	return _ui_layers


func set_mode(m: Mode) -> void:
	mode = m
	_layout()


func cycle_mode() -> void:
	set_mode((mode + 1) % Mode.size() as Mode)


func mode_name() -> String:
	return MODE_NAMES[mode]


## Aspect ratio of one rendered eye image (before any display un-squeeze).
func eye_aspect() -> float:
	var vp := _views[0].size if not _views.is_empty() else Vector2i(1920, 1080)
	return float(vp.x) / maxf(float(vp.y), 1.0)


func _layout() -> void:
	var win := Vector2i(get_viewport().get_visible_rect().size)
	# Each eye is rendered at the resolution it will finally be shown at, then the composite
	# shader packs the two. SBS half renders full-res so the display's un-squeeze restores
	# the correct aspect.
	var frame := win
	if mode == Mode.SBS_FULL:
		frame = Vector2i(win.x / 2, win.y)
	for vp in _views:
		vp.size = frame
	_views[1].render_target_update_mode = SubViewport.UPDATE_DISABLED if mode == Mode.MONO else SubViewport.UPDATE_ALWAYS
	var pattern: int = {Mode.SBS_HALF: 0, Mode.SBS_FULL: 0, Mode.MONO: 1}[mode]
	_mat.set_shader_parameter("pattern", pattern)


func _process(_dt: float) -> void:
	if head == null:
		return
	var xf := head.global_transform
	var conv := maxf(target_distance * convergence_factor, near * 2.0)
	var ipd := conv * ipd_ratio
	var size := 2.0 * near * tan(deg_to_rad(hfov_deg) * 0.5)   # near-plane width
	var shift := view_shift * size
	if mode == Mode.MONO:
		var c := _cams[0]
		c.projection = Camera3D.PROJECTION_FRUSTUM
		c.keep_aspect = Camera3D.KEEP_WIDTH
		c.size = size
		c.frustum_offset = Vector2(shift, 0.0)
		c.global_transform = xf
		return
	for i in 2:
		var eye := -1.0 if i == 0 else 1.0     # left = -1, right = +1
		if swap_eyes:
			eye = -eye
		var c := _cams[i]
		c.projection = Camera3D.PROJECTION_FRUSTUM
		c.keep_aspect = Camera3D.KEEP_WIDTH
		c.size = size
		# shift the near-plane window toward the convergence plane
		c.frustum_offset = Vector2(shift - eye * (ipd * 0.5) * near / conv, 0.0)
		c.global_transform = xf.translated(xf.basis.x * (eye * ipd * 0.5))

