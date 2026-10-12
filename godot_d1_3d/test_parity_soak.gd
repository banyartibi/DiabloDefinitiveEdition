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
func _soak_level_gate(bridge, auth, samples: int, tag: String) -> void:
	var mirror = TransitionLogic.new()
	var bad := 0
	for i in range(samples):
		var g = bridge.get_read_gate_state()
		var native_verdict : bool = mirror.is_safe_to_read(g)
		var cpp_verdict : bool = bool(g.get("safe", false))
		var sig := "gate|%d|%d|%d|%d|%d|%d" % [
			int(bool(g.get("game_running", false))), int(bool(g.get("transitioning", false))),
			int(bool(g.get("faded_in", false))), int(bool(g.get("player_ready", false))),
			int(g.get("pmode", -1)), int(bool(g.get("lvl_changing", false)))]
		if not auth.record("level_transition", {"safe": native_verdict}, {"safe": cpp_verdict}, sig):
			bad += 1
			print("[SOAK] GATE MISMATCH %s %s native=%s cpp=%s" % [tag, sig, native_verdict, cpp_verdict])
		OS.delay_msec(20)
	print("[SOAK] level gate (%s): %d samples, %d mismatched" % [tag, samples, bad])


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
	var need_items := not auth.can_promote("inventory_item_use")
	var need_rng := not auth.can_promote("rng")
	if not need_items and not need_rng:
		print("[SOAK] inventory_item_use and rng already promotable, nothing to do")
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
	if need_items:
		for i in range(8):
			if int(auth.checks["inventory_item_use"]) >= target:
				break
			if use_and_verify(bridge, auth, i):
				run_checks += 1

	if need_rng:
		_soak_rng(bridge, auth)
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
