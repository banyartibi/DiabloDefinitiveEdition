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

	var grid = bridge.get_dungeon_grid()
	var sol = bridge.get_dungeon_solidity_grid()
	var objs = bridge.get_active_objects()
	var ppos = bridge.get_player_tile_pos()

	var img = Image.create(112, 112, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.05, 0.05, 0.05, 1.0)) # Dark void

	for y in range(112):
		for x in range(112):
			var idx = y * 112 + x
			var s = sol[idx]
			var pid = grid[idx]
			if s == 1:
				img.set_pixel(x, y, Color(0.7, 0.7, 0.7, 1.0)) # Walkable floor
			elif s == 2:
				img.set_pixel(x, y, Color(0.25, 0.25, 0.35, 1.0)) # Wall
			if pid >= 355 and pid <= 390:
				img.set_pixel(x, y, Color(0.9, 0.1, 0.1, 1.0)) # Blood floor

	# Mark objects
	for o in objs:
		var tx = o.get("tile_x", -1)
		var ty = o.get("tile_y", -1)
		var o_type = o.get("type", -1)
		var cat = str(o.get("category", ""))
		if tx >= 0 and tx < 112 and ty >= 0 and ty < 112:
			if o_type in [36, 37, 38, 39, 40]: # Spikes
				img.set_pixel(tx, ty, Color(1.0, 0.5, 0.0, 1.0)) # Orange
			elif cat == "DOOR" or o_type in [1, 2]:
				img.set_pixel(tx, ty, Color(0.1, 0.8, 1.0, 1.0)) # Cyan
			elif cat == "SARCOPHAGUS":
				img.set_pixel(tx, ty, Color(1.0, 1.0, 1.0, 1.0)) # White

	# Mark player
	if ppos.x >= 0 and ppos.x < 112 and ppos.y >= 0 and ppos.y < 112:
		img.set_pixel(ppos.x, ppos.y, Color(0.0, 1.0, 0.0, 1.0)) # Green

	# Scale up 4x to 448x448 with nearest neighbor for easy viewing
	var scaled = Image.create(448, 448, false, Image.FORMAT_RGBA8)
	for y in range(448):
		for x in range(448):
			scaled.set_pixel(x, y, img.get_pixel(x / 4, y / 4))

	scaled.save_png("/home/biti/.gemini/antigravity/brain/4427fff3-fdfb-47e3-b8be-42adea0050ce/full_dungeon_level2_map.png")
	print("Saved full_dungeon_level2_map.png")

	quit(0)
