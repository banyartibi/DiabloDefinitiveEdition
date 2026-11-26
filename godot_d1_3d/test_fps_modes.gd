extends SceneTree
# Bug 3 bisect, steady-state: launch hero, then measure fps per display mode
# (Original 2.5D HD blit vs Native 3D sandbox) with vsync off at 2560x1440.

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

var ctrl = null
var bridge = null
var sub_viewport = null

var states = []
var state_idx = -1
var settle = 0.0
var measure = 0.0
var frames_in_state = 0
var started = false

func _initialize():
	print("[FPSTEST] initialize")
	ctrl = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(ctrl)
	states = [
		["mode 0 ORIGINAL_25D", func(): ctrl.switch_display_mode(0)],
		["mode 1 NATIVE_25D", func(): ctrl.switch_display_mode(1)],
		["mode 2 NATIVE_3D", func(): ctrl.switch_display_mode(2)],
		["mode 0 ORIGINAL_25D again", func(): ctrl.switch_display_mode(0)],
		["mode 2 NATIVE_3D again", func(): ctrl.switch_display_mode(2)],
		["mode 0 + window 1280x720", func(): _mode0_small()],
	]

func _mode0_small() -> void:
	ctrl.switch_display_mode(0)
	_win(1280, 720)

func _win(w: int, h: int) -> void:
	DisplayServer.window_set_size(Vector2i(w, h))

func _next_state():
	state_idx += 1
	if state_idx >= states.size():
		print("[FPSTEST] done")
		quit()
		return
	print("[FPSTEST] state %d: %s" % [state_idx, states[state_idx][0]])
	states[state_idx][1].call()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	settle = 3.0
	measure = 0.0
	frames_in_state = 0

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
		_launch()
		_next_state()
		return false

	if settle > 0.0:
		settle -= delta
		return false

	measure += delta
	frames_in_state += 1
	if measure >= 6.0:
		print("[FPSTEST] %s -> %.1f fps | mode=%d modal=%s level=%s objs=%s window=%s viewport=%s hd_model=%s fps_label=%s" % [
			states[state_idx][0], frames_in_state / measure,
			ctrl.current_display_mode, ctrl.last_modal_active,
			bridge.get_current_level() if bridge != null else "?",
			bridge.get_active_objects().size() if bridge != null else "?",
			DisplayServer.window_get_size(),
			sub_viewport.size if sub_viewport else "?",
			bridge.get_hd_model_enabled() if bridge.has_method("get_hd_model_enabled") else "?",
			ctrl.fps_label.text if ctrl.fps_label else "?",
		])
		_next_state()
	return false
