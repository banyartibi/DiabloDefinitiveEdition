extends "res://scripts/entities/monster_3d_controller.gd"
class_name Diablo3DController

# ==============================================================================
# Task 4.5: Diablo (The Lord of Terror) Final Boss Controller
# Custom high-presence boss behavior: incandescent hellfire aura,
# brimstone embers, heavy thunderous footsteps, and Apocalypse ground shatter.
# ==============================================================================

signal apocalypse_strike(pos: Vector3)
signal heavy_step(pos: Vector3)

var hellfire_particles: CPUParticles3D = null
var lord_aura_light: OmniLight3D = null
var time_alive: float = 0.0
var step_timer: float = 0.0
var last_attack_action: bool = false

func _init() -> void:
	monster_type = "DIABLO"
	setup_boss_visuals()

func _ready() -> void:
	super._ready()
	setup_boss_visuals()

func setup_boss_visuals() -> void:
	if lord_aura_light != null:
		return

	# 1. Incandescent Lord of Terror Forward+ Aura Light
	lord_aura_light = OmniLight3D.new()
	lord_aura_light.name = "DiabloAuraLight"
	lord_aura_light.light_color = Color(1.0, 0.16, 0.02)
	lord_aura_light.light_energy = 3.4
	lord_aura_light.omni_range = 8.5
	lord_aura_light.omni_attenuation = 1.15
	lord_aura_light.position = Vector3(0, 1.8, 0)
	add_child(lord_aura_light)

	# 2. Brimstone Ash & Hellfire Embers Emitter
	hellfire_particles = CPUParticles3D.new()
	hellfire_particles.name = "DiabloHellfireEmbers"
	hellfire_particles.amount = 32
	hellfire_particles.lifetime = 1.5
	hellfire_particles.preprocess = 0.2
	hellfire_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	hellfire_particles.emission_sphere_radius = 0.85
	hellfire_particles.direction = Vector3(0, 1, 0)
	hellfire_particles.spread = 30.0
	hellfire_particles.gravity = Vector3(0, 0.6, 0)
	hellfire_particles.initial_velocity_min = 0.5
	hellfire_particles.initial_velocity_max = 1.4
	hellfire_particles.color = Color(1.0, 0.35, 0.05, 0.90)
	hellfire_particles.position = Vector3(0, 0.8, 0)
	add_child(hellfire_particles)

func set_action(action: String) -> void:
	var prev = current_action
	super.set_action(action)

	# Detect transition into Apocalypse attack or claw sweep
	if action == "ATTACK" and prev != "ATTACK":
		trigger_apocalypse_windup()
	elif action != "ATTACK":
		last_attack_action = false

func trigger_apocalypse_windup() -> void:
	last_attack_action = true
	# Terrifying windup before cataclysmic ground strike (0.32s)
	if is_inside_tree():
		var tw = create_tween()
		tw.tween_interval(0.32)
		tw.tween_callback(func():
			if not is_dead and is_instance_valid(self):
				var p = global_position if is_inside_tree() else position
				apocalypse_strike.emit(p)
		)
	else:
		apocalypse_strike.emit(position)

func update_animation(delta: float, is_moving: bool) -> void:
	super.update_animation(delta, is_moving)
	time_alive += delta

	# 1. Deep Demonic Heartbeat Pulse
	if lord_aura_light and is_instance_valid(lord_aura_light):
		var heartbeat = 1.0 + 0.20 * sin(time_alive * 6.0) * cos(time_alive * 3.0)
		lord_aura_light.light_energy = 3.4 * heartbeat

	# 2. Thunderous Footstep Impacts
	if is_moving and not is_dead:
		step_timer += delta
		if step_timer >= 0.42:
			step_timer = 0.0
			heavy_step.emit(global_position)
	else:
		step_timer = 0.0

	# 3. Death sequence: Cataclysmic light implosion and fire storm
	if is_dead and lord_aura_light and lord_aura_light.light_energy > 0.0:
		lord_aura_light.light_energy = maxf(0.0, lord_aura_light.light_energy - delta * 2.0)
		if hellfire_particles:
			hellfire_particles.amount = 50
			hellfire_particles.initial_velocity_max = 3.0
