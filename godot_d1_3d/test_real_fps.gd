extends SceneTree
# Bug 3 measurement on the real display: launch a hero in the real scene, force the
# Native 3D sandbox, then print fps per graphics configuration.

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

var ctrl = null
var bridge = null
var env = null
var sub_viewport = null

var states = []
var state_idx = -1
var settle = 0.0
var measure = 0.0
var frames_in_state = 0
var started = false
var walking = false
var walk_timer = 0.0
var walk_steps = 0

func _initialize():
	print("[FPSTEST] initialize")
	ctrl = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(ctrl)
	states = [
		["baseline native3d 2560x1440", func(): pass],
		["vsync OFF", func(): _vsync(false)],
		["fog OFF", func(): _fog(false)],
		["fog OFF + glow OFF", func(): _glow(false)],
		["fog/glow OFF + viewport 1280x720", func(): _vp(1280, 720)],
		["viewport 2560 + walking", func(): _start_walk()],
		["restore all (control)", func(): _restore()],
	]

func _vsync(on: bool) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if on else DisplayServer.VSYNC_DISABLED)

func _fog(on: bool) -> void:
	if env:
		env.volumetric_fog_enabled = on

func _glow(on: bool) -> void:
	if env:
		env.glow_enabled = on

func _vp(w: int, h: int) -> void:
	if sub_viewport:
		sub_viewport.size = Vector2i(w, h)

func _start_walk() -> void:
	_vp(2560, 1440)
	walking = true

func _restore() -> void:
	walking = false
	_vp(2560, 1440)
	_fog(true)
	_glow(true)
	_vsync(true)

func _next_state():
	state_idx += 1
	if state_idx >= states.size():
		print("[FPSTEST] done")
		quit()
		return
	print("[FPSTEST] state %d: %s" % [state_idx, states[state_idx][0]])
	states[state_idx][1].call()
	settle = 1.5
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
	print("[FPSTEST] running=%s level=%d objects=%d" % [bridge.is_game_running(), bridge.get_current_level(), bridge.get_active_objects().size()])
	if bridge.is_game_running():
		ctrl.switch_display_mode(2)
		_dump_settings()

func _dump_settings():
	for c in bridge.get_settings_categories():
		print("[SET] cat ", int(c.get("id", -1)), " ", c.get("name", ""))
		for e in bridge.get_settings_entries(int(c.get("id", -1))):
			print("   id=", int(e.get("id", -1)), " name=", e.get("name", ""),
				" type=", int(e.get("type", -1)), " bool=", e.get("bool_val", ""),
				" idx=", e.get("list_index", -1), " str=", e.get("value_str", ""),
				" opts=", e.get("list_options", []))

func _process(delta: float) -> bool:
	if ctrl == null or not is_instance_valid(ctrl):
		return false
	if not started:
		if ctrl.diablo_bridge == null:
			return false
		started = true
		env = ctrl.world_env.environment if ctrl.world_env else null
		sub_viewport = ctrl.game_view
		ctrl.show_fps = true
		_launch()
		_next_state()
		return false

	if walking:
		walk_timer += delta
		if walk_timer >= 0.5:
			walk_timer = 0.0
			walk_steps += 1
			if bridge != null and bridge.has_method("walk_to_tile"):
				var p = bridge.get_player_continuous_pos()
				bridge.walk_to_tile(int(p["pos_x"]) + (walk_steps % 3) - 1, int(p["pos_y"]) + 1)

	if settle > 0.0:
		settle -= delta
		return false

	measure += delta
	frames_in_state += 1
	if measure >= 5.0:
		print("[FPSTEST] %s -> %.1f fps | level=%s objs=%s sandbox_children=%s window=%s fog=%s glow=%s viewport=%s vsync=%s mode=%s" % [
			states[state_idx][0], frames_in_state / measure,
			bridge.get_current_level() if bridge != null else "?",
			bridge.get_active_objects().size() if bridge != null else "?",
			ctrl.sandbox_instance.get_child_count() if is_instance_valid(ctrl.sandbox_instance) else -1,
			DisplayServer.window_get_size(),
			env.volumetric_fog_enabled if env else "?",
			env.glow_enabled if env else "?",
			sub_viewport.size if sub_viewport else "?",
			DisplayServer.window_get_vsync_mode(),
			ctrl.current_display_mode,
		])
		_next_state()
	return false
