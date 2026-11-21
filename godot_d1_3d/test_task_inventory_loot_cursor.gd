extends SceneTree

# ==============================================================================
# Verification: Inventory Functions, Ground Loot Hover Accuracy, and Software/Gauntlet Cursor
# ==============================================================================

class MockBridge extends RefCounted:
	var _has_item := false
	var _cur_id := 1
	var _dropped := false
	var _clicked_slot_type := -1
	var _clicked_slot_idx := -1
	var _inv_version := 10

	func has_held_item() -> bool:
		return _has_item

	func get_cursor_id() -> int:
		return _cur_id

	func drop_held_item() -> bool:
		_dropped = true
		_has_item = false
		_cur_id = 1
		_inv_version += 1
		return true

	func get_inventory_version() -> int:
		return _inv_version

	func click_inventory_slot(slot_type: int, slot_idx: int, _shift: bool, _ctrl: bool) -> void:
		_clicked_slot_type = slot_type
		_clicked_slot_idx = slot_idx
		_inv_version += 1

	func get_player_backpack() -> Array:
		return [
			{
				"slot_id": 20, # bottom row index in devilution
				"cell_x": 0,
				"cell_y": 1,
				"cell_w": 2,
				"cell_h": 2,
				"curs_id": 14,
				"quality": 1,
				"can_use": true,
				"inv_list_index": 0
			}
		]

	func get_player_equipment() -> Array:
		return []

	func get_player_gold() -> int:
		return 5000

	func get_cursor_texture(cid: int) -> Texture2D:
		var img = Image.create(28, 28, false, Image.FORMAT_RGBA8)
		img.fill(Color.GOLD if cid == 1 else Color.WHITE)
		return ImageTexture.create_from_image(img)

	func is_game_running() -> bool:
		return true

	func is_text_input_active() -> bool:
		return false

	func get_last_action_seq() -> int:
		return 1

	func get_last_action_rng_seed() -> int:
		return 12345

	func is_hellfire() -> bool:
		return false

func _init():
	print("\n=======================================================")
	print(" Testing Inventory, Loot Hover & Cursor Architecture   ")
	print("=======================================================\n")

	var bridge = MockBridge.new()

	# --------------------------------------------------------------------------
	# Test 1: Software Cursor & Golden Gauntlet
	# --------------------------------------------------------------------------
	print("[1/4] Verifying Software Cursor & Authentic Gauntlet Cursor...")
	var hud_scene = load("res://scenes/hud/d1de_hud.tscn")
	var hud = hud_scene.instantiate()
	root.add_child(hud)
	hud.set_bridge(bridge)

	# Normal cursor (cid == 1)
	bridge._cur_id = 1
	bridge._has_item = false
	hud.update_custom_cursor()
	assert(hud.held_item_cursor != null, "ERROR: held_item_cursor should be initialized!")
	assert(hud.held_item_cursor.visible == false, "ERROR: software cursor must be hidden when not holding item!")
	assert(hud.last_custom_cursor_id == 1, "ERROR: gauntlet cursor must be active!")
	print("  PASS: Normal gameplay uses golden gauntlet cursor and hides software cursor!")

	# Held item cursor (cid >= 12, has_held_item == true)
	bridge._cur_id = 15
	bridge._has_item = true
	hud.update_custom_cursor()
	assert(hud.held_item_cursor.visible == true, "ERROR: software cursor must be visible when holding item!")
	assert(hud.held_item_cursor.texture != null, "ERROR: software cursor must have item texture assigned!")
	assert(hud.held_item_cursor.mouse_filter == Control.MOUSE_FILTER_IGNORE, "ERROR: software cursor must ignore mouse filter!")
	print("  PASS: Held items use dedicated Software Cursor TextureRect (bypassing OS cursor size limits)!")

	# --------------------------------------------------------------------------
	# Test 2: Backpack Sub-Cell Clicking & Continuous Update
	# --------------------------------------------------------------------------
	print("\n[2/4] Verifying Backpack Sub-Cell Grid Math & Automatic _process Update...")
	var inv_scene = load("res://scenes/hud/d1de_inventory.tscn")
	var inv = inv_scene.instantiate()
	root.add_child(inv)
	inv._ready()
	inv.set_bridge(bridge)
	inv.visible = true
	inv.update_inventory()

	var bp_overlay = inv.items_overlay
	assert(bp_overlay != null and bp_overlay.get_child_count() > 0, "ERROR: Backpack item overlay must contain items!")
	var item_node = bp_overlay.get_child(0)

	# Simulate clicking subcell (1, 1) inside a 2x2 item located at (cell_x: 0, cell_y: 1)
	# Cell size + gap is CELL_STEP (56.0). Subcell (1, 1) clicked at local position Vector2(60, 60)
	var fake_click = InputEventMouseButton.new()
	fake_click.button_index = MOUSE_BUTTON_LEFT
	fake_click.pressed = true
	fake_click.position = Vector2(60.0, 60.0)

	item_node.gui_input.emit(fake_click)
	# Expected target cell: (cell_y + 1) * 10 + (cell_x + 1) = (1 + 1) * 10 + (0 + 1) = 21
	assert(bridge._clicked_slot_type == 1, "ERROR: Must click backpack slot type (1)!")
	assert(bridge._clicked_slot_idx == 21, "ERROR: Must compute exact clicked sub-cell! Got: %d, expected: 21" % bridge._clicked_slot_idx)
	print("  PASS: Clicking sub-cell inside multi-cell item accurately routes to grid cell (21)!")

	# Verify _process calls check_and_update() when inventory is visible
	var ver_before = inv.last_inventory_version
	bridge._inv_version += 5
	inv._process(0.016)
	assert(inv.last_inventory_version == bridge._inv_version, "ERROR: _process must auto-sync inventory version when visible!")
	print("  PASS: Inventory _process() automatically detects engine state updates and refreshes immediately!")

	# Verify _gui_input on inventory does NOT drop held items
	bridge._has_item = true
	bridge._dropped = false
	var empty_area_click = InputEventMouseButton.new()
	empty_area_click.button_index = MOUSE_BUTTON_LEFT
	empty_area_click.pressed = true
	inv._gui_input(empty_area_click)
	assert(bridge._dropped == false, "ERROR: Clicking empty inventory dialog background must NEVER drop items to the ground!")
	print("  PASS: Clicking empty inventory dialog area does NOT accidentally drop items to ground!")

	# --------------------------------------------------------------------------
	# Test 3: Playfield Item Drop Across Modes
	# --------------------------------------------------------------------------
	print("\n[3/4] Verifying Playfield Item Drop Integration...")
	bridge._has_item = true
	bridge._dropped = false
	var playfield_click = InputEventMouseButton.new()
	playfield_click.button_index = MOUSE_BUTTON_LEFT
	playfield_click.pressed = true

	hud._unhandled_input(playfield_click)
	assert(bridge._dropped == true, "ERROR: Playfield left click via HUD must trigger diablo_bridge.drop_held_item()!")
	print("  PASS: Left-clicking playfield while holding item successfully drops item to dungeon floor!")

	# --------------------------------------------------------------------------
	# Test 4: Ground Loot 2D Screen Label Hover Accuracy & Tooltip Placement
	# --------------------------------------------------------------------------
	print("\n[4/4] Verifying Pixel-Perfect Ground Loot Hover & Tooltip Positioning...")
	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = sandbox_script.new()
	root.add_child(sandbox)
	sandbox.diablo_bridge = bridge
	sandbox.is_sandbox_active = true

	# Set up mock camera
	var cam = Camera3D.new()
	sandbox.add_child(cam)
	sandbox.camera = cam
	cam.look_at_from_position(Vector3(0, 10, 10), Vector3.ZERO, Vector3.UP)

	# Mock dropped ground item
	var item_root = Node3D.new()
	item_root.position = Vector3(0, 0, 0)
	item_root.set_meta("box_w", 1.2)
	item_root.set_meta("item_name", "Griswold's Edge")
	item_root.set_meta("quality", 2)
	item_root.set_meta("tile_x", 10)
	item_root.set_meta("tile_y", 10)
	sandbox.item_instances[55] = item_root
	sandbox.add_child(item_root)

	var label_root = Node3D.new()
	label_root.name = "LabelRoot"
	label_root.position = Vector3(0, 0.85, 0)
	item_root.add_child(label_root)

	var hit = sandbox.find_entity_under_ray(Vector2(640, 360))
	assert(hit.type == "ITEM", "ERROR: Hovering directly over ground label must detect ITEM! Got: %s" % hit.type)
	assert(hit.id == 55, "ERROR: Detected item id must match 55!")
	print("  PASS: Hovering directly on the ground loot label detects item with 100% precision (no raycast offset)!")

	# Cleanup
	hud.queue_free()
	inv.queue_free()
	sandbox.queue_free()

	print("\n=======================================================")
	print(" ALL INVENTORY, LOOT & CURSOR TESTS PASSED 100%!")
	print("=======================================================\n")
	quit(0)
