extends SceneTree

# ==============================================================================
# Comprehensive Verification: Level Transitions, Teleport Isolation & Scaling
# ==============================================================================

class MockBridge extends RefCounted:
	var cur_lvl = 9 # Start in Caves
	var player_spellcasting = false

	func get_current_level():
		return cur_lvl

	func is_level_loading():
		return false

	func get_dungeon_solidity_grid():
		var arr = PackedByteArray()
		arr.resize(112 * 112)
		arr.fill(1)
		arr[20 * 112 + 20] = 2 # rock wall
		return arr

	func get_dungeon_grid():
		var arr = PackedInt32Array()
		arr.resize(112 * 112)
		arr.fill(2) # piece 2 (Lava in Caves, Pathway in Town)
		arr[20 * 112 + 20] = 168 # piece 168 (Rock in Caves, Fence in Town)
		return arr

	func get_dungeon_special_grid():
		var arr = PackedInt32Array()
		arr.resize(112 * 112)
		arr.fill(0)
		return arr

	func get_active_objects():
		return []

	func get_active_items():
		return [
			{"id": 1, "curs_id": 19, "anim_frame": 0, "quality": 0, "name": "Healing Potion", "tile_x": 25, "tile_y": 25}
		]

	func get_ground_item_sprite_data(i_id: int):
		var img = Image.create(28, 28, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.8, 0.1, 0.1, 1.0))
		return {"width": 28, "height": 28, "rgba": img.get_data()}

	func get_dungeon_piece_texture(pid: int):
		var img = Image.create(64, 128, false, Image.FORMAT_RGBA8)
		# Distinct color based on level
		if cur_lvl == 0:
			img.fill(Color(0.1, 0.8, 0.2, 1.0)) # Bright grass green in town
		else:
			img.fill(Color(0.9, 0.2, 0.05, 1.0)) # Burning lava red in caves
		return ImageTexture.create_from_image(img)

	func get_player_continuous_pos():
		return {"pos_x": 25.0, "pos_y": 25.0, "dir": 0, "anim_frame": 0}

	func get_player_sprite_data():
		if player_spellcasting:
			# Wide spell cast frame (width = 144 > 120)
			var img = Image.create(144, 144, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.2, 0.4, 0.9, 1.0))
			return {"width": 144, "height": 144, "rgba": img.get_data(), "frame": 5, "dir": 0}
		else:
			# Normal idle/walk frame (width = 96)
			var img = Image.create(96, 96, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.8, 0.7, 0.5, 1.0))
			return {"width": 96, "height": 96, "rgba": img.get_data(), "frame": 0, "dir": 0}

	func get_active_monsters_data():
		if cur_lvl == 0:
			return []
		return [
			{"id": 5, "name": "Cave Bat", "pos_x": 22.0, "pos_y": 22.0, "dir": 0, "anim_frame": 1, "hp": 50, "max_hp": 50, "is_alive": true}
		]

	func get_monster_sprite_data(m_id: int):
		var img = Image.create(130, 100, false, Image.FORMAT_RGBA8) # Winged bat width > 120
		img.fill(Color(0.4, 0.2, 0.5, 1.0))
		return {"width": 130, "height": 100, "rgba": img.get_data(), "frame": 1, "dir": 0}

func _init():
	print("\n=======================================================")
	print(" Testing Level Transition, Teleport & Scaling Fixes")
	print("=======================================================")

	var mock_bridge = MockBridge.new()
	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = Node3D.new()
	sandbox.set_script(sandbox_script)
	root.add_child(sandbox)

	sandbox.diablo_bridge = mock_bridge
	sandbox._ready()
	sandbox.activate()

	# 1. Step in Caves (Level 9)
	mock_bridge.cur_lvl = 9
	sandbox._process(0.016)
	sandbox.update_ground_items(0.016)

	# Verify Caves floor material cache
	var caves_mat = sandbox.get_floor_material(2, 9)
	assert(caves_mat != null, "Caves floor material must exist")
	print("  PASS: Level 9 (Caves) initialized with distinct floor material")

	# Check monster scale
	var bat_node = sandbox.monster_instances.get(5, null)
	assert(bat_node != null, "Bat monster must exist in Caves")
	var bat_spr = bat_node.get_node("MonsterSprite3D") as Sprite3D
	assert(abs(bat_spr.pixel_size - sandbox.PIXEL_SIZE_1X) < 0.0001, "Monster sprite must use PIXEL_SIZE_1X even when width > 120")
	print("  PASS: Monster with width > 120 uses PIXEL_SIZE_1X (not shrunken to miniature): %f" % bat_spr.pixel_size)

	# Check dropped item scale
	var item_node = sandbox.item_instances.get(1, null)
	var item_spr = item_node.get_node("ItemSprite") as Sprite3D
	var is_hd_item = sandbox.item_is_hd_cache.get("19_0", false)
	var expected_item_scale = (sandbox.PIXEL_SIZE_HD if is_hd_item else sandbox.PIXEL_SIZE_1X) * 1.75
	assert(abs(item_spr.pixel_size - expected_item_scale) < 0.0001, "Item sprite must have +75% boost")
	print("  PASS: Ground item receives +75%% visibility boost: %f" % item_spr.pixel_size)

	# 2. Check Player Spellcast Sizing
	# Normal state
	sandbox.update_player_entity(0.016)
	var p_spr = sandbox.player_sprite
	assert(abs(p_spr.pixel_size - sandbox.PIXEL_SIZE_1X) < 0.0001, "Normal player sprite uses PIXEL_SIZE_1X")
	# Spellcast state (width = 144)
	mock_bridge.player_spellcasting = true
	sandbox.last_player_frame = -999 # force frame refresh
	sandbox.update_player_entity(0.016)
	assert(abs(p_spr.pixel_size - sandbox.PIXEL_SIZE_1X) < 0.0001, "Spellcasting player sprite MUST remain PIXEL_SIZE_1X (never miniature)")
	print("  PASS: Player spellcasting sprite (width=144) maintains heroic PIXEL_SIZE_1X scale: %f" % p_spr.pixel_size)

	# 3. Teleport to Town (Level 0)
	print("\n[Teleport Test] Teleporting from Caves to Town (Level 0)...")
	mock_bridge.cur_lvl = 0
	# _process triggers _on_level_changed instantly!
	sandbox._process(0.016)

	# Verify Caves monsters are purged
	assert(sandbox.monster_instances.is_empty(), "All cave monsters must be purged upon teleport to Town")
	print("  PASS: Monster instances completely wiped on level transition")

	# Verify Town floor material is isolated and NOT Caves lava
	var town_mat = sandbox.get_floor_material(2, 0)
	assert(town_mat != caves_mat, "Town floor material must NOT be reused Caves material!")
	var town_tex = town_mat.albedo_texture
	assert(town_tex != null, "Town floor must have a valid bridge texture")
	print("  PASS: Town Piece 2 is completely isolated from Caves Piece 2 (GEMINI.md Rule #1 enforced)!")

	# Verify Town special CEL arches are 0
	assert(sandbox.special_scenery_nodes.is_empty(), "Town must NEVER build special CEL archways (GEMINI.md Rule #2 enforced)!")
	print("  PASS: Town has 0 special CEL archways")

	sandbox.deactivate()
	sandbox.queue_free()

	print("\n=======================================================")
	print(" ALL LEVEL TRANSITION & SCALING TESTS PASSED 100%!")
	print("=======================================================\n")
	quit(0)
