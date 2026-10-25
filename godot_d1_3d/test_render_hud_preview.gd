extends SceneTree

const HudScene = preload("res://scenes/hud/d1de_hud.tscn")

class MockBridge extends RefCounted:
	var hp := 132
	var max_hp := 165
	var mana := 223
	var max_mana := 610
	var seq := 10

	func get_belt_items() -> Array:
		var arr = []
		for i in range(8):
			arr.append({
				"slot_id": i,
				"name": "Potion of Healing" if i < 4 else "Potion of Mana",
				"type": 1 if i < 4 else 3,
				"count": 1,
				"misc_id": 3 if i < 4 else 6,
				"can_use": true
			})
		return arr

	func get_player_hp() -> int: return hp
	func get_player_max_hp() -> int: return max_hp
	func get_player_mana() -> int: return mana
	func get_player_max_mana() -> int: return max_mana
	func get_player_hp_raw() -> int: return hp * 64
	func get_player_max_hp_raw() -> int: return max_hp * 64
	func get_player_mana_raw() -> int: return mana * 64
	func get_player_max_mana_raw() -> int: return max_mana * 64
	func get_player_level() -> int: return 50
	func get_player_xp() -> int: return 750000
	func get_player_next_xp() -> int: return 1000000
	func get_player_gold() -> int: return 25420
	func get_player_item_flags() -> int: return 0
	func get_player_class() -> int: return 0
	func get_last_action_seq() -> int: return seq
	func get_last_action_rng_seed() -> int: return 12345
	func get_rng_seed() -> int: return 12345
	func is_hellfire() -> bool: return false
	func get_belt_item_texture(_idx: int): return null
	func use_belt_slot(_idx: int): pass
	func click_belt_slot(_idx: int): pass
	func is_inventory_open() -> bool: return false

func _init() -> void:
	print("Starting HUD preview renderer...")
	var subvp = SubViewport.new()
	subvp.size = Vector2i(1024, 576)
	subvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(subvp)

	var hud = HudScene.instantiate()
	subvp.add_child(hud)
	hud._ready()

	var bridge = MockBridge.new()
	hud.set_bridge(bridge)
	hud.get_node("Root").visible = true
	hud.update_health_and_mana(1.0)
	hud.update_xp_and_level()
	hud.update_belt_slots()

	var img = subvp.get_texture().get_image()
	if img:
		img.save_png("scratch/hud_preview_rendered.png")
		print("Successfully saved scratch/hud_preview_rendered.png!")
	else:
		print("Failed to get image from SubViewport!")

	quit(0)
