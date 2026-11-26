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

	var items = bridge.get_active_items() if bridge.has_method("get_active_items") else []
	print("--- ALL GROUND ITEMS ON LEVEL 2 (%d) ---" % items.size())
	for it in items:
		var name = str(it.get("name", ""))
		var tx = it.get("tile_x", -1)
		var ty = it.get("tile_y", -1)
		var wx = (tx - ty) * 0.75
		var wz = (tx + ty) * 0.75
		print("Item: '%-25s' at tile=(%2d, %2d) world=(%6.2f, %6.2f)" % [name, tx, ty, wx, wz])

	quit(0)
