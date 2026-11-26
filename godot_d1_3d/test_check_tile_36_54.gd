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
	var objs = bridge.get_active_objects()

	print("--- MAP PIECES X=32..40, Y=50..58 ---")
	for y in range(50, 59):
		var row = ""
		for x in range(32, 41):
			row += "%4d" % grid[y * 112 + x]
		print("Y=%2d: %s" % [y, row])

	print("--- OBJECTS near (36, 54) ---")
	for o in objs:
		var ox = o.get("tile_x", -1)
		var oy = o.get("tile_y", -1)
		if ox >= 30 and ox <= 42 and oy >= 48 and oy <= 60:
			print("Obj id=%d type=%d at (%d, %d)" % [o.get("id", -1), o.get("type", -1), ox, oy])

	quit(0)
