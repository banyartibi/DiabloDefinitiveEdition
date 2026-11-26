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

	print("=== CHECKING AREA A: (50..58, 50..58) (where pieces 355..390 are) ===")
	for y in range(49, 59):
		var p_row = "Y=%2d: pieces: " % y
		var s_row = "      sol:    "
		for x in range(49, 59):
			p_row += "%4d" % grid[y * 112 + x]
			s_row += "%4d" % sol[y * 112 + x]
		print(p_row)
		print(s_row)

	print("\nObjects in Area A (X=49..59, Y=49..59):")
	for o in objs:
		var tx = o.get("tile_x", -1)
		var ty = o.get("tile_y", -1)
		if tx >= 49 and tx <= 59 and ty >= 49 and ty <= 59:
			print("   Obj id=%3d type=%2d cat=%-12s tile=(%2d, %2d)" % [o.get("id", -1), o.get("type", -1), o.get("category", ""), tx, ty])

	print("\n=== CHECKING AREA B: Player Current Location ===")
	var pt = bridge.get_player_tile_pos()
	print("Player is at tile: (%d, %d)" % [pt.x, pt.y])
	for y in range(pt.y - 4, pt.y + 5):
		var p_row = "Y=%2d: pieces: " % y
		var s_row = "      sol:    "
		for x in range(pt.x - 4, pt.x + 5):
			p_row += "%4d" % grid[y * 112 + x]
			s_row += "%4d" % sol[y * 112 + x]
		print(p_row)
		print(s_row)

	print("\nObjects in Area B (around player):")
	for o in objs:
		var tx = o.get("tile_x", -1)
		var ty = o.get("tile_y", -1)
		if tx >= pt.x - 4 and tx <= pt.x + 4 and ty >= pt.y - 4 and ty <= pt.y + 4:
			print("   Obj id=%3d type=%2d cat=%-12s tile=(%2d, %2d)" % [o.get("id", -1), o.get("type", -1), o.get("category", ""), tx, ty])

	quit(0)
