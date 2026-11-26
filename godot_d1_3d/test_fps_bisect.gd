extends SceneTree
# Bug 3 bisect on the real display: launch hero, force Native 3D, then toggle
# contributors and print fps for each configuration.

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

func _initialize():
	print("[FPSTEST] initialize")
	ctrl = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(ctrl)
	states = [
		["baseline native3d 2560x1440 vsync off", func(): _vsync(false)],
		["sandbox fog OFF", func(): _sb_fog(false)],
		["sandbox fog OFF + glow OFF", func(): _sb_glow(false)],
		["sandbox fog/glow OFF + hdr off", func(): _sb_hdr(false)],
		["restore (control)", func(): _restore_all()],
	]

var sb_env = null
func _sb_env():
	if sb_env == null:
		var sb = ctrl.sandbox_instance
		if is_instance_valid(sb):
			sb_env = sb.get_node_or_null("WorldEnvironment")
	return sb_env.environment if sb_env else null

func _sb_fog(on: bool) -> void:
	var e = _sb_env()
	if e: e.volumetric_fog_enabled = on

func _sb_glow(on: bool) -> void:
	var e = _sb_env()
	if e: e.glow_enabled = on

func _sb_hdr(on: bool) -> void:
	if sub_viewport: sub_viewport.use_hdr_2d = on

func _vsync(on: bool) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if on else DisplayServer.VSYNC_DISABLED)

func _lights(on: bool) -> void:
	for n in _all_light3d():
		n.visible = on

func _shadows(on: bool) -> void:
	for n in _all_light3d():
		n.shadow_enabled = on

func _all_light3d() -> Array:
	var out = []
	var stack = [ctrl]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			if c is Light3D:
				out.append(c)
			stack.push_back(c)
	return out

func _set_visible(root_name: String, vis: bool) -> void:
	var sb = ctrl.sandbox_instance
	if not is_instance_valid(sb):
		return
	for c in sb.get_children():
		if c.name == root_name:
			c.visible = vis

func _hide_sprites(on: bool) -> void:
	for r in ["PropsRoot", "ItemsRoot", "MonstersRoot", "MissilesRoot", "CorpsesRoot", "EffectsRoot", "TownSceneryRoot", "StairsRoot"]:
		_set_visible(r, not on)

func _hide_all_but_tiles(on: bool) -> void:
	_hide_sprites(on)
	for r in ["FloorMultiMesh", "WallMultiMesh", "WallNSMultiMesh", "WallEWMultiMesh", "PillarMultiMesh", "FloorMMIRoot"]:
		_set_visible(r, not on)

func _restore_all() -> void:
	_sb_fog(true)
	_sb_glow(true)
	_sb_hdr(true)
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
	if bridge.is_game_running():
		ctrl.switch_display_mode(2)
		# Report the sandbox subtree so the toggles above target real names.
		var sb = ctrl.sandbox_instance
		if is_instance_valid(sb):
			for c in sb.get_children():
				print("[TREE] ", c.name, " children=", c.get_child_count())
			var e = _sb_env()
			print("[SBENV] ", e, " fog=", e.volumetric_fog_enabled if e else "?", " glow=", e.glow_enabled if e else "?",
				" fog_density=", e.volumetric_fog_density if e else "?", " light_energy=", e.volumetric_fog_light_energy if e else "?")
		print("[LIGHTS] ", _all_light3d().size())

func _process(delta: float) -> bool:
	if ctrl == null or not is_instance_valid(ctrl):
		return false
	if not started:
		if ctrl.diablo_bridge == null:
			return false
		started = true
		env = ctrl.world_env.environment if ctrl.world_env else null
		sub_viewport = ctrl.game_view
		_launch()
		_next_state()
		return false

	if settle > 0.0:
		settle -= delta
		return false

	measure += delta
	frames_in_state += 1
	if measure >= 5.0:
		var se = _sb_env()
		print("[FPSTEST] %s -> %.1f fps | level=%s objs=%s sbfog=%s sbglow=%s hdr=%s" % [
			states[state_idx][0], frames_in_state / measure,
			bridge.get_current_level() if bridge != null else "?",
			bridge.get_active_objects().size() if bridge != null else "?",
			se.volumetric_fog_enabled if se else "?",
			se.glow_enabled if se else "?",
			sub_viewport.use_hdr_2d if sub_viewport else "?",
		])
		_next_state()
	return false
