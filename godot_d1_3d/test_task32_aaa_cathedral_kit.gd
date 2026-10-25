extends SceneTree

# ==============================================================================
# Test: Task 2 - AAA Cathedral Architectural Kit Geometry & PBR Integration
# ==============================================================================

func _init():
	print("\n==================================================")
	print(" Testing Task 2: AAA Cathedral Kit Verification   ")
	print("==================================================")

	var sandbox_script = load("res://scripts/native_3d_sandbox.gd")
	var sandbox = sandbox_script.new()

	var paths = [
		"res://assets/models/aaa/cathedral/wall_ns_gothic.res",
		"res://assets/models/aaa/cathedral/wall_ew_gothic.res",
		"res://assets/models/aaa/cathedral/wall_corner_gothic.res",
		"res://assets/models/aaa/cathedral/pillar_gothic.res"
	]

	print("\n[1/3] Verifying AAA Certification & Resource Loading...")
	for p in paths:
		assert(ResourceLoader.exists(p), "ERROR: Asset file missing: %s" % p)
		var mesh = sandbox.get_or_load_mesh(p)
		assert(mesh != null and (mesh is ArrayMesh), "ERROR: Mesh must be valid ArrayMesh: %s" % p)
		assert(sandbox.is_mesh_aaa_certified(p), "ERROR: Asset must be AAA certified: %s" % p)
		print("  PASS: Loaded & Certified: %s (Faces: %d)" % [p.get_file(), mesh.get_faces().size() / 3])

	print("\n[2/3] Verifying Architectural Geometry & Invariants...")
	# Check Wall NS
	var wall_ns = sandbox.get_or_load_mesh(paths[0])
	var aabb_ns = wall_ns.get_aabb()
	assert(is_equal_approx(aabb_ns.size.x, 1.06066), "ERROR: Wall NS length must match diagonal step (1.06066m)! Got: %f" % aabb_ns.size.x)
	assert(aabb_ns.position.y <= -0.05, "ERROR: Subterranean skirt must extend below y=0 to stop light leaks! Got: %f" % aabb_ns.position.y)
	assert(aabb_ns.end.y >= 2.40, "ERROR: Wall height must reach at least 2.40m! Got: %f" % aabb_ns.end.y)
	print("  PASS: Wall NS geometry matches architectural spec: %s" % str(aabb_ns))

	# Check Wall EW
	var wall_ew = sandbox.get_or_load_mesh(paths[1])
	var aabb_ew = wall_ew.get_aabb()
	assert(is_equal_approx(aabb_ew.size.z, 1.06066), "ERROR: Wall EW length must match diagonal step (1.06066m)! Got: %f" % aabb_ew.size.z)
	assert(aabb_ew.position.y <= -0.05, "ERROR: Subterranean skirt must extend below y=0! Got: %f" % aabb_ew.position.y)
	print("  PASS: Wall EW geometry matches architectural spec: %s" % str(aabb_ew))

	# Check Pillar
	var pillar = sandbox.get_or_load_mesh(paths[3])
	var aabb_p = pillar.get_aabb()
	assert(aabb_p.position.y <= -0.05, "ERROR: Pillar base plinth must extend below y=0!")
	assert(aabb_p.end.y >= 2.40, "ERROR: Pillar capital must reach 2.40m!")
	print("  PASS: Pillar geometry matches architectural spec: %s" % str(aabb_p))

	print("\n[3/3] Verifying PBR Material Channels...")
	for p in paths:
		var m = sandbox.get_or_load_mesh(p)
		var mat = m.surface_get_material(0) as StandardMaterial3D
		assert(mat != null, "ERROR: Material must be StandardMaterial3D on: %s" % p)
		assert(mat.albedo_texture != null, "ERROR: Albedo texture missing on: %s" % p)
		assert(mat.normal_enabled and mat.normal_texture != null, "ERROR: Normal map missing on: %s" % p)
		assert(mat.roughness_texture != null, "ERROR: Roughness texture missing on: %s" % p)
		print("  PASS: %s -> Albedo, Normal, Roughness PBR channels fully active!" % p.get_file())

	print("\n==================================================")
	print(" ALL TASK 2 AAA CATHEDRAL KIT CHECKS PASSED 100%!")
	print("==================================================")
	quit(0)
