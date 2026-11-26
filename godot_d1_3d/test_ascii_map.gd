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

	print("--- MAP LAYOUT ASCII (X=46..68, Y=44..66) ---")
	print("Legend: '#' = solid wall (sol=2), '.' = walkable floor (sol=1), 'B' = blood floor (355..390), 'D' = door, 'S' = sarcophagus")

	var active_objects = bridge.get_active_objects()
	var objs_at = {}
	for o in active_objects:
		objs_at[Vector2i(o.get("tile_x", -1), o.get("tile_y", -1))] = o

	var header = "    X="
	for x in range(46, 68):
		header += "%2d" % (x % 100)
	print(header)

	for y in range(44, 67):
		var row = "Y=%2d: " % y
		for x in range(46, 68):
			var idx = y * 112 + x
			var p = Vector2i(x, y)
			var s = sol[idx]
			var pid = grid[idx]
			var ch = " "
			if s == 2:
				ch = "#"
			elif s == 1:
				ch = "."
			if pid >= 355 and pid <= 390:
				ch = "B"
			if objs_at.has(p):
				var cat = str(objs_at[p].get("category", ""))
				var o_type = objs_at[p].get("type", -1)
				if cat == "DOOR" or o_type in [1, 2]: ch = "D"
				elif cat == "SARCOPHAGUS": ch = "S"
				elif o_type in [36, 37, 38, 39, 40]: ch = "T" # Torture spike!
			row += ch + " "
		print(row)

	quit(0)
