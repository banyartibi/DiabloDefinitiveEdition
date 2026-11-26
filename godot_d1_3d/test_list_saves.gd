@tool
extends SceneTree

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

func _init() -> void:
	var bridge = ClassDB.instantiate("DiabloBridge")
	root.add_child(bridge)
	bridge.init_engine(MPQ_DIR)
	while not bridge.is_engine_ready():
		OS.delay_msec(20)
	bridge.menu_select_single_player()
	OS.delay_msec(500)
	var heroes = bridge.get_hero_list() if bridge.has_method("get_hero_list") else []
	for h in heroes:
		var snum = h.get("save_num", -1)
		print("Checking save %d: name=%s class=%s level=%d" % [snum, h.get("name", ""), h.get("class_name", ""), h.get("level", 0)])
	quit(0)
