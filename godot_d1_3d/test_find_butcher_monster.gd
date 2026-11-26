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

	var monsters = bridge.get_active_monsters_data()
	for m in monsters:
		var name = m.get("name", "")
		var is_boss = m.get("is_boss", false)
		if "Butcher" in name or is_boss:
			print("BOSS: '%s' at (%d, %d), hp=%d" % [name, m.get("tile_x", -1), m.get("tile_y", -1), m.get("hp", -1)])

	quit(0)
