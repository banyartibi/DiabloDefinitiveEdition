extends Node3D
class_name Warrior3DController

# ==============================================================================
# AAA Warrior Hero 3D Controller
# Manages 3D skeletal animations, smooth 8-directional orientation,
# action state machine, and sync with DevilutionX game logic.
# ==============================================================================

signal action_finished(action_name: String)

@export var move_speed: float = 3.5
@export var turn_speed: float = 16.0

var current_action: String = "IDLE"
var target_direction: int = 0
var anim_player: AnimationPlayer = null
var mesh_root: Node3D = null

# Procedural animation parameters for smooth responsiveness
var walk_cycle_phase: float = 0.0
var attack_blend: float = 0.0
var hit_recoil: float = 0.0

func _ready():
	mesh_root = get_node_or_null("MeshRoot")
	anim_player = get_node_or_null("AnimationPlayer")

func set_direction(dir_idx: int):
	target_direction = clampi(dir_idx, 0, 7)

func set_action(action: String):
	if action == current_action and action != "ATTACK" and action != "HIT":
		return
	current_action = action
	if anim_player:
		var anim_name = action.to_lower()
		if anim_player.has_animation(anim_name):
			anim_player.play(anim_name)

func update_animation(delta: float, velocity: Vector3, is_moving: bool):
	# 1. Smooth 8-Directional Orientation
	var target_yaw_rad = deg_to_rad(float(target_direction) * 45.0)
	rotation.y = lerp_angle(rotation.y, target_yaw_rad, delta * turn_speed)

	# 2. Action State Synchronization
	if current_action == "WALK" or is_moving:
		walk_cycle_phase += delta * 10.0
		if mesh_root:
			# Natural walk bobbing and slight stride tilt
			mesh_root.position.y = abs(sin(walk_cycle_phase)) * 0.04
			mesh_root.rotation.z = sin(walk_cycle_phase) * 0.03
	elif current_action == "ATTACK":
		attack_blend = min(1.0, attack_blend + delta * 8.0)
		if mesh_root:
			mesh_root.position.z = sin(attack_blend * PI) * 0.12
		if attack_blend >= 1.0:
			attack_blend = 0.0
			set_action("IDLE")
			action_finished.emit("ATTACK")
	elif current_action == "HIT":
		hit_recoil = min(1.0, hit_recoil + delta * 12.0)
		if mesh_root:
			mesh_root.position.z = -sin(hit_recoil * PI) * 0.08
		if hit_recoil >= 1.0:
			hit_recoil = 0.0
			set_action("IDLE")
			action_finished.emit("HIT")
	else:
		# IDLE breathing motion
		if mesh_root:
			mesh_root.position.y = lerp(mesh_root.position.y, sin(Time.get_ticks_msec() * 0.003) * 0.015, delta * 6.0)
			mesh_root.rotation.z = lerp(mesh_root.rotation.z, 0.0, delta * 8.0)
