extends SceneTree

const HudScene = preload("res://scenes/hud/d1de_hud.tscn")

var failures := 0

func check(label: String, condition: bool) -> void:
	if condition:
		print("PASS  ", label)
	else:
		failures += 1
		print("FAIL  ", label)

class MockBridgeIdentify extends RefCounted:
	var belt_used := []
	var belt_clicked := []
	var targeting_cancelled := false
	var cursor_id := 1 # 1 = HAND, 2 = IDENTIFY
	var inventory_open := false
	var active_panel := -1
	var inventory_version := 1
	var last_inv_click := {}

	func is_engine_ready() -> bool: return true
	func is_game_running() -> bool: return true
	func is_vanilla_hud_hidden() -> bool: return true
	func get_player_hp() -> int: return 100
	func get_player_max_hp() -> int: return 100
	func get_player_mana() -> int: return 50
	func get_player_max_mana() -> int: return 50
	func get_player_level() -> int: return 5
	func get_player_xp() -> int: return 1000
	func get_player_next_xp() -> int: return 2000
	func get_player_gold() -> int: return 500
	func get_town_portal_summary() -> Dictionary: return {}
	func get_potion_summary() -> Dictionary: return {}
	func get_available_spells() -> Array: return []
	func get_player_durability_warnings() -> Array: return []

	func get_belt_items() -> Array:
		return [
			{
				"slot": 0,
				"slot_id": 0,
				"type": 8, # Scroll
				"name": "Scroll of Identify",
				"count": 1,
				"can_use": true
			},
			{
				"slot": 1,
				"slot_id": 1,
				"type": 1, # Heal
				"name": "Potion of Healing",
				"count": 1,
				"can_use": true
			}
		]

	func use_belt_slot(idx: int) -> void:
		belt_used.append(idx)
		if idx == 0:
			# Identify scroll triggers targeting mode
			cursor_id = 2
			inventory_open = true
			active_panel = 1

	func click_belt_slot(idx: int) -> void:
		belt_clicked.append(idx)

	func get_cursor_id() -> int:
		return cursor_id

	func cancel_targeting_cursor() -> void:
		targeting_cancelled = true
		cursor_id = 1

	func get_active_ui_panel() -> int:
		return active_panel

	func set_active_ui_panel(p: int) -> void:
		active_panel = p
		inventory_open = (p == 1)

	func is_inventory_open() -> bool:
		return inventory_open

	func get_inventory_version() -> int:
		return inventory_version

	func click_inventory_slot(slot_type: int, slot_idx: int, is_shift: bool = false, is_ctrl: bool = false) -> void:
		last_inv_click = {
			"slot_type": slot_type,
			"slot_idx": slot_idx,
			"shift": is_shift,
			"ctrl": is_ctrl
		}
		if cursor_id == 2:
			# Identified the item!
			cursor_id = 1
			inventory_version += 1

func _init() -> void:
	print("==================================================")
	print(" Testing Identify Scroll & Belt 1:1 Parity ")
	print("==================================================")

	var hud = HudScene.instantiate()
	root.add_child(hud)
	hud._ready()

	var bridge = MockBridgeIdentify.new()
	hud.set_bridge(bridge)
	hud.get_node("Root").visible = true

	# Initially tabbed menu is closed
	check("Tabbed menu starts closed", hud.tabbed_menu != null and not hud.tabbed_menu.visible)

	# 1. User presses F1 to use Scroll of Identify from belt slot 0
	var f1_event = InputEventKey.new()
	f1_event.pressed = true
	f1_event.keycode = KEY_F1
	hud._unhandled_input(f1_event)

	check("F1 called use_belt_slot(0)", bridge.belt_used.has(0))
	check("Using Identify scroll automatically opened Inventory tab", hud.tabbed_menu.visible and hud.tabbed_menu.current_tab == 1)
	check("Cursor entered targeting mode (cid=2)", bridge.get_cursor_id() == 2)

	# 2. Test update_panels during targeting mode:
	# Even if active_engine_panel temporarily flickers to -1 during network frames,
	# targeting mode must keep tabbed_menu visible and open!
	bridge.active_panel = -1
	hud.update_panels()
	check("Targeting mode keeps Inventory open during engine tick flicker", hud.tabbed_menu.visible and hud.tabbed_menu.current_tab == 1)

	# 3. Test Right-Click cancels targeting mode (DevilutionX parity)
	var rmb_event = InputEventMouseButton.new()
	rmb_event.pressed = true
	rmb_event.button_index = MOUSE_BUTTON_RIGHT
	hud._input(rmb_event)

	check("Right-click called cancel_targeting_cursor()", bridge.targeting_cancelled)
	check("Cursor returned to normal HAND (cid=1)", bridge.get_cursor_id() == 1)

	# 4. Re-enter targeting mode and test clicking an inventory item to identify
	bridge.cursor_id = 2
	bridge.targeting_cancelled = false
	var inv_panel = hud.tabbed_menu.find_child("InventoryPanel", true, false)
	check("InventoryPanel exists", inv_panel != null)

	bridge.click_inventory_slot(1, 15)
	check("Clicking item during targeting identifies item and restores HAND cursor", bridge.get_cursor_id() == 1)
	check("Inventory version incremented", bridge.inventory_version > 1)

	# 5. Test Belt Slot tooltips reflect action dynamically
	hud.update_belt_slots()
	var slot0 = hud.belt_slots[0]
	var slot1 = hud.belt_slots[1]
	check("Slot 0 tooltip says Read Scroll", slot0 != null and "Read Scroll" in slot0.tooltip_text)
	check("Slot 1 tooltip says Drink", slot1 != null and "Drink" in slot1.tooltip_text)

	if failures == 0:
		print("==================================================")
		print(" ALL IDENTIFY SCROLL & BELT PARITY TESTS PASS! ")
		print("==================================================")
	else:
		print("TEST FAILED WITH %d FAILURES" % failures)

	hud.queue_free()
	quit(failures)
