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

	# We test two camera targets:
	# 1. target = center of blood room (54, 54)
	# 2. target = player spawn pos (54, 66)

	var targets = {
		"(54, 54) blood room": sandbox.tile_to_world_3d(54.0, 54.0),
		"(54, 66) spawn hall": sandbox.tile_to_world_3d(54.0, 66.0)
	}

	for desc in targets.keys():
		var tgt = targets[desc]
		sandbox.camera_target = tgt
		sandbox.camera_distance = 22.0
		sandbox.camera_pitch = 30.0
		sandbox.camera_yaw = 0.0
		sandbox.update_camera_transform()
		sandbox.update_props(0.1)

		print("\n=======================================================")
		print("CAMERA TARGET: %s -> world %s" % [desc, str(tgt)])
		print("=======================================================")

		for pid in sandbox.prop_instances.keys():
			var pnode = sandbox.prop_instances[pid]
			var wpos = pnode.position
			var spos = sandbox.camera.unproject_position(wpos)
			# Viewport is 1024 x 558
			if spos.x >= -50 and spos.x <= 1074 and spos.y >= -50 and spos.y <= 608:
				var ptype = pnode.get_meta("prop_type", -1)
				var tx = pnode.get_meta("tile_x", -1)
				var ty = pnode.get_meta("tile_y", -1)
				print("Prop id=%3d type=%2d tile=(%2d, %2d) world=(%6.2f, %6.2f) -> SCREEN=(%6.1f, %6.1f) vis=%s" % [
					pid, ptype, tx, ty, wpos.x, wpos.z, spos.x, spos.y, str(pnode.visible)
				])

	quit(0)
