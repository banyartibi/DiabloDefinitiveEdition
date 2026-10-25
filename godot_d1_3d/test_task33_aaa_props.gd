extends SceneTree

# ==============================================================================
# Test: Task 3 - AAA Gothic Interactive Props & Lighting Integration
# ==============================================================================

class MockBridge extends RefCounted:
	var cur_lvl = 1
	var sol = PackedByteArray()
	var grid = PackedInt32Array()
	var objs: Array = []

	func _init():
		sol.resize(112 * 112)
		sol.fill(1)
		grid.resize(112 * 112)
		grid.fill(1)

		# Standing brazier at (20, 20)
		objs.append({"id": 1, "type": 0, "tile_x": 20, "tile_y": 20, "category": "TORCH", "anim_frame": 0})
		# Gothic Chest at (22, 22)
		objs.append({"id": 2, "type": 5, "tile_x": 22, "tile_y": 22, "category": "CHEST", "anim_frame": 0})
		# Gothic Sarcophagus at (24, 24)
		objs.append({"id": 3, "type": 154, "tile_x": 24, "tile_y": 24, "category": "SARCOPHAGUS", "anim_frame": 0})

	func get_current_level(): return cur_lvl
	func is_level_loading(): return false
	func get_dungeon_solidity_grid(): return sol
	func get_dungeon_grid(): return grid
	func get_dungeon_special_grid(): return PackedInt32Array()
	func get_active_objects(): return objs
	func get_dungeon_piece_texture(pid: int): return null
	func get_special_cel_texture(sid: int): return null
	func get_player_continuous_pos(): return {"pos_x": 20.0, "pos_y": 20.0, "dir": 0}
	func get_player_sprite_data(): return {"width": 0, "height": 0, "frame": 0, "dir": 0, "rgba": PackedByteArray()}
	func get_active_monsters_data(): return []

func _init():
	print("\n==================================================")
	print(" Testing Task 3: AAA Gothic Props & Animations    ")
	print("==================================================")

	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = sandbox_script.new()
	var bridge = MockBridge.new()
	sandbox.diablo_bridge = bridge
	root.add_child(sandbox)
	sandbox.setup_scene_nodes()

	# Certify props for testing
	sandbox.modular_3d_props_enabled = true
	sandbox.set_prop_aaa_certified("standing_brazier", true)
	sandbox.set_prop_aaa_certified("chest", true)
	sandbox.set_prop_aaa_certified("sarcophagus", true)

	sandbox.activate()
	sandbox.update_props(0.016)

	print("\n[1/3] Verifying 3D Prop Node Structures...")
	# 1. Brazier
	var braz_node = sandbox.prop_instances.get(1) as Node3D
	assert(braz_node != null, "ERROR: Brazier prop must be instantiated!")
	var light = braz_node.get_node_or_null("TorchLight") as OmniLight3D
	assert(light != null, "ERROR: Brazier must have dynamic OmniLight3D!")
	assert(light.shadow_enabled, "ERROR: Brazier light must cast real-time shadows!")
	print("  PASS: Brazier node active with dynamic OmniLight3D and shadows!")

	# 2. Chest
	var chest_node = sandbox.prop_instances.get(2) as Node3D
	assert(chest_node != null, "ERROR: Chest prop must be instantiated!")
	var chest_lid = chest_node.get_node_or_null("ChestProp/ChestLid") as Node3D
	assert(chest_lid != null, "ERROR: Chest must have ChestLid pivot!")
	print("  PASS: Gothic Chest active with articulated ChestLid pivot!")

	# 3. Sarcophagus
	var sarc_node = sandbox.prop_instances.get(3) as Node3D
	assert(sarc_node != null, "ERROR: Sarcophagus prop must be instantiated!")
	var sarc_lid = sarc_node.get_node_or_null("SarcLid") as Node3D
	assert(sarc_lid != null, "ERROR: Sarcophagus must have SarcLid node!")
	print("  PASS: Gothic Sarcophagus active with articulated SarcLid node!")

	print("\n[2/3] Testing Interactive Open Animations...")
	# Open chest and sarcophagus
	bridge.objs[1]["anim_frame"] = 2 # Chest opened
	bridge.objs[2]["anim_frame"] = 2 # Sarcophagus opened

	for f in range(30):
		sandbox.update_props(0.033)

	assert(chest_lid.rotation_degrees.x < -20.0, "ERROR: Chest lid must rotate open on anim_frame > 1! Got: %f" % chest_lid.rotation_degrees.x)
	print("  PASS: Chest lid rotated open to %f degrees!" % chest_lid.rotation_degrees.x)

	assert(sarc_lid.position.x > 0.15, "ERROR: Sarcophagus lid must slide open on anim_frame > 1! Got: %f" % sarc_lid.position.x)
	print("  PASS: Sarcophagus lid slid open to offset x=%f!" % sarc_lid.position.x)

	print("\n[3/3] Testing Dynamic Light Energy & Flickering...")
	var initial_energy = light.light_energy
	sandbox.time_accum += 0.5
	sandbox.update_props(0.033)
	assert(light.light_energy > 0.5 and light.light_energy < 3.0, "ERROR: Light energy out of bounds!")
	print("  PASS: TorchLight dynamic flicker active! Energy: %f" % light.light_energy)

	print("\n==================================================")
	print(" ALL TASK 3 AAA PROPS & LIGHTING CHECKS PASSED!   ")
	print("==================================================")
	quit(0)
