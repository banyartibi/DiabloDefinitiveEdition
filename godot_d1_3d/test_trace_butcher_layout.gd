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
	sandbox.modular_3d_walls_enabled = true # Enable modular 3D walls like in user's screenshot!
	sandbox.set_theme_aaa_certified("cathedral", true)
	sandbox.activate()
	sandbox.rebuild_dungeon_if_needed(true)
	sandbox.update_props(0.1)

	var print_mmi = func(name: String, mmi: MultiMeshInstance3D):
		if mmi == null or mmi.multimesh == null:
			return
		var mm = mmi.multimesh
		var count = mm.instance_count
		print("--- %s instance count: %d ---" % [name, count])
		for i in range(count):
			var tf = mm.get_instance_transform(i)
			var p = tf.origin
			if p.x >= -10.0 and p.x <= 10.0 and p.z >= 70.0 and p.z <= 95.0:
				var tile = sandbox.world_3d_to_tile(p)
				print("%s at pos=(%.2f, %.2f, %.2f) -> tile=(%.1f, %.1f)" % [name, p.x, p.y, p.z, tile.x, tile.y])

	print_mmi.call("Wall BLOCK", sandbox.wall_mmi)
	print_mmi.call("Wall NS", sandbox.wall_ns_mmi)
	print_mmi.call("Wall EW", sandbox.wall_ew_mmi)
	print_mmi.call("Pillar", sandbox.pillar_mmi)
	print_mmi.call("ARCH", sandbox.arch_mmi)

	print("\n--- PROPS IN THAT SAME REGION ---")
	for pid in sandbox.prop_instances.keys():
		var node = sandbox.prop_instances[pid]
		var p = node.position
		if p.x >= -10.0 and p.x <= 10.0 and p.z >= 70.0 and p.z <= 95.0:
			var ptype = node.get_meta("prop_type", -1)
			var tx = node.get_meta("tile_x", -1)
			var ty = node.get_meta("tile_y", -1)
			print("Prop id=%d type=%d tile=(%d, %d) pos=(%.2f, %.2f, %.2f) vis=%s" % [pid, ptype, tx, ty, p.x, p.y, p.z, str(node.visible)])

	quit(0)
