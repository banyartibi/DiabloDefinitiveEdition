class_name D1LogicAuthority
extends RefCounted

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

var authority := {}
var checks := {}
var mismatches := {}
var log := []


func _init() -> void:
	for s in SUBSYSTEMS:
		authority[s] = AUTH_SHADOW
		checks[s] = 0
		mismatches[s] = 0


func set_authority(subsystem: String, mode: int) -> void:
	authority[subsystem] = mode


func get_authority(subsystem: String) -> int:
	return authority.get(subsystem, AUTH_CPP)


func record(subsystem: String, native_result, cpp_result) -> bool:
	if authority.get(subsystem, AUTH_CPP) == AUTH_CPP:
		return true
	checks[subsystem] = int(checks.get(subsystem, 0)) + 1
	var ok = _equal(native_result, cpp_result)
	if not ok:
		mismatches[subsystem] = int(mismatches.get(subsystem, 0)) + 1
		log.append({"subsystem": subsystem, "native": native_result, "cpp": cpp_result})
	return ok


func can_promote(subsystem: String) -> bool:
	return int(mismatches.get(subsystem, 0)) == 0 and int(checks.get(subsystem, 0)) >= PROMOTION_THRESHOLD


func report() -> Dictionary:
	var out := {}
	for s in SUBSYSTEMS:
		out[s] = {
			"authority": authority[s],
			"checks": int(checks.get(s, 0)),
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
