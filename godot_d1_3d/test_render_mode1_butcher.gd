@tool
extends SceneTree

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

func _init() -> void:
	var bridge = ClassDB.instantiate("DiabloBridge")
	root.add_child(bridge)
	bridge.init_engine(MPQ_DIR)
	while not bridge.is_engine_ready(): OS.delay_msec(20)
	bridge.menu_select_single_player()
	OS.delay_msec(400)
	bridge.launch_hero_game(2, 0, true)
	while not bridge.is_game_running(): OS.delay_msec(20)
	OS.delay_msec(1000)

	var vp = SubViewport.new()
	vp.size = Vector2i(1024, 768)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var view_25d_script = load("res://scripts/native_25d_view.gd")
	var view_25d = view_25d_script.new()
	vp.add_child(view_25d)
	view_25d.diablo_bridge = bridge
	view_25d._init_bridge_caps()
	view_25d.setup_scene_hierarchy()
	view_25d.rebuild_dungeon_tiles()

	# Center camera on (54, 54)
	if view_25d.camera:
		view_25d.camera.position = Vector2(float(54 - 54) * 32.0, float(54 + 54) * 16.0)
		view_25d.camera.zoom = Vector2(1.0, 1.0)

	var lights = bridge.get_dungeon_light_grid()
	var ppos = {"pos_x": 54.0, "pos_y": 54.0}
	view_25d.update_objects(lights, ppos)

	# Print all object sprite positions in 2.5D
	print("--- 2.5D OBJECT POSITIONS IN VIEW ---")
	for oid in [0, 126, 125, 124, 123, 122, 121, 120, 119, 118, 117, 116, 94]:
		var spr = view_25d.object_sprites.get(oid, null)
		if spr:
			print("Obj id=%3d: pos=%s, offset=%s, vis=%s" % [oid, str(spr.position), str(spr.offset), str(spr.visible)])

	quit(0)
