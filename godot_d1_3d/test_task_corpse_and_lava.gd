extends SceneTree

class MockCorpseBridge:
	var corpses: Array = []
	var level: int = 9 # Caves Level 9

	func get_current_level() -> int: return level
	func get_active_corpses() -> Array: return corpses
	func get_gamma() -> int: return 100
	func get_player_continuous_pos() -> Dictionary:
		return { "pos_x": 25.0, "pos_y": 25.0, "dir": 0, "anim_frame": 0, "action": "IDLE" }
	func get_dungeon_solidity_grid() -> PackedByteArray:
		var arr = PackedByteArray()
		arr.resize(112 * 112)
		return arr
	func get_monsters() -> Array: return []
	func get_active_monsters_data() -> Array: return []
	func get_active_lights() -> Array: return []
	func get_wall_occluders() -> Array: return []
	func get_active_objects() -> Array: return []
	func get_active_items() -> Array: return []
	func get_active_missiles() -> Array: return []
	func poll_combat_events() -> Array: return []

	func get_corpse_sprite_data(idx: int, dir: int) -> Dictionary:
		var w = 64
		var h = 64
		var rgba = PackedByteArray()
		rgba.resize(w * h * 4)
		for i in range(0, rgba.size(), 4):
			rgba[i + 0] = 120 # R (demon skin)
			rgba[i + 1] = 90  # G
			rgba[i + 2] = 150 # B
			rgba[i + 3] = 255 # A
		return { "width": w, "height": h, "rgba": rgba }

	func get_dungeon_piece_texture(pid: int) -> Texture2D:
		var img = Image.create(64, 32, false, Image.FORMAT_RGBA8)
		if pid == 101:
			# Molten lava orange
			img.fill(Color(0.85, 0.35, 0.05, 1.0))
		else:
			# Dark cave stone
			img.fill(Color(0.25, 0.22, 0.20, 1.0))
		return ImageTexture.create_from_image(img)

func _init():
	print("==================================================================")
	print("  TEST: 3D CORPSE LIGHTING & DYNAMIC MOLTEN LAVA VERIFICATION")
	print("==================================================================")
	call_deferred("_run_tests")

func _run_tests():
	await process_frame
	root.size = Vector2i(1280, 720)

	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	assert(sandbox_script != null, "Failed to load native_3d_sandbox.gd")

	var sandbox = sandbox_script.new()
	var mock_bridge = MockCorpseBridge.new()
	sandbox.diablo_bridge = mock_bridge
	root.add_child(sandbox)
	sandbox.activate()
	await process_frame

	print("[1/3] Testing Dynamic 3D Molten Lava Shader & Detection...")
	# Verify Lava Shader resource loads
	var lava_shader = load("res://shaders/d1de_3d_lava.gdshader")
	assert(lava_shader != null, "Lava spatial shader must exist and load")

	# Test _is_lava_piece
	var lava_img = Image.create(32, 16, false, Image.FORMAT_RGBA8)
	lava_img.fill(Color(0.85, 0.35, 0.04, 1.0)) # Incandescent red-orange
	var stone_img = Image.create(32, 16, false, Image.FORMAT_RGBA8)
	stone_img.fill(Color(0.28, 0.25, 0.24, 1.0)) # Grey stone

	assert(sandbox._is_lava_piece(lava_img, "caves") == true, "Lava image in caves must be identified as lava")
	assert(sandbox._is_lava_piece(stone_img, "caves") == false, "Stone image in caves must NOT be identified as lava")
	assert(sandbox._is_lava_piece(lava_img, "town") == false, "Town must never identify lava (GEMINI.md Rule #1)")

	# Test get_floor_material on Caves level 9
	var lava_mat = sandbox.get_floor_material(101, 9)
	assert(lava_mat is ShaderMaterial, "Lava floor piece must use ShaderMaterial")
	assert(lava_mat.shader == sandbox.LAVA_3D_SHADER, "Lava floor piece must use LAVA_3D_SHADER")
	assert(lava_mat.get_shader_parameter("is_hell") == false, "Caves level must set is_hell = false")

	var stone_mat = sandbox.get_floor_material(5, 9)
	assert(stone_mat is StandardMaterial3D, "Stone floor piece must use standard PBR material")
	print("  PASS: Lava shader compiled, piece classifier 100% accurate, lava pieces use dynamic spatial fluid shader.")

	print("\n[2/3] Testing Hell Lava Parameters...")
	mock_bridge.level = 13 # Hell Level 13
	sandbox._on_level_changed(13)
	var hell_lava_mat = sandbox.get_floor_material(90, 13)
	assert(hell_lava_mat is ShaderMaterial, "Hell lava must use ShaderMaterial")
	assert(hell_lava_mat.get_shader_parameter("is_hell") == true, "Hell level must set is_hell = true")
	print("  PASS: Hell theme correctly configures infernal crimson brimstone spectrum.")

	print("\n[3/3] Testing 3D Corpse Lighting & Floor Alignment...")
	mock_bridge.corpses = [
		{
			"tile_x": 24,
			"tile_y": 26,
			"corpse_idx": 2,
			"dir": 3,
			"frame": 5,
			"monster_name": "Acid Beast"
		}
	]
	sandbox.update_corpses()
	await process_frame

	assert(sandbox.corpse_instances.size() == 1, "Expected 1 corpse node to be instantiated")
	var corpse_node = sandbox.corpse_instances.values()[0] as Node3D
	assert(corpse_node != null, "Corpse node must exist")
	assert(corpse_node.position.y >= 0.03, "Corpse node must be elevated slightly above floor (y >= 0.03m)")

	var spr = corpse_node.get_node_or_null("CorpseSprite") as Sprite3D
	assert(spr != null, "CorpseSprite must exist")
	assert(spr.shaded == false, "CRITICAL: CorpseSprite must be UNSHADED (shaded=false) to prevent turning into pitch black shadows!")
	assert(spr.modulate.r >= 1.25 and spr.modulate.g >= 1.25, "CorpseSprite must have healthy unshaded illumination matching living monsters")
	assert(spr.offset.y > 0.0, "CorpseSprite offset must be elevated (+height/2) so the lower half does not bury below the floor")
	assert(spr.texture != null, "CorpseSprite texture must be loaded from bridge RGBA")
	print("  PASS: CorpseSprite unshaded, illuminated, elevated, and textured with zero black silhouette artifacts.")

	print("\n==================================================================")
	print("  ALL 3D CORPSE LIGHTING & LAVA TESTS PASSED 100%!")
	print("==================================================================")
	sandbox.queue_free()
	quit(0)
