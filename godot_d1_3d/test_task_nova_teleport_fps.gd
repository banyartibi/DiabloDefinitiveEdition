extends SceneTree

# ==============================================================================
# VERIFICATION TEST: NOVA SPELL, TELEPORT & COMBAT 144 FPS OPTIMIZATIONS
# Tests:
# 1. 3D Missile RAM Texture Cache (36 Nova missiles share cached ImageTextures)
# 2. 3D Forward+ Dynamic Light & Particle Capping (max 4 lights & 4 particles for 36 missiles)
# 3. 3D Monster Animation RAM Cache (5 mobs hit simultaneously share textures)
# 4. 3D Corpse RAM Cache (multiple corpses share textures without per-frame GPU reloads)
# 5. Instant Teleport Snapping (player & camera snap on large delta without sliding)
# 6. 2.5D Mode Spell Light Shadow Immunity (spell lights never cast 2D wall shadows, capped at 4)
# ==============================================================================

class MockBridgeForNova:
	var missiles_called: int = 0
	var monsters_called: int = 0
	var corpses_called: int = 0
	var player_pos = {"pos_x": 25.0, "pos_y": 25.0, "dir": 0, "anim_frame": 0}
	var missiles_list = []
	var monsters_list = []
	var corpses_list = []
	var lights_list = []

	func is_game_running(): return true
	func is_level_loading(): return false
	func get_current_level(): return 1
	func get_player_continuous_pos(): return player_pos
	func get_player_sprite_data(): return {"width": 64, "height": 64, "rgba": PackedByteArray()}
	func get_player_class(): return 2 # Sorcerer
	func get_active_monsters_data(): return monsters_list
	func get_active_corpses(): return corpses_list
	func get_active_missiles(): return missiles_list
	func get_active_lights(): return lights_list
	func get_active_objects(): return []
	func get_active_items(): return []
	func poll_visual_events(): return []
	func get_dungeon_solidity_grid():
		var b = PackedByteArray()
		b.resize(112 * 112)
		return b
	func get_dungeon_grid():
		var a = PackedInt32Array()
		a.resize(112 * 112)
		return a

	func get_missile_sprite_data(mid: int):
		missiles_called += 1
		var arr = PackedByteArray()
		arr.resize(32 * 32 * 4)
		return {"width": 32, "height": 32, "rgba": arr}

	func get_monster_sprite_data(mid: int):
		monsters_called += 1
		var arr = PackedByteArray()
		arr.resize(64 * 64 * 4)
		return {"width": 64, "height": 64, "rgba": arr}

	func get_corpse_sprite_data(c_idx: int, c_dir: int):
		corpses_called += 1
		var arr = PackedByteArray()
		arr.resize(64 * 64 * 4)
		return {"width": 64, "height": 64, "rgba": arr}

func _init():
	print("\n=======================================================")
	print("  TEST TASK: NOVA SPELL, TELEPORT & COMBAT 144 FPS")
	print("=======================================================")

	var root = Node3D.new()
	var b = MockBridgeForNova.new()

	# -------------------------------------------------------------
	# Test 1 & 2: 3D Missile RAM Cache and Dynamic Light/Particle Capping
	# -------------------------------------------------------------
	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = Node3D.new()
	sandbox.set_script(sandbox_script)
	root.add_child(sandbox)
	sandbox.diablo_bridge = b
	sandbox._ready()
	sandbox.activate()

	# Simulate 36 Nova lightning missiles radiating outward
	b.missiles_list.clear()
	for i in range(36):
		var dir = i % 8
		b.missiles_list.append({
			"id": i,
			"type": 3, # Lightning / Nova
			"dir": dir,
			"pos_x": 25.0 * 32.0,
			"pos_y": 25.0 * 16.0,
			"anim_frame": 1,
			"light_flag": true,
			"pre_flag": false
		})

	b.missiles_called = 0
	sandbox.update_missiles(0.016)

	var unique_dir_frame = 8 # 8 distinct directions for frame 1
	assert(b.missiles_called == unique_dir_frame, "Missiles called should be exactly 8 for 8 distinct dirs, got %d" % b.missiles_called)
	assert(sandbox.missile_textures.size() >= 8, "Missile textures dictionary must contain cached textures")

	# Count visible dynamic lights and active particles among the 36 missiles
	var visible_lights = 0
	var active_particles = 0
	for m_node in sandbox.missiles_root.get_children():
		var l = m_node.get_node_or_null("MissileLight") as OmniLight3D
		if l and l.visible:
			visible_lights += 1
		var p = m_node.get_node_or_null("MissileSparkParticles")
		if p != null:
			active_particles += 1

	assert(visible_lights <= 4, "Active missile lights must be capped at <= 4, got %d" % visible_lights)
	assert(active_particles <= 4, "Active missile particles must be capped at <= 4, got %d" % active_particles)
	print("  [PASS] Test 1 & 2: 36 Nova missiles share RAM textures; dynamic lights capped at %d (<=4), particles at %d (<=4)" % [visible_lights, active_particles])

	# Subsequent frame with same missiles: bridge should NOT be called again
	var calls_before = b.missiles_called
	sandbox.update_missiles(0.016)
	assert(b.missiles_called == calls_before, "Missile cache hit must result in 0 bridge calls!")
	print("  [PASS] Test 1b: Subsequent frame for 36 missiles results in 0 bridge calls (100% RAM cache hit)")

	# -------------------------------------------------------------
	# Test 3: 3D Monster Animation RAM Cache (5 mobs hit simultaneously)
	# -------------------------------------------------------------
	b.monsters_list.clear()
	for i in range(5):
		b.monsters_list.append({
			"id": 100 + i,
			"name": "Skeleton Archer",
			"type": 1,
			"mode": 4, # MM_HURT
			"dir": 2,
			"anim_frame": 1,
			"pos_x": 26.0 + float(i) * 0.5,
			"pos_y": 25.0,
			"hp": 20,
			"max_hp": 50,
			"is_alive": true
		})

	b.monsters_called = 0
	sandbox.update_monster_entities(0.016)
	assert(b.monsters_called == 1, "5 identical monsters in same animation frame must call bridge exactly ONCE (RAM cache), got %d" % b.monsters_called)
	assert(sandbox.monster_anim_cache.size() >= 1, "Monster anim cache must store entry")

	var m_calls_before = b.monsters_called
	sandbox.update_monster_entities(0.016)
	assert(b.monsters_called == m_calls_before, "Subsequent monster update must result in 0 bridge calls!")
	print("  [PASS] Test 3: 5 monsters hit simultaneously share RAM cache; bridge called only once, subsequent frames 0 calls")

	# -------------------------------------------------------------
	# Test 4: 3D Corpse RAM Cache
	# -------------------------------------------------------------
	b.corpses_list.clear()
	for i in range(5):
		b.corpses_list.append({
			"tile_x": 24 + i,
			"tile_y": 24,
			"corpse_idx": 7,
			"dir": 3
		})

	b.corpses_called = 0
	sandbox.update_corpses()
	assert(b.corpses_called == 1, "5 corpses of same type/dir must call bridge exactly ONCE, got %d" % b.corpses_called)
	assert(sandbox.corpse_textures.has("7_3"), "Corpse texture 7_3 must be cached in corpse_textures")
	print("  [PASS] Test 4: 5 dead corpses share cached texture; bridge called once for all 5")

	# -------------------------------------------------------------
	# Test 5: Instant Teleport Snapping
	# -------------------------------------------------------------
	sandbox.player_root.position = Vector3(0, 0, 0)
	sandbox.camera_target = Vector3(0, 0, 0)
	# Simulate Teleport jump to (35, 35) (delta = 10 tiles ~= 10.6 meters)
	b.player_pos = {"pos_x": 35.0, "pos_y": 35.0, "dir": 0, "anim_frame": 0}
	sandbox.update_player_entity(0.016)
	sandbox.update_camera_tracking(0.016)

	var target_wpos = sandbox.tile_to_world_3d(35.0, 35.0)
	assert(sandbox.player_root.position.distance_to(target_wpos) < 0.01, "Player must snap immediately on Teleport jump!")
	assert(sandbox.camera_target.distance_to(target_wpos) < 0.01, "Camera target must snap immediately on Teleport jump!")
	print("  [PASS] Test 5: Teleport jump (>4m) immediately snaps player position and camera target without sliding")

	# -------------------------------------------------------------
	# Test 6: 2.5D Mode Spell Light Shadow Immunity & Capping
	# -------------------------------------------------------------
	var view_25d_script = load("res://scripts/native_25d_view.gd")
	var view_25d = Node2D.new()
	view_25d.set_script(view_25d_script)
	root.add_child(view_25d)
	view_25d.diablo_bridge = b
	view_25d.enable_wall_occluders = true
	view_25d._ready()

	# Set up 20 lights: index 0 = player, 1..3 = env torches, 4..19 = spell lights (type 2)
	b.lights_list.clear()
	b.lights_list.append({"tile_x": 25, "tile_y": 25, "radius": 10, "type": 0})
	for i in range(1, 4):
		b.lights_list.append({"tile_x": 25 + i, "tile_y": 25, "radius": 7, "type": 1})
	for i in range(4, 20):
		b.lights_list.append({"tile_x": 25, "tile_y": 25 + i, "radius": 6, "type": 2}) # Spell/Nova

	var dummy_light_grid = PackedByteArray()
	dummy_light_grid.resize(112 * 112)
	view_25d.update_torches(dummy_light_grid, {"pos_x": 25.0, "pos_y": 25.0})

	var spell_lights_with_shadows = 0
	var visible_spell_lights = 0
	for i in range(1, view_25d.torch_lights.size()):
		var pl = view_25d.torch_lights[i] as PointLight2D
		if pl and pl.visible:
			if i >= 4:
				visible_spell_lights += 1
				if pl.shadow_enabled:
					spell_lights_with_shadows += 1

	assert(spell_lights_with_shadows == 0, "Spell/Nova lights must NEVER have shadow_enabled=true!")
	assert(visible_spell_lights <= 4, "Active spell lights in 2.5D must be capped at <= 4, got %d" % visible_spell_lights)
	print("  [PASS] Test 6: In 2.5D, spell lights strictly have shadow_enabled=false and are capped at %d (<=4)" % visible_spell_lights)

	print("\n=======================================================")
	print("  RESULTS: ALL NOVA, TELEPORT & COMBAT TESTS PASSED 100%!")
	print("=======================================================\n")
	root.queue_free()
	quit(0)
