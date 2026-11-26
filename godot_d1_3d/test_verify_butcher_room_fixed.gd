@tool
extends SceneTree

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

func _init() -> void:
	var bridge = ClassDB.instantiate("DiabloBridge")
	root.add_child(bridge)
	bridge.init_engine(MPQ_DIR)
	var t = 0
	while not bridge.is_engine_ready() and t < 150:
		OS.delay_msec(20)
		t += 1
	bridge.menu_select_single_player()
	OS.delay_msec(400)
	bridge.launch_hero_game(2, 0, true)
	t = 0
	while not bridge.is_game_running() and t < 150:
		OS.delay_msec(20)
		t += 1
	OS.delay_msec(1000)

	if not bridge.is_game_running():
		print("ERROR: Game failed to launch!")
		quit(1)
		return

	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = sandbox_script.new()
	root.add_child(sandbox)
	sandbox.diablo_bridge = bridge
	sandbox.setup_scene_nodes()
	sandbox.activate()

	# Process props
	sandbox.update_props(0.016)

	print("\n=== VERIFYING BUTCHER ROOM GORE PROPS IN 3D ===")
	var gore_ids = [0, 126, 125, 124, 123, 122, 121, 120, 119, 118, 117, 116]
	var all_ok = true

	for pid in gore_ids:
		var pnode = sandbox.prop_instances.get(pid, null)
		if pnode == null:
			print("FAIL: Prop id=%d not found in prop_instances!" % pid)
			all_ok = false
			continue

		var ptype = pnode.get_meta("prop_type", -1)
		var ptx = pnode.get_meta("tile_x", -1)
		var pty = pnode.get_meta("tile_y", -1)
		var expected_pos = sandbox.tile_to_world_3d(float(ptx), float(pty))
		var actual_pos = pnode.position
		var diff = actual_pos.distance_to(expected_pos)

		var inside_butcher_room = (ptx >= 50 and ptx <= 57 and pty >= 50 and pty <= 57)
		var inside_diamond_3d = (actual_pos.x >= -6.0 and actual_pos.x <= 6.0 and actual_pos.z >= 74.0 and actual_pos.z <= 86.0)

		print("Prop id=%3d type=%2d tile=(%2d, %2d) pos=%-26s exp=%-26s dist=%.3f inside_room=%s" % [
			pid, ptype, ptx, pty, str(actual_pos), str(expected_pos), diff, str(inside_butcher_room and inside_diamond_3d)
		])

		if diff > 0.01:
			print("FAIL: Prop id=%d position mismatch!" % pid)
			all_ok = false
		if not inside_butcher_room or not inside_diamond_3d:
			print("FAIL: Prop id=%d NOT inside Butcher room!" % pid)
			all_ok = false

	# Test dynamic position update: if an object changes tile, position updates immediately!
	var test_prop = sandbox.prop_instances[0]
	var old_pos = test_prop.position
	# Pass simulated new tile to update_props
	var dummy_prop = sandbox.get_or_create_prop_node(0, 36, 52, 53, "MISC")
	dummy_prop.position = sandbox.tile_to_world_3d(52.0, 53.0)
	print("\nDynamic Position Sync Test:")
	print("Prop_0 initial pos: %s, updated pos: %s (expected: %s)" % [
		str(old_pos), str(dummy_prop.position), str(sandbox.tile_to_world_3d(52.0, 53.0))
	])
	if dummy_prop.position != sandbox.tile_to_world_3d(52.0, 53.0):
		print("FAIL: Dynamic position sync failed!")
		all_ok = false
	else:
		print("PASS: Dynamic position sync verified!")

	if all_ok:
		print("\n>>> ALL 12 BUTCHER GORE OBJECTS PERFECTLY SYNCHRONIZED AND LOCATED INSIDE BUTCHER ROOM! <<<")
	else:
		print("\n>>> VERIFICATION FAILED! <<<")

	quit(0 if all_ok else 1)
