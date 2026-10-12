extends SceneTree

## Proves the AUTH_NATIVE handover is real: the HUD's behaviour must depend on the authority mode,
## and the optimistic value must come from the native mirror, not from the engine.

const InventoryScript = preload("res://scenes/hud/d1de_inventory.gd")
const HudScript = preload("res://scenes/hud/d1de_hud.gd")
const AuthorityScript = preload("res://scripts/logic/d1_logic_authority.gd")

var failures := 0


func check(name: String, got, want) -> void:
	if got == want:
		print("PASS  %s" % name)
	else:
		failures += 1
		print("FAIL  %s  got=%s want=%s" % [name, got, want])


class MockBridge extends RefCounted:
	var seq := 7

	func get_player_hp() -> int: return 50
	func get_player_max_hp() -> int: return 100
	func get_player_mana() -> int: return 20
	func get_player_max_mana() -> int: return 60
	func get_player_hp_raw() -> int: return 50 * 64
	func get_player_max_hp_raw() -> int: return 100 * 64
	func get_player_mana_raw() -> int: return 20 * 64
	func get_player_max_mana_raw() -> int: return 60 * 64
	func get_player_item_flags() -> int: return 0
	func get_player_class() -> int: return 1
	func get_last_action_seq() -> int: return seq
	func get_last_action_rng_seed() -> int: return 12345
	func get_rng_seed() -> int: return 12345
	func is_hellfire() -> bool: return false


class MockHud extends Node:
	var calls := []

	func _ready() -> void:
		add_to_group("d1de_hud")

	func apply_optimistic_item_delta(hp: int, mana: int, seq: int) -> void:
		calls.append([hp, mana, seq])


func _init() -> void:
	var bridge = MockBridge.new()

	# --- 1. the HUD applies the offset only while the engine action is still queued ---
	var hud = HudScript.new()
	hud.diablo_bridge = bridge
	hud.display_hp = 50.0
	hud.apply_optimistic_item_delta(30, 0, 7)
	hud.update_health_and_mana(1.0)
	check("HUD shows predicted value while action queued", hud.display_hp, 80.0)
	bridge.seq = 8  # engine drained the action; its own value now contains the change
	hud.update_health_and_mana(1.0)
	check("HUD drops offset once engine caught up", hud.display_hp, 50.0)
	hud.apply_optimistic_item_delta(0, 0, 8)
	check("zero delta pushes nothing", hud._optimistic.is_empty(), true)

	# --- 2. the inventory only pushes when the subsystem is AUTH_NATIVE ---
	var probe = MockHud.new()
	var inv = InventoryScript.new()
	var auth = AuthorityScript.new()
	inv.diablo_bridge = bridge
	inv.hud = probe
	inv.logic_authority = auth
	var potion = {"misc_id": 2, "can_use": true}  # Potion of Full Healing

	auth.set_authority("inventory_item_use", auth.AUTH_SHADOW)
	inv._shadow_use(potion)
	check("shadow mode does not drive the HUD", probe.calls.size(), 0)

	auth.set_authority("inventory_item_use", auth.AUTH_NATIVE)
	inv._pending_prediction = {}
	inv._shadow_use(potion)
	check("native mode drives the HUD", probe.calls.size(), 1)
	if probe.calls.size() == 1:
		check("predicted hp delta", int(probe.calls[0][0]) > 0, true)
		check("offset tagged with the push sequence", int(probe.calls[0][2]), bridge.seq)

	if failures > 0:
		print("--------------------------------------------------")
		print("%d FAILURES" % failures)
		quit(1)
	else:
		print("ALL NATIVE CONSUMER TESTS PASS.")
		quit(0)
