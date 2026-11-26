extends SceneTree
# Bug 3: one candidate skip per process (fresh launch), baseline then skip.

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

var ctrl = null
var bridge = null
var sb = null
var which = ""
var phase = ""
var settle = 0.0
var measure = 0.0
var frames_in_state = 0
var armed = false
var results = []

func _initialize():
	ctrl = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(ctrl)
	which = OS.get_environment("SKIP_WHICH")

func _apply() -> void:
	if which == "TXONLY":
		sb.SKIP_TXONLY = true
	elif which == "PX":
		sb.SKIP_PX = true
	elif which == "ASSIGN":
		sb.SKIP_ASSIGN = true
	elif which == "MAT":
		sb.SKIP_MAT = true
	elif which == "LABEL":
		sb.SKIP_LABEL = true
	elif which == "HP":
		sb.SKIP_HP = true
	elif which == "ANIM":
		sb.SKIP_ANIM = true
	elif which == "TEX":
		sb.SKIP_TEX = true
	elif which == "MONSTERS":
		sb.SKIP_MONSTERS = true
	elif which == "NONE":
		pass

func _next(p: String) -> void:
	phase = p
	if p == "skip":
		_apply()
	settle = 1.0
	measure = 0.0
	frames_in_state = 0
	print("[ONE] phase=%s which=%s" % [p, which])

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
	ctrl.switch_display_mode(2)
	sb = ctrl.sandbox_instance
	print("[ONE] running=%s level=%d mode=%d" % [bridge.is_game_running(), bridge.get_current_level(), ctrl.current_display_mode])

func _process(delta: float) -> bool:
	if ctrl == null or not is_instance_valid(ctrl):
		return false
	if not armed:
		if ctrl.diablo_bridge == null:
			return false
		armed = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_launch()
		_next("base")
		return false
	if phase == "done":
		return false
	if settle > 0.0:
		settle -= delta
		return false
	measure += delta
	frames_in_state += 1
	if measure >= 7.0:
		var fps = frames_in_state / measure
		results.append("%s=%.1f" % [phase, fps])
		print("[ONE] %s fps=%.1f" % [phase, fps])
		if phase == "base":
			_next("skip")
		else:
			print("[ONE] RESULT which=%s %s" % [which, " ".join(results)])
			phase = "done"
			quit()
	return false
