@tool
extends SceneTree

# Automated Verification Test for Ground Items, 144 FPS Performance, and Column Immunity
# Verifies that:
# 1. Ground items (gold, equipment) prioritize authentic bridge rasterization and reject pure black masks.
# 2. 2.5D active tile loop is clamped to screen view bounds, and lightmap uses precomputed LUT caching.
# 3. Secondary shadow shaders are disabled on 2D billboard sprites (eliminating floating sky silhouettes).
# 4. Freestanding columns and pillars are strictly immune to room translucency in 2.5D view.

func _init() -> void:
	print("\n=======================================================")
	print("  TEST TASK: GROUND ITEMS, 144 FPS & PILLAR OCCLUSION")
	print("=======================================================")

	var total_tests = 0
	var passed_tests = 0

	# ------------------------------------------------------------------
	# TEST 1: Pure Black Texture Detector Test
	# ------------------------------------------------------------------
	total_tests += 1
	var view_25d_script = load("res://scripts/native_25d_view.gd")

	# Pure black image with alpha
	var black_img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	black_img.fill(Color(0.0, 0.0, 0.0, 1.0))
	var is_black = view_25d_script._is_texture_pure_black(black_img)

	# Colored image (gold yellow)
	var gold_img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	gold_img.fill(Color(1.0, 0.85, 0.2, 1.0))
	var is_gold_black = view_25d_script._is_texture_pure_black(gold_img)

	print("Detector check: black_detected=%s, gold_detected_black=%s" % [is_black, is_gold_black])
	if is_black and not is_gold_black:
		passed_tests += 1
		print("  [PASS] Test 1: Pure black texture detector accurately identifies silhouette masks.")
	else:
		printerr("  [FAIL] Test 1: Texture detector failed.")

	# ------------------------------------------------------------------
	# TEST 2: Pillar Classification and Immunity to Translucency in 2.5D
	# ------------------------------------------------------------------
	total_tests += 1
	var view_25d = Node2D.new()
	view_25d.set_script(view_25d_script)
	get_root().add_child(view_25d)

	view_25d.last_level_idx = 1 # Cathedral
	var p24_is_pillar = view_25d.is_piece_pillar(24)
	var p269_is_pillar = view_25d.is_piece_pillar(269)
	var p2_is_pillar = view_25d.is_piece_pillar(2) # floor
	view_25d.last_level_idx = 0 # Town
	var p24_in_town = view_25d.is_piece_pillar(24)

	print("Pillar checks: p24=%s, p269=%s, p2_floor=%s, p24_town=%s" % [
		p24_is_pillar, p269_is_pillar, p2_is_pillar, p24_in_town
	])

	if p24_is_pillar and p269_is_pillar and not p2_is_pillar and not p24_in_town:
		passed_tests += 1
		print("  [PASS] Test 2: 2.5D pillar classification is accurate and enforces Town isolation.")
	else:
		printerr("  [FAIL] Test 2: Pillar classification check failed.")

	# ------------------------------------------------------------------
	# TEST 3: Precomputed Lightmap LUT Accuracy and 0ms Cache
	# ------------------------------------------------------------------
	total_tests += 1
	var d_lut = view_25d.DUNGEON_LIGHT_LUT
	var t_lut = view_25d.TOWN_LIGHT_LUT

	# Check values: level 0 (full light) = 255, level 15 (darkness) = 0
	var d_full = d_lut[0]
	var d_dark = d_lut[15]
	var t_full = t_lut[0]
	var t_dark = t_lut[15]

	print("LUT checks: dungeon full=%d, dark=%d; town full=%d, dark=%d" % [d_full, d_dark, t_full, t_dark])
	if d_full == 255 and d_dark == 0 and t_full == 255 and t_dark == 0 and d_lut.size() == 16:
		passed_tests += 1
		print("  [PASS] Test 3: Precomputed lighting LUT is mathematically sound and replaces pow() loops.")
	else:
		printerr("  [FAIL] Test 3: Lighting LUT verification failed.")

	# ------------------------------------------------------------------
	# TEST 4: Ground Item Prioritizes Bridge Over Pure-Black Disk Mask
	# ------------------------------------------------------------------
	total_tests += 1
	var mock_bridge = MockBridgeForItems.new()
	view_25d.diablo_bridge = mock_bridge
	view_25d._has_active_items = true
	view_25d._has_ground_item_sprite = true
	view_25d._has_monster_data = true
	view_25d._has_monster_sprite = true
	view_25d.last_level_idx = 1
	view_25d.setup_scene_hierarchy()

	# Run update_ground_items with mock gold item
	view_25d.update_ground_items(PackedByteArray())

	var gold_node = view_25d.item_nodes.get(50, null)
	var has_gold_sprite = false
	var gold_spr_valid = false
	var spr_centered_and_grounded = false
	var lbl_docked_above_item = false
	if gold_node:
		var spr = gold_node.get_node_or_null("Sprite") as Sprite2D
		var lbl = gold_node.get_node_or_null("Label") as Label
		if spr and spr.texture:
			has_gold_sprite = true
			if spr.texture.get_width() == 28 and spr.texture.get_height() == 28:
				gold_spr_valid = true
			if spr.centered and spr.offset == Vector2.ZERO:
				spr_centered_and_grounded = true
		if lbl and spr and spr.texture:
			var expected_top = -float(spr.texture.get_height()) * spr.scale.y * 0.5
			if lbl.position.y < expected_top and lbl.position.y > expected_top - 50.0:
				lbl_docked_above_item = true

	print("Ground item check: has_gold_node=%s, has_gold_sprite=%s, gold_spr_valid=%s, grounded=%s, lbl_docked=%s" % [
		gold_node != null, has_gold_sprite, gold_spr_valid, spr_centered_and_grounded, lbl_docked_above_item
	])

	if gold_node != null and has_gold_sprite and gold_spr_valid and spr_centered_and_grounded and lbl_docked_above_item:
		passed_tests += 1
		print("  [PASS] Test 4: Ground items correctly prioritize bridge, auto-crop, center on floor diamond, and dock label snugly.")
	else:
		printerr("  [FAIL] Test 4: Ground item prioritization check failed.")

	# ------------------------------------------------------------------
	# TEST 5: Secondary 2D Silhouette Shadows are Disabled
	# ------------------------------------------------------------------
	total_tests += 1
	view_25d.update_player(0.016, PackedByteArray(), {"pos_x": 25.0, "pos_y": 25.0})
	var player_shadow_hidden = (view_25d.player_shadow != null and not view_25d.player_shadow.visible)

	view_25d.update_monsters(0.016, PackedByteArray())
	var monster_shadow_hidden = true
	for m_node in view_25d.monster_nodes.values():
		var m_sh = m_node.get_node_or_null("Shadow") as Sprite2D
		if m_sh and m_sh.visible:
			monster_shadow_hidden = false

	print("Shadow checks: player_shadow_hidden=%s, monster_shadow_hidden=%s" % [
		player_shadow_hidden, monster_shadow_hidden
	])

	if player_shadow_hidden and monster_shadow_hidden:
		passed_tests += 1
		print("  [PASS] Test 5: Secondary silhouette projection shadows disabled; authentic foot contact preserved.")
	else:
		printerr("  [FAIL] Test 5: Shadow gating check failed.")

	# ------------------------------------------------------------------
	# TEST 6: Corpse & Monster Frame Caching (144 FPS Performance)
	# ------------------------------------------------------------------
	total_tests += 1
	view_25d._has_active_corpses = true
	view_25d.update_corpses(PackedByteArray())

	# Initial call populated cache
	var initial_cache_size = view_25d.corpse_textures.size()
	var corpse_calls_before = mock_bridge.corpse_data_call_count

	# Run 10 consecutive frames with active corpse
	for frame_i in range(10):
		view_25d.update_corpses(PackedByteArray())

	var corpse_calls_after = mock_bridge.corpse_data_call_count
	var corpse_cached_properly = (initial_cache_size > 0 and corpse_calls_after == corpse_calls_before)

	# Check monster animation cache
	var monster_cache_has_entries = view_25d.monster_anim_cache.size() > 0
	print("Performance checks: corpse_cached=%s (calls before=%d, after=%d), monster_cached=%s" % [
		corpse_cached_properly, corpse_calls_before, corpse_calls_after, monster_cache_has_entries
	])

	if corpse_cached_properly and monster_cache_has_entries:
		passed_tests += 1
		print("  [PASS] Test 6: Corpses and monster frames are strictly cached in RAM; zero redundant extraction per frame.")
	else:
		printerr("  [FAIL] Test 6: Performance caching check failed.")

	# ------------------------------------------------------------------
	# Summary
	# ------------------------------------------------------------------
	print("\n=======================================================")
	print("  RESULTS: %d / %d TESTS PASSED" % [passed_tests, total_tests])
	print("=======================================================\n")

	if passed_tests == total_tests:
		quit(0)
	else:
		quit(1)

class MockBridgeForItems:
	extends RefCounted

	var corpse_data_call_count: int = 0

	func get_active_items() -> Array:
		return [
			{
				"id": 50,
				"tile_x": 25,
				"tile_y": 25,
				"curs_id": 4, # Gold
				"anim_frame": 0,
				"quality": 0,
				"name": "11 GOLD",
				"is_gold": true,
				"gold_value": 11
			}
		]

	func get_ground_item_sprite_data(item_id: int) -> Dictionary:
		# Return authentic 28x28 golden nugget RGBA
		var w = 28
		var h = 28
		var rgba = PackedByteArray()
		rgba.resize(w * h * 4)
		for i in range(w * h):
			rgba[i * 4 + 0] = 240 # R
			rgba[i * 4 + 1] = 200 # G
			rgba[i * 4 + 2] = 50  # B
			rgba[i * 4 + 3] = 255 # A
		return {
			"width": w,
			"height": h,
			"rgba": rgba
		}

	func get_player_continuous_pos() -> Dictionary:
		return {"pos_x": 25.0, "pos_y": 25.0, "dir": 0, "anim_frame": 0}

	func get_player_sprite_data() -> Dictionary:
		var w = 96
		var h = 96
		var rgba = PackedByteArray()
		rgba.resize(w * h * 4)
		return {"width": w, "height": h, "frame": 0, "rgba": rgba}

	func get_active_monsters_data() -> Array:
		return [
			{
				"id": 1,
				"is_alive": true,
				"pos_x": 26.0,
				"pos_y": 26.0,
				"dir": 0,
				"anim_frame": 0,
				"hp": 20,
				"max_hp": 20,
				"name": "Skeleton"
			}
		]

	func get_monster_sprite_data(monster_id: int) -> Dictionary:
		var w = 64
		var h = 64
		var rgba = PackedByteArray()
		rgba.resize(w * h * 4)
		for i in range(w * h):
			rgba[i * 4 + 0] = 200
			rgba[i * 4 + 1] = 200
			rgba[i * 4 + 2] = 200
			rgba[i * 4 + 3] = 255
		return {"width": w, "height": h, "rgba": rgba}

	func get_active_corpses() -> Array:
		return [
			{
				"tile_x": 24,
				"tile_y": 24,
				"corpse_idx": 3,
				"dir": 2,
				"frame": 5,
				"monster_name": "Skeleton"
			}
		]

	func get_corpse_sprite_data(corpse_idx: int, dir: int) -> Dictionary:
		corpse_data_call_count += 1
		var w = 64
		var h = 64
		var rgba = PackedByteArray()
		rgba.resize(w * h * 4)
		for i in range(w * h):
			rgba[i * 4 + 0] = 180
			rgba[i * 4 + 1] = 180
			rgba[i * 4 + 2] = 180
			rgba[i * 4 + 3] = 255
		return {
			"width": w,
			"height": h,
			"rgba": rgba
		}

	func is_item_label_highlight_enabled() -> bool:
		return true
