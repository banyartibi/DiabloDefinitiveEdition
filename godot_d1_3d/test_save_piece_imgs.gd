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

	var pids_to_save = [349, 360, 366, 375, 379, 385, 389]
	for pid in pids_to_save:
		var tex = bridge.get_dungeon_piece_texture(pid)
		if tex:
			var img = tex.get_image()
			if img:
				img.save_png("/home/biti/.gemini/antigravity/brain/4427fff3-fdfb-47e3-b8be-42adea0050ce/piece_%d.png" % pid)
				print("Saved piece_%d.png (%dx%d)" % [pid, img.get_width(), img.get_height()])

	quit(0)
