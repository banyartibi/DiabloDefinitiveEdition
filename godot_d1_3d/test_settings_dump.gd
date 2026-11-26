extends SceneTree
# Dump the in-game Graphics settings (category/entry ids + current values) so the
# FPS bisect can toggle the same settings the pause menu uses.

var ctrl = null
var bridge = null
var frames = 0

func _initialize():
	ctrl = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(ctrl)

func _process(delta: float) -> bool:
	frames += 1
	if ctrl == null or not is_instance_valid(ctrl) or ctrl.diablo_bridge == null:
		return false
	bridge = ctrl.diablo_bridge
	if frames < 5:
		return false
	if not bridge.is_game_running():
		bridge.launch_hero_game(2, 0, true)
	if bridge.is_game_running():
		_dump_settings()
		quit()
	return false

func _dump_settings():
	var cats = bridge.get_settings_categories()
	for c in cats:
		var cid = int(c.get("id", -1))
		print("[SET] cat ", cid, " ", c.get("name", ""))
		for e in bridge.get_settings_entries(cid):
			print("   id=", int(e.get("id", -1)), " name=", e.get("name", ""),
				" type=", int(e.get("type", -1)),
				" bool=", e.get("bool_val", ""), " idx=", e.get("list_index", -1),
				" str=", e.get("value_str", ""), " opts=", e.get("list_options", []))
