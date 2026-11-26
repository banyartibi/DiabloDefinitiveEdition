extends SceneTree
# Micro-probe: why does get_monster_sprite() miss for specific monstdat types?
# Prints the family the table gives, the on-disk candidates, and the provider's
# internal screening state for that folder. Headless only, opens no window.

const HdSpriteProvider = preload("res://scripts/hd_sprite_provider.gd")
const MonsterFamilyTable = preload("res://scripts/monster_family_table.gd")
const UpscalerModelConfig = preload("res://scripts/upscaler_model_config.gd")

const MON_MODE := { "stand": 0, "walk": 1, "attack": 4, "hit": 5, "death": 6, "special": 7 }

func _init() -> void:
	var names: Array = JSON.parse_string(FileAccess.open("res://test_hd_names.json", FileAccess.READ).get_as_text())["monsters"]
	var want: Array = OS.get_environment("MON_DEBUG").split(",") if OS.get_environment("MON_DEBUG") != "" else ["Fallen One", "Skeleton", "Scavenger", "Wyrm", "Golem"]
	var folder: String = UpscalerModelConfig.get_sprite_folder(0)
	for mi in names.size():
		var nm: String = names[mi]
		if nm not in want:
			continue
		var fam: String = MonsterFamilyTable.MONSTER_FAMILY[mi]
		var acts: Array = []
		for act in MON_MODE.keys():
			var sub := "monsters/%s_%s" % [fam, act]
			var p := folder + "/" + sub + "/dir_3_frame_2.png"
			acts.append("%s=%s%s" % [act, "file" if FileAccess.file_exists(p) else "nofile", "|bad" if HdSpriteProvider._bad_folders.has(folder + "/" + sub) else ""])
			HdSpriteProvider.get_monster_sprite(nm, MON_MODE[act], 3, 2, 0, mi)
		var drains := 0
		while HdSpriteProvider.pending_count() > 0 and drains < 60:
			HdSpriteProvider.pump(8)
			drains += 1
		# Second pass: what each action actually resolves to after the queue drained.
		for i in acts.size():
			var act2: String = acts[i].split("=")[0]
			acts[i] = "%s:%s" % [act2, "OK" if HdSpriteProvider.get_monster_sprite(nm, MON_MODE[act2], 3, 2, 0, mi) != null else "NULL"]
		print("DBG %3d %-14s fam=%-16s %s" % [mi, nm, fam, " ".join(acts)])
	print("DBG bad_folders=%d hits=%d created=%d hits_stat=%d miss_stat=%d pending=%d" % [
		HdSpriteProvider._bad_folders.size(), HdSpriteProvider._black_hits.size(),
		int(HdSpriteProvider.stat_created), int(HdSpriteProvider.stat_hits), int(HdSpriteProvider.stat_misses),
		HdSpriteProvider.pending_count()])
	var bad_keys = HdSpriteProvider._bad_folders.keys()
	bad_keys.sort()
	print("DBG BAD: " + ", ".join(bad_keys))
	quit()
