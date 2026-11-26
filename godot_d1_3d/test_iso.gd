extends SceneTree
# TEMP: isolate the ~32 ms/frame GPU cost in Mode 2 HD by toggling engine-side
# properties on the live sandbox (no code changes).

var ctrl = null
var sb = null
var armed = false
var phase = "base"
var win_time = 0.0
var win_frames = 0
var phases = ["base", "small_window", "pause_sb_only", "resume_small"]
var pidx = 0

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
	print("[ISO] running=%s level=%d mode=%d monsters=%d props=%d" % [
		bridge.is_game_running(), bridge.get_current_level(), ctrl.current_display_mode,
		sb.monster_instances.size(), sb.prop_instances.size()])

func _sprites(node) -> Array:
	var out = []
	var stack = [node]
	while stack.size() > 0:
		var n = stack.pop_back()
		for c in n.get_children():
			if c is Sprite3D:
				out.append(c)
			stack.append(c)
	return out

func _is_descendant(n: Node, ancestor: Node) -> bool:
	var p = n
	while p != null:
		if p == ancestor:
			return true
		p = p.get_parent()
	return false

func _all_nodes(from: Node) -> Array:
	var out = []
	var stack = [from]
	while stack.size() > 0:
		var n = stack.pop_back()
		for c in n.get_children():
			out.append(c)
			stack.append(c)
	return out

func _all_entity_nodes() -> Array:
	var out = []
	for key in ["monster_instances", "prop_instances", "item_instances", "corpse_instances", "missile_instances"]:
		var d = sb.get(key)
		if d == null:
			continue
		for n in d.values():
			if is_instance_valid(n):
				out.append(n)
	return out

func _apply() -> void:
	match phase:
		"pause_sb_only":
			sb.set_process(false)
		"small_window":
			DisplayServer.window_set_size(Vector2i(640, 480))
		"resume_small":
			DisplayServer.window_set_size(Vector2i(1280, 720))
		"inventory":
			var tex_bytes = 0
			var tex_count = 0
			var seen = {}
			var inst = 0
			var stack = [sb]
			while stack.size() > 0:
				var n = stack.pop_back()
				for c in n.get_children():
					stack.append(c)
					if c is VisualInstance3D:
						inst += 1
					var t = null
					if c is Sprite3D:
						t = c.texture
					elif c is MeshInstance3D:
						var m = c.mesh
						if m != null and m.get_surface_count() > 0:
							var mat = m.surface_get_material(0)
							if mat != null and mat.albedo_texture != null:
								t = mat.albedo_texture
					if t != null and not seen.has(t):
						seen[t] = true
						tex_count += 1
						tex_bytes += t.get_width() * t.get_height() * 4
			print("[ISO] visual_instances=%d unique_textures=%d approx_tex_MB=%.1f" % [inst, tex_count, float(tex_bytes) / 1048576.0])
			var big = 0
			for t in seen.keys():
				if t.get_width() >= 200:
					big += 1
			print("[ISO] big_textures=%d" % big)
		"hide_scenery":
			if sb.get("scenery_root") != null:
				sb.scenery_root.visible = false
		"hide_everything":
			for n in _all_entity_nodes():
				n.visible = false
			if sb.get("player_entity") != null:
				sb.player_entity.visible = false
		"shared_tex":
			# every entity sprite uses ONE texture -> tests per-unique-texture cost
			var shared = null
			for n in _all_entity_nodes():
				for s in _sprites(n):
					if s.texture != null and s.texture.get_width() >= 200:
						shared = s.texture
						break
				if shared != null:
					break
			if shared == null:
				print("[ISO] no HD texture found to share")
			else:
				for n in _all_entity_nodes():
					for s in _sprites(n):
						if s.texture != null and s.texture.get_width() >= 200:
							s.texture = shared
		"hide_half":
			var i = 0
			for n in _all_entity_nodes():
				i += 1
				if i % 2 == 0:
					n.visible = false
		"show_all":
			for n in _all_entity_nodes():
				n.visible = true
			if sb.get("scenery_root") != null:
				sb.scenery_root.visible = true
			if sb.get("player_entity") != null:
				sb.player_entity.visible = true
		"no_all_shadow":
			for key in ["prop_instances", "item_instances", "corpse_instances", "missile_instances"]:
				var d = sb.get(key)
				if d == null:
					continue
				for n in d.values():
					if is_instance_valid(n):
						for s in _sprites(n):
							s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"no_shadow_map":
			for n in _all_lights():
				n.shadow_enabled = false
		"restore":
			for key in ["monster_instances"]:
				var d = sb.get(key)
				if d == null:
					continue
				for n in d.values():
					if is_instance_valid(n):
						for s in _sprites(n):
							s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func _all_lights() -> Array:
	var out = []
	var stack = [sb]
	while stack.size() > 0:
		var n = stack.pop_back()
		for c in n.get_children():
			if c is Light3D:
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
	if pidx >= phases.size():
		quit()
		return false
	if win_time == 0.0:
		phase = phases[pidx]
		_apply()
		print("[ISO] phase=%s" % phase)
	win_time += delta
	win_frames += 1
	if win_time >= 6.0:
		print("[ISO] %s fps=%.1f process=%.1fms draw=%.1fms render=%.1fms objs=%d prims=%d verts=%d" % [
			phase, win_frames / win_time,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			0.0, 0, 0, 0])
		pidx += 1
		win_time = 0.0
		win_frames = 0
	return false
