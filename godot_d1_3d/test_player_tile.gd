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

	var pt = bridge.get_player_tile_pos()
	print(">>> PLAYER TILE POS: (%d, %d) <<<" % [pt.x, pt.y])

	var pid_at_p = bridge.get_dungeon_grid()[pt.y * 112 + pt.x]
	print(">>> PIECE ID AT PLAYER TILE: %d <<<" % pid_at_p)

	quit(0)
