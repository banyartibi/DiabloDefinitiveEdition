@tool
extends SceneTree
func _init():
	var b = ClassDB.instantiate("DiabloBridge")
	root.add_child(b)
	b.init_engine("/home/biti/.local/share/diasurgical/devilution")
	while not b.is_engine_ready(): OS.delay_msec(20)
	b.menu_select_single_player()
	OS.delay_msec(400)
	b.launch_hero_game(2, 0, true)
	while not b.is_game_running(): OS.delay_msec(20)
	OS.delay_msec(1000)
	for m in b.get_active_monsters_data():
		if "Butcher" in m.get("name", ""):
			print(">>> BUTCHER REAL POS: ", m.get("pos_x"), ", ", m.get("pos_y"), " dict: ", m)
	quit(0)
