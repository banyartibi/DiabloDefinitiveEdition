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

	var sol = b.get_dungeon_solidity_grid()
	print("--- SOLIDITY X=45..60, Y=38..52 ---")
	var h = "    X="
	for x in range(45, 61): h += "%3d" % x
	print(h)
	for y in range(38, 52):
		var r = "Y=%2d: " % y
		for x in range(45, 61):
			r += "%3d" % sol[y * 112 + x]
		print(r)

	quit(0)
