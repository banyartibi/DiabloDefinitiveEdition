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
	OS.delay_msec(400)
	bridge.launch_hero_game(2, 0, true)
	while not bridge.is_game_running():
		OS.delay_msec(20)
	OS.delay_msec(1000)

	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = sandbox_script.new()
	root.add_child(sandbox)
	sandbox.diablo_bridge = bridge
	sandbox.setup_scene_nodes()
	sandbox.modular_3d_walls_enabled = true
	sandbox.set_theme_aaa_certified("cathedral", true)
	sandbox.activate()
	sandbox.rebuild_dungeon_if_needed(true)

	var check_mm = func(name: String, mmi: MultiMeshInstance3D):
		if not mmi or not mmi.multimesh:
			return
		var mm = mmi.multimesh
		var non_zero = 0
		var in_butcher_area = 0
		for i in range(mm.instance_count):
			var tf = mm.get_instance_transform(i)
			if tf.origin.length_squared() > 0.001:
				non_zero += 1
			var t = sandbox.world_3d_to_tile(tf.origin)
			if t.x >= 45 and t.x <= 65 and t.y >= 45 and t.y <= 65:
				in_butcher_area += 1
				print("%s %d: pos=%s -> tile=(%.1f, %.1f)" % [name, i, str(tf.origin), t.x, t.y])
		print("%s: total=%d, non_zero=%d, in_butcher_area=%d" % [name, mm.instance_count, non_zero, in_butcher_area])

	check_mm.call("wall_block", sandbox.wall_mmi)
	check_mm.call("wall_ns", sandbox.wall_ns_mmi)
	check_mm.call("wall_ew", sandbox.wall_ew_mmi)
	check_mm.call("pillar", sandbox.pillar_mmi)
	check_mm.call("arch", sandbox.arch_mmi)

	quit(0)
