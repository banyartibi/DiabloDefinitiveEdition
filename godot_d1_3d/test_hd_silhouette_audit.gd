extends SceneTree

# Runtime HD audit: for every entity the Mode 2 renderer draws, resolve the HD
# frame the provider WOULD use and compare it against the 1x bridge raster the
# engine actually renders. A size that is not 4x the 1x frame means the HD lookup
# landed on the wrong CEL family / wrong frame; a black frame means the asset was
# exported against the wrong palette.

const HdSpriteProvider = preload("res://scripts/hd_sprite_provider.gd")
const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

var bridge

func _init() -> void:
	bridge = ClassDB.instantiate("DiabloBridge")
	root.add_child(bridge)
	bridge.init_engine(MPQ_DIR)
	while not bridge.is_engine_ready():
		OS.delay_msec(20)
	bridge.menu_select_single_player()
	OS.delay_msec(500)
	bridge.launch_hero_game(2, 0, true)
	while not bridge.is_game_running():
		OS.delay_msec(20)
	OS.delay_msec(2500)

	var model := 2
	var env_model := OS.get_environment("HD_MODEL")
	if env_model != "":
		model = int(env_model)

	for cycle in 6:
		if cycle > 0:
			for f in 12:
				await process_frame
			OS.delay_msec(120)
		print("======== cycle %d | level=%d ========" % [cycle, bridge.get_current_level()])
		_audit_hero(model)
		_audit_objects(model)
		_audit_monsters(model)
		_audit_missiles(model)
		_audit_items(model)
		_audit_corpses(model)

	bridge.quit_game()
	bridge.deinit_engine()
	quit()

func _fmt(tex: Texture2D, one_x: Vector2i) -> String:
	if tex == null:
		return "HD=none (1x fallback)  1x=%dx%d" % [one_x.x, one_x.y]
	var img = tex.get_image()
	var w = tex.get_width()
	var h = tex.get_height()
	var black := false
	var mean := 0.0
	if img != null and not img.is_empty():
		var rect = img.get_used_rect()
		if rect.size.x > 0 and rect.size.y > 0:
			var n := 0
			var sum := 0.0
			for y in range(rect.position.y, rect.position.y + rect.size.y, 2):
				for x in range(rect.position.x, rect.position.x + rect.size.x, 2):
					var c = img.get_pixel(x, y)
					if c.a > 0.05:
						sum += (c.r + c.g + c.b) / 3.0
						n += 1
			mean = sum / max(n, 1)
			black = mean < 0.03
	var ratio_ok = (one_x.x == 0 or (w >= one_x.x * 3 and w <= one_x.x * 5))
	return "HD=%dx%d meanlum=%.3f %s ratio_ok=%s  1x=%dx%d" % [w, h, mean, ("BLACK" if black else "ok"), ratio_ok, one_x.x, one_x.y]

func _one_x(call: String, id: int = -1) -> Vector2i:
	if not bridge.has_method(call):
		return Vector2i.ZERO
	var d: Dictionary = bridge.call(call, id) if id >= 0 else bridge.call(call)
	return Vector2i(int(d.get("width", 0)), int(d.get("height", 0)))

func _audit_hero(model: int) -> void:
	var p_class := int(bridge.get_player_class())
	var cel_path := ""
	if bridge.has_method("get_player_cel_path"):
		cel_path = str(bridge.get_player_cel_path())
	var prefix := ""
	var parts := cel_path.replace("/", "\\").split("\\")
	if parts.size() >= 3:
		prefix = str(parts[2]).to_lower()
	var one := _one_x("get_player_sprite_data")
	var frames := {}
	for act in ["STAND", "WALK", "ATTACK", "SPELL", "HIT", "DEATH"]:
		for dir in [0, 3]:
			var tex = HdSpriteProvider.get_player_sprite(p_class, act, dir, 0, model, prefix)
			var tex2 = HdSpriteProvider.get_player_sprite(p_class, act, dir, 4, model, prefix)
			frames[act] = [tex, tex2]
	var resolved := 0
	for act in frames:
		if frames[act][0] != null:
			resolved += 1
	print("HERO class=%d prefix='%s' cel='%s' 1x=%dx%d resolved=%d/6" % [p_class, prefix, cel_path, one.x, one.y, resolved])
	for act in frames:
		var t: Texture2D = frames[act][0]
		var t2: Texture2D = frames[act][1]
		var w = t.get_width() if t != null else 0
		var h = t.get_height() if t != null else 0
		var w2 = t2.get_width() if t2 != null else 0
		var h2 = t2.get_height() if t2 != null else 0
		print("   %-7s f0=%dx%d f4=%dx%d %s" % [act, w, h, w2, h2, _fmt(t, one)])

func _audit_objects(model: int) -> void:
	if not bridge.has_method("get_active_objects"):
		print("OBJECTS: bridge method missing")
		return
	var objs: Array = bridge.get_active_objects()
	var seen := {}
	var hit := 0
	var miss := 0
	for o in objs:
		var g := str(o.get("graphic", ""))
		var af := int(o.get("anim_frame", 1))
		var at := int(o.get("anim_total", 1))
		var key := "%s|%d" % [g, af]
		if seen.has(key):
			continue
		seen[key] = true
		var tex = HdSpriteProvider.get_object_sprite(g, af, model)
		var one := _one_x("get_object_sprite_data", int(o.get("id", -1)))
		if tex != null:
			hit += 1
			print("OBJ  %-12s af=%d/%d id=%d %s" % [g, af, at, int(o.get("id", -1)), _fmt(tex, one)])
		else:
			miss += 1
			var avail := DirAccess.open("res://assets/hd_sprites_x4plus/objects/" + g) != null
			print("OBJ  %-12s af=%d/%d MISSING (dir_exists=%s) %s" % [g, af, at, avail, _fmt(null, one)])
	print("OBJECTS total=%d distinct=%d hd=%d missing=%d" % [objs.size(), seen.size(), hit, miss])

func _audit_monsters(model: int) -> void:
	if not bridge.has_method("get_active_monsters_data"):
		return
	var mons: Array = bridge.get_active_monsters_data()
	var seen := {}
	var hit := 0
	var miss := 0
	for m in mons:
		var nm := str(m.get("name", ""))
		var mode := int(m.get("mode", 0))
		var act := str(m.get("action", ""))
		var dir := int(m.get("dir", 0))
		var af := int(m.get("anim_frame", 0))
		var key := "%s|%d" % [nm, mode]
		if seen.has(key):
			continue
		seen[key] = true
		var tex = HdSpriteProvider.get_monster_sprite(nm, mode, dir, af, model)
		var one := _one_x("get_monster_sprite_data", int(m.get("id", -1)))
		if tex != null:
			hit += 1
			print("MON  %-14s mode=%-2d %-9s dir=%d f=%d %s" % [nm, mode, act, dir, af, _fmt(tex, one)])
		else:
			miss += 1
			print("MON  %-14s mode=%-2d %-9s dir=%d f=%d MISSING %s" % [nm, mode, act, dir, af, _fmt(null, one)])
	print("MONSTERS total=%d distinct=%d hd=%d missing=%d" % [mons.size(), seen.size(), hit, miss])

func _audit_missiles(model: int) -> void:
	if not bridge.has_method("get_active_missiles"):
		return
	var ms: Array = bridge.get_active_missiles()
	var seen := {}
	var hit := 0
	var miss := 0
	for m in ms:
		var cel := str(m.get("cel", ""))
		var dir := int(m.get("dir", 0))
		var af := int(m.get("anim_frame", 1))
		var key := "%s|%d" % [cel, dir]
		if seen.has(key):
			continue
		seen[key] = true
		var tex = HdSpriteProvider.get_missile_sprite(cel, dir, af, model)
		if tex != null:
			hit += 1
			print("MISL %-14s dir=%d f=%d %s" % [cel, dir, af, _fmt(tex, Vector2i.ZERO)])
		else:
			miss += 1
			print("MISL %-14s dir=%d f=%d MISSING" % [cel, dir, af])
	print("MISSILES total=%d distinct=%d hd=%d missing=%d" % [ms.size(), seen.size(), hit, miss])

func _audit_items(model: int) -> void:
	if not bridge.has_method("get_active_items"):
		return
	var items: Array = bridge.get_active_items()
	var seen := {}
	var hit := 0
	var miss := 0
	for it in items:
		var cid := int(it.get("curs_id", 0))
		var af := int(it.get("anim_frame", 0))
		if seen.has(cid):
			continue
		seen[cid] = true
		var tex = HdSpriteProvider.get_item_sprite(cid, af, model)
		var one := _one_x("get_ground_item_sprite_data", int(it.get("id", -1)))
		if tex != null:
			hit += 1
			print("ITEM curs=%-4d f=%d name=%-18s %s" % [cid, af, str(it.get("name", "")), _fmt(tex, one)])
		else:
			miss += 1
			print("ITEM curs=%-4d f=%d name=%-18s MISSING %s" % [cid, af, str(it.get("name", "")), _fmt(null, one)])
	print("ITEMS total=%d distinct=%d hd=%d missing=%d" % [items.size(), seen.size(), hit, miss])

func _audit_corpses(model: int) -> void:
	if not bridge.has_method("get_active_corpses"):
		return
	var cs: Array = bridge.get_active_corpses()
	for c in cs:
		var nm := str(c.get("monster_name", ""))
		var dir := int(c.get("dir", 0))
		var fr := int(c.get("frame", 0))
		var tex = HdSpriteProvider.get_corpse_sprite(nm, dir, fr, model)
		print("CORP %-14s dir=%d f=%d %s" % [nm, dir, fr, _fmt(tex, Vector2i.ZERO)])
