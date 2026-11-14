extends "res://scripts/entities/monster_3d_controller.gd"
class_name Leoric3DController

# ==============================================================================
# Task 4.4: King Leoric (A Csontváz Király) Boss Controller
# Custom high-presence boss behavior: royal unholy aura, broadsword cleaving
# impacts, necromantic resurrection wave, and spectral soul mist.
# ==============================================================================

signal sword_impact(pos: Vector3)
signal resurrection_pulse(pos: Vector3)
signal leoric_voice(quote: String)

var spectral_particles: CPUParticles3D = null
var unholy_aura_light: OmniLight3D = null
var time_alive: float = 0.0
var pulse_timer: float = 0.0
var last_attack_action: bool = false
var has_threatened: bool = false

func _init() -> void:
	monster_type = "LEORIC"
	setup_boss_visuals()

func _ready() -> void:
	super._ready()
	setup_boss_visuals()

func setup_boss_visuals() -> void:
	if unholy_aura_light != null:
		return

	# 1. Royal Unholy Amethyst / Purple Forward+ Aura Light
	unholy_aura_light = OmniLight3D.new()
	unholy_aura_light.name = "LeoricAuraLight"
	unholy_aura_light.light_color = Color(0.78, 0.16, 0.92)
	unholy_aura_light.light_energy = 2.6
	unholy_aura_light.omni_range = 6.0
	unholy_aura_light.omni_attenuation = 1.3
	unholy_aura_light.position = Vector3(0, 1.4, 0)
	add_child(unholy_aura_light)

	# 2. Rising Spectral Souls & Tomb Mist Emitter
	spectral_particles = CPUParticles3D.new()
	spectral_particles.name = "LeoricSpectralMist"
	spectral_particles.amount = 22
	spectral_particles.lifetime = 1.6
	spectral_particles.preprocess = 0.3
	spectral_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	spectral_particles.emission_sphere_radius = 0.55
	spectral_particles.direction = Vector3(0, 1, 0)
	spectral_particles.spread = 25.0
	spectral_particles.gravity = Vector3(0, 0.4, 0) # Rising ethereal lift
	spectral_particles.initial_velocity_min = 0.4
	spectral_particles.initial_velocity_max = 1.1
	spectral_particles.color = Color(0.42, 0.85, 0.75, 0.65) # Eerie spectral turquoise/cyan
	spectral_particles.position = Vector3(0, 0.6, 0)
	add_child(spectral_particles)

func set_action(action: String) -> void:
	var prev = current_action
	super.set_action(action)

	# Detect transition into heavy broadsword attack
	if action == "ATTACK" and prev != "ATTACK":
		trigger_greatsword_windup()
	elif action != "ATTACK":
		last_attack_action = false

func trigger_greatsword_windup() -> void:
	last_attack_action = true
	# Massive two-handed greatsword sweeping strike timing (0.28s)
	if is_inside_tree():
		var tw = create_tween()
		tw.tween_interval(0.28)
		tw.tween_callback(func():
			if not is_dead and is_instance_valid(self):
				var p = global_position if is_inside_tree() else position
				sword_impact.emit(p)
		)
	else:
		sword_impact.emit(position)

func trigger_resurrection_wave() -> void:
	if is_dead:
		return
	var p = position
	if is_inside_tree():
		p = global_position
	resurrection_pulse.emit(p)
	# Radial burst flare on the unholy light
	if unholy_aura_light and is_inside_tree():
		var tw = create_tween()
		tw.tween_property(unholy_aura_light, "light_energy", 4.2, 0.15)
		tw.tween_property(unholy_aura_light, "light_energy", 2.6, 0.45)

func update_animation(delta: float, is_moving: bool) -> void:
	super.update_animation(delta, is_moving)
	time_alive += delta

	# 1. Undulating Royal Unholy Aura Flicker
	if unholy_aura_light and is_instance_valid(unholy_aura_light):
		var pulse = 1.0 + 0.18 * sin(time_alive * 5.7) * cos(time_alive * 2.8)
		unholy_aura_light.light_energy = 2.6 * pulse

	# 2. Periodic Necromantic Resurrection Pulse (every 7 seconds)
	if not is_dead:
		pulse_timer += delta
		if pulse_timer >= 7.0:
			pulse_timer = 0.0
			trigger_resurrection_wave()

	# 3. Death sequence: burst spectral souls into the air, extinguish royal light
	if is_dead and unholy_aura_light and unholy_aura_light.light_energy > 0.0:
		unholy_aura_light.light_energy = maxf(0.0, unholy_aura_light.light_energy - delta * 3.0)
		if spectral_particles:
			spectral_particles.gravity = Vector3(0, 2.5, 0)
			spectral_particles.initial_velocity_max = 2.5
