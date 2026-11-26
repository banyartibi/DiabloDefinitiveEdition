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

	var grid = bridge.get_dungeon_grid()
	var sol = bridge.get_dungeon_solidity_grid()
	var ppos = bridge.get_player_tile_pos()
	print("--- PLAYER POSITION: (%d, %d) ---" % [ppos.x, ppos.y])

	print("--- PIECES AROUND (54, 66): X=50..58, Y=62..70 ---")
	for y in range(62, 71):
		var p_row = "Y=%2d pieces: " % y
		var s_row = "     sol:    "
		for x in range(50, 59):
			p_row += "%4d" % grid[y * 112 + x]
			s_row += "%4d" % sol[y * 112 + x]
		print(p_row)
		print(s_row)

	quit(0)
