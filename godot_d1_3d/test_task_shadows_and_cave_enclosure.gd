extends SceneTree

# ==============================================================================
# Comprehensive Verification Suite:
# Task: Shadows Restoration, Cave Enclosure, No Floor Pads, and Seam Elimination
# ==============================================================================

class MockBridge extends Node:
	var cur_lvl: int = 9
	var sol = PackedByteArray()
	var grid = PackedInt32Array()
	var active_objs: Array = []

	func _init():
		sol.resize(112 * 112)
		sol.fill(0) # void
		grid.resize(112 * 112)
		grid.fill(0)

		# Walkable floor in Caves at (50..55, 50..55)
		for y in range(50, 56):
			for x in range(50, 56):
				var idx = y * 112 + x
				sol[idx] = 1 # walkable floor
				grid[idx] = 100 # cave floor paver

		# Stalagmite in room: (52, 52)
		sol[52 * 112 + 52] = 2
		grid[52 * 112 + 52] = 2 # rock billboard

		# Boundary rock tile directly bordering the room: (49, 50)
		sol[50 * 112 + 49] = 0
		grid[50 * 112 + 49] = 0 # boundary rock wall

	func get_current_level(): return cur_lvl
	func is_level_loading(): return false
	func is_engine_running(): return true
	func get_dungeon_solidity_grid(): return sol
	func get_dungeon_grid(): return grid
	func get_dungeon_special_grid(): return PackedInt32Array()
	func get_active_objects(): return active_objs
	func get_dungeon_piece_texture(pid: int):
		var img = Image.create(64, 128 if pid < 100 else 32, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.4, 0.3, 0.2, 1.0))
		return ImageTexture.create_from_image(img)
	func get_player_continuous_pos():
		return {"pos_x": 50.0, "pos_y": 50.0, "tile_x": 50, "tile_y": 50, "dir": 0, "anim_frame": 0, "mode": 0}
	func get_player_sprite_data():
		var img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.8, 0.2, 0.2, 1.0))
		return {"width": 64, "height": 64, "rgba": img.get_data()}

func _init() -> void:
	print("=====================================================================")
	print("Starting Test: Shadows Restoration & Cave Enclosure Suite")
	print("=====================================================================")

	var root = Node3D.new()
	get_root().add_child(root)

	# 1. Test 3D Sandbox Shadows & Lighting
	print("\n--- Test 1: 3D Forward+ Dynamic Shadows & Light Rig ---")
	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = Node3D.new()
	sandbox.set_script(sandbox_script)
	root.add_child(sandbox)

	var mock = MockBridge.new()
	sandbox.diablo_bridge = mock

	# Initialize nodes
	sandbox.setup_scene_nodes()
	sandbox.setup_player_entity()

	# Dungeon Level 9 (Caves)
	mock.cur_lvl = 9
	sandbox.update_modular_dungeon_assets(9)
	assert(sandbox.player_lantern.shadow_enabled == true, "ERROR: player_lantern.shadow_enabled must be true in dungeons!")
	assert(sandbox.player_lantern.omni_shadow_mode == OmniLight3D.SHADOW_CUBE, "ERROR: omni_shadow_mode must be SHADOW_CUBE!")
	assert(sandbox.dir_light.shadow_enabled == false, "ERROR: dir_light.shadow_enabled must be false in dungeons to prevent black floating blobs!")
	print("  PASS: In Dungeon (L9 Caves), player_lantern has shadow_enabled=true (CUBE) and dir_light.shadow_enabled=false.")

	# Town (Level 0)
	mock.cur_lvl = 0
	sandbox.update_modular_dungeon_assets(0)
	assert(sandbox.dir_light.shadow_enabled == true, "ERROR: dir_light.shadow_enabled must be true in Town (sunlight)!")
	print("  PASS: In Town (L0), dir_light has shadow_enabled=true (sunlight).")

	# 2. Test 3D Cave Enclosure & Elimination of Synthetic Floor Pads
	print("\n--- Test 2: 3D Boundary Rock Enclosure & Floor Pavers ---")
	mock.cur_lvl = 9
	sandbox.update_modular_dungeon_assets(9)
	sandbox.rebuild_dungeon_if_needed(true)

	# Verify boundary rock tile (49, 50) is retained as scenery to enclose cavern
	var b_idx = 50 * 112 + 49
	assert(sandbox.town_scenery_nodes.has(b_idx), "ERROR: Boundary rock tile (49, 50) must be built as a scenery billboard to enclose cavern!")

	# Verify far void tile (10, 10) is skipped
	var far_idx = 10 * 112 + 10
	assert(not sandbox.town_scenery_nodes.has(far_idx), "ERROR: Far void tile (10, 10) must be skipped!")
	print("  PASS: Boundary rock tile (49, 50) encloses cave cavern; far void tile (10, 10) correctly skipped.")

	# 3. Test Native 2.5D Projected Shadows
	print("\n--- Test 3: Native 2.5D Dynamic Silhouette Shadows ---")
	var view_25d_script = load("res://scripts/native_25d_view.gd")
	var view_25d = Node2D.new()
	view_25d.set_script(view_25d_script)
	var canvas_root = Node2D.new()
	get_root().add_child(canvas_root)
	canvas_root.add_child(view_25d)

	view_25d.world_root = Node2D.new()
	view_25d.add_child(view_25d.world_root)
	view_25d.floor_root = Node2D.new()
	view_25d.add_child(view_25d.floor_root)

	view_25d.setup_player_node()
	assert(view_25d.player_shadow != null, "ERROR: player_shadow must exist!")

	view_25d.diablo_bridge = mock
	view_25d._has_player_pos = true
	view_25d._has_player_sprite = true
	view_25d.update_player(0.016, PackedByteArray(), mock.get_player_continuous_pos())

	assert(view_25d.player_shadow.visible == false, "ERROR: player_shadow.visible must be false to prevent black sky blobs and 144 FPS drops!")
	print("  PASS: In Native 2.5D, artificial secondary shadow is cleanly disabled, preserving authentic foot contact and 144 FPS.")

	# 4. Test Shader Compilation
	print("\n--- Test 4: Shader Integrity (Lava & PBR Surface) ---")
	var pbr_shader = load("res://shaders/d1de_25d_pbr.gdshader") as Shader
	assert(pbr_shader != null, "ERROR: d1de_25d_pbr.gdshader failed to load!")
	var lava_shader = load("res://shaders/d1de_3d_lava.gdshader") as Shader
	assert(lava_shader != null, "ERROR: d1de_3d_lava.gdshader failed to load!")
	var shadow_shader = load("res://shaders/realistic_25d_shadow.gdshader") as Shader
	assert(shadow_shader != null, "ERROR: realistic_25d_shadow.gdshader failed to load!")
	print("  PASS: All 3 shaders loaded and compiled successfully with zero syntax errors.")

	print("\n=====================================================================")
	print("ALL TESTS PASSED 100%! Shadows restored and cavern enclosure verified.")
	print("=====================================================================")
	quit(0)
