extends SceneTree

# ==============================================================================
# Test: Task 1 - 3D Asset Quality Gate & AAA Certification Validator
# ==============================================================================

class MockBridge extends RefCounted:
	var cur_lvl = 1
	var sol = PackedByteArray()
	var grid = PackedInt32Array()

	func _init():
		sol.resize(112 * 112)
		sol.fill(1)
		grid.resize(112 * 112)
		grid.fill(1) # Floor

		# Solid wall at (25, 25)
		sol[25 * 112 + 25] = 2
		grid[25 * 112 + 25] = 168

	func get_current_level(): return cur_lvl
	func is_level_loading(): return false
	func get_dungeon_solidity_grid(): return sol
	func get_dungeon_grid(): return grid
	func get_dungeon_special_grid(): return PackedInt32Array()
	func get_active_objects(): return []
	func get_dungeon_piece_texture(pid: int):
		var img = Image.create(64, 128 if pid >= 150 else 32, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.3, 0.3, 0.3, 1.0))
		return ImageTexture.create_from_image(img)
	func get_special_cel_texture(sid: int): return null
	func get_player_continuous_pos(): return {"pos_x": 25.0, "pos_y": 25.0, "dir": 0}
	func get_player_sprite_data(): return {"width": 0, "height": 0, "frame": 0, "dir": 0, "rgba": PackedByteArray()}
	func get_active_monsters_data(): return []

func _init():
	print("\n==================================================")
	print(" Testing 3D Asset Quality Gate & AAA Certification")
	print("==================================================")

	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = sandbox_script.new()
	sandbox.diablo_bridge = MockBridge.new()
	root.add_child(sandbox)
	sandbox.setup_scene_nodes()

	# [Test 1] Verify that legacy low-poly test meshes are strictly rejected
	print("\n[1/4] Checking legacy test model certification...")
	assert(sandbox.has_method("is_mesh_aaa_certified"), "ERROR: sandbox must implement is_mesh_aaa_certified!")
	var is_legacy_wall_cert = sandbox.is_mesh_aaa_certified("res://assets/models/dungeon/wall_ns.glb")
	assert(not is_legacy_wall_cert, "ERROR: Legacy 1KB wall_ns.glb must NOT be AAA certified!")
	var is_legacy_sarc_cert = sandbox.is_mesh_aaa_certified("res://assets/models/props/sarcophagus.glb")
	assert(not is_legacy_sarc_cert, "ERROR: Legacy bathtub sarcophagus.glb must NOT be AAA certified!")
	print("  PASS: All legacy low-poly/bathtub models rejected by AAA Quality Gate!")

	# [Test 2] Verify theme-level quality gating
	print("\n[2/4] Checking theme-level modular kit certification...")
	assert(sandbox.has_method("can_use_modular_3d_walls"), "ERROR: sandbox must implement can_use_modular_3d_walls!")
	# When modular walls disabled globally:
	sandbox.modular_3d_walls_enabled = false
	assert(not sandbox.can_use_modular_3d_walls("cathedral"), "ERROR: Cathedral theme must not allow 3D walls when globally disabled!")
	assert(not sandbox.can_use_modular_3d_walls("catacombs"), "ERROR: Catacombs must not allow 3D walls when globally disabled!")
	assert(not sandbox.can_use_modular_3d_walls("caves"), "ERROR: Caves must not allow 3D walls when globally disabled!")
	assert(not sandbox.can_use_modular_3d_walls("hell"), "ERROR: Hell must not allow 3D walls when globally disabled!")

	# Uncertified dummy theme must remain strictly uncertified:
	sandbox.modular_3d_walls_enabled = true
	assert(not sandbox.can_use_modular_3d_walls("uncertified_test_theme"), "ERROR: Uncertified theme must NOT be certified!")

	# All 4 dungeon themes must be certified when assets loaded:
	sandbox.update_modular_dungeon_assets(1) # Cathedral
	assert(sandbox.can_use_modular_3d_walls("cathedral"), "ERROR: Cathedral must be certified!")
	sandbox.update_modular_dungeon_assets(5) # Catacombs
	assert(sandbox.can_use_modular_3d_walls("catacombs"), "ERROR: Catacombs must be certified!")
	sandbox.update_modular_dungeon_assets(9) # Caves
	assert(sandbox.can_use_modular_3d_walls("caves"), "ERROR: Caves must be certified!")
	sandbox.update_modular_dungeon_assets(13) # Hell
	assert(sandbox.can_use_modular_3d_walls("hell"), "ERROR: Hell must be certified!")
	print("  PASS: All 4 authentic themes certified; uncertified dummy theme strictly rejected!")

	# [Test 3] Quality Gate enforcement during dungeon rebuild
	print("\n[3/4] Testing automatic fallback protection during dungeon rebuild...")
	# Simulate uncertified theme fallback
	sandbox.diablo_bridge.cur_lvl = 5
	sandbox.diablo_bridge.grid[25 * 112 + 25] = 101 # Catacombs wall piece (256x512)
	sandbox.activate()
	sandbox.set_theme_aaa_certified("catacombs", false)
	sandbox.rebuild_dungeon_if_needed(true)

	var total_cubes = sandbox.wall_mmi.multimesh.instance_count + sandbox.wall_ns_mmi.multimesh.instance_count + sandbox.wall_ew_mmi.multimesh.instance_count
	assert(total_cubes == 0, "ERROR: Quality Gate MUST prevent uncertified 3D wall cubes from spawning! Found: %d" % total_cubes)
	assert(sandbox.town_scenery_nodes.size() > 0, "ERROR: Engine MUST maintain authentic 4K PBR scenery when uncertified!")
	print("  PASS: Quality Gate intercepted uncertified walls: 0 toy cubes, 100% 4K PBR scenery preserved!")

	# Re-certify Catacombs and test certified 3D build
	sandbox.set_theme_aaa_certified("catacombs", true)
	sandbox.rebuild_dungeon_if_needed(true)
	var certified_cubes = sandbox.wall_mmi.multimesh.instance_count + sandbox.wall_ns_mmi.multimesh.instance_count + sandbox.wall_ew_mmi.multimesh.instance_count + sandbox.pillar_mmi.multimesh.instance_count
	assert(certified_cubes > 0, "ERROR: Certified theme MUST spawn 3D modular geometry! Found: %d" % certified_cubes)
	print("  PASS: Certified theme successfully generated %d modular 3D architectural pieces!" % certified_cubes)

	# [Test 4] Prop-level quality gating
	print("\n[4/4] Checking interactive prop quality gating...")
	assert(sandbox.has_method("can_use_modular_3d_prop"), "ERROR: sandbox must implement can_use_modular_3d_prop!")
	assert(not sandbox.can_use_modular_3d_prop("sarcophagus"), "ERROR: Bathtub sarcophagus must be rejected!")
	assert(not sandbox.can_use_modular_3d_prop("chest"), "ERROR: Low-poly chest must be rejected!")
	print("  PASS: Uncertified 3D props rejected in favor of authentic gothic Blizzard North art!")

	print("\n==================================================")
	print(" ALL 3D QUALITY GATE CHECKS PASSED 100%!")
	print("==================================================")
	quit(0)
