@tool
extends SceneTree

func _init():
	print("--- Starting DiabloBridge in Headless Mode ---")
	if not ClassDB.class_exists("DiabloBridge"):
		print("DiabloBridge not found!")
		quit(1)
		return

	var bridge = ClassDB.instantiate("DiabloBridge")
	root.add_child(bridge)
	var mpq_dir = "/home/biti/.local/share/diasurgical/devilution"
	bridge.init_engine(mpq_dir)
	print("Bridge initialized, waiting for game start...")

	# Wait a bit for engine loop
	for frame in range(120):
		# Let bridge process
		if bridge.has_method("is_game_running") and bridge.is_game_running():
			print("Game running at frame %d!" % frame)
			break
		OS.delay_msec(20)

	var cur_lvl = bridge.get_current_level() if bridge.has_method("get_current_level") else -1
	print("Current level: %d" % cur_lvl)
	var grid = bridge.get_dungeon_grid() if bridge.has_method("get_dungeon_grid") else PackedInt32Array()
	print("Grid size: %d" % grid.size())

	if grid.size() >= 112 * 112:
		var unique_pids: Dictionary = {}
		for pid in grid:
			unique_pids[pid] = unique_pids.get(pid, 0) + 1
		print("Found %d unique pieces in Town:" % unique_pids.size())
		var null_tex_count = 0
		var scenery_count = 0
		var floor_count = 0
		for pid in unique_pids.keys():
			var tex = bridge.get_dungeon_piece_texture(pid)
			if tex == null:
				null_tex_count += 1
				print("  NULL tex for pid=%d (count on map: %d)" % [pid, unique_pids[pid]])
			else:
				var tw = tex.get_width()
				var th = tex.get_height()
				var floor_h = int(round(float(tw) * 0.5))
				if th > floor_h:
					scenery_count += 1
				else:
					floor_count += 1
		print("Summary: %d floor pieces, %d scenery pieces, %d NULL texture pieces!" % [floor_count, scenery_count, null_tex_count])

	quit(0)
