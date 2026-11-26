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
	var objs = bridge.get_active_objects()

	print("=== OBJECTS IN REGION X=35..60, Y=35..50 ===")
	for o in objs:
		var tx = o.get("tile_x", -1)
		var ty = o.get("tile_y", -1)
		if tx >= 35 and tx <= 60 and ty >= 35 and ty <= 50:
			print("Obj id=%3d type=%2d cat=%-12s tile=(%2d, %2d)" % [o.get("id", -1), o.get("type", -1), o.get("category", ""), tx, ty])

	quit(0)
