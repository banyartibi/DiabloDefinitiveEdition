@tool
extends SceneTree

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

func _init() -> void:
	var save_idx = int(OS.get_environment("HERO_ID")) if OS.get_environment("HERO_ID") != "" else 2
	print("--- Inspecting Hero Save %d ---" % save_idx)
	var bridge = ClassDB.instantiate("DiabloBridge")
	root.add_child(bridge)
	bridge.init_engine(MPQ_DIR)

	var waited = 0
	while not bridge.is_engine_ready() and waited < 200:
		OS.delay_msec(20)
		waited += 1
	if not bridge.is_engine_ready():
		print("FAIL: engine not ready")
		quit(1)
		return

	bridge.menu_select_single_player()
	OS.delay_msec(400)

	bridge.launch_hero_game(save_idx, 0, true)

	waited = 0
	while not bridge.is_game_running() and waited < 500:
		OS.delay_msec(20)
		waited += 1

	if not bridge.is_game_running():
		print("FAIL: game not running for hero %d" % save_idx)
		quit(1)
		return

	OS.delay_msec(1200)

	var cur_lvl = bridge.get_current_level() if bridge.has_method("get_current_level") else -1
	var hp = bridge.get_player_hp() if bridge.has_method("get_player_hp") else -1
	var max_hp = bridge.get_player_max_hp() if bridge.has_method("get_player_max_hp") else -1
	var mana = bridge.get_player_mana() if bridge.has_method("get_player_mana") else -1
	var max_mana = bridge.get_player_max_mana() if bridge.has_method("get_player_max_mana") else -1
	var pclass = bridge.get_player_class() if bridge.has_method("get_player_class") else -1
	var ppos = bridge.get_player_position() if bridge.has_method("get_player_position") else {}
	print("HERO %d: level=%d, class=%d, HP=%d/%d, Mana=%d/%d, pos=%s" % [save_idx, cur_lvl, pclass, hp, max_hp, mana, max_mana, str(ppos)])

	var objects = bridge.get_active_objects() if bridge.has_method("get_active_objects") else []
	var torture_objs = []
	for obj in objects:
		var o_type = obj.get("type", -1)
		if o_type in [29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40]:
			torture_objs.append(obj)

	if torture_objs.size() > 0:
		print(">>> HERO %d HAS %d TORTURE OBJECTS! <<<" % [save_idx, torture_objs.size()])
		for tobj in torture_objs:
			print("   Torture id=%d type=%d at (%d, %d)" % [tobj.get("id", -1), tobj.get("type", -1), tobj.get("tile_x", -1), tobj.get("tile_y", -1)])

	quit(0)
