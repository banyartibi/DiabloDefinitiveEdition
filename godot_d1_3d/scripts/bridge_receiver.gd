extends Node3D

const UpscalerModelConfig = preload("res://scripts/upscaler_model_config.gd")

@export var mesh_instance: MeshInstance3D
@export var hero_light: OmniLight3D
@export var camera: Camera3D
@export var world_env: WorldEnvironment

var image_texture: ImageTexture
var shader_material: ShaderMaterial
var last_frame_id: int = -1
var time_accum: float = 0.0
var had_connected: bool = false

var d1_width: int = 2560
var d1_height: int = 1440

# User Requested Defaults:
var vsync_enabled: bool = true          # Default: ON (Smooth 144Hz Monitor Sync) - menu driven, no hotkey
var show_fps: bool = false              # Default: OFF - Settings / Graphics / Show FPS drives this (no F8)
var current_fog_mode: int = 0           # Default: 0 = OFF (pause-menu driven)
var current_color_profile: int = 0      # Default: 0 = Vanilla / OFF (pause-menu driven)
var current_upscaler_mode: int = 0      # Default: 0 = AMD FidelityFX CAS Super-Resolution (FSR) (pause-menu driven)
var current_relief_mode: int = 0        # Default: 0 = OFF (pause-menu driven)
var current_hdr_level: int = 1          # Default: 1 = Balanced Gothic Glow (1.0x) (pause-menu driven)
var hero_light_enabled: bool = true     # Default: ENABLED (pause-menu driven)

# Dynamic 3D Lights, Shadows & Particles (all live inside the GameView SubViewport)
@onready var game_view: SubViewport = $GameView
@onready var torch_container: Node3D = get_node_or_null("GameView/TorchLightsContainer")
@onready var shadow_container: Node3D = get_node_or_null("GameView/ShadowCastersContainer")
@onready var effects_container: Node3D = get_node_or_null("GameView/EffectsContainer")
@onready var directional_light: DirectionalLight3D = get_node_or_null("GameView/GothicAngledLight")
@onready var dungeon_embers: GPUParticles3D = get_node_or_null("GameView/DungeonEmbers3D")

# Godot-native global Brightness (SubViewport post-process). Independent of the C++/palette gamma pipeline.
var current_brightness_pct := 100        # Default: 100% (neutral contrast)
var brightness_material: ShaderMaterial = null
var composite_rect: TextureRect = null

var blood_splatter_scene = preload("res://scenes/effects/blood_splatter.tscn")
var bone_shards_scene = preload("res://scenes/effects/bone_shards.tscn")
var fireball_explosion_scene = preload("res://scenes/effects/fireball_explosion.tscn")
var torch_sparks_scene = preload("res://scenes/effects/torch_sparks.tscn")

var pooled_torch_lights: Array = []
var pooled_shadow_boxes: Array = []
var hero_sparks: GPUParticles3D = null
var occluder_box_mesh: BoxMesh = null

var wet_floor: bool = true              # Default: ON - pause menu driven (Wet & Reflective Cobblestone)
var playfield_zoom: float = 1.0
var left_panel_open: bool = false
var right_panel_open: bool = false
var speedbook_open: bool = false
var diablo_bridge = null
var use_gdextension: bool = false
var modern_hud_scene = preload("res://scenes/hud/d1de_hud.tscn")
var modern_hud = null
var modern_hud_enabled: bool = true     # Default: Modern Diablo: Definitive Edition Native CanvasLayer HUD
var last_is_ingame: bool = false
var last_level_idx: int = -999

# 3-Mode Display Architecture:
# Mode 0: Classic 2.5D Blit (Vanilla + 3D Relief Shader)
# Mode 1: Native Godot 2.5D Engine (Direct Godot 2D Engine, 144Hz Smooth Camera, Y-Sorted Sprites, PointLight2D)
# Mode 2: Native 3D Sandbox (Real 3D Geometry, Billboard Sprites, Q/E Orbit, PgUp/PgDn Tilt)
enum DisplayMode { ORIGINAL_25D = 0, NATIVE_25D = 1, NATIVE_3D = 2 }
var current_display_mode: int = DisplayMode.NATIVE_25D
# Track modal open/close in native modes so we can re-apply the display mode (show/hide the authentic D1 UI blit)
var last_modal_active := false


var native_25d_scene = preload("res://scenes/views/native_25d_view.tscn")
var native_25d_instance = null

# Native Godot 3D Sandbox (Mode 2)
var sandbox_scene = preload("res://scenes/sandbox/native_3d_sandbox.tscn")
var sandbox_instance = null

# Native Godot modal overlay script (D1 pause/gamemenu, dialog/store, death-restart menus)
const MODAL_SCENE = preload("res://scenes/modals/native_modal_layer.tscn")

# Native Godot 4K Main Menu & Campfire Scene (D1DE style)
var main_menu_scene = preload("res://scenes/menu/main_menu.tscn")
var main_menu_instance = null
var menu_layer: CanvasLayer = null

# Modal Dialog & Menu Overlay (for Mode 1 / Mode 2 when talking to Towners, visiting shops, or in Esc menu).
# Renders D1's own menus natively with Control nodes (see native_modal_layer.gd) instead of blitting
# D1's rasterized vanilla frame onto the mesh.
var modal_layer: CanvasLayer = null
var modal_container: Control = null
var native_modal: Control = null

# Automap Overlay (for Tab map in Native 2.5D / 3D)
var automap_layer: CanvasLayer = null
var automap_rect: TextureRect = null

# Authentic Diablo 1 / Hellfire Red Death Screen Post-Process
var death_screen_layer: CanvasLayer = null
var death_screen_rect: ColorRect = null
var death_screen_mat: ShaderMaterial = null
var death_fade: float = 0.0

var current_zoom_step: int = 1          # Default: 1.5x (Balanced View)
var zoom_step_names = [
	"1.0x (Normál / Széles Látószög)",
	"1.5x (Köztes / Kiegyensúlyozott)",
	"2.0x (Közeli / Zoomed)",
	"2.5x (Ultra Közeli / Ultra Close)",
	"3.0x (Epikus Makró / Macro Close)"
]

# Mode 0 (Classic Blit / Legacy) calibrated HDR multipliers:
# The former 1.0x level is now 3.0x (max) to prevent excessive blown-out bloom
var mode0_hdr_multipliers = [0.0, 0.35, 0.70, 1.00]

# Mode 1 (Native Godot 2.5D) next-gen vibrant HDR parameters:
var mode1_hdr_multipliers = [0.0, 1.0, 2.0, 3.0]
var mode1_glow_intensities = [0.0, 0.75, 1.10, 1.45]
var mode1_glow_blooms = [0.0, 0.35, 0.60, 0.90]
var mode1_glow_strengths = [1.0, 1.05, 1.10, 1.20]

var hdr_names = [
	"Engine HDR Glow: OFF (0.0x)",
	"Engine HDR Glow: 1.0x (Subtle Natural Glow - Default)",
	"Engine HDR Glow: 2.0x (Warm Radiant Bloom)",
	"Engine HDR Glow: 3.0x (Intense Blazing Bloom)"
]

var upscaler_names = [
	"Upscaler: xBRZ (4x/5x Vector Smoothing)",
	"Upscaler: SDF Silhouette Smoothing",
	"Upscaler: Kuwahara / Bilateral Dither Filter",
	"Upscaler: AMD FSR 1.0 (EASU + RCAS Full-Screen)",
	"Upscaler: Native 1:1 Direct Retro Pixel-Art"
]

# Neural Upscale Model for pre-baked 4x tile & sprite assets (offline GPU pipeline)
var current_tile_model: int = 0  # Default: 0 = Real-ESRGAN 4x-UltraSharp
var tile_model_names: Array = UpscalerModelConfig.MODEL_NAMES

var color_names = [
	"Vanilla (1996 Classic 32-bit - UI Untouched - Default)",
	"Dark Gothic (Deep OLED Slate Contrast)",
	"Hellish Crimson (Warm Blood-Amber)",
	"Crypt Cyan (Gothic Cold Chill)",
	"Desaturated Noir (Grimdark Film)"
]

var fog_names = [
	"Atmospheric Fog: OFF (Default)",
	"Atmospheric Fog: Crypt Mist (Subtle Dungeon Haze)",
	"Atmospheric Fog: Dense Drift (Hellfire Smoke)"
]

var relief_names = [
	"3D Surface Relief: OFF (Flat 2D)",
	"3D Surface Relief: Mode 1 (Subtle 3D)",
	"3D Surface Relief: Mode 2 (Balanced 3D Emboss)",
	"3D Surface Relief: Mode 3 (Deep 3D Embossed Relief - Default)",
	"3D Surface Relief: Mode 4 (Extreme Sculpted 3D Relief)"
]

var osd_label: Label
var osd_timer: float = 0.0
var fps_label: Label
var fps_timer: float = 0.0
var settings_poll_timer := 0.0
var frame_counter: int = 0
var current_fps: int = 0
const AudioManagerScript = preload("res://scripts/audio_manager.gd")
var audio_mgr: Node = null

func _ready():
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)

# Set up the GameView SubViewport + global brightness composite (see _setup_game_view).
	
	if ClassDB.class_exists("DiabloBridge"):
		diablo_bridge = ClassDB.instantiate("DiabloBridge")
		add_child(diablo_bridge)
		use_gdextension = true
		var mpq_dir = "/home/biti/.local/share/diasurgical/devilution"
		diablo_bridge.call_deferred("init_engine", mpq_dir)
		print("[Godot-D1 Bridge] GDExtension DiabloBridge started directly in-process!")
		
		audio_mgr = AudioManagerScript.new()
		audio_mgr.name = "D1AudioManager"
		add_child(audio_mgr)
		audio_mgr.init(diablo_bridge, self)
	
	if not hero_light:
		hero_light = get_node_or_null("HeroTorchLight")
	
	if not torch_container:
		torch_container = get_node_or_null("TorchLightsContainer")
		if not torch_container:
			torch_container = Node3D.new()
			torch_container.name = "TorchLightsContainer"
			add_child(torch_container)

	if not shadow_container:
		shadow_container = get_node_or_null("ShadowCastersContainer")
		if not shadow_container:
			shadow_container = Node3D.new()
			shadow_container.name = "ShadowCastersContainer"
			add_child(shadow_container)

	if not effects_container:
		effects_container = get_node_or_null("EffectsContainer")
		if not effects_container:
			effects_container = Node3D.new()
			effects_container.name = "EffectsContainer"
			add_child(effects_container)

	occluder_box_mesh = BoxMesh.new()
	occluder_box_mesh.size = Vector3(0.68, 0.68, 0.60)

	if hero_light:
		hero_light.visible = hero_light_enabled
		hero_light.omni_range = 2.8
		hero_light.omni_attenuation = 2.0
		hero_light.position.z = 0.35

	# Solid Flat 2D Viewport setup (pure clean fullscreen)
	if mesh_instance:
		mesh_instance.rotation_degrees = Vector3.ZERO
		mesh_instance.position = Vector3.ZERO
		if mesh_instance.material_override:
			shader_material = mesh_instance.material_override as ShaderMaterial
			update_shader_params()
	# DEBUG (dev only): startup render-path state for automated runtime tests
	print("[D1-DEBUG] ready: mesh=%s camera=%s shader_mat=%s mesh_visible=%s" % [
		mesh_instance != null, camera != null, shader_material != null,
		(mesh_instance.visible if mesh_instance else false)])
			
	if camera:
		camera.fov = 60.0
		camera.position = Vector3(0, 0, 7.8)
		camera.rotation_degrees = Vector3.ZERO
		var listener = AudioListener3D.new()
		listener.name = "D1AudioListener3D"
		camera.add_child(listener)
		listener.make_current()
		
	setup_osd()
	setup_modal_overlay()
	apply_upscaler_mode()
	update_fog_mode()
	update_torch_light()

	# Initialize Diablo IV Native CanvasLayer Modern HUD
	modern_hud = modern_hud_scene.instantiate()
	add_child(modern_hud)
	if diablo_bridge and modern_hud and modern_hud.has_method("set_bridge"):
		modern_hud.set_bridge(diablo_bridge)

	# Initialize Native Godot 4K Main Menu & D1DE Campfire Scene
	menu_layer = CanvasLayer.new()
	menu_layer.name = "NativeMainMenuLayer"
	menu_layer.layer = 130
	add_child(menu_layer)
	main_menu_instance = main_menu_scene.instantiate()
	menu_layer.add_child(main_menu_instance)
	if diablo_bridge and main_menu_instance:
		if main_menu_instance.has_method("set_bridge"):
			main_menu_instance.set_bridge(diablo_bridge)
		if main_menu_instance.has_signal("settings_saved"):
			main_menu_instance.connect("settings_saved", _on_main_menu_settings_saved)

	# Query initial D1DE & Resurrected settings from diablo.ini via bridge
	if diablo_bridge:
		if diablo_bridge.has_method("get_d1de_torchlight"):
			hero_light_enabled = bool(diablo_bridge.get_d1de_torchlight())
		elif diablo_bridge.has_method("get_resurrected_torchlight"):
			hero_light_enabled = bool(diablo_bridge.get_resurrected_torchlight())

		if diablo_bridge.has_method("get_d1de_fog_level"):
			current_fog_mode = int(diablo_bridge.get_d1de_fog_level())
		elif diablo_bridge.has_method("get_resurrected_fog_level"):
			current_fog_mode = int(diablo_bridge.get_resurrected_fog_level())

		if diablo_bridge.has_method("get_d1de_color_profile"):
			current_color_profile = int(diablo_bridge.get_d1de_color_profile())
		elif diablo_bridge.has_method("get_resurrected_color_profile"):
			current_color_profile = int(diablo_bridge.get_resurrected_color_profile())

		if diablo_bridge.has_method("get_d1de_hdr_level"):
			current_hdr_level = int(diablo_bridge.get_d1de_hdr_level())
		elif diablo_bridge.has_method("get_resurrected_hdr_level"):
			current_hdr_level = int(diablo_bridge.get_resurrected_hdr_level())

		if diablo_bridge.has_method("get_d1de_upscaler_mode"):
			current_upscaler_mode = int(diablo_bridge.get_d1de_upscaler_mode())
		elif diablo_bridge.has_method("get_resurrected_upscaler_mode"):
			current_upscaler_mode = int(diablo_bridge.get_resurrected_upscaler_mode())

		if diablo_bridge.has_method("get_d1de_relief_mode"):
			current_relief_mode = int(diablo_bridge.get_d1de_relief_mode())
		elif diablo_bridge.has_method("get_resurrected_relief_mode"):
			current_relief_mode = int(diablo_bridge.get_resurrected_relief_mode())

		if diablo_bridge.has_method("get_d1de_wet_floor"):
			wet_floor = bool(diablo_bridge.get_d1de_wet_floor())
		elif diablo_bridge.has_method("get_resurrected_wet_floor"):
			wet_floor = bool(diablo_bridge.get_resurrected_wet_floor())

		if diablo_bridge.has_method("get_d1de_tile_model"):
			current_tile_model = int(diablo_bridge.get_d1de_tile_model())
		elif diablo_bridge.has_method("get_resurrected_tile_model"):
			current_tile_model = int(diablo_bridge.get_resurrected_tile_model())

	# Initialize Native Godot 2.5D View (Mode 1)
	native_25d_instance = native_25d_scene.instantiate()
	game_view.add_child(native_25d_instance)
	native_25d_instance.diablo_bridge = diablo_bridge
	if native_25d_instance.has_method("apply_all_d1de_settings"):
		native_25d_instance.apply_all_d1de_settings(
			hero_light_enabled,
			current_fog_mode,
			current_upscaler_mode,
			current_relief_mode,
			wet_floor,
			current_hdr_level,
			current_tile_model
		)
	elif native_25d_instance.has_method("apply_all_resurrected_settings"):
		native_25d_instance.apply_all_resurrected_settings(
			hero_light_enabled,
			current_fog_mode,
			current_upscaler_mode,
			current_relief_mode,
			wet_floor,
			current_hdr_level,
			current_tile_model
		)
	native_25d_instance.deactivate()

	# Initialize Native 3D Sandbox (Mode 2)
	sandbox_instance = sandbox_scene.instantiate()
	game_view.add_child(sandbox_instance)
	sandbox_instance.diablo_bridge = diablo_bridge
	sandbox_instance.main_receiver = self
	sandbox_instance.deactivate()

	# Set up the GameView SubViewport composite + global brightness (must run so the
	# SubViewport's render target is actually displayed in the main viewport).
	_setup_game_view()

	if native_modal:
		native_modal.call("set_bridge", diablo_bridge)
		native_modal.call("set_brightness_host", self)
	
	show_osd("Diablo: Definitive Edition - Display Mode switch is rebindable (see Game Settings > Definitive Edition)", 4.5)
	print("[Godot-D1 Bridge] 3-Mode Architecture ready: [Original 2.5D] / [Native Godot 2.5D] / [Native 3D Sandbox].")

func _notification(what: int):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if use_gdextension and diablo_bridge != null:
			diablo_bridge.quit_engine()
		get_tree().quit()

func setup_osd():
	var canvas = CanvasLayer.new()
	canvas.layer = 150
	add_child(canvas)
	
	osd_label = Label.new()
	osd_label.position = Vector2(40, 40)
	osd_label.add_theme_font_size_override("font_size", 22)
	osd_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	osd_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	osd_label.add_theme_constant_override("shadow_offset_x", 2)
	osd_label.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(osd_label)
	
	fps_label = Label.new()
	fps_label.position = Vector2(40, 75)
	fps_label.add_theme_font_size_override("font_size", 18)
	fps_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0, 0.85))
	fps_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	fps_label.visible = show_fps
	canvas.add_child(fps_label)

func setup_modal_overlay():
	modal_layer = CanvasLayer.new()
	modal_layer.layer = 120 # Above 2.5D/3D world, below OSD
	modal_layer.visible = false
	add_child(modal_layer)

	modal_container = Control.new()
	modal_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_layer.add_child(modal_container)

	# Native Godot modal overlay: renders D1's menus with Control nodes.
	native_modal = MODAL_SCENE.instantiate()
	native_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	native_modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	native_modal.visible = false
	modal_container.add_child(native_modal)

	# Transparent Automap Layer (Layer 115: Above 2.5D/3D world, below modals)
	automap_layer = CanvasLayer.new()
	automap_layer.layer = 115
	automap_layer.visible = false
	add_child(automap_layer)

	automap_rect = TextureRect.new()
	automap_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	automap_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	automap_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	automap_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	automap_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	automap_layer.add_child(automap_rect)

	# Authentic Red Death Screen Layer (Layer 118: Above world & automap, below modal layer)
	death_screen_layer = CanvasLayer.new()
	death_screen_layer.layer = 118
	death_screen_layer.visible = false
	add_child(death_screen_layer)

	var death_shader = load("res://shaders/death_red_screen.gdshader")
	if death_shader:
		death_screen_mat = ShaderMaterial.new()
		death_screen_mat.shader = death_shader
		death_screen_mat.set_shader_parameter("intensity", 0.0)

		death_screen_rect = ColorRect.new()
		death_screen_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		death_screen_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		death_screen_rect.material = death_screen_mat
		death_screen_layer.add_child(death_screen_rect)

func update_torch_light():
	if hero_light:
		hero_light.visible = hero_light_enabled and current_display_mode == DisplayMode.ORIGINAL_25D
		hero_light.light_color = Color(1.0, 0.75, 0.42, 1.0) # Warm gothic amber candlelight
		hero_light.light_energy = 0.55
		hero_light.light_specular = 0.0 # Pure diffuse, zero sharp directional glints!
		hero_light.omni_range = 3.2
		hero_light.omni_attenuation = 1.4 # Soft, even 360-degree ambient falloff
		hero_light.shadow_enabled = false
	if native_25d_instance and native_25d_instance.has_method("set_soft_torchlight"):
		native_25d_instance.set_soft_torchlight(hero_light_enabled)

func show_osd(text: String, duration: float = 2.5):
	if osd_label:
		osd_label.text = text
		osd_timer = duration

func apply_zoom_step(old_step: int, new_step: int):
	if camera:
		camera.fov = 60.0
		
	if new_step > old_step:
		for i in range(new_step - old_step):
			send_input_to_d1(4, 0, 0, 0, 0) # D1 ZoomInMode
	elif new_step < old_step:
		for i in range(old_step - new_step):
			send_input_to_d1(5, 0, 0, 0, 0) # D1 ZoomOutMode
			
	playfield_zoom = 1.0 # Native D1 engine scaling for all 5 steps!
	update_shader_params()
	show_osd("[Zoom] " + zoom_step_names[new_step], 1.2)

func apply_upscaler_mode():
	# 3D content now renders inside the GameView SubViewport, so upscaling must target it.
	var vp = game_view if game_view else get_viewport()
	if not vp: return
	
	if current_display_mode != DisplayMode.ORIGINAL_25D:
		# Mode 1 (Native 2.5D) and Mode 2 (Pure 3D Sandbox) use native Godot 2D/3D pipelines.
		# Mode 1 runs in 2D and must ALWAYS use BILINEAR on the SubViewport to prevent FSR2 edge artifacts / grid seams.
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 1.0
	else:
		# Mode 0 (3D Quad Blit): The shader itself handles CAS, Bicubic Spline, and Anime4K.
		# Viewport scaling must remain clean Bilinear to prevent FSR/FSR2 motion-vector grid seams and double-upscaling.
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 1.0

	if native_25d_instance and native_25d_instance.has_method("set_upscaler_mode"):
		native_25d_instance.set_upscaler_mode(current_upscaler_mode)

	update_shader_params()

# --- GameView SubViewport + global Brightness composite ----------------------
# All game 3D/2D content renders inside the GameView SubViewport; its render target is
# composited onto a full-screen TextureRect in the main viewport with a brightness shader.
# UI CanvasLayers (HUD=100, automap=115, modal=120, OSD=150) stay above and are unaffected.
func _setup_game_view():
	if not game_view:
		return
	var vp_size = get_viewport().get_visible_rect().size
	game_view.size = Vector2i(vp_size) if (vp_size.x > 0 and vp_size.y > 0) else Vector2i(2560, 1440)
	game_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	game_view.use_hdr_2d = true
	# Mirror the project rendering settings onto GameView (they only apply to the root window by default).
	game_view.msaa_3d = 2
	game_view.screen_space_aa = 1
	game_view.snap_2d_transforms_to_pixel = false
	game_view.snap_2d_vertices_to_pixel = false
	# Positional audio inside the subviewport (required for AudioListener3D to work there).
	game_view.audio_listener_enable_2d = true
	game_view.audio_listener_enable_3d = true

	var comp_layer = CanvasLayer.new()
	comp_layer.name = "GameComposite"
	comp_layer.layer = 0
	add_child(comp_layer)

	composite_rect = TextureRect.new()
	composite_rect.name = "GameViewTexture"
	composite_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	composite_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	composite_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	composite_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	composite_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	brightness_material = ShaderMaterial.new()
	var shd = load("res://shaders/view_brightness.gdshader")
	if shd:
		brightness_material.shader = shd
	_apply_brightness()
	_apply_gamma()
	brightness_material.set_shader_parameter("color_profile", current_color_profile if current_display_mode != DisplayMode.ORIGINAL_25D else 0)
	composite_rect.material = brightness_material

	composite_rect.texture = game_view.get_texture()
	comp_layer.add_child(composite_rect)

func get_brightness() -> int:
	return current_brightness_pct

# Godot-native global brightness (percent). Independent of the C++/palette gamma pipeline.
func set_brightness(pct: int) -> void:
	current_brightness_pct = clampi(pct, 50, 150)
	_apply_brightness()

func _apply_brightness():
	if brightness_material:
		var b_uniform := 1.30
		if current_brightness_pct >= 100:
			b_uniform = remap(float(current_brightness_pct), 100.0, 150.0, 1.30, 1.90)
		else:
			b_uniform = remap(float(current_brightness_pct), 50.0, 100.0, 0.70, 1.30)
		brightness_material.set_shader_parameter("brightness", b_uniform)

var current_gamma_pct: int = 50

func get_gamma_pct() -> int:
	return current_gamma_pct

func set_gamma_pct(pct: int) -> void:
	current_gamma_pct = clampi(pct, 30, 100)
	_apply_gamma()

func _apply_gamma():
	if brightness_material:
		var g_uniform := 1.30
		if current_gamma_pct >= 50:
			g_uniform = remap(float(current_gamma_pct), 50.0, 100.0, 1.30, 2.10)
		else:
			g_uniform = remap(float(current_gamma_pct), 30.0, 50.0, 0.85, 1.30)
		brightness_material.set_shader_parameter("gamma", g_uniform)

var hd_graphics_enabled: bool = true

func get_hd_graphics_enabled() -> bool:
	if native_25d_instance and native_25d_instance.has_method("get_hd_graphics_enabled"):
		return native_25d_instance.get_hd_graphics_enabled()
	return hd_graphics_enabled

func set_hd_graphics_enabled(enabled: bool) -> void:
	hd_graphics_enabled = enabled
	if native_25d_instance and native_25d_instance.has_method("set_hd_graphics_enabled"):
		native_25d_instance.set_hd_graphics_enabled(enabled)

func toggle_hd_graphics() -> bool:
	set_hd_graphics_enabled(not get_hd_graphics_enabled())
	return get_hd_graphics_enabled()

func get_tile_model_index() -> int:
	if native_25d_instance and native_25d_instance.has_method("get_tile_model"):
		return int(native_25d_instance.get_tile_model())
	return current_tile_model

func set_tile_model(model_id: int) -> void:
	current_tile_model = clampi(model_id, 0, UpscalerModelConfig.get_model_count() - 1)
	if diablo_bridge and diablo_bridge.has_method("set_d1de_tile_model"):
		diablo_bridge.set_d1de_tile_model(current_tile_model)
		if diablo_bridge.has_method("save_settings"):
			diablo_bridge.save_settings()
	elif diablo_bridge and diablo_bridge.has_method("set_resurrected_tile_model"):
		diablo_bridge.set_resurrected_tile_model(current_tile_model)
		if diablo_bridge.has_method("save_settings"):
			diablo_bridge.save_settings()
	if native_25d_instance and native_25d_instance.has_method("set_tile_model"):
		native_25d_instance.set_tile_model(current_tile_model)
	show_osd("Tile Model: " + UpscalerModelConfig.get_model_display_name(current_tile_model), 2.5)

func _apply_environment_glow():
	if not world_env or not world_env.environment:
		return
	var env = world_env.environment
	var is_on = (current_hdr_level > 0)
	env.glow_enabled = is_on
	if not is_on:
		return

	if current_display_mode == DisplayMode.ORIGINAL_25D:
		# Mode 0: Blit / legacy 3D quad view
		# Scaled so that 3.0x is equal to former 1.0x (no more blown-out blinding white fog)
		var m0 = mode0_hdr_multipliers[current_hdr_level]
		env.glow_hdr_threshold = 0.98
		env.glow_hdr_scale = 2.0
		env.glow_intensity = 0.85 * m0
		env.glow_bloom = 0.35 * m0
		env.glow_strength = 1.15
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		env.set("glow_levels/1", 0.0)
		env.set("glow_levels/2", 0.8)
		env.set("glow_levels/3", 0.4)
		env.set("glow_levels/4", 0.1)
		env.set("glow_levels/5", 0.0)
	elif current_display_mode == DisplayMode.NATIVE_25D:
		# Mode 1: Native Godot 2.5D View
		# Rich, multi-octave vibrant bloom on torches, braziers, spells and loot beams
		env.glow_hdr_threshold = 0.90
		env.glow_hdr_scale = 2.0
		env.glow_intensity = mode1_glow_intensities[current_hdr_level]
		env.glow_bloom = mode1_glow_blooms[current_hdr_level]
		env.glow_strength = mode1_glow_strengths[current_hdr_level]
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		env.set("glow_levels/1", 0.45)
		env.set("glow_levels/2", 0.35)
		env.set("glow_levels/3", 0.25)
		env.set("glow_levels/4", 0.15)
		env.set("glow_levels/5", 0)
	else:
		# Mode 2: Native 3D Sandbox
		env.glow_hdr_threshold = 0.95
		env.glow_intensity = 0.6
		env.glow_bloom = 0.3

func update_shader_params():
	if shader_material:
		shader_material.set_shader_parameter("color_profile", current_color_profile)
		shader_material.set_shader_parameter("upscaler_mode", current_upscaler_mode)
		shader_material.set_shader_parameter("relief_mode", current_relief_mode)
		shader_material.set_shader_parameter("hdr_glow_mult", mode0_hdr_multipliers[current_hdr_level])
		shader_material.set_shader_parameter("wet_floor", wet_floor)
		shader_material.set_shader_parameter("playfield_zoom", playfield_zoom)
		shader_material.set_shader_parameter("left_panel_open", left_panel_open)
		shader_material.set_shader_parameter("right_panel_open", right_panel_open)
		if diablo_bridge and diablo_bridge.has_method("get_left_panel_rect"):
			var lp = diablo_bridge.get_left_panel_rect()
			var rp = diablo_bridge.get_right_panel_rect()
			shader_material.set_shader_parameter("left_panel_rect", Vector4(lp.position.x, lp.position.y, lp.size.x, lp.size.y))
			shader_material.set_shader_parameter("right_panel_rect", Vector4(rp.position.x, rp.position.y, rp.size.x, rp.size.y))
		shader_material.set_shader_parameter("hide_vanilla_hud", modern_hud_enabled and last_is_ingame)

	if brightness_material:
		brightness_material.set_shader_parameter("color_profile", current_color_profile if current_display_mode != DisplayMode.ORIGINAL_25D else 0)
		brightness_material.set_shader_parameter("upscaler_mode", current_upscaler_mode)
		var is_town = (last_level_idx == 0) if last_level_idx != -999 else (diablo_bridge != null and diablo_bridge.has_method("get_current_level") and diablo_bridge.get_current_level() == 0)
		brightness_material.set_shader_parameter("is_town", is_town)
		_apply_brightness()
		_apply_gamma()

	if directional_light:
		directional_light.light_color = Color.WHITE if current_color_profile == 0 else Color(0.96, 0.78, 0.50, 1)

	_apply_environment_glow()

	if native_25d_instance:
		if native_25d_instance.has_method("set_relief_mode"):
			native_25d_instance.set_relief_mode(current_relief_mode)
		if native_25d_instance.has_method("set_wet_floor"):
			native_25d_instance.set_wet_floor(wet_floor)
		if native_25d_instance.has_method("set_hdr_level"):
			native_25d_instance.set_hdr_level(current_hdr_level)

func update_fog_mode():
	if world_env and world_env.environment:
		var env = world_env.environment
		if current_fog_mode == 0:
			env.volumetric_fog_enabled = false
		elif current_fog_mode == 1:
			# Crypt Mist (Subtle atmospheric dungeon haze - Default)
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = 0.016
			env.volumetric_fog_emission = Color(0.02, 0.02, 0.02, 1)
			env.volumetric_fog_emission_energy = 0.22
		elif current_fog_mode == 2:
			# Dense Drift (Hellfire Smoke)
			env.volumetric_fog_enabled = true
			env.volumetric_fog_density = 0.038
			env.volumetric_fog_emission = Color(0.06, 0.03, 0.015, 1)
			env.volumetric_fog_emission_energy = 0.35

	if dungeon_embers:
		var is_town = (last_level_idx == 0) if last_level_idx != -999 else (diablo_bridge != null and diablo_bridge.has_method("get_current_level") and diablo_bridge.get_current_level() == 0)
		var should_emit = not is_town and last_is_ingame and current_fog_mode > 0 and current_display_mode == DisplayMode.ORIGINAL_25D
		dungeon_embers.emitting = should_emit
		dungeon_embers.visible = should_emit

	if native_25d_instance and native_25d_instance.has_method("set_atmospheric_fog"):
		native_25d_instance.set_atmospheric_fog(current_fog_mode)

# --- DEBUG (dev only): external screenshot + state dump trigger --------------
# Touch /tmp/d1_dbg_shot_req to capture a viewport PNG and log the current
# modal/options state. Used by automated runtime tests of the native Options
# panel; the file is never created during normal play.
var _dbg_shot_count := 0

func _dbg_capture() -> void:
	_dbg_shot_count += 1
	var out_path := "/tmp/d1_dbg_shot_%02d.png" % _dbg_shot_count
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_path)
	print("[D1-DEBUG] screenshot saved: ", out_path)
	if diablo_bridge != null and diablo_bridge.has_method("is_modal_active"):
		var modal: bool = diablo_bridge.is_modal_active()
		var mtype := -1
		var sel := -1
		var item_texts := ""
		if modal:
			if diablo_bridge.has_method("get_modal_type"):
				mtype = diablo_bridge.get_modal_type()
			if diablo_bridge.has_method("get_modal_selection_index"):
				sel = diablo_bridge.get_modal_selection_index()
			if diablo_bridge.has_method("get_current_menu_items"):
				for d in diablo_bridge.get_current_menu_items():
					item_texts += str(d.get("text", "")) + " | "
		print("[D1-DEBUG] modal=%s type=%d sel=%d items=[%s]" % [modal, mtype, sel, item_texts])
	if diablo_bridge != null and diablo_bridge.has_method("get_music_volume"):
		print("[D1-DEBUG] options music_vol=%d sound_vol=%d gamma=%d speed=%d brightness=%d" % [
			diablo_bridge.get_music_volume(),
			diablo_bridge.get_sound_volume(),
			diablo_bridge.get_gamma(),
			diablo_bridge.get_speed(),
	current_brightness_pct])
	DirAccess.remove_absolute("/tmp/d1_dbg_shot_req")

func _process(delta: float):
	time_accum += delta
	frame_counter += 1
	fps_timer += delta

	# DEBUG trigger (see _dbg_capture above)
	if FileAccess.file_exists("/tmp/d1_dbg_shot_req"):
		_dbg_capture()
	
	if hero_light and hero_light_enabled and current_display_mode == DisplayMode.ORIGINAL_25D:
		# Organic soft torch breathing flicker
		var flicker = 0.50 + 0.06 * sin(time_accum * 4.8) * cos(time_accum * 2.3)
		hero_light.light_energy = flicker
	
	if fps_timer >= 1.0:
		current_fps = frame_counter
		frame_counter = 0
		fps_timer = 0.0
		if fps_label and fps_label.visible:
			fps_label.text = "Godot 4.7.2 Forward+ Vulkan: %d FPS (RX 6800 XT)" % current_fps

	# Poll Definitive Edition (D1DE) + Graphics settings from C++ (~4 Hz). Menu-driven changes
	# (pause menu / Game Settings) apply directly - no effect hotkeys left.
	if diablo_bridge != null and diablo_bridge.has_method("get_vsync_enabled"):
		settings_poll_timer += delta
		if settings_poll_timer >= 0.25:
			settings_poll_timer = 0.0
			var new_disp = -1
			if diablo_bridge.has_method("get_d1de_display_mode"):
				new_disp = int(diablo_bridge.get_d1de_display_mode())
			elif diablo_bridge.has_method("get_resurrected_display_mode"):
				new_disp = int(diablo_bridge.get_resurrected_display_mode())
			if new_disp != current_display_mode and new_disp >= 0 and new_disp < 3:
				switch_display_mode(new_disp)

			var new_vs = bool(diablo_bridge.get_vsync_enabled())
			if new_vs != vsync_enabled:
				vsync_enabled = new_vs
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if new_vs else DisplayServer.VSYNC_DISABLED)
				show_osd("V-Sync: " + ("ENABLED (144Hz Smooth)" if new_vs else "DISABLED (Uncapped FPS)"), 2.5)
			var new_fps = bool(diablo_bridge.get_show_fps())
			if new_fps != show_fps:
				show_fps = new_fps
				_update_fps_label()

			var new_torch = hero_light_enabled
			if diablo_bridge.has_method("get_d1de_torchlight"):
				new_torch = bool(diablo_bridge.get_d1de_torchlight())
			elif diablo_bridge.has_method("get_resurrected_torchlight"):
				new_torch = bool(diablo_bridge.get_resurrected_torchlight())
			if new_torch != hero_light_enabled:
				hero_light_enabled = new_torch
				update_torch_light()
				show_osd("Dungeon Soft Torchlight: " + ("ENABLED (Warm Candlelight)" if new_torch else "DISABLED"), 2.5)

			var new_fog = current_fog_mode
			if diablo_bridge.has_method("get_d1de_fog_level"):
				new_fog = int(diablo_bridge.get_d1de_fog_level())
			elif diablo_bridge.has_method("get_resurrected_fog_level"):
				new_fog = int(diablo_bridge.get_resurrected_fog_level())
			if new_fog != current_fog_mode and new_fog >= 0 and new_fog < fog_names.size():
				current_fog_mode = new_fog
				update_fog_mode()
				show_osd(fog_names[current_fog_mode], 2.5)

			var new_color = current_color_profile
			if diablo_bridge.has_method("get_d1de_color_profile"):
				new_color = int(diablo_bridge.get_d1de_color_profile())
			elif diablo_bridge.has_method("get_resurrected_color_profile"):
				new_color = int(diablo_bridge.get_resurrected_color_profile())
			if new_color != current_color_profile and new_color >= 0 and new_color < color_names.size():
				current_color_profile = new_color
				update_shader_params()
				show_osd("Color Profile: " + color_names[current_color_profile], 2.5)

			var new_hdr = current_hdr_level
			if diablo_bridge.has_method("get_d1de_hdr_level"):
				new_hdr = int(diablo_bridge.get_d1de_hdr_level())
			elif diablo_bridge.has_method("get_resurrected_hdr_level"):
				new_hdr = int(diablo_bridge.get_resurrected_hdr_level())
			if new_hdr != current_hdr_level and new_hdr >= 0 and new_hdr < hdr_names.size():
				current_hdr_level = new_hdr
				update_shader_params()
				show_osd(hdr_names[current_hdr_level], 2.5)

			var new_ups = current_upscaler_mode
			if diablo_bridge.has_method("get_d1de_upscaler_mode"):
				new_ups = int(diablo_bridge.get_d1de_upscaler_mode())
			elif diablo_bridge.has_method("get_resurrected_upscaler_mode"):
				new_ups = int(diablo_bridge.get_resurrected_upscaler_mode())
			if new_ups != current_upscaler_mode and new_ups >= 0 and new_ups < upscaler_names.size():
				current_upscaler_mode = new_ups
				apply_upscaler_mode()
				show_osd(upscaler_names[current_upscaler_mode], 2.5)

			var new_relief = current_relief_mode
			if diablo_bridge.has_method("get_d1de_relief_mode"):
				new_relief = int(diablo_bridge.get_d1de_relief_mode())
			elif diablo_bridge.has_method("get_resurrected_relief_mode"):
				new_relief = int(diablo_bridge.get_resurrected_relief_mode())
			if new_relief != current_relief_mode and new_relief >= 0 and new_relief < relief_names.size():
				current_relief_mode = new_relief
				update_shader_params()
				show_osd(relief_names[current_relief_mode], 2.5)

			var new_wet = wet_floor
			if diablo_bridge.has_method("get_d1de_wet_floor"):
				new_wet = bool(diablo_bridge.get_d1de_wet_floor())
			elif diablo_bridge.has_method("get_resurrected_wet_floor"):
				new_wet = bool(diablo_bridge.get_resurrected_wet_floor())
			if new_wet != wet_floor:
				wet_floor = new_wet
				update_shader_params()

			# Poll tile model (neural upscale model for pre-baked 4x assets)
			var new_tile_model = current_tile_model
			if diablo_bridge.has_method("get_d1de_tile_model"):
				new_tile_model = int(diablo_bridge.get_d1de_tile_model())
			elif diablo_bridge.has_method("get_resurrected_tile_model"):
				new_tile_model = int(diablo_bridge.get_resurrected_tile_model())
			if new_tile_model != current_tile_model and new_tile_model >= 0 and new_tile_model < tile_model_names.size():
				current_tile_model = new_tile_model
				if native_25d_instance and native_25d_instance.has_method("set_tile_model"):
					native_25d_instance.set_tile_model(current_tile_model)
				show_osd("Tile Model: " + tile_model_names[current_tile_model], 2.5)
	if osd_timer > 0.0:
		osd_timer -= delta
		if osd_timer <= 0.0 and osd_label:
			osd_label.text = ""

	if game_view:
		var root_vp_size = Vector2i(get_viewport().get_visible_rect().size)
		if root_vp_size.x > 0 and root_vp_size.y > 0 and game_view.size != root_vp_size:
			game_view.size = root_vp_size

	# Authentic Red Death Screen post-processing update
	if diablo_bridge and diablo_bridge.has_method("is_player_dead"):
		var is_dead = diablo_bridge.is_player_dead()
		if is_dead:
			death_fade = minf(death_fade + delta * 2.5, 1.0)
			if death_screen_layer:
				death_screen_layer.visible = true
			if death_screen_mat:
				death_screen_mat.set_shader_parameter("intensity", death_fade)
		else:
			death_fade = maxf(death_fade - delta * 3.0, 0.0)
			if death_fade <= 0.0 and death_screen_layer:
				death_screen_layer.visible = false
			elif death_screen_mat:
				death_screen_mat.set_shader_parameter("intensity", death_fade)

	if use_gdextension and diablo_bridge != null:
		var quit_req = diablo_bridge.is_quit_requested()
		var eng_run = diablo_bridge.is_engine_running()
		if quit_req or (had_connected and not eng_run):
			print("[Godot-D1 Bridge] DevilutionX engine requested exit. Terminating Godot process cleanly... [diag: is_quit_requested=%s, is_engine_running=%s, had_connected=%s]" % [quit_req, eng_run, had_connected])
			diablo_bridge.quit_engine()
			get_tree().quit()
			return

		# Poll and process native Godot audio events
		if audio_mgr and diablo_bridge.has_method("poll_audio_events"):
			var audio_events = diablo_bridge.poll_audio_events()
			if audio_events.size() > 0:
				var player_tile = diablo_bridge.get_player_tile_pos() if diablo_bridge.has_method("get_player_tile_pos") else Vector2i(25, 25)
				audio_mgr.process_audio_events(audio_events, player_tile)

		if diablo_bridge.is_engine_ready():
			if not had_connected:
				had_connected = true
				print("[Godot-D1 Bridge] In-Process Engine Connected! Streaming live frames to 3D Viewport.")
				if modern_hud and modern_hud.has_method("set_bridge"):
					modern_hud.set_bridge(diablo_bridge)
				if modern_hud_enabled:
					diablo_bridge.set_vanilla_hud_hidden(true)
				if native_25d_instance:
					native_25d_instance.diablo_bridge = diablo_bridge
				if sandbox_instance:
					sandbox_instance.diablo_bridge = diablo_bridge
				if native_modal:
					native_modal.call("set_bridge", diablo_bridge)
				if main_menu_instance and main_menu_instance.has_method("set_bridge"):
					main_menu_instance.set_bridge(diablo_bridge)

			var is_ingame = diablo_bridge.is_game_running() if diablo_bridge.has_method("is_game_running") else false
			if menu_layer:
				menu_layer.visible = not is_ingame
			if main_menu_instance:
				main_menu_instance.visible = not is_ingame

			var cur_frame_id = diablo_bridge.get_frame_id()
			if cur_frame_id != last_frame_id:
				last_frame_id = cur_frame_id
				if is_ingame and current_display_mode == DisplayMode.ORIGINAL_25D:
					var pixel_bytes = diablo_bridge.get_frame_bytes()
					d1_width = diablo_bridge.get_frame_width()
					d1_height = diablo_bridge.get_frame_height()
					if pixel_bytes.size() == d1_width * d1_height * 4:
						update_frame_texture(d1_width, d1_height, pixel_bytes)
					
			var new_left = diablo_bridge.is_left_panel_open()
			var new_right = diablo_bridge.is_right_panel_open()
			var new_speedbook = diablo_bridge.is_speedbook_open() if diablo_bridge.has_method("is_speedbook_open") else false
			if new_left != left_panel_open or new_right != right_panel_open or new_speedbook != speedbook_open or is_ingame != last_is_ingame:
				left_panel_open = new_left
				right_panel_open = new_right
				speedbook_open = new_speedbook
				var ingame_changed = (is_ingame != last_is_ingame)
				last_is_ingame = is_ingame
				update_shader_params()
				if ingame_changed:
					apply_display_mode()
			if diablo_bridge.has_method("get_current_level"):
				var cur_lvl = diablo_bridge.get_current_level()
				if cur_lvl != last_level_idx:
					last_level_idx = cur_lvl
					if brightness_material:
						brightness_material.set_shader_parameter("is_town", cur_lvl == 0)
					if dungeon_embers and current_display_mode == DisplayMode.ORIGINAL_25D:
						var is_dungeon = (cur_lvl > 0 and is_ingame)
						dungeon_embers.emitting = is_dungeon
						dungeon_embers.visible = is_dungeon
			if diablo_bridge.has_method("get_zoom_mode"):
				var cur_zoom = diablo_bridge.get_zoom_mode()
				if cur_zoom >= 0 and cur_zoom < zoom_step_names.size() and cur_zoom != current_zoom_step:
					current_zoom_step = cur_zoom

			# Modal dialog & menu overlay for Native 2.5D / 3D views.
			# Native modes render D1's authentic UI (pause/death/talk/store) with Godot Control nodes
			# (native_modal_layer.gd); the world view does not need to rebuild.
			if modal_layer and diablo_bridge.has_method("is_modal_active"):
				var modal_active = diablo_bridge.is_modal_active()
				var should_show_modal = modal_active and (current_display_mode != DisplayMode.ORIGINAL_25D or modern_hud_enabled)
				if modal_layer.visible != should_show_modal:
					modal_layer.visible = should_show_modal
				last_modal_active = modal_active


			# Transparent Automap Overlay for Native 2.5D / 3D views
			if automap_layer and diablo_bridge.has_method("is_automap_active"):
				var map_active = diablo_bridge.is_automap_active()
				if current_display_mode != DisplayMode.ORIGINAL_25D and map_active:
					automap_layer.visible = true
					if diablo_bridge.has_method("get_automap_texture"):
						var map_tex = diablo_bridge.get_automap_texture()
						if map_tex:
							automap_rect.texture = map_tex
				else:
					automap_layer.visible = false

			# Dynamic 3D Lights & Native Particles (Mode 0 only)
			if is_ingame and current_display_mode == DisplayMode.ORIGINAL_25D:
				update_dynamic_lighting(delta)
				process_visual_events()
			else:
				if hero_light:
					hero_light.visible = false
				for tl in pooled_torch_lights:
					tl.visible = false
		return
			
	if not FileAccess.file_exists("/dev/shm/d1_godot_frame"):
		if had_connected:
			get_tree().quit()
		return
		
	var file = FileAccess.open("/dev/shm/d1_godot_frame", FileAccess.READ)
	if not file:
		if had_connected:
			get_tree().quit()
		return
		
	var magic = file.get_32()
	if magic == 0xDEADBEEF or magic == 0:
		get_tree().quit()
		return
		
	if magic != 0x44315242: # "D1RB"
		return
		
	had_connected = true
		
	var _version = file.get_32()
	d1_width = file.get_32()
	d1_height = file.get_32()
	var _pitch = file.get_32()
	var frame_id = file.get_32()
	var _timestamp = file.get_32()
	var _px = file.get_float()
	var _py = file.get_float()
	var _zoom_mode = file.get_32()
	var _torch_count = file.get_32()
	
	# Read UI panel flags exported from DevilutionX (torches[0].normX and normY)
	var left_p = file.get_float()
	var right_p = file.get_float()
	var new_left = (left_p > 0.5)
	var new_right = (right_p > 0.5)
	if new_left != left_panel_open or new_right != right_panel_open:
		left_panel_open = new_left
		right_panel_open = new_right
		update_shader_params()
	
	# Skip to payload at 4096 bytes (4KB aligned page)
	file.seek(4096)
	
	if frame_id != last_frame_id:
		last_frame_id = frame_id
		var pixel_bytes = file.get_buffer(d1_width * d1_height * 4)
		if pixel_bytes.size() == d1_width * d1_height * 4:
			update_frame_texture(d1_width, d1_height, pixel_bytes)

# DEBUG (dev only): frame-update tracing for automated runtime tests
var _dbg_frame_updates := 0

func update_frame_texture(w: int, h: int, bytes: PackedByteArray):
	_dbg_frame_updates += 1
	if _dbg_frame_updates <= 3 or _dbg_frame_updates % 600 == 0:
		print("[D1-DEBUG] frame_update #%d w=%d h=%d bytes=%d shader_mat_bound=%s tex_size=(%d,%d)" % [
			_dbg_frame_updates, w, h, bytes.size(), shader_material != null,
			(image_texture.get_width() if image_texture else 0),
			(image_texture.get_height() if image_texture else 0)])
	var img = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes)
	if not img:
		return
		
	if not image_texture or image_texture.get_width() != w or image_texture.get_height() != h:
		image_texture = ImageTexture.create_from_image(img)
		if shader_material:
			shader_material.set_shader_parameter("d1_texture", image_texture)
	else:
		image_texture.update(img)

func get_game_mouse_pos(screen_pos: Vector2, vp_size: Vector2) -> Vector2i:
	var norm_x = screen_pos.x / vp_size.x
	var norm_y = screen_pos.y / vp_size.y
	var game_x = int(clamp(norm_x * float(d1_width), 0.0, float(d1_width - 1)))
	var game_y = int(clamp(norm_y * float(d1_height), 0.0, float(d1_height - 1)))
	return Vector2i(game_x, game_y)

func _update_fps_label() -> void:
	# Mode 0 uses DevilutionX's own DrawFPS meter inside the authentic blit texture;
	# Native modes use the Godot engine FPS label.
	if fps_label:
		fps_label.visible = show_fps and current_display_mode != DisplayMode.ORIGINAL_25D

func apply_display_mode():
	var is_ingame = diablo_bridge.is_game_running() if (diablo_bridge and diablo_bridge.has_method("is_game_running")) else false
	_update_fps_label()

	# If the engine is in menus, hero creation, cutscenes or title screen:
	# Always ensure classic blit mesh is visible and interactive!
	if not is_ingame:
		if native_25d_instance:
			native_25d_instance.deactivate()
		if sandbox_instance:
			sandbox_instance.deactivate()
		if modal_layer:
			modal_layer.visible = false
		if automap_layer:
			automap_layer.visible = false
		if mesh_instance:
			mesh_instance.visible = true
		if hero_light:
			hero_light.visible = false
		if torch_container:
			torch_container.visible = false
		if effects_container:
			effects_container.visible = false
		if directional_light:
			directional_light.visible = true
		if dungeon_embers:
			dungeon_embers.emitting = false
			dungeon_embers.visible = false
		if world_env and world_env.environment:
			world_env.environment.volumetric_fog_enabled = false
			world_env.environment.glow_enabled = false
		if camera:
			camera.make_current()
		return

	# In-game mode activation:
	if native_25d_instance:
		native_25d_instance.deactivate()
	if sandbox_instance:
		sandbox_instance.deactivate()

	if current_display_mode == DisplayMode.ORIGINAL_25D:
		# Mode 0: Classic 2.5D Blit (Vanilla + PBR Relief Shader)
		if modal_layer:
			modal_layer.visible = false
		if automap_layer:
			automap_layer.visible = false
		if mesh_instance:
			mesh_instance.visible = true
		if hero_light:
			hero_light.visible = hero_light_enabled
		if torch_container:
			torch_container.visible = true
		if effects_container:
			effects_container.visible = true
		if directional_light:
			directional_light.visible = true
			directional_light.light_color = Color.WHITE if current_color_profile == 0 else Color(0.96, 0.78, 0.50, 1)
		if dungeon_embers:
			var is_town = (last_level_idx == 0) if last_level_idx != -999 else (diablo_bridge != null and diablo_bridge.has_method("get_current_level") and diablo_bridge.get_current_level() == 0)
			var should_emit = not is_town and is_ingame and current_fog_mode > 0
			dungeon_embers.emitting = should_emit
			dungeon_embers.visible = should_emit
		_apply_environment_glow()
		update_fog_mode()
		# Mode 0 uses 3D QuadMesh: re-enable 3D anti-aliasing on SubViewport
		if game_view:
			game_view.msaa_3d = 2
			game_view.screen_space_aa = 1
		if brightness_material:
			brightness_material.set_shader_parameter("color_profile", 0)
		if camera:
			camera.make_current()
		show_osd("Display Mode 1/3: Classic 2.5D Blit (Vanilla + 3D Relief Shader)", 3.5)

	elif current_display_mode == DisplayMode.NATIVE_25D:
		# Mode 1: Native Godot 2.5D Engine (Smooth 144Hz Camera, Y-Sorted Sprites, PointLight2D)
		if camera:
			camera.current = false
		if mesh_instance:
			mesh_instance.visible = false
		if hero_light:
			hero_light.visible = false
		if torch_container:
			torch_container.visible = false
		if shadow_container:
			shadow_container.visible = false
		if effects_container:
			effects_container.visible = false
			for child in effects_container.get_children():
				child.queue_free()
		for tl in pooled_torch_lights:
			tl.visible = false
		if directional_light:
			directional_light.visible = false
		if dungeon_embers:
			dungeon_embers.emitting = false
			dungeon_embers.visible = false
		if world_env and world_env.environment:
			world_env.environment.volumetric_fog_enabled = false
		# Mode 1 is pure 2D: disable 3D anti-aliasing on SubViewport (saves GPU time)
		if game_view:
			game_view.msaa_3d = 0
			game_view.screen_space_aa = 0
		_apply_environment_glow()
		if brightness_material:
			brightness_material.set_shader_parameter("color_profile", current_color_profile)
		if modal_layer and diablo_bridge and diablo_bridge.has_method("is_modal_active"):
			modal_layer.visible = diablo_bridge.is_modal_active()
		if native_25d_instance:
			if diablo_bridge and diablo_bridge.has_method("get_d1de_tile_model"):
				current_tile_model = int(diablo_bridge.get_d1de_tile_model())
			if native_25d_instance.has_method("apply_all_d1de_settings"):
				native_25d_instance.apply_all_d1de_settings(
					hero_light_enabled,
					current_fog_mode,
					current_upscaler_mode,
					current_relief_mode,
					wet_floor,
					current_hdr_level,
					current_tile_model
				)
			elif native_25d_instance.has_method("apply_all_resurrected_settings"):
				native_25d_instance.apply_all_resurrected_settings(
					hero_light_enabled,
					current_fog_mode,
					current_upscaler_mode,
					current_relief_mode,
					wet_floor,
					current_hdr_level,
					current_tile_model
				)
			native_25d_instance.activate()
		show_osd("Display Mode 2/3: Native Godot 2.5D Engine (144Hz Smooth Camera, Y-Sorted Sprites, PointLight2D)", 3.5)

	elif current_display_mode == DisplayMode.NATIVE_3D:
		# Mode 2: Native 3D Sandbox (Real 3D Geometry, Billboard Sprites, Q/E Orbit, PgUp/PgDn Tilt)
		if camera:
			camera.current = false
		if mesh_instance:
			mesh_instance.visible = false
		if hero_light:
			hero_light.visible = false
		if torch_container:
			torch_container.visible = false
		if effects_container:
			effects_container.visible = false
			for child in effects_container.get_children():
				child.queue_free()
		for tl in pooled_torch_lights:
			tl.visible = false
		if directional_light:
			directional_light.visible = false
		if dungeon_embers:
			dungeon_embers.emitting = false
			dungeon_embers.visible = false
		if world_env and world_env.environment:
			world_env.environment.volumetric_fog_enabled = false
			world_env.environment.glow_enabled = false
		update_shader_params()
		if modal_layer and diablo_bridge and diablo_bridge.has_method("is_modal_active"):
			modal_layer.visible = diablo_bridge.is_modal_active()
		if sandbox_instance:
			sandbox_instance.activate()
		show_osd("Display Mode 3/3: Native 3D Sandbox (Real 3D Geometry, Billboard Sprites, Q/E Orbit, PgUp/PgDn Tilt)", 3.5)

	apply_upscaler_mode()

func switch_display_mode(new_mode: int):
	current_display_mode = new_mode
	print("[D1-DEBUG] display_mode -> %d" % new_mode)
	apply_display_mode()

func _unhandled_input(event: InputEvent):
	var is_ingame = diablo_bridge.is_game_running() if (diablo_bridge and diablo_bridge.has_method("is_game_running")) else false
	var is_text_active = diablo_bridge.is_text_input_active() if (diablo_bridge and diablo_bridge.has_method("is_text_input_active")) else false

	if event is InputEventKey:
		# If user is entering text (character name, chat, IP, password) or NOT in-game:
		# DO NOT intercept letter keys H or G! They must type characters!
		if not is_text_active and is_ingame:
			if event.keycode == KEY_H:
				if event.pressed and not event.echo:
					if current_display_mode != DisplayMode.ORIGINAL_25D:
						show_osd("[H] Modern/Classic HUD Switch is only available in Classic Blit Mode (Display Mode 1/3)")
					else:
						modern_hud_enabled = !modern_hud_enabled
						if modern_hud:
							modern_hud.visible = modern_hud_enabled
						if diablo_bridge:
							diablo_bridge.set_vanilla_hud_hidden(modern_hud_enabled)
						update_shader_params()
						show_osd("[H] HUD Mode: " + ("Modern D1DE CanvasLayer (Forward+ Vulkan)" if modern_hud_enabled else "Classic 1996 Panel (Vanilla)"))
				return
			elif event.keycode == KEY_G:
				if event.pressed and not event.echo:
					var is_hd = toggle_hd_graphics()
					show_osd("[G] Graphics Style: " + ("Definitive Edition 4x HD" if is_hd else "Authentic 1996 Pixel Art"))
				return

	if event is InputEventKey and event.pressed and not event.echo:
		print("[D1-DEBUG] key_unhandled keycode=%d phys=%d uni=%d text_act=%s ingame=%s" % [event.keycode, event.physical_keycode, event.unicode, is_text_active, is_ingame])

		if diablo_bridge != null and diablo_bridge.has_method("get_mode_switch_key"):
			var sw_key := int(diablo_bridge.get_mode_switch_key())
			var sw_mods := int(diablo_bridge.get_mode_switch_mods())
			var pressed_mask := 0
			if event.shift_pressed: pressed_mask |= 1
			if event.ctrl_pressed: pressed_mask |= 2
			if event.alt_pressed: pressed_mask |= 4
			if event.meta_pressed: pressed_mask |= 8
			if int(event.physical_keycode) == sw_key and pressed_mask == sw_mods:
				var next_mode = (current_display_mode + 1) % 3
				switch_display_mode(next_mode)
				_write_display_mode(next_mode)   # persists to diablo.ini
				if not is_ingame:
					var mode_names = [
						"Classic 2.5D Blit (Vanilla + 3D Relief Shader)",
						"Native Godot 2.5D Engine (144Hz Smooth Camera)",
						"Native 3D Sandbox (Real 3D Geometry)"
					]
					show_osd("Mode selected: " + mode_names[next_mode] + " (Active when game begins)", 3.0)
				return

	if is_ingame:
		if current_display_mode == DisplayMode.NATIVE_3D and sandbox_instance != null:
			if sandbox_instance.handle_input(event):
				return

		if current_display_mode == DisplayMode.NATIVE_25D and native_25d_instance != null:
			if native_25d_instance.handle_input(event):
				return

	if not use_gdextension and not FileAccess.file_exists("/dev/shm/d1_godot_frame"):
		return
		
	var vp_size = get_viewport().get_visible_rect().size
	if vp_size.x <= 0 or vp_size.y <= 0:
		return
		
	if event is InputEventMouseMotion:
		var mpos = get_game_mouse_pos(event.position, vp_size)
		send_input_to_d1(1, 0, 0, mpos.x, mpos.y)
	elif event is InputEventMouseButton:
		# 5-Step In-Game Zoom (1.0x, 1.5x, 2.0x Native D1 + 2.5x, 3.0x Ultra-Close Seamless Playfield)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if current_zoom_step < zoom_step_names.size() - 1:
				var old_s = current_zoom_step
				current_zoom_step += 1
				apply_zoom_step(old_s, current_zoom_step)
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if current_zoom_step > 0:
				var old_s = current_zoom_step
				current_zoom_step -= 1
				apply_zoom_step(old_s, current_zoom_step)
			return
			
		var mpos = get_game_mouse_pos(event.position, vp_size)
		var btn = 1
		if event.button_index == MOUSE_BUTTON_RIGHT:
			btn = 3
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			btn = 2
		var state = 1 if event.pressed else 0
		send_input_to_d1(2, btn, state, mpos.x, mpos.y)
	elif event is InputEventKey:
		var raw_code = event.keycode
		if raw_code == 0:
			raw_code = event.physical_keycode
		if raw_code == 0:
			raw_code = event.key_label

		var key = get_sdl_key(raw_code)
		var state = 1 if event.pressed else 0
		var uni = event.unicode if event.pressed else 0
		var mod_mask = 0
		if event.shift_pressed: mod_mask |= 1
		if event.ctrl_pressed: mod_mask |= 2
		if event.alt_pressed: mod_mask |= 4
		send_input_to_d1(3, key, state, uni, mod_mask)

func _write_display_mode(mode_idx: int):
	if diablo_bridge == null or not diablo_bridge.has_method("get_settings_categories"):
		return
	var cats = diablo_bridge.get_settings_categories()
	for cat in cats:
		if str(cat.get("name", "")) in ["Definitive Edition", "Resurrected"]:
			var found := false
			var e_id := -1
			var entries = diablo_bridge.get_settings_entries(int(cat.get("id", 0))) if diablo_bridge.has_method("get_settings_entries") else []
			for entry in entries:
				if str(entry.get("name", "")) == "Display Mode" and int(entry.get("type", -1)) == 1:
					e_id = int(entry.get("id", 0))
					found = true
					break
			if found and diablo_bridge.has_method("set_setting_list"):
				diablo_bridge.set_setting_list(int(cat.get("id", 0)), e_id, mode_idx)
				diablo_bridge.save_settings()
			return

func send_input_to_d1(msg_type: int, code: int, state: int, x: int, y: int):
	if use_gdextension and diablo_bridge != null:
		diablo_bridge.send_input(msg_type, code, state, x, y)
		return

	var file = FileAccess.open("/dev/shm/d1_godot_frame", FileAccess.READ_WRITE)
	if not file:
		return
		
	file.seek(304)
	var write_idx = file.get_32()
	
	var slot_offset = 312 + (write_idx % 128) * 20
	file.seek(slot_offset)
	file.store_32(msg_type)
	file.store_32(code)
	file.store_32(state)
	file.store_32(x)
	file.store_32(y)
	
	file.seek(304)
	file.store_32(write_idx + 1)
	file.flush()

func get_sdl_key(keycode: int) -> int:
	if keycode == KEY_ESCAPE: return 27
	if keycode == KEY_ENTER or keycode == KEY_KP_ENTER: return 13
	if keycode == KEY_SPACE: return 32
	if keycode == KEY_TAB: return 9
	if keycode == KEY_BACKSPACE: return 8
	if keycode == KEY_DELETE: return 127
	if keycode >= KEY_0 and keycode <= KEY_9: return keycode
	if keycode >= KEY_A and keycode <= KEY_Z: return keycode + 32
	if keycode >= 97 and keycode <= 122: return keycode
	if keycode >= KEY_F1 and keycode <= KEY_F12: return 1073741882 + (keycode - KEY_F1)
	if keycode == KEY_SHIFT: return 1073742049
	if keycode == KEY_CTRL: return 1073742048
	if keycode == KEY_ALT: return 1073742050
	if keycode == KEY_CAPSLOCK: return 1073741881
	if keycode == KEY_UP: return 1073741906
	if keycode == KEY_DOWN: return 1073741905
	if keycode == KEY_LEFT: return 1073741904
	if keycode == KEY_RIGHT: return 1073741903
	if keycode == KEY_PAGEUP: return 1073741899
	if keycode == KEY_PAGEDOWN: return 1073741902
	if keycode == KEY_HOME: return 1073741898
	if keycode == KEY_END: return 1073741901
	return keycode

func update_dynamic_lighting(delta: float) -> void:
	if not diablo_bridge or not diablo_bridge.has_method("get_active_lights"):
		return

	var active_lights: Array = diablo_bridge.get_active_lights()
	if active_lights.is_empty():
		if hero_light:
			hero_light.visible = false
		for light in pooled_torch_lights:
			light.visible = false
		return

	# 1. Hero Torch (Type 0, index 0 - pause-menu driven soft torchlight; default off keeps hero sprite clean
	if hero_light:
		if hero_light_enabled and active_lights.size() > 0:
			var hero_info = active_lights[0]
			hero_light.visible = true
			var hp = hero_info["world_pos"]
			hero_light.position = Vector3(hp.x, hp.y, 0.45)
			var h_flicker = 1.0 + 0.04 * sin(time_accum * 11.7) * cos(time_accum * 6.3)
			hero_light.light_energy = 0.50 * h_flicker
			hero_light.light_specular = 0.0 # Pure diffuse, zero directional tracking glint
			hero_light.omni_range = clamp(hero_info["radius"] * 0.28, 2.2, 3.2)
			hero_light.omni_attenuation = 1.4
		else:
			hero_light.visible = false

	# 2. Environmental & Spell Lights (Wall torches, braziers, fireballs)
	var env_count = active_lights.size() - 1
	while pooled_torch_lights.size() < env_count:
		var o_light = OmniLight3D.new()
		o_light.shadow_enabled = false
		o_light.omni_attenuation = 2.0
		var sparks = torch_sparks_scene.instantiate()
		sparks.name = "TorchSparks"
		o_light.add_child(sparks)
		sparks.position = Vector3(0, 0, 0.05)
		torch_container.add_child(o_light)
		pooled_torch_lights.append(o_light)

	for i in range(pooled_torch_lights.size()):
		var o_light = pooled_torch_lights[i]
		if i < env_count:
			var info = active_lights[i + 1]
			var l_type = info.get("type", 0)
			var sparks = o_light.get_node_or_null("TorchSparks")

			# Wall torches/braziers (type 1) only active when Soft Torchlight is enabled;
			# spell missiles (type 2) remain active for projectile lighting feedback.
			if l_type == 1 and not hero_light_enabled:
				o_light.visible = false
				if sparks:
					sparks.visible = false
					sparks.emitting = false
				continue

			o_light.visible = true
			var lp = info["world_pos"]
			o_light.position = Vector3(lp.x, lp.y, 0.30)
			if l_type == 1: # Wall Torch / Brazier
				o_light.light_color = Color(1.0, 0.68, 0.28, 1.0)
				o_light.omni_range = clamp(info["radius"] * 0.26, 1.8, 2.8)
				o_light.omni_attenuation = 2.0
				var phase = float(i + 1) * 1.83
				var t_flicker = 1.0 + 0.10 * sin(time_accum * 13.1 + phase) * cos(time_accum * 7.9 + phase * 2.0)
				o_light.light_energy = 1.10 * t_flicker
				if sparks:
					sparks.visible = true
					sparks.emitting = true
			elif l_type == 2: # Spell / Missile (Fireball, Flame)
				o_light.light_color = Color(1.0, 0.88, 0.45, 1.0)
				o_light.omni_range = clamp(info["radius"] * 0.32, 2.0, 3.5)
				o_light.omni_attenuation = 2.0
				o_light.light_energy = 1.50
				if sparks:
					sparks.visible = false
					sparks.emitting = false
			else:
				o_light.light_color = Color(0.9, 0.65, 0.35, 1.0)
				o_light.omni_range = 2.2
				o_light.omni_attenuation = 2.0
				o_light.light_energy = 0.8
				if sparks:
					sparks.visible = false
					sparks.emitting = false
		else:
			o_light.visible = false
			var sparks = o_light.get_node_or_null("TorchSparks")
			if sparks:
				sparks.visible = false
				sparks.emitting = false

func update_shadow_casters() -> void:
	pass

func get_zoom_vfx_scale() -> float:
	match current_zoom_step:
		0: return 0.35   # 1.0x Normal / Wide
		1: return 0.52   # 1.5x Balanced
		2: return 0.68   # 2.0x Zoomed
		3: return 0.84   # 2.5x Ultra-Close
		4: return 1.00   # 3.0x Macro-Close (User reference size)
		_: return 0.52

func process_visual_events() -> void:
	if not diablo_bridge or not diablo_bridge.has_method("poll_visual_events"):
		return

	var z_scale = get_zoom_vfx_scale()
	var events: Array = diablo_bridge.poll_visual_events()
	for ev in events:
		var ev_type = ev.get("type", 0)
		var ev_pos = ev.get("world_pos", Vector3.ZERO)
		var ev_scale = ev.get("intensity", 1.0)
		var p_instance: GPUParticles3D = null

		if ev_type == 1: # Blood Splatter (Fleshy / Demon)
			p_instance = blood_splatter_scene.instantiate()
		elif ev_type == 2: # Bone Shards (Undead / Skeleton / Stone)
			p_instance = bone_shards_scene.instantiate()
		elif ev_type == 3: # Fireball / Spell Explosion
			p_instance = fireball_explosion_scene.instantiate()

		if p_instance:
			p_instance.position = ev_pos
			var b_factor = 0.82 if ev_type == 1 else 1.0
			var s = clamp(ev_scale, 0.9, 2.2) * z_scale * b_factor
			p_instance.scale = Vector3(s, s, s)
			effects_container.add_child(p_instance)

			# On heavy hit or fatal kill gore (intensity >= 1.8), spawn a secondary burst for visceral gore volume
			if ev_type == 1 and ev_scale >= 1.8:
				var extra_gore = blood_splatter_scene.instantiate()
				extra_gore.position = ev_pos + Vector3(randf_range(-0.12, 0.12), randf_range(-0.08, 0.08), 0.05)
				extra_gore.scale = Vector3(s * 1.15, s * 1.15, s * 1.15)
				effects_container.add_child(extra_gore)
			elif ev_type == 2 and ev_scale >= 1.8:
				var extra_bones = bone_shards_scene.instantiate()
				extra_bones.position = ev_pos + Vector3(randf_range(-0.10, 0.10), randf_range(-0.06, 0.06), 0.05)
				extra_bones.scale = Vector3(s * 1.1, s * 1.1, s * 1.1)
				effects_container.add_child(extra_bones)

func _on_main_menu_settings_saved() -> void:
	if diablo_bridge:
		if diablo_bridge.has_method("get_d1de_torchlight"):
			hero_light_enabled = bool(diablo_bridge.get_d1de_torchlight())
		elif diablo_bridge.has_method("get_resurrected_torchlight"):
			hero_light_enabled = bool(diablo_bridge.get_resurrected_torchlight())

		if diablo_bridge.has_method("get_d1de_fog_level"):
			current_fog_mode = int(diablo_bridge.get_d1de_fog_level())
		elif diablo_bridge.has_method("get_resurrected_fog_level"):
			current_fog_mode = int(diablo_bridge.get_resurrected_fog_level())

		if diablo_bridge.has_method("get_d1de_color_profile"):
			current_color_profile = int(diablo_bridge.get_d1de_color_profile())
		elif diablo_bridge.has_method("get_resurrected_color_profile"):
			current_color_profile = int(diablo_bridge.get_resurrected_color_profile())

		if diablo_bridge.has_method("get_d1de_hdr_level"):
			current_hdr_level = int(diablo_bridge.get_d1de_hdr_level())
		elif diablo_bridge.has_method("get_resurrected_hdr_level"):
			current_hdr_level = int(diablo_bridge.get_resurrected_hdr_level())

		if diablo_bridge.has_method("get_d1de_upscaler_mode"):
			current_upscaler_mode = int(diablo_bridge.get_d1de_upscaler_mode())
		elif diablo_bridge.has_method("get_resurrected_upscaler_mode"):
			current_upscaler_mode = int(diablo_bridge.get_resurrected_upscaler_mode())

		if diablo_bridge.has_method("get_d1de_relief_mode"):
			current_relief_mode = int(diablo_bridge.get_d1de_relief_mode())
		elif diablo_bridge.has_method("get_resurrected_relief_mode"):
			current_relief_mode = int(diablo_bridge.get_resurrected_relief_mode())

		if diablo_bridge.has_method("get_d1de_wet_floor"):
			wet_floor = bool(diablo_bridge.get_d1de_wet_floor())
		elif diablo_bridge.has_method("get_resurrected_wet_floor"):
			wet_floor = bool(diablo_bridge.get_resurrected_wet_floor())

		if diablo_bridge.has_method("get_d1de_tile_model"):
			current_tile_model = int(diablo_bridge.get_d1de_tile_model())
		elif diablo_bridge.has_method("get_resurrected_tile_model"):
			current_tile_model = int(diablo_bridge.get_resurrected_tile_model())

		if native_25d_instance and native_25d_instance.has_method("apply_all_d1de_settings"):
			native_25d_instance.apply_all_d1de_settings(
				hero_light_enabled,
				current_fog_mode,
				current_upscaler_mode,
				current_relief_mode,
				wet_floor,
				current_hdr_level,
				current_tile_model
			)
		update_torch_light()
		update_fog_mode()
		apply_upscaler_mode()
		update_shader_params()

