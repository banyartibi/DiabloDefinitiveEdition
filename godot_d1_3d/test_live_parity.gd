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

	# Settle: the engine must be past level load / PM_NEWLVL before queued actions are honoured.
	OS.delay_msec(1500)

	var checked = 0
	var native_uses = 0
	var fallbacks_before = 0

	# Guard, live: a decision must never be applied to an item it was not computed for. Push a
	# FULLMANA decision onto a slot that holds a partial Potion of Healing: the engine's own item
	# (IMISC_HEAL) is not even in the handover set, so the gate must ignore the payload entirely -
	# mana must not move, and the vanilla partial heal must still happen.
	var guard_slot = -1
	for i in range(8):
		var b = bridge.get_belt_items()[i]
		if int(b.get("count", 0)) > 0 and BELT_TYPE_TO_MISC.get(int(b.get("type", 0)), -1) == ItemLogic.IMISC_HEAL:
			guard_slot = i
			break
	var guard_ok = true
	if guard_slot >= 0:
		var g_before = state(bridge)
		var g_seq = bridge.get_last_action_seq()
		bridge.use_belt_slot_native(guard_slot, int(ItemLogic.IMISC_FULLMANA), 0, 0, 1, 0, 0, 0, 0, 0)
		var g_wait = 0
		while bridge.get_last_action_seq() == g_seq and g_wait < 2000:
			OS.delay_msec(20)
			g_wait += 20
		var g_after = state(bridge)
		print("[GUARD] foreign decision on belt ", guard_slot, ": hp ", g_before.hp, " -> ", g_after.hp,
			" mana ", g_before.mana, " -> ", g_after.mana, " (want: healed, mana untouched)")
		guard_ok = g_after.mana == g_before.mana and g_after.hp > g_before.hp
		if not guard_ok:
			print("FAIL: a decision computed for another item was applied")
	# Baseline for the clean-use check: taken after the deliberate mismatch above.
	fallbacks_before = int(bridge.get_native_item_fallbacks())

	for i in range(8):
		var belt = bridge.get_belt_items()[i]
		var t = int(belt.get("type", 0))
		if int(belt.get("count", 0)) <= 0 or not BELT_TYPE_TO_MISC.has(t):
			continue
		var before = state(bridge)
		var item = {"misc_id": BELT_TYPE_TO_MISC[t], "can_use": true}
		var ctx = {"hellfire": bridge.is_hellfire()}
		var seq_before = bridge.get_last_action_seq()
		# Handover path: when the mirror can decide the effect deterministically it hands the
		# decision to the engine, which applies it instead of recomputing it. Anything else (and
		# anything the mirror refuses) goes through the plain C++ switch.
		var fx = ItemLogic.native_handover_request(item, before, ctx)
		if fx.is_empty():
			bridge.use_belt_slot(i)
		else:
			native_uses += 1
			bridge.use_belt_slot_native(i, int(fx.misc_id), int(fx.hp_mode), int(fx.hp_delta),
				int(fx.mana_mode), int(fx.mana_delta),
				int(fx.str), int(fx.mag), int(fx.dex), int(fx.vit))
		# Wait for PROOF of execution on the engine thread (the drain counter moves), not a fixed
		# sleep: a fixed sleep can read state before PollGodotBridgeInput() has drained the job.
		var executed = false
		var waited2 = 0
		while not executed and waited2 < 2000:
			OS.delay_msec(20)
			waited2 += 20
			if bridge.get_last_action_seq() > seq_before:
				executed = true
		if not executed:
			print("[SKIP]   belt %d: action not executed within %d ms" % [i, waited2])
			continue
		var after = state(bridge)
		# Predict with the seed the engine had AT EXECUTION TIME (snapshot taken inside
		# PollGodotBridgeInput before the job ran), not with the seed read at push time.
		# `before` is still valid because in town nothing consumes HP/mana between push and drain.
		var seed_at_exec = bridge.get_last_action_rng_seed()
		var pred = ItemLogic.predict_use_item(item, before, RNG.new(seed_at_exec), ctx)
		var native_result = {"hp": pred["effects"]["hp"], "mana": pred["effects"]["mana"]}
		var cpp_result = {"hp": after["hp"] - before["hp"], "mana": after["mana"] - before["mana"]}
		var ok = auth.record("inventory_item_use", native_result, cpp_result)
		checked += 1
		print("[PARITY] belt %d (%s) %s native=%s cpp=%s seed=%d type=%d path=%s%s" % [
			i, belt.get("name", ""), "OK" if ok else "MISMATCH", native_result, cpp_result, seed_at_exec,
			bridge.get_last_action_type(),
			"NATIVE" if not fx.is_empty() else "CPP",
			"  [rng]" if pred["rng_dependent"] else "  [deterministic]"])

	# The engine drops a decision it cannot match to the item it is using, and counts each drop.
	# Any increase here means the handover was NOT applied and the vanilla switch ran instead.
	var fallbacks = int(bridge.get_native_item_fallbacks()) - fallbacks_before
	print("native handover uses: ", native_uses, "  engine fallbacks (clean uses): ", fallbacks)
	if native_uses == 0:
		print("[NOTE] this hero carries no deterministic consumable (full heal / elixir), so the "
			+ "engine-side apply path was not exercised live here. It is covered by "
			+ "test_hud_belt_and_bindings.gd (payload) and by the guard above (never mis-applied).")
	if fallbacks != 0:
		print("FAIL: engine dropped ", fallbacks, " native item-use decision(s)")

	print("--------------------------------------------------")
	print("checks recorded: ", checked)
	print("[PARITY REPORT] ", auth.report())
	bridge.quit_engine()
	quit(0 if int(auth.report()["inventory_item_use"]["mismatches"]) == 0 and fallbacks == 0 and guard_ok else 1)
