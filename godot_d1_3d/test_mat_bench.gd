extends SceneTree
# TEMP: is per-sprite ShaderMaterial param churn the cost?

const ENTITY_HD_3D_SHADER = preload("res://shaders/entity_hd_upscaler_3d.gdshader")
const MODES = ["own_mat_churn", "shared_mat_churn", "own_mat_static", "own_std_churn"]

var root_node: Node3D
var sprites: Array = []
var mats_own: Array = []
var mat_shared: ShaderMaterial
var std_mats: Array = []
var texs: Array = []
var mode_i = -1
var win_time = 0.0
var win_frames = 0
var times = []
var cam: Camera3D

func _initialize():
	root_node = Node3D.new()
	root.add_child(root_node)
	cam = Camera3D.new()
	cam.position = Vector3(0, 20, 20)
	cam.rotation_degrees = Vector3(-45, 0, 0)
	root_node.add_child(cam)
	root_node.add_child(DirectionalLight3D.new())
	for i in range(40):
		var img = Image.create(512, 512, false, Image.FORMAT_RGBA8)
		img.fill(Color(randf(), randf(), randf(), 1.0))
		img.generate_mipmaps()
		texs.append(ImageTexture.create_from_image(img))
	mat_shared = ShaderMaterial.new()
	mat_shared.shader = ENTITY_HD_3D_SHADER
	for i in range(37):
		var spr = Sprite3D.new()
		spr.texture = texs[i % texs.size()]
		spr.pixel_size = 0.03
		var m = ShaderMaterial.new()
		m.shader = ENTITY_HD_3D_SHADER
		m.set_shader_parameter("albedo_texture", spr.texture)
		mats_own.append(m)
		spr.material_override = m
		var sm = StandardMaterial3D.new()
		sm.set_texture(StandardMaterial3D.TEXTURE_ALBEDO, spr.texture)
		std_mats.append(sm)
		sprites.append(spr)
		root_node.add_child(spr)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

func _process(delta: float) -> bool:
	win_time += delta
	win_frames += 1
	times.append(Time.get_ticks_msec())
	if times.size() > 400:
		times.pop_front()
	if win_time >= 5.0:
		times.sort()
		var p50 = times[int(times.size() * 0.5)]
		print("[MB] mode=%s fps=%.1f p50=%dms" % [MODES[max(mode_i, 0)], win_frames / win_time, p50])
		win_time = 0.0
		win_frames = 0
		times.clear()
		mode_i += 1
		if mode_i >= MODES.size():
			quit()
			return false
		match MODES[mode_i]:
			"own_mat_churn":
				for i in range(sprites.size()):
					sprites[i].material_override = mats_own[i]
			"shared_mat_churn":
				for i in range(sprites.size()):
					sprites[i].material_override = mat_shared
			"own_mat_static":
				pass
			"own_std_churn":
				for i in range(sprites.size()):
					sprites[i].material_override = std_mats[i]
	# per-frame churn: assign a new texture to each sprite and update its material params
	for i in range(sprites.size()):
		var t = texs[(i + win_frames) % texs.size()]
		match MODES[max(mode_i, 0)]:
			"own_mat_churn":
				sprites[i].texture = t
				mats_own[i].set_shader_parameter("albedo_texture", t)
				mats_own[i].set_shader_parameter("hd_enabled", true)
				mats_own[i].set_shader_parameter("upscaler_mode", 0)
				mats_own[i].set_shader_parameter("brightness", 1.0)
			"shared_mat_churn":
				sprites[i].texture = t
				mat_shared.set_shader_parameter("albedo_texture", t)
			"own_mat_static":
				pass
			"own_std_churn":
				sprites[i].texture = t
				std_mats[i].set_texture(StandardMaterial3D.TEXTURE_ALBEDO, t)
	return false
