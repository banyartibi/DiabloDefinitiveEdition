extends SceneTree

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

func _init() -> void:
	var bridge = ClassDB.instantiate("DiabloBridge")
	root.add_child(bridge)
	bridge.init_engine(MPQ_DIR)
	while not bridge.is_engine_ready():
		OS.delay_msec(20)
	bridge.menu_select_single_player()
	OS.delay_msec(1200)
	print("heroes=%d" % bridge.get_hero_list().size())
	bridge.launch_hero_game(2, 0, true)
	print("launch_hero_game(2,0,true) called")
	var t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000:
		OS.delay_msec(500)
		print("  t=%d running=%s loading=%s level=%d gate=%s player=%s" % [
			Time.get_ticks_msec() - t0, bridge.is_game_running(), bridge.is_level_loading(),
			bridge.get_current_level(), str(bridge.get_read_gate_state()), str(bridge.get_player_tile_pos())])
		if bridge.is_game_running():
			break
	quit(0)
