@tool
extends SceneTree

func _init():
	print("--- Testing 3D -> Blit -> 2.5D Mode Switching ---")

	var bridge_script = GDScript.new()
	bridge_script.source_code = """
extends RefCounted
var cur_level: int = 0
var sol = PackedByteArray()
var grid = PackedInt32Array()
var light = PackedByteArray()

func _init():
	sol.resize(112 * 112)
	sol.fill(1)
	grid.resize(112 * 112)
	grid.fill(218) # Town grass
	light.resize(112 * 112)
	light.fill(0)

func get_current_level(): return cur_level
func is_level_loading(): return false
func is_game_running(): return true
func get_dungeon_solidity_grid(): return sol
func get_dungeon_grid(): return grid
func get_dungeon_light_grid(): return light
func get_dungeon_flags_grid(): return PackedByteArray()
func get_dungeon_trans_grid(): return PackedByteArray()
func get_dungeon_trans_mask(): return PackedByteArray()
func get_trans_list(): return PackedByteArray()
func get_dungeon_special_grid(): return PackedInt32Array()
func get_active_monsters_data(): return []
func get_active_objects(): return []
func get_active_lights(): return []
func get_active_items(): return []
func get_active_corpses(): return []
func get_active_missiles(): return []
func get_gamma(): return 100
func get_player_continuous_pos(): return {"pos_x": 75.0, "pos_y": 68.0, "dir": 0, "anim_frame": 0}
func get_player_sprite_data(): return {"width": 96, "height": 96, "frame": 0, "rgba": PackedByteArray()}
func get_player_class(): return 0
func clear_dungeon_piece_cache(): pass
func is_item_label_highlight_enabled(): return false
func set_zoom_vision_radius(_r): pass
func map_world_to_screen(v): return Vector2i(int(v.x), int(v.y))
func is_modal_active(): return false

func get_dungeon_piece_texture(pid):
	var tw = 64
	var th = 32
	var img = Image.create(tw, th, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.5, 0.2, 1.0))
	return ImageTexture.create_from_image(img)
"""
	bridge_script.reload()
	var bridge = bridge_script.new()

	var main_scene = load("res://scenes/main_3d.tscn")
	var main = main_scene.instantiate()
	main.diablo_bridge = bridge
	root.add_child(main)

	# Simulate game running
	main.last_is_ingame = true

	print("[Step 1] Switch to Mode 2 (3D Sandbox)")
	main.switch_display_mode(2)
	for i in range(5):
		main._process(0.016)
		if main.sandbox_instance:
			main.sandbox_instance._process(0.016)

	print("[Step 2] Switch to Mode 0 (Classic 2.5D Blit)")
	main.switch_display_mode(0)
	for i in range(5):
		main._process(0.016)

	print("[Step 3] Switch to Mode 1 (Native 2.5D)")
	main.switch_display_mode(1)
	for i in range(5):
		main._process(0.016)
		if main.native_25d_instance:
			main.native_25d_instance._process(0.016)

	print("\n--- Diagnostic Results for Mode 1 (Native 2.5D) ---")
	var n25d = main.native_25d_instance
	print("n25d is_active: ", n25d.is_active)
	print("n25d visible: ", n25d.visible)
	print("n25d tile_sprites count: ", n25d.tile_sprites.size())
	print("n25d wall_sprites count: ", n25d.wall_sprites.size())
	print("n25d last_visible_tiles count: ", n25d.last_visible_tiles.size())
	print("n25d pending_dungeon_rebuild: ", n25d.pending_dungeon_rebuild)
	print("n25d pending_secondary_rebuild: ", n25d.pending_secondary_rebuild)
	if n25d.camera:
		print("n25d camera position: ", n25d.camera.position)
		print("n25d camera enabled: ", n25d.camera.enabled)
	print("main.camera current: ", main.camera.current)

	var visible_count = 0
	for spr in n25d.tile_sprites.values():
		if spr.visible:
			visible_count += 1
	print("n25d visible tile_sprites: ", visible_count)

	quit(0)
