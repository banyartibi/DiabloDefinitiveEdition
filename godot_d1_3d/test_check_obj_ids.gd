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

	# In single_2.hsv, current level is 2.
	# What if we inspect all object IDs on Level 2?
	var objs = bridge.get_active_objects()
	print("--- OBJECT COUNT: %d ---" % objs.size())
	for o in objs:
		var id = o.get("id", -1)
		var o_type = o.get("type", -1)
		var cat = str(o.get("category", ""))
		var tx = o.get("tile_x", -1)
		var ty = o.get("tile_y", -1)
		if id in [0, 126, 125, 124, 123, 122, 121, 120, 119, 118, 117, 116, 75, 74, 73, 72, 71, 70, 69]:
			print("Obj id=%3d type=%2d cat=%-10s tile=(%2d, %2d)" % [id, o_type, cat, tx, ty])

	quit(0)
