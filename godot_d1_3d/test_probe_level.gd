@tool
extends SceneTree

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

func _init() -> void:
	var bridge = ClassDB.instantiate("DiabloBridge")
	root.add_child(bridge)
	bridge.init_engine(MPQ_DIR)
	var t0 = Time.get_ticks_msec()
	while not bridge.is_engine_ready() and Time.get_ticks_msec() - t0 < 5000:
		OS.delay_msec(20)
	for i in range(10):
		OS.delay_msec(500)
		print("t=%d running=%s level=%d objects=%d trigs=%d gate_read=%s" % [
			Time.get_ticks_msec() - t0,
			bridge.is_game_running(), bridge.get_current_level(),
			bridge.get_active_objects().size(), bridge.get_level_triggers().size(),
			str(bridge.get_read_gate_state()),
		])
	print("heroes: %s" % str(bridge.get_hero_list()))
	quit(0)
