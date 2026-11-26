extends SceneTree
var ctrl = null
var bridge = null
var sb = null
var armed = false
var seen = {}
var changes := 0
var prev = null
var n := 0
func _initialize():
	ctrl = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(ctrl)
func _process(delta: float) -> bool:
	if ctrl == null or not is_instance_valid(ctrl):
		return false
	if not armed:
		if ctrl.diablo_bridge == null:
			return false
		armed = true
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
		return false
	n += 1
	if n > 240:
		var fps = 0.0
		print("[GAMMA] frames=%d distinct=%d changes=%d prev=%s clear_events_per_sec=%.1f" % [n, seen.size(), changes, prev, changes / 8.0])
		quit()
		return false
	var g = bridge.get_gamma() if bridge.has_method("get_gamma") else null
	seen[str(g)] = true
	if prev != null and g != prev:
		changes += 1
	prev = g
	if n % 60 == 0:
		print("[GAMMA] n=%d g=%s changes=%d distinct=%d anim_cache=%d" % [n, str(g), changes, seen.size(), sb.monster_anim_cache.size()])
	return false
