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

	var mm = sandbox.wall_mmi.multimesh
	print("Total wall_mmi instances: %d" % mm.instance_count)
	for i in range(min(20, mm.instance_count)):
		var tf = mm.get_instance_transform(i)
		var p = tf.origin
		var tile = sandbox.world_3d_to_tile(p)
		print("Wall %d: pos=%s -> tile=(%.1f, %.1f)" % [i, str(p), tile.x, tile.y])

	quit(0)
