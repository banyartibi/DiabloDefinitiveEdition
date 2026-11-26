extends SceneTree
# Bug 3 quantification: after warming the HD cache, force N new-texture-per-frame
# churns (evict + reload + assign to a monster sprite) and measure the fps cost.

const HD = preload("res://scripts/hd_sprite_provider.gd")

var ctrl = null
var bridge = null
var sb = null
var phase = ""
var settle = 0.0
var measure = 0.0
var frames_in_state = 0
var armed = false
var paths = []
var cursor = 0
var rate = 1
var sprites = []

func _initialize():
	ctrl = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(ctrl)
	rate = int(OS.get_environment("CHURN_RATE"))
	if rate <= 0:
		rate = 1

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
	print("[CHURN] running=%s level=%d" % [bridge.is_game_running(), bridge.get_current_level()])

func _prewarm() -> void:
	var mons: Array = bridge.get_active_monsters_data()
	var fams = {}
	for m in mons:
		fams[str(m.get("name", "Monster")) + str(m.get("mode", 0))] = true
	for key in fams.keys():
		var nm = key.substr(0, key.length() - 1)
		var md = int(key.right(1))
		for d in range(8):
			for f in range(14):
				HD.get_monster_sprite(nm, md, d, f, sb.current_tile_model)
	for inst in sb.monster_instances.values():
		var spr = inst.get_node_or_null("MonsterSprite3D") as Sprite3D
		if spr and spr.texture:
			sprites.append(spr)
	print("[CHURN] warmed, sprites=%d" % sprites.size())

func _churn_once() -> void:
	if paths.is_empty() or sprites.is_empty():
		return
	var p: String = paths[cursor % paths.size()]
	cursor += 1
	HD._debug_evict(p)
	var dir_path = p.substr(0, p.rfind("/"))
	var base = p.substr(p.rfind("/") + 1)
	if not base.begins_with("dir_"):
		return
	var parts = base.replace(".png", "").split("_")
	if parts.size() < 4:
		return
	var d = int(parts[1])
	var f = int(parts[3])
	var tex = HD._load_exact_frame(dir_path, d, f)
	if tex == null:
		return
	var spr = sprites[cursor % sprites.size()]
	spr.texture = tex

func _next(p: String) -> void:
	phase = p
	settle = 1.0
	measure = 0.0
	frames_in_state = 0
	print("[CHURN] phase=%s" % p)

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
	if phase == "churn":
		if frames_in_state % rate == 0:
			_churn_once()
	if measure >= 7.0:
		var fps = frames_in_state / measure
		print("[CHURN] %s fps=%.1f" % [phase, fps])
		if phase == "base":
			_prewarm()
			paths = HD.list_cached("res://assets/hd_sprites")
			print("[CHURN] cached paths=%d" % paths.size())
			_next("warmed")
		elif phase == "warmed":
			_next("churn")
		else:
			print("[CHURN] RESULT rate=%d warmed_then_churn=%.1f" % [rate, fps])
			phase = "done"
			quit()
	return false
