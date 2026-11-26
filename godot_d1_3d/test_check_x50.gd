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
	var grid = b.get_dungeon_grid()
	print("--- EXACT SOLIDITY AND PIECES AT X=49, 50, 51 FOR Y=49..59 ---")
	for y in range(49, 60):
		print("Y=%2d: sol=[%d, %d, %d] pid=[%3d, %3d, %3d]" % [
			y,
			sol[y * 112 + 49], sol[y * 112 + 50], sol[y * 112 + 51],
			grid[y * 112 + 49], grid[y * 112 + 50], grid[y * 112 + 51]
		])
	quit(0)
