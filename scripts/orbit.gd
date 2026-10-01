class_name OrbitRig
extends Node3D
## Orbit camera pivot: this node sits at the target; `head` is offset along +Z by `distance`.
## The tour frames each slide (goto + auto_rotate); the viewer can still orbit (drag, WASD)
## and zoom (wheel, Q/E) around that framing until the next slide takes over. The arrow keys
## belong to slide navigation.

@export var distance := 1600.0
@export var yaw_deg := 0.0
@export var pitch_deg := 0.0
@export var auto_rotate := true
@export var auto_rotate_speed := 6.0   # deg / s
@export var min_distance := 50.0
@export var max_distance := 8000.0

@onready var head: Node3D = $Head

var _dragging := false
var _yaw_target := 0.0
var _pitch_target := 0.0
var _dist_target := 0.0
var _pivot_target := Vector3.ZERO


func _ready() -> void:
	_yaw_target = yaw_deg
	_pitch_target = pitch_deg
	_dist_target = distance
	_pivot_target = position


## Smoothly fly to a framing (used by the story tour). Angles in degrees, pivot in scene units.
func goto(pivot: Vector3, yaw: float, pitch: float, dist: float) -> void:
	_pivot_target = pivot
	# Yaw accumulates freely (auto-rotate, drag), so aim for the equivalent angle nearest the
	# current one; otherwise the transition unwinds every full turn taken since the last slide.
	_yaw_target = yaw_deg + wrapf(yaw - yaw_deg, -180.0, 180.0)
	_pitch_target = clampf(pitch, -89, 89)
	_dist_target = clampf(dist, min_distance, max_distance)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			_dragging = e.pressed
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist_target *= 0.9
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist_target *= 1.1
	elif e is InputEventMouseMotion and _dragging:
		_yaw_target -= e.relative.x * 0.3
		_pitch_target = clampf(_pitch_target - e.relative.y * 0.3, -89, 89)
		auto_rotate = false
	elif e is InputEventPanGesture:
		_dist_target *= 1.0 + e.delta.y * 0.1


func _process(dt: float) -> void:
	var spd := 60.0 * dt
	if Input.is_key_pressed(KEY_A):
		_yaw_target += spd; auto_rotate = false
	if Input.is_key_pressed(KEY_D):
		_yaw_target -= spd; auto_rotate = false
	if Input.is_key_pressed(KEY_W):
		_pitch_target = clampf(_pitch_target + spd, -89, 89); auto_rotate = false
	if Input.is_key_pressed(KEY_S):
		_pitch_target = clampf(_pitch_target - spd, -89, 89); auto_rotate = false
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_PAGEUP):
		_dist_target *= 1.0 - dt
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_PAGEDOWN):
		_dist_target *= 1.0 + dt
	if auto_rotate:
		_yaw_target += auto_rotate_speed * dt
	_dist_target = clampf(_dist_target, min_distance, max_distance)

	var k := 1.0 - exp(-8.0 * dt)
	yaw_deg = lerpf(yaw_deg, _yaw_target, k)
	pitch_deg = lerpf(pitch_deg, _pitch_target, k)
	distance = lerpf(distance, _dist_target, k)
	position = position.lerp(_pivot_target, k)
	rotation_degrees = Vector3(pitch_deg, yaw_deg, 0)
	head.position = Vector3(0, 0, distance)
