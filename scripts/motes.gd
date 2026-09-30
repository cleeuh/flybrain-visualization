class_name Motes
extends GPUParticles3D
## A sparse field of faint drifting motes around the CNS. Pixel-sized points with no depth
## write, so they give the stereo image something to hang depth on in the empty space
## around the connectome without ever covering it. Scaled by the anim_level shader global.

const AMOUNT := 260
const LIFETIME := 24.0


func _ready() -> void:
	amount = AMOUNT
	lifetime = LIFETIME
	preprocess = LIFETIME
	local_coords = false
	visibility_aabb = AABB(Vector3(-2500, -2000, -2500), Vector3(5000, 4000, 6000))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1300, 900, 1700)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 14.0
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_scale = 6.0
	pm.turbulence_noise_speed_random = 0.3
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.06
	var ramp := Gradient.new()          # fade in and out over each mote's life
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.2, Color(1, 1, 1, 1))
	ramp.add_point(0.8, Color(1, 1, 1, 1))
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	pm.color_ramp = tex
	process_material = pm

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/mote.gdshader")
	var mesh := PointMesh.new()
	mesh.material = mat
	draw_pass_1 = mesh
