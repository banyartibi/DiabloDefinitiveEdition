@tool
extends SceneTree

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

func _init() -> void:
	var bridge = ClassDB.instantiate("DiabloBridge")
	root.add_child(bridge)
	bridge.init_engine(MPQ_DIR)
	while not bridge.is_engine_ready():
		OS.delay_msec(20)
	bridge.menu_select_single_player()
	OS.delay_msec(400)
	bridge.launch_hero_game(2, 0, true)
	while not bridge.is_game_running():
		OS.delay_msec(20)
	OS.delay_msec(1200)

	var view_25d_script = load("res://scripts/native_25d_view.gd")
	var view_25d = view_25d_script.new()
	root.add_child(view_25d)
	view_25d.diablo_bridge = bridge
	view_25d._init_bridge_caps()
	view_25d.setup_scene_hierarchy()
	view_25d.rebuild_dungeon_tiles()

	# Center camera on (54, 54)
	if view_25d.camera:
		view_25d.camera.position = Vector2((54.0 - 54.0) * 32.0, (54.0 + 54.0) * 16.0)
		view_25d.camera.zoom = Vector2(1.0, 1.0)

	var lights = bridge.get_dungeon_light_grid()
	var ppos = {"pos_x": 54.0, "pos_y": 54.0}
	view_25d.update_objects(lights, ppos)

	# Print object sprites in view_25d
	print("--- 2.5D OBJECT SPRITES ---")
	for oid in view_25d.object_sprites.keys():
		var spr = view_25d.object_sprites[oid]
		if spr:
			print("2.5D Obj id=%d: pos=%s, offset=%s, vis=%s" % [oid, str(spr.position), str(spr.offset), str(spr.visible)])

	# Check wall sprites and floor sprites around (54, 54)
	print("Tile sprite at (54, 54): ", view_25d.tile_sprites.get(Vector2i(54, 54), null))
	print("Wall sprite at (50, 50): ", view_25d.wall_sprites.get(Vector2i(50, 50), null))
	print("Wall sprite at (50, 54): ", view_25d.wall_sprites.get(Vector2i(50, 54), null))

	quit(0)
