extends SceneTree

# Headless coverage probe: asks HdSpriteProvider the same questions the Mode 2
# renderer asks (hero gear, monsters, missiles, objects, ground items) and
# reports how many lookups resolve to an HD texture, per model tree. Opens no
# window and runs no game; it only touches the provider and the asset trees.
#
# Engine keys come from test_hd_names.json, dumped from monstdat.cpp,
# objdat.cpp, misdat.cpp and itemdat.h by tools/audit_hd_assets.py's parsers.

const HdSpriteProvider = preload("res://scripts/hd_sprite_provider.gd")
const UpscalerModelConfig = preload("res://scripts/upscaler_model_config.gd")

var HERO = {
	0: ["warrior", "wha whb whd whh whm whn whs wht whu wla wlb wld wlh wlm wln wls wlt wlu wma wmb wmd wmh wmm wmn wms wmt wmu".split(" ")],
	1: ["rogue", "rha rhb rhd rhh rhm rhn rhs rht rhu rla rlb rld rlh rlm rln rls rlt rlu rma rmb rmd rmh rmm rmn rms rmt rmu".split(" ")],
	2: ["sorceror", "sha shb shd shh shm shn shs sht shu sla slb sld slh slm sln sls slt slu sma smb smd smh smm smn sms smt smu".split(" ")],
	3: ["monk", "mha mhb mhd mhh mhm mhn mhs mht mhu mla mlb mld mlh mlm mln mls mlt mlu mma mmb mmd mmh mmm mmn mms mmt mmu".split(" ")],
}
const ACTIONS = ["stand", "walk", "attack", "rattack", "block", "hit", "death", "spell", "spell_lm", "spell_qm"]
const HERO_PREFIX_SAMPLE := 27
# Cases per judged chunk; a case can queue several files (family aliases and
# action fallbacks), so the chunk stays well under MAX_CACHED_TEXTURES.
const CHUNK := 24

# Engine MonsterMode ints (DevilutionX/Source/monster.h), as the bridge passes them.
const MON_MODE = { "stand": 0, "walk": 1, "attack": 4, "hit": 5, "death": 6, "special": 7 }
const MON_ACTIONS = ["stand", "walk", "attack", "hit", "death", "special"]

func _init() -> void:
	var names = _read_json("res://test_hd_names.json")
	if names == null:
		print("PROBE ERROR: test_hd_names.json missing")
		quit()
		return
	var monsters: Array = names["monsters"]
	var missiles: Array = names["missiles"]
	var objects: Array = names["objects"]
	var curs: Array = names["curs"]

	for model in _models():
		var cases: Array = []
		for cid in HERO.keys():
			var cls: String = HERO[cid][0]
			var prefixes: Array = HERO[cid][1]
			for act in ACTIONS:
				for i in HERO_PREFIX_SAMPLE:
					var prefix: String = prefixes[i * prefixes.size() / HERO_PREFIX_SAMPLE]
					cases.append([cls + "/" + prefix + "/" + act, func(): return HdSpriteProvider.get_player_sprite(cid, act, 3, 2, model, prefix)])
		for mi in monsters.size():
			var m: String = monsters[mi]
			for act in MON_ACTIONS:
				var mode: int = MON_MODE[act]
				cases.append(["mon/" + m + "/" + act, func(): return HdSpriteProvider.get_monster_sprite(m, mode, 3, 2, model, mi)])
		for cel in missiles:
			for dir in [0, 5]:
				cases.append(["mis/" + cel, func(): return HdSpriteProvider.get_missile_sprite(cel, dir, 3, model)])
		for o in objects:
			cases.append(["obj/" + o, func(): return HdSpriteProvider.get_object_sprite(o, 1, model)])
		for cid in curs:
			var iid: int = int(cid)
			cases.append(["item/" + str(iid), func(): return HdSpriteProvider.get_item_sprite(iid, 0, model)])

		# Judge in chunks: the provider's LRU cap (1200 textures) and its stale
		# window (600 pump ticks) would evict frames queued by a single 1240-case
		# pass, so a whole-tree pass reports evicted frames as misses. Each chunk
		# queues well under the cap and drains inside the stale window, so the
		# second pass judges real availability, not decode timing or eviction.
		var tag: String = UpscalerModelConfig.MODEL_SHORT_NAMES[model]
		var ok := 0
		var total := 0
		var misses := {}
		var ok_cat := {}
		var miss_cat := {}
		var i := 0
		while i < cases.size():
			var chunk: Array = cases.slice(i, mini(i + CHUNK, cases.size()))
			# First pass queues every file the lookups found on disk; drain the
			# queue (no cap: the chunk is small) so the second pass sees textures.
			for c in chunk:
				c[1].call()
			var pump := 0
			while HdSpriteProvider.pending_count() > 0 and pump < 2000:
				HdSpriteProvider.pump(8)
				pump += 1
			for c in chunk:
				var cat: String = c[0].split("/")[0]
				total += 1
				if c[1].call() != null:
					ok += 1
					ok_cat[cat] = int(ok_cat.get(cat, 0)) + 1
				else:
					misses[c[0]] = true
					miss_cat[cat] = int(miss_cat.get(cat, 0)) + 1
			# Cache stays warm across chunks: clearing it would re-decode every
			# shared fallback dir, and the LRU already bounds memory.
			i += CHUNK
		print("PROBE model=%s resolved=%d/%d (%.1f%%)" % [tag, ok, total, 100.0 * ok / float(total)])
		var cats = ok_cat.keys()
		cats.sort()
		for cat in cats:
			print("PROBE model=%s cat=%s ok=%d miss=%d" % [tag, cat, int(ok_cat[cat]), int(miss_cat.get(cat, 0))])
		var keys = misses.keys()
		keys.sort()
		print("PROBE model=%s miss=%d %s" % [tag, keys.size(), ", ".join(keys)])
		print("PROBE model=%s bad_folders=%d created=%d evicted=%d" % [tag, HdSpriteProvider._bad_folders.size(), int(HdSpriteProvider.stat_created), int(HdSpriteProvider.stat_evicted)])
	quit()

func _models() -> Array:
	# HD_PROBE_MODEL selects one model tree (0 = hd_sprites, 1 = hd_sprites_x4plus);
	# draining the queue for both in one run costs too much memory.
	var sel = OS.get_environment("HD_PROBE_MODEL")
	return [int(sel)] if sel != "" else [0, 1]

func _read_json(path: String) -> Variant:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else null
