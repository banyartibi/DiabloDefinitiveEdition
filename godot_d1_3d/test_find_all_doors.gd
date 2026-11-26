@tool
extends SceneTree
func _init():
	var b = ClassDB.instantiate("DiabloBridge")
	root.add_child(b)
	b.init_engine("/home/biti/.local/share/diasurgical/devilution")
	while not b.is_engine_ready(): OS.delay_msec(20)
	b.menu_select_single_player()
	OS.delay_msec(400)
	b.launch_hero_game(2, 0, true)
	while not b.is_game_running(): OS.delay_msec(20)
	OS.delay_msec(1000)
	var objs = b.get_active_objects()
	print("--- ALL DOORS ON LEVEL 2 ---")
	for o in objs:
		var cat = str(o.get("category", ""))
		var o_type = o.get("type", -1)
		if cat == "DOOR" or o_type in [1, 2, 42, 43, 74, 75, 83, 84]:
			var tx = o.get("tile_x", -1)
			var ty = o.get("tile_y", -1)
			var wx = (tx - ty) * 0.75
			var wz = (tx + ty) * 0.75
			print("Door id=%d type=%d at (%d, %d) world=(%.2f, %.2f)" % [o.get("id", -1), o_type, tx, ty, wx, wz])
	quit(0)
