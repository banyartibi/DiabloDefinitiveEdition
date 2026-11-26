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

	var items = bridge.get_active_items() if bridge.has_method("get_active_items") else []
	print("--- ACTIVE GROUND ITEMS (%d items) ---" % items.size())
	for it in items:
		var name = it.get("name", "")
		var tx = it.get("tile_x", -1)
		var ty = it.get("tile_y", -1)
		var id = it.get("id", -1)
		print("Item id=%d '%s' at tile=(%d, %d)" % [id, name, tx, ty])

	quit(0)
