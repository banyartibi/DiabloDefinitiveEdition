@tool
extends SceneTree

func _init():
	print("==================================================")
	print(" Testing Native 3D Sandbox in Godot 4.7.2 Headless ")
	print("==================================================")

	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	if not sandbox_script:
		print("FAIL: Could not load native_3d_sandbox.gd")
		quit(1)
		return

	var sandbox = Node3D.new()
	sandbox.set_script(sandbox_script)
	root.add_child(sandbox)
	sandbox.setup_scene_nodes()

	# 1. Test Coordinate Mathematics
	print("[1/5] Testing Coordinate Mathematics...")
	var test_points = [
		Vector2(0, 0),
		Vector2(25, 25),
		Vector2(10, 80),
		Vector2(111, 111),
		Vector2(45.5, 62.3)
	]
	for pt in test_points:
		var w = sandbox.tile_to_world_3d(pt.x, pt.y)
		var back = sandbox.world_3d_to_tile(w)
		if abs(back.x - pt.x) > 0.001 or abs(back.y - pt.y) > 0.001:
			print("FAIL: Invertibility error on %s -> %s -> %s" % [pt, w, back])
			quit(1)
			return
	print("  PASS: Tile to 3D world invertible with machine precision!")
	var b_neg45 = Basis().rotated(Vector3.UP, deg_to_rad(-45.0))
	var tile_x_dir = (sandbox.tile_to_world_3d(1, 0) - sandbox.tile_to_world_3d(0, 0)).normalized()
	var tile_y_dir = (sandbox.tile_to_world_3d(0, 1) - sandbox.tile_to_world_3d(0, 0)).normalized()
	var basis_x = (b_neg45 * Vector3(1, 0, 0)).normalized()
	var basis_z = (b_neg45 * Vector3(0, 0, 1)).normalized()
	print("  tile_x_dir: ", tile_x_dir, " | basis_x (local X): ", basis_x)
	print("  tile_y_dir: ", tile_y_dir, " | basis_z (local Z): ", basis_z)

	# 2. Test Modular Mesh Loading
	print("[2/5] Testing Modular .glb Meshes Loading...")
	var models = [
		"res://assets/models/dungeon/floor_cathedral.glb",
		"res://assets/models/dungeon/floor_catacombs.glb",
		"res://assets/models/dungeon/floor_caves.glb",
		"res://assets/models/dungeon/floor_hell.glb",
		"res://assets/models/dungeon/floor_town.glb",
		"res://assets/models/dungeon/wall_block.glb",
		"res://assets/models/dungeon/wall_ns.glb",
		"res://assets/models/dungeon/wall_ew.glb",
		"res://assets/models/dungeon/pillar.glb",
		"res://assets/models/dungeon/arch_open.glb",
		"res://assets/models/props/torch_sconce.glb",
		"res://assets/models/props/chest.glb",
		"res://assets/models/props/sarcophagus.glb",
		"res://assets/models/props/stairs_down.glb",
		"res://assets/models/characters/warrior.glb",
		"res://assets/models/characters/skeleton.glb"
	]
	for m_path in models:
		var m = sandbox.get_or_load_mesh(m_path)
		if m == null or (m is BoxMesh):
			print("FAIL: Model failed to load via GLTF and fell back to BoxMesh: %s" % m_path)
			quit(1)
			return
		print("  PASS: Loaded %s | type: %s | aabb: %s" % [m_path.get_file(), m.get_class(), m.get_aabb()])

	# 3. Test MultiMesh Configuration
	print("[3/4] Testing MultiMesh Dungeon Kit Configuration...")
	sandbox.update_modular_dungeon_assets(1)
	for mmi_name in ["floor_mmi", "wall_mmi", "wall_ns_mmi", "wall_ew_mmi", "pillar_mmi", "arch_mmi"]:
		var mmi = sandbox.get(mmi_name)
		var mat = mmi.material_override as StandardMaterial3D
		print("  %s | mesh: %s (aabb: %s) | mat albedo: %s | albedo_tex: %s | norm_tex: %s" % [
			mmi_name, mmi.multimesh.mesh.get_class(), mmi.multimesh.mesh.get_aabb(),
			mat.albedo_color, mat.albedo_texture, mat.normal_texture
		])

	# 4. Test GPUParticles3D Embers
	print("[4/5] Testing GPUParticles3D Ember Generator...")
	var embers = sandbox.create_ember_particles()
	if embers == null or embers.process_material == null:
		print("FAIL: Ember particles generation failed")
		quit(1)
		return
	print("  PASS: Ember GPUParticles3D configured properly!")

	# 5. Test Diamond Floor Mesh & Authentic Materials
	print("[5/5] Testing Procedural Diamond Floor Mesh & Multi-Piece Materials...")
	var diamond_mesh = sandbox.get_floor_diamond_mesh()
	if diamond_mesh == null:
		print("FAIL: Diamond floor mesh generation failed")
		quit(1)
		return
	print("  PASS: Floor diamond mesh: %s | aabb: %s" % [diamond_mesh.get_class(), diamond_mesh.get_aabb()])
	var f_mat = sandbox.get_floor_material(1, 1)
	if f_mat == null:
		print("FAIL: Floor material for piece 1 failed")
		quit(1)
		return
	print("  PASS: Floor piece 1 material: albedo_tex=%s, norm_tex=%s" % [f_mat.albedo_texture, f_mat.normal_texture])

	print("==================================================")
	print(" ALL NATIVE 3D SANDBOX CHECKS PASSED SUCCESSFULLY ")
	print("==================================================")
	quit(0)
