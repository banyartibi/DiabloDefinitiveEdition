extends SceneTree
# TEMP fps bench: warm up, then measure fixed-length windows. Env:
#   TOGGLES=csv, GV_SIZE=WxH, WARM=secs (default 15), MEASURE=secs (default 10), WINDOWS=n (default 3)

const HdSpriteProvider = preload("res://scripts/hd_sprite_provider.gd")

var ctrl = null
var sb = null
var armed = false
var phase = "warm"          # warm -> measure
var phase_time = 0.0
var win_frames = 0
var times = []
var win_idx = 0
var cfg_list = []
var cur_cfg = 0
var block_wins = 3
var blocks_done = 0
var total_blocks = 0
var last_stats = ""
var show_all = false
var pin_cam = false
var cam_xform = Transform3D()
var WARM = 15.0
var MEASURE = 10.0
var WINDOWS = 3

func _initialize():
	WARM = float(OS.get_environment("WARM")) if OS.get_environment("WARM") != "" else 15.0
	MEASURE = float(OS.get_environment("MEASURE")) if OS.get_environment("MEASURE") != "" else 10.0
	WINDOWS = int(OS.get_environment("WINDOWS")) if OS.get_environment("WINDOWS") != "" else 3
	block_wins = int(OS.get_environment("BLOCK")) if OS.get_environment("BLOCK") != "" else 3
	cfg_list = []
	for c in OS.get_environment("TOGLIST").split(";"):
		var t = c.strip_edges()
		cfg_list.append((t + ",win_small") if t != "" else "win_small")
	if cfg_list.is_empty():
		cfg_list = ["win_small"]
	total_blocks = cfg_list.size() * 2
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
	OS.set_environment("TOGGLES", cfg_list[0])
	_apply_toggles(true)
	print("[START] running=%s level=%d" % [bridge.is_game_running(), bridge.get_current_level()])

func _pg(obj: Object, key: String):
	for pi in obj.get_property_list():
		if pi["name"] == key:
			return obj.get(key)
	return "<n/a>"

func _floor_materials() -> Array:
	var out = []
	var seen = {}
	for m in _floor_mmis():
		if m.multimesh == null or m.multimesh.mesh == null:
			continue
		var mt = m.material_override
		if mt == null and m.multimesh and m.multimesh.mesh:
			mt = m.multimesh.mesh.surface_get_material(0)
		if mt != null and not seen.has(mt.get_instance_id()):
			seen[mt.get_instance_id()] = true
			out.append(mt)
	return out

func _floor_mmis() -> Array:
	var out = []
	if sb == null or not is_instance_valid(sb):
		return out
	for c in sb.floor_root.get_children():
		if c is MultiMeshInstance3D:
			out.append(c)
	return out

func _lights() -> Array:
	var out = []
	if sb == null or not is_instance_valid(sb):
		return out
	var stack = [sb]
	while stack:
		var n = stack.pop_back()
		for c in n.get_children():
			if c is Light3D:
				out.append(c)
			stack.append(c)
	return out

func _apply_toggles(first: bool) -> void:
	var tg = OS.get_environment("TOGGLES")
	if sb == null or not is_instance_valid(sb):
		sb = ctrl.sandbox_instance
	if first:
		print("[TOG] %s" % tg)
	if OS.get_environment("GV_SIZE") != "":
		var p = OS.get_environment("GV_SIZE").split("x")
		if p.size() == 2:
			ctrl.game_view.size = Vector2i(int(p[0]), int(p[1]))
	for t in tg.split(","):
		match t.strip_edges():
			"":
				continue
			"win_small":
				DisplayServer.window_set_size(Vector2i(1280, 720))
			"dump":
				if sb and is_instance_valid(sb):
					var mm = _floor_mmis()
					var inst = 0
					var matinfo = {}
					for m in mm:
						if m.multimesh:
							inst += m.multimesh.instance_count
						var mt = m.material_override
						if mt == null and m.multimesh and m.multimesh.mesh:
							mt = m.multimesh.mesh.surface_get_material(0)
						if mt is ShaderMaterial:
							var key = mt.shader.resource_path if mt.shader else "<no shader>"
							if not matinfo.has(key):
								matinfo[key] = {
									"n": 0, "relief": mt.get_shader_parameter("relief_mode"),
									"wet": mt.get_shader_parameter("wet_floor"),
									"town": mt.get_shader_parameter("is_town"),
									"lava": mt.get_shader_parameter("is_lava_level"),
									"shading": mt.shading_mode, "transp": mt.transparency,
								}
							matinfo[key]["n"] = int(matinfo[key]["n"]) + 1
					var li = []
					for l in _lights():
						li.append("%s:%s/sh=%s/r=%s" % [l.get_class(), l.name, str(l.shadow_enabled),
							str(l.shadow_atlas_size) if l.has_method("get_shadow_atlas_size") else "?"])
					print("[DUMP] floor_mmis=%d inst=%d mats=%s" % [mm.size(), inst, str(matinfo)])
					print("[DUMP] lights=%d %s" % [li.size(), str(li.slice(0, 14))])
					var e = sb.world_env.environment
					print("[DUMP] glow=%s strength=%s vfog=%s density=%s ssao=%s aoi=%s ambient=%s bm=%s sdfgi=%s fog=%s" % [
						str(e.glow_enabled), str(e.glow_strength), str(e.volumetric_fog_enabled),
						str(e.volumetric_fog_density), str(_pg(e, "ssao_enabled")), str(_pg(e, "ao_light_affect")),
						str(e.ambient_light_source), str(_pg(e, "background_mode")), str(_pg(e, "sdfgi_enabled")),
						str(_pg(e, "fog_enabled"))])
					print("[DUMP] gv=%s hdr=%s msaa=%s ssaa=%s scale=%s win=%s" % [
						str(ctrl.game_view.size), str(ctrl.game_view.use_hdr_2d), str(ctrl.game_view.msaa_3d),
						str(ctrl.game_view.screen_space_aa), str(_pg(ctrl.game_view,"scaling_3d_scale")), str(DisplayServer.window_get_size())])
			"floor_mat_unlit":
				for mt in _floor_materials():
					if mt is ShaderMaterial:
						mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			"floor_override_unlit":
				var mat = StandardMaterial3D.new()
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				for m in _floor_mmis():
					m.material_override = mat
			"floor_no_mm":
				for m in _floor_mmis():
					m.visible = false
			"floor_no_shadow":
				for m in _floor_mmis():
					m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			"floor_relief0":
				for mt in _floor_materials():
					if mt is ShaderMaterial:
						mt.set_shader_parameter("relief_mode", 0)
			"floor_no_wet":
				for mt in _floor_materials():
					if mt is ShaderMaterial:
						mt.set_shader_parameter("wet_floor", false)
			"hide_floor":
				sb.floor_root.visible = false
			"hide_scenery":
				sb.town_scenery_root.visible = false
			"scenery_half":
				var ch = sb.town_scenery_root.get_children()
				for i in range(ch.size()):
					if i % 2 == 0:
						ch[i].visible = false
			"hide_props":
				sb.props_root.visible = false
			"hide_mon":
				sb.monsters_root.visible = false
			"hide_all":
				for r in [sb.props_root, sb.monsters_root, sb.town_scenery_root, sb.floor_root,
						sb.corpses_root, sb.items_root, sb.missiles_root, sb.effects_root, sb.stairs_root]:
					if r:
						r.visible = false
			"sb_invisible":
				sb.visible = false
			"no_lights":
				for l in _lights():
					l.visible = false
			"few_lights":
				var ls = _lights()
				for i in range(3, ls.size()):
					ls[i].visible = false
			"no_shadows":
				for l in _lights():
					l.shadow_enabled = false
			"no_glow":
				sb.world_env.environment.glow_enabled = false
			"no_vfog":
				sb.world_env.environment.volumetric_fog_enabled = false
			"no_ssao":
				if sb.world_env.environment.has_method("set_ssao_enabled"):
					sb.world_env.environment.set_ssao_enabled(false)
			"no_fxaa":
				ctrl.game_view.screen_space_aa = 0
			"no_hdr":
				ctrl.game_view.use_hdr_2d = false
			"no_ui":
				for c in root.get_children():
					if c != ctrl:
						c.visible = false
			"no_composite_draw":
				ctrl.composite_rect.visible = false

func _force_visible() -> void:
	if sb == null or not is_instance_valid(sb):
		return
	var stack = [sb]
	while stack:
		var n = stack.pop_back()
		var vis = n.get("visible")
		if vis != null:
			n.visible = true
		for c in n.get_children():
			stack.append(c)

func _render_stats() -> String:
	if sb == null or not is_instance_valid(sb):
		return "?"
	var root = sb.town_scenery_root.get_parent()
	var stack = [root]
	var spr = 0
	var mm = 0
	var li = 0
	while stack:
		var n = stack.pop_back()
		var vis = n.get("visible")
		if vis != null and not vis:
			continue
		if n.get_class() == "ObjectSprite3D" or n.get_class() == "Sprite3D":
			spr += 1
		elif n is MultiMeshInstance3D and n.multimesh:
			mm += n.multimesh.visible_instance_count
		elif n is Light3D:
			li += 1
		for c in n.get_children():
			stack.append(c)
	var b = ctrl.diablo_bridge
	var dead = b.is_player_dead() if b.has_method("is_player_dead") else "?"
	var hp = b.get_player_hp() if b.has_method("get_player_hp") else "?"
	var pos = b.get_player_continuous_pos() if b.has_method("get_player_continuous_pos") else null
	return "spr=%d mm=%d li=%d hp=%s pos=%s mode=%s engmode=%s gvdraw=%s" % [
		int(spr), int(mm), int(li), str(hp),
		("%.0f,%.0f" % [pos["x"], pos["y"]]) if pos is Dictionary and pos.has("x") else "?",
		str(ctrl.current_display_mode),
		str(b.get_d1de_display_mode()) if b.has_method("get_d1de_display_mode") else "?",
		str(ctrl.composite_rect.visible)]

func _apply_cfg(cfg: String) -> void:
	var saved = OS.get_environment("TOGGLES")
	OS.set_environment("TOGGLES", cfg if cfg != "" else " ")
	_apply_toggles(false)
	OS.set_environment("TOGGLES", saved)

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
	if pin_cam and sb.camera:
		sb.camera.global_transform = cam_xform
	if show_all:
		_force_visible()
	phase_time += delta
	win_frames += 1
	times.append(Time.get_ticks_msec())
	if times.size() > 600:
		times.pop_front()
	var limit = WARM if phase == "warm" else MEASURE
	if phase_time >= limit:
		var fps = win_frames / phase_time
		var ms = []
		for i in range(1, times.size()):
			ms.append(float(times[i] - times[i - 1]))
		ms.sort()
		var p50 = ms[int(ms.size() * 0.5)] if ms.size() > 0 else 0.0
		var gpu = -1
		var f = FileAccess.open("/sys/class/drm/card0/device/gpu_busy_percent", FileAccess.READ)
		if f != null:
			gpu = int(f.get_line())
		last_stats = _render_stats()
		if phase == "warm":
			phase = "measure"
			if OS.get_environment("FREEZE") == "1":
				ctrl.diablo_bridge.set_process(false)
				print("[FREEZE] bridge process off")
			elif OS.get_environment("FREEZE") == "2":
				ctrl.set_process(false)
				sb.set_process(false)
				print("[FREEZE] visual sync off (static built scene)")
			elif OS.get_environment("FREEZE") == "3":
				ctrl.set_process(false)
				sb.set_process(false)
				if sb.camera:
					cam_xform = sb.camera.global_transform
					pin_cam = true
				print("[FREEZE3] sync off, camera pinned")
			cur_cfg = 0
			_apply_cfg(cfg_list[0])
			print("[WARM-DONE] fps=%.1f pending=%d %s" % [fps, HdSpriteProvider.pending_count(), last_stats])
		else:
			win_idx += 1
			print("[M] cfg=%s w=%d fps=%.2f p50=%.2fms gpu=%d%% %s" % [cfg_list[cur_cfg], win_idx, fps, p50, gpu, last_stats])
			if win_idx >= block_wins:
				blocks_done += 1
				if blocks_done >= total_blocks:
					return true
				win_idx = 0
				cur_cfg = (cur_cfg + 1) % cfg_list.size()
				_apply_cfg(cfg_list[cur_cfg])
				print("[SWITCH] cfg=%s" % cfg_list[cur_cfg])
		phase_time = 0.0
		win_frames = 0
		times.clear()
	return false
