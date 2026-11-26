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

	var flags = bridge.get_dungeon_flags_grid()
	print("--- EXPLORED TILES IN single_2.hsv ---")
	var explored_count = 0
	var min_x = 999; var max_x = -1; var min_y = 999; var max_y = -1
	for y in range(112):
		for x in range(112):
			if (flags[y * 112 + x] & 128) != 0:
				explored_count += 1
				min_x = min(min_x, x)
				max_x = max(max_x, x)
				min_y = min(min_y, y)
				max_y = max(max_y, y)
	print("Explored tiles count: %d, X range: [%d..%d], Y range: [%d..%d]" % [explored_count, min_x, max_x, min_y, max_y])

	# Check Butcher room (50..58, 50..58)
	var br_exp = 0
	var br_vis = 0
	for y in range(50, 58):
		for x in range(50, 58):
			var fl = flags[y * 112 + x]
			if (fl & 128) != 0: br_exp += 1
			if (fl & 2) != 0: br_vis += 1
	print("Butcher room (50..57, 50..57): explored=%d/64, visible=%d/64" % [br_exp, br_vis])

	# Check area (35..40, 53..57)
	var ul_exp = 0
	var ul_vis = 0
	for y in range(53, 58):
		for x in range(35, 41):
			var fl = flags[y * 112 + x]
			if (fl & 128) != 0: ul_exp += 1
			if (fl & 2) != 0: ul_vis += 1
	print("Area (35..40, 53..57): explored=%d/30, visible=%d/30" % [ul_exp, ul_vis])

	quit(0)
