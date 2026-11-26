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
	OS.delay_msec(500)

	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = sandbox_script.new()
	root.add_child(sandbox)
	sandbox.diablo_bridge = bridge
	sandbox.setup_scene_nodes()
	sandbox.modular_3d_walls_enabled = true
	sandbox.activate()

	print("=== MONITORING PROP POSITIONS ACROSS 20 FRAMES ===")
	for f in range(20):
		sandbox._process(0.016)
		OS.delay_msec(20)
		var p0 = sandbox.prop_instances.get(0, null)
		var p126 = sandbox.prop_instances.get(126, null)
		var p108 = sandbox.prop_instances.get(108, null)
		if f in [0, 1, 5, 10, 19]:
			var s0 = ("pos=%s, tile=(%d, %d), vis=%s" % [str(p0.position), p0.get_meta("tile_x", -1), p0.get_meta("tile_y", -1), str(p0.visible)]) if p0 else "null"
			var s126 = ("pos=%s, tile=(%d, %d), vis=%s" % [str(p126.position), p126.get_meta("tile_x", -1), p126.get_meta("tile_y", -1), str(p126.visible)]) if p126 else "null"
			var s108 = ("pos=%s, tile=(%d, %d), vis=%s" % [str(p108.position), p108.get_meta("tile_x", -1), p108.get_meta("tile_y", -1), str(p108.visible)]) if p108 else "null"
			print("Frame %2d: Prop_0: %s | Prop_126: %s | Prop_108: %s" % [f, s0, s126, s108])

	quit(0)
