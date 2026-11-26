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

	var objs = bridge.get_active_objects()
	var grid = bridge.get_dungeon_grid()
	var sol = bridge.get_dungeon_solidity_grid()

	for o in objs:
		var cat = str(o.get("category", ""))
		var o_type = o.get("type", -1)
		var id = o.get("id", -1)
		var tx = o.get("tile_x", -1)
		var ty = o.get("tile_y", -1)
		if cat == "SARCOPHAGUS" or o_type in [48, 96]:
			print("\n--- Sarcophagus id=%d at (%d, %d) ---" % [id, tx, ty])
			for dy in range(-2, 3):
				var row = ""
				for dx in range(-2, 3):
					var nx = tx + dx
					var ny = ty + dy
					var s = sol[ny * 112 + nx]
					var p = grid[ny * 112 + nx]
					row += "[s=%d,p=%3d] " % [s, p]
				print("dy=%2d: %s" % [dy, row])

	quit(0)
