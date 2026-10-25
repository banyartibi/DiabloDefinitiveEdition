extends SceneTree

# ==============================================================================
# Verification: Upright Scenery Sprites (No Diagonal Door Clipping)
# & Monster Overhead Name/HP UI Polish
# ==============================================================================

class MockBridge extends RefCounted:
	var cur_lvl = 1
	var monsters = [
		{
			"id": 101,
			"name": "Skeleton Archer",
			"type": 5,
			"pos_x": 20.0,
			"pos_y": 20.0,
			"dir": 2,
			"hp": 20,
			"max_hp": 40,
			"is_alive": true,
			"is_visible": true,
			"anim_frame": 0,
			"action": "STAND"
		}
	]

	func get_current_level(): return cur_lvl
	func is_level_loading(): return false

	func get_dungeon_solidity_grid():
		var arr = PackedByteArray()
		arr.resize(112 * 112)
		arr.fill(1)
		arr[20 * 112 + 20] = 2 # Solid wall
		arr[20 * 112 + 21] = 2 # Door tile
		return arr

	func get_dungeon_grid():
		var arr = PackedInt32Array()
		arr.resize(112 * 112)
		arr.fill(1)
		arr[20 * 112 + 20] = 168 # Stone wall
		arr[20 * 112 + 21] = 169 # Doorway piece
		return arr

	func get_dungeon_special_grid():
		var arr = PackedInt32Array()
		arr.resize(112 * 112)
		arr.fill(0)
		arr[20 * 112 + 20] = 1 # Archway special CEL
		return arr

	func get_active_objects():
		return [
			{
				"id": 1,
				"type": 1, # Door
				"tile_x": 21,
				"tile_y": 20,
				"category": "DOOR",
				"is_open": false
			}
		]

	func get_dungeon_piece_texture(pid: int):
		var img = Image.create(64, 128, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.4, 0.4, 0.4, 1.0))
		return ImageTexture.create_from_image(img)

	func get_special_cel_texture(sid: int):
		var img = Image.create(64, 128, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.6, 0.6, 0.6, 1.0))
		return ImageTexture.create_from_image(img)

	func get_player_continuous_pos():
		return {"pos_x": 20.0, "pos_y": 20.0, "dir": 0, "anim_frame": 0}

	func get_player_sprite_data():
		return {"width": 0, "height": 0, "frame": 0, "dir": 0, "rgba": PackedByteArray()}

	func get_active_monsters_data():
		return monsters

	func get_monster_sprite_data(mid: int):
		return {"width": 0, "height": 0, "frame": 0, "dir": 0, "rgba": PackedByteArray()}

func _init():
	print("\n=======================================================")
	print(" Testing Upright Scenery Sprites & Monster UI Polish   ")
	print("=======================================================")

	var script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = script.new()
	var mock = MockBridge.new()
	sandbox.diablo_bridge = mock
	root.add_child(sandbox)
	sandbox.setup_scene_nodes()
	sandbox.modular_3d_walls_enabled = false

	# --------------------------------------------------------------------------
	# Part 1: Scenery Sprite Orientation (No Diagonal Room Piercing)
	# --------------------------------------------------------------------------
	print("\n[1/4] Verifying Upright Scenery Wall & Special Archway Sprites...")
	mock.cur_lvl = 1
	sandbox.activate()
	sandbox.camera_pitch = 30.0
	sandbox.camera_yaw = 0.0
	sandbox.rebuild_dungeon_if_needed(true)

	assert(sandbox.town_scenery_nodes.size() > 0, "ERROR: Wall scenery sprites must exist!")
	for spr in sandbox.town_scenery_nodes.values():
		assert(abs(spr.rotation.x) < 0.001, "ERROR: Scenery wall sprite must stand upright along Y! rotation.x was: %f" % spr.rotation.x)
	print("  PASS: All scenery wall sprites stand strictly upright (rotation.x == 0.0)!")

	assert(sandbox.special_scenery_nodes.size() > 0, "ERROR: Special CEL archway must exist!")
	for aspr in sandbox.special_scenery_nodes.values():
		assert(abs(aspr.rotation.x) < 0.001, "ERROR: Special archway sprite must stand upright along Y! rotation.x was: %f" % aspr.rotation.x)
		assert(aspr.sorting_offset == 1.0, "ERROR: Archway sprite must have sorting_offset == 1.0 to render cleanly in front of wall!")
	print("  PASS: Special CEL archways stand strictly upright with sorting_offset == 1.0!")

	# Orbit camera yaw: verify walls rotate in Y only and remain upright in X
	print("\n[2/4] Testing Camera Yaw Orbiting (Upright Invariant Preservation)...")
	sandbox.camera_yaw = 45.0
	sandbox.camera_pitch = 50.0
	sandbox.update_camera_transform()

	for spr in sandbox.town_scenery_nodes.values():
		assert(abs(spr.rotation.x) < 0.001, "ERROR: Scenery sprite rotation.x must stay 0.0 during orbit! Got: %f" % spr.rotation.x)
		assert(abs(spr.rotation.y - deg_to_rad(45.0)) < 0.01, "ERROR: Scenery sprite rotation.y must match yaw!")
	print("  PASS: Upright invariant preserved during camera orbit (rotation.x == 0.0, rotation.y == yaw)!")

	# --------------------------------------------------------------------------
	# Part 2: Monster Overhead Name & HP Bar Polish
	# --------------------------------------------------------------------------
	print("\n[3/4] Verifying Monster NameLabel & HPRoot Hierarchy & Render Priorities...")
	sandbox.update_monster_entities(0.016)
	var mnode = sandbox.monster_instances.get(101, null)
	assert(mnode != null, "ERROR: Monster node 101 must exist!")

	var lbl = mnode.get_node_or_null("NameLabel") as Label3D
	assert(lbl != null, "ERROR: NameLabel must exist!")
	assert(lbl.visible, "ERROR: NameLabel must be visible for active dungeon monster!")
	assert(lbl.font_size == 20, "ERROR: NameLabel font_size must be 20! Got: %d" % lbl.font_size)
	assert(abs(lbl.pixel_size - 0.0075) < 0.0001, "ERROR: NameLabel pixel_size must be 0.0075! Got: %f" % lbl.pixel_size)
	assert(lbl.render_priority == 27, "ERROR: NameLabel render_priority must be 27! Got: %d" % lbl.render_priority)
	assert(lbl.outline_render_priority == 26, "ERROR: NameLabel outline_render_priority must be 26! Got: %d" % lbl.outline_render_priority)
	assert(lbl.text.begins_with("Skeleton Archer [20/40]"), "ERROR: NameLabel text incorrect! Got: '%s'" % lbl.text)
	print("  PASS: NameLabel has authentic Exocet typography, high readability, and correct render priorities!")

	var hp_border = mnode.get_node_or_null("HPRoot/HPBorder") as MeshInstance3D
	var hp_bg = mnode.get_node_or_null("HPRoot/HPBg") as MeshInstance3D
	var hp_bar = mnode.get_node_or_null("HPRoot/HPBar") as MeshInstance3D

	assert(hp_border != null and hp_border.material_override.render_priority == 20, "ERROR: HPBorder must have render_priority 20!")
	assert(hp_bg != null and hp_bg.material_override.render_priority == 21, "ERROR: HPBg must have render_priority 21!")
	assert(hp_bar != null and hp_bar.material_override.render_priority == 22, "ERROR: HPBar must have render_priority 22!")
	print("  PASS: HPRoot has strict render layering: Border (20) -> Background (21) -> Health Bar (22)!")

	# Check HP Bar draining (at 20/40 HP = 50%, size.x should be 0.80 * 0.5 = 0.40)
	var quad = hp_bar.mesh as QuadMesh
	assert(abs(quad.size.x - 0.40) < 0.01, "ERROR: HPBar QuadMesh width must be 0.40 at 50%% HP! Got: %f" % quad.size.x)
	assert(abs(hp_bar.position.x - (-0.20)) < 0.01, "ERROR: HPBar position.x must be -0.20 at 50%% HP! Got: %f" % hp_bar.position.x)
	print("  PASS: Health bar cleanly drains towards left edge (width: 0.40m, pos.x: -0.20m)!")

	# --------------------------------------------------------------------------
	# Part 3: Monster Death & Town Isolation
	# --------------------------------------------------------------------------
	print("\n[4/4] Verifying Death & Town Hiding...")
	mock.monsters[0]["hp"] = 0
	sandbox.update_monster_entities(0.016)
	var hp_root = mnode.get_node_or_null("HPRoot")
	assert(not hp_root.visible, "ERROR: HPRoot must be hidden when monster dies (hp == 0)!")
	assert(not lbl.visible, "ERROR: NameLabel must be hidden when monster dies (hp == 0)!")
	print("  PASS: Dead monsters do not show overhead HP or Name labels!")

	# Friendly Town NPCs should also not show HP bars
	mock.cur_lvl = 0
	mock.monsters[0]["hp"] = 100
	sandbox.update_monster_entities(0.016)
	assert(not hp_root.visible, "ERROR: Town NPCs must never show overhead HP bars!")
	print("  PASS: Town NPCs safely hide HP bars!")

	sandbox.deactivate()
	sandbox.queue_free()

	print("\n=======================================================")
	print(" ALL SCENERY & MONSTER UI TESTS PASSED 100%!")
	print("=======================================================\n")
	quit(0)
