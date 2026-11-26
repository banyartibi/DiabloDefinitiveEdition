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

	var vp = SubViewport.new()
	vp.size = Vector2i(1024, 558)
	root.add_child(vp)

	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = sandbox_script.new()
	vp.add_child(sandbox)
	sandbox.diablo_bridge = bridge
	sandbox.setup_scene_nodes()
	sandbox.modular_3d_walls_enabled = true
	sandbox.activate()
	sandbox.rebuild_dungeon_if_needed(true)

	# Place player at (54, 54) (Butcher room center) like user
	bridge.walk_to_tile(54, 54)
	for i in range(30):
		sandbox._process(0.016)
		OS.delay_msec(16)

	print("=== ALL VISIBLE SPRITE3D NODES ===")
	var check_node = func(n: Node, recurse):
		if n is Sprite3D and n.is_visible_in_tree():
			var gpos = n.global_position
			var spos = sandbox.camera.unproject_position(gpos)
			var tex = n.texture
			var tex_sz = Vector2(tex.get_width(), tex.get_height()) if tex else Vector2.ZERO
			var parent_name = n.get_parent().name if n.get_parent() else "root"
			var tile = sandbox.world_3d_to_tile(gpos)
			print("Sprite '%s' under '%s': world=(%.2f, %.2f, %.2f) tile=(%.1f, %.1f) -> SCREEN=(%.1f, %.1f) tex=%s" % [
				n.name, parent_name, gpos.x, gpos.y, gpos.z, tile.x, tile.y, spos.x, spos.y, str(tex_sz)
			])
		for c in n.get_children():
			recurse.call(c, recurse)

	check_node.call(sandbox, check_node)

	# Take a screenshot to verify what Godot actually sees
	var img = vp.get_texture().get_image()
	if img:
		img.save_png("/tmp/test_viewport_capture.png")
		print("Saved /tmp/test_viewport_capture.png")

	quit(0)
