class_name D1ItemLogic
extends RefCounted

## Native Godot mirror of DevilutionX `UseItem()` (Source/items.cpp:4041).
## Pure and side-effect free: it only *predicts* the effect of using an item.
## The C++ engine remains the source of truth until parity is proven
## (see D1LogicAuthority). Values use the C++ fixed-point convention
## (HP/mana stored <<6).

# item_misc_id values, exactly as in Source/itemdat.h.
const IMISC_NONE := 0
const IMISC_USEFIRST := 1
const IMISC_FULLHEAL := 2
const IMISC_HEAL := 3
const IMISC_MANA := 6
const IMISC_FULLMANA := 7
const IMISC_ELIXSTR := 10
const IMISC_ELIXMAG := 11
const IMISC_ELIXDEX := 12
const IMISC_ELIXVIT := 13
const IMISC_REJUV := 18
const IMISC_FULLREJUV := 19
const IMISC_USELAST := 20
const IMISC_SCROLL := 21
const IMISC_SCROLLT := 22
const IMISC_STAFF := 23
const IMISC_BOOK := 24
const IMISC_OILFIRST := 29
const IMISC_OILOF := 30
const IMISC_OILACC := 31
const IMISC_OILMAST := 32
const IMISC_OILSHARP := 33
const IMISC_OILDEATH := 34
const IMISC_OILSKILL := 35
const IMISC_OILBSMTH := 36
const IMISC_OILFORT := 37
const IMISC_OILPERM := 38
const IMISC_OILHARD := 39
const IMISC_OILIMP := 40
const IMISC_OILLAST := 41
const IMISC_MAPOFDOOM := 42
const IMISC_SPECELIX := 44
const IMISC_RUNEFIRST := 46
const IMISC_RUNEF := 47
const IMISC_RUNEL := 48
const IMISC_GR_RUNEL := 49
const IMISC_GR_RUNEF := 50
const IMISC_RUNES := 51
const IMISC_RUNELAST := 52
const IMISC_ARENAPOT := 55

const MAX_SPELL_LEVEL := 15  # Source/player.h:37

const CURSOR_OIL := "CURSOR_OIL"
const CURSOR_TELEPORT := "CURSOR_TELEPORT"

const CLASS_WARRIOR := 0
const CLASS_ROGUE := 1
const CLASS_SORCERER := 2
const CLASS_MONK := 3
const CLASS_BARBARIAN := 4
const CLASS_BARD := 5

const CONTROL_KEYBOARD_AND_MOUSE := 0


static func is_usable(item: Dictionary, ctx: Dictionary = {}) -> bool:
	## Mirror of Item::isUsable() (Source/items.cpp:4766).
	if not item.get("can_use", false):
		return false
	var misc := int(item.get("misc_id", IMISC_NONE))
	if misc == IMISC_SPECELIX and not bool(ctx.get("mushroom_quest_done", true)):
		return false
	return true


static func belt_usable(item: Dictionary, ctx: Dictionary = {}) -> bool:
	## isUsable() + belt slot rules: only consumables fit a belt slot.
	if not is_usable(item, ctx):
		return false
	var misc := int(item.get("misc_id", IMISC_NONE))
	return (misc >= IMISC_USEFIRST and misc <= IMISC_USELAST) or (misc >= IMISC_OILFIRST and misc <= IMISC_OILLAST)


static func rune_spell(misc: int) -> String:
	match misc:
		IMISC_RUNEF: return "RuneOfFire"
		IMISC_RUNEL: return "RuneOfLight"
		IMISC_GR_RUNEL: return "RuneOfNova"
		IMISC_GR_RUNEF: return "RuneOfImmolation"
		IMISC_RUNES: return "RuneOfStone"
	return ""


static func predict_use_item(item: Dictionary, player: Dictionary, rng, ctx: Dictionary = {}) -> Dictionary:
	var misc := int(item.get("misc_id", IMISC_NONE))
	var result := {
		"ok": false,
		"reason": "not_usable",
		"actions": [],
		"effects": {"hp": 0, "mana": 0, "str": 0, "mag": 0, "dex": 0, "vit": 0},
		"cursor": "",
		"flags": {"invflag": false, "sbookflag": false, "oil_type": IMISC_NONE, "prepare_spell": "", "spell_from": int(item.get("spell_from", -1))},
		"rng_dependent": false,
	}

	if not is_usable(item, ctx):
		return result
	result["ok"] = true
	result["reason"] = "applied"

	var hellfire := bool(ctx.get("hellfire", false))
	var hp := int(player.get("hp", 0))
	var max_hp := int(player.get("max_hp", 0))
	var mana := int(player.get("mana", 0))
	var max_mana := int(player.get("max_mana", 0))

	match misc:
		IMISC_HEAL, IMISC_FULLHEAL, IMISC_REJUV, IMISC_FULLREJUV, IMISC_ARENAPOT:
			if misc == IMISC_FULLHEAL or misc == IMISC_FULLREJUV or misc == IMISC_ARENAPOT:
				result["actions"].append("restore_full_life")
				result["effects"]["hp"] = max_hp - hp
			else:
				result["actions"].append("restore_partial_life")
				result["rng_dependent"] = true
				var whole := max_hp >> 6
				var gain: int = ((whole / 8) + rng.generate_rnd(whole / 4)) << 6
				if int(player.get("class", 0)) in [CLASS_WARRIOR, CLASS_BARBARIAN]:
					gain *= 2
				elif int(player.get("class", 0)) in [CLASS_ROGUE, CLASS_MONK, CLASS_BARD]:
					gain += gain / 2
				result["effects"]["hp"] = min(hp + gain, max_hp) - hp
			if misc == IMISC_REJUV or misc == IMISC_FULLREJUV or misc == IMISC_ARENAPOT:
				if misc == IMISC_FULLREJUV or misc == IMISC_ARENAPOT:
					result["actions"].append("restore_full_mana")
					result["effects"]["mana"] = max_mana - mana
				else:
					result["actions"].append("restore_partial_mana")
					result["rng_dependent"] = true
					var whole_m := max_mana >> 6
					var gain_m: int = ((whole_m / 8) + rng.generate_rnd(whole_m / 4)) << 6
					if int(player.get("class", 0)) in [CLASS_ROGUE, CLASS_SORCERER, CLASS_BARD]:
						gain_m *= 2
					result["effects"]["mana"] = min(mana + gain_m, max_mana) - mana
		IMISC_MANA:
			result["actions"].append("restore_partial_mana")
			result["rng_dependent"] = true
			var whole_mana := max_mana >> 6
			var gain_mana: int = ((whole_mana / 8) + rng.generate_rnd(whole_mana / 4)) << 6
			if int(player.get("class", 0)) in [CLASS_ROGUE, CLASS_SORCERER, CLASS_BARD]:
				gain_mana *= 2
			result["effects"]["mana"] = min(mana + gain_mana, max_mana) - mana
		IMISC_FULLMANA:
			result["actions"].append("restore_full_mana")
			result["effects"]["mana"] = max_mana - mana
		IMISC_ELIXSTR:
			result["actions"].append("modify_str")
			result["effects"]["str"] = 1
		IMISC_ELIXMAG:
			result["actions"].append("modify_mag")
			result["effects"]["mag"] = 1
			if hellfire:
				result["actions"].append("restore_full_mana")
				result["effects"]["mana"] = max_mana - mana
		IMISC_ELIXDEX:
			result["actions"].append("modify_dex")
			result["effects"]["dex"] = 1
		IMISC_ELIXVIT:
			result["actions"].append("modify_vit")
			result["effects"]["vit"] = 1
			if hellfire:
				result["actions"].append("restore_full_life")
				result["effects"]["hp"] = max_hp - hp
		IMISC_SPECELIX:
			result["actions"].append("modify_all_stats")
			result["effects"]["str"] = 3
			result["effects"]["mag"] = 3
			result["effects"]["dex"] = 3
			result["effects"]["vit"] = 3
		IMISC_BOOK:
			result["actions"].append("spell_level_up")
			var spell_id := int(item.get("spell_id", -1))
			var levels: Dictionary = player.get("spell_levels", {})
			var current := int(levels.get(spell_id, 0))
			if current + 1 <= MAX_SPELL_LEVEL:
				result["effects"]["spell_level"] = 1
			if not bool(ctx.get("no_mana_flag", false)):
				var cost := int(ctx.get("spell_mana_cost", 0)) << 6
				result["effects"]["mana"] = min(mana + cost, max_mana) - mana
		IMISC_MAPOFDOOM:
			result["actions"].append("doom_init")
		IMISC_OILFIRST:
			pass
		IMISC_OILACC, IMISC_OILMAST, IMISC_OILSHARP, IMISC_OILDEATH, IMISC_OILSKILL, IMISC_OILBSMTH, IMISC_OILFORT, IMISC_OILPERM, IMISC_OILHARD, IMISC_OILIMP:
			result["actions"].append("set_oil_type")
			result["flags"]["oil_type"] = misc
			result["flags"]["sbookflag"] = false  # C++ closes the spellbook on oil use
			result["flags"]["invflag"] = true
			result["cursor"] = CURSOR_OIL
		IMISC_SCROLL, IMISC_SCROLLT:
			if int(ctx.get("control_mode", CONTROL_KEYBOARD_AND_MOUSE)) == CONTROL_KEYBOARD_AND_MOUSE and bool(ctx.get("spell_is_targeted", false)):
				result["actions"].append("prepare_spell")
				result["flags"]["prepare_spell"] = str(item.get("spell_id", -1))
				result["cursor"] = CURSOR_TELEPORT
			else:
				result["actions"].append("cmd_spellxy")
		IMISC_RUNEF, IMISC_RUNEL, IMISC_GR_RUNEL, IMISC_GR_RUNEF, IMISC_RUNES:
			result["actions"].append("prepare_spell")
			result["flags"]["prepare_spell"] = rune_spell(misc)
			result["cursor"] = CURSOR_TELEPORT
		_:
			result["reason"] = "no_effect"

	return result
