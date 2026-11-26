@tool
extends SceneTree

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

func _init() -> void:
	var bridge = ClassDB.instantiate("DiabloBridge")
	root.add_child(bridge)
	bridge.init_engine(MPQ_DIR)
	while not bridge.is_engine_ready(): OS.delay_msec(20)
	bridge.menu_select_single_player()
	OS.delay_msec(400)
	bridge.launch_hero_game(2, 0, true)
	while not bridge.is_game_running(): OS.delay_msec(20)
	OS.delay_msec(1000)

	var objs = bridge.get_active_objects()
	print("--- CHECKING ALL SARCOPHAGI ON LEVEL 2 ---")
	for o in objs:
		var cat = str(o.get("category", ""))
		var o_type = o.get("type", -1)
		if cat == "SARCOPHAGUS" or o_type in [48, 96]:
			var id = o.get("id", -1)
			var tx = o.get("tile_x", -1)
			var ty = o.get("tile_y", -1)
			var is_open = o.get("is_open", false)
			var sel = o.get("selectable", true)
			var frame = o.get("anim_frame", -1)
			print("Sarc id=%3d at (%2d, %2d): is_open=%s, selectable=%s, frame=%d" % [id, tx, ty, str(is_open), str(sel), frame])

	quit(0)
