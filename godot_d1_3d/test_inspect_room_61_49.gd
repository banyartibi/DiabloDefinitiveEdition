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

	var grid = bridge.get_dungeon_grid()
	var sol = bridge.get_dungeon_solidity_grid()

	print("--- MAP PIECES X=56..68, Y=44..56 ---")
	for y in range(44, 57):
		var row = ""
		for x in range(56, 68):
			row += "%4d" % grid[y * 112 + x]
		print("Y=%2d: %s" % [y, row])

	print("--- SOLIDITY X=56..68, Y=44..56 ---")
	for y in range(44, 57):
		var row = ""
		for x in range(56, 68):
			row += "%2d" % sol[y * 112 + x]
		print("Y=%2d: %s" % [y, row])

	quit(0)
