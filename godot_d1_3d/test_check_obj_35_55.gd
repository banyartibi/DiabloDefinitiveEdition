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

	var objs = bridge.get_active_objects()
	print("--- OBJECTS NEAR (35, 55): X=30..42, Y=48..60 ---")
	for o in objs:
		var tx = o.get("tile_x", -1)
		var ty = o.get("tile_y", -1)
		if tx >= 30 and tx <= 42 and ty >= 48 and ty <= 60:
			print("Obj id=%3d type=%2d cat=%-12s tile=(%2d, %2d)" % [o.get("id", -1), o.get("type", -1), o.get("category", ""), tx, ty])

	quit(0)
