extends SceneTree
# Micro-test: does the sandbox _process actually run while we await frames?

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

var bridge
var sandbox
var viewport: SubViewport

func _init():
	bridge = ClassDB.instantiate("DiabloBridge")
	bridge.init_engine(MPQ_DIR)
	for attempt in range(3):
		if bridge.is_game_running():
			break
		bridge.menu_select_single_player()
		OS.delay_msec(1500)
		bridge.launch_hero_game(2, 0, true)
		for i in range(40):
			OS.delay_msec(100)
			if bridge.is_game_running():
				break
	print("[PROC] running=%s level=%d" % [bridge.is_game_running(), bridge.get_current_level()])

	# go to dungeon like the probe does
	if bridge.has_method("enter_level"):
		bridge.enter_level(1)
	for i in range(120):
		await process_frame

	var scene = load("res://scenes/sandbox/native_3d_sandbox.tscn")
	sandbox = scene.instantiate()
	sandbox.diablo_bridge = bridge
	root.add_child(sandbox)
	sandbox._ready()
	sandbox.activate()
	for i in range(240):
		await process_frame

	var a0 = sandbox.time_accum
	var n = 0
	var t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1000:
		await process_frame
		n += 1
	var a1 = sandbox.time_accum
	print("[PROC] 1s: process_frame awaits=%d sandbox_time_accum_delta=%.3f active=%s gate=%s" % [
		n, a1 - a0, sandbox.is_sandbox_active, sandbox._bridge_read_gate_open()])

	# prop tracking inside that window
	var watch = []
	for o in bridge.get_active_objects():
		if int(o.get("anim_total", 1)) > 1 and sandbox.prop_instances.has(int(o.get("id", -1))):
			var nn = sandbox.prop_instances[int(o.get("id", -1))]
			if is_instance_valid(nn) and nn.visible and nn.get_node_or_null("ObjectSprite3D") != null:
				watch.append(int(o.get("id", -1)))
	print("[PROC] watching %d animated props: %s" % [watch.size(), str(watch.slice(0, 6))])
	for it in range(10):
		await process_frame
		var line = []
		for oid in watch.slice(0, 4):
			var eng = -1
			for o in bridge.get_active_objects():
				if int(o.get("id", -1)) == oid:
					eng = int(o.get("anim_frame", 1))
					break
			line.append("id%d eng=%d godot=%d vis=%s" % [oid, eng, int(sandbox.prop_last_frame.get(oid, -999)), str(sandbox.prop_instances[oid].visible)])
		print("  t=%dms %s" % [Time.get_ticks_msec() - t0 - 1000, " | ".join(line)])
	print("[PROC] TPS check: engine ticks? player anim_frame samples")
	quit()
