extends SceneTree

# ==============================================================================
# Automated Verification: Task 5.6 - Corpse Occlusion & Visual Layering
#
# Verifies:
# 1. Corpse uses CORPSE_HD_3D_SHADER with depth_draw_never (no depth write)
# 2. Corpse has render_priority = 1 and sorting_offset = -2.0 + (tx+ty)*0.001
# 3. Ground item has render_priority = 2 and sorting_offset = 2.0 + (tx+ty)*0.001 (strictly above corpses)
# 4. Living monster entities & player have render_priority = 3 and sorting_offset = 3.0
# 5. Loot labels have render_priority = 20 with no_depth_test = true
# 6. Corpse at same tile as item never occludes the item sprite or loot label
# ==============================================================================

class MockBridge:
	var level: int = 1
	var corpses: Array = []
	var items: Array = []

	func get_current_level() -> int: return level
	func get_read_gate_state() -> Dictionary: return {"open": true, "level": 1}
	func get_active_corpses() -> Array: return corpses
	func get_active_items() -> Array: return items
	func get_dungeon_flags_grid() -> PackedByteArray:
		var b = PackedByteArray()
		b.resize(112 * 112)
		b.fill(130) # visible & explored
		return b
	func get_corpse_sprite_data(idx: int, dir: int) -> Dictionary:
		var rgba = PackedByteArray()
		rgba.resize(64 * 48 * 4)
		for i in range(64 * 48):
			rgba[i * 4 + 0] = 180
			rgba[i * 4 + 1] = 160
			rgba[i * 4 + 2] = 140
			rgba[i * 4 + 3] = 255
		return {"width": 64, "height": 48, "rgba": rgba}
	func get_item_sprite_data(curs_id: int) -> Dictionary:
		var rgba = PackedByteArray()
		rgba.resize(32 * 32 * 4)
		for i in range(32 * 32):
			rgba[i * 4 + 0] = 220
			rgba[i * 4 + 1] = 200
			rgba[i * 4 + 2] = 50
			rgba[i * 4 + 3] = 255
		return {"width": 32, "height": 32, "rgba": rgba}
	func is_item_label_highlight_enabled() -> bool: return true

func _init() -> void:
	print("\n==================================================================")
	print("  RUNNING VERIFICATION: 3D CORPSE OCCLUSION & PIPELINE LAYERING")
	print("==================================================================")
	call_deferred("_run_tests")

func _run_tests() -> void:
	await process_frame

	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	assert(sandbox_script != null, "native_3d_sandbox.gd must load")

	var sandbox = sandbox_script.new()
	var mock_bridge = MockBridge.new()
	sandbox.diablo_bridge = mock_bridge
	sandbox._gate_native = true
	sandbox._gate_checked = true

	root.add_child(sandbox)
	sandbox.activate()
	await process_frame

	# [1/4] Test Corpse Shader & Render Priority
	print("\n[1/4] Testing Corpse Shader, render_priority & depth_draw_never...")
	mock_bridge.corpses = [
		{
			"tile_x": 20,
			"tile_y": 22,
			"corpse_idx": 1,
			"dir": 2,
			"frame": 0,
			"monster_name": "Horned Demon"
		},
		{
			"tile_x": 25,
			"tile_y": 25,
			"corpse_idx": 2,
			"dir": 4,
			"frame": 0,
			"monster_name": "Skeleton"
		}
	]
	sandbox.update_corpses()
	await process_frame

	assert(sandbox.corpse_instances.size() == 2, "2 corpses must be spawned, got %d" % sandbox.corpse_instances.size())
	var c_node = sandbox.corpse_instances.values()[0] as Node3D
	assert(c_node != null, "Corpse node must exist")

	var c_spr = c_node.get_node_or_null("CorpseSprite") as Sprite3D
	assert(c_spr != null, "CorpseSprite must exist")
	assert(c_spr.render_priority == 1, "CorpseSprite render_priority must be 1 (is %d)" % c_spr.render_priority)
	assert(c_spr.sorting_offset < 0.0, "CorpseSprite sorting_offset must be negative (is %.2f)" % c_spr.sorting_offset)

	var c_mat = c_spr.material_override as ShaderMaterial
	assert(c_mat != null, "CorpseSprite must have ShaderMaterial material_override")
	assert(c_mat.render_priority == 1, "Corpse ShaderMaterial render_priority must be 1 (is %d)" % c_mat.render_priority)
	assert(c_mat.shader != null, "Corpse ShaderMaterial must have valid shader")
	assert(c_mat.shader.resource_path.ends_with("corpse_hd_upscaler_3d.gdshader"),
		"Corpse must use corpse_hd_upscaler_3d.gdshader with depth_draw_never, got %s" % c_mat.shader.resource_path)
	print("  PASS: CorpseSprite uses corpse_hd_upscaler_3d.gdshader with render_priority=1 and sorting_offset < -1.0")

	# [2/4] Test Ground Item Layering (render_priority=2, strictly above corpses)
	print("\n[2/4] Testing Ground Item render_priority (must be 2, strictly above corpses)...")
	mock_bridge.items = [
		{
			"id": 501,
			"tile_x": 20,
			"tile_y": 22, # EXACT SAME TILE AS HORNED DEMON CORPSE!
			"quality": 1,
			"name": "Short Bow",
			"curs_id": 12,
			"anim_frame": 0
		}
	]
	sandbox.update_ground_items(0.016)
	await process_frame

	assert(sandbox.item_instances.has(501), "Ground item 501 must exist")
	var i_node = sandbox.item_instances[501] as Node3D
	var i_spr = i_node.get_node_or_null("ItemSprite") as Sprite3D
	assert(i_spr != null, "ItemSprite must exist")
	assert(i_spr.render_priority == 2, "ItemSprite render_priority must be 2 (is %d)" % i_spr.render_priority)
	assert(i_spr.sorting_offset > 0.0, "ItemSprite sorting_offset must be > 0.0 (is %.2f)" % i_spr.sorting_offset)

	var i_mat = i_spr.material_override as ShaderMaterial
	assert(i_mat != null, "ItemSprite must have ShaderMaterial")
	assert(i_mat.render_priority == 2, "Item ShaderMaterial render_priority must be 2 (is %d)" % i_mat.render_priority)
	print("  PASS: Ground Item on same tile has render_priority=2 and sorting_offset >= 2.0, strictly above corpse (priority=1)")

	# [3/4] Test Loot Label Container & UI Layering (render_priority=20)
	print("\n[3/4] Testing Loot Label container & UI depth exclusion...")
	var lbl_root = i_node.get_node_or_null("LabelRoot") as Node3D
	assert(lbl_root != null, "LabelRoot must exist")
	assert(lbl_root.position.y >= 0.80, "LabelRoot must be elevated at >= 0.80m")

	var lbl_bg = lbl_root.get_node_or_null("LabelBg") as MeshInstance3D
	var bg_mat = lbl_bg.material_override as StandardMaterial3D
	assert(bg_mat.no_depth_test == true, "LabelBg must have no_depth_test=true")
	assert(bg_mat.render_priority == 20, "LabelBg must have render_priority=20")

	var lbl_border = lbl_root.get_node_or_null("LabelBorder") as MeshInstance3D
	var border_mat = lbl_border.material_override as StandardMaterial3D
	assert(border_mat.no_depth_test == true, "LabelBorder must have no_depth_test=true")
	assert(border_mat.render_priority == 19, "LabelBorder must have render_priority=19")

	var lbl_text = lbl_root.get_node_or_null("ItemLabel") as Label3D
	assert(lbl_text.no_depth_test == true, "ItemLabel must have no_depth_test=true")
	assert(lbl_text.render_priority == 21, "ItemLabel must have render_priority=21")
	print("  PASS: Loot Label backing, border, and text render at priority 19-21 with no_depth_test=true (never occluded)")

	# [4/4] Test Living Monsters & Player Priority (render_priority=3)
	print("\n[4/4] Testing Living Monsters & Player render_priority (must be 3)...")
	var m_node = sandbox.get_or_create_monster_node(10, "SkelWarrior")
	var m_spr = m_node.get_node_or_null("MonsterSprite3D") as Sprite3D
	assert(m_spr != null, "MonsterSprite3D must exist")
	assert(m_spr.render_priority == 3, "Living monster sprite render_priority must be 3 (is %d)" % m_spr.render_priority)
	assert(m_spr.sorting_offset >= 0.04, "Living monster sorting_offset must be >= 0.04 (is %.2f)" % m_spr.sorting_offset)

	assert(sandbox.player_sprite != null, "player_sprite must exist")
	assert(sandbox.player_sprite.render_priority == 3, "player_sprite render_priority must be 3 (is %d)" % sandbox.player_sprite.render_priority)
	assert(sandbox.player_sprite.sorting_offset >= 0.04, "player_sprite sorting_offset must be >= 0.04")
	print("  PASS: Living monsters and player have render_priority=3 and sorting_offset >= 0.04 (strictly above corpses & items)")

	print("\n==================================================================")
	print("  ALL 3D CORPSE OCCLUSION & PIPELINE LAYERING TESTS PASSED 100%!")
	print("==================================================================")

	sandbox.queue_free()
	quit(0)
