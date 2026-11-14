extends SceneTree

func _init() -> void:
	print("--- Running Pillar Priority Visual Test with Real Shader ---")
	var root = Node3D.new()
	get_root().add_child(root)

	var vp = SubViewport.new()
	vp.size = Vector2i(200, 200)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.0
	vp.add_child(cam)
	cam.position = Vector3(0, 3, 3)
	cam.look_at_from_position(Vector3(0, 3, 3), Vector3(0, 0, 0), Vector3.UP)

	# Pillar at (0, 0, 0)
	var p_img = Image.create(64, 128, false, Image.FORMAT_RGBA8)
	p_img.fill(Color(0, 0, 1, 1)) # Solid blue
	var p_tex = ImageTexture.create_from_image(p_img)

	var pillar_spr = Sprite3D.new()
	pillar_spr.texture = p_tex
	pillar_spr.position = Vector3(0, 0, 0)
	pillar_spr.pixel_size = 0.015
	pillar_spr.offset = Vector2(0, 64)
	pillar_spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	pillar_spr.render_priority = 0
	vp.add_child(pillar_spr)

	# Player behind pillar at (0, 0, -0.5)
	var pl_img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	pl_img.fill(Color(1, 0, 0, 1)) # Solid red
	var pl_tex = ImageTexture.create_from_image(pl_img)

	var player_spr = Sprite3D.new()
	player_spr.texture = pl_tex
	player_spr.position = Vector3(0, 0, -0.5) # Player is BEHIND pillar
	player_spr.pixel_size = 0.015
	player_spr.offset = Vector2(0, 32)
	player_spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	player_spr.render_priority = 3
	player_spr.sorting_offset = 3.0

	var shader = load("res://shaders/entity_hd_upscaler_3d.gdshader") as Shader
	var p_mat = ShaderMaterial.new()
	p_mat.shader = shader
	p_mat.render_priority = 3
	p_mat.set_shader_parameter("albedo_texture", pl_tex)
	p_mat.set_shader_parameter("hd_enabled", false)
	player_spr.material_override = p_mat

	vp.add_child(player_spr)

	for i in range(3):
		await process_frame

	var img = vp.get_texture().get_image()
	var red_count = 0
	var blue_count = 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c = img.get_pixel(x, y)
			if c.r > 0.8 and c.b < 0.2:
				red_count += 1
			elif c.b > 0.8 and c.r < 0.2:
				blue_count += 1

	print("Case A (Pillar prio 0, Player prio 3 + sorting_offset 3): Red pixels: %d, Blue pixels: %d" % [red_count, blue_count])

	# Now change pillar to render_priority 3
	pillar_spr.render_priority = 3
	for i in range(3):
		await process_frame

	var img2 = vp.get_texture().get_image()
	var red_count2 = 0
	var blue_count2 = 0
	for y in range(img2.get_height()):
		for x in range(img2.get_width()):
			var c = img2.get_pixel(x, y)
			if c.r > 0.8 and c.b < 0.2:
				red_count2 += 1
			elif c.b > 0.8 and c.r < 0.2:
				blue_count2 += 1

	print("Case B (Pillar prio 3, Player prio 3 + sorting_offset 3): Red pixels: %d, Blue pixels: %d" % [red_count2, blue_count2])
	quit(0)
