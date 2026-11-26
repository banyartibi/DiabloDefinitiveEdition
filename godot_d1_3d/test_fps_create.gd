extends SceneTree
# Does creating a NEW texture (never cached, no eviction) stall, or only
# create-after-free? Uses real HD files not yet in the cache.

const HD = preload("res://scripts/hd_sprite_provider.gd")

var ctrl = null
var bridge = null
var sb = null
var phase = ""
var settle = 0.0
var measure = 0.0
var frames_in_state = 0
var armed = false
var sprites = []
var queue = []      # (dir_path, dir_idx, frame_idx) not yet cached
var created := 0
var samples = []

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
	print("[CRE] running=%s" % bridge.is_game_running())

func _collect_queue() -> void:
	var root_dir = "res://assets/hd_sprites/monsters"
	var cached = HD.list_cached("res://assets/hd_sprites")
	var cached_set = {}
	for c in cached:
		cached_set[c] = true
	var rd = DirAccess.open(root_dir)
	if rd == null:
		print("[CRE] cannot open %s" % root_dir)
		return
	for fam in rd.get_directories():
		var fam_dir = root_dir + "/" + fam
		var fd = DirAccess.open(fam_dir)
		if fd == null:
			continue
		for f in fd.get_files():
			if not f.begins_with("dir_"):
				continue
			var full = fam_dir + "/" + f
			if cached_set.has(full):
				continue
			var parts = f.replace(".png", "").split("_")
			if parts.size() < 4:
				continue
			queue.append([fam_dir, int(parts[1]), int(parts[3])])
	print("[CRE] uncached files available=%d (cached=%d)" % [queue.size(), cached.size()])

func _prepare() -> void:
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
	_collect_queue()

func _create_and_bind() -> void:
	if queue.is_empty() or sprites.is_empty():
		return
	var e = queue.pop_front()
	var tex = HD._load_exact_frame(e[0], e[1], e[2])
	if tex == null:
		return
	created += 1
	sprites[created % sprites.size()].texture = tex

func _next(p: String) -> void:
	phase = p
	settle = 1.0
	measure = 0.0
	frames_in_state = 0
	print("[CRE] phase=%s" % p)

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
	if phase in ["base", "create"]:
		samples.append(delta * 1000.0)
	if phase == "create":
		_create_and_bind()
	if measure >= 7.0:
		var fps = frames_in_state / measure
		var ml = []
		for i in range(32):
			ml.append("%d=%.3f" % [i, Performance.get_monitor(i)])
		print("[CRE] monitors %s" % " ".join(ml))
		var ss = samples.duplicate()
		ss.sort()
		var n = ss.size()
		print("[CRE] %s fps=%.1f created=%d frames_ms min=%.1f p50=%.1f p90=%.1f p99=%.1f max=%.1f" % [phase, fps, created, ss[0], ss[n/2], ss[int(n*0.9)], ss[int(n*0.99)], ss[n-1]])
		samples = []
		if phase == "base":
			_prepare()
			_next("warmed")
		elif phase == "warmed":
			_next("create")
		else:
			print("[CRE] RESULT done")
			phase = "done"
			quit()
	return false
