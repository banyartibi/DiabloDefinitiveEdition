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
	print("--- ALL OBJECTS IN X=30..65, Y=30..65 ---")
	for o in objs:
		var tx = o.get("tile_x", -1)
		var ty = o.get("tile_y", -1)
		if tx >= 30 and tx <= 65 and ty >= 30 and ty <= 65:
			var id = o.get("id", -1)
			var o_type = o.get("type", -1)
			var cat = str(o.get("category", ""))
			var wx = (tx - ty) * 0.75
			var wz = (tx + ty) * 0.75
			print("Obj id=%3d type=%2d cat=%-12s tile=(%2d, %2d) world=(%6.2f, %6.2f)" % [id, o_type, cat, tx, ty, wx, wz])

	quit(0)
