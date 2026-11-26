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
	print("--- ALL SARCOPHAGI AND CHESTS ON LEVEL 2 ---")
	for o in objs:
		var cat = str(o.get("category", ""))
		var o_type = o.get("type", -1)
		var id = o.get("id", -1)
		var tx = o.get("tile_x", -1)
		var ty = o.get("tile_y", -1)
		if cat in ["SARCOPHAGUS", "CHEST"] or o_type in [5, 6, 7, 48, 68, 69, 70, 96]:
			var wx = (tx - ty) * 0.75
			var wz = (tx + ty) * 0.75
			print("Obj id=%3d type=%2d cat=%-12s tile=(%2d, %2d) world=(%6.2f, %6.2f)" % [id, o_type, cat, tx, ty, wx, wz])

	quit(0)
