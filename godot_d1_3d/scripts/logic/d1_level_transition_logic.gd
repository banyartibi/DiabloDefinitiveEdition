class_name D1LevelTransitionLogic
extends RefCounted

## Native Godot owner of the level-transition state machine.
## Mirrors the C++ safety contract (IsBridgeSafeToRead) plus the D1DE rules:
##   Rule #1 - Town isolation: town never resolves to a Cathedral PBR folder.
##   Rule #2 - Special CEL archways only exist on Cathedral levels (1..4).
##   Rule #3 - Runtime height validation: a 4X piece whose world height differs
##             from the 1X ground truth by > 4 must fall back to the engine texture.
## No C++ state is mutated here; this is the decision layer that the bridge calls.

const STATE_IDLE := 0
const STATE_QUEUED := 1
const STATE_TRANSITIONING := 2
const STATE_LOADED := 3

const MAX_LEVEL := 20          # Diablo I; Hellfire extends to 24
const CATHEDRAL_LEVELS := [1, 2, 3, 4]
const HEIGHT_TOLERANCE := 4    # Rule #3
const PM_NEWLVL := 10          # Source/player.h PLR_MODE

var state := STATE_IDLE
var pending_level := -1
var current_level := -1
var reads_blocked := false
var cache_generation := 0


func is_town(level_idx: int) -> bool:
	return level_idx == 0


func is_cathedral_level(level_idx: int) -> bool:
	return level_idx in CATHEDRAL_LEVELS


func queue_transition(level_idx: int) -> bool:
	if state == STATE_TRANSITIONING:
		return false
	if level_idx < 0 or level_idx > MAX_LEVEL:
		return false
	pending_level = level_idx
	state = STATE_QUEUED
	return true


func begin() -> Dictionary:
	if state != STATE_QUEUED:
		return {"ok": false, "reason": "not_queued"}
	current_level = pending_level
	pending_level = -1
	state = STATE_TRANSITIONING
	reads_blocked = true
	cache_generation += 1
	return {"ok": true, "level": current_level, "invalidate": invalidated_caches()}


func complete() -> Dictionary:
	if state != STATE_TRANSITIONING:
		return {"ok": false, "reason": "not_transitioning"}
	state = STATE_LOADED
	reads_blocked = false
	return {"ok": true, "level": current_level}


func is_safe_to_read(pmode: int, lvl_changing: bool, game_running: bool, player_ready: bool) -> bool:
	## Mirror of IsBridgeSafeToRead(): reads during the transition window are the
	## known crash source, so the native layer must refuse them.
	if not game_running or not player_ready or reads_blocked:
		return false
	if pmode == PM_NEWLVL or lvl_changing:
		return false
	return true


func invalidated_caches() -> Array:
	## Caches that must be dropped when the level changes (piece/special/item caches).
	return ["piece_texture_cache", "special_texture_cache", "item_texture_cache", "durability_texture_cache"]


func pbr_folder_for_level(level_idx: int, theme_map: Dictionary) -> String:
	## Rule #1: town must never fall back to the Cathedral theme.
	var theme := "town" if is_town(level_idx) else str(theme_map.get(level_idx, "cathedral"))
	if theme == "cathedral" and is_town(level_idx):
		return ""
	return "res://assets/dungeon_pbr_%s_4x" % theme


func height_gate(pbr_height: int, ground_truth_height: int) -> bool:
	## Rule #3: true = accept the 4X piece, false = fall back to engine texture.
	return abs(pbr_height - ground_truth_height) <= HEIGHT_TOLERANCE


func special_cel_gate(special_id: int, level_idx: int) -> bool:
	## Rule #2.
	return special_id > 0 and is_cathedral_level(level_idx)


func snapshot() -> Dictionary:
	return {
		"state": state,
		"current_level": current_level,
		"pending_level": pending_level,
		"reads_blocked": reads_blocked,
		"cache_generation": cache_generation,
	}
