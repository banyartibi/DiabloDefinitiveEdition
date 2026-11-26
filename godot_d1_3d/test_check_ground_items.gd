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

	var items = bridge.get_ground_items() if bridge.has_method("get_ground_items") else []
	var objs = bridge.get_active_objects() if bridge.has_method("get_active_objects") else []
	var monsters = bridge.get_active_monsters() if bridge.has_method("get_active_monsters") else []

	print("=== ALL GROUND ITEMS ON LEVEL 2 ===")
	for it in items:
		var name = it.get("name", "")
		var tx = it.get("tile_x", -1)
		var ty = it.get("tile_y", -1)
		print("Item '%s' at (%d, %d)" % [name, tx, ty])

	print("\n=== CHESTS ON LEVEL 2 ===")
	for o in objs:
		var cat = str(o.get("category", ""))
		var o_type = o.get("type", -1)
		if cat == "CHEST" or o_type in [5, 6, 7]:
			print("Chest id=%d at (%d, %d)" % [o.get("id", -1), o.get("tile_x", -1), o.get("tile_y", -1)])

	quit(0)
