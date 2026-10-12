extends SceneTree

## The runtime handover for level_transition: the render freeze decision is made by
## D1LevelTransitionLogic.update_from_gate(), fed by the engine's gate signals.

const Mirror = preload("res://scripts/logic/d1_level_transition_logic.gd")

var failures := 0


func check(name: String, got, want) -> void:
	if got == want:
		print("PASS  %s" % name)
	else:
		failures += 1
		print("FAIL  %s  got=%s want=%s" % [name, got, want])


func gate(running := true, transitioning := false, faded := true, player := true, pmode := 1, lvl_changing := false) -> Dictionary:
	return {
		"game_running": running, "transitioning": transitioning, "faded_in": faded,
		"player_ready": player, "pmode": pmode, "lvl_changing": lvl_changing,
	}


func _init() -> void:
	var m = Mirror.new()

	check("steady state allows reads", m.update_from_gate(gate(), 3), true)
	check("no transition observed", m.state, m.STATE_IDLE)

	# The engine starts tearing the level down.
	check("teardown blocks reads", m.update_from_gate(gate(true, true, false), 3), false)
	check("mirror entered TRANSITIONING", m.state, m.STATE_TRANSITIONING)
	check("still blocked mid-load", m.update_from_gate(gate(true, true, false), 3), false)

	# Engine finished; the destination level is learned here, not earlier.
	check("load finished allows reads", m.update_from_gate(gate(), 7), true)
	check("mirror back to a settled state", m.state, m.STATE_LOADED)
	check("destination learned from engine", m.current_level, 7)

	# A gate that is not faded in must block even with no transition running.
	var m2 = Mirror.new()
	check("fade window blocks reads", m2.update_from_gate(gate(true, false, false), 1), false)
	# Player in PM_NEWLVL is the other known crash window.
	check("PM_NEWLVL blocks reads", m2.update_from_gate(gate(true, false, true, true, Mirror.PM_NEWLVL), 1), false)
	# Missing player is not "safe" just because the game is running.
	check("no player blocks reads", m2.update_from_gate(gate(true, false, true, false), 1), false)

	if failures > 0:
		print("--------------------------------------------------")
		print("%d FAILURES" % failures)
		quit(1)
	else:
		print("ALL GATE HANDOVER TESTS PASS.")
		quit(0)
