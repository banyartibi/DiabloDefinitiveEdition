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
	OS.delay_msec(500)
	var heroes = bridge.get_hero_list() if bridge.has_method("get_hero_list") else []
	for h in heroes:
		var snum = h.get("save_num", -1)
		# Load hero
		bridge.launch_hero_game(snum, 0, true)
		var waited = 0
		while not bridge.is_game_running() and waited < 200:
			OS.delay_msec(20)
			waited += 1
		if bridge.is_game_running():
			var lvl = bridge.get_current_level()
			print("Save %d (%s, %s): current_level = %d" % [snum, h.get("name", ""), h.get("class_name", ""), lvl])
			bridge.quit_game_to_menu()
			OS.delay_msec(300)
			bridge.menu_select_single_player()
			OS.delay_msec(300)
		else:
			print("Save %d failed to load" % snum)
	quit(0)
