extends SceneTree

## Task 2 Step 5 harness: golden fixtures for the native logic layer plus
## shadow-mode parity against the C++ engine when the engine is running.
## Run: tools/godot4/godot4 --headless --path godot_d1_3d --script res://test_logic_authority.gd

var RNG := preload("res://scripts/logic/d1_rng.gd")
var ItemLogic := preload("res://scripts/logic/d1_item_logic.gd")
var Transition := preload("res://scripts/logic/d1_level_transition_logic.gd")
var Authority := preload("res://scripts/logic/d1_logic_authority.gd")

var failures := 0


func check(label: String, got, want) -> void:
	if got == want:
		print("PASS  ", label)
	else:
		failures += 1
		print("FAIL  ", label, "  got=", got, " want=", want)


func _init() -> void:
	print("==================================================")
	print(" Testing Native Logic Authority (Task 2 Step 5) ")
	print("==================================================")

	# --- 1. RNG parity with the vanilla LCG (Source/engine/random.cpp) ---
	var rng = RNG.new(0x12345678)
	var golden_rng := [1788971303, 1443805422, 1058065735, 1627643468, 1237307973]
	var got := []
	for i in range(5):
		var s = rng.generate_seed()
		got.append(abs(s - 0x100000000 if s >= 0x80000000 else s))
	check("RNG LCG stream", got, golden_rng)

	# --- 2. Item logic golden fixtures ---
	var warrior := {"hp": 50, "max_hp": 100, "mana": 40, "max_mana": 80,
		"str": 30, "mag": 20, "dex": 20, "vit": 30, "class": ItemLogic.CLASS_WARRIOR, "spell_levels": {}}
	var rogue := {"hp": 40, "max_hp": 80, "mana": 40, "max_mana": 80,
		"str": 20, "mag": 20, "dex": 30, "vit": 20, "class": ItemLogic.CLASS_ROGUE, "spell_levels": {}}

	var heal := {"misc_id": ItemLogic.IMISC_HEAL, "can_use": true, "spell_from": -1}
	var r = RNG.new(0x12345678)
	var p1 = ItemLogic.predict_use_item(heal, warrior, r)
	check("HEAL warrior partial life delta", p1["effects"]["hp"], 50)
	check("HEAL rng_dependent", p1["rng_dependent"], true)

	var mana_item := {"misc_id": ItemLogic.IMISC_MANA, "can_use": true}
	var p1b = ItemLogic.predict_use_item(mana_item, rogue, RNG.new(0x12345678))
	check("MANA rogue partial mana delta", p1b["effects"]["mana"], 40)

	var fullheal := {"misc_id": ItemLogic.IMISC_FULLHEAL, "can_use": true}
	var p2 = ItemLogic.predict_use_item(fullheal, warrior, RNG.new(1))
	check("FULLHEAL deterministic", p2["rng_dependent"], false)
	check("FULLHEAL delta", p2["effects"]["hp"], 50)

	var elixvit := {"misc_id": ItemLogic.IMISC_ELIXVIT, "can_use": true}
	var p3 = ItemLogic.predict_use_item(elixvit, warrior, RNG.new(1), {"hellfire": true})
	check("ELIXVIT hellfire grants full life", p3["effects"]["hp"], 50)
	check("ELIXVIT vit", p3["effects"]["vit"], 1)

	var specelix := {"misc_id": ItemLogic.IMISC_SPECELIX, "can_use": true}
	var p4 = ItemLogic.predict_use_item(specelix, warrior, RNG.new(1), {"mushroom_quest_done": false})
	check("SPECELIX blocked before quest (isUsable gate)", p4["ok"], false)
	var p5 = ItemLogic.predict_use_item(specelix, warrior, RNG.new(1), {"mushroom_quest_done": true})
	check("SPECELIX all stats +3", [p5["effects"]["str"], p5["effects"]["mag"], p5["effects"]["dex"], p5["effects"]["vit"]], [3, 3, 3, 3])
	check("SPECELIX not belt-usable", ItemLogic.belt_usable(specelix, {"mushroom_quest_done": true}), false)

	var book := {"misc_id": ItemLogic.IMISC_BOOK, "can_use": true, "spell_id": 0, "spell_from": 0}
	var p6 = ItemLogic.predict_use_item(book, rogue, RNG.new(1), {"spell_mana_cost": 15})
	check("BOOK spell level up", p6["effects"]["spell_level"], 1)
	check("BOOK mana gain (spell cost)", p6["effects"]["mana"], 15)

	var oil := {"misc_id": ItemLogic.IMISC_OILACC, "can_use": true}
	var p7 = ItemLogic.predict_use_item(oil, warrior, RNG.new(1), {"sbookflag": true, "invflag": false})
	check("OIL cursor", p7["cursor"], ItemLogic.CURSOR_OIL)
	check("OIL closes spellbook", p7["flags"]["sbookflag"], false)
	check("OIL opens inventory", p7["flags"]["invflag"], true)

	var rune := {"misc_id": ItemLogic.IMISC_RUNEF, "can_use": true, "spell_from": 0}
	var p8 = ItemLogic.predict_use_item(rune, warrior, RNG.new(1))
	check("RUNEF prepares RuneOfFire", p8["flags"]["prepare_spell"], "RuneOfFire")
	check("RUNEF cursor", p8["cursor"], ItemLogic.CURSOR_TELEPORT)

	# --- 3. Level transition state machine ---
	var tr = Transition.new()
	check("queue town level", tr.queue_transition(0), true)
	var begin_res = tr.begin()
	check("transition blocks reads", tr.reads_blocked, true)
	check("caches invalidated", begin_res["invalidate"], tr.invalidated_caches())
	check("complete clears block", tr.complete()["ok"], true)
	check("safe read after load", tr.is_safe_to_read(0, false, true, true), true)
	tr.queue_transition(1)
	tr.begin()
	check("unsafe during PM_NEWLVL", tr.is_safe_to_read(Transition.PM_NEWLVL, false, true, true), false)
	tr.complete()
	var themes := {0: "town", 1: "cathedral", 5: "catacombs", 10: "caves", 16: "hell"}
	check("town never resolves to cathedral (Rule #1)", tr.pbr_folder_for_level(0, themes), "res://assets/dungeon_pbr_town_4x")
	check("cathedral level routing", tr.pbr_folder_for_level(1, themes), "res://assets/dungeon_pbr_cathedral_4x")
	check("height gate accepts (Rule #3)", tr.height_gate(128, 128), true)
	check("height gate rejects drift", tr.height_gate(136, 128), false)
	check("special CEL gate cathedral only (Rule #2)", tr.special_cel_gate(3, 1), true)
	check("special CEL gate rejects town", tr.special_cel_gate(3, 0), false)

	# --- 4. Authority registry ---
	var auth = Authority.new()
	check("shadow mode default", auth.get_authority("inventory_item_use"), Authority.AUTH_SHADOW)
	auth.record("inventory_item_use", p2, {"effects": {"hp": 3200}, "actions": ["restore_full_life"]})
	check("parity recorded", auth.report()["inventory_item_use"]["checks"], 1)
	auth.record("level_transition", tr.snapshot()["state"], Transition.STATE_LOADED)
	check("transition parity", auth.report()["level_transition"]["mismatches"], 0)

	print("--------------------------------------------------")
	if failures:
		print("FAILURES: ", failures)
		quit(1)
	print("ALL LOGIC AUTHORITY TESTS PASS.")
	quit(0)
