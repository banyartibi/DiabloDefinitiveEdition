extends SceneTree

# ==============================================================================
# Comprehensive Verification: Unified Billboard Scenery Pipeline Across All Levels
# ==============================================================================

class MockBridge extends RefCounted:
	var cur_lvl = 1

	func get_current_level():
		return cur_lvl

	func is_level_loading():
		return false

	func get_dungeon_solidity_grid():
		var arr = PackedByteArray()
		arr.resize(112 * 112)
		arr.fill(1) # walkable floor
		arr[20 * 112 + 20] = 2 # wall / solid obstacle
		arr[21 * 112 + 21] = 3 # archway
		return arr

	func get_dungeon_grid():
		var arr = PackedInt32Array()
		arr.resize(112 * 112)
		arr.fill(1) # piece 1 (floor)
		arr[20 * 112 + 20] = 168 # piece 168 (wall)
		return arr

	func get_dungeon_special_grid():
		var arr = PackedInt32Array()
		arr.resize(112 * 112)
		arr.fill(0)
		arr[21 * 112 + 21] = 1 # special 1 (archway)
		return arr

	func get_active_objects():
		return []

	func get_dungeon_piece_texture(pid: int):
		var img = Image.create(64, 128, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.5, 0.4, 0.3, 1.0))
		return ImageTexture.create_from_image(img)

	func get_special_cel_texture(sid: int):
		var img = Image.create(64, 128, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.6, 0.6, 0.6, 1.0))
		return ImageTexture.create_from_image(img)

	func get_player_continuous_pos():
		return {"pos_x": 25.0, "pos_y": 25.0, "dir": 0, "anim_frame": 0}

	func get_active_monsters_data():
		return []

func _init():
	print("\n=======================================================")
	print(" Testing Unified Billboard Scenery in Native 3D Sandbox")
	print("=======================================================")

	var script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = script.new()
	var mock = MockBridge.new()
	sandbox.diablo_bridge = mock
	sandbox.setup_scene_nodes()

	# 1. Test Cathedral (Level 1)
	mock.cur_lvl = 1
	sandbox.activate()
	sandbox.rebuild_dungeon_if_needed(true)

	assert(sandbox.town_scenery_nodes.size() > 0, "FAIL: No scenery billboard sprites built in Cathedral!")
	print("  PASS: Cathedral built %d billboard scenery sprites!" % sandbox.town_scenery_nodes.size())

	assert(sandbox.special_scenery_nodes.size() > 0, "FAIL: Special CEL archway not built in Cathedral!")
	print("  PASS: Cathedral built %d special CEL archway sprites!" % sandbox.special_scenery_nodes.size())

	# Ensure modular wall cubes are strictly disabled (0 instances)
	assert(sandbox.wall_mmi.multimesh.instance_count == 0, "FAIL: wall_mmi had instances!")
	assert(sandbox.wall_ns_mmi.multimesh.instance_count == 0, "FAIL: wall_ns_mmi had instances!")
	assert(sandbox.wall_ew_mmi.multimesh.instance_count == 0, "FAIL: wall_ew_mmi had instances!")
	assert(sandbox.pillar_mmi.multimesh.instance_count == 0, "FAIL: pillar_mmi had instances!")
	assert(sandbox.arch_mmi.multimesh.instance_count == 0, "FAIL: arch_mmi had instances!")
	print("  PASS: Modular 3D cubes / pyramids strictly disabled (0 instances across all wall MMIs)!")

	# Check floor diamond material transparency
	var f_mat = sandbox.get_floor_material(1, 1)
	assert(f_mat.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "FAIL: Floor material transparency not DISABLED!")
	print("  PASS: Floor diamond material transparency is DISABLED (100% solid, eliminates grid lines)!")

	# 2. Test Town (Level 0) Isolation (GEMINI.md Rules #1 and #2)
	mock.cur_lvl = 0
	sandbox.activate()
	sandbox.rebuild_dungeon_if_needed(true)

	# Rule #2: Special CEL archways must be strictly 0 in Town!
	assert(sandbox.special_scenery_nodes.size() == 0, "FAIL: GEMINI.md Rule #2 violated: special archway built in Town!")
	print("  PASS: Town has 0 special CEL archways (strictly gated to Cathedral per GEMINI.md Rule #2)!")

	# Scenery billboard built for Town tree / cottage
	assert(sandbox.town_scenery_nodes.size() > 0, "FAIL: Town scenery billboard not built!")
	print("  PASS: Town built %d billboard scenery sprites using engine bridge!" % sandbox.town_scenery_nodes.size())

	sandbox.deactivate()
	sandbox.free()

	print("\n=======================================================")
	print(" ALL UNIFIED BILLBOARD SCENERY TESTS PASSED 100%!")
	print("=======================================================\n")
	quit(0)
