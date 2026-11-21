extends "res://scripts/entities/monster_3d_controller.gd"
class_name Butcher3DController

# ==============================================================================
# Task 4.3: The Butcher (A Hentes) Boss Controller
# Custom high-presence boss behavior: heavy cleaver attack timings,
# blood drip trails, footstep impacts, and demonic Forward+ red aura.
# ==============================================================================

signal cleaver_impact(pos: Vector3)
signal butcher_shout()

var blood_particles: CPUParticles3D = null
var boss_aura_light: OmniLight3D = null
var time_alive: float = 0.0
var step_timer: float = 0.0
var last_attack_action: bool = false
var has_shouted: bool = false

func _init() -> void:
	monster_type = "BUTCHER"
	setup_boss_visuals()

func _ready() -> void:
	super._ready()
	setup_boss_visuals()

func setup_boss_visuals() -> void:
	if boss_aura_light != null:
		return
	# 1. Demonic Blood-Red Forward+ Aura Light
	boss_aura_light = OmniLight3D.new()
	boss_aura_light.name = "ButcherAuraLight"
	boss_aura_light.light_color = Color(0.92, 0.08, 0.04)
	boss_aura_light.light_energy = 2.4
	boss_aura_light.omni_range = 5.5
	boss_aura_light.omni_attenuation = 1.2
	boss_aura_light.position = Vector3(0, 1.2, 0)
	add_child(boss_aura_light)

	# 2. Dripping Fresh Blood Trail Emitter
	blood_particles = CPUParticles3D.new()
	blood_particles.name = "ButcherBloodTrail"
	blood_particles.amount = 18
	blood_particles.lifetime = 1.2
	blood_particles.preprocess = 0.2
	blood_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	blood_particles.emission_sphere_radius = 0.35
	blood_particles.direction = Vector3(0, -1, 0)
	blood_particles.spread = 15.0
	blood_particles.gravity = Vector3(0, -9.8, 0)
	blood_particles.initial_velocity_min = 0.2
	blood_particles.initial_velocity_max = 0.6
	blood_particles.color = Color(0.72, 0.02, 0.02, 0.90)
	blood_particles.position = Vector3(0, 0.8, 0)
	add_child(blood_particles)

func set_action(action: String) -> void:
	var prev = current_action
	super.set_action(action)

	# Detect transition into attack
	if action == "ATTACK" and prev != "ATTACK":
		trigger_cleaver_windup()
	elif action != "ATTACK":
		last_attack_action = false

func trigger_cleaver_windup() -> void:
	last_attack_action = true
	# Cleaver snap chop timing: after heavy windup, signal screen impact
	var tw = create_tween()
	tw.tween_interval(0.24)
	tw.tween_callback(func():
		if not is_dead and is_instance_valid(self):
			cleaver_impact.emit(global_position)
	)

func update_animation(delta: float, is_moving: bool) -> void:
	super.update_animation(delta, is_moving)
	time_alive += delta

	# 1. Pulsing Demonic Aura Flicker
	if boss_aura_light and is_instance_valid(boss_aura_light):
		var flicker = 1.0 + 0.15 * sin(time_alive * 9.3) * cos(time_alive * 4.1)
		boss_aura_light.light_energy = 2.4 * flicker

	# 2. Heavy Footstep Impacts & Blood Trails
	if is_moving and not is_dead:
		step_timer += delta
		if blood_particles:
			blood_particles.emitting = true
		# Heavy thudding footsteps every 0.38s
		if step_timer >= 0.38:
			step_timer = 0.0
	else:
		step_timer = 0.0
		if blood_particles and not is_dead:
			blood_particles.emitting = false

	# 3. Death transition: extinguish demonic aura and burst blood pool
	if is_dead:
		if boss_aura_light:
			boss_aura_light.light_energy = maxf(0.0, boss_aura_light.light_energy - delta * 3.0)
		if blood_particles:
			blood_particles.amount = 32
			blood_particles.spread = 75.0
			blood_particles.initial_velocity_max = 2.5
