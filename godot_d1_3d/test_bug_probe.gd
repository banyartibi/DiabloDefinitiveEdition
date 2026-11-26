extends SceneTree
# Probe v2: barrel explosion animation end-to-end + real render FPS harness.

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"
const HD = preload("res://scripts/hd_sprite_provider.gd")

var bridge
var sandbox
var viewport: SubViewport

func _init():
	bridge = ClassDB.instantiate("DiabloBridge")
	if not bridge.init_engine(MPQ_DIR):
		print("init failed")
		quit()
		return
	for attempt in range(8):
		if bridge.is_game_running():
			break
		bridge.menu_select_single_player()
		OS.delay_msec(1500)
		bridge.launch_hero_game(2, 0, true)
		for i in range(60):
			OS.delay_msec(100)
			if bridge.is_game_running():
				break
		print("[PROBE] launch attempt %d: running=%s level=%d gate=%s" % [attempt, bridge.is_game_running(), bridge.get_current_level(), str(bridge.get_read_gate_state())])
	print("[PROBE] game_running=%s level=%d player=%d objects=%d" % [bridge.is_game_running(), bridge.get_current_level(), bridge.get_player_level(), bridge.get_active_objects().size()])
	OS.delay_msec(1500)
	var scene = load("res://scenes/sandbox/native_3d_sandbox.tscn")
	sandbox = scene.instantiate()
	sandbox.diablo_bridge = bridge
	root.add_child(sandbox)
	sandbox._ready()
	sandbox.activate()

	_descend_to_dungeon()
	_test_bridge_cost()
	_test_missile_sizes()
	await _test_flame_tracking()
	await _test_barrel_explosion()
	await _test_missile_live()
	_count_lights()
	await _test_render_fps()
	print("[PROBE] done")
	quit()

func _descend_to_dungeon() -> void:
	for attempt in range(4):
		if bridge.get_current_level() > 0 and bridge.get_active_objects().size() > 0:
			var barrels = 0
			for o in bridge.get_active_objects():
				if str(o.get("category", "")) == "BARREL":
					barrels += 1
			if barrels > 0:
				print("[PROBE] on level %d with %d barrels" % [bridge.get_current_level(), barrels])
				return
		var trigs = bridge.get_level_triggers()
		var target = null
		for t in trigs:
			if int(t.get("target_level", 0)) > bridge.get_current_level():
				target = t
				break
		if target == null:
			for t in trigs:
				if int(t.get("target_level", 0)) != bridge.get_current_level():
					target = t
					break
		if target == null:
			# Town has no trigs: stairs are dTransVal tiles the player walks onto.
			var grid = bridge.get_dungeon_trans_grid()
			if grid.size() < 112 * 112:
				print("[PROBE] no trigger and no trans grid on level %d" % bridge.get_current_level())
				return
			var pp = bridge.get_player_continuous_pos()
			var px = int(float(pp.get("x", 0)))
			var py = int(float(pp.get("y", 0)))
			var best = -1
			var best_d = 1e9
			for y in range(112):
				for x in range(112):
					if grid[y * 112 + x] > 0:
						var d = absi(x - px) + absi(y - py)
						if d < best_d:
							best_d = d
							best = y * 112 + x
			if best < 0:
				print("[PROBE] no trans tiles on level %d" % bridge.get_current_level())
				return
			var tx = best % 112
			var ty = int(best / 112)
			print("[PROBE] walking to trans tile (%d,%d) dist=%d" % [tx, ty, best_d])
			bridge.walk_to_tile(tx, ty)
			var t2 = Time.get_ticks_msec()
			var lvl2 = bridge.get_current_level()
			while Time.get_ticks_msec() - t2 < 25000:
				OS.delay_msec(100)
				if bridge.get_current_level() != lvl2 and not bridge.is_level_loading():
					break
			OS.delay_msec(2000)
			sandbox._process(0.5)
			print("[PROBE] now on level %d, objects=%d" % [bridge.get_current_level(), bridge.get_active_objects().size()])
			continue
		var tx = int(target.get("x"))
		var ty = int(target.get("y"))
		print("[PROBE] walking to stairs (%d,%d) -> level %d" % [tx, ty, int(target.get("target_level"))])
		var lvl0 = bridge.get_current_level()
		bridge.walk_to_tile(tx, ty)
		var t0 = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 4000:
			OS.delay_msec(100)
			sandbox._process(0.1)
			var pp = bridge.get_player_continuous_pos()
			if absf(float(pp.get("x", 0)) - float(tx)) < 1.5 and absf(float(pp.get("y", 0)) - float(ty)) < 1.5:
				break
		bridge.send_click_to_tile(tx, ty, 1)
		var t1 = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t1 < 20000:
			OS.delay_msec(100)
			if bridge.get_current_level() != lvl0 and not bridge.is_level_loading():
				break
		OS.delay_msec(2000)
		sandbox._process(0.5)
		print("[PROBE] now on level %d, objects=%d" % [bridge.get_current_level(), bridge.get_active_objects().size()])

func _obj(id: int) -> Dictionary:
	for o in bridge.get_active_objects():
		if int(o.get("id", -1)) == id:
			return o
	return {}

func _test_bridge_cost() -> void:
	print("=== [COST] bridge query cost per call ===")
	var t0 = Time.get_ticks_msec()
	var n = 0
	while Time.get_ticks_msec() - t0 < 1000:
		bridge.get_active_objects()
		n += 1
	var t1 = Time.get_ticks_msec()
	print("  get_active_objects: %d calls in %d ms -> %.3f ms/call" % [n, t1 - t0, float(t1 - t0) / n])
	var t2 = Time.get_ticks_msec()
	n = 0
	while Time.get_ticks_msec() - t2 < 1000:
		sandbox.update_props(0.016)
		n += 1
	var t3 = Time.get_ticks_msec()
	print("  update_props: %d calls in %d ms -> %.3f ms/call" % [n, t3 - t2, float(t3 - t2) / n])

func _test_missile_sizes() -> void:
	print("=== [BUG1] missile texture vs pixel_size ===")
	var px1 = sandbox.PIXEL_SIZE_1X
	var pxhd = sandbox.PIXEL_SIZE_HD
	for g in ["explosion", "bigexp", "firebolt", "litearrow"]:
		var tex = HD.get_missile_sprite(g, 0, 1, 1)
		if tex == null:
			print("  %s: no HD frame" % g)
			continue
		var w = tex.get_width()
		print("  %s: %dx%d -> world %.2f units @1X, %.2f @HD" % [g, w, tex.get_height(), w * px1, w * pxhd])
	# what the code currently assigns: pixel_size is set at node creation to PIXEL_SIZE_1X
	print("  PIXEL_SIZE_1X=%.5f PIXEL_SIZE_HD=%.5f (ratio %.2f)" % [px1, pxhd, px1 / pxhd])
	var live = bridge.get_active_missiles()
	var sizes = {}
	for m in live:
		var g = str(m.get("graphic", ""))
		var tex = HD.get_missile_sprite(str(m.get("cel", "")), int(m.get("dir", 0)), int(m.get("anim_frame", 1)), 1)
		var k = "%s:%s" % [str(m.get("cel", "")), ("%dx%d" % [tex.get_width(), tex.get_height()]) if tex else "none"]
		sizes[k] = int(sizes.get(k, 0)) + 1
	print("  live missiles: %s" % str(sizes))

func _test_barrel() -> void:
	print("=== [BUG2] barrel break timeline ===")
	var barrels = []
	for o in bridge.get_active_objects():
		if str(o.get("category", "")) == "BARREL":
			barrels.append(o)
	print("  barrels on level: %d" % barrels.size())
	if barrels.is_empty():
		print("  no barrels — skipping")
		return
	var b = barrels[0]
	var id = int(b.get("id"))
	print("  before: id=%d type=%d graphic=%s frame=%d/%d broken=%s solid=%s" % [
		id, int(b.get("type")), str(b.get("graphic")), int(b.get("anim_frame")), int(b.get("anim_total")), str(b.get("is_broken")), str(b.get("solid"))])
	var bx = int(b.get("tile_x"))
	var by = int(b.get("tile_y"))
	var node = sandbox.prop_instances.get(id)
	var engine_seen = {}
	var godot_seen = {}
	var t0 = Time.get_ticks_msec()
	bridge.interact_with_object(id, bx, by)
	while Time.get_ticks_msec() - t0 < 2500:
		OS.delay_msec(50)
		sandbox._process(0.05)
		var cur = _obj(id)
		if cur.is_empty():
			print("  t=%.0fms object DELETED" % (Time.get_ticks_msec() - t0))
			break
		var ef = int(cur.get("anim_frame"))
		var gf = int(sandbox.prop_last_frame.get(id, -1))
		var texsize = _prop_tex_size(node)
		var key = "%d/%d" % [ef, gf]
		if not engine_seen.has(key):
			engine_seen[key] = Time.get_ticks_msec() - t0
			print("  t=%5dms engine_frame=%2d/%2d godot_frame=%2d tex=%s graphic=%s broken=%s visible=%s" % [
				Time.get_ticks_msec() - t0, ef, int(cur.get("anim_total")), gf, texsize,
				str(cur.get("graphic")), str(cur.get("is_broken")), str(node != null and node.visible)])
	# final state
	var cur = _obj(id)
	if not cur.is_empty():
		print("  FINAL: frame=%d/%d broken=%s graphic=%s godot_frame=%d tex=%s" % [
			int(cur.get("anim_frame")), int(cur.get("anim_total")), str(cur.get("is_broken")), str(cur.get("graphic")),
			int(sandbox.prop_last_frame.get(id, -1)), _prop_tex_size(node)])
		# which HD file does the provider resolve for engine frame 1 (intact) vs final?
		for f in range(1, int(cur.get("anim_total")) + 1):
			var tex = HD.get_object_sprite(str(cur.get("graphic")), f, 1)
			print("    engine frame %d -> HD %s" % [f, ("%dx%d" % [tex.get_width(), tex.get_height()]) if tex else "MISSING"])

func _test_flame_objects() -> void:
	print("=== [BUG2b] continuously animated objects (torches/flames/candles) ===")
	var animated = []
	for o in bridge.get_active_objects():
		if int(o.get("anim_total", 1)) > 1:
			animated.append(o)
	print("  objects with anim_total>1: %d" % animated.size())
	var before = {}
	for o in animated:
		before[int(o.get("id"))] = [int(o.get("anim_frame")), str(o.get("graphic")), 0]
	var engine_changes = 0
	var t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2000:
		OS.delay_msec(25)
		sandbox._process(0.025)
		for id in before.keys():
			var cur = _obj(id)
			if cur.is_empty():
				continue
			if int(cur.get("anim_frame")) != before[id][0]:
				engine_changes += 1
				before[id][0] = int(cur.get("anim_frame"))
				before[id][2] += 1
	var moved = []
	for id in before.keys():
		if before[id][2] > 0:
			moved.append("%d(%s x%d)" % [id, before[id][1], before[id][2]])
	print("  engine frame changes in 2s: %d ; animated-by-engine objects: %d of %d" % [engine_changes, moved.size(), before.size()])
	print("  moved: %s" % ", ".join(moved.slice(0, 12)))
	var synced = 0
	var stale = 0
	for id in before.keys():
		var cur = _obj(id)
		if cur.is_empty():
			continue
		if int(sandbox.prop_last_frame.get(id, -1)) == int(cur.get("anim_frame")):
			synced += 1
		else:
			stale += 1
			print("    STALE id=%d graphic=%s engine=%d godot=%d" % [id, str(cur.get("graphic")), int(cur.get("anim_frame")), int(sandbox.prop_last_frame.get(id, -1))])
	print("  prop nodes in sync with engine at sample end: %d, stale: %d" % [synced, stale])

func _test_render_fps() -> void:
	print("=== [BUG3] render harness: sandbox in a 2560x1440 SubViewport ===")
	viewport = SubViewport.new()
	viewport.size = Vector2i(2560, 1440)
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var env_res = load("res://scenes/main_3d.tscn")
	var we = WorldEnvironment.new()
	# reuse the environment from the main scene
	var scene_inst = env_res.instantiate()
	for c in scene_inst.get_children():
		if c is WorldEnvironment:
			we.environment = c.environment
			viewport.add_child(we)
			break
	scene_inst.queue_free()
	var cam = Camera3D.new()
	var p = bridge.get_player_continuous_pos()
	cam.position = sandbox.tile_to_world_3d(float(p.get("x", 0)), float(p.get("y", 0))) + Vector3(0, -14, 7.8)
	viewport.add_child(cam)
	root.remove_child(sandbox)
	viewport.add_child(sandbox)
	var drawn0 = Engine.get_frames_drawn()
	var t0 = Time.get_ticks_msec()
	var frames = 0
	while Time.get_ticks_msec() - t0 < 3000:
		await process_frame
		frames += 1
	var dt = Time.get_ticks_msec() - t0
	var ri = RenderingServer
	print("  %d frames in %d ms -> %.1f fps (frames_drawn delta %d)" % [frames, dt, frames * 1000.0 / dt, Engine.get_frames_drawn() - drawn0])
	print("  draw calls/frames: %s  primitives: %s" % [
		ri.get_rendering_info(ri.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		ri.get_rendering_info(ri.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])


func _count_lights() -> void:
	print("=== [BUG3a] shadow cost audit ===")
	var omni_shadow = 0
	var omni_plain = 0
	var visible_omni_shadow = 0
	var stack = [sandbox]
	while stack.size() > 0:
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
			if c is OmniLight3D:
				if c.shadow_enabled:
					omni_shadow += 1
					if c.visible:
						visible_omni_shadow += 1
				else:
					omni_plain += 1
			elif c is DirectionalLight3D and c.shadow_enabled:
				print("  directional shadow on: %s" % c.name)
			elif c is SpotLight3D and c.shadow_enabled:
				print("  spot shadow on: %s" % c.name)
	print("  omni lights: %d shadowed (%d visible), %d unshadowed" % [omni_shadow, visible_omni_shadow, omni_plain])
	var spr = 0
	stack = [sandbox]
	while stack.size() > 0:
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
			if c is Sprite3D:
				spr += 1
	print("  Sprite3D nodes: %d" % spr)

func _test_flame_tracking() -> void:
	print("=== [BUG2b] animated prop frame tracking (5Hz gate removed) ===")
	var tracked: Dictionary = {}   # oid -> {"a": frameA, "b": frameB}
	for o in bridge.get_active_objects():
		var oid = o.get("id", -1)
		if oid < 0 or not sandbox.prop_instances.has(oid):
			continue
		var n = sandbox.prop_instances[oid]
		if not is_instance_valid(n) or not n.visible:
			continue
		if n.get_node_or_null("ObjectSprite3D") == null:
			continue
		tracked[oid] = { "a": int(o.get("anim_frame", 1)), "g": int(sandbox.prop_last_frame.get(oid, -999)), "graphic": str(o.get("graphic", "")), "total": int(o.get("anim_total", o.get("frames", 1))) }
	var animated = 0
	var exact = 0
	var lagged = 0
	for oid in tracked.keys():
		var total = int(tracked[oid]["total"])
		if total > 1:
			animated += 1
			if tracked[oid]["g"] == tracked[oid]["a"]:
				exact += 1
			else:
				lagged += 1
				print("  LAG id=%d graphic=%s engine=%d godot=%d (anim_total=%d)" % [oid, tracked[oid]["graphic"], tracked[oid]["a"], tracked[oid]["g"], total])
	print("  animated billboard props: %d, exactly synced: %d, lagged: %d" % [animated, exact, lagged])
	# Second sample 300 ms later: engine frames must have advanced and godot must follow.
	var t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300:
		await process_frame
	var advanced = 0
	var followed = 0
	for o in bridge.get_active_objects():
		var oid = o.get("id", -1)
		if oid < 0 or not tracked.has(oid):
			continue
		var eng = int(o.get("anim_frame", 1))
		if eng != tracked[oid]["a"]:
			advanced += 1
			if int(sandbox.prop_last_frame.get(oid, -999)) == eng:
				followed += 1
			else:
				print("  LAG2 id=%d graphic=%s engine %d -> %d, godot=%d" % [oid, tracked[oid]["graphic"], tracked[oid]["a"], eng, int(sandbox.prop_last_frame.get(oid, -999))])
	print("  frames advanced in 300ms: %d, godot followed exactly: %d" % [advanced, followed])

func _test_barrel_explosion() -> void:
	print("=== [BUG2c] barrel explosion graphic swap ===")
	var pp = bridge.get_player_continuous_pos()
	var px = float(pp.get("pos_x", 0))
	var py = float(pp.get("pos_y", 0))
	var barrels: Array = []
	for o in bridge.get_active_objects():
		if str(o.get("graphic", "")).begins_with("barrel") and not bool(o.get("broken", false)):
			barrels.append(o)
	if barrels.size() == 0:
		print("  no barrels")
		return
	barrels.sort_custom(func(a, b): return (pow(float(a.get("tile_x", 0)) - px, 2) + pow(float(a.get("tile_y", 0)) - py, 2)) < (pow(float(b.get("tile_x", 0)) - px, 2) + pow(float(b.get("tile_y", 0)) - py, 2)))
	var oid = int(barrels[0].get("id", -1))
	var bt = int(barrels[0].get("tile_x", 0))
	var by = int(barrels[0].get("tile_y", 0))
	print("  nearest barrel id=%d tile=%d,%d (player %.1f,%.1f)" % [oid, bt, by, px, py])
	var seen: Dictionary = {}
	var graphic_swap = ""
	var frames: Array = []
	for i in range(150):
		bridge.walk_to_tile(bt, by)
		bridge.send_click_to_tile(bt, by, 1)
		await process_frame
		if i % 3 == 0:
			for o in bridge.get_active_objects():
				if int(o.get("id", -1)) != oid:
					continue
				var eng = int(o.get("anim_frame", 1))
				var gr = str(o.get("graphic", ""))
				var key = "%s:%d" % [gr, eng]
				if not seen.has(key):
					seen[key] = true
					frames.append(key)
				if not frames.has(key):
					frames.append(key)
				if sandbox.prop_instances.has(oid):
					var n = sandbox.prop_instances[oid]
					if is_instance_valid(n) and str(n.get_meta("hd_graphic", "")) != gr and graphic_swap == "":
						graphic_swap = "%s -> meta %s (engine %s)" % [gr, str(n.get_meta("hd_graphic", "")), gr]
				if bool(o.get("broken", false)):
					break
			if bool(_find_barrel(oid).get("broken", false)):
				break
	print("  engine states seen: %s" % ", ".join(frames))
	var eng_now = _find_barrel(oid)
	var g_now = int(eng_now.get("anim_frame", 1))
	var gr_now = str(eng_now.get("graphic", ""))
	var godot_now = int(sandbox.prop_last_frame.get(oid, -999))
	var meta_now = ""
	if sandbox.prop_instances.has(oid):
		var nn = sandbox.prop_instances[oid]
		if is_instance_valid(nn):
			meta_now = str(nn.get_meta("hd_graphic", ""))
			var spr = nn.get_node_or_null("ObjectSprite3D") as Sprite3D
			if spr and spr.texture:
				meta_now += " tex=%dx%d px=%.5f" % [spr.texture.get_width(), spr.texture.get_height(), spr.pixel_size]
	print("  final engine graphic=%s frame=%d broken=%s | godot frame=%d meta=%s" % [gr_now, g_now, str(eng_now.get("broken")), godot_now, meta_now])
	print("  graphic swap observed: %s" % (graphic_swap if graphic_swap != "" else "no swap detected"))

func _find_barrel(oid: int) -> Dictionary:
	for o in bridge.get_active_objects():
		if int(o.get("id", -1)) == oid:
			return o
	return {}

func _test_missile_live() -> void:
	print("=== [BUG1b] live missile sprite scale (casting spells) ===")
	var px1 = float(sandbox.get("PIXEL_SIZE_1X"))
	var pxh = float(sandbox.get("PIXEL_SIZE_HD"))
	var seen: Dictionary = {}
	var max_seen = 0
	for i in range(120):
		if bridge.has_method("quick_cast_hotkey"):
			bridge.quick_cast_hotkey(0)
		if i % 4 == 0:
			var pp2 = bridge.get_player_continuous_pos()
			bridge.send_click_to_tile(int(float(pp2.get("pos_x", 0))) + 3, int(float(pp2.get("pos_y", 0))), 1)
		await process_frame
		if sandbox.missile_instances.size() > max_seen:
			max_seen = sandbox.missile_instances.size()
		for mid in sandbox.missile_instances.keys():
			var n = sandbox.missile_instances[mid]
			if not is_instance_valid(n) or not n.visible:
				continue
			var spr = n.get_node_or_null("Sprite3D") as Sprite3D
			if spr == null or spr.texture == null:
				continue
			var key = "%dx%d@%.5f" % [spr.texture.get_width(), spr.texture.get_height(), spr.pixel_size]
			if not seen.has(key):
				seen[key] = true
				var want = "HD(%.5f)" % pxh if spr.pixel_size > pxh - 0.00001 and spr.pixel_size < pxh + 0.00001 else ("1X(%.5f)" % px1)
				print("  missile id=%s tex=%dx%d pixel_size=%.5f -> world %.2f units [%s]" % [
					str(mid), spr.texture.get_width(), spr.texture.get_height(), spr.pixel_size,
					spr.texture.get_width() * spr.pixel_size, want])
	if seen.size() == 0:
		print("  no live missile sprites observed (max missile nodes seen: %d)" % max_seen)

func _prop_tex_size(node) -> String:
	if node == null:
		return "no-node"
	var spr = node.get_node_or_null("ObjectSprite3D") as Sprite3D
	if spr == null:
		return "no-sprite"
	if spr.texture == null:
		return "null-tex"
	return "%dx%d" % [spr.texture.get_width(), spr.texture.get_height()]
