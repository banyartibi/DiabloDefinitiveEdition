extends SceneTree

## Parity soak run: one hero load per process.
##
## Loading restores HP/mana and the belt from disk, so every run starts from the same known
## state. Without that the hero would be full after the first potion and every later check
## would be a trivial 0 == 0 that proves nothing. Counters accumulate in the persisted state
## across runs, so the soak reaches the promotion threshold over many runs.
##
## Run once:  tools/godot4/godot4 --headless --path godot_d1_3d --script res://test_parity_soak.gd
## Loop until promoted: ./scripts/soak_parity.sh

var ItemLogic = preload("res://scripts/logic/d1_item_logic.gd")
var RNG = preload("res://scripts/logic/d1_rng.gd")
var Authority = preload("res://scripts/logic/d1_logic_authority.gd")
var TransitionLogic = preload("res://scripts/logic/d1_level_transition_logic.gd")

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"
const SAVE_NUM = 4
const STATE_PATH = "res://logs/parity_state.json"
const TARGET_CHECKS = 200

var save_num := SAVE_NUM

# beltTypes[] is a UI category, not item_misc_id (render_bridge.cpp:214).
var BELT_TYPE_TO_MISC := {
	1: ItemLogic.IMISC_HEAL,
	2: ItemLogic.IMISC_FULLHEAL,
	3: ItemLogic.IMISC_MANA,
	4: ItemLogic.IMISC_FULLMANA,
	5: ItemLogic.IMISC_REJUV,
	6: ItemLogic.IMISC_FULLREJUV,
}


func state(bridge) -> Dictionary:
	return {
		"hp": bridge.get_player_hp(),
		"max_hp": bridge.get_player_max_hp(),
		"mana": bridge.get_player_mana(),
		"max_mana": bridge.get_player_max_mana(),
		"hp_raw": bridge.get_player_hp_raw(),
		"max_hp_raw": bridge.get_player_max_hp_raw(),
		"mana_raw": bridge.get_player_mana_raw(),
		"max_mana_raw": bridge.get_player_max_mana_raw(),
		"class": bridge.get_player_class(),
		"item_flags": bridge.get_player_item_flags(),
	}


func _wait(bridge, cond: String, max_ms: int) -> int:
	var waited := 0
	while waited < max_ms:
		if cond == "running" and bridge.is_game_running():
			break
		if cond == "stopped" and not bridge.is_game_running():
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


## Draw-for-draw comparison of the GDScript LCG against the engine's own generator. This is the
## one subsystem whose parity cannot be inferred from gameplay effects: a mirror can produce the
## right HP delta by luck while its stream has already diverged.
## Sample the engine's read-gate and compare it against the mirror's IsBridgeSafeToRead().
## Sampled during the load window (where the gate is false) and during steady play (where it is
## true), because the whole point of the contract is the transition window.
var gate_stats := {"samples": 0, "bad": 0, "transitioning": 0}


func _sample_gate(bridge, auth, mirror, tag: String) -> void:
	var g = bridge.get_read_gate_state()
	gate_stats["samples"] = int(gate_stats["samples"]) + 1
	if bool(g.get("transitioning", false)):
		gate_stats["transitioning"] = int(gate_stats["transitioning"]) + 1
		if mirror.state != mirror.STATE_TRANSITIONING:
			mirror.queue_transition()
			mirror.begin()
	elif mirror.state == mirror.STATE_TRANSITIONING:
		mirror.complete(int(bridge.get_current_level()))
	var native_verdict : bool = mirror.is_safe_to_read(g)
	var cpp_verdict : bool = bool(g.get("safe", false))
	var sig := "gate|%d|%d|%d|%d|%d|%d" % [
		int(bool(g.get("game_running", false))), int(bool(g.get("transitioning", false))),
		int(bool(g.get("faded_in", false))), int(bool(g.get("player_ready", false))),
		int(g.get("pmode", -1)), int(bool(g.get("lvl_changing", false)))]
	if not auth.record("level_transition", {"safe": native_verdict}, {"safe": cpp_verdict}, sig):
		gate_stats["bad"] = int(gate_stats["bad"]) + 1
		print("[SOAK] GATE MISMATCH %s %s native=%s cpp=%s" % [tag, sig, native_verdict, cpp_verdict])
	# The mirror tracks the level through its own state machine. The comparison is only meaningful
	# while reads are approved: during the load window the engine has already switched currlevel but
	# the native layer must not adopt the new level until the gate is safe again, otherwise it would
	# route caches for a level that is still being built.
	if cpp_verdict:
		# First sync: a mirror created mid-game has no level yet. It adopts the engine's level only
		# once reads are approved - before that there is nothing to compare, and recording -1 against
		# the engine would be a comparison the native layer never actually made.
		if mirror.current_level < 0:
			mirror.current_level = bridge.get_current_level()
		else:
			var eng_lvl : int = bridge.get_current_level()
			auth.record("level_transition", {"level": mirror.current_level}, {"level": eng_lvl}, "lvl|%d" % eng_lvl)


func _soak_level_gate(bridge, auth, samples: int, tag: String) -> void:
	var mirror = TransitionLogic.new()
	var before := int(gate_stats["samples"])
	for i in range(samples):
		_sample_gate(bridge, auth, mirror, tag)
		OS.delay_msec(20)
	print("[SOAK] level gate (%s): %d samples, %d mismatched" % [
		tag, int(gate_stats["samples"]) - before, int(gate_stats["bad"])])


## Drive a real level change. Sampling alone never reaches the transition window - the soak has to
## walk the hero onto a level trigger. The clickable stairs piece is not the trigger tile itself:
## ForceTownTrig/ForceL*Trig match a stairs *piece* under the cursor and snap cursPosition to the
## trigger, so the neighbours of the trigger tile are probed as well.
func _drive_transition(bridge, auth) -> bool:
	var trigs = bridge.get_level_triggers()
	if trigs.is_empty():
		print("[SOAK] no level trigger here, cannot drive a transition")
		return false
	var pt = bridge.get_player_tile_pos()
	var best = null
	var best_d := 1 << 30
	for t in trigs:
		var dx : int = int(t["x"]) - int(pt.x)
		var dy : int = int(t["y"]) - int(pt.y)
		var d : int = dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = t
	var gx := int(best["x"])
	var gy := int(best["y"])
	var lvl0 : int = bridge.get_current_level()
	print("[SOAK] driving transition: player=(%d,%d) trigger=(%d,%d) msg=%d level=%d" % [
		int(pt.x), int(pt.y), gx, gy, int(best["msg"]), lvl0])

	var mirror = TransitionLogic.new()
	mirror.current_level = lvl0
	mirror.state = mirror.STATE_LOADED

	# Walk: short hops (a far click lands off screen and the engine drops it), with detours when a
	# wall or building blocks the direct line.
	var last := Vector2i(-999, -999)
	var stuck := 0
	var tried := {}
	for step in range(300):
		for slice in range(6):
			_sample_gate(bridge, auth, mirror, "walk")
			OS.delay_msec(20)
		if bridge.get_current_level() != lvl0:
			break
		var cur = bridge.get_player_tile_pos()
		var px := int(cur.x)
		var py := int(cur.y)
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
			print("[SOAK] walk blocked at (%d,%d)" % [px, py])
			break
		var hop : int = mini(dist, 4)
		var cands: Array = [Vector2i(px + int(round(float(dx) * float(hop) / float(dist))),
			py + int(round(float(dy) * float(hop) / float(dist))))]
		if stuck >= 1:
			for d in [Vector2i(-dy, dx), Vector2i(dy, -dx), Vector2i(dx, -dy), Vector2i(-dx, dy)]:
				var dl : float = sqrt(float(d.x * d.x + d.y * d.y))
				if dl < 1.0:
					continue
				cands.append(Vector2i(px + int(round(float(d.x) * 4.0 / dl)),
					py + int(round(float(d.y) * 4.0 / dl))))
		var chosen = cands[0]
		for c in cands:
			if not tried.has(c):
				chosen = c
				break
		tried[chosen] = true
		bridge.send_click_to_tile(int(chosen.x), int(chosen.y), 1)

	# Stand next to the stairs and probe the trigger tile plus its neighbours.
	for ox in range(-1, 2):
		for oy in range(-1, 2):
			if bridge.get_current_level() != lvl0:
				break
			bridge.send_click_to_tile(gx + ox, gy + oy, 1)
			for slice in range(40):
				_sample_gate(bridge, auth, mirror, "stairs")
				OS.delay_msec(20)
			if bridge.get_current_level() != lvl0:
				print("[SOAK] transition fired from click (%d,%d)" % [gx + ox, gy + oy])
				break
		if bridge.get_current_level() != lvl0:
			break

	# Keep sampling while the engine loads the new level: this is the window the contract guards.
	for slice in range(120):
		_sample_gate(bridge, auth, mirror, "load")
		OS.delay_msec(20)
	var lvl1 : int = bridge.get_current_level()
	print("[SOAK] transition drive: level %d -> %d, gate samples %d, transitioning %d, mirror level %d" % [
		lvl0, lvl1, int(gate_stats["samples"]), int(gate_stats["transitioning"]), mirror.current_level])
	return lvl1 != lvl0


func _soak_rng(bridge, auth) -> void:
	var rng = RNG.new(bridge.get_rng_seed())
	var moduli := [1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377, 610, 987, 1597]
	var bad := 0
	for v in moduli:
		var cpp_val : int = bridge.engine_generate_rnd(v)
		var native_val := rng.generate_rnd(v)
		# The engine keeps the LCG state in a uint32 but hands it back through an int32, so the same
		# state arrives as a negative number. Compare the bit pattern, not the sign.
		var cpp_seed : int = bridge.get_rng_seed() & 0xFFFFFFFF
		auth.record("rng",
			{"value": native_val, "seed": rng.seed & 0xFFFFFFFF},
			{"value": cpp_val, "seed": cpp_seed},
			"rnd|%d" % v)
		if cpp_val != native_val:
			bad += 1
			print("[SOAK] RNG MISMATCH mod=%d native=%d cpp=%d" % [v, native_val, cpp_val])
	print("[SOAK] rng: %d draws, %d mismatched, seed native=%d cpp=%d" % [
		moduli.size(), bad, rng.seed, bridge.get_rng_seed()])


## The backpack path goes through a different engine entry point than the belt: UseInventorySlot ->
## UseInvItem(INVITEM_INV_FIRST + i) instead of the belt slot code. Same item, different caller, so
## it has to be measured separately - a mirror can be right on one path and wrong on the other.
## Potions only: scrolls leave the engine in a targeting cursor and the effect is not immediate.
func use_inventory_and_verify(bridge, auth) -> bool:
	var consumables := [ItemLogic.IMISC_HEAL, ItemLogic.IMISC_FULLHEAL, ItemLogic.IMISC_MANA,
		ItemLogic.IMISC_FULLMANA, ItemLogic.IMISC_REJUV, ItemLogic.IMISC_FULLREJUV]
	var ctx = {"hellfire": bridge.is_hellfire()}
	var before = state(bridge)
	# Pick the first consumable that can actually change this hero, not just the first consumable.
	# A hero at full HP but empty mana must still be exercised: taking the first potion and giving
	# up when it predicts zero silently dropped every mana case (and vice versa).
	var chosen = null
	for it in bridge.get_player_backpack():
		if not bool(it.get("can_use", false)) or not consumables.has(int(it.get("misc_id", 0))) \
				or int(it.get("inv_list_index", -1)) < 0:
			continue
		var cand = {"misc_id": int(it.get("misc_id", 0)), "can_use": true}
		var pred = ItemLogic.predict_use_item(cand, before, RNG.new(bridge.get_rng_seed()), ctx)
		if int(pred["effects"]["hp"]) == 0 and int(pred["effects"]["mana"]) == 0:
			continue  # no-op for this state, try the next consumable
		chosen = it
		break
	if chosen == null:
		return false  # every consumable is a no-op for the current hero state
	var inv_idx := int(chosen.get("inv_list_index", -1))
	var item = {"misc_id": int(chosen.get("misc_id", 0)), "can_use": true}

	var seq_before = bridge.get_last_action_seq()
	bridge.use_inventory_slot(2, inv_idx)
	var spin := 0
	while spin < 2000 and bridge.get_last_action_seq() <= seq_before:
		OS.delay_msec(20)
		spin += 20
	if bridge.get_last_action_seq() <= seq_before:
		print("[SOAK]   inventory %d: action not executed within 2000 ms" % inv_idx)
		return false

	var after = state(bridge)
	var seed_at_exec = bridge.get_last_action_rng_seed()
	var pred = ItemLogic.predict_use_item(item, before, RNG.new(seed_at_exec), ctx)
	var native_result = {"hp": int(pred["effects"]["hp"]), "mana": int(pred["effects"]["mana"])}
	var cpp_result = {"hp": int(after["hp"]) - int(before["hp"]), "mana": int(after["mana"]) - int(before["mana"])}
	var sig = "invu|%d|%d|%d|%d" % [seed_at_exec, native_result.hp, native_result.mana, int(item.misc_id)]
	var is_new = not auth.seen["inventory_item_use"].has(sig)
	var ok = auth.record("inventory_item_use", native_result, cpp_result, sig)
	print("[PARITY] save %d backpack %d (%s) %s native=%s cpp=%s seed=%d%s%s" % [
		save_num, inv_idx, chosen.get("name", ""), "OK" if ok else "MISMATCH", native_result, cpp_result, seed_at_exec,
		"  [rng]" if pred["rng_dependent"] else "  [deterministic]",
		"  [new]" if is_new else "  [repeat]"])
	if not ok:
		print("[PARITY]   before=%s after=%s" % [before, after])
	return true


func use_and_verify(bridge, auth, belt_idx: int) -> bool:
	var belt = bridge.get_belt_items()[belt_idx]
	var t = int(belt.get("type", 0))
	if int(belt.get("count", 0)) <= 0 or not BELT_TYPE_TO_MISC.has(t):
		return false
	var item = {"misc_id": int(BELT_TYPE_TO_MISC[t]), "can_use": true}
	var ctx = {"hellfire": bridge.is_hellfire()}
	var before = state(bridge)
	var pred_before = ItemLogic.predict_use_item(item, before, RNG.new(bridge.get_rng_seed()), ctx)
	if not pred_before["ok"]:
		return false
	# Nothing predicted -> nothing to verify. Recording 0 == 0 would inflate the count with
	# checks that prove nothing (hero already full).
	if int(pred_before["effects"]["hp"]) == 0 and int(pred_before["effects"]["mana"]) == 0:
		return false

	var seq_before = bridge.get_last_action_seq()
	bridge.use_belt_slot(belt_idx)
	var spin := 0
	while spin < 2000 and bridge.get_last_action_seq() <= seq_before:
		OS.delay_msec(20)
		spin += 20
	if bridge.get_last_action_seq() <= seq_before:
		print("[SOAK]   belt %d: action not executed within 2000 ms" % belt_idx)
		return false

	var after = state(bridge)
	# Predict with the seed the engine had AT EXECUTION TIME (snapshot inside
	# PollGodotBridgeInput, before the job ran). Reading it at push time is not deterministic.
	var seed_at_exec = bridge.get_last_action_rng_seed()
	var pred = ItemLogic.predict_use_item(item, before, RNG.new(seed_at_exec), ctx)
	var native_result = {"hp": int(pred["effects"]["hp"]), "mana": int(pred["effects"]["mana"])}
	var cpp_result = {"hp": int(after["hp"]) - int(before["hp"]), "mana": int(after["mana"]) - int(before["mana"])}
	var sig = "iuh|%d|%d|%d|%d" % [seed_at_exec, native_result.hp, native_result.mana, int(item.misc_id)]
	var is_new = not auth.seen["inventory_item_use"].has(sig)
	var ok = auth.record("inventory_item_use", native_result, cpp_result, sig)
	print("[PARITY] save %d belt %d (%s) %s native=%s cpp=%s seed=%d%s%s" % [
		save_num, belt_idx, belt.get("name", ""), "OK" if ok else "MISMATCH", native_result, cpp_result, seed_at_exec,
		"  [rng]" if pred["rng_dependent"] else "  [deterministic]",
		"  [new]" if is_new else "  [repeat]"])
	if not ok:
		# The effect is a delta; a delta mismatch is undiagnosable without the endpoints. A gain
		# clamped by max_mana looks like a wrong draw unless the raw states are visible.
		print("[PARITY]   before=%s after=%s" % [before, after])
	return true


func _init() -> void:
	var auth = Authority.new()
	var target := TARGET_CHECKS
	var env_target := String(OS.get_environment("SOAK_TARGET"))
	if env_target != "":
		target = int(env_target)
	var env_save := String(OS.get_environment("SOAK_SAVE"))
	if env_save != "":
		save_num = int(env_save)
	if auth.load_state(STATE_PATH):
		print("[SOAK] restored persisted counters: ", auth.report())
	# Counters are sticky: one mismatch poisons promotion forever. After fixing a mirror bug the
	# evidence has to be re-measured, otherwise the numbers describe code that no longer exists.
	var env_reset := String(OS.get_environment("SOAK_RESET"))
	if env_reset != "":
		auth.reset_counters("" if env_reset == "all" else env_reset)
		print("[SOAK] counters reset for: ", env_reset)
	# Handover is a pure state operation and needs no engine: SOAK_PROMOTE=1 (or a comma separated
	# list) promotes only subsystems whose evidence passes the gate. promote() refuses otherwise,
	# so this cannot hand over a subsystem that has not been proven.
	var env_promote := String(OS.get_environment("SOAK_PROMOTE"))
	if env_promote != "":
		var targets: Array = ["inventory_item_use", "rng", "level_transition"] if env_promote == "all" \
			else env_promote.split(",")
		for s in targets:
			if auth.promote(s):
				print("[SOAK] PROMOTED %s -> AUTH_NATIVE" % s)
			else:
				print("[SOAK] NOT promotable: %s (%s)" % [s, auth.report()[s]])
		auth.save_state(STATE_PATH)
		quit(0)
		return
	# SOAK_TRANSITION=1 keeps driving level changes even after the subsystem is promotable, so the
	# evidence keeps broadening (different levels, both directions) instead of freezing at the first
	# passing sample. SOAK_ITEMS=1 does the same for the belt/backpack item paths.
	var force_tr := String(OS.get_environment("SOAK_TRANSITION")) != ""
	var force_items := String(OS.get_environment("SOAK_ITEMS")) != ""
	var need_items := not auth.can_promote("inventory_item_use") or force_items
	var need_rng := not auth.can_promote("rng")
	var need_level := not auth.can_promote("level_transition") or force_tr
	if not need_items and not need_rng and not need_level:
		print("[SOAK] all subsystems already promotable, nothing to do")
		quit(0)
		return

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
	if not bridge.is_engine_ready():
		print("FAIL: engine not ready")
		quit(1)
		return

	# The menu selection is processed on the engine thread; do not launch before the hero list
	# is actually active (menu_mode 2), otherwise the pending result is consumed by the main
	# menu and the hero is never loaded.
	bridge.menu_select_single_player()
	_wait_menu(bridge, 2, 2000)
	bridge.launch_hero_game(save_num, 0, true)
	# Sample the gate while the level is still loading: this is the window the contract exists for.
	_soak_level_gate(bridge, auth, 12, "load")
	waited = _wait(bridge, "running", 4000)
	if not bridge.is_game_running():
		print("[SOAK] hero not loaded (menu_mode=%d), aborting" % bridge.get_menu_mode())
		quit(1)
		return
	_wait(bridge, "loaded", 1000)
	OS.delay_msec(400)

	print("[SOAK] save %d at load: seed=%d hp=%d/%d mana=%d/%d class=%d" % [
		save_num, bridge.get_rng_seed(), bridge.get_player_hp(), bridge.get_player_max_hp(),
		bridge.get_player_mana(), bridge.get_player_max_mana(), bridge.get_player_class()])

	var belt = bridge.get_belt_items()
	var names := []
	for i in range(belt.size()):
		names.append("%d:%s" % [i, belt[i].get("name", "")])
	print("[SOAK] save %d belt: %s" % [save_num, " ".join(names)])

	var run_checks := 0
	# A forced re-run must not be gated by the already-reached target, otherwise the loop breaks
	# before trying anything and the new path (backpack) is never exercised.
	var budget : int = target if not force_items else int(auth.checks["inventory_item_use"]) + 20
	if need_items:
		# Backpack first: the belt loop calls replenish_belt(), which moves backpack consumables into
		# the belt, so running it first would empty the very path this loop is meant to cover. Eight
		# attempts, not three: the soak fixture carries a full backpack of potions and each use is a
		# distinct (state, seed) case, so the old cap of three threw away most of the reachable space.
		for i in range(8):
			if int(auth.checks["inventory_item_use"]) >= budget:
				break
			if not use_inventory_and_verify(bridge, auth):
				break
		for i in range(8):
			if int(auth.checks["inventory_item_use"]) >= budget:
				break
			if use_and_verify(bridge, auth, i):
				run_checks += 1

	if need_rng:
		_soak_rng(bridge, auth)
	# Last, because it changes the level and would invalidate the item/rng context of this save.
	if need_level:
		_drive_transition(bridge, auth)
	_soak_level_gate(bridge, auth, 8, "steady")
	if not auth.save_state(STATE_PATH):
		print("[SOAK] WARN: could not write ", STATE_PATH)
	print("[SOAK] run (save %d): +%d checks -> total %d, distinct %d, mismatches %d" % [
		save_num, run_checks, int(auth.checks["inventory_item_use"]), auth.distinct("inventory_item_use"),
		int(auth.mismatches["inventory_item_use"])])
	print("[SOAK REPORT] ", auth.report())
	var bad := 0
	for s in ["inventory_item_use", "rng", "level_transition"]:
		bad += int(auth.mismatches[s])
	bridge.quit_engine()
	quit(0 if bad == 0 else 1)
