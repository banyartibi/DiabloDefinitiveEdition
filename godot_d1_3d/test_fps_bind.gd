extends SceneTree
# Distinguish "new texture object" cost from "any texture re-bind" cost.

const HD = preload("res://scripts/hd_sprite_provider.gd")

var ctrl = null
var bridge = null
var sb = null
var phase = ""
var settle = 0.0
var measure = 0.0
var frames_in_state = 0
var armed = false
var pool = []          # already-created textures
var fresh_paths = []   # paths to evict+recreate each cycle
var cursor = 0
var sprites = []
var pending_tex = null
var pending_spr = null

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
	print("[BIND] running=%s" % bridge.is_game_running())

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
				var t = HD.get_monster_sprite(nm, md, d, f, sb.current_tile_model)
				if t:
					pool.append(t)
	for inst in sb.monster_instances.values():
		var spr = inst.get_node_or_null("MonsterSprite3D") as Sprite3D
		if spr and spr.texture:
			sprites.append(spr)
	fresh_paths = HD.list_cached("res://assets/hd_sprites")
	print("[BIND] pool=%d sprites=%d paths=%d" % [pool.size(), sprites.size(), fresh_paths.size()])

func _rebind_existing() -> void:
	if pool.size() < 2 or sprites.is_empty():
		return
	cursor += 1
	var spr = sprites[cursor % sprites.size()]
	spr.texture = pool[(cursor * 7) % pool.size()]

func _bind_fresh_defer() -> void:
	# assign what was created last frame
	if pending_tex != null and pending_spr != null:
		pending_spr.texture = pending_tex
		pending_tex = null
		pending_spr = null
	if fresh_paths.is_empty() or sprites.is_empty():
		return
	var p: String = fresh_paths[cursor % fresh_paths.size()]
	cursor += 1
	HD._debug_evict(p)
	var dir_path = p.substr(0, p.rfind("/"))
	var base = p.substr(p.rfind("/") + 1)
	if not base.begins_with("dir_"):
		return
	var parts = base.replace(".png", "").split("_")
	if parts.size() < 4:
		return
	var tex = HD._load_exact_frame(dir_path, int(parts[1]), int(parts[3]))
	if tex:
		pending_tex = tex
		pending_spr = sprites[cursor % sprites.size()]

func _bind_fresh() -> void:
	if fresh_paths.is_empty() or sprites.is_empty():
		return
	var p: String = fresh_paths[cursor % fresh_paths.size()]
	cursor += 1
	HD._debug_evict(p)
	var dir_path = p.substr(0, p.rfind("/"))
	var base = p.substr(p.rfind("/") + 1)
	if not base.begins_with("dir_"):
		return
	var parts = base.replace(".png", "").split("_")
	if parts.size() < 4:
		return
	var tex = HD._load_exact_frame(dir_path, int(parts[1]), int(parts[3]))
	if tex:
		sprites[cursor % sprites.size()].texture = tex

func _next(p: String) -> void:
	phase = p
	settle = 1.0
	measure = 0.0
	frames_in_state = 0
	print("[BIND] phase=%s" % p)

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
	if phase == "rebind":
		_rebind_existing()
	elif phase == "fresh":
		_bind_fresh()
	elif phase == "fresh_defer":
		_bind_fresh_defer()
	elif phase == "fresh_nomat":
		for spr in sprites:
			spr.material_override = null
		_bind_fresh()
	if measure >= 7.0:
		var fps = frames_in_state / measure
		print("[BIND] %s fps=%.1f" % [phase, fps])
		if phase == "base":
			_prewarm()
			_next("warmed")
		elif phase == "warmed":
			_next("rebind")
		elif phase == "rebind":
			_next("fresh")
		elif phase == "fresh":
			_next("fresh_defer")
		elif phase == "fresh_defer":
			_next("fresh_nomat")
		else:
			print("[BIND] RESULT done")
			phase = "done"
			quit()
	return false
