extends SceneTree
# TEMP: track scene churn — node counts, lights, and frame gaps.

var ctrl = null
var sb = null
var armed = false
var win = 0
var win_time = 0.0
var win_frames = 0
var last_end = 0

func _initialize():
	ctrl = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(ctrl)

func _launch() -> void:
	var bridge = ctrl.diablo_bridge
	for attempt in range(6):
		if bridge.is_game_running():
			break
		bridge.menu_select_single_player()
		OS.delay_msec(1200)
		bridge.launch_hero_game(2, 0, true)
		for i in range(40):
			OS.delay_msec(100)
			if bridge.is_game_running():
				break
	ctrl.switch_display_mode(2)
	sb = ctrl.sandbox_instance
	print("[CH] running=%s level=%d mode=%d" % [bridge.is_game_running(), bridge.get_current_level(), ctrl.current_display_mode])

func _counts() -> String:
	var nodes = 0
	var lights = 0
	var sprites = 0
	var stacks = 0
	var mmis = 0
	for n in _all_nodes(ctrl):
		nodes += 1
		if n is OmniLight3D:
			lights += 1
		elif n is Sprite3D:
			sprites += 1
		elif n is MultiMeshInstance3D:
			mmis += 1
		elif n is GPUParticles3D:
			stacks += 1
	return "nodes=%d lights=%d sprites=%d mmis=%d particles=%d" % [nodes, lights, sprites, mmis, stacks]

func _all_nodes(n: Node) -> Array:
	var out = []
	out.append(n)
	for c in n.get_children():
		out.append_array(_all_nodes(c))
	return out

func _process(delta: float) -> bool:
	if ctrl == null or not is_instance_valid(ctrl):
		return false
	if not armed:
		if ctrl.diablo_bridge == null:
			return false
		armed = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_launch()
		return false
	var now = Time.get_ticks_msec()
	win_time += delta
	win_frames += 1
	if win_time >= 5.0:
		var gap = now - last_end
		print("[CH] window=%d fps=%.1f gap_from_sb_or_engine=%dms %s" % [win, win_frames / win_time, gap, _counts()])
		if win >= 6:
			quit()
			return false
		win += 1
		win_time = 0.0
		win_frames = 0
	last_end = Time.get_ticks_msec()
	return false
