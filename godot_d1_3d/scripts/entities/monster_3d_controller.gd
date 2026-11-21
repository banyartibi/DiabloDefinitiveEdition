extends Node3D
class_name Monster3DController

# ==============================================================================
# AAA Monster 3D Controller (Skeleton Warrior / Undead / Bosses)
# Handles 3D skeletal reactions, directional orientation, attack chops,
# and collapse-to-bones physics on death.
# ==============================================================================

signal monster_died(m_id: int)

@export var turn_speed: float = 14.0

var monster_id: int = -1
var monster_type: String = "SKELETON"
var current_action: String = "IDLE"
var target_direction: int = 0
var anim_player: AnimationPlayer = null
var mesh_root: Node3D = null

var walk_phase: float = 0.0
var attack_blend: float = 0.0
var hit_blend: float = 0.0
var is_dead: bool = false
var death_progress: float = 0.0

func _ready():
	ensure_mesh_root()
	anim_player = get_node_or_null("AnimationPlayer")

func ensure_mesh_root():
	if mesh_root == null:
		mesh_root = get_node_or_null("MeshRoot")
	if mesh_root == null:
		mesh_root = Node3D.new()
		mesh_root.name = "MeshRoot"
		add_child(mesh_root)

func set_direction(dir_idx: int):
	target_direction = clampi(dir_idx, 0, 7)

func set_action(action: String):
	if is_dead:
		return
	if action == "DIE" or action == "DEATH":
		trigger_death()
		return
	if action == current_action and action != "ATTACK" and action != "HIT":
		return
	current_action = action
	if anim_player:
		var a_name = action.to_lower()
		if anim_player.has_animation(a_name):
			anim_player.play(a_name)

func trigger_death():
	is_dead = true
	current_action = "DEATH"
	death_progress = 0.0
	monster_died.emit(monster_id)

func update_animation(delta: float, is_moving: bool):
	ensure_mesh_root()
	# 1. Death collapse animation
	if is_dead:
		if death_progress < 1.0:
			death_progress = min(1.0, death_progress + delta * 3.5)
			if mesh_root:
				# Smooth collapse to ground plane
				mesh_root.position.y = lerp(mesh_root.position.y, 0.02, delta * 8.0)
				mesh_root.rotation.x = lerp(mesh_root.rotation.x, deg_to_rad(-80.0), delta * 8.0)
		return

	# 2. Smooth 8-Directional Orientation
	var target_yaw_rad = deg_to_rad(float(target_direction) * 45.0)
	rotation.y = lerp_angle(rotation.y, target_yaw_rad, delta * turn_speed)

	# 3. Movement & Attack State
	if current_action == "WALK" or is_moving:
		walk_phase += delta * 9.0
		if mesh_root:
			mesh_root.position.y = abs(sin(walk_phase)) * 0.035
			mesh_root.rotation.z = sin(walk_phase) * 0.04
	elif current_action == "ATTACK":
		attack_blend = min(1.0, attack_blend + delta * 9.0)
		if mesh_root:
			mesh_root.position.z = sin(attack_blend * PI) * 0.15
			mesh_root.rotation.x = sin(attack_blend * PI) * 0.20
		if attack_blend >= 1.0:
			attack_blend = 0.0
			set_action("IDLE")
	elif current_action == "HIT":
		hit_blend = min(1.0, hit_blend + delta * 14.0)
		if mesh_root:
			mesh_root.position.z = -sin(hit_blend * PI) * 0.09
		if hit_blend >= 1.0:
			hit_blend = 0.0
			set_action("IDLE")
	else:
		# IDLE subtle sway
		if mesh_root:
			mesh_root.position.y = lerp(mesh_root.position.y, 0.0, delta * 6.0)
			mesh_root.rotation.x = lerp(mesh_root.rotation.x, 0.0, delta * 6.0)
			mesh_root.rotation.z = lerp(mesh_root.rotation.z, 0.0, delta * 6.0)
