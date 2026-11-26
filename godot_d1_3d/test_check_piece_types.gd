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
	OS.delay_msec(400)
	bridge.launch_hero_game(2, 0, true)
	while not bridge.is_game_running():
		OS.delay_msec(20)
	OS.delay_msec(1000)

	var pids = [
		349, 350, 285, 286, 345, 346, 274, 275, 269, 270,
		351, 352, 287, 288, 347, 348, 276, 271,
		219, 220, 221, 222, 314, 315, 316, 317,
		363, 364, 365, 366, 367, 368, 369, 370,
		371, 372, 373, 374, 375, 376, 377, 378,
		379, 380, 381, 382, 383, 384, 385, 386,
		387, 388, 389, 390
	]

	print("--- PIECE DIMENSIONS & TYPES (IN-GAME) ---")
	for pid in pids:
		var tex = bridge.get_dungeon_piece_texture(pid)
		if tex:
			var w = tex.get_width()
			var h = tex.get_height()
			var is_wall = (h > int(round(float(w) * 0.5)))
			print("Piece %3d: %3dx%3d  %s" % [pid, w, h, "WALL" if is_wall else "FLOOR"])
		else:
			print("Piece %3d: NULL texture" % pid)

	quit(0)
