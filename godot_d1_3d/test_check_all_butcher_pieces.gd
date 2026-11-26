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

	print("--- CHECKING ALL BUTCHER PIECES 355..390 ---")
	for pid in range(355, 391):
		var tex = sandbox.get_scenery_piece_texture(pid, 2)
		var tw = tex.get_width() if tex else 0
		var th = tex.get_height() if tex else 0
		var floor_h = int(round(float(tw) * 0.5))
		var is_wall = (th > floor_h)
		print("Piece %3d: %3dx%3d -> %s" % [pid, tw, th, "WALL" if is_wall else "FLOOR"])

	quit(0)
