@tool
extends SceneTree

# Smoke test: does the rebuilt GDExtension expose the HD lookup keys
# (object "graphic", missile "cel") and does HdSpriteProvider resolve an
# HD PNG for each of them?

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"
const HdSpriteProvider = preload("res://scripts/hd_sprite_provider.gd")

func _init() -> void:
	var bridge = ClassDB.instantiate("DiabloBridge")
	root.add_child(bridge)
	bridge.init_engine(MPQ_DIR)
	while not bridge.is_engine_ready(): OS.delay_msec(20)
	bridge.menu_select_single_player()
	OS.delay_msec(400)
	bridge.launch_hero_game(2, 0, true)
	while not bridge.is_game_running(): OS.delay_msec(20)
	OS.delay_msec(1500)

	print("=== HD BRIDGE FIELD SMOKE (level %d) ===" % bridge.get_current_level())

	# ---- objects --------------------------------------------------------
	var objs = bridge.get_active_objects()
	var o_total = 0
	var o_named = 0
	var o_hd = 0
	var o_missing_names = []
	for o in objs:
		o_total += 1
		var g = str(o.get("graphic", ""))
		if g == "":
			o_missing_names.append(int(o.get("type", -1)))
			continue
		o_named += 1
		var frame = int(o.get("anim_frame", 1))
		if HdSpriteProvider.get_object_sprite(g, frame, 0) != null:
			o_hd += 1
		else:
			o_missing_names.append(g)
	print("OBJECTS  total=%d  graphic_named=%d  hd_resolved=%d" % [o_total, o_named, o_hd])
	if o_missing_names.size() > 0:
		print("  no-HD: %s" % str(o_missing_names.slice(0, 25)))

	# ---- missiles -------------------------------------------------------
	var miss = bridge.get_active_missiles()
	var m_total = 0
	var m_named = 0
	var m_hd = 0
	var m_missing = []
	for m in miss:
		m_total += 1
		var cel = str(m.get("cel", ""))
		if cel == "":
			m_missing.append(int(m.get("type", -1)))
			continue
		m_named += 1
		var fr = int(m.get("anim_frame", 1))
		var dir = int(m.get("dir", 0))
		if HdSpriteProvider.get_missile_sprite(cel, dir, fr, 0) != null:
			m_hd += 1
		else:
			m_missing.append(cel)
	print("MISSILES total=%d  cel_named=%d  hd_resolved=%d" % [m_total, m_named, m_hd])
	if m_missing.size() > 0:
		print("  no-HD: %s" % str(m_missing.slice(0, 25)))

	# ---- monsters (regression: provider path already used) --------------
	var mons = bridge.get_active_monsters_data()
	var k_total = 0
	var k_hd = 0
	var k_missing = []
	for mo in mons:
		k_total += 1
		var nm = str(mo.get("name", ""))
		if HdSpriteProvider.get_monster_sprite(nm, int(mo.get("mode", 1)),
				int(mo.get("dir", 0)), int(mo.get("anim_frame", 0)), 0) != null:
			k_hd += 1
		else:
			k_missing.append(nm)
	print("MONSTERS total=%d  hd_resolved=%d" % [k_total, k_hd])
	if k_missing.size() > 0:
		print("  no-HD: %s" % str(k_missing.slice(0, 25)))

	print("=== SMOKE DONE ===")
	quit(0)
