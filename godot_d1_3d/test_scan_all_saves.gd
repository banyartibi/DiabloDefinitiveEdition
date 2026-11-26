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
	OS.delay_msec(500)
	var heroes = bridge.get_hero_list() if bridge.has_method("get_hero_list") else []

	for h in heroes:
		var snum = h.get("save_num", -1)
		bridge.launch_hero_game(snum, 0, true)
		var waited = 0
		while not bridge.is_game_running() and waited < 300:
			OS.delay_msec(20)
			waited += 1
		if not bridge.is_game_running():
			continue

		OS.delay_msec(1200)

		var lvl = bridge.get_current_level()
		var objs = bridge.get_active_objects() if bridge.has_method("get_active_objects") else []
		var torture_count = 0
		for o in objs:
			var t = o.get("type", -1)
			if t in [29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40]:
				torture_count += 1

		var grid = bridge.get_dungeon_grid() if bridge.has_method("get_dungeon_grid") else PackedInt32Array()
		var count_366 = 0
		var count_2 = 0
		for pid in grid:
			if pid == 366:
				count_366 += 1
			elif pid == 2:
				count_2 += 1

		print("SAVE %2d (%s): lvl=%d, objs=%d, tortures=%d, 366=%d, p2=%d" % [
			snum, h.get("name", ""), lvl, objs.size(), torture_count, count_366, count_2
		])

		bridge.quit_game_to_menu()
		OS.delay_msec(400)
		bridge.menu_select_single_player()
		OS.delay_msec(400)

	quit(0)
