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
		"class": bridge.get_player_class(),
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
	if auth.can_promote("inventory_item_use"):
		print("[SOAK] already promotable, nothing to do")
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
	for i in range(8):
		if int(auth.checks["inventory_item_use"]) >= target:
			break
		if use_and_verify(bridge, auth, i):
			run_checks += 1

	if not auth.save_state(STATE_PATH):
		print("[SOAK] WARN: could not write ", STATE_PATH)
	print("[SOAK] run (save %d): +%d checks -> total %d, distinct %d, mismatches %d" % [
		save_num, run_checks, int(auth.checks["inventory_item_use"]), auth.distinct("inventory_item_use"),
		int(auth.mismatches["inventory_item_use"])])
	print("[SOAK REPORT] ", auth.report())
	bridge.quit_engine()
	quit(0 if int(auth.mismatches["inventory_item_use"]) == 0 else 1)
