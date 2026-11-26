extends SceneTree
# Bug 3: find which sandbox update causes the ~39 ms/frame stall.

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

var ctrl = null
var bridge = null
var sb = null

var states = []
var state_idx = -1
var settle = 0.0
var measure = 0.0
var frames_in_state = 0
var armed = false

func _initialize():
	ctrl = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(ctrl)
	states = [
		["baseline", func(): pass],
		["SKIP_MONSTERS", func(): sb.SKIP_MONSTERS = true],
		["SKIP_PROPS", func(): sb.SKIP_PROPS = true],
		["SKIP_CORPSES", func(): sb.SKIP_CORPSES = true],
		["SKIP_ITEMS", func(): sb.SKIP_ITEMS = true],
		["SKIP_SCENERY", func(): sb.SKIP_SCENERY = true],
		["all skipped", func(): _all(true)],
		["restore", func(): _all(false)],
	]

func _all(v: bool) -> void:
	sb.SKIP_MONSTERS = v
	sb.SKIP_PROPS = v
	sb.SKIP_CORPSES = v
	sb.SKIP_ITEMS = v
	sb.SKIP_SCENERY = v
	sb.SKIP_EFFECTS = v
	sb.SKIP_PLAYER = v

func _next_state():
	state_idx += 1
	if state_idx >= states.size():
		print("[ISOL] done")
		quit()
		return
	print("[ISOL] state %d: %s" % [state_idx, states[state_idx][0]])
	states[state_idx][1].call()
	settle = 1.5
	measure = 0.0
	frames_in_state = 0

func _launch() -> void:
	bridge = ctrl.diablo_bridge
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
		print("[ISOL] launch attempt %d running=%s level=%d" % [attempt, bridge.is_game_running(), bridge.get_current_level()])
	ctrl.switch_display_mode(2)
	sb = ctrl.sandbox_instance

func _process(delta: float) -> bool:
	if ctrl == null or not is_instance_valid(ctrl):
		return false
	if not armed:
		if ctrl.diablo_bridge == null:
			return false
		armed = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_launch()
		_next_state()
		return false
	if settle > 0.0:
		settle -= delta
		return false
	measure += delta
	frames_in_state += 1
	if measure >= 6.0:
		print("[ISOL] %s -> %.1f fps | objs=%d" % [
			states[state_idx][0], frames_in_state / measure,
			bridge.get_active_objects().size(),
		])
		_next_state()
	return false
