@tool
extends SceneTree

func _init():
	print("--- Testing Real-Time 2.5D Door Opening & Closing Tile Synchronization ---")

	var bridge_script = GDScript.new()
	bridge_script.source_code = """
extends RefCounted
var cur_level: int = 1 # Cathedral
var sol = PackedByteArray()
var grid = PackedInt32Array()
var special = PackedInt32Array()
var light = PackedByteArray()
var active_objs = []

func _init():
	sol.resize(112 * 112)
	sol.fill(1)
	grid.resize(112 * 112)
	grid.fill(1) # Floor
	special.resize(112 * 112)
	special.fill(0)
	light.resize(112 * 112)
	light.fill(0)

	# Closed door at (25, 25): piece 43 (wall), solid = 2
	grid[25 * 112 + 25] = 43
	sol[25 * 112 + 25] = 2
	active_objs = [{
		"id": 1,
		"type": 1, # OBJ_L1LDOOR
		"tile_x": 25,
		"tile_y": 25,
		"anim_frame": 1,
		"pre_flag": false,
		"solid": true
	}]

func get_current_level(): return cur_level
func is_level_loading(): return false
func is_game_running(): return true
func get_dungeon_solidity_grid(): return sol
func get_dungeon_grid(): return grid
func get_dungeon_tile(x, y): return grid[y * 112 + x]
func get_dungeon_special_grid(): return special
func get_dungeon_light_grid(): return light
func get_dungeon_flags_grid(): return PackedByteArray()
func get_dungeon_trans_grid(): return PackedByteArray()
func get_dungeon_trans_mask(): return PackedByteArray()
func get_trans_list(): return PackedByteArray()
func get_active_monsters_data(): return []
func get_active_objects(): return active_objs
func get_active_lights(): return []
func get_active_items(): return []
func get_active_corpses(): return []
func get_active_missiles(): return []
func poll_visual_events(): return []
func get_player_continuous_pos(): return {"pos_x": 25.0, "pos_y": 26.0, "dir": 0, "anim_frame": 0}
func get_player_sprite_data(): return {}
func get_object_sprite_data(oid): return {"width": 0, "height": 0, "rgba": PackedByteArray()}

func get_dungeon_piece_texture(pid):
	var tw = 64
	# Piece 43 is wall (height 128 > tw/2); piece 392 is open floor (height 32 == tw/2)
	var th = 128 if pid == 43 else 32
	var img = Image.create(tw, th, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.6, 0.4, 0.2, 1.0))
	return ImageTexture.create_from_image(img)

func get_special_cel_texture(sid):
	var img = Image.create(64, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.8, 0.7, 0.3, 1.0))
	return ImageTexture.create_from_image(img)
"""
	var err = bridge_script.reload()
	if err != OK:
		print("Failed to reload bridge script: ", err)
		quit(1)
		return
	var bridge = bridge_script.new()

	var view_script = load("res://scripts/native_25d_view.gd")
	var view = view_script.new()
	view.diablo_bridge = bridge
	root.add_child(view)
	view.activate()

	print("\n[State 1: Initial Closed Door]")
	var door_pos = Vector2i(25, 25)
	assert(view.wall_sprites.has(door_pos), "ERROR: Closed door piece 43 must be instantiated as wall_sprites!")
	assert(not view.tile_sprites.has(door_pos), "ERROR: Closed door piece 43 must NOT be in tile_sprites!")
	var w_tex = view.wall_sprites[door_pos].texture
	assert(w_tex.get_height() > int(round(float(w_tex.get_width()) * 0.5)), "ERROR: Closed door texture must be wall (height > width/2)!")
	print("  [PASS] Closed door verified: wall_sprite active (piece 43, wall)")

	print("\n[State 2: Opening Door via D1 Engine]")
	# Engine opens door: piece changes to 392 (open floor), special becomes 7 (arch), pre_flag = true
	bridge.grid[25 * 112 + 25] = 392
	bridge.special[25 * 112 + 25] = 7
	bridge.sol[25 * 112 + 25] = 3 # Walkable doorway
	bridge.active_objs[0]["pre_flag"] = true
	bridge.active_objs[0]["solid"] = false

	# Run update_objects
	view.update_objects(bridge.get_dungeon_light_grid(), bridge.get_player_continuous_pos())

	assert(not view.wall_sprites.has(door_pos), "ERROR: Wall sprite must be removed when door opens!")
	assert(view.tile_sprites.has(door_pos), "ERROR: Floor sprite 392 must be created when door opens!")
	var f_tex = view.tile_sprites[door_pos].texture
	assert(f_tex.get_height() <= int(round(float(f_tex.get_width()) * 0.5)) + 4, "ERROR: Open door floor texture must be floor (height <= width/2)!")
	assert(view.special_sprites.has(door_pos), "ERROR: Special archway 7 must be created when door opens!")
	print("  [PASS] Open door verified: wall sprite removed, floor sprite 392 active, archway 7 active!")

	print("\n[State 3: Closing Door via D1 Engine]")
	# Engine closes door: piece changes back to 43 (wall), special becomes 0, pre_flag = false
	bridge.grid[25 * 112 + 25] = 43
	bridge.special[25 * 112 + 25] = 0
	bridge.sol[25 * 112 + 25] = 2
	bridge.active_objs[0]["pre_flag"] = false
	bridge.active_objs[0]["solid"] = true

	view.update_objects(bridge.get_dungeon_light_grid(), bridge.get_player_continuous_pos())

	assert(not view.tile_sprites.has(door_pos), "ERROR: Floor sprite must be removed when door closes!")
	assert(view.wall_sprites.has(door_pos), "ERROR: Wall sprite 43 must be restored when door closes!")
	var rw_tex = view.wall_sprites[door_pos].texture
	assert(rw_tex.get_height() > int(round(float(rw_tex.get_width()) * 0.5)), "ERROR: Restored closed door texture must be wall!")
	assert(not view.special_sprites.has(door_pos), "ERROR: Special archway must be removed when door closes!")
	print("  [PASS] Closed door verified: floor sprite removed, wall sprite 43 restored, archway removed!")

	view.queue_free()
	print("\n--- All Real-Time 2.5D Door Synchronization Tests Passed 100%! ---")
	quit(0)
