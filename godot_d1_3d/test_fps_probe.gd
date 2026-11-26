extends SceneTree

# Bug 3 harness: run the REAL main scene (GameView SubViewport + post-process quad)
# with a live game, read its own FPS counter, then bisect the pipeline.

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

var bridge
var main
var gameview

func _init():
	bridge = ClassDB.instantiate("DiabloBridge")
	if not bridge.init_engine(MPQ_DIR):
		print("init failed")
		quit()
		return
	var hero = OS.get_environment("HERO")
	if hero == "":
		hero = "2,0,1"
	var parts = hero.split(",")
	var h_class = int(parts[0])
	var h_hero = int(parts[1])
	var h_new = int(parts[2])
	for attempt in range(4):
		if bridge.is_game_running():
			break
		bridge.menu_select_single_player()
		OS.delay_msec(1500)
		bridge.launch_hero_game(h_class, h_hero, h_new == 1)
		for i in range(60):
			OS.delay_msec(100)
			if bridge.is_game_running():
				break
	print("[FPS] game_running=%s level=%d" % [bridge.is_game_running(), bridge.get_current_level()])

	main = load("res://scenes/main_3d.tscn").instantiate()
	if main.has_method("set_diablo_bridge"):
		main.set_diablo_bridge(bridge)
	elif "diablo_bridge" in main:
		main.diablo_bridge = bridge
	root.add_child(main)
	gameview = main.get_node_or_null("GameView")
	print("[FPS] gameview=%s size=%s hdr=%s msaa=%s mode=%s" % [
		gameview != null, gameview.size if gameview else "?",
		gameview.use_hdr_2d if gameview else "?", gameview.msaa_3d if gameview else "?",
		main.current_display_mode])

	for i in range(240):
		await process_frame
	await _measure("baseline real scene")
	await _measure("baseline steady")

	if gameview:
		var mesh = main.get_node_or_null("GameView/D1DisplayMesh")
		if mesh:
			mesh.visible = false
		await _measure("post-process quad hidden")
		if mesh:
			mesh.visible = true
		gameview.msaa_3d = Viewport.MSAA_DISABLED
		await _measure("MSAA off")
		gameview.msaa_3d = Viewport.MSAA_2X
		gameview.use_hdr_2d = false
		await _measure("HDR off")
		gameview.use_hdr_2d = true
		gameview.size = Vector2i(1280, 720)
		await _measure("viewport 1280x720")
		gameview.size = Vector2i(2560, 1440)
		if main.has_method("switch_display_mode"):
			main.switch_display_mode(0)
		await _measure("sandbox off (25D blit)")
	print("[FPS] done")
	quit()

func _measure(label: String) -> void:
	for i in range(60):
		await process_frame
	var t0 = Time.get_ticks_msec()
	var n = 0
	while Time.get_ticks_msec() - t0 < 3000:
		await process_frame
		n += 1
		# Force a GPU sync so the measurement reflects real render cost, not submit-only.
		if gameview:
			gameview.get_texture().get_image()
	var ri = RenderingServer
	print("  %-30s iters=%d/s fps_counter=%s draw_calls=%s primitives=%s" % [
		label,
		int(n * 1000.0 / (Time.get_ticks_msec() - t0)),
		str(main.current_fps) if "current_fps" in main else "?",
		ri.get_rendering_info(ri.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		ri.get_rendering_info(ri.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
	])
