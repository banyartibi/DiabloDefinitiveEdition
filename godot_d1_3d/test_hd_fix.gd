extends SceneTree
# TEMP verification driver for the HD prefetch fix: fps cold vs warm.

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"
const HdSpriteProvider = preload("res://scripts/hd_sprite_provider.gd")

var ctrl = null
var sb = null
var armed = false
var win = 0
var win_time = 0.0
var win_frames = 0
var times = []
var times_ms = []
var last_drawn = 0
var total_proc = 0
var _sec_acc = 0.0
var proc0 = 0.0

func _gpu_busy() -> int:
	var f = FileAccess.open("/sys/class/drm/card0/device/gpu_busy_percent", FileAccess.READ)
	if f == null:
		return -1
	return int(f.get_line())

func _proc_total() -> int:
	return int(Performance.get_monitor(Performance.TIME_PROCESS) * 1000)

func _initialize():
	ctrl = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(ctrl)

func _launch() -> void:
	var bridge = ctrl.diablo_bridge
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
	_apply_toggles()
	print("[FIX] running=%s level=%d mode=%d" % [bridge.is_game_running(), bridge.get_current_level(), ctrl.current_display_mode])

func _apply_toggles() -> void:
	var tg = OS.get_environment("TOGGLES")
	if tg == "":
		return
	print("[TOG] %s" % tg)
	for t in tg.split(","):
		match t.strip_edges():
			"count_nodes":
				print("[COUNT] floor=%d props=%d mon=%d scenery=%d items=%d corpses=%d stairs=%d effects=%d" % [
					sb.floor_root.get_child_count(), sb.props_root.get_child_count(),
					sb.monsters_root.get_child_count(), sb.town_scenery_root.get_child_count(),
					sb.items_root.get_child_count(), sb.corpse_root_count() if sb.has_method("corpse_root_count") else -1,
					sb.stairs_root.get_child_count(), sb.effects_root.get_child_count()])
				var hist = {}
				for c in sb.floor_root.get_children():
					var cls = c.get_class()
					hist[cls] = int(hist.get(cls, 0)) + 1
				print("[COUNT_FLOOR_CLASSES] %s" % str(hist))
				var kids = 0
				for c in sb.floor_root.get_children():
					kids += c.get_child_count()
				print("[COUNT_FLOOR_GRANDKIDS] %d" % kids)
			"half_view":
				ctrl.game_view.size = Vector2i(1280, 720)
				print("[VIEW] %s msaa=%s ssaa=%s" % [str(ctrl.game_view.size), str(ctrl.game_view.msaa_3d), str(ctrl.game_view.screen_space_aa)])
			"quarter_view":
				ctrl.game_view.size = Vector2i(640, 360)
			"no_msaa":
				ctrl.game_view.msaa_3d = 0
				ctrl.game_view.screen_space_aa = 0
			"msaa_off_only":
				ctrl.game_view.msaa_3d = 0
			"ssaa_off_only":
				ctrl.game_view.screen_space_aa = 0
			"msaa_2x":
				ctrl.game_view.msaa_3d = 1
			"msaa_off_view1440":
				ctrl.game_view.msaa_3d = 0
				ctrl.game_view.size = Vector2i(1920, 1080)
			"msaa_on":
				ctrl.game_view.msaa_3d = 2
			"hide_floor_msaa_on":
				ctrl.game_view.msaa_3d = 2
				sb.floor_root.visible = false
			"env_info":
				var e = sb.world_env.environment
				var names = []
				for pi in e.get_property_list():
					var nm = pi["name"]
					if nm.contains("sdfgi") or nm.contains("sdfgi") or nm.contains("fog") or nm.contains("glow") or nm.contains("ambient") or nm.contains("volumetric"):
						names.append("%s=%s" % [nm, str(e.get(nm))])
				print("[ENVPROPS] %s" % " ".join(names))
				print("[ENV] sdfgi=%s fog=%s glow=%s ambient=%s tonemap=%s lights=%d ssao=%s" % [
					str(e.global_light_enabled), str(e.volumetric_fog_enabled), str(e.glow_enabled),
					str(e.ambient_light_source), str(e.tonemap_mode), _all_lights().size(),
					str(sb.world_env.environment.get_ssao_enabled()) if e.has_method("get_ssao_enabled") else "?"])
			"no_sdfgi":
				sb.world_env.environment.global_light_enabled = false
			"floor_relief0":
				_set_floor_param("relief_mode", 0)
			"floor_no_wet":
				_set_floor_param("wet_floor", false)
			"floor_info":
				if sb and is_instance_valid(sb):
					var total = 0
					var mats = {}
					var texsizes = {}
					for pid in sb.floor_mmis:
						var m = sb.floor_mmis[pid]
						total += m.multimesh.instance_count if m.multimesh else 0
						var mm = m.material
						if mm is ShaderMaterial:
							var sh = mm.shader.resource_path if mm.shader else "<null>"
							mats[sh] = int(mats.get(sh, 0)) + 1
							var tx = mm.get_shader_parameter("texture_albedo")
							if tx == null:
								tx = mm.get_shader_parameter("albedo_texture")
							if tx is Texture2D:
								var sz = str(tx.get_size())
								texsizes[sz] = int(texsizes.get(sz, 0)) + 1
					print("[FLOORINFO] mmis=%d instances=%d mats=%s tex=%s relief=%s wet=%s" % [
						sb.floor_mmis.size(), total, str(mats), str(texsizes),
						str(_first_floor_param("relief_mode")), str(_first_floor_param("wet_floor"))])
					var kids = []
					for c in sb.floor_root.get_children():
						kids.append("%s:%s" % [c.get_class(), c.name])
					print("[FLOORROOT] kids=%d %s" % [kids.size(), str(kids.slice(0, 8))])
			"floor_unlit":
				if sb and is_instance_valid(sb):
					var mat = StandardMaterial3D.new()
					mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					mat.cull_mode = BaseMaterial3D.CULL_DISABLED
					for pid in sb.floor_mmis:
						sb.floor_mmis[pid].material_override = mat
			"sb_invisible":
				if sb and is_instance_valid(sb):
					sb.visible = false
			"no_vfog":
				if sb and is_instance_valid(sb):
					sb.world_env.volumetric_fog_enabled = false
					print("[ENV] vfog off")
			"no_fog":
				sb.world_env.environment.volumetric_fog_enabled = false
			"no_glow":
				sb.world_env.environment.glow_enabled = false
			"no_sdfgi_fog":
				sb.world_env.environment.global_light_enabled = false
				sb.world_env.environment.volumetric_fog_enabled = false
			"hide_props":
				sb.props_root.visible = false
			"hide_mon":
				sb.monsters_root.visible = false
			"hide_scenery":
				sb.town_scenery_root.visible = false
			"hide_floor":
				sb.floor_root.visible = false
			"hide_corpses":
				sb.corpses_root.visible = false
			"hide_env":
				sb.world_env.visible = false
			"hide_all":
				for r in [sb.props_root, sb.monsters_root, sb.town_scenery_root, sb.floor_root,
						sb.corpses_root, sb.items_root, sb.missiles_root, sb.effects_root, sb.stairs_root]:
					if r:
						r.visible = false
			"small_win":
				DisplayServer.window_set_size(Vector2i(800, 450))
				print("[WIN] %s" % str(DisplayServer.window_get_size()))
			"floor_no_shadow":
				for m in sb.floor_mmis.values():
					m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			"floor_default_mat":
				for m in sb.floor_mmis.values():
					m.material_override = null
			"floor_1_inst":
				for m in sb.floor_mmis.values():
					m.multimesh.instance_count = 1
			"floor_no_mm":
				for m in sb.floor_mmis.values():
					m.visible = false
			"mms_no_shadow":
				for n in _all_mesh_instances():
					n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			"no_shadows":
				for n in _all_lights():
					n.shadow_enabled = false
			"no_lights":
				for n in _all_lights():
					n.visible = false
			"no_shadow_sprites":
				for n in _all_sprites():
					n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			"pipeline_info":
				print("[PIPE] hdr=%s msaa=%s ssaa=%s scale=%s size=%s upscaler=%s gamma=%s bright=%s profile=%s" % [
					str(ctrl.game_view.use_hdr_2d), str(ctrl.game_view.msaa_3d), str(ctrl.game_view.screen_space_aa),
					str(ctrl.game_view.scaling_3d_scale), str(ctrl.game_view.size),
					str(ctrl.brightness_material.get_shader_parameter("upscaler_mode")),
					str(ctrl.brightness_material.get_shader_parameter("gamma")),
					str(ctrl.brightness_material.get_shader_parameter("brightness")),
					str(ctrl.brightness_material.get_shader_parameter("color_profile"))])
			"no_fsr":
				ctrl.brightness_material.set_shader_parameter("upscaler_mode", 0)
				print("[PIPE] upscaler -> 0")
			"no_composite_mat":
				ctrl.composite_rect.material = null
			"no_hdr":
				ctrl.game_view.use_hdr_2d = false
			"no_fxaa":
				ctrl.game_view.screen_space_aa = 0
			"no_composite_draw":
				ctrl.composite_rect.visible = false
			"no_3d_render":
				ctrl.game_view.render_target_update_mode = SubViewport.UPDATE_ONCE
			"win_small":
				DisplayServer.window_set_size(Vector2i(1280, 720))
				print("[WSIZE] %s" % str(DisplayServer.window_get_size()))
			"no_ui":
				for c in get_root().get_children():
					if c is CanvasLayer and c != ctrl.composite_rect.get_parent():
						c.visible = false
				if ctrl.modern_hud:
					ctrl.modern_hud.visible = false

func _class_hist(n: Node) -> Dictionary:
	var h = {}
	for c in n.get_children():
		var cls = c.get_class()
		h[cls] = int(h.get(cls, 0)) + 1
	return h

func _shadow_light_count() -> int:
	var c = 0
	for n in _all_lights():
		if n is Light3D and n.shadow_enabled:
			c += 1
	return c

func _set_floor_param(name: String, value) -> void:
	if sb == null or not is_instance_valid(sb):
		return
	var n = 0
	for pid in sb.floor_mmis:
		var mm = sb.floor_mmis[pid].material
		if mm is ShaderMaterial:
			mm.set_shader_parameter(name, value)
			n += 1
	print("[FLOORPARAM] %s=%s on %d meshes" % [name, str(value), n])

func _first_floor_param(name: String):
	if sb == null or not is_instance_valid(sb):
		return null
	for pid in sb.floor_mmis:
		var mm = sb.floor_mmis[pid].material
		if mm is ShaderMaterial:
			return mm.get_shader_parameter(name)
	return null

func _all_mesh_instances_in(root: Node) -> Array:
	var out = []
	var stack = [root]
	while stack:
		var n = stack.pop_back()
		for c in n.get_children():
			if c is MeshInstance3D:
				out.append(c)
			stack.append(c)
	return out

func _all_lights() -> Array:
	var out = []
	var stack = [sb]
	while stack:
		var n = stack.pop_back()
		for c in n.get_children():
			if c is Light3D:
				out.append(c)
			stack.append(c)
	return out

func _all_mesh_instances() -> Array:
	var out = []
	var stack = [sb]
	while stack:
		var n = stack.pop_back()
		for c in n.get_children():
			if c is MeshInstance3D or c is MultiMeshInstance3D:
				out.append(c)
			stack.append(c)
	return out

func _all_sprites() -> Array:
	var out = []
	var stack = [sb]
	while stack:
		var n = stack.pop_back()
		for c in n.get_children():
			if c is Sprite3D:
				out.append(c)
			stack.append(c)
	return out

func _process(delta: float) -> bool:
	if ctrl == null or not is_instance_valid(ctrl):
		return false
	if not armed:
		if ctrl.diablo_bridge == null:
			return false
		armed = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_launch()
		return false
	# The WM minimizes the fullscreen window; Godot then pauses rendering and the
	# main loop spins at 145fps without drawing anything. Keep it mapped.
	win_time += delta
	win_frames += 1
	_sec_acc += delta
	if _sec_acc >= 1.0:
		_sec_acc = 0.0
		print("[SEC] drawn=%d proc=%d lvl=%d mem=%d pending=%d" % [
			Engine.get_frames_drawn(), _proc_total(), int(sb.get_current_level()) if sb and is_instance_valid(sb) else -1,
			OS.get_static_memory_usage(), HdSpriteProvider.pending_count()])
	times.append(Time.get_ticks_msec())
	if times.size() > 400:
		times.pop_front()
	if win_time >= 6.0:
		var fps = win_frames / win_time
		times_ms.clear()
		for i in range(1, times.size()):
			times_ms.append(float(times[i] - times[i - 1]))
		times_ms.sort()
		var p50 = times_ms[int(times_ms.size() * 0.5)] if times_ms.size() > 0 else 0.0
		var p95 = times_ms[int(times_ms.size() * 0.95)] if times_ms.size() > 0 else 0.0
		var slow = 0
		for t in times_ms:
			if t > 20.0:
				slow += 1
		var st = "sb=none"
		if sb != null and is_instance_valid(sb):
			st = "active=%s mons=%d props=%d items=%d missiles=%d corpses=%d" % [
				sb.is_sandbox_active, sb.monster_instances.size(), sb.prop_instances.size(),
				sb.item_instances.size(), sb.missile_instances.size(), sb.corpse_instances.size()]
		print("[FIX] window=%d fps=%.1f p50=%.1fms slow=%d/%d pending=%d %s" % [
			win, fps, p50, slow, times_ms.size(), HdSpriteProvider.pending_count(), st])
		var drawn = Engine.get_frames_drawn()
		print("[WIN] mode=%s hid=%s min=%s size=%s dfps=%.1f mem=%d proc=%.2fms gpu=%d%%" % [
			str(DisplayServer.window_get_mode()), str(DisplayServer.window_get_flag(0)),
			str(DisplayServer.window_get_flag(1)), str(root.size),
			float(drawn - last_drawn) / win_time if win_time > 0 else 0.0,
			OS.get_static_memory_usage(),
			(Performance.get_monitor(Performance.TIME_PROCESS) - proc0) * 1000.0 / win_frames if win_frames > 0 else 0.0,
			_gpu_busy()])
		total_proc += win_frames
		print("[PERF] proc+%d drawn+%d lag=%d p95=%.1fms" % [
			win_frames, drawn - last_drawn, total_proc - drawn,
			times_ms[int(times_ms.size() * 0.95)] if times_ms.size() > 0 else 0.0])
		if OS.get_environment("TOGGLES") == "count_nodes":
			var hist = {}
			var stack = [ctrl]
			var total = 0
			while stack:
				var n = stack.pop_back()
				for c in n.get_children():
					total += 1
					var cls = c.get_class()
					hist[cls] = int(hist.get(cls, 0)) + 1
					stack.append(c)
			print("[TREE] total=%d classes=%s" % [total, str(hist)])
			print("[FLOOR] kids=%d mmis=%d classes=%s" % [sb.floor_root.get_child_count(), sb.floor_mmis.size(), str(_class_hist(sb.floor_root))])
		print("[LIGHTS] n=%d shadows=%d" % [_all_lights().size(), _all_lights().count(0) if false else _shadow_light_count()])
		var mon = []
		for i in range(33):
			mon.append("%d=%.4f" % [i, Performance.get_monitor(i)])
		print("[MON] " + " ".join(mon))
		var save_p = OS.get_environment("SAVE")
		if save_p != "" and (win == 3 or win == 6):
			var img = get_root().get_texture().get_image()
			var err = img.save_png(save_p)
			img.save_png(save_p.replace(".png", "-w%d.png" % win))
			print("[SAVE] %s err=%d size=%s drawn=%d exposed=%s" % [save_p, err, str(img.get_size()), Engine.get_frames_drawn()])
		last_drawn = drawn
		win += 1
		_apply_toggles()
		win_time = 0.0
		win_frames = 0
		proc0 = Performance.get_monitor(Performance.TIME_PROCESS)
		times.clear()
		if win >= 8:
			quit()
	return false
