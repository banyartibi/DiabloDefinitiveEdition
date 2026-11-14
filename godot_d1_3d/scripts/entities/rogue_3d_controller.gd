extends Node3D
class_name Rogue3DController

# ==============================================================================
# Task 4.6: AAA Rogue Hero 3D Controller
# Manages 3D skeletal animations, agile 8-directional orientation,
# bow aiming and draw timing, and synchronization with DevilutionX logic.
# ==============================================================================

signal action_finished(action_name: String)
signal arrow_fired(pos: Vector3, dir: Vector3)

@export var move_speed: float = 4.0
@export var turn_speed: float = 18.0

var current_action: String = "IDLE"
var target_direction: int = 0
var anim_player: AnimationPlayer = null
var mesh_root: Node3D = null

# Procedural animation parameters for nimble ranger movement
var walk_cycle_phase: float = 0.0
var bow_draw_blend: float = 0.0
var hit_recoil: float = 0.0

func _ready() -> void:
	mesh_root = get_node_or_null("MeshRoot")
	anim_player = get_node_or_null("AnimationPlayer")

func set_direction(dir_idx: int) -> void:
	target_direction = clampi(dir_idx, 0, 7)

func set_action(action: String) -> void:
	if action == current_action and action != "ATTACK" and action != "HIT":
		return
	current_action = action
	if anim_player:
		var anim_name = action.to_lower()
		if anim_player.has_animation(anim_name):
			anim_player.play(anim_name)

func update_animation(delta: float, velocity: Vector3, is_moving: bool) -> void:
	# 1. Smooth 8-Directional Orientation
	var target_yaw_rad = deg_to_rad(float(target_direction) * 45.0)
	rotation.y = lerp_angle(rotation.y, target_yaw_rad, delta * turn_speed)

	# 2. Action State Synchronization
	if current_action == "WALK" or is_moving:
		walk_cycle_phase += delta * 12.0
		if mesh_root:
			# Agile, quick stride with slight forward lean
			mesh_root.position.y = abs(sin(walk_cycle_phase)) * 0.03
			mesh_root.rotation.z = sin(walk_cycle_phase) * 0.025
			mesh_root.rotation.x = deg_to_rad(4.0) # Aerodynamic lean
	elif current_action == "ATTACK":
		bow_draw_blend = min(1.0, bow_draw_blend + delta * 9.0)
		if mesh_root:
			# Bow draw recoil
			mesh_root.position.z = -sin(bow_draw_blend * PI) * 0.06
		if bow_draw_blend >= 0.5 and not is_moving:
			# Release point
			pass
		if bow_draw_blend >= 1.0:
			bow_draw_blend = 0.0
			set_action("IDLE")
			action_finished.emit("ATTACK")
			var shoot_dir = Vector3(sin(rotation.y), 0, cos(rotation.y))
			arrow_fired.emit(global_position + Vector3(0, 1.2, 0), shoot_dir)
	elif current_action == "HIT":
		hit_recoil = min(1.0, hit_recoil + delta * 14.0)
		if mesh_root:
			mesh_root.position.z = -sin(hit_recoil * PI) * 0.07
		if hit_recoil >= 1.0:
			hit_recoil = 0.0
			set_action("IDLE")
			action_finished.emit("HIT")
	else:
		# IDLE nimble breathing
		if mesh_root:
			mesh_root.position.y = lerp(mesh_root.position.y, sin(Time.get_ticks_msec() * 0.0035) * 0.012, delta * 6.0)
			mesh_root.rotation.z = lerp(mesh_root.rotation.z, 0.0, delta * 8.0)
			mesh_root.rotation.x = lerp(mesh_root.rotation.x, 0.0, delta * 8.0)
