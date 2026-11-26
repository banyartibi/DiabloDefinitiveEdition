extends SceneTree
# Bug 3 hypothesis test: pre-warm the HD sprite texture cache for the monsters
# present in the level, then measure fps. If the Vulkan stall is caused by
# binding *newly created* textures, pre-warming should remove it.

const HD = preload("res://scripts/hd_sprite_provider.gd")
const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

var ctrl = null
var bridge = null
var sb = null
var phase = ""
var settle = 0.0
var measure = 0.0
var frames_in_state = 0
var armed = false

func _initialize():
	ctrl = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(ctrl)

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
	print("[PREWARM] running=%s level=%d" % [bridge.is_game_running(), bridge.get_current_level()])

func _prewarm() -> int:
	var mons: Array = bridge.get_active_monsters_data()
	var fams = {}
	var loaded := 0
	var t0 = Time.get_ticks_msec()
	for m in mons:
		var nm: String = m.get("name", "Monster")
		var md: int = m.get("mode", 0)
		fams[nm + str(md)] = true
	for key in fams.keys():
		var nm = key.substr(0, key.length() - 1)
		var md = int(key.right(1))
		for d in range(8):
			for f in range(14):
				if HD.get_monster_sprite(nm, md, d, f, sb.current_tile_model) != null:
					loaded += 1
	print("[PREWARM] families=%d textures_warmed=%d in %d ms" % [fams.size(), loaded, Time.get_ticks_msec() - t0])
	return loaded

func _next(p: String) -> void:
	phase = p
	settle = 1.0
	measure = 0.0
	frames_in_state = 0
	print("[PREWARM] phase=%s" % p)

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
		print("[PREWARM] %s fps=%.1f" % [phase, fps])
		if phase == "base":
			_prewarm()
			_next("warmed")
		else:
			print("[PREWARM] RESULT warmed_fps=%.1f" % fps)
			phase = "done"
			quit()
	return false
