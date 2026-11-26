extends SceneTree
# Bug 3: profile the sandbox _process phases in the real game on the real display.

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

var ctrl = null
var bridge = null
var frames = 0
var armed = false

func _initialize():
	ctrl = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(ctrl)

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
		print("[PROFTEST] launch attempt %d running=%s level=%d" % [attempt, bridge.is_game_running(), bridge.get_current_level()])
	ctrl.switch_display_mode(2)

func _process(delta: float) -> bool:
	if ctrl == null or not is_instance_valid(ctrl):
		return false
	frames += 1
	if not armed:
		if ctrl.diablo_bridge == null:
			return false
		armed = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_launch()
		ctrl.sandbox_instance.PROF = true
		print("[PROFTEST] profiling for 30s")
		return false
	if frames > 30 * 60 + 200:
		print("[PROFTEST] done fps_label=%s" % ctrl.fps_label.text)
		quit()
	return false
