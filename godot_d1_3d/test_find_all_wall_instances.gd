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

	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = sandbox_script.new()
	root.add_child(sandbox)
	sandbox.diablo_bridge = bridge
	sandbox.setup_scene_nodes()
	sandbox.modular_3d_walls_enabled = true
	sandbox.set_theme_aaa_certified("cathedral", true)
	sandbox.activate()
	sandbox.rebuild_dungeon_if_needed(true)

	var check_mmi = func(name: String, mmi: MultiMeshInstance3D):
		if mmi == null or mmi.multimesh == null: return
		var mm = mmi.multimesh
		print("MultiMesh %s has %d instances" % [name, mm.instance_count])
		# Count how many instances are in Area A: X in [-7..7], Z in [74..88]
		var in_area_a = 0
		var other_clusters = {}
		for i in range(mm.instance_count):
			var tf = mm.get_instance_transform(i)
			var p = tf.origin
			if p.x >= -7.0 and p.x <= 7.0 and p.z >= 74.0 and p.z <= 88.0:
				in_area_a += 1
			else:
				var k = Vector2i(int(p.x / 10.0), int(p.z / 10.0))
				other_clusters[k] = other_clusters.get(k, 0) + 1
		print("   Instances in Area A: %d" % in_area_a)

	check_mmi.call("Wall Block", sandbox.wall_mmi)
	check_mmi.call("Wall NS", sandbox.wall_ns_mmi)
	check_mmi.call("Wall EW", sandbox.wall_ew_mmi)
	check_mmi.call("Pillar", sandbox.pillar_mmi)
	check_mmi.call("Arch", sandbox.arch_mmi)

	quit(0)
