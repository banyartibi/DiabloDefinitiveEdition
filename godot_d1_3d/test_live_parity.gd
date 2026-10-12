extends SceneTree

## Live parity harness: drives the real C++ engine through the bridge and compares
## the native D1ItemLogic prediction with the actual state delta.
## Run: tools/godot4/godot4 --headless --path godot_d1_3d --script res://test_live_parity.gd

var ItemLogic = preload("res://scripts/logic/d1_item_logic.gd")
var RNG = preload("res://scripts/logic/d1_rng.gd")
var Authority = preload("res://scripts/logic/d1_logic_authority.gd")

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"
const SAVE_NUM = 4

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


func _init() -> void:
	print("==================================================")
	print(" Live parity: native D1ItemLogic vs C++ engine ")
	print("==================================================")
	if not ClassDB.class_exists("DiabloBridge"):
		print("FAIL: DiabloBridge not found")
		quit(1)
		return

	var bridge = ClassDB.instantiate("DiabloBridge")
	root.add_child(bridge)
	bridge.init_engine(MPQ_DIR)

	var auth = Authority.new()
	var waited = 0
	while not bridge.is_engine_ready() and waited < 200:
		OS.delay_msec(20)
		waited += 1
	if not bridge.is_engine_ready():
		print("FAIL: engine not ready")
		quit(1)
		return

	bridge.menu_select_single_player()
	OS.delay_msec(500)
	print("menu_mode after single player: ", bridge.get_menu_mode())
	print("hero list: ", bridge.get_hero_list())
	bridge.launch_hero_game(SAVE_NUM, 0, true)

	waited = 0
	while not bridge.is_game_running() and waited < 800:
		OS.delay_msec(20)
		waited += 1
	if not bridge.is_game_running():
		print("FAIL: game not running (hero %d not loaded), menu_mode=%d, waited=%d ms" % [SAVE_NUM, bridge.get_menu_mode(), waited * 20])
		quit(1)
		return

	print("Hero loaded: class=%d hp=%d/%d mana=%d/%d level=%d" % [
		bridge.get_player_class(), bridge.get_player_hp(), bridge.get_player_max_hp(),
		bridge.get_player_mana(), bridge.get_player_max_mana(), bridge.get_current_level()])

	var checked = 0
	for i in range(8):
		var belt = bridge.get_belt_items()[i]
		var t = int(belt.get("type", 0))
		if int(belt.get("count", 0)) <= 0 or not BELT_TYPE_TO_MISC.has(t):
			continue
		var before = state(bridge)
		var item = {"misc_id": BELT_TYPE_TO_MISC[t], "can_use": true}
		var ctx = {"hellfire": bridge.is_hellfire()}
		var pred = ItemLogic.predict_use_item(item, before, RNG.new(bridge.get_rng_seed()), ctx)
		bridge.use_belt_slot(i)
		OS.delay_msec(400)  # let the engine thread execute the queued action
		var after = state(bridge)
		var native_result = {"hp": pred["effects"]["hp"], "mana": pred["effects"]["mana"]}
		var cpp_result = {"hp": after["hp"] - before["hp"], "mana": after["mana"] - before["mana"]}
		if pred["rng_dependent"]:
			# Cannot be recorded as parity: the engine may consume RNG between the
			# prediction and the execution of the queued action. Informational only.
			print("[INFO]   belt %d (%s) rng_dependent native=%s cpp=%s%s" % [
				i, belt.get("name", ""), native_result, cpp_result,
				"  MATCH" if native_result == cpp_result else "  (stream diverged)"])
			continue
		var ok = auth.record("inventory_item_use", native_result, cpp_result)
		checked += 1
		print("[PARITY] belt %d (%s) %s native=%s cpp=%s" % [
			i, belt.get("name", ""), "OK" if ok else "MISMATCH", native_result, cpp_result])

	print("--------------------------------------------------")
	print("checks recorded: ", checked)
	print("[PARITY REPORT] ", auth.report())
	bridge.quit_engine()
	quit(0 if int(auth.report()["inventory_item_use"]["mismatches"]) == 0 else 1)
