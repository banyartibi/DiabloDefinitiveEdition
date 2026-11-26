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

	# Find any tiles with blood floor (piece 2, piece 366, pieces 355..390)
	var blood_tiles = []
	for y in range(112):
		for x in range(112):
			var pid = grid[y * 112 + x]
			if pid == 2 or (pid >= 355 and pid <= 390):
				blood_tiles.append(Vector2i(x, y))

	print("Total blood tiles on Level 2: %d" % blood_tiles.size())
	# Group blood tiles by connected components / clusters
	var clusters = []
	var visited = {}
	for bt in blood_tiles:
		if visited.has(bt):
			continue
		var cluster = []
		var queue = [bt]
		visited[bt] = true
		while queue.size() > 0:
			var curr = queue.pop_back()
			cluster.append(curr)
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if dx == 0 and dy == 0:
						continue
					var n = Vector2i(curr.x + dx, curr.y + dy)
					if blood_tiles.has(n) and not visited.has(n):
						visited[n] = true
						queue.append(n)
		clusters.append(cluster)

	print("Found %d blood clusters on Level 2:" % clusters.size())
	for i in range(clusters.size()):
		var c = clusters[i]
		var min_x = 999; var max_x = -1
		var min_y = 999; var max_y = -1
		for p in c:
			if p.x < min_x: min_x = p.x
			if p.x > max_x: max_x = p.x
			if p.y < min_y: min_y = p.y
			if p.y > max_y: max_y = p.y
		print("Cluster %d (%d tiles): X=%d..%d, Y=%d..%d, sample pid=%d" % [i, c.size(), min_x, max_x, min_y, max_y, grid[c[0].y * 112 + c[0].x]])

	quit(0)
