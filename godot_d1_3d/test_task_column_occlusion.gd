extends SceneTree

# Automated Verification Test for Column / Pillar Occlusion and Scenery Transparency
# Verifies that characters, monsters, corpses, and items do NOT show through or overlap columns/pillars.

func _init() -> void:
	print("\n=======================================================")
	print("  TEST TASK: COLUMN / PILLAR OCCLUSION VERIFICATION")
	print("=======================================================")

	var total_tests = 0
	var passed_tests = 0

	# ------------------------------------------------------------------
	# TEST 1: Pillar Piece Classification Verification
	# ------------------------------------------------------------------
	total_tests += 1
	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = Node3D.new()
	sandbox.set_script(sandbox_script)
	get_root().add_child(sandbox)

	if sandbox.has_method("load_dungeon_piece_types"):
		sandbox.load_dungeon_piece_types()

	var p24_is_pillar = sandbox.is_piece_pillar(24, 1) if sandbox.has_method("is_piece_pillar") else false
	var p269_is_pillar = sandbox.is_piece_pillar(269, 1) if sandbox.has_method("is_piece_pillar") else false
	var p113_is_pillar = sandbox.is_piece_pillar(113, 1) if sandbox.has_method("is_piece_pillar") else false
	var p2_is_pillar_dungeon = sandbox.is_piece_pillar(2, 1) if sandbox.has_method("is_piece_pillar") else false
	var p24_is_pillar_town = sandbox.is_piece_pillar(24, 0) if sandbox.has_method("is_piece_pillar") else false

	print("Pillar checks: p24=%s, p269=%s, p113=%s, p2(floor)=%s, town=%s" % [
		p24_is_pillar, p269_is_pillar, p113_is_pillar, p2_is_pillar_dungeon, p24_is_pillar_town
	])

	if p24_is_pillar and p269_is_pillar and p113_is_pillar and not p2_is_pillar_dungeon and not p24_is_pillar_town:
		passed_tests += 1
		print("  [PASS] Test 1: Pillar piece classification is accurate and obeys Town Isolation.")
	else:
		printerr("  [FAIL] Test 1: Pillar piece classification failed.")

	# ------------------------------------------------------------------
	# TEST 2: Pillar Immunity to Translucency in update_scenery_transparency()
	# ------------------------------------------------------------------
	total_tests += 1
	var pillar_idx = 20 * 112 + 20 # tile (20, 20)
	var wall_idx = 20 * 112 + 21   # tile (21, 20) - non-pillar wall piece 168

	var mock_bridge = MockOcclusionBridge.new()
	# Set tile (20, 20) to piece 24 (pillar), tile (21, 20) to piece 168 (wall)
	mock_bridge.grid[pillar_idx] = 24
	mock_bridge.grid[wall_idx] = 168

	# Mark both tiles as having transparency in DevilutionX
	mock_bridge.trans_mask[pillar_idx] = 1
	mock_bridge.trans_mask[wall_idx] = 1
	mock_bridge.trans_grid[pillar_idx] = 5
	mock_bridge.trans_grid[wall_idx] = 5
	mock_bridge.trans_list[5] = 1

	sandbox.diablo_bridge = mock_bridge
	sandbox.is_sandbox_active = true
	sandbox.last_level_idx = 1 # Cathedral

	# Create sprite nodes for both
	var pillar_spr = Sprite3D.new()
	pillar_spr.name = "Scenery_20_20"
	pillar_spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	pillar_spr.modulate.a = 1.0
	pillar_spr.render_priority = 3
	sandbox.town_scenery_nodes[pillar_idx] = pillar_spr
	sandbox.add_child(pillar_spr)

	var wall_spr = Sprite3D.new()
	wall_spr.name = "Scenery_21_20"
	wall_spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	wall_spr.modulate.a = 1.0
	wall_spr.render_priority = 3
	sandbox.town_scenery_nodes[wall_idx] = wall_spr
	sandbox.add_child(wall_spr)

	# Run transparency update
	sandbox.update_scenery_transparency()

	var pillar_kept_solid = (pillar_spr.alpha_cut == SpriteBase3D.ALPHA_CUT_DISCARD) and is_equal_approx(pillar_spr.modulate.a, 1.0) and (pillar_spr.render_priority == 3)
	var wall_became_translucent = (wall_spr.alpha_cut == SpriteBase3D.ALPHA_CUT_DISABLED) and is_equal_approx(wall_spr.modulate.a, 0.45) and (wall_spr.render_priority == 4)
	var indices_valid = (not sandbox.translucent_scenery_indices.has(pillar_idx)) and (sandbox.translucent_scenery_indices.has(wall_idx))

	print("Transparency check: pillar_kept_solid=%s, wall_became_translucent=%s, indices_valid=%s" % [
		pillar_kept_solid, wall_became_translucent, indices_valid
	])
	print("Wall spr props: alpha_cut=%s, modulate.a=%.2f, render_priority=%d" % [
		wall_spr.alpha_cut, wall_spr.modulate.a, wall_spr.render_priority
	])

	if pillar_kept_solid and wall_became_translucent and indices_valid:
		passed_tests += 1
		print("  [PASS] Test 2: Pillars are strictly immune to transparency; normal walls gain prio 4.")
	else:
		printerr("  [FAIL] Test 2: Scenery transparency gating failed.")

	# ------------------------------------------------------------------
	# TEST 3: Scenery Restoration on Leaving Room
	# ------------------------------------------------------------------
	total_tests += 1
	mock_bridge.trans_list[5] = 0 # No longer in room
	sandbox.update_scenery_transparency()

	var wall_restored = (wall_spr.alpha_cut == SpriteBase3D.ALPHA_CUT_DISCARD) and (wall_spr.modulate.a == 1.0) and (wall_spr.render_priority == 3)
	var list_cleared = sandbox.translucent_scenery_indices.is_empty()

	if wall_restored and list_cleared:
		passed_tests += 1
		print("  [PASS] Test 3: Normal walls cleanly restore to prio 3, modulate.a 1.0, and ALPHA_CUT_DISCARD.")
	else:
		printerr("  [FAIL] Test 3: Wall restoration failed.")

	# ------------------------------------------------------------------
	# TEST 4: Optical 3D Forward+ Depth Occlusion Rendering Test
	# ------------------------------------------------------------------
	total_tests += 1
	var vp = SubViewport.new()
	vp.size = Vector2i(256, 256)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)

	var camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14.5
	camera.rotation_degrees = Vector3(-30, 0, 0)
	vp.add_child(camera)

	var TILE_SCALE = 1.06066
	var p_z = 40.0 * TILE_SCALE

	var alb_path = ProjectSettings.globalize_path("res://assets/dungeon_pbr_4x/albedo/piece_24.png")
	var img_24 = Image.load_from_file(alb_path)
	var p24_tex = ImageTexture.create_from_image(img_24)

	var render_pillar = Sprite3D.new()
	render_pillar.texture = p24_tex
	render_pillar.centered = true
	render_pillar.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	render_pillar.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	render_pillar.pixel_size = 1.50 / float(p24_tex.get_width())
	render_pillar.offset = Vector2(0.0, float(p24_tex.get_height()) * 0.5)
	render_pillar.position = Vector3(0.0, 0.01, p_z)
	render_pillar.render_priority = 0
	vp.add_child(render_pillar)

	# Place red player behind the pillar at delta (-1, -1)
	var pl_z = 38.0 * TILE_SCALE
	var render_player = Sprite3D.new()
	render_player.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	render_player.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	render_player.pixel_size = 1.50 / 256.0
	render_player.offset = Vector2(0.0, 128.0 * 0.5)
	render_player.position = Vector3(0.0, 0.0, pl_z)
	render_player.render_priority = 3

	var pimg = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	pimg.fill(Color(1.0, 0.0, 0.0, 1.0))
	var ptex = ImageTexture.create_from_image(pimg)
	render_player.texture = ptex

	var shader = load("res://shaders/entity_hd_upscaler_3d.gdshader") as Shader
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = 3
	mat.set_shader_parameter("albedo_texture", ptex)
	mat.set_shader_parameter("hd_enabled", false)
	mat.set_shader_parameter("brightness", 1.0)
	render_player.material_override = mat
	vp.add_child(render_player)

	var dist = 12.0
	camera.position = Vector3(0.0, 1.5 + dist * sin(deg_to_rad(30.0)), p_z + dist * cos(deg_to_rad(30.0)))

	await process_frame
	await process_frame

	var cap_img = vp.get_texture().get_image()
	var red_capital_overlap = 0
	if cap_img:
		cap_img.save_png("/home/biti/.gemini/antigravity/brain/4427fff3-fdfb-47e3-b8be-42adea0050ce/test_task_occlusion_view.png")
		# Check the central capital area (rows around y=105..127, cols around x=115..140)
		for y in range(105, 128):
			for x in range(115, 140):
				var col = cap_img.get_pixel(x, y)
				if col.r > 0.8 and col.g < 0.2 and col.b < 0.2:
					red_capital_overlap += 1

	print("Optical occlusion check: red_capital_overlap = %d" % red_capital_overlap)
	if red_capital_overlap == 0:
		passed_tests += 1
		print("  [PASS] Test 4: Player is 100% occluded by solid pillar capital (0 overlapping red pixels).")
	else:
		printerr("  [FAIL] Test 4: Player still overlapped pillar capital with %d pixels." % red_capital_overlap)

	# ------------------------------------------------------------------
	# SUMMARY
	# ------------------------------------------------------------------
	print("\n=======================================================")
	print("  COLUMN OCCLUSION VERIFICATION SUMMARY: %d / %d PASSED" % [passed_tests, total_tests])
	print("=======================================================\n")

	sandbox.queue_free()
	vp.queue_free()

	if passed_tests == total_tests:
		quit(0)
	else:
		quit(1)

class MockOcclusionBridge extends RefCounted:
	var grid: PackedInt32Array
	var trans_mask: PackedByteArray
	var trans_grid: PackedByteArray
	var trans_list: PackedByteArray

	func _init():
		grid.resize(112 * 112)
		trans_mask.resize(112 * 112)
		trans_grid.resize(112 * 112)
		trans_list.resize(256)
		grid.fill(1)
		trans_mask.fill(0)
		trans_grid.fill(0)
		trans_list.fill(0)

	func get_dungeon_grid() -> PackedInt32Array: return grid
	func get_dungeon_trans_mask() -> PackedByteArray: return trans_mask
	func get_dungeon_trans_grid() -> PackedByteArray: return trans_grid
	func get_trans_list() -> PackedByteArray: return trans_list
	func get_player_continuous_pos() -> Dictionary: return {"pos_x": 20.0, "pos_y": 20.0}
	func get_current_level() -> int: return 1
	func get_dungeon_piece_texture(pid: int) -> Texture2D: return null
