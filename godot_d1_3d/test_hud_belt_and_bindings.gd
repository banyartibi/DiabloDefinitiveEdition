extends SceneTree

const HudScene = preload("res://scenes/hud/d1de_hud.tscn")

var failures := 0

func check(label: String, condition: bool) -> void:
	if condition:
		print("PASS  ", label)
	else:
		failures += 1
		print("FAIL  ", label)

class MockBridge extends RefCounted:
	var belt_used := []
	var belt_clicked := []
	var hp := 50
	var max_hp := 100
	var mana := 25
	var max_mana := 50
	var seq := 10

	func get_belt_items() -> Array:
		var arr = []
		for i in range(8):
			arr.append({
				"slot_id": i,
				"name": "Potion of Healing" if i < 4 else "Potion of Mana",
				"type": 1 if i < 4 else 3,
				"count": 1,
				"misc_id": 3 if i < 4 else 6, # IMISC_HEAL / IMISC_MANA
				"can_use": true
			})
		for slot in belt_overrides:
			arr[slot] = belt_overrides[slot]
		return arr

	# Native item-use handover (Task 2 Step 5).
	var belt_overrides := {}
	var native_calls := []
	var fallbacks := 0

	func set_belt_item(idx: int, item: Dictionary) -> void:
		belt_overrides[idx] = item

	func get_native_item_fallbacks() -> int: return fallbacks

	func use_belt_slot_native(idx: int, misc_id: int, hp_mode: int, hp_delta: int,
	    mana_mode: int, mana_delta: int, str_d: int, mag_d: int, dex_d: int, vit_d: int) -> void:
		native_calls.append({
			"idx": idx, "misc_id": misc_id, "hp_mode": hp_mode, "hp_delta": hp_delta,
			"mana_mode": mana_mode, "mana_delta": mana_delta,
			"str": str_d, "mag": mag_d, "dex": dex_d, "vit": vit_d,
		})
		seq += 1

	func get_player_hp() -> int: return hp
	func get_player_max_hp() -> int: return max_hp
	func get_player_mana() -> int: return mana
	func get_player_max_mana() -> int: return max_mana
	func get_player_hp_raw() -> int: return hp * 64
	func get_player_max_hp_raw() -> int: return max_hp * 64
	func get_player_mana_raw() -> int: return mana * 64
	func get_player_max_mana_raw() -> int: return max_mana * 64
	func get_player_item_flags() -> int: return 0
	func get_player_class() -> int: return 0
	func get_last_action_seq() -> int: return seq
	func get_last_action_rng_seed() -> int: return 12345
	func get_rng_seed() -> int: return 12345
	func is_hellfire() -> bool: return false
	func get_belt_item_texture(_idx: int): return null

	func use_belt_slot(idx: int) -> void:
		belt_used.append(idx)
		seq += 1

	func click_belt_slot(idx: int) -> void:
		belt_clicked.append(idx)

func _init() -> void:
	print("==================================================")
	print(" Testing HUD Belt & Keybindings (Task 4) ")
	print("==================================================")

	var hud = HudScene.instantiate()
	root.add_child(hud)
	hud._ready()

	var bridge = MockBridge.new()
	hud.set_bridge(bridge)
	hud.get_node("Root").visible = true

	# 1. Verify belt_slots array populated
	check("8 belt slots registered", hud.belt_slots.size() == 8)

	# 2. Test F1..F8 key events
	for i in range(8):
		var ev = InputEventKey.new()
		ev.pressed = true
		ev.keycode = KEY_F1 + i
		hud._unhandled_input(ev)
		check("F%d triggers belt slot %d" % [i + 1, i], bridge.belt_used.has(i))

	# 3. Test LMB when inventory is closed (drinks potion)
	bridge.belt_used.clear()
	bridge.belt_clicked.clear()
	var click_lmb = InputEventMouseButton.new()
	click_lmb.button_index = MOUSE_BUTTON_LEFT
	click_lmb.pressed = true
	hud._on_hud_belt_slot_gui_input(2, click_lmb)
	check("LMB when inventory closed drinks potion", bridge.belt_used.has(2) and bridge.belt_clicked.is_empty())

	# 4. Test LMB when inventory is open (drags / clicks belt slot)
	bridge.belt_used.clear()
	bridge.belt_clicked.clear()
	hud.set_meta("test_inventory_open", true)
	hud._on_hud_belt_slot_gui_input(2, click_lmb)
	check("LMB when inventory open clicks belt slot", bridge.belt_clicked.has(2) and bridge.belt_used.is_empty())

	# 5. Test RMB always drinks potion
	bridge.belt_used.clear()
	var click_rmb = InputEventMouseButton.new()
	click_rmb.button_index = MOUSE_BUTTON_RIGHT
	click_rmb.pressed = true
	hud._on_hud_belt_slot_gui_input(5, click_rmb)
	check("RMB drinks potion", bridge.belt_used.has(5))

	# 6. Native item-use handover. Under AUTH_NATIVE a deterministic consumable is decided by the
	# mirror and handed to the engine; anything that draws from the LCG still goes the old way.
	var Authority := preload("res://scripts/logic/d1_logic_authority.gd")
	var auth = hud._auth()
	var auth_before: int = auth.get_authority("inventory_item_use")
	auth.set_authority("inventory_item_use", Authority.AUTH_NATIVE)

	bridge.belt_used.clear()
	bridge.native_calls.clear()
	hud._use_hud_belt_slot(0) # IMISC_HEAL: partial restore, rng-dependent
	check("partial heal still decided by C++", bridge.belt_used.has(0) and bridge.native_calls.is_empty())

	bridge.belt_used.clear()
	bridge.set_belt_item(1, {"slot_id": 1, "name": "Potion of Full Healing", "type": 1, "count": 1,
		"misc_id": 2, "can_use": true}) # IMISC_FULLHEAL
	hud._use_hud_belt_slot(1)
	check("full heal takes the native path", bridge.native_calls.size() == 1 and bridge.belt_used.is_empty())
	if bridge.native_calls.size() == 1:
		var call: Dictionary = bridge.native_calls[0]
		check("native payload carries the misc id", call["misc_id"] == 2)
		check("native payload: hp full restore", call["hp_mode"] == 1 and call["hp_delta"] == 0)
		check("native payload: mana untouched", call["mana_mode"] == 0)
		check("native payload: slot index", call["idx"] == 1)

	# Watchdog: an engine-side fallback (a decision it could not match to the item in use) demotes
	# the subsystem back to SHADOW instead of running an unverified decision again.
	bridge.fallbacks = 1
	hud._check_native_handover() # first read: establishes the baseline (engine reports 0)
	bridge.fallbacks = 2
	hud._check_native_handover()
	check("fallback demotes to SHADOW", auth.get_authority("inventory_item_use") == Authority.AUTH_SHADOW)
	bridge.belt_used.clear()
	bridge.native_calls.clear()
	hud._use_hud_belt_slot(1)
	check("after demotion C++ decides again", bridge.belt_used.has(1) and bridge.native_calls.is_empty())
	auth.set_authority("inventory_item_use", auth_before)

	hud.queue_free()

	if failures > 0:
		print("--------------------------------------------------")
		print("%d FAILURES in HUD Belt & Keybindings" % failures)
		quit(1)
	else:
		print("ALL HUD BELT & KEYBINDINGS TESTS PASS.")
		quit(0)
