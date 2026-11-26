extends SceneTree

# Probe: does Godot actually rasterize under this display driver?
func _init() -> void:
	var vp = SubViewport.new()
	vp.size = Vector2i(256, 256)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 4.0
	cam.position = Vector3(0, 5, 5)
	cam.rotation_degrees = Vector3(-45, 0, 0)
	vp.add_child(cam)

	var mi = MeshInstance3D.new()
	var m = BoxMesh.new()
	m.size = Vector3(2, 2, 2)
	mi.mesh = m
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.2, 0.2)
	mi.material_override = mat
	vp.add_child(mi)

	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	vp.add_child(light)

	for i in range(10):
		await process_frame

	var img = vp.get_texture().get_image()
	if img == null:
		print("PROBE img=null")
		quit(1)
		return
	var nonblack := 0
	for y in range(0, 256, 8):
		for x in range(0, 256, 8):
			var c = img.get_pixel(x, y)
			if c.r > 0.05 or c.g > 0.05 or c.b > 0.05:
				nonblack += 1
	print("PROBE size=%s nonblack_samples=%d" % [img.get_size(), nonblack])
	img.save_png("/home/biti/antigravity/magical-bell/scratch/probe_render.png")
	quit(0)
