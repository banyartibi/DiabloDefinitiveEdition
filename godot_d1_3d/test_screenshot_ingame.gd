extends SceneTree

# In-game Mode 2 (native 3D) screenshot. Run under Xvfb with Vulkan:
#   xvfb-run -a ./tools/godot4/godot4 --path godot_d1_3d --rendering renderer=vulkan \
#       -s res://test_screenshot_ingame.gd

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"
const OUT_DIR = "/home/biti/antigravity/magical-bell/scratch"

func _init() -> void:
	var bridge = ClassDB.instantiate("DiabloBridge")
	root.add_child(bridge)
	bridge.init_engine(MPQ_DIR)
	while not bridge.is_engine_ready():
		OS.delay_msec(20)
	bridge.menu_select_single_player()
	OS.delay_msec(500)
	bridge.launch_hero_game(2, 0, true)
	while not bridge.is_game_running():
		OS.delay_msec(20)
	OS.delay_msec(2000)

	var vp = SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var scene = load("res://scenes/sandbox/native_3d_sandbox.tscn").instantiate()
	vp.add_child(scene)
	await process_frame
	scene.diablo_bridge = bridge
	scene.activate()

	for i in range(120):
		await process_frame

	var objs = bridge.get_active_objects()
	var mons = bridge.get_active_monsters_data()
	var mis = bridge.get_active_missiles()
	print("SHOT objects=%d monsters=%d missiles=%d" % [objs.size(), mons.size(), mis.size()])

	var img = vp.get_texture().get_image()
	if img == null:
		print("SHOT img=null")
		quit(1)
		return
	var path = OUT_DIR + "/ingame_mode2.png"
	img.save_png(path)
	print("SHOT saved=" + path + " size=" + str(img.get_size()))
	quit(0)
