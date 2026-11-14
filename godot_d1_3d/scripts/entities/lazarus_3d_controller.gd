extends "res://scripts/entities/monster_3d_controller.gd"
class_name Lazarus3DController

# ==============================================================================
# Task 4.5: Archbishop Lazarus Boss Controller
# Custom high-presence boss behavior: ceremonial demonic crimson aura,
# ritual ember circle, Hellfire orb casting pulses, and teleportation shimmer.
# ==============================================================================

signal hellfire_cast(pos: Vector3)
signal teleport_shimmer(pos: Vector3)

var ritual_particles: CPUParticles3D = null
var ritual_light: OmniLight3D = null
var time_alive: float = 0.0
var cast_timer: float = 0.0
var last_attack_action: bool = false

func _init() -> void:
	monster_type = "LAZARUS"
	setup_boss_visuals()

func _ready() -> void:
	super._ready()
	setup_boss_visuals()

func setup_boss_visuals() -> void:
	if ritual_light != null:
		return

	# 1. Ceremonial Blood-Orange / Crimson Forward+ Ritual Light
	ritual_light = OmniLight3D.new()
	ritual_light.name = "LazarusRitualLight"
	ritual_light.light_color = Color(0.95, 0.32, 0.08)
	ritual_light.light_energy = 2.4
	ritual_light.omni_range = 5.5
	ritual_light.omni_attenuation = 1.3
	ritual_light.position = Vector3(0, 1.2, 0)
	add_child(ritual_light)

	# 2. Demonic Ritual Circle & Floating Ash Embers
	ritual_particles = CPUParticles3D.new()
	ritual_particles.name = "LazarusRitualEmbers"
	ritual_particles.amount = 20
	ritual_particles.lifetime = 1.4
	ritual_particles.preprocess = 0.2
	ritual_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	ritual_particles.emission_ring_radius = 0.8
	ritual_particles.emission_ring_inner_radius = 0.3
	ritual_particles.direction = Vector3(0, 1, 0)
	ritual_particles.spread = 20.0
	ritual_particles.gravity = Vector3(0, 0.25, 0)
	ritual_particles.initial_velocity_min = 0.3
	ritual_particles.initial_velocity_max = 0.8
	ritual_particles.color = Color(0.95, 0.40, 0.12, 0.80)
	ritual_particles.position = Vector3(0, 0.1, 0)
	add_child(ritual_particles)

func set_action(action: String) -> void:
	var prev = current_action
	super.set_action(action)

	# Detect transition into spellcast / attack
	if action == "ATTACK" and prev != "ATTACK":
		trigger_hellfire_windup()
	elif action != "ATTACK":
		last_attack_action = false

func trigger_hellfire_windup() -> void:
	last_attack_action = true
	# Spellcasting windup timing (0.22s)
	if is_inside_tree():
		var tw = create_tween()
		tw.tween_interval(0.22)
		tw.tween_callback(func():
			if not is_dead and is_instance_valid(self):
				var p = global_position if is_inside_tree() else position
				hellfire_cast.emit(p)
		)
	else:
		hellfire_cast.emit(position)

func update_animation(delta: float, is_moving: bool) -> void:
	super.update_animation(delta, is_moving)
	time_alive += delta

	# 1. Pulsing Ritual Light Intensity
	if ritual_light and is_instance_valid(ritual_light):
		var flicker = 1.0 + 0.14 * sin(time_alive * 8.2) * cos(time_alive * 4.3)
		ritual_light.light_energy = 2.4 * flicker

	# 2. Death sequence: sacrificial combustion
	if is_dead and ritual_light and ritual_light.light_energy > 0.0:
		ritual_light.light_energy = maxf(0.0, ritual_light.light_energy - delta * 2.8)
		if ritual_particles:
			ritual_particles.amount = 35
			ritual_particles.initial_velocity_max = 2.0
