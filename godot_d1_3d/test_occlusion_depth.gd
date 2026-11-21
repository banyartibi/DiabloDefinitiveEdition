extends SceneTree

func _init() -> void:
	print("--- Testing Pillar vs Player Depth Occlusion ---")
	var root = Node3D.new()
	root_node_add(root)

	var vp = SubViewport.new()
	vp.size = Vector2i(256, 256)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 5.0
	cam.position = Vector3(0, 10, 10)
	cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	vp.add_child(cam)

	# Pillar at (0, 0, 0)
	var pillar = MeshInstance3D.new()
	var p_mesh = BoxMesh.new()
	p_mesh.size = Vector3(1.0, 3.0, 1.0)
	pillar.mesh = p_mesh
	pillar.position = Vector3(0, 1.5, 0) # Pillar center
	var p_mat = StandardMaterial3D.new()
	p_mat.albedo_color = Color(0, 0, 1) # Blue pillar
	pillar.material_override = p_mat
	vp.add_child(pillar)

	# Player behind pillar at (0, 0, -2)
	var player = MeshInstance3D.new()
	var pl_mesh = BoxMesh.new()
	pl_mesh.size = Vector3(1.0, 2.0, 1.0)
	player.mesh = pl_mesh
	player.position = Vector3(0, 1.0, -2.0) # Player behind pillar
	var pl_mat = StandardMaterial3D.new()
	pl_mat.albedo_color = Color(1, 0, 0) # Red player
	player.material_override = pl_mat
	vp.add_child(player)

	print("Setup complete. Testing default render_priority=0 for both:")
	print("Pillar prio:", p_mat.render_priority, "Player prio:", pl_mat.render_priority)
	quit(0)
