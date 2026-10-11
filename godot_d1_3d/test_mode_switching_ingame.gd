@tool
extends SceneTree

func _init():
	print("--- Testing Native 2.5D View and 3D Sandbox Switching ---")
	
	# Mock bridge
	var bridge_script = GDScript.new()
	bridge_script.source_code = """
extends RefCounted
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
func get_current_level(): return 1
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
func get_dungeon_piece_texture(pid): 
	var img = Image.create(64, 32, false, Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(img)
func get_special_cel_texture(sid): return null
func get_player_continuous_pos(): return {"pos_x": 25.0, "pos_y": 25.0, "dir": 0, "anim_frame": 0, "mode": 0}
func get_player_sprite_data(): return {"width": 96, "height": 96, "frame": 0, "rgba": PackedByteArray()}
func get_player_class(): return 0
func get_active_monsters_data(): return []
func get_active_objects(): return []
func get_active_items(): return []
func get_active_corpses(): return []
func get_active_missiles(): return []
func clear_dungeon_piece_cache(): pass
func is_modal_active(): return false
func get_gamma(): return 100
"""
	bridge_script.reload()
	var b_inst = bridge_script.new()

	var native_25d_script = load("res://scripts/native_25d_view.gd")
	var native_25d = Node2D.new()
	native_25d.set_script(native_25d_script)
	root.add_child(native_25d)
	native_25d.diablo_bridge = b_inst
	native_25d._ready()

	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = Node3D.new()
	sandbox.set_script(sandbox_script)
	root.add_child(sandbox)
	sandbox.diablo_bridge = b_inst
	sandbox.setup_scene_nodes()

	print("[1] Initially in Mode 2 (3D Sandbox)...")
	sandbox.activate()
	native_25d.deactivate()
	print("  Sandbox active: ", sandbox.is_sandbox_active)
	print("  2.5D active: ", native_25d.is_active)

	print("[2] Switching to Mode 0 (Blit)...")
	sandbox.deactivate()
	native_25d.deactivate()
	print("  Sandbox active: ", sandbox.is_sandbox_active)
	print("  2.5D active: ", native_25d.is_active)

	print("[3] Switching to Mode 1 (Native 2.5D)...")
	sandbox.deactivate()
	native_25d.activate()
	print("  Sandbox active: ", sandbox.is_sandbox_active)
	print("  2.5D active: ", native_25d.is_active)
	print("  2.5D pending_rebuild: ", native_25d.pending_dungeon_rebuild)
	print("  2.5D tile_sprites count: ", native_25d.tile_sprites.size())

	# Process frame 1
	native_25d._process(0.016)
	print("  After process frame 1: pending_rebuild=", native_25d.pending_dungeon_rebuild, " tile_sprites count=", native_25d.tile_sprites.size())

	# Process frame 2
	native_25d._process(0.016)
	print("  After process frame 2: pending_rebuild=", native_25d.pending_dungeon_rebuild, " tile_sprites count=", native_25d.tile_sprites.size())

	print("--- Success! ---")
	quit(0)
