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
	OS.delay_msec(1200)

	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = sandbox_script.new()
	root.add_child(sandbox)
	sandbox.diablo_bridge = bridge
	sandbox.setup_scene_nodes()
	sandbox.activate()
	sandbox.rebuild_dungeon_if_needed(true)
	sandbox.update_props(0.1)

	# Focus camera on (54, 54) - center of Butcher room
	var target = sandbox.tile_to_world_3d(54.0, 54.0)
	sandbox.camera_target = target
	sandbox.player_target_pos = target
	sandbox.camera_distance = 22.0
	sandbox.camera_pitch = 30.0
	sandbox.camera_yaw = 0.0
	sandbox.update_camera_transform()

	# Print positions of props and room walls
	print("--- CAMERA TARGET (54, 54): ", target)
	for pid in sandbox.prop_instances.keys():
		var pnode = sandbox.prop_instances[pid]
		var ptype = pnode.get_meta("prop_type", -1)
		var ptx = pnode.get_meta("tile_x", -1)
		var pty = pnode.get_meta("tile_y", -1)
		if ptype in [29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40]:
			print("Prop id=%d type=%d at tile=(%d, %d), 3D pos=%s, vis=%s" % [pid, ptype, ptx, pty, str(pnode.position), str(pnode.visible)])

	# Print count of wall blocks, pillars, etc.
	print("Modular walls:")
	print("  pillars: %d" % sandbox.pillar_transforms.size())
	print("  wall_ns: %d" % sandbox.wall_ns_transforms.size())
	print("  wall_ew: %d" % sandbox.wall_ew_transforms.size())
	print("  wall_block: %d" % sandbox.wall_block_transforms.size())
	print("  arch_transforms: %d" % sandbox.arch_transforms.size())

	# Render a frame
	var vp = root.get_viewport()
	RenderingServer.frame_post_draw.connect(func():
		var tex = vp.get_texture()
		if tex:
			var img = tex.get_image()
			if img:
				img.save_png("/home/biti/.gemini/antigravity/brain/4427fff3-fdfb-47e3-b8be-42adea0050ce/render_butcher_54_54.png")
				print("SAVED: render_butcher_54_54.png")
	)

	for f in range(5):
		OS.delay_msec(50)

	quit(0)
