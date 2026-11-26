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
	OS.delay_msec(1200)

	var grid = bridge.get_dungeon_grid()
	var special = bridge.get_dungeon_special_grid()
	var objects = bridge.get_active_objects()
	var monsters = bridge.get_active_monsters()

	print("=== TILES AROUND (51, 51) ===")
	# Print a 20x20 window around 51, 51 (from x=42..62, y=42..62)
	print("Rows are Y (42..62), Columns are X (42..62):")
	for y in range(44, 62):
		var row_pids = []
		for x in range(44, 62):
			var idx = y * 112 + x
			row_pids.append("%4d" % grid[idx])
		print("Y=%2d: %s" % [y, " ".join(row_pids)])

	print("=== OBJECTS IN THIS WINDOW ===")
	for o in objects:
		var tx = o.get("tile_x", -1)
		var ty = o.get("tile_y", -1)
		if tx >= 44 and tx <= 62 and ty >= 44 and ty <= 62:
			print("Object id=%d type=%d cat=%s at (%d, %d)" % [o.get("id", -1), o.get("type", -1), o.get("category", ""), tx, ty])

	print("=== MONSTERS IN THIS WINDOW ===")
	for m in monsters:
		var tx = m.get("tile_x", -1)
		var ty = m.get("tile_y", -1)
		if tx >= 44 and tx <= 62 and ty >= 44 and ty <= 62:
			print("Monster '%s' boss=%s at (%d, %d)" % [m.get("name", ""), str(m.get("is_boss", false)), tx, ty])

	quit(0)
