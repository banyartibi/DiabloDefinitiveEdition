extends SceneTree

const HudScene = preload("res://scenes/hud/d1de_hud.tscn")

var failures := 0

func check(label: String, condition: bool) -> void:
	if condition:
		print("PASS  ", label)
	else:
		failures += 1
		print("FAIL  ", label)

func _init() -> void:
	print("==================================================")
	print(" Testing HUD Hierarchy (Task 3) ")
	print("==================================================")

	var hud = HudScene.instantiate()
	root.add_child(hud)
	hud._ready()

	# 1. Orbs: Life & Mana
	var life_container = hud.find_child("LifeContainer", true, false)
	check("LifeContainer exists", life_container != null)
	var mana_container = hud.find_child("ManaContainer", true, false)
	check("ManaContainer exists", mana_container != null)

	# 2. XP Bar
	var xp_bar = hud.find_child("XpBar", true, false)
	check("XpBar exists", xp_bar != null)

	# 3. Left Console: 4 Skills + 4 Utility Slots
	for i in range(1, 5):
		check("SkillSlot%d exists" % i, hud.find_child("SkillSlot%d" % i, true, false) != null)

	check("HealthPotionSlot exists", hud.find_child("HealthPotionSlot", true, false) != null)
	check("ManaPotionSlot exists", hud.find_child("ManaPotionSlot", true, false) != null)
	check("RejuvPotionSlot exists", hud.find_child("RejuvPotionSlot", true, false) != null)
	check("TownPortalSlot exists", hud.find_child("TownPortalSlot", true, false) != null)

	# 4. Center Divider Pillar
	var pillar = hud.find_child("CenterPillar", true, false)
	check("CenterPillar exists", pillar != null)

	# 5. Right Console: 8 Belt Slots
	for i in range(8):
		check("BeltSlot%d exists" % i, hud.find_child("BeltSlot%d" % i, true, false) != null)

	hud.queue_free()

	if failures > 0:
		print("--------------------------------------------------")
		print("%d FAILURES in HUD Hierarchy" % failures)
		quit(1)
	else:
		print("ALL HUD HIERARCHY TESTS PASS.")
		quit(0)
