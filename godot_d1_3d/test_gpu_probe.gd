extends SceneTree
# GPU-cost probe: does SubViewport readback force a GPU sync, and what does the
# sandbox actually cost at various sizes / with post-processing?

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

var bridge
var sandbox
var viewport: SubViewport
var cam: Camera3D

func _init():
	bridge = ClassDB.instantiate("DiabloBridge")
	bridge.init_engine(MPQ_DIR)
	for attempt in range(3):
		if bridge.is_game_running():
			break
		bridge.menu_select_single_player()
		OS.delay_msec(1500)
		bridge.launch_hero_game(2, 0, true)
		for i in range(40):
			OS.delay_msec(100)
			if bridge.is_game_running():
				break
	print("[GPU] game_running=%s level=%d" % [bridge.is_game_running(), bridge.get_current_level()])

	var scene = load("res://scenes/sandbox/native_3d_sandbox.tscn")
	sandbox = scene.instantiate()
	sandbox.diablo_bridge = bridge
	root.add_child(sandbox)
	sandbox._ready()
	sandbox.activate()

	viewport = SubViewport.new()
	viewport.size = Vector2i(2560, 1440)
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var env = WorldEnvironment.new()
	var env_res = load("res://scenes/main_3d.tscn").instantiate()
	for c in env_res.get_children():
		if c is WorldEnvironment:
			env.environment = c.environment
			break
	env_res.queue_free()
	viewport.add_child(env)
	cam = Camera3D.new()
	var p = bridge.get_player_continuous_pos()
	cam.position = sandbox.tile_to_world_3d(float(p.get("x", 0)), float(p.get("y", 0))) + Vector3(0, -14, 7.8)
	viewport.add_child(cam)
	root.remove_child(sandbox)
	viewport.add_child(sandbox)

	for i in range(120):
		await process_frame
	await _m("2560x1440 no readback", false)
	await _m("2560x1440 readback", true)
	viewport.size = Vector2i(1280, 720)
	await _m("1280x720 readback", true)
	viewport.size = Vector2i(2560, 1440)
	env.environment.volumetric_fog_enabled = false
	await _m("2560x1440 readback, no volumetric fog", true)
	env.environment.glow_enabled = false
	await _m("2560x1440 readback, no fog/glow", true)
	env.environment.volumetric_fog_enabled = true
	env.environment.glow_enabled = true
	for l in _collect_shadowed_lights():
		l.shadow_enabled = false
	await _m("2560x1440 readback, no light shadows", true)
	viewport.msaa_3d = Viewport.MSAA_4X
	await _m("2560x1440 readback, MSAA4x", true)
	print("[GPU] done")
	quit()

func _collect_shadowed_lights() -> Array:
	var out: Array = []
	var stack = [sandbox]
	while stack.size() > 0:
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
			if (c is OmniLight3D or c is SpotLight3D) and c.visible and c.shadow_enabled:
				out.append(c)
	return out

func _m(label: String, readback: bool) -> void:
	for i in range(30):
		await process_frame
	var t0 = Time.get_ticks_msec()
	var n = 0
	while Time.get_ticks_msec() - t0 < 3000:
		await process_frame
		n += 1
		if readback:
			viewport.get_texture().get_image()
	var el = Time.get_ticks_msec() - t0
	print("  %-42s %6.1f fps  (%.2f ms/frame)" % [label, n * 1000.0 / el, float(el) / n])
