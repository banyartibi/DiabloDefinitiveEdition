@tool
extends SceneTree

# ==============================================================================
# Comprehensive Verification: Task 3.1 Modular 3D Dungeon Kit (.glb)
# ==============================================================================

class MockBridge extends RefCounted:
	var cur_lvl = 1
	var sol = PackedByteArray()
	var grid = PackedInt32Array()
	var active_objs: Array = []

	func _init():
		sol.resize(112 * 112)
		sol.fill(1) # walkable floor
		grid.resize(112 * 112)
		grid.fill(1) # floor piece 1

		# In Cathedral (L1):
		# Standalone pillar at (20, 20)
		sol[20 * 112 + 20] = 2
		grid[20 * 112 + 20] = 153 # pillar piece

		# NS Wall along X from (25, 30) to (28, 30)
		for x in range(25, 29):
			sol[30 * 112 + x] = 2
			grid[30 * 112 + x] = 168 # wall piece

		# Door at (29, 30)
		active_objs.append({
			"id": 1,
			"type": 1, # OBJ_L1LDOOR
			"tile_x": 29,
			"tile_y": 30,
			"solid": true,
			"category": "DOOR",
			"is_open": false,
			"is_broken": false
		})
		sol[30 * 112 + 29] = 2
		grid[30 * 112 + 29] = 43

		# EW Wall along Y from (40, 35) to (40, 39)
		for y in range(35, 40):
			sol[y * 112 + 40] = 2
			grid[y * 112 + 40] = 169

		# Corner apex at (50, 50), connected to (51, 50) and (50, 51)
		sol[50 * 112 + 50] = 2
		sol[50 * 112 + 51] = 2
		sol[51 * 112 + 50] = 2
		grid[50 * 112 + 50] = 180
		grid[50 * 112 + 51] = 185
		grid[51 * 112 + 50] = 186

	func get_current_level(): return cur_lvl
	func is_level_loading(): return false
	func get_dungeon_solidity_grid(): return sol
	func get_dungeon_grid(): return grid
	func get_dungeon_special_grid(): return PackedInt32Array()
	func get_active_objects(): return active_objs
	func get_dungeon_piece_texture(pid: int):
		var img = Image.create(64, 128 if pid >= 150 else 32, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.5, 0.4, 0.3, 1.0))
		return ImageTexture.create_from_image(img)
	func get_special_cel_texture(sid: int): return null
	func get_player_continuous_pos(): return {"pos_x": 25.0, "pos_y": 25.0, "dir": 0, "anim_frame": 0}
	func get_active_monsters_data(): return []

func _init():
	print("==================================================")
	print(" Testing Task 3.1: Modular 3D Dungeon Kit (.glb)  ")
	print("==================================================")

	var script = load("res://scripts/native_3d_sandbox.gd")
	if not script:
		print("FAIL: Could not load native_3d_sandbox.gd")
		quit(1)
		return

	var sandbox = script.new()
	var mock = MockBridge.new()
	sandbox.diablo_bridge = mock
	root.add_child(sandbox)
	sandbox.setup_scene_nodes()

	# 1. Test Modular Meshes Loading
	print("[1/5] Verifying 3D Modular Meshes and PBR Materials...")
	sandbox.modular_3d_walls_enabled = true
	sandbox.activate()
	sandbox.update_modular_dungeon_assets(1)

	var mmis = {
		"wall_block": sandbox.wall_mmi,
		"wall_ns": sandbox.wall_ns_mmi,
		"wall_ew": sandbox.wall_ew_mmi,
		"pillar": sandbox.pillar_mmi,
		"arch": sandbox.arch_mmi
	}
	for name in mmis.keys():
		var mmi = mmis[name]
		assert(mmi != null, "MMI %s must not be null" % name)
		assert(mmi.multimesh != null, "MultiMesh %s must not be null" % name)
		assert(mmi.multimesh.mesh != null, "Mesh in %s must not be null" % name)
		assert(not (mmi.multimesh.mesh is BoxMesh), "Mesh in %s must be real GLTF mesh, not BoxMesh fallback" % name)
		var mat = mmi.material_override as StandardMaterial3D
		assert(mat != null, "Material in %s must be StandardMaterial3D" % name)
		print("  PASS: %s | Mesh: %s | AABB: %s | Mat: %s (Albedo: %s)" % [
			name, mmi.multimesh.mesh.get_class(), mmi.multimesh.mesh.get_aabb(),
			mat.get_class(), mat.albedo_texture != null
		])

	# 2. Test Dungeon Reconstruction & MultiMesh Population
	print("[2/5] Testing Cathedral 3D Reconstruction with Modular Walls...")
	mock.cur_lvl = 1
	sandbox.rebuild_dungeon_if_needed(true)

	var pillar_count = sandbox.pillar_mmi.multimesh.instance_count
	var wall_ns_count = sandbox.wall_ns_mmi.multimesh.instance_count
	var wall_ew_count = sandbox.wall_ew_mmi.multimesh.instance_count
	var corner_count = sandbox.wall_mmi.multimesh.instance_count
	var arch_count = sandbox.arch_mmi.multimesh.instance_count

	print("  Reconstructed instances: Pillars=%d, NS=%d, EW=%d, Corners=%d, Arches=%d" % [
		pillar_count, wall_ns_count, wall_ew_count, corner_count, arch_count
	])

	assert(pillar_count >= 1, "Pillar instance count must be >= 1")
	assert(wall_ns_count >= 4, "Wall NS instance count must be >= 4")
	assert(wall_ew_count >= 5, "Wall EW instance count must be >= 5")
	assert(corner_count >= 1, "Corner instance count must be >= 1")
	assert(arch_count >= 1, "Arch instance count must be >= 1")
	print("  PASS: All modular 3D wall types successfully populated and visible!")

	# 3. Test That Wall Tiles Do NOT Spawn Duplicate Billboard Sprites
	print("[3/5] Verifying Wall Tiles Do Not Spawn Redundant Billboard Sprites...")
	# In Cathedral with modular_3d_walls_enabled, wall tiles must NOT produce town_scenery_nodes
	assert(sandbox.town_scenery_nodes.size() == 0, "Wall tiles must use 3D meshes, not redundant billboard sprites!")
	print("  PASS: Zero redundant billboard sprites spawned in Cathedral when 3D modular walls active!")

	# 4. Test Town (Level 0) Isolation & Safeguards (GEMINI.md Rule #1 & #2)
	print("[4/5] Testing Town Isolation (GEMINI.md Rule #1 & #2)...")
	mock.cur_lvl = 0
	sandbox.update_modular_dungeon_assets(0)
	sandbox.rebuild_dungeon_if_needed(true)

	var town_wall_count = sandbox.wall_mmi.multimesh.instance_count + sandbox.wall_ns_mmi.multimesh.instance_count + sandbox.wall_ew_mmi.multimesh.instance_count
	var town_pillar_count = sandbox.pillar_mmi.multimesh.instance_count
	var town_arch_count = sandbox.arch_mmi.multimesh.instance_count

	assert(town_wall_count == 0, "GEMINI.md Rule #1 violated: Town has wall instances!")
	assert(town_pillar_count == 0, "GEMINI.md Rule #1 violated: Town has pillar instances!")
	assert(town_arch_count == 0, "GEMINI.md Rule #2 violated: Town has arch instances!")
	assert(sandbox.special_scenery_nodes.size() == 0, "GEMINI.md Rule #2 violated: Town has special archway sprites!")
	print("  PASS: Town strictly contains 0 modular wall/pillar/arch instances and 0 special CEL archways!")

	# 5. Test Fallback Toggle (modular_3d_walls_enabled = false)
	print("[5/5] Testing Billboard Scenery Fallback Toggle...")
	mock.cur_lvl = 1
	sandbox.modular_3d_walls_enabled = false
	sandbox.rebuild_dungeon_if_needed(true)

	var fb_wall_count = sandbox.wall_mmi.multimesh.instance_count + sandbox.wall_ns_mmi.multimesh.instance_count + sandbox.wall_ew_mmi.multimesh.instance_count
	assert(fb_wall_count == 0, "When modular_3d_walls_enabled is false, 3D wall instances must be 0!")
	assert(sandbox.town_scenery_nodes.size() > 0, "When modular_3d_walls_enabled is false, billboard scenery must be restored!")
	print("  PASS: Fallback to unified billboard scenery functions cleanly when modular walls disabled!")

	print("==================================================")
	print(" ALL TASK 3.1 MODULAR 3D DUNGEON KIT CHECKS PASSED")
	print("==================================================")
	quit(0)
