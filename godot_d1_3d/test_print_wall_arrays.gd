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

	var solidity: PackedByteArray = bridge.get_dungeon_solidity_grid()
	var grid = bridge.get_dungeon_grid()
	var active_objects = bridge.get_active_objects()
	var door_tiles: Dictionary = {}
	for obj in active_objects:
		var o_type = obj.get("type", -1)
		var otx = obj.get("tile_x", -1)
		var oty = obj.get("tile_y", -1)
		if otx >= 0 and oty >= 0:
			var cat = str(obj.get("category", ""))
			if cat == "DOOR" or (o_type in [1, 2, 42, 43, 74, 75, 83, 84]):
				door_tiles[Vector2i(otx, oty)] = obj

	var basis_tile = Basis().rotated(Vector3.UP, deg_to_rad(-45.0))
	var tile_to_world_3d = func(tx: float, ty: float) -> Vector3:
		return Vector3((tx - ty) * 0.75, 0.0, (tx + ty) * 0.75)

	print("--- WALLS BUILT AROUND AREA A (X=50..58, Y=50..58) ---")
	for y in range(49, 59):
		for x in range(49, 59):
			var idx = y * 112 + x
			var val = solidity[idx]
			var pid = grid[idx]
			# Wall logic from native_3d_sandbox.gd:
			if val == 2:
				var has_wall_nx = (x > 0 and (solidity[y * 112 + (x - 1)] == 2 or door_tiles.has(Vector2i(x - 1, y))))
				var has_wall_px = (x < 111 and (solidity[y * 112 + (x + 1)] == 2 or door_tiles.has(Vector2i(x + 1, y))))
				var has_wall_ny = (y > 0 and (solidity[(y - 1) * 112 + x] == 2 or door_tiles.has(Vector2i(x, y - 1))))
				var has_wall_py = (y < 111 and (solidity[(y + 1) * 112 + x] == 2 or door_tiles.has(Vector2i(x, y + 1))))
				var neighbor_x_count = (1 if has_wall_nx else 0) + (1 if has_wall_px else 0)
				var neighbor_y_count = (1 if has_wall_ny else 0) + (1 if has_wall_py else 0)
				var wpos = tile_to_world_3d.call(float(x), float(y))
				var w_type = "BLOCK"
				if neighbor_x_count == 0 and neighbor_y_count == 0:
					w_type = "PILLAR"
				elif neighbor_x_count > 0 and neighbor_y_count == 0:
					w_type = "WALL_NS"
				elif neighbor_y_count > 0 and neighbor_x_count == 0:
					w_type = "WALL_EW"
				print("Wall at (%2d, %2d): type=%-8s pos=(%6.2f, %6.2f)" % [x, y, w_type, wpos.x, wpos.z])

	quit(0)
