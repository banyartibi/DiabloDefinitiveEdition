extends SceneTree

func _init():
	print("--- Rendering Corpse Test Frame ---")
	var r = get_root()

	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.1, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 1.0, 1.0)

	var vp = SubViewport.new()
	vp.size = Vector2i(512, 512)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	r.add_child(vp)

	var cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 6.0
	cam.position = Vector3(0, 10, 10 * sqrt(3))
	cam.rotation_degrees = Vector3(-30, 0, 0)
	cam.environment = env
	vp.add_child(cam)

	var floor_quad = MeshInstance3D.new()
	var f_mesh = PlaneMesh.new()
	f_mesh.size = Vector2(8, 8)
	floor_quad.mesh = f_mesh
	var f_mat = StandardMaterial3D.new()
	f_mat.albedo_color = Color(0.2, 0.2, 0.25)
	floor_quad.material_override = f_mat
	vp.add_child(floor_quad)

	var spr = Sprite3D.new()
	var test_tex_path = "res://assets/hd_sprites_omnisr/monsters/skeleton_death/dir_0_frame_14.png"
	var tex = load(test_tex_path) as Texture2D
	if tex:
		spr.texture = tex
		spr.pixel_size = 0.00674
		spr.axis = Vector3.AXIS_Y
		spr.scale = Vector3(1.0, 1.0, 2.0)
		spr.position = Vector3(0, 0.03, 0)
		vp.add_child(spr)
		print("Corpse sprite loaded: ", tex.get_size())

	for i in range(5):
		await process_frame

	var img = vp.get_texture().get_image()
	if img:
		img.save_png("/home/biti/.gemini/antigravity/brain/4427fff3-fdfb-47e3-b8be-42adea0050ce/test_corpse_flat_render.png")
		print("Saved test_corpse_flat_render.png")

	vp.queue_free()
	quit(0)
