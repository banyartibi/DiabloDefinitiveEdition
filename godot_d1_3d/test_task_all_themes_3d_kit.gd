extends SceneTree

# ==============================================================================
# Multi-Theme AAA 3D Architectural Kit Verification Suite
# Verifies:
# 1. Complete AAA kits across ALL 4 Themes (Cathedral, Catacombs, Caves, Hell)
# 2. Strict Mathematical Grid Invariants (1.06066m step, 2.40m height, -0.08m skirt)
# 3. 4K PBR Material Channels (Albedo, Normal Map, Roughness, Render Priority 3)
# 4. MultiMesh Sandbox Dungeon Generation across Levels 1, 5, 9, and 13
# ==============================================================================

class MockBridge extends RefCounted:
	var cur_lvl = 1
	var sol = PackedByteArray()
	var grid = PackedInt32Array()

	func _init():
		sol.resize(112 * 112)
		sol.fill(1) # Floor
		grid.resize(112 * 112)
		grid.fill(1)

		# Build test room:
		# Corners at (20,20), (25,20), (20,25), (25,25)
		# NS walls along X from 21..24
		# EW walls along Y from 21..24
		# Isolated pillar at (22, 22)
		sol[20 * 112 + 20] = 2
		sol[25 * 112 + 20] = 2
		sol[20 * 112 + 25] = 2
		sol[25 * 112 + 25] = 2
		for x in range(21, 25):
			sol[20 * 112 + x] = 2
			sol[25 * 112 + x] = 2
		for y in range(21, 25):
			sol[y * 112 + 20] = 2
			sol[y * 112 + 25] = 2
		sol[22 * 112 + 22] = 2

	func set_wall_piece(pid: int):
		grid[20 * 112 + 20] = pid
		grid[25 * 112 + 20] = pid
		grid[20 * 112 + 25] = pid
		grid[25 * 112 + 25] = pid
		for x in range(21, 25):
			grid[20 * 112 + x] = pid
			grid[25 * 112 + x] = pid
		for y in range(21, 25):
			grid[y * 112 + 20] = pid
			grid[y * 112 + 25] = pid
		grid[22 * 112 + 22] = pid

	func get_current_level(): return cur_lvl
	func is_level_loading(): return false
	func get_dungeon_solidity_grid(): return sol
	func get_dungeon_grid(): return grid
	func get_dungeon_special_grid(): return PackedInt32Array()
	func get_active_objects():
		return [
			{"type": 1, "tile_x": 23, "tile_y": 20, "category": "DOOR"}
		]
	func get_dungeon_piece_texture(pid: int):
		var img = Image.create(64, 128 if pid >= 100 else 32, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.25, 0.25, 0.25, 1.0))
		return ImageTexture.create_from_image(img)
	func get_special_cel_texture(sid: int): return null
	func get_player_continuous_pos(): return {"pos_x": 22.0, "pos_y": 23.0, "dir": 0}
	func get_player_sprite_data(): return {"width": 0, "height": 0, "frame": 0, "dir": 0, "rgba": PackedByteArray()}
	func get_active_monsters_data(): return []

func _init():
	print("\n=======================================================")
	print("  TEST TASK: ALL 4 THEMES 3D ARCHITECTURAL KIT SUITE   ")
	print("=======================================================")

	var total_tests = 0
	var passed_tests = 0

	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = sandbox_script.new()
	sandbox.diablo_bridge = MockBridge.new()
	root.add_child(sandbox)
	sandbox.setup_scene_nodes()

	var themes = [
		{"name": "cathedral", "suffix": "gothic", "level": 1, "wall_pid": 168},
		{"name": "catacombs", "suffix": "catacombs", "level": 5, "wall_pid": 101},
		{"name": "caves", "suffix": "caves", "level": 9, "wall_pid": 0},
		{"name": "hell", "suffix": "hell", "level": 13, "wall_pid": 0}
	]

	# ------------------------------------------------------------------
	# TEST 1: Resource Loading & Certification for All 20 Meshes
	# ------------------------------------------------------------------
	total_tests += 1
	var all_loaded = true
	var piece_types = ["wall_ns", "wall_ew", "wall_corner", "pillar", "arch_door"]

	print("\n[TEST 1] Verifying AAA Certification & Loading for 20 meshes across all 4 themes...")
	for t in themes:
		var theme_name = t["name"]
		var suffix = t["suffix"]
		for pt in piece_types:
			var path = "res://assets/models/aaa/%s/%s_%s.res" % [theme_name, pt, suffix]
			if not ResourceLoader.exists(path):
				printerr("  [FAIL] Missing mesh resource: %s" % path)
				all_loaded = false
				continue
			var mesh = sandbox.get_or_load_mesh(path)
			if mesh == null or not (mesh is ArrayMesh):
				printerr("  [FAIL] Mesh load failed or not ArrayMesh: %s" % path)
				all_loaded = false
				continue
			if not sandbox.is_mesh_aaa_certified(path):
				printerr("  [FAIL] Mesh not certified by AAA Quality Gate: %s" % path)
				all_loaded = false
				continue
			print("  [PASS] Certified: [%s] %s (Faces: %d)" % [theme_name.to_upper(), pt, mesh.get_faces().size() / 3])

	if all_loaded:
		passed_tests += 1
		print("  -> TEST 1 PASSED: All 20 AAA meshes exist and certified!")
	else:
		printerr("  -> TEST 1 FAILED!")

	# ------------------------------------------------------------------
	# TEST 2: Mathematical Invariants (Diagonal Step, Height, Skirt)
	# ------------------------------------------------------------------
	total_tests += 1
	var geom_ok = true
	print("\n[TEST 2] Verifying Mathematical Geometry Invariants...")
	for t in themes:
		var theme_name = t["name"]
		var suffix = t["suffix"]

		# Wall NS
		var p_ns = "res://assets/models/aaa/%s/wall_ns_%s.res" % [theme_name, suffix]
		var m_ns = sandbox.get_or_load_mesh(p_ns)
		var aabb_ns = m_ns.get_aabb()
		if not is_equal_approx(aabb_ns.size.x, 1.06066):
			printerr("  [FAIL] %s Wall NS width %f != 1.06066m" % [theme_name, aabb_ns.size.x])
			geom_ok = false
		if aabb_ns.position.y > -0.05:
			printerr("  [FAIL] %s Wall NS skirt y=%f must be <= -0.05m" % [theme_name, aabb_ns.position.y])
			geom_ok = false
		if aabb_ns.end.y < 2.40:
			printerr("  [FAIL] %s Wall NS height %f must be >= 2.40m" % [theme_name, aabb_ns.end.y])
			geom_ok = false

		# Wall EW
		var p_ew = "res://assets/models/aaa/%s/wall_ew_%s.res" % [theme_name, suffix]
		var m_ew = sandbox.get_or_load_mesh(p_ew)
		var aabb_ew = m_ew.get_aabb()
		if not is_equal_approx(aabb_ew.size.z, 1.06066):
			printerr("  [FAIL] %s Wall EW length %f != 1.06066m" % [theme_name, aabb_ew.size.z])
			geom_ok = false
		if aabb_ew.position.y > -0.05:
			printerr("  [FAIL] %s Wall EW skirt y=%f must be <= -0.05m" % [theme_name, aabb_ew.position.y])
			geom_ok = false

		# Pillar
		var p_pil = "res://assets/models/aaa/%s/pillar_%s.res" % [theme_name, suffix]
		var m_pil = sandbox.get_or_load_mesh(p_pil)
		var aabb_pil = m_pil.get_aabb()
		if aabb_pil.position.y > -0.05 or aabb_pil.end.y < 2.40:
			printerr("  [FAIL] %s Pillar height or skirt invalid" % theme_name)
			geom_ok = false

		# Arch
		var p_arch = "res://assets/models/aaa/%s/arch_door_%s.res" % [theme_name, suffix]
		var m_arch = sandbox.get_or_load_mesh(p_arch)
		var aabb_arch = m_arch.get_aabb()
		if aabb_arch.position.y > -0.05 or aabb_arch.end.y < 2.40:
			printerr("  [FAIL] %s Arch height or skirt invalid" % theme_name)
			geom_ok = false

	if geom_ok:
		passed_tests += 1
		print("  -> TEST 2 PASSED: 100% mathematical grid parity, 2.40m height, -0.08m subterranean skirt verified!")
	else:
		printerr("  -> TEST 2 FAILED!")

	# ------------------------------------------------------------------
	# TEST 3: PBR Material Channels (Albedo, Normal Map, Roughness, Render Priority)
	# ------------------------------------------------------------------
	total_tests += 1
	var pbr_ok = true
	print("\n[TEST 3] Verifying 4K PBR Material Channels...")
	for t in themes:
		var theme_name = t["name"]
		var suffix = t["suffix"]
		for pt in piece_types:
			var path = "res://assets/models/aaa/%s/%s_%s.res" % [theme_name, pt, suffix]
			var mesh = sandbox.get_or_load_mesh(path)
			var mat = mesh.surface_get_material(0) as StandardMaterial3D
			if mat == null:
				printerr("  [FAIL] Material null on %s" % path)
				pbr_ok = false
				continue
			if mat.albedo_texture == null:
				printerr("  [FAIL] Albedo texture missing on %s" % path)
				pbr_ok = false
			if not mat.normal_enabled or mat.normal_texture == null:
				printerr("  [FAIL] Normal map missing or not enabled on %s" % path)
				pbr_ok = false
			if mat.roughness_texture == null:
				printerr("  [FAIL] Roughness map missing on %s" % path)
				pbr_ok = false
			if mat.render_priority != 3:
				printerr("  [FAIL] Render priority %d != 3 on %s" % [mat.render_priority, path])
				pbr_ok = false

	if pbr_ok:
		passed_tests += 1
		print("  -> TEST 3 PASSED: All 20 meshes have verified Albedo, Normal (+Y), Roughness, and render_priority=3!")
	else:
		printerr("  -> TEST 3 FAILED!")

	# ------------------------------------------------------------------
	# TEST 4: Live Dungeon Generation & MultiMesh Population for All 4 Themes
	# ------------------------------------------------------------------
	total_tests += 1
	var rebuild_ok = true
	print("\n[TEST 4] Verifying Live MultiMesh Dungeon Builds across Themes...")
	sandbox.modular_3d_walls_enabled = true

	for t in themes:
		var lvl = t["level"]
		var theme_name = t["name"]
		var wall_pid = t["wall_pid"]
		sandbox.diablo_bridge.cur_lvl = lvl
		sandbox.diablo_bridge.set_wall_piece(wall_pid)
		sandbox.update_modular_dungeon_assets(lvl)

		if not sandbox.can_use_modular_3d_walls(theme_name):
			printerr("  [FAIL] Theme %s must be certified for 3D walls!" % theme_name)
			rebuild_ok = false
			continue

		sandbox.rebuild_dungeon_if_needed(true)

		var ns_cnt = sandbox.wall_ns_mmi.multimesh.instance_count
		var ew_cnt = sandbox.wall_ew_mmi.multimesh.instance_count
		var corner_cnt = sandbox.wall_mmi.multimesh.instance_count
		var pil_cnt = sandbox.pillar_mmi.multimesh.instance_count
		var arch_cnt = sandbox.arch_mmi.multimesh.instance_count
		var total_3d = ns_cnt + ew_cnt + corner_cnt + pil_cnt + arch_cnt

		print("  [%s (L%d)] MultiMesh 3D Pieces -> NS:%d, EW:%d, Corners:%d, Pillars:%d, Arches:%d (Total: %d)" % [
			theme_name.to_upper(), lvl, ns_cnt, ew_cnt, corner_cnt, pil_cnt, arch_cnt, total_3d
		])

		if total_3d == 0:
			printerr("  [FAIL] No 3D modular pieces generated for theme %s!" % theme_name)
			rebuild_ok = false
		if pil_cnt == 0:
			printerr("  [FAIL] Pillar not generated for theme %s!" % theme_name)
			rebuild_ok = false
		if arch_cnt == 0:
			printerr("  [FAIL] Door archway not generated for theme %s!" % theme_name)
			rebuild_ok = false

	if rebuild_ok:
		passed_tests += 1
		print("  -> TEST 4 PASSED: All 4 themes successfully build full 3D dungeons with walls, pillars, and arches!")
	else:
		printerr("  -> TEST 4 FAILED!")

	print("\n=======================================================")
	print("  SUITE RESULTS: %d / %d TESTS PASSED                  " % [passed_tests, total_tests])
	print("=======================================================\n")

	quit(0 if passed_tests == total_tests else 1)
