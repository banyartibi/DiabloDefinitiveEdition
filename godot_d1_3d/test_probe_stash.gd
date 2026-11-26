extends SceneTree

## Throwaway probe: stash contents of save 4 (looking for a handover-capable consumable).
const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

func _init() -> void:
	var bridge = ClassDB.instantiate("DiabloBridge")
	root.add_child(bridge)
	bridge.init_engine(MPQ_DIR)
	var waited = 0
	while not bridge.is_engine_ready() and waited < 200:
		OS.delay_msec(20)
		waited += 1
	bridge.menu_select_single_player()
	OS.delay_msec(500)
	bridge.launch_hero_game(4, 0, true)
	waited = 0
	while not bridge.is_game_running() and waited < 800:
		OS.delay_msec(20)
		waited += 1
	OS.delay_msec(1200)
	var HANDOVER := [2, 7, 10, 11, 12, 13, 19, 44]
	for it in bridge.get_stash_items():
		var mid := int(it.get("misc_id", -1))
		if mid in HANDOVER:
			print("STASH-HANDOVER misc=", mid, " name=", it.get("name", "?"), " count=", it.get("count", 1),
				" cell=", it.get("cell_idx", it.get("slot_idx", -1)))
	print("stash total: ", bridge.get_stash_items().size())
	bridge.quit_engine()
	quit(0)
