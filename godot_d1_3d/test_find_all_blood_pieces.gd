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
	var unique_pids = {}
	for pid in grid:
		if pid > 0:
			unique_pids[pid] = true

	print("Unique pieces on Level 2: %d" % unique_pids.size())

	# Check each piece texture for red blood
	var blood_pids = {}
	for pid in unique_pids.keys():
		var tex = bridge.get_dungeon_piece_texture(pid)
		if tex:
			var img = tex.get_image()
			if img and not img.is_empty():
				var red_count = 0
				var w = img.get_width()
				var h = img.get_height()
				for y in range(h):
					for x in range(w):
						var c = img.get_pixel(x, y)
						if c.a > 0.3 and c.r > 0.35 and c.r > c.g * 1.5 and c.r > c.b * 1.5:
							red_count += 1
				if red_count > 15:
					blood_pids[pid] = red_count

	print("Pieces with red blood on Level 2: %s" % str(blood_pids))

	# Now find all locations of these blood pieces on the map!
	print("--- MAP LOCATIONS OF BLOOD PIECES ---")
	for y in range(112):
		for x in range(112):
			var pid = grid[y * 112 + x]
			if blood_pids.has(pid):
				print("Blood tile (%d, %d): pid=%d (red_pixels=%d)" % [x, y, pid, blood_pids[pid]])

	quit(0)
