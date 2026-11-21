@tool
extends SceneTree

func _init():
	print("==================================================")
	print(" Testing Task 2.2: Pure Entity & Grid State API   ")
	print("==================================================")

	var bridge_class = ClassDB.can_instantiate("DiabloBridge")
	if not bridge_class:
		print("FAIL: DiabloBridge class not registered in ClassDB")
		quit(1)
		return

	var bridge = ClassDB.instantiate("DiabloBridge")
	if not bridge:
		print("FAIL: Could not instantiate DiabloBridge")
		quit(1)
		return

	# 1. Test Player Entity State API
	print("[1/4] Testing Player Entity State Fields...")
	var player_data: Dictionary = bridge.get_player_continuous_pos()
	var expected_player_keys = [
		"pos_x", "pos_y", "tile_x", "tile_y", "dir", "is_walking",
		"mode", "anim_frame", "action", "hp", "max_hp", "hp_pct",
		"mana", "max_mana", "mana_pct", "player_class", "name"
	]
	for k in expected_player_keys:
		if not player_data.has(k):
			print("FAIL: Missing player state field: ", k)
			quit(1)
			return
	print("  PASS: All 17 player state keys present! Action: '%s', HP: %s/%s (%s%%)" % [
		player_data["action"], player_data["hp"], player_data["max_hp"], player_data["hp_pct"] * 100.0
	])

	# 2. Test Monster Entity State API
	print("[2/4] Testing Monster Entity State Fields...")
	var monsters: Array = bridge.get_active_monsters_data()
	print("  Active monsters returned: ", monsters.size())
	if monsters.size() > 0:
		var m0 = monsters[0]
		var expected_monster_keys = [
			"id", "name", "type", "pos_x", "pos_y", "dir", "hp", "max_hp",
			"is_alive", "is_walking", "mode", "anim_frame", "is_visible",
			"action", "hp_pct"
		]
		for mk in expected_monster_keys:
			if not m0.has(mk):
				print("FAIL: Missing monster state field: ", mk)
				quit(1)
				return
		print("  PASS: Monster state fields verified! Monster: %s, action: %s, hp_pct: %s" % [
			m0["name"], m0["action"], m0["hp_pct"]
		])
	else:
		print("  PASS: No active monsters during idle/init, API call succeeded with empty array.")

	# 3. Test Active Objects API
	print("[3/4] Testing Active Objects Categorization & State...")
	var objects: Array = bridge.get_active_objects()
	print("  Active objects returned: ", objects.size())
	if objects.size() > 0:
		var obj0 = objects[0]
		for ok in ["id", "type", "tile_x", "tile_y", "anim_frame", "solid", "selectable", "is_open", "is_broken", "category"]:
			if not obj0.has(ok):
				print("FAIL: Missing object field: ", ok)
				quit(1)
				return
		print("  PASS: Object state fields verified! Object 0 category: %s, isOpen: %s, isBroken: %s" % [
			obj0["category"], obj0["is_open"], obj0["is_broken"]
		])
	else:
		print("  PASS: No active objects on level 0 / town, API call succeeded.")

	# 4. Test Active Items API
	print("[4/4] Testing Active Items Quality & State...")
	var items: Array = bridge.get_active_items()
	print("  Active items returned: ", items.size())
	if items.size() > 0:
		var it0 = items[0]
		for ik in ["id", "tile_x", "tile_y", "curs_id", "quality", "identified", "name", "quality_name"]:
			if not it0.has(ik):
				print("FAIL: Missing item field: ", ik)
				quit(1)
				return
		print("  PASS: Item state fields verified! Item 0: %s, quality: %s" % [it0["name"], it0["quality_name"]])
	else:
		print("  PASS: No ground items on level 0, API call succeeded.")

	print("==================================================")
	print(" ALL TASK 2.2 ENTITY & GRID STATE API CHECKS PASSED")
	print("==================================================")
	quit(0)
