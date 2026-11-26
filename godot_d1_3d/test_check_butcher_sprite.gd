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

	var s_data = bridge.get_monster_sprite_data(11) # Butcher ID is 11
	print("Butcher sprite data: width=%d, height=%d, rgba_size=%d" % [
		s_data.get("width", 0), s_data.get("height", 0), s_data.get("rgba", PackedByteArray()).size()
	])

	quit(0)
