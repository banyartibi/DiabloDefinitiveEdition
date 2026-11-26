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

	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = sandbox_script.new()
	root.add_child(sandbox)
	sandbox.diablo_bridge = bridge

	var grid = bridge.get_dungeon_grid()
	var sol = bridge.get_dungeon_solidity_grid()

	print("--- INSPECTING AREA A TILES (X=50..58, Y=50..58) ---")
	for y in range(50, 59):
		for x in range(50, 59):
			var idx = y * 112 + x
			var pid = grid[idx]
			var val = sol[idx]
			var tex = sandbox.get_scenery_piece_texture(pid, 2)
			var tw = tex.get_width() if tex else 0
			var th = tex.get_height() if tex else 0
			var is_wall = (th > int(round(float(tw) * 0.5)))
			if val == 2 or is_wall:
				print("(%2d, %2d): pid=%3d, val=%d, tex=%dx%d, is_wall_scenery=%s" % [
					x, y, pid, val, tw, th, str(is_wall)
				])

	quit(0)
