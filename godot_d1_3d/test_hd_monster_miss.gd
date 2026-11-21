@tool
extends SceneTree

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"
const HdSpriteProvider = preload("res://scripts/hd_sprite_provider.gd")

func _init() -> void:
	var bridge = ClassDB.instantiate("DiabloBridge")
	root.add_child(bridge)
	bridge.init_engine(MPQ_DIR)
	while not bridge.is_engine_ready(): OS.delay_msec(20)
	bridge.menu_select_single_player()
	OS.delay_msec(400)
	bridge.launch_hero_game(2, 0, true)
	while not bridge.is_game_running(): OS.delay_msec(20)
	OS.delay_msec(1500)

	for mo in bridge.get_active_monsters_data():
		var nm = str(mo.get("name", ""))
		if HdSpriteProvider.get_monster_sprite(nm, int(mo.get("mode", 1)),
				int(mo.get("dir", 0)), int(mo.get("anim_frame", 0)), 0) == null:
			print("MISS name=%s mode=%d dir=%d frame=%d action=%s" % [
				nm, int(mo.get("mode", 1)), int(mo.get("dir", 0)),
				int(mo.get("anim_frame", 0)), str(mo.get("action", ""))])
	quit(0)
