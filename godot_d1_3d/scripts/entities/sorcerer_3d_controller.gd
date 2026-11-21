extends Node3D
class_name Sorcerer3DController

# ==============================================================================
# Task 4.6: AAA Sorcerer Hero 3D Controller
# Manages 3D skeletal animations, mystic staff raising spell casts,
# mana shield spherical shimmering energy barrier, and DevilutionX logic sync.
# ==============================================================================

signal action_finished(action_name: String)
signal spell_cast_started(pos: Vector3)

@export var move_speed: float = 3.5
@export var turn_speed: float = 14.0

var current_action: String = "IDLE"
var target_direction: int = 0
var anim_player: AnimationPlayer = null
var mesh_root: Node3D = null

# Mana Shield Visual Barrier
var mana_shield_active: bool = false
var mana_shield_mesh: MeshInstance3D = null
var cast_blend: float = 0.0
var hit_recoil: float = 0.0
var walk_cycle_phase: float = 0.0

func _init() -> void:
	setup_mana_shield()

func _ready() -> void:
	mesh_root = get_node_or_null("MeshRoot")
	anim_player = get_node_or_null("AnimationPlayer")
	setup_mana_shield()

func setup_mana_shield() -> void:
	if mana_shield_mesh != null:
		return
	mana_shield_mesh = MeshInstance3D.new()
	mana_shield_mesh.name = "ManaShieldSphere"
	var sphere = SphereMesh.new()
	sphere.radius = 0.85
	sphere.height = 1.70
	mana_shield_mesh.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.20, 0.65, 1.0, 0.28) # Shimmering translucent blue
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mana_shield_mesh.material_override = mat
	mana_shield_mesh.position = Vector3(0, 1.0, 0)
	mana_shield_mesh.visible = false
	add_child(mana_shield_mesh)

func set_mana_shield(active: bool) -> void:
	mana_shield_active = active
	if mana_shield_mesh:
		mana_shield_mesh.visible = active

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

	# 2. Shimmering Mana Shield Pulse
	if mana_shield_active and mana_shield_mesh and mana_shield_mesh.visible:
		var pulse = 0.85 + 0.04 * sin(Time.get_ticks_msec() * 0.008)
		mana_shield_mesh.scale = Vector3(pulse, pulse, pulse)

	# 3. Action State Synchronization
	if current_action == "WALK" or is_moving:
		walk_cycle_phase += delta * 9.5
		if mesh_root:
			mesh_root.position.y = abs(sin(walk_cycle_phase)) * 0.032
			mesh_root.rotation.z = sin(walk_cycle_phase) * 0.02
	elif current_action == "ATTACK": # In Sorcerer, attack = staff raise & spell casting
		cast_blend = min(1.0, cast_blend + delta * 7.5)
		if mesh_root:
			# Raising staff skyward
			mesh_root.position.y = sin(cast_blend * PI) * 0.08
			mesh_root.rotation.x = -sin(cast_blend * PI) * 0.15
		if cast_blend >= 0.4 and not is_moving:
			spell_cast_started.emit(global_position + Vector3(0, 1.4, 0))
		if cast_blend >= 1.0:
			cast_blend = 0.0
			set_action("IDLE")
			action_finished.emit("ATTACK")
	elif current_action == "HIT":
		hit_recoil = min(1.0, hit_recoil + delta * 12.0)
		if mesh_root:
			mesh_root.position.z = -sin(hit_recoil * PI) * 0.09
		if hit_recoil >= 1.0:
			hit_recoil = 0.0
			set_action("IDLE")
			action_finished.emit("HIT")
	else:
		# IDLE mystic breathing
		if mesh_root:
			mesh_root.position.y = lerp(mesh_root.position.y, sin(Time.get_ticks_msec() * 0.003) * 0.015, delta * 5.0)
			mesh_root.rotation.z = lerp(mesh_root.rotation.z, 0.0, delta * 6.0)
