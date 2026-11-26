@tool
extends SceneTree

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

func _init() -> void:
	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = sandbox_script.new()
	root.add_child(sandbox)
	sandbox.setup_scene_nodes()

	# Simulate Level 1 objects: Object 0 at (38, 56)
	var dummy_objects_lvl1 = [
		{"id": 0, "type": 57, "tile_x": 38, "tile_y": 56, "anim_frame": 1, "category": "BARREL"}
	]

	# Manually create prop for Level 1
	var p0 = sandbox.get_or_create_prop_node(0, 57, 38, 56, "BARREL")
	print("Level 1 created Prop_0 at position: %s" % str(p0.position))

	# Now level transition to Level 2!
	sandbox._on_level_changed(2)

	# Level 2 objects: Object 0 is now TORTURE1 at (51, 52)
	var dummy_objects_lvl2 = [
		{"id": 0, "type": 36, "tile_x": 51, "tile_y": 52, "anim_frame": 1, "category": "MISC"}
	]

	# Now simulate get_or_create_prop_node for Level 2
	var p0_lvl2 = sandbox.get_or_create_prop_node(0, 36, 51, 52, "MISC")
	print("Level 2 Prop_0 position: %s (EXPECTED: %s)" % [
		str(p0_lvl2.position),
		str(sandbox.tile_to_world_3d(51.0, 52.0))
	])

	if p0_lvl2.position != sandbox.tile_to_world_3d(51.0, 52.0):
		print("BUG CONFIRMED: Prop_0 position was NOT updated! It retained the stale Level 1 position!")
	else:
		print("Prop position updated properly.")

	quit(0)
