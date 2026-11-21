@tool
extends SceneTree

func _init():
	run_test_suite()

func run_test_suite():
	await process_frame
	print("==================================================")
	print(" Testing Task 5.1: 3D Raycast Pickup & Interaction")
	print("==================================================")

	var bridge_script = GDScript.new()
	bridge_script.source_code = """
extends RefCounted

var recorded_item_clicks = []
var recorded_object_clicks = []
var recorded_monster_clicks = []
var recorded_walk_clicks = []

var sol = PackedByteArray()
var grid = PackedInt32Array()
var light = PackedByteArray()

func _init():
	sol.resize(112 * 112)
	sol.fill(1)
	grid.resize(112 * 112)
	grid.fill(1)
	light.resize(112 * 112)
	light.fill(0)
	
	# Door at (25, 26)
	sol[26 * 112 + 25] = 2
	grid[26 * 112 + 25] = 43

func is_game_running(): return true
func is_level_loading(): return false
func is_modal_active(): return false
func is_text_input_active(): return false
func get_current_level(): return 1
func get_dungeon_solidity_grid(): return sol
func get_dungeon_grid(): return grid
func get_dungeon_light_grid(): return light
func get_dungeon_flags_grid(): return PackedByteArray()
func get_dungeon_trans_grid(): return PackedByteArray()
func get_dungeon_trans_mask(): return PackedByteArray()
func get_trans_list(): return PackedByteArray()
func get_dungeon_special_grid(): return PackedInt32Array()
func get_dungeon_piece_texture(pid): 
	var img = Image.create(64, 32, false, Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(img)
func get_player_continuous_pos(): return {"pos_x": 25.0, "pos_y": 25.0, "dir": 0, "anim_frame": 0}
func get_player_sprite_data(): return {"width": 96, "height": 96, "frame": 0, "rgba": PackedByteArray()}

func get_active_items():
	return [
		{
			"id": 101,
			"tile_x": 25,
			"tile_y": 27,
			"curs_id": 12,
			"quality": 0,
			"name": "Broad Sword",
			"anim_frame": 0
		},
		{
			"id": 102,
			"tile_x": 26,
			"tile_y": 27,
			"curs_id": 25,
			"quality": 2,
			"name": "The Butcher's Cleaver",
			"anim_frame": 0
		}
	]

func get_active_objects():
	return [
		{
			"id": 1,
			"type": 1, # Door
			"tile_x": 25,
			"tile_y": 26,
			"solid": true,
			"anim_frame": 1,
			"category": "DOOR"
		},
		{
			"id": 2,
			"type": 154, # Sarcophagus
			"tile_x": 24,
			"tile_y": 25,
			"solid": true,
			"anim_frame": 1,
			"category": "SARCOPHAGUS"
		}
	]

func get_active_monsters_data():
	return [
		{
			"id": 10,
			"is_alive": true,
			"pos_x": 28.0,
			"pos_y": 28.0,
			"dir": 2,
			"anim_frame": 1,
			"hp": 50,
			"max_hp": 50,
			"name": "Skeleton Archer"
		}
	]

func get_active_lights(): return []
func get_ground_item_sprite_data(iid):
	var rgba = PackedByteArray()
	rgba.resize(32 * 32 * 4)
	return {"width": 32, "height": 32, "rgba": rgba}
func get_object_sprite_data(oid):
	var rgba = PackedByteArray()
	rgba.resize(32 * 32 * 4)
	return {"width": 32, "height": 32, "rgba": rgba}
func get_monster_sprite_data(mid):
	return {"width": 64, "height": 64, "rgba": PackedByteArray()}

func interact_with_item(item_id: int, tx: int, ty: int):
	recorded_item_clicks.append({"id": item_id, "tile_x": tx, "tile_y": ty})

func interact_with_object(object_id: int, tx: int, ty: int):
	recorded_object_clicks.append({"id": object_id, "tile_x": tx, "tile_y": ty})

func interact_with_monster(monster_id: int):
	recorded_monster_clicks.append({"id": monster_id})

func walk_to_tile(tx: int, ty: int):
	recorded_walk_clicks.append({"tile_x": tx, "tile_y": ty})
"""
	bridge_script.reload()
	var mock_bridge = bridge_script.new()

	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = sandbox_script.new()
	sandbox.diablo_bridge = mock_bridge
	root.size = Vector2i(1280, 720)
	root.add_child(sandbox)
	sandbox.activate()

	# Center camera around player at tile (25, 25)
	sandbox.player_target_pos = sandbox.tile_to_world_3d(25.0, 25.0)
	sandbox.camera_target = sandbox.player_target_pos
	sandbox.camera_distance = 13.0
	sandbox.camera_yaw = 0.0
	sandbox.camera_pitch = 45.0
	sandbox.update_camera_transform()

	# Populate world entities
	sandbox.update_ground_items(0.016)
	sandbox.update_props(0.016)
	sandbox.update_monster_entities(0.016)

	assert(sandbox.item_instances.size() == 2, "Expected 2 ground items")
	assert(sandbox.prop_instances.size() == 2, "Expected 2 props")
	assert(sandbox.monster_instances.size() == 1, "Expected 1 monster")

	var cam = sandbox.camera

	# =========================================================================
	# Test 1: Ground Item Raycast & Selection
	# =========================================================================
	print("[1/5] Testing Ground Item Raycast Selection...")
	var item101 = sandbox.item_instances[101]
	var item101_screen = cam.unproject_position(item101.position + Vector3(0, 0.25, 0))
	var hit_item = sandbox.find_entity_under_ray(item101_screen)

	assert(hit_item.type == "ITEM", "Expected type ITEM, got %s" % hit_item.type)
	assert(hit_item.id == 101, "Expected item id 101, got %d" % hit_item.id)
	assert(hit_item.tile == Vector2i(25, 27), "Expected tile (25, 27), got %s" % str(hit_item.tile))
	print("  PASS: Item 101 ('Broad Sword') correctly selected via raycast")

	# =========================================================================
	# Test 2: Item Hover Visual Scaling & Outline
	# =========================================================================
	print("[2/5] Testing Item Hover Visual Reaction...")
	var lbl101 = item101.get_node_or_null("LabelRoot/ItemLabel") as Label3D
	if lbl101 == null:
		lbl101 = item101.get_node_or_null("ItemLabel") as Label3D
	assert(lbl101 != null, "ItemLabel must exist on item node")

	sandbox.update_hover(item101_screen)
	assert(lbl101.outline_modulate.r > 0.9, "ItemLabel outline must glow on hover")

	# Clear hover
	sandbox.update_hover(Vector2(-999, -999))
	assert(lbl101.outline_modulate.r < 0.2, "ItemLabel outline must reset to dark after unhover")
	print("  PASS: ItemLabel glows on hover, resets on unhover")

	# =========================================================================
	# Test 3: Monster Raycast & Selection
	# =========================================================================
	print("[3/5] Testing Monster Raycast Selection...")
	var m10 = sandbox.monster_instances[10]
	var m10_screen = cam.unproject_position(m10.position + Vector3(0, 0.9, 0))
	var hit_monster = sandbox.find_entity_under_ray(m10_screen)

	assert(hit_monster.type == "MONSTER", "Expected type MONSTER, got %s" % hit_monster.type)
	assert(hit_monster.id == 10, "Expected monster id 10, got %d" % hit_monster.id)
	assert(hit_monster.data.get("name", "") == "Skeleton Archer", "Monster name correct")
	print("  PASS: Monster 10 ('Skeleton Archer') correctly selected via raycast")

	# =========================================================================
	# Test 4: Prop / Door Raycast & Selection
	# =========================================================================
	print("[4/5] Testing Prop / Door Raycast Selection...")
	var prop1 = sandbox.prop_instances[1]
	var prop1_screen = cam.unproject_position(prop1.position + Vector3(0, 0.7, 0))
	var hit_prop = sandbox.find_entity_under_ray(prop1_screen)

	assert(hit_prop.type == "OBJECT", "Expected type OBJECT, got %s" % hit_prop.type)
	assert(hit_prop.id == 1, "Expected prop id 1, got %d" % hit_prop.id)
	print("  PASS: Prop 1 (Door) correctly selected via raycast")

	# =========================================================================
	# Test 5: Click Execution & Color-Coded Waypoint Rings
	# =========================================================================
	print("[5/5] Testing Click Command Dispatch & Color-Coded Ring Feedback...")

	# 5a. Click Item -> Gold Ring & interact_with_item
	var ev_item = InputEventMouseButton.new()
	ev_item.button_index = MOUSE_BUTTON_LEFT
	ev_item.pressed = true
	ev_item.position = item101_screen
	sandbox.handle_input(ev_item)

	assert(mock_bridge.recorded_item_clicks.size() == 1, "interact_with_item must be called")
	assert(mock_bridge.recorded_item_clicks[0].id == 101, "item id must match 101")
	assert(sandbox.click_marker.visible == true, "click marker must be visible")
	var mat_item = sandbox.click_marker.material_override as StandardMaterial3D
	assert(mat_item.albedo_color.r > 0.9 and mat_item.albedo_color.g > 0.8, "Item ring must be Gold/Amber")
	print("  PASS: Item click dispatched to interact_with_item with Gold ring")

	# 5b. Click Prop -> Cyan Ring & interact_with_object
	var ev_prop = InputEventMouseButton.new()
	ev_prop.button_index = MOUSE_BUTTON_LEFT
	ev_prop.pressed = true
	ev_prop.position = prop1_screen
	sandbox.handle_input(ev_prop)

	assert(mock_bridge.recorded_object_clicks.size() == 1, "interact_with_object must be called")
	assert(mock_bridge.recorded_object_clicks[0].id == 1, "object id must match 1")
	var mat_prop = sandbox.click_marker.material_override as StandardMaterial3D
	assert(mat_prop.albedo_color.b > 0.9 and mat_prop.albedo_color.r < 0.3, "Object ring must be Cyan/Azure")
	print("  PASS: Prop click dispatched to interact_with_object with Cyan ring")

	# 5c. Click Monster -> Crimson Ring & interact_with_monster
	var ev_monst = InputEventMouseButton.new()
	ev_monst.button_index = MOUSE_BUTTON_LEFT
	ev_monst.pressed = true
	ev_monst.position = m10_screen
	sandbox.handle_input(ev_monst)

	assert(mock_bridge.recorded_monster_clicks.size() == 1, "interact_with_monster must be called")
	assert(mock_bridge.recorded_monster_clicks[0].id == 10, "monster id must match 10")
	var mat_monst = sandbox.click_marker.material_override as StandardMaterial3D
	assert(mat_monst.albedo_color.r > 0.9 and mat_monst.albedo_color.g < 0.3, "Monster ring must be Crimson")
	print("  PASS: Monster click dispatched to interact_with_monster with Crimson ring")

	# 5d. Click Ground Tile -> Yellow Ring & walk_to_tile
	var ground_wpos = sandbox.tile_to_world_3d(20.0, 20.0)
	var ground_screen = cam.unproject_position(ground_wpos)
	var ev_ground = InputEventMouseButton.new()
	ev_ground.button_index = MOUSE_BUTTON_LEFT
	ev_ground.pressed = true
	ev_ground.position = ground_screen
	sandbox.handle_input(ev_ground)

	assert(mock_bridge.recorded_walk_clicks.size() == 1, "walk_to_tile must be called")
	assert(mock_bridge.recorded_walk_clicks[0].tile_x == 20 and mock_bridge.recorded_walk_clicks[0].tile_y == 20, "Ground tile coordinates correct")
	var mat_ground = sandbox.click_marker.material_override as StandardMaterial3D
	assert(mat_ground.albedo_color.r > 0.9 and mat_ground.albedo_color.g > 0.7, "Ground ring must be Yellow")
	print("  PASS: Ground click dispatched to walk_to_tile with Yellow ring")

	print("==================================================")
	print(" ALL TASK 5.1 3D RAYCAST & INTERACTION TESTS PASSED! ")
	print("==================================================")
	quit(0)
