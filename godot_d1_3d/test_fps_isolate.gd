extends SceneTree
# Bug 3: locate the ~25fps limiter by disabling suspects at runtime.

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

var ctrl = null
var bridge = null
var sub_viewport = null

var states = []
var state_idx = -1
var settle = 0.0
var measure = 0.0
var frames_in_state = 0
var deltas = []
var started = false

func _initialize():
	ctrl = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(ctrl)
	states = [
		["baseline", func(): pass],
		["sandbox _process OFF", func(): ctrl.sandbox_instance.set_process(false)],
		["sandbox _process ON", func(): ctrl.sandbox_instance.set_process(true)],
		["controller _process OFF", func(): ctrl.set_process(false)],
		["SubViewport render OFF", func(): sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE],
		["restore", func(): _restore()],
	]

func _restore() -> void:
	ctrl.set_process(true)
	ctrl.sandbox_instance.set_process(true)
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func _next_state():
	state_idx += 1
	if state_idx >= states.size():
		print("[FPSTEST] done")
		quit()
		return
	print("[FPSTEST] state %d: %s" % [state_idx, states[state_idx][0]])
	states[state_idx][1].call()
	settle = 2.0
	measure = 0.0
	frames_in_state = 0
	deltas.clear()

func _launch() -> void:
	bridge = ctrl.diablo_bridge
	if bridge == null:
		return
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
		print("[FPSTEST] launch attempt %d running=%s level=%d" % [attempt, bridge.is_game_running(), bridge.get_current_level()])

func _process(delta: float) -> bool:
	if ctrl == null or not is_instance_valid(ctrl):
		return false
	if not started:
		if ctrl.diablo_bridge == null:
			return false
		started = true
		sub_viewport = ctrl.game_view
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_launch()
		_next_state()
		return false

	if settle > 0.0:
		settle -= delta
		return false

	measure += delta
	frames_in_state += 1
	deltas.append(delta)
	if measure >= 6.0:
		var mn = 99.0
		var mx = 0.0
		for d in deltas:
			mn = min(mn, d)
			mx = max(mx, d)
		print("[FPSTEST] %s -> %.1f fps | min=%.1fms avg=%.1fms max=%.1fms spikes>100ms=%d" % [
			states[state_idx][0], frames_in_state / measure,
			mn * 1000.0, measure * 1000.0 / frames_in_state, mx * 1000.0,
			deltas.filter(func(d): return d > 0.1).size(),
		])
		_next_state()
	return false
