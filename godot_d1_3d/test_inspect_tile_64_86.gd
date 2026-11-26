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
	var objs = bridge.get_active_objects()

	print("=== TILES AROUND (64, 86): X=58..70, Y=80..92 ===")
	for y in range(80, 93):
		var p_row = "Y=%2d: pieces: " % y
		var s_row = "      sol:    "
		for x in range(58, 71):
			p_row += "%4d" % grid[y * 112 + x]
			s_row += "%4d" % sol[y * 112 + x]
		print(p_row)
		print(s_row)

	print("\nObjects in this region (X=58..70, Y=80..92):")
	for o in objs:
		var tx = o.get("tile_x", -1)
		var ty = o.get("tile_y", -1)
		if tx >= 58 and tx <= 70 and ty >= 80 and ty <= 92:
			print("   Obj id=%3d type=%2d cat=%-12s tile=(%2d, %2d)" % [o.get("id", -1), o.get("type", -1), o.get("category", ""), tx, ty])

	quit(0)
