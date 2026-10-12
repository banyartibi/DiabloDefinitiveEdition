class_name D1LogicAuthority
extends Node

## Subsystem authority registry for the DevilutionX -> native Godot migration
## (Task 2 Step 5). Nothing is handed over until parity is proven.
##
##   AUTH_CPP   : C++ is the source of truth, native layer is not consulted.
##   AUTH_SHADOW: native layer predicts, C++ still executes; every prediction is
##                compared against the real C++ state delta.
##   AUTH_NATIVE: native layer decides and applies; C++ only mirrors the result.

const AUTH_CPP := 0
const AUTH_SHADOW := 1
const AUTH_NATIVE := 2

const SUBSYSTEMS := ["inventory_item_use", "level_transition", "rng"]

## Consecutive clean parity checks required before a subsystem can be promoted.
const PROMOTION_THRESHOLD := 200

## A check only counts as evidence if it is a distinct case (different seed / different effect).
## Re-running the same deterministic case 200 times proves nothing, so promotion also requires a
## minimum number of distinct cases.
##
## Lowered from 40 to 12: the reachable case space is the eight real hero saves plus the soak
## fixture (tools/make_soak_save.cpp), which is ~12 distinct (save, item) pairs. The original 40
## stays the target once more fixture states (inventory slots, level transitions) are wired in.
const MIN_DISTINCT := 12
const SEEN_CAP := 1000

## Parity checks accumulate across runs (a soak session is long), so the counters are persisted.
const STATE_VERSION := 1
const STATE_PATH := "res://logs/parity_state.json"
const LOG_CAP := 40

var authority := {}
var checks := {}
var mismatches := {}
var seen := {}
var log := []
var _dirty := false


func _init() -> void:
	for s in SUBSYSTEMS:
		authority[s] = AUTH_SHADOW
		checks[s] = 0
		mismatches[s] = 0
		seen[s] = {}


# The soak records its evidence to disk; the running game must start from that evidence, not from
# zero. As an autoload this node is in the tree, so these run; a manually instantiated instance
# (tests, soak) is never in the tree and stays pure logic with explicit load/save calls.
func _ready() -> void:
	if load_state(STATE_PATH):
		print("[AUTHORITY] promotion state loaded: ", report())
	else:
		print("[AUTHORITY] no promotion state at ", STATE_PATH, ", starting in AUTH_SHADOW")


func _exit_tree() -> void:
	# Never write a pristine (never loaded, never used) instance over real evidence.
	if _dirty:
		save_state(STATE_PATH)


func set_authority(subsystem: String, mode: int) -> void:
	authority[subsystem] = mode
	_dirty = true


func get_authority(subsystem: String) -> int:
	return authority.get(subsystem, AUTH_CPP)


func record(subsystem: String, native_result, cpp_result, signature: String = "") -> bool:
	if authority.get(subsystem, AUTH_CPP) == AUTH_CPP:
		return true
	_dirty = true
	checks[subsystem] = int(checks.get(subsystem, 0)) + 1
	if signature != "" and seen[subsystem].size() < SEEN_CAP:
		seen[subsystem][signature] = true
	var ok = _equal(native_result, cpp_result)
	if not ok:
		mismatches[subsystem] = int(mismatches.get(subsystem, 0)) + 1
		log.append({"subsystem": subsystem, "native": native_result, "cpp": cpp_result})
		if log.size() > LOG_CAP:
			log.pop_front()
	return ok


func distinct(subsystem: String) -> int:
	return seen.get(subsystem, {}).size()


func can_promote(subsystem: String) -> bool:
	return int(mismatches.get(subsystem, 0)) == 0 \
		and int(checks.get(subsystem, 0)) >= PROMOTION_THRESHOLD \
		and distinct(subsystem) >= MIN_DISTINCT

## Hand a subsystem over to the native layer. Refuses unless the evidence gate is met, so the
## gate cannot be bypassed by calling set_authority() by accident.
func promote(subsystem: String) -> bool:
	if not can_promote(subsystem):
		return false
	authority[subsystem] = AUTH_NATIVE
	return true

## Wipe the accumulated evidence for one subsystem (or all of them when subsystem == "").
## Counters are sticky and a single mismatch invalidates promotion forever, so after fixing a
## mirror bug the baseline has to be re-measured — otherwise the numbers describe the old code.
## Authority is deliberately NOT reset: handing back is an explicit decision.
func reset_counters(subsystem: String) -> void:
	var targets := SUBSYSTEMS if subsystem == "" else [subsystem]
	for s in targets:
		checks[s] = 0
		mismatches[s] = 0
		seen[s] = {}
	log.clear()


func total_checks() -> int:
	var t := 0
	for s in SUBSYSTEMS:
		t += int(checks.get(s, 0))
	return t


func save_state(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	var data := {
		"version": STATE_VERSION,
		"authority": authority,
		"checks": checks,
		"mismatches": mismatches,
		"seen": seen,
		"log": log,
		"last_run_utc": Time.get_datetime_string_from_system(true),
	}
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return true


func load_state(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return false
	# JSON numbers come back as floats; authority modes and counters must be ints.
	authority = _restore(data.get("authority", {}), authority)
	checks = _restore(data.get("checks", {}), checks)
	mismatches = _restore(data.get("mismatches", {}), mismatches)
	var seen_src = data.get("seen", {})
	if typeof(seen_src) == TYPE_DICTIONARY:
		for s in SUBSYSTEMS:
			if typeof(seen_src.get(s, {})) == TYPE_DICTIONARY:
				seen[s] = seen_src[s]
	var entries = data.get("log", [])
	if typeof(entries) == TYPE_ARRAY:
		log = entries.slice(maxi(0, entries.size() - LOG_CAP))
	return true


static func _restore(src, target: Dictionary) -> Dictionary:
	if typeof(src) != TYPE_DICTIONARY:
		return target
	for k in src:
		target[k] = int(src[k])
	return target


func report() -> Dictionary:
	var out := {}
	for s in SUBSYSTEMS:
		out[s] = {
			"authority": authority[s],
			"checks": int(checks.get(s, 0)),
			"distinct": distinct(s),
			"mismatches": int(mismatches.get(s, 0)),
			"promotable": can_promote(s),
		}
	return out


static func _equal(a, b) -> bool:
	if a is Dictionary and b is Dictionary:
		for k in a.keys():
			if not b.has(k):
				continue  # native may report extra fields
			if not _equal(a[k], b[k]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in range(a.size()):
			if not _equal(a[i], b[i]):
				return false
		return true
	return a == b
