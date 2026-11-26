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

	var objects = bridge.get_active_objects()
	print("--- TOTAL OBJECTS ON LEVEL 2: %d ---" % objects.size())
	for o in objects:
		var o_type = o.get("type", -1)
		var tx = o.get("tile_x", -1)
		var ty = o.get("tile_y", -1)
		var id = o.get("id", -1)
		# Print all torture/gore objects: types 29..40
		if o_type in [29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40]:
			print("GORE id=%3d type=%2d at (%2d, %2d)" % [id, o_type, tx, ty])

	quit(0)
