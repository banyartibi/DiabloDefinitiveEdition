@tool
extends SceneTree

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

func _init() -> void:
	var save_idx = 2
	print("--- Inspecting Hero Save %d Wall & Butcher Coords ---" % save_idx)
	var bridge = ClassDB.instantiate("DiabloBridge")
	root.add_child(bridge)
	bridge.init_engine(MPQ_DIR)

	var waited = 0
	while not bridge.is_engine_ready() and waited < 200:
		OS.delay_msec(20)
		waited += 1

	bridge.menu_select_single_player()
	OS.delay_msec(400)
	bridge.launch_hero_game(save_idx, 0, true)

	waited = 0
	while not bridge.is_game_running() and waited < 500:
		OS.delay_msec(20)
		waited += 1

	OS.delay_msec(1200)

	var grid = bridge.get_dungeon_grid() if bridge.has_method("get_dungeon_grid") else PackedInt32Array()
	print("Grid size: %d" % grid.size())

	# Find piece 366
	for y in range(112):
		for x in range(112):
			var pid = grid[y * 112 + x]
			if pid == 366:
				print("FOUND PIECE 366 at (%d, %d)" % [x, y])

	# Find butcher walls: 185..188, 180, 177, 179, 171, 172
	var butcher_walls = []
	for y in range(112):
		for x in range(112):
			var pid = grid[y * 112 + x]
			if pid in [180, 185, 186, 187, 188, 177, 179, 171, 172]:
				butcher_walls.append({"pid": pid, "pos": Vector2i(x, y)})
	print("Found %d butcher wall pieces:" % butcher_walls.size())
	for bw in butcher_walls:
		print("   wall pid=%d at (%d, %d)" % [bw["pid"], bw["pos"].x, bw["pos"].y])

	# Find monsters
	var monsters = bridge.get_active_monsters() if bridge.has_method("get_active_monsters") else []
	for m in monsters:
		var name = m.get("name", "")
		var is_boss = m.get("is_boss", false)
		if "Butcher" in name or is_boss:
			print("BOSS: '%s' at (%d, %d)" % [name, m.get("tile_x", -1), m.get("tile_y", -1)])

	quit(0)
