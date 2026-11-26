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

	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = sandbox_script.new()
	root.add_child(sandbox)
	sandbox.diablo_bridge = bridge
	sandbox.setup_scene_nodes()
	sandbox.modular_3d_walls_enabled = true
	sandbox.set_theme_aaa_certified("cathedral", true)
	sandbox.activate()
	sandbox.rebuild_dungeon_if_needed(true)
	sandbox.update_props(0.1)

	print("--- ALL PROP INSTANCES IN props_root (%d) ---" % sandbox.prop_instances.size())
	for id in sandbox.prop_instances.keys():
		var p = sandbox.prop_instances[id]
		var ttype = p.get_meta("prop_type", -1)
		var tx = p.get_meta("tile_x", -1)
		var ty = p.get_meta("tile_y", -1)
		var pos = p.position
		# print all props
		print("Prop id=%3d type=%2d tile=(%2d, %2d) pos=(%6.2f, %6.2f, %6.2f) vis=%s" % [
			id, ttype, tx, ty, pos.x, pos.y, pos.z, str(p.visible)
		])

	quit(0)
