extends SceneTree

const InventoryScene = preload("res://scenes/hud/d1de_inventory.tscn")

var failures := 0

func check(label: String, condition: bool) -> void:
	if condition:
		print("PASS  ", label)
	else:
		failures += 1
		print("FAIL  ", label)

func _init() -> void:
	print("==================================================")
	print(" Testing Inventory Cleanup (Task 2) ")
	print("==================================================")

	var inv = InventoryScene.instantiate()
	root.add_child(inv)
	inv._ready()

	# 1. Assert BeltCells is removed
	var belt_cells = inv.find_child("BeltCells", true, false)
	check("BeltCells node removed from inventory", belt_cells == null)

	# 2. Assert Paperdoll slots remain intact
	check("HeadSlot exists", inv.find_child("HeadSlot", true, false) != null)
	check("ChestSlot exists", inv.find_child("ChestSlot", true, false) != null)
	check("HandLeftSlot exists", inv.find_child("HandLeftSlot", true, false) != null)
	check("HandRightSlot exists", inv.find_child("HandRightSlot", true, false) != null)
	check("RingLeftSlot exists", inv.find_child("RingLeftSlot", true, false) != null)
	check("RingRightSlot exists", inv.find_child("RingRightSlot", true, false) != null)
	check("AmuletSlot exists", inv.find_child("AmuletSlot", true, false) != null)

	# 3. Assert GoldLabel exists
	check("GoldLabel exists", inv.find_child("GoldLabel", true, false) != null)

	# 4. Assert Backpack grid cells exist and count is 40
	var grid = inv.find_child("GridCells", true, false)
	check("GridCells exists", grid != null)
	if grid != null:
		check("Backpack has 40 grid cells", grid.get_child_count() == 40)

	inv.queue_free()

	if failures > 0:
		print("--------------------------------------------------")
		print("%d FAILURES in Inventory Cleanup" % failures)
		quit(1)
	else:
		print("ALL INVENTORY CLEANUP TESTS PASS.")
		quit(0)
