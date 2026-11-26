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

	# Walk or place player at (54, 54) like in user screenshot
	bridge.walk_to_tile(54, 54)
	for i in range(30):
		sandbox._process(0.016)
		OS.delay_msec(16)

	print("=== SCENE GRAPH PROPS ===")
	for c in sandbox.props_root.get_children():
		if c is Node3D:
			var spr = c.get_node_or_null("ObjectSprite3D") as Sprite3D
			var tex_name = spr.texture.resource_path if (spr and spr.texture) else ("tex" if spr and spr.texture else "none")
			print("PropNode '%s': pos=%s, meta_tile=(%d, %d), vis=%s, tex=%s" % [
				c.name, str(c.position), c.get_meta("tile_x", -1), c.get_meta("tile_y", -1), str(c.visible), tex_name
			])

	quit(0)
