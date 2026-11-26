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

	var sol = bridge.get_dungeon_solidity_grid()
	var grid = bridge.get_dungeon_grid()

	# Find all connected components of walkable floor (solidity == 1)
	var visited = {}
	var rooms = []
	for y in range(112):
		for x in range(112):
			var idx = y * 112 + x
			if sol[idx] == 1 and not visited.has(Vector2i(x, y)):
				# Flood fill
				var comp = []
				var q = [Vector2i(x, y)]
				visited[Vector2i(x, y)] = true
				while q.size() > 0:
					var cur = q.pop_back()
					comp.append(cur)
					for dy in [-1, 0, 1]:
						for dx in [-1, 0, 1]:
							if abs(dx) + abs(dy) != 1: continue
							var nx = cur.x + dx
							var ny = cur.y + dy
							if nx >= 0 and nx < 112 and ny >= 0 and ny < 112:
								var nidx = ny * 112 + nx
								if sol[nidx] == 1 and not visited.has(Vector2i(nx, ny)):
									visited[Vector2i(nx, ny)] = true
									q.append(Vector2i(nx, ny))
				# If room size is between 10 and 100 tiles, print it
				if comp.size() >= 10 and comp.size() <= 200:
					rooms.append(comp)

	print("Found %d distinct floor components (size 10..200):" % rooms.size())
	for i in range(rooms.size()):
		var c = rooms[i]
		var min_x = 999; var max_x = -1
		var min_y = 999; var max_y = -1
		var pids = {}
		for p in c:
			if p.x < min_x: min_x = p.x
			if p.x > max_x: max_x = p.x
			if p.y < min_y: min_y = p.y
			if p.y > max_y: max_y = p.y
			var pid = grid[p.y * 112 + p.x]
			pids[pid] = true
		print("Room %2d: %3d tiles, X=%2d..%2d, Y=%2d..%2d, pieces: %s" % [
			i, c.size(), min_x, max_x, min_y, max_y, str(pids.keys().slice(0, 8))
		])

	quit(0)
