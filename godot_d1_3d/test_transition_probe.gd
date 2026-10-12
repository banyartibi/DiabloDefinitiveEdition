extends SceneTree

## Probe: can a soak drive a real level transition?
## Prints the town trigger tiles, clicks the stairs, and reports whether the engine entered the
## transition window (g_D1LevelTransitioning) and what level it landed on.

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

func _wait(bridge, cond: String, max_ms: int) -> int:
	var waited := 0
	while waited < max_ms:
		if cond == "running" and bridge.is_game_running():
			break
		if cond == "loaded" and not bridge.is_level_loading():
			break
		OS.delay_msec(20)
		waited += 20
	return waited


func _wait_menu(bridge, mode: int, max_ms: int) -> int:
	var waited := 0
	while waited < max_ms and int(bridge.get_menu_mode()) != mode:
		OS.delay_msec(20)
		waited += 20
	return waited


func _init() -> void:
	if not ClassDB.class_exists("DiabloBridge"):
		print("FAIL: DiabloBridge not found")
		quit(1)
		return
	var bridge = ClassDB.instantiate("DiabloBridge")
	root.add_child(bridge)
	bridge.init_engine(MPQ_DIR)
	var waited = 0
	while not bridge.is_engine_ready() and waited < 200:
		OS.delay_msec(20)
		waited += 1
	bridge.menu_select_single_player()
	_wait_menu(bridge, 2, 2000)
	var save := int(String(OS.get_environment("PROBE_SAVE")) if String(OS.get_environment("PROBE_SAVE")) != "" else "0")
	bridge.launch_hero_game(save, 0, true)
	_wait(bridge, "running", 4000)
	_wait(bridge, "loaded", 1000)
	OS.delay_msec(400)

	var tile = bridge.get_player_tile_pos()
	print("[PROBE] level=", bridge.get_current_level(), " player tile=", tile)
	var trigs = bridge.get_level_triggers()
	print("[PROBE] triggers=", trigs)
	if trigs.is_empty():
		print("[PROBE] no triggers, aborting")
		bridge.quit_engine()
		quit(1)
		return

	var target = trigs[0]
	var gx := int(target["x"])
	var gy := int(target["y"])
	# Walk in short hops: a single click to a far tile lands off the visible screen and the engine
	# drops it. When a hop fails (wall/building) try detour directions instead of hammering the
	# same blocked tile.
	var last := Vector2i(-999, -999)
	var stuck := 0
	var tried := {}
	for step in range(300):
		var pt = bridge.get_player_tile_pos()
		var px := int(pt.x)
		var py := int(pt.y)
		if abs(px - gx) <= 1 and abs(py - gy) <= 1:
			break
		var dx := gx - px
		var dy := gy - py
		var dist : int = maxi(1, int(sqrt(float(dx * dx + dy * dy))))
		if Vector2i(px, py) == last:
			stuck += 1
		else:
			stuck = 0
			tried.clear()
		last = Vector2i(px, py)
		if stuck > 12:
			print("[PROBE] giving up at ", px, ",", py)
			break
		var hop : int = mini(dist, 4)
		var cands: Array = []
		cands.append(Vector2i(px + int(round(float(dx) * float(hop) / float(dist))),
			py + int(round(float(dy) * float(hop) / float(dist)))))
		if stuck >= 1:
			# detours: perpendicular, then the two side diagonals
			var detours: Array = [Vector2i(-dy, dx), Vector2i(dy, -dx), Vector2i(dx, -dy), Vector2i(-dx, dy)]
			for d in detours:
				var dl : float = sqrt(float(d.x * d.x + d.y * d.y))
				if dl < 1.0:
					continue
				var h2 : int = mini(dist, 5)
				cands.append(Vector2i(px + int(round(float(d.x) * float(h2) / dl)),
					py + int(round(float(d.y) * float(h2) / dl))))
		var chosen = null
		for c in cands:
			if not tried.has(c):
				chosen = c
				break
		if chosen == null:
			chosen = cands[0]  # retry the direct hop; a single click is sometimes simply dropped
		tried[chosen] = true
		bridge.send_click_to_tile(int(chosen.x), int(chosen.y), 1)
		OS.delay_msec(150)
		if step < 12 or step % 20 == 0:
			print("[PROBE] step ", step, " player=", px, ",", py, " -> ", chosen, " goal=", gx, ",", gy, " stuck=", stuck)
	var final_tile = bridge.get_player_tile_pos()
	print("[PROBE] after walk: player=", final_tile, " goal=", gx, ",", gy, " level=", bridge.get_current_level())
	# Stand on the trigger and click it directly (interact).
	bridge.send_click_to_tile(gx, gy, 1)
	# The clickable stairs piece is not the trigger tile itself: ForceTownTrig/ForceL*Trig match a
	# stairs *piece* under the cursor and then snap cursPosition to the trigger. So probe the
	# neighbours too.
	var lvl0 = bridge.get_current_level()
	for roundi in range(3):
		for ox in range(-1, 2):
			for oy in range(-1, 2):
				if ox == 0 and oy == 0:
					continue
				bridge.send_click_to_tile(gx + ox, gy + oy, 1)
				for w in range(30):
					if bridge.get_current_level() != lvl0:
						break
					OS.delay_msec(20)
			if bridge.get_current_level() != lvl0:
				break
		if bridge.get_current_level() != lvl0:
			print("[PROBE] transition fired from neighbour click round ", roundi)
			break

	var saw_transitioning := 0
	var saw_newlvl_pmode := 0
	var saw_unsafe := 0
	var safe_samples := 0
	var lvl = bridge.get_current_level()
	for i in range(400):
		var g = bridge.get_read_gate_state()
		if bool(g.get("transitioning", false)):
			saw_transitioning += 1
		if int(g.get("pmode", -1)) == 10:
			saw_newlvl_pmode += 1
		if bool(g.get("safe", false)):
			safe_samples += 1
		else:
			saw_unsafe += 1
		var cur = bridge.get_current_level()
		if cur != lvl:
			print("[PROBE] level changed %d -> %d at sample %d" % [lvl, cur, i])
			lvl = cur
		OS.delay_msec(20)
	print("[PROBE] gate samples: safe=%d unsafe=%d transitioning=%d pmode_newlvl=%d final level=%d" % [
		safe_samples, saw_unsafe, saw_transitioning, saw_newlvl_pmode, bridge.get_current_level()])
	bridge.quit_engine()
	quit(0)
