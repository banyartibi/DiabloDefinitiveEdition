extends SceneTree
# Micro-benchmark: what exactly costs ~1.4 ms per monster texture bind in Mode 2?
# 26 sprites x 1 bind/frame, 12 rotating 512x512 textures, real entity shader.

const SHADER = preload("res://shaders/entity_hd_upscaler_3d.gdshader")

var sprites = []
var texs = []
var mats = []
var root3d = null
var phase = 0
var phase_time = 0.0
var phase_frames = 0
var idx = 0
var policies = ["NONE", "TEX", "PARAM", "TEX_PARAM", "FILTER", "PIXEL", "FULL"]

func _initialize():
	for i in range(12):
		var img = Image.create(512, 512, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.8, 0.5, 0.3, 1.0))
		img.generate_mipmaps()
		texs.append(ImageTexture.create_from_image(img))

	root3d = Node3D.new()
	root.add_child(root3d)
	var cam = Camera3D.new()
	cam.position = Vector3(0, 10, 10)
	cam.rotation_degrees = Vector3(-40, 0, 0)
	root3d.add_child(cam)

	for i in range(26):
		var spr = Sprite3D.new()
		spr.texture = texs[0]
		spr.pixel_size = 0.0029
		spr.offset = Vector2(0, 256)
		spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		spr.position = Vector3(i % 6, 0, i / 6)
		var mat = ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("albedo_texture", texs[0])
		spr.material_override = mat
		root3d.add_child(spr)
		sprites.append(spr)
		mats.append(mat)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	phase = 1
	print("[MB] policies=%s" % policies)

func _process(delta: float) -> bool:
	phase_time += delta
	phase_frames += 1
	var pol = policies[phase - 1] if phase - 1 < policies.size() else ""
	idx += 1
	var t = texs[idx % texs.size()]
	for i in range(sprites.size()):
		var spr = sprites[i]
		var mat = mats[i]
		match pol:
			"NONE":
				pass
			"TEX":
				spr.texture = t
			"PARAM":
				mat.set_shader_parameter("albedo_texture", t)
			"TEX_PARAM":
				spr.texture = t
				mat.set_shader_parameter("albedo_texture", t)
			"FILTER":
				spr.texture = t
				mat.set_shader_parameter("albedo_texture", t)
				spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			"PIXEL":
				spr.texture = t
				mat.set_shader_parameter("albedo_texture", t)
				spr.pixel_size = 0.0029
				spr.offset = Vector2(0, 256)
			"FULL":
				spr.texture = t
				mat.set_shader_parameter("albedo_texture", t)
				mat.set_shader_parameter("hd_enabled", true)
				mat.set_shader_parameter("upscaler_mode", 0)
				mat.set_shader_parameter("brightness", 1.0)
				spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				spr.pixel_size = 0.0029
				spr.offset = Vector2(0, 256)
	if phase_time >= 4.0:
		print("[MB] %s fps=%.1f" % [pol, phase_frames / phase_time])
		phase += 1
		phase_time = 0.0
		phase_frames = 0
		if phase > policies.size():
			quit()
	return false
