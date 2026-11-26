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
	print("--- TILES FROM Y=28 to Y=44, X=48 to X=62 ---")
	var header = "    X="
	for x in range(48, 62):
		header += "%4d" % x
	print(header)

	for y in range(28, 44):
		var row = ""
		for x in range(48, 62):
			row += "%4d" % grid[y * 112 + x]
		print("Y=%2d: %s" % [y, row])

	quit(0)
