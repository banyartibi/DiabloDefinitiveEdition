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

	# Set camera target to (54, 54) - the Butcher room center
	sandbox.camera_target = sandbox.tile_to_world_3d(54.0, 54.0)
	sandbox.camera_distance = 22.0
	sandbox.camera_pitch = 30.0
	sandbox.camera_yaw = 0.0
	sandbox.update_camera_transform()

	# Run one frame of process
	sandbox.update_props(0.016)

	print("=== EXACT PROP POSITIONS & SCREEN COORDS ===")
	print("Camera global position: %s" % str(sandbox.camera.global_position))
	print("Camera target: %s" % str(sandbox.camera_target))

	for pid in [0, 126, 125, 124, 123, 122, 121, 120, 119, 118, 117, 116, 110, 94]:
		var pnode = sandbox.prop_instances.get(pid, null)
		if pnode:
			var gpos = pnode.global_position
			var spos = sandbox.camera.unproject_position(gpos)
			var spr = pnode.get_node_or_null("ObjectSprite3D")
			var spr_tex = spr.texture if spr else null
			var spr_size = Vector2(spr_tex.get_width(), spr_tex.get_height()) if spr_tex else Vector2.ZERO
			print("Prop id=%3d type=%2d tile=(%2d, %2d) gpos=%s -> SCREEN=(%6.1f, %6.1f) vis=%s spr_size=%s" % [
				pid, pnode.get_meta("prop_type", -1), pnode.get_meta("tile_x", -1), pnode.get_meta("tile_y", -1),
				str(gpos), spos.x, spos.y, str(pnode.visible), str(spr_size)
			])

	quit(0)
