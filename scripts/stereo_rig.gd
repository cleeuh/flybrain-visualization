class_name StereoRig
extends Control
## Side-by-side stereo output for 3D display walls.
##
## Renders the shared 3D world twice (left / right eye) into SubViewports with
## off-axis (asymmetric-frustum) projections and composites them side by side.
##   HALF  - one window, each eye squeezed into half the width (3D TV / most walls)
##   FULL  - window is two frames wide, each eye at full resolution (dual-output walls)
##   MONO  - single camera, no stereo

enum Mode { HALF, FULL, MONO }

@export var mode: Mode = Mode.HALF
@export var swap_eyes := false
## Eye separation as a fraction of the convergence distance (1/30 ~ 6.5 cm eyes at 2 m).
@export var ipd_ratio := 1.0 / 30.0
## Multiplier on the target distance to place the zero-parallax plane.
@export var convergence_factor := 1.0
@export var hfov_deg := 70.0
@export var near := 2.0
@export var far := 20000.0

## Node3D whose global transform is the "head" (between the eyes).
var head: Node3D
## Distance from head to the object of interest; sets convergence.
var target_distance := 1000.0

var _views: Array[SubViewport] = []
var _cams: Array[Camera3D] = []
var _rects: Array[TextureRect] = []
var _ui_layers: Array[CanvasLayer] = []


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
		var tr := TextureRect.new()
		tr.texture = vp.get_texture()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
		_views.append(vp)
		_cams.append(cam)
		_rects.append(tr)
		_ui_layers.append(ui)
	get_viewport().size_changed.connect(_layout)
	_layout()


## Per-eye CanvasLayers: add UI here so it appears in both eyes at screen depth.
func ui_layers() -> Array[CanvasLayer]:
	return _ui_layers


func set_mode(m: Mode) -> void:
	mode = m
	_layout()


func cycle_mode() -> void:
	set_mode((mode + 1) % 3 as Mode)


func mode_name() -> String:
	return ["SBS half", "SBS full", "mono"][mode]


func _layout() -> void:
	var win := get_viewport().get_visible_rect().size
	if mode == Mode.MONO:
		_views[0].size = Vector2i(win)
		_rects[0].position = Vector2.ZERO
		_rects[0].size = win
		_rects[1].visible = false
		_views[1].render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_rects[1].visible = true
	_views[1].render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var half := Vector2(win.x * 0.5, win.y)
	# eye frame resolution: full window res for HALF (then squeezed), half window for FULL
	var frame := Vector2i(win) if mode == Mode.HALF else Vector2i(half)
	for i in 2:
		_views[i].size = frame
		_rects[i].position = Vector2(half.x * i, 0)
		_rects[i].size = half


func _process(_dt: float) -> void:
	if head == null:
		return
	var xf := head.global_transform
	var conv := maxf(target_distance * convergence_factor, near * 2.0)
	var ipd := conv * ipd_ratio
	var size := 2.0 * near * tan(deg_to_rad(hfov_deg) * 0.5)   # near-plane width
	if mode == Mode.MONO:
		var c := _cams[0]
		c.projection = Camera3D.PROJECTION_PERSPECTIVE
		c.keep_aspect = Camera3D.KEEP_WIDTH
		c.fov = hfov_deg
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
		c.frustum_offset = Vector2(-eye * (ipd * 0.5) * near / conv, 0.0)
		c.global_transform = xf.translated(xf.basis.x * (eye * ipd * 0.5))
