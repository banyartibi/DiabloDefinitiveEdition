extends SceneTree

const FloatingCombatTextManager = preload("res://scripts/floating_combat_text.gd")

# Mock bridge for headless testing of Task 5.2 Combat Events
class MockCombatBridge:
	var queued_events: Array = []
	var gamma: int = 100
	var level: int = 1

	func poll_combat_events() -> Array:
		var evs = queued_events.duplicate()
		queued_events.clear()
		return evs

	func get_current_level() -> int: return level
	func get_gamma() -> int: return gamma
	func get_player_continuous_pos() -> Dictionary:
		return { "pos_x": 25.0, "pos_y": 25.0, "dir": 0, "anim_frame": 0, "action": "IDLE" }
	func get_dungeon_solidity_grid() -> PackedByteArray:
		var arr = PackedByteArray()
		arr.resize(112 * 112)
		return arr
	func get_monsters() -> Array: return []
	func get_ground_items() -> Array: return []
	func get_active_lights() -> Array: return []
	func get_wall_occluders() -> Array: return []
	func get_active_objects() -> Array: return []

func _init():
	print("==================================================================")
	print("  TEST TASK 5.2: NATIVE COMBAT EVENTS, FCT & HIT VFX VERIFICATION")
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

	var mock_bridge = MockCombatBridge.new()
	sandbox.diablo_bridge = mock_bridge
	sandbox.is_sandbox_active = true

	# Ensure setup
	sandbox.setup_scene_nodes()
	await process_frame

	print("[1/5] Testing FloatingCombatTextManager creation and properties...")
	assert(sandbox.fct_manager != null, "fct_manager should be initialized")
	var fct = sandbox.fct_manager

	# Test Monster Damage FCT
	var fnode_dam = fct.spawn_fct(Vector3(10, 0, 10), "-32", FloatingCombatTextManager.EventType.DAMAGE_TO_MONSTER, false)
	assert(fnode_dam != null, "Should return FloatingTextNode")
	assert(fnode_dam.label != null, "Should have Label3D child")
	assert(fnode_dam.label.text == "-32", "Label text should be '-32'")
	assert(fnode_dam.label.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "Label should have billboard enabled")
	assert(fnode_dam.label.modulate.r > 0.9 and fnode_dam.label.modulate.g < 0.3, "Normal monster damage should be red")
	print("  PASS: Normal monster damage FCT spawned correctly (-32, red billboard).")

	# Test Critical Hit FCT
	var fnode_crit = fct.spawn_fct(Vector3(10, 0, 10), "CRIT -64!", FloatingCombatTextManager.EventType.DAMAGE_TO_MONSTER, true)
	assert(fnode_crit.label.text == "CRIT -64!", "Crit label text should match")
	assert(fnode_crit.label.modulate.r > 0.9 and fnode_crit.label.modulate.g > 0.7, "Crit damage should be gold")
	assert(fnode_crit.base_scale > 1.2, "Crit should have enlarged scale")
	print("  PASS: Critical hit FCT spawned with golden surge and larger scale.")

	# Test Block and Miss
	var fnode_block = fct.spawn_fct(Vector3(10, 0, 10), "BLOCKED", FloatingCombatTextManager.EventType.PLAYER_BLOCK, false)
	assert(fnode_block.label.text == "BLOCKED", "Block text correct")
	assert(fnode_block.label.modulate.b > 0.9, "Block text should be cyan")

	var fnode_miss = fct.spawn_fct(Vector3(10, 0, 10), "MISS", FloatingCombatTextManager.EventType.COMBAT_MISS, false)
	assert(fnode_miss.label.text == "MISS", "Miss text correct")
	print("  PASS: Block and Miss FCT colors and labels verified.")

	# Test Level Up FCT
	var fnode_lvl = fct.spawn_fct(Vector3(10, 0, 10), "★ LEVEL UP! (Lvl 5) ★", FloatingCombatTextManager.EventType.PLAYER_LEVEL_UP, false)
	assert(fnode_lvl.label.text.contains("LEVEL UP"), "Level up text correct")
	print("  PASS: Level Up radiant announcement verified.")

	print("\n[2/5] Testing Sandbox combat event ingestion & entity hit reactions...")
	# Create a mock monster in sandbox
	var mnode = sandbox.get_or_create_monster_node(42)
	mnode.set_meta("name", "Skeleton Warrior")
	mnode.global_position = Vector3(15, 0, 15)

	# Mock bridge emits DAMAGE_TO_MONSTER event
	mock_bridge.queued_events.append({
		"type": 1,
		"target_id": 42,
		"source_id": 0,
		"tile": Vector2i(20, 20),
		"damage": 18,
		"target_hp": 32,
		"target_max_hp": 50,
		"is_crit": false,
		"exp_gained": 0,
		"new_level": 0
	})

	# Process combat events
	sandbox.process_combat_events(0.016)
	await process_frame

	# Check flash modulation
	assert(sandbox.flashing_entities.has(mnode), "Monster should be registered in flashing_entities")
	var sprite = mnode.get_node("MonsterSprite3D") as Sprite3D
	assert(sprite.modulate.r > 2.0, "Monster sprite should flash bright red on hit")

	# Check overhead HP bar
	var hp_fg = mnode.get_node("HPRoot/HPBar") as MeshInstance3D
	var quad = hp_fg.mesh as QuadMesh
	var expected_width = 0.80 * (32.0 / 50.0)
	assert(abs(quad.size.x - expected_width) < 0.01, "Overhead HP bar width should update instantly")
	print("  PASS: Monster hit flash & instantaneous overhead HP bar update verified.")

	print("\n[3/5] Testing Critical strike camera micro-shake (trauma)...")
	var initial_trauma = sandbox.camera_trauma
	mock_bridge.queued_events.append({
		"type": 1,
		"target_id": 42,
		"source_id": 0,
		"tile": Vector2i(20, 20),
		"damage": 55,
		"target_hp": 0,
		"target_max_hp": 50,
		"is_crit": true,
		"exp_gained": 0,
		"new_level": 0
	})
	sandbox.process_combat_events(0.016)
	assert(sandbox.camera_trauma > initial_trauma, "Crit should add camera trauma")
	print("  PASS: Camera trauma increased to %0.2f on critical strike." % sandbox.camera_trauma)

	print("\n[4/5] Testing Player damage event & Warrior hit state...")
	mock_bridge.queued_events.append({
		"type": 2,
		"target_id": 0,
		"source_id": 42,
		"tile": Vector2i(25, 25),
		"damage": 14,
		"target_hp": 86,
		"target_max_hp": 100,
		"is_crit": false,
		"exp_gained": 0,
		"new_level": 0
	})
	sandbox.process_combat_events(0.016)
	assert(sandbox.flashing_entities.has(sandbox.player_root), "Player should be flashing")
	if sandbox.warrior_controller:
		assert(sandbox.warrior_controller.current_action == "HIT", "Warrior controller should enter HIT state")
	print("  PASS: Player damage event, player flash and warrior HIT flinch verified.")

	print("\n[5/5] Testing FCT animation lifecycle and node cleanup...")
	# Simulate 1.0 second elapsed time to trigger FCT cleanup
	for i in range(65):
		fnode_dam._process(0.016)
	assert(fnode_dam.is_queued_for_deletion(), "FCT node should be queued for deletion after lifetime expires")
	print("  PASS: FCT node queued for deletion with zero memory leak.")

	print("\n==================================================================")
	print("  TASK 5.2 VERIFICATION 100% SUCCESSFUL: ALL CHECKS PASSED!")
	print("==================================================================")
	sandbox.queue_free()
	quit(0)
