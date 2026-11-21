extends SceneTree

const FloatingCombatTextManager = preload("res://scripts/floating_combat_text.gd")

class MockReceiver extends Node:
	var d1de_hud = null

class MockLootBridge:
	var items: Array = []
	var char_info: Dictionary = {
		"str_now": 25,
		"dex_now": 18,
		"mag_now": 10,
		"level": 3
	}

	func get_active_items() -> Array: return items
	func get_character_info() -> Dictionary: return char_info
	func get_current_level() -> int: return 1
	func get_gamma() -> int: return 100
	func is_engine_ready() -> bool: return true
	func is_game_running() -> bool: return true
	func is_vanilla_hud_hidden() -> bool: return true
	func get_player_hp() -> int: return 100
	func get_player_max_hp() -> int: return 100
	func get_player_mana() -> int: return 50
	func get_player_max_mana() -> int: return 50
	func get_player_xp() -> int: return 1000
	func get_player_next_level_xp() -> int: return 2000
	func get_target_monster_id() -> int: return -1
	func has_hover_item() -> bool: return false
	func get_player_level() -> int: return 3
	func get_player_next_xp() -> int: return 2000
	func get_player_gold() -> int: return 500
	func get_last_action_seq() -> int: return 0
	func get_player_continuous_pos() -> Dictionary:
		return { "pos_x": 25.0, "pos_y": 25.0, "dir": 0, "anim_frame": 0, "action": "IDLE" }
	func get_dungeon_solidity_grid() -> PackedByteArray:
		var arr = PackedByteArray()
		arr.resize(112 * 112)
		return arr
	func get_monsters() -> Array: return []
	func get_active_lights() -> Array: return []
	func get_wall_occluders() -> Array: return []
	func get_active_objects() -> Array: return []
	func get_active_corpses() -> Array: return []
	func get_active_missiles() -> Array: return []
	func poll_combat_events() -> Array: return []

func _init():
	print("==================================================================")
	print("  TEST: MODERN ARPG GROUND LOOT LABELS & D4 TOOLTIP VERIFICATION")
	print("==================================================================")
	call_deferred("_run_tests")

func _run_tests():
	await process_frame
	root.size = Vector2i(1280, 720)

	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	assert(sandbox_script != null, "Failed to load native_3d_sandbox.gd")

	var sandbox = sandbox_script.new()
	root.add_child(sandbox)
	await process_frame

	var mock_bridge = MockLootBridge.new()
	sandbox.diablo_bridge = mock_bridge
	sandbox.activate()

	# Center camera around player at tile (25, 25)
	sandbox.player_target_pos = sandbox.tile_to_world_3d(25.0, 25.0)
	sandbox.camera_target = sandbox.player_target_pos
	sandbox.camera_distance = 13.0
	sandbox.camera_yaw = 0.0
	sandbox.camera_pitch = 45.0
	sandbox.update_camera_transform()
	await process_frame

	# Setup mock HUD
	var hud_scene = load("res://scenes/hud/d1de_hud.tscn")
	var hud = hud_scene.instantiate()
	hud.diablo_bridge = mock_bridge
	root.add_child(hud)
	hud.set_process(false)
	hud.set_physics_process(false)
	await process_frame

	var main_mock = MockReceiver.new()
	main_mock.d1de_hud = hud
	sandbox.main_receiver = main_mock

	# Define 3 rich test items: Normal Bow, Magic Sword, Unique Cleaver
	mock_bridge.items = [
		{
			"id": 101,
			"tile_x": 24,
			"tile_y": 25,
			"curs_id": 1,
			"quality": 0,
			"quality_name": "NORMAL",
			"name": "Short Bow",
			"item_type": 2,
			"type_desc": "Two-Handed Bow",
			"min_dam": 1,
			"max_dam": 4,
			"ac": 0,
			"durability": 30,
			"max_dur": 30,
			"req_str": 0,
			"req_dex": 20, # Higher than player's 18 -> should trigger unmet warning
			"req_mag": 0,
			"value": 35,
			"magic_desc": ""
		},
		{
			"id": 102,
			"tile_x": 26,
			"tile_y": 25,
			"curs_id": 2,
			"quality": 1,
			"quality_name": "MAGIC",
			"name": "Amber Broad Sword",
			"item_type": 0,
			"type_desc": "One-Handed Sword",
			"min_dam": 4,
			"max_dam": 12,
			"ac": 0,
			"durability": 45,
			"max_dur": 50,
			"req_str": 20,
			"req_dex": 0,
			"req_mag": 0,
			"value": 480,
			"magic_desc": "+18% Resist Lightning | +10 to Attack Rating"
		},
		{
			"id": 103,
			"tile_x": 25,
			"tile_y": 26,
			"curs_id": 3,
			"quality": 2,
			"quality_name": "UNIQUE",
			"name": "The Butcher's Cleaver",
			"item_type": 1,
			"type_desc": "One-Handed Axe",
			"min_dam": 4,
			"max_dam": 24,
			"ac": 0,
			"durability": 10,
			"max_dur": 10,
			"req_str": 25,
			"req_dex": 0,
			"req_mag": 0,
			"value": 2400,
			"magic_desc": "+10 to Strength | Steals 20% Life | Indestructible"
		}
	]

	print("[1/4] Testing ground item creation and modern ARPG label box geometry...")
	sandbox.update_ground_items(0.016)
	await process_frame

	assert(sandbox.item_instances.size() == 3, "All 3 items should be spawned")
	var bow_node = sandbox.item_instances.get(101, null)
	assert(bow_node != null, "Bow node should exist")

	var label_root = bow_node.get_node_or_null("LabelRoot") as Node3D
	assert(label_root != null, "LabelRoot container must exist")
	assert(label_root.position.y >= 0.80, "LabelRoot must be elevated above corpses (>= 0.80m, is %0.2f)" % label_root.position.y)

	var bg_quad = label_root.get_node_or_null("LabelBg") as MeshInstance3D
	assert(bg_quad != null and bg_quad.mesh is QuadMesh, "Dark slate LabelBg QuadMesh must exist")

	var border_quad = label_root.get_node_or_null("LabelBorder") as MeshInstance3D
	assert(border_quad != null and border_quad.mesh is QuadMesh, "Quality LabelBorder QuadMesh must exist")

	var lbl = label_root.get_node_or_null("ItemLabel") as Label3D
	assert(lbl != null and lbl.text == "Short Bow", "ItemLabel text must match 'Short Bow'")
	print("  PASS: Ground item created with elevated LabelRoot (y=%0.2fm), dark slate backing, border, and text." % label_root.position.y)

	print("\n[2/4] Testing label visibility (Always-Visible Modern ARPG Invariant)...")
	assert(bow_node.visible == true, "Item node must be visible by default")
	assert(label_root.visible == true, "LabelRoot must be visible by default without requiring hover")
	print("  PASS: Ground loot labels are always visible on drop (D2R / D3 / PoE style).")

	print("\n[3/4] Testing Fixed Comfortable Size & Hover Highlight (No Scale Jump Invariant)...")
	assert(lbl.font_size == 22, "Font size must be fixed at larger comfortable size 22")
	var cleaver_node = sandbox.item_instances.get(103, null)
	assert(cleaver_node != null, "The Butcher's Cleaver node must exist")
	var cleaver_box_w = float(cleaver_node.get_meta("box_w", 0.0))
	assert(cleaver_box_w >= 1.5, "Box width for 'The Butcher's Cleaver' must accommodate full text width (is %0.2f)" % cleaver_box_w)

	sandbox._set_item_hover(bow_node, true)
	assert(label_root.scale == Vector3.ONE, "Scale must remain constant (no jarring scale jumps on hover)")
	assert(lbl.scale == Vector3.ONE, "Label scale must remain constant")
	var b_mat = border_quad.material_override as StandardMaterial3D
	assert(b_mat.albedo_color.r > 0.9 and b_mat.albedo_color.g > 0.8, "LabelBorder must glow gold on hover")
	assert(lbl.outline_modulate.r > 0.9, "Label outline must glow white on hover")

	sandbox._reset_item_hover(bow_node)
	assert(label_root.scale == Vector3.ONE, "Scale must remain constant on unhover")
	print("  PASS: Constant comfortable larger size (font 22, dynamic padding box), radiant golden border on hover without scale jump.")

	print("\n[4/4] Testing Diablo IV Style Tooltip Card on Hover...")
	var bow_screen = sandbox.camera.unproject_position(bow_node.position + Vector3(0, 0.25, 0))
	var hit = sandbox.find_entity_under_ray(bow_screen)
	print("  DEBUG: Ray hit type=", hit.type, " id=", hit.id, " bow_screen=", bow_screen)
	sandbox.update_hover(bow_screen)
	await process_frame

	assert(hud.item_tooltip != null, "HUD item_tooltip must exist")
	assert(hud.item_tooltip.visible == true, "Diablo IV tooltip card must become visible on hover")
	assert(hud.item_title_label.text == "Short Bow", "Tooltip title must be 'Short Bow'")

	var stats_text = hud.item_stats_label.text
	assert(stats_text.contains("TWO-HANDED BOW"), "Tooltip must display category banner 'TWO-HANDED BOW'")
	assert(stats_text.contains("DAMAGE: 1 - 4"), "Tooltip must display primary stat 'DAMAGE: 1 - 4'")
	assert(stats_text.contains("Durability: 30 / 30"), "Tooltip must display durability 'Durability: 30 / 30'")
	assert(stats_text.contains("Dex: 20"), "Tooltip must display Dexterity requirement")
	assert(stats_text.contains("(! Dex: 20 !)"), "Unmet Dexterity requirement (18 < 20) must trigger warning indicator")
	assert(stats_text.contains("Left Click to Pick Up"), "Tooltip must display '[ Left Click to Pick Up ]'")
	print("  PASS: Diablo IV Tooltip Card populated with full combat stats, durability, unmet requirement warning, and pickup prompt.")

	# Test Unhover hides Tooltip Card
	sandbox.update_hover(Vector2(-999, -999))
	await process_frame
	assert(hud.item_tooltip.visible == false, "Tooltip card must hide cleanly on unhover")
	print("  PASS: Tooltip card hides cleanly on unhover.")

	print("\n==================================================================")
	print("  ALL MODERN ARPG LOOT & D4 TOOLTIP TESTS PASSED 100%!")
	print("==================================================================")
	sandbox.queue_free()
	hud.queue_free()
	main_mock.queue_free()
	quit(0)
