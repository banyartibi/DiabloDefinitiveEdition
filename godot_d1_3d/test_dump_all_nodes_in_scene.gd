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
	sandbox.update_props(0.1)

	print("--- INSPECTING ALL NODES IN SANDBOX ---")
	var check_node = func(n: Node, recurse):
		if n is Node3D:
			var p = n.position
			var g = n.global_position
			# Check if name contains prop, sarc, chest, gore, corpse, torture
			var n_name = n.name.to_lower()
			if "prop" in n_name or "sarc" in n_name or "chest" in n_name or "torture" in n_name or "scenery" in n_name:
				var t = sandbox.world_3d_to_tile(p)
				print("Node '%s' (%s): pos=(%.2f, %.2f, %.2f) -> tile=(%.1f, %.1f), vis=%s" % [
					n.name, n.get_class(), p.x, p.y, p.z, t.x, t.y, str(n.visible)
				])
		for c in n.get_children():
			recurse.call(c, recurse)

	check_node.call(sandbox, check_node)

	quit(0)
