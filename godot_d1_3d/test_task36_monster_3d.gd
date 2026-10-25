extends SceneTree

# ==============================================================================
# Test: Task 6 - First AAA Monster: The Skeleton Warrior Controller & Quality Gate
# ==============================================================================

class MockBridge extends RefCounted:
	var cur_lvl = 1
	var monsters = [
		{
			"id": 101,
			"pos_x": 20.0,
			"pos_y": 22.0,
			"dir": 0,
			"anim_frame": 0,
			"action": "IDLE",
			"hp": 24,
			"max_hp": 24,
			"name": "Skeleton",
			"is_alive": true
		}
	]

	func get_current_level(): return cur_lvl
	func is_level_loading(): return false
	func get_dungeon_solidity_grid(): return PackedByteArray()
	func get_dungeon_grid(): return PackedInt32Array()
	func get_dungeon_special_grid(): return PackedInt32Array()
	func get_active_objects(): return []
	func get_dungeon_piece_texture(pid: int): return null
	func get_special_cel_texture(sid: int): return null
	func get_player_continuous_pos(): return {"pos_x": 25.0, "pos_y": 25.0, "dir": 0, "anim_frame": 0}
	func get_player_sprite_data(): return {"width": 0, "height": 0, "frame": 0, "dir": 0, "rgba": PackedByteArray()}
	func get_active_monsters_data(): return monsters
	func get_monster_sprite_data(mid: int): return {"width": 0, "height": 0, "frame": 0, "dir": 0, "rgba": PackedByteArray()}

func _init():
	print("\n==================================================")
	print(" Testing Task 6: AAA Monster 3D Controller        ")
	print("==================================================")

	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = sandbox_script.new()
	var bridge = MockBridge.new()
	sandbox.diablo_bridge = bridge
	root.add_child(sandbox)
	sandbox.setup_scene_nodes()

	print("\n[1/5] Verifying Safe Quality-Gated Default (Fallback Sprite)...")
	sandbox.update_monster_entities(0.016)
	var m_node = sandbox.monster_instances.get(101, null)
	assert(m_node != null, "ERROR: Monster node 101 must exist!")
	var mc = m_node.get_node_or_null("Monster3DController")
	var sprite = m_node.get_node_or_null("MonsterSprite3D")
	assert(mc != null, "ERROR: Monster3DController must exist!")
	assert(not mc.visible, "ERROR: Monster 3D controller must be HIDDEN by default!")
	assert(sprite.visible, "ERROR: Monster Sprite3D must be VISIBLE by default!")
	print("  PASS: Authentic 4K PBR fallback sprite active by default, 3D mesh safely muted!")

	print("\n[2/5] Verifying 8-Directional Orientation...")
	bridge.monsters[0]["dir"] = 4 # North-West (4 * 45 = 180 degrees)
	for i in range(25):
		sandbox.update_monster_entities(0.033)

	var current_deg = rad_to_deg(mc.rotation.y)
	var diff_rad = abs(angle_difference(mc.rotation.y, deg_to_rad(180.0)))
	assert(diff_rad < deg_to_rad(5.0), "ERROR: Monster should orient to 180 degrees! Got: %f" % current_deg)
	print("  PASS: Monster smoothly oriented to %f degrees (180 deg target)!" % current_deg)

	print("\n[3/5] Verifying Action State Machine (WALK, ATTACK, HIT)...")
	bridge.monsters[0]["action"] = "WALK"
	sandbox.update_monster_entities(0.016)
	assert(mc.current_action == "WALK", "ERROR: Action state must update to WALK!")
	print("  PASS: Action state synchronized to WALK!")

	bridge.monsters[0]["action"] = "ATTACK"
	sandbox.update_monster_entities(0.016)
	assert(mc.current_action == "ATTACK", "ERROR: Action state must update to ATTACK!")
	print("  PASS: Action state synchronized to ATTACK!")

	bridge.monsters[0]["action"] = "HIT"
	sandbox.update_monster_entities(0.016)
	assert(mc.current_action == "HIT", "ERROR: Action state must update to HIT!")
	print("  PASS: Action state synchronized to HIT!")

	print("\n[4/5] Verifying Collapse-to-Bones Physics on Death...")
	bridge.monsters[0]["hp"] = 0
	bridge.monsters[0]["action"] = "DEATH"
	sandbox.update_monster_entities(0.016)
	assert(mc.is_dead, "ERROR: Monster controller must register death when HP <= 0!")
	assert(mc.current_action == "DEATH", "ERROR: Action state must update to DEATH!")

	# Simulate death collapse over time
	for i in range(20):
		sandbox.update_monster_entities(0.033)

	assert(mc.death_progress > 0.5, "ERROR: Death progress must advance towards 1.0! Got: %f" % mc.death_progress)
	assert(mc.mesh_root.rotation.x < -0.5, "ERROR: Monster mesh must tilt down into collapse on death! Got: %f" % mc.mesh_root.rotation.x)
	print("  PASS: Collapse-to-bones physics triggered smoothly (progress: %0.2f, tilt: %0.2f rad)!" % [mc.death_progress, mc.mesh_root.rotation.x])

	print("\n[5/5] Verifying Quality Gated Activation...")
	# Reset monster for testing activation
	bridge.monsters[0]["hp"] = 24
	bridge.monsters[0]["action"] = "IDLE"
	mc.is_dead = false
	mc.death_progress = 0.0

	# Without certification: enabling 3D must NOT activate
	sandbox.monsters_3d_enabled = true
	sandbox.update_monster_entities(0.016)
	assert(not mc.visible, "ERROR: Uncertified monster 3D must remain hidden!")

	# With certification: activating 3D must show mesh and hide sprite
	sandbox.set_mesh_aaa_certified("res://assets/models/aaa/monsters/skeleton_gothic.res", true)
	sandbox.update_monster_entities(0.016)
	assert(mc.visible, "ERROR: Certified monster 3D must be visible!")
	assert(not sprite.visible, "ERROR: Sprite must hide when 3D monster is active!")
	print("  PASS: Certified AAA Monster activation verified!")

	print("\n==================================================")
	print(" ALL TASK 6 MONSTER 3D CONTROLLER CHECKS PASSED!  ")
	print("==================================================")
	quit(0)
