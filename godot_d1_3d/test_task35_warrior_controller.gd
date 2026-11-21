extends SceneTree

# ==============================================================================
# Test: Task 5 - AAA Warrior Hero 3D Skeletal Mesh & Controller
# ==============================================================================

class MockBridge extends RefCounted:
	var cur_lvl = 1
	var pos_data = {"pos_x": 25.0, "pos_y": 25.0, "dir": 0, "anim_frame": 0, "action": "IDLE"}

	func get_current_level(): return cur_lvl
	func is_level_loading(): return false
	func get_dungeon_solidity_grid(): return PackedByteArray()
	func get_dungeon_grid(): return PackedInt32Array()
	func get_dungeon_special_grid(): return PackedInt32Array()
	func get_active_objects(): return []
	func get_dungeon_piece_texture(pid: int): return null
	func get_special_cel_texture(sid: int): return null
	func get_player_continuous_pos(): return pos_data
	func get_player_sprite_data(): return {"width": 0, "height": 0, "frame": 0, "dir": 0, "rgba": PackedByteArray()}
	func get_active_monsters_data(): return []

func _init():
	print("\n==================================================")
	print(" Testing Task 5: AAA Warrior 3D Controller        ")
	print("==================================================")

	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = sandbox_script.new()
	var bridge = MockBridge.new()
	sandbox.diablo_bridge = bridge
	root.add_child(sandbox)
	sandbox.setup_scene_nodes()

	print("\n[1/4] Verifying Safe Quality-Gated Default (Fallback Sprite)...")
	sandbox.update_player_entity(0.016)
	assert(sandbox.warrior_controller != null, "ERROR: Warrior3DController must exist!")
	assert(not sandbox.warrior_controller.visible, "ERROR: Warrior 3D controller must be HIDDEN by default!")
	assert(sandbox.player_sprite.visible, "ERROR: Player Sprite3D must be VISIBLE by default!")
	print("  PASS: Authentic 4K PBR fallback sprite active by default, 3D mesh safely muted!")

	print("\n[2/4] Verifying 8-Directional Orientation...")
	var wc = sandbox.warrior_controller
	# Set direction to West (dir=2 -> 90 degrees)
	bridge.pos_data["dir"] = 2
	for i in range(20):
		sandbox.update_player_entity(0.033)

	var current_deg = rad_to_deg(wc.rotation.y)
	assert(abs(current_deg - 90.0) < 5.0, "ERROR: Warrior should orient to 90 degrees! Got: %f" % current_deg)
	print("  PASS: Warrior smoothly oriented to %f degrees (West)!" % current_deg)

	print("\n[3/4] Verifying Action State Machine (WALK, ATTACK, HIT)...")
	# Test WALK
	bridge.pos_data["action"] = "WALK"
	sandbox.update_player_entity(0.016)
	assert(wc.current_action == "WALK", "ERROR: Action state must update to WALK!")
	print("  PASS: Action state synchronized to WALK!")

	# Test ATTACK
	bridge.pos_data["action"] = "ATTACK"
	sandbox.update_player_entity(0.016)
	assert(wc.current_action == "ATTACK", "ERROR: Action state must update to ATTACK!")
	print("  PASS: Action state synchronized to ATTACK!")

	# Test HIT
	bridge.pos_data["action"] = "HIT"
	sandbox.update_player_entity(0.016)
	assert(wc.current_action == "HIT", "ERROR: Action state must update to HIT!")
	print("  PASS: Action state synchronized to HIT!")

	print("\n[4/4] Verifying Quality Gated Activation...")
	# Without certification: enabling 3D must NOT activate
	sandbox.warrior_3d_enabled = true
	sandbox.update_player_entity(0.016)
	assert(not sandbox.warrior_controller.visible, "ERROR: Uncertified warrior 3D must remain hidden!")

	# With certification: activating 3D must show mesh and hide sprite
	sandbox.set_mesh_aaa_certified("res://assets/models/aaa/characters/warrior_gothic.res", true)
	sandbox.update_player_entity(0.016)
	assert(sandbox.warrior_controller.visible, "ERROR: Certified warrior 3D must be visible!")
	assert(not sandbox.player_sprite.visible, "ERROR: Sprite must hide when 3D warrior is active!")
	print("  PASS: Certified AAA Warrior activation verified!")

	print("\n==================================================")
	print(" ALL TASK 5 WARRIOR 3D CONTROLLER CHECKS PASSED! ")
	print("==================================================")
	quit(0)
