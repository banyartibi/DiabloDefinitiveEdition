extends Node2D

# Native Godot 2.5D View
# Directly renders authentic Diablo 1 level pieces, characters, and monsters
# with 144Hz smooth camera, Godot 2D Y-sorting, and dynamic PointLight2D lighting.

const UpscalerModelConfig = preload("res://scripts/upscaler_model_config.gd")

var diablo_bridge = null
var is_active: bool = false

# Nodes
var camera: Camera2D = null
var world_root: Node2D = null
var floor_root: Node2D = null
var player_node: Node2D = null
var player_sprite: Sprite2D = null
var player_light: PointLight2D = null
var player_shadow: Sprite2D = null
var shadow_texture: ImageTexture = null
var canvas_modulate: CanvasModulate = null
var shared_radial_light_texture: GradientTexture2D = null

# State tracking
var hd_graphics_enabled: bool = true
var last_level_idx: int = -999
var pending_dungeon_rebuild: bool = false
var level_stabilize_frames: int = 0
var pending_secondary_rebuild: bool = false
var secondary_rebuild_countdown: int = 0
var last_gamma_value: int = -1  # bridge gamma; on change -> invalidate all palette-baked textures

# Bridge capability flags (resolved once to avoid per-frame has_method() reflection)
var _has_light_grid: bool = false
var _has_solidity_grid: bool = false
var _has_flags_grid: bool = false
var _has_trans_grid: bool = false
var _has_trans_mask: bool = false
var _has_trans_list: bool = false
var _has_special_grid: bool = false
var _has_player_pos: bool = false
var _has_current_level: bool = false
var _has_gamma: bool = false
var _has_level_loading: bool = false
var _has_game_running: bool = false
var _has_dungeon_grid: bool = false
var _has_player_sprite: bool = false
var _has_monster_data: bool = false
var _has_monster_sprite: bool = false
var _has_active_lights: bool = false
var _has_active_objects: bool = false
var _has_active_items: bool = false
var _has_active_corpses: bool = false
var _has_active_missiles: bool = false
var _has_visual_events: bool = false
var _has_object_sprite: bool = false
var _has_ground_item_sprite: bool = false
var _has_corpse_sprite: bool = false
var _has_missile_sprite: bool = false
var _has_piece_texture: bool = false
var _has_special_cel: bool = false
var _has_item_label_highlight: bool = false
var _has_clear_cache: bool = false
var _has_zoom_vision: bool = false
var _has_map_world: bool = false
var _has_modal_active: bool = false
var _has_text_input: bool = false

func _init_bridge_caps():
	if not diablo_bridge:
		return
	_has_light_grid = diablo_bridge.has_method("get_dungeon_light_grid")
	_has_solidity_grid = diablo_bridge.has_method("get_dungeon_solidity_grid")
	_has_flags_grid = diablo_bridge.has_method("get_dungeon_flags_grid")
	_has_trans_grid = diablo_bridge.has_method("get_dungeon_trans_grid")
	_has_trans_mask = diablo_bridge.has_method("get_dungeon_trans_mask")
	_has_trans_list = diablo_bridge.has_method("get_trans_list")
	_has_special_grid = diablo_bridge.has_method("get_dungeon_special_grid")
	_has_player_pos = diablo_bridge.has_method("get_player_continuous_pos")
	_has_current_level = diablo_bridge.has_method("get_current_level")
	_has_gamma = diablo_bridge.has_method("get_gamma")
	_has_level_loading = diablo_bridge.has_method("is_level_loading")
	_has_game_running = diablo_bridge.has_method("is_game_running")
	_has_dungeon_grid = diablo_bridge.has_method("get_dungeon_grid")
	_has_player_sprite = diablo_bridge.has_method("get_player_sprite_data")
	_has_monster_data = diablo_bridge.has_method("get_active_monsters_data")
	_has_monster_sprite = diablo_bridge.has_method("get_monster_sprite_data")
	_has_active_lights = diablo_bridge.has_method("get_active_lights")
	_has_active_objects = diablo_bridge.has_method("get_active_objects")
	_has_active_items = diablo_bridge.has_method("get_active_items")
	_has_active_corpses = diablo_bridge.has_method("get_active_corpses")
	_has_active_missiles = diablo_bridge.has_method("get_active_missiles")
	_has_visual_events = diablo_bridge.has_method("poll_visual_events")
	_has_object_sprite = diablo_bridge.has_method("get_object_sprite_data")
	_has_ground_item_sprite = diablo_bridge.has_method("get_ground_item_sprite_data")
	_has_corpse_sprite = diablo_bridge.has_method("get_corpse_sprite_data")
	_has_missile_sprite = diablo_bridge.has_method("get_missile_sprite_data")
	_has_piece_texture = diablo_bridge.has_method("get_dungeon_piece_texture")
	_has_special_cel = diablo_bridge.has_method("get_special_cel_texture")
	_has_item_label_highlight = diablo_bridge.has_method("is_item_label_highlight_enabled")
	_has_clear_cache = diablo_bridge.has_method("clear_dungeon_piece_cache")
	_has_zoom_vision = diablo_bridge.has_method("set_zoom_vision_radius")
	_has_map_world = diablo_bridge.has_method("map_world_to_screen")
	_has_modal_active = diablo_bridge.has_method("is_modal_active")
	_has_text_input = diablo_bridge.has_method("is_text_input_active")
	_has_dungeon_tile = diablo_bridge.has_method("get_dungeon_tile")

var _has_dungeon_tile: bool = false
var last_dungeon_hash: int = 0
var tile_sprites: Dictionary = {} # Vector2i -> Sprite2D (Floor diamonds, z_index = -2)
var wall_sprites: Dictionary = {} # Vector2i -> Sprite2D (Upper Wall & Scenery, z_index = 0)
var special_sprites: Dictionary = {} # Vector2i -> Sprite2D (Arches, Doorways, Column Tops)
var tile_piece_ids: Dictionary = {} # Vector2i -> int (Track piece IDs for runtime door syncing)
var tile_special_ids: Dictionary = {} # Vector2i -> int (Track special CEL IDs for runtime door syncing)
var last_visible_tiles: Dictionary = {} # Vector2i -> bool (track visible tiles for efficient culling)
var last_player_frame: int = -999
var last_player_dir: int = -999
var player_texture: ImageTexture = null

# Monster tracking
var monster_nodes: Dictionary = {} # int -> Node2D
var monster_textures: Dictionary = {} # int -> ImageTexture
var monster_last_frame: Dictionary = {}
var monster_last_dir: Dictionary = {}
var player_hd_cache: Dictionary = {}   # cache_key -> Texture2D (4x native HD sprites)
var monster_hd_cache: Dictionary = {}  # cache_key -> Texture2D (4x native HD sprites)

# Milestone 4: Dungeon Objects (Torches, Barrels, Chests, Shrines)
var object_sprites: Dictionary = {} # int (id) -> Sprite2D
var object_textures: Dictionary = {} # String ("type_frame") -> ImageTexture

# Milestone 4: Dropped Items (Loot with name labels)
var item_nodes: Dictionary = {} # int (id) -> Node2D
var item_textures: Dictionary = {}
var _loot_stylebox_normal: StyleBoxFlat = null
var _loot_stylebox_magic: StyleBoxFlat = null
var _loot_stylebox_unique: StyleBoxFlat = null
 # int (id) -> ImageTexture

# Ground loot typography & Diablo IV loot beams
const FONT_EXOCET = preload("res://assets/fonts/Exocet.ttf")
const TEX_LOOT_BEAM = preload("res://assets/hud/loot_beam_gradient.png")
const TEX_LOOT_FLARE = preload("res://assets/hud/loot_flare_disc.png")

const COLOR_NORMAL = Color(0.85, 0.82, 0.75, 1.0)
const COLOR_MAGIC = Color(0.45, 0.70, 1.0, 1.0)
const COLOR_UNIQUE = Color(1.0, 0.85, 0.35, 1.0)

var loot_beam_material: CanvasItemMaterial = null

# Milestone 4: Corpses (Fallen monsters & skeletons)
var corpse_sprites: Dictionary = {} # Vector2i -> Sprite2D
var corpse_textures: Dictionary = {} # String ("corpseIdx_dir") -> ImageTexture
var corpse_is_hd: Dictionary = {} # String -> bool
var item_is_hd: Dictionary = {} # String -> bool

# Missiles & Spell Projectiles
var missile_nodes: Dictionary = {} # int (id) -> Node2D
var missile_textures: Dictionary = {} # String ("type_frame") -> ImageTexture

# D1DE Combat VFX - Native Godot 2.5D GPUParticles2D one-shot bursts
var blood_splatter_2d_scene = preload("res://scenes/effects/blood_splatter_2d.tscn")
var bone_shards_2d_scene = preload("res://scenes/effects/bone_shards_2d.tscn")
var fireball_explosion_2d_scene = preload("res://scenes/effects/fireball_explosion_2d.tscn")
var last_player_mode: int = -999

# Torch light pool
var torch_lights: Array = []

# Realistic 2.5D Shadows & Lighting
var realistic_shadow_shader = preload("res://shaders/realistic_25d_shadow.gdshader")
var entity_hd_shader = preload("res://shaders/entity_hd_upscaler.gdshader")
var entity_hd_material: ShaderMaterial = null
var player_hd_material: ShaderMaterial = null
var monster_hd_material: ShaderMaterial = null
var player_shadow_material: ShaderMaterial = null
var current_player_shadow_skew: Vector2 = Vector2(0.28, 0.42)
var current_player_shadow_length: float = 0.9
var current_player_shadow_opacity: float = 0.52
# Toggle for static wall occluders (false: prevents 2D shadow rays from projecting black cuts onto floor)
var enable_wall_occluders: bool = false
var pbr_texture_cache: Dictionary = {} # piece_id -> CanvasTexture
var pbr_special_cache: Dictionary = {} # special_id -> CanvasTexture
var pbr_occluders_cache: Dictionary = {} # String -> Dictionary (points, type)
var tile_occluders: Dictionary = {} # Vector2i -> LightOccluder2D
var monster_shadow_materials: Dictionary = {} # int -> ShaderMaterial

# Definitive Edition (D1DE) visual settings (pause-menu driven)
var hero_torchlight_enabled: bool = true
var current_fog_mode: int = 0
var fog_layer: CanvasLayer = null
var fog_rect: ColorRect = null
var fog_material: ShaderMaterial = null
var current_upscaler_mode: int = 0
var current_tile_model: int = 0  # Neural upscale model for pre-baked tile/sprite assets (see UpscalerModelConfig)
var current_relief_mode: int = 0
var wet_floor: bool = true
var current_hdr_level: int = 1

# Continuous 2.5D GPU Isometric Lightmap & Shared Tile PBR Material
var d1de_pbr_shader = preload("res://shaders/d1de_25d_pbr.gdshader")
var dungeon_tile_material: ShaderMaterial = null
var light_image: Image = null
var light_map_texture: ImageTexture = null

# Smooth Camera & Movement
var player_target_pos: Vector2 = Vector2.ZERO
var time_accum: float = 0.0

# Zoom Steps
var zoom_levels = [0.75, 1.0, 1.25, 1.5, 2.0, 2.5]
var current_zoom_idx: int = 3 # Default: 1.5x

# D1 Resolution (for input mapping)
var d1_width: int = 2560
var d1_height: int = 1440

func _ready():
	visible = false
	set_process(false)
	setup_scene_hierarchy()

func setup_scene_hierarchy():
	# 2D World Root with Y-sorting and adaptive texture filtering (HD: Linear with Mipmaps, 1996: Nearest)
	floor_root = Node2D.new()
	floor_root.name = "FloorRoot"
	floor_root.y_sort_enabled = false
	add_child(floor_root)

	world_root = Node2D.new()
	world_root.name = "WorldRoot"
	world_root.y_sort_enabled = true
	_apply_texture_filtering()
	add_child(world_root)
	load_pbr_occluders()

	# Atmospheric Gothic Crypt Canvas Modulate (Pure 1.0 ambient so dLight controls contrast cleanly)
	canvas_modulate = CanvasModulate.new()
	canvas_modulate.name = "CryptModulate"
	canvas_modulate.color = Color(1.0, 1.0, 1.0)
	add_child(canvas_modulate)

	# Continuous GPU Isometric Lightmap & Shared Tile PBR Material
	light_image = Image.create(112, 112, false, Image.FORMAT_R8)
	light_image.fill(Color(0, 0, 0, 1))
	light_map_texture = ImageTexture.create_from_image(light_image)
	dungeon_tile_material = ShaderMaterial.new()
	dungeon_tile_material.shader = d1de_pbr_shader
	dungeon_tile_material.set_shader_parameter("light_map", light_map_texture)
	dungeon_tile_material.set_shader_parameter("is_town", false)
	dungeon_tile_material.set_shader_parameter("relief_mode", current_relief_mode)
	dungeon_tile_material.set_shader_parameter("wet_floor", wet_floor)

	# Smooth 144Hz Camera2D
	camera = Camera2D.new()
	camera.name = "Camera2D"
	camera.position_smoothing_enabled = false
	var z = zoom_levels[current_zoom_idx]
	camera.zoom = Vector2(z, z)
	add_child(camera)
	_apply_zoom_vision(z)

	# Entity Neural Super-Resolution & Multi-Upscaler Shader Material
	entity_hd_material = ShaderMaterial.new()
	entity_hd_material.shader = entity_hd_shader
	entity_hd_material.set_shader_parameter("hd_enabled", hd_graphics_enabled)
	entity_hd_material.set_shader_parameter("upscaler_mode", current_upscaler_mode)
	entity_hd_material.set_shader_parameter("gamma", 1.0)
	entity_hd_material.set_shader_parameter("brightness", 1.0)
	player_hd_material = entity_hd_material
	monster_hd_material = entity_hd_material

	# 2D Atmospheric Fog Layer (Crypt Mist & Dense Drift)
	fog_layer = CanvasLayer.new()
	fog_layer.name = "AtmosphericFogLayer"
	fog_layer.layer = 5
	add_child(fog_layer)
	fog_rect = ColorRect.new()
	fog_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fog_material = ShaderMaterial.new()
	fog_material.shader = preload("res://shaders/atmospheric_fog_2d.gdshader")
	fog_material.set_shader_parameter("fog_mode", current_fog_mode)
	fog_rect.material = fog_material
	fog_layer.add_child(fog_rect)
	_update_fog()

	# Player Entity (participates in Y-sorting under world_root)
	setup_player_node()

func get_hd_graphics_enabled() -> bool:
	return hd_graphics_enabled

func set_hd_graphics_enabled(enabled: bool) -> void:
	if hd_graphics_enabled == enabled:
		return
	hd_graphics_enabled = enabled
	pbr_texture_cache.clear()
	pbr_special_cache.clear()
	player_hd_cache.clear()
	monster_hd_cache.clear()
	player_texture = null
	last_player_frame = -999
	last_player_dir = -999
	last_player_mode = -999
	monster_textures.clear()
	monster_last_frame.clear()
	monster_last_dir.clear()
	object_textures.clear()
	item_textures.clear()
	item_is_hd.clear()
	corpse_textures.clear()
	corpse_is_hd.clear()
	missile_textures.clear()
	if entity_hd_material:
		entity_hd_material.set_shader_parameter("hd_enabled", enabled)
	if dungeon_tile_material:
		dungeon_tile_material.set_shader_parameter("relief_mode", current_relief_mode if enabled else 0)
	_apply_texture_filtering()
	rebuild_dungeon_tiles()
	var inline_light = diablo_bridge.get_dungeon_light_grid() if _has_light_grid else PackedByteArray()
	var inline_solid = diablo_bridge.get_dungeon_solidity_grid() if _has_solidity_grid else PackedByteArray()
	var inline_pos = diablo_bridge.get_player_continuous_pos() if _has_player_pos else {}
	update_lighting_and_transparency(inline_light, inline_solid, inline_pos)
	print("[Native 2.5D View] HD Graphics switched to: %s" % ("Definitive Edition 4x HD" if enabled else "Authentic 1996"))

func _apply_texture_filtering() -> void:
	var level_has_hd = hd_graphics_enabled
	if world_root:
		world_root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if level_has_hd else CanvasItem.TEXTURE_FILTER_NEAREST
	if floor_root:
		floor_root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if level_has_hd else CanvasItem.TEXTURE_FILTER_NEAREST
	var ent_filter = CanvasItem.TEXTURE_FILTER_LINEAR if (hd_graphics_enabled and current_upscaler_mode != 4) else CanvasItem.TEXTURE_FILTER_NEAREST
	if player_sprite:
		player_sprite.texture_filter = ent_filter
	for m_root in monster_nodes.values():
		if is_instance_valid(m_root):
			var s = m_root.get_node_or_null("Sprite") as Sprite2D
			if s:
				s.texture_filter = ent_filter

func get_or_create_shadow_texture() -> ImageTexture:
	if shadow_texture != null:
		return shadow_texture
	var sw = 36
	var sh = 18
	var img = Image.create(sw, sh, false, Image.FORMAT_RGBA8)
	var cx = float(sw) * 0.5
	var cy = float(sh) * 0.5
	var rx = cx - 1.0
	var ry = cy - 1.0
	for y in range(sh):
		for x in range(sw):
			var nx = (float(x) + 0.5 - cx) / rx
			var ny = (float(y) + 0.5 - cy) / ry
			var dist_sq = nx * nx + ny * ny
			if dist_sq < 1.0:
				var alpha = clampf((1.0 - sqrt(dist_sq)) * 1.5, 0.0, 1.0)
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, alpha * 0.55))
			else:
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
	shadow_texture = ImageTexture.create_from_image(img)
	return shadow_texture

func setup_player_node():
	player_node = Node2D.new()
	player_node.name = "PlayerEntity"
	player_node.z_index = 0
	world_root.add_child(player_node)

	# Realistic 2.5D Directional Silhouette Shadow
	player_shadow_material = ShaderMaterial.new()
	player_shadow_material.shader = realistic_shadow_shader
	player_shadow_material.set_shader_parameter("shadow_skew", current_player_shadow_skew * current_player_shadow_length)
	player_shadow_material.set_shader_parameter("shadow_color", Color(0.0, 0.0, 0.0, current_player_shadow_opacity))
	player_shadow_material.set_shader_parameter("shadow_blur", 2.0)
	player_shadow_material.set_shader_parameter("contact_fade", 0.35)

	player_shadow = Sprite2D.new()
	player_shadow.name = "PlayerShadow"
	player_shadow.material = player_shadow_material
	player_shadow.centered = true
	player_shadow.position = Vector2.ZERO
	player_shadow.z_index = -1
	player_shadow.visible = false
	player_node.add_child(player_shadow)

	# Hero Sprite2D (authentic animated Diablo 1 & Hellfire character with Neural Super-Resolution)
	player_sprite = Sprite2D.new()
	player_sprite.name = "PlayerSprite"
	player_sprite.centered = true
	player_sprite.material = entity_hd_material
	player_node.add_child(player_sprite)

	# Hero Torch Light with PCF13 Soft Penumbra Shadows
	shared_radial_light_texture = create_radial_light_texture(512)
	player_light = PointLight2D.new()
	player_light.name = "HeroTorchLight"
	player_light.texture = shared_radial_light_texture
	player_light.texture_scale = 2.4
	player_light.color = Color(1.0, 0.90, 0.78)
	player_light.energy = 0.35
	player_light.enabled = true
	player_light.position = Vector2(0, -16)
	player_light.shadow_enabled = enable_wall_occluders
	player_light.shadow_filter = Light2D.SHADOW_FILTER_PCF13
	player_light.shadow_filter_smooth = 4.5
	player_light.shadow_color = Color(0.0, 0.0, 0.0, 0.38)
	player_node.add_child(player_light)

func create_radial_light_texture(size: int) -> GradientTexture2D:
	var grad = Gradient.new()
	grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex = GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.96, 0.5)
	tex.width = size
	tex.height = size
	return tex

# --- Definitive Edition (D1DE) Settings (Pause-menu driven) ---

func set_soft_torchlight(enabled: bool) -> void:
	hero_torchlight_enabled = enabled
	if player_light:
		var is_town = (last_level_idx == 0)
		player_light.enabled = (not is_town) and hero_torchlight_enabled

func set_atmospheric_fog(mode: int) -> void:
	current_fog_mode = mode
	_update_fog()

func _update_fog() -> void:
	if not fog_layer or not fog_material:
		return
	var is_town = (last_level_idx == 0)
	if not is_active or is_town or current_fog_mode == 0:
		fog_layer.visible = false
	else:
		fog_layer.visible = true
		fog_material.set_shader_parameter("fog_mode", current_fog_mode)

func set_upscaler_mode(mode: int) -> void:
	current_upscaler_mode = mode
	if entity_hd_material:
		entity_hd_material.set_shader_parameter("upscaler_mode", mode)
	_apply_texture_filtering()

func set_relief_mode(mode: int) -> void:
	current_relief_mode = mode
	if dungeon_tile_material:
		dungeon_tile_material.set_shader_parameter("relief_mode", mode)

func set_wet_floor(enabled: bool) -> void:
	wet_floor = enabled
	if dungeon_tile_material:
		dungeon_tile_material.set_shader_parameter("wet_floor", enabled)

func set_hdr_level(level: int) -> void:
	current_hdr_level = clamp(level, 0, 3)

func set_tile_model(model_id: int) -> void:
	var new_id = clampi(model_id, 0, UpscalerModelConfig.get_model_count() - 1)
	if current_tile_model == new_id:
		return
	current_tile_model = new_id
	# Invalidate all cached textures so they reload from the new model's directory
	pbr_texture_cache.clear()
	pbr_special_cache.clear()
	player_hd_cache.clear()
	monster_hd_cache.clear()
	player_texture = null
	last_player_frame = -999
	last_player_dir = -999
	last_player_mode = -999
	monster_textures.clear()
	monster_last_frame.clear()
	monster_last_dir.clear()
	corpse_textures.clear()
	corpse_is_hd.clear()
	# Rebuild dungeon tiles with the new model's assets
	rebuild_dungeon_tiles()
	var inline_light = diablo_bridge.get_dungeon_light_grid() if _has_light_grid else PackedByteArray()
	var inline_solid = diablo_bridge.get_dungeon_solidity_grid() if _has_solidity_grid else PackedByteArray()
	var inline_pos = diablo_bridge.get_player_continuous_pos() if _has_player_pos else {}
	update_lighting_and_transparency(inline_light, inline_solid, inline_pos)
	print("[Native 2.5D View] Tile Model switched to: %s" % UpscalerModelConfig.get_model_short_name(current_tile_model))

func get_tile_model() -> int:
	return current_tile_model

func apply_all_d1de_settings(torch: bool, fog: int, upscaler: int, relief: int, wet: bool, hdr: int = 1, tile_model: int = 0) -> void:
	set_soft_torchlight(torch)
	set_atmospheric_fog(fog)
	set_upscaler_mode(upscaler)
	set_relief_mode(relief)
	set_wet_floor(wet)
	set_hdr_level(hdr)
	set_tile_model(tile_model)

func apply_all_resurrected_settings(torch: bool, fog: int, upscaler: int, relief: int, wet: bool, hdr: int = 1, tile_model: int = 0) -> void:
	apply_all_d1de_settings(torch, fog, upscaler, relief, wet, hdr, tile_model)

func activate():
	if floor_root == null:
		setup_scene_hierarchy()
	is_active = true
	_init_bridge_caps()
	var cur_lvl = diablo_bridge.get_current_level() if (_has_current_level and diablo_bridge) else 0
	var cur_grid = diablo_bridge.get_dungeon_grid() if (_has_dungeon_grid and diablo_bridge) else PackedInt32Array()
	var cur_hash = hash(cur_grid) if cur_grid.size() >= 112 * 112 else 0

	var p_pos = diablo_bridge.get_player_continuous_pos() if (_has_player_pos and diablo_bridge) else {}
	var px = float(p_pos.get("pos_x", 25.0))
	var py = float(p_pos.get("pos_y", 25.0))
	var p_target = Vector2((px - py) * 32.0, (px + py) * 16.0 + 16.0)
	if player_node:
		player_node.position = p_target
	if camera:
		camera.position = Vector2((px - py) * 32.0, (px + py) * 16.0)

	# Rebuild only if level changed, grid geometry changed, or tile sprites are not yet created.
	# Preserves cached tile sprites on fast-path mode switches (e.g. 3D -> Blit -> 2.5D) for 0ms instant switching!
	var needs_rebuild = (cur_lvl != last_level_idx) or (cur_hash != last_dungeon_hash) or tile_sprites.is_empty()
	if needs_rebuild:
		var level_changed = (cur_lvl != last_level_idx)
		last_level_idx = cur_lvl
		last_dungeon_hash = cur_hash
		if level_changed and _has_clear_cache and diablo_bridge:
			diablo_bridge.clear_dungeon_piece_cache()
		if cur_grid.size() >= 112 * 112:
			rebuild_dungeon_tiles()
			var inline_light = diablo_bridge.get_dungeon_light_grid() if _has_light_grid else PackedByteArray()
			var inline_solid = diablo_bridge.get_dungeon_solidity_grid() if _has_solidity_grid else PackedByteArray()
			update_lighting_and_transparency(inline_light, inline_solid, p_pos)
			pending_dungeon_rebuild = false
		else:
			pending_dungeon_rebuild = true
	else:
		# Fast-path reactivation: refresh lighting and visible tiles around player
		last_visible_tiles.clear()
		var inline_light = diablo_bridge.get_dungeon_light_grid() if _has_light_grid else PackedByteArray()
		var inline_solid = diablo_bridge.get_dungeon_solidity_grid() if _has_solidity_grid else PackedByteArray()
		update_lighting_and_transparency(inline_light, inline_solid, p_pos)

	visible = true
	set_process(true)
	if camera and camera.is_inside_tree():
		camera.enabled = true
		camera.make_current()
	_update_fog()
	print("[Native 2.5D View] Activated (144Hz Smooth Camera, Y-Sorted Sprites, PointLight2D)")

func deactivate():
	is_active = false
	visible = false
	set_process(false)
	if camera:
		camera.enabled = false
	if fog_layer:
		fog_layer.visible = false
	print("[Native 2.5D View] Deactivated")

func _process(delta: float):
	if not is_active or diablo_bridge == null:
		return

	# Check level change
	if _has_current_level:
		var cur_lvl = diablo_bridge.get_current_level()
		if cur_lvl != last_level_idx:
			last_level_idx = cur_lvl
			pending_dungeon_rebuild = true
			level_stabilize_frames = 6
			pending_secondary_rebuild = false
			_update_fog()

	# Gamma changed (options slider) -> palette-baked textures are stale. Invalidate all of them so the
	# whole scene re-renders with the new palette, matching legacy behaviour where gamma affects the entire
	# image. We poll the gamma VALUE (not the raw palette version), because that counter also ticks every frame
	# for animated lava/glow in cave/crypt levels and would force a full rebuild per frame there.
	if _has_gamma:
		var cur_gamma = diablo_bridge.get_gamma()
		if cur_gamma != last_gamma_value:
			last_gamma_value = cur_gamma
			pending_dungeon_rebuild = true
			player_texture = null
			last_player_frame = -999
			last_player_dir = -999
			last_player_mode = -999
			monster_textures.clear()
			monster_last_frame.clear()
			monster_last_dir.clear()
			object_textures.clear()
			item_textures.clear()
			item_is_hd.clear()
			corpse_textures.clear()
			corpse_is_hd.clear()
			missile_textures.clear()

	if tile_sprites.is_empty():
		pending_dungeon_rebuild = true

	# During level transitions, DevilutionX is tearing down and rebuilding memory.
	# Freeze rendering updates until the new level is 100% ready to eliminate race conditions.
	if _has_level_loading and diablo_bridge.is_level_loading():
		return

	if _has_game_running and not diablo_bridge.is_game_running():
		return

	if level_stabilize_frames > 0:
		level_stabilize_frames -= 1
		return

	if pending_dungeon_rebuild:
		var grid = diablo_bridge.get_dungeon_grid() if _has_dungeon_grid else PackedInt32Array()
		if grid.size() >= 112 * 112:
			var can_fetch = false
			for piece_id in grid:
				if piece_id >= 0:
					var test_tex = diablo_bridge.get_dungeon_piece_texture(piece_id)
					if test_tex != null:
						can_fetch = true
						break
			if can_fetch:
				var p_pos = diablo_bridge.get_player_continuous_pos() if _has_player_pos else {}
				var px = float(p_pos.get("pos_x", 0.0))
				var py = float(p_pos.get("pos_y", 0.0))
				if last_level_idx > 0 and (px <= 0.0 or py <= 0.0):
					# Player position not yet initialized in engine, wait another frame
					return

				if _has_clear_cache:
					diablo_bridge.clear_dungeon_piece_cache()
				rebuild_dungeon_tiles()
				var inline_light = diablo_bridge.get_dungeon_light_grid() if _has_light_grid else PackedByteArray()
				var inline_solid = diablo_bridge.get_dungeon_solidity_grid() if _has_solidity_grid else PackedByteArray()
				var inline_pos = diablo_bridge.get_player_continuous_pos() if _has_player_pos else {}
				update_lighting_and_transparency(inline_light, inline_solid, inline_pos)
				pending_dungeon_rebuild = false
				pending_secondary_rebuild = true
				secondary_rebuild_countdown = 8

	if pending_secondary_rebuild:
		if secondary_rebuild_countdown > 0:
			secondary_rebuild_countdown -= 1
		else:
			pending_secondary_rebuild = false
			rebuild_dungeon_tiles()
			var inline_light = diablo_bridge.get_dungeon_light_grid() if _has_light_grid else PackedByteArray()
			var inline_solid = diablo_bridge.get_dungeon_solidity_grid() if _has_solidity_grid else PackedByteArray()
			var inline_pos = diablo_bridge.get_player_continuous_pos() if _has_player_pos else {}
			update_lighting_and_transparency(inline_light, inline_solid, inline_pos)
			print("[Native 2.5D View] Post-load stabilization rebuild completed (100% assets verified)")

	time_accum += delta

	if fog_layer and fog_layer.visible and fog_material and camera:
		fog_material.set_shader_parameter("camera_offset", camera.position)

	# --- Per-frame shared data (fetch once, pass everywhere) ---
	var frame_light_grid: PackedByteArray = diablo_bridge.get_dungeon_light_grid() if _has_light_grid else PackedByteArray()
	var frame_solidity_grid: PackedByteArray = diablo_bridge.get_dungeon_solidity_grid() if _has_solidity_grid else PackedByteArray()
	var frame_player_pos: Dictionary = diablo_bridge.get_player_continuous_pos() if _has_player_pos else {}

	update_player(delta, frame_light_grid, frame_player_pos)
	update_monsters(delta, frame_light_grid)
	update_torches(frame_light_grid, frame_player_pos)
	update_objects(frame_light_grid, frame_player_pos)
	update_corpses(frame_light_grid)
	update_ground_items(frame_light_grid)
	update_missiles(frame_light_grid)
	update_visual_effects()
	update_lighting_and_transparency(frame_light_grid, frame_solidity_grid, frame_player_pos)

# --- PBR Asset & Linear Wall Occluder Pipeline ---

func load_pbr_occluders():
	var occ_file = "res://assets/dungeon_pbr/occluders.json"
	if FileAccess.file_exists(occ_file):
		var f = FileAccess.open(occ_file, FileAccess.READ)
		if f:
			var json_text = f.get_as_text()
			f.close()
			var json = JSON.new()
			if json.parse(json_text) == OK and typeof(json.data) == TYPE_DICTIONARY:
				pbr_occluders_cache = json.data
				print("[Native 2.5D View] Loaded %d PBR linear wall occluders" % pbr_occluders_cache.size())

func is_cathedral_level() -> bool:
	return last_level_idx >= 1 and last_level_idx <= 4

func is_town_level() -> bool:
	return last_level_idx == 0

func is_dungeon_level() -> bool:
	return last_level_idx > 0

func get_pbr_folder_for_level() -> String:
	# Delegate to UpscalerModelConfig for the selected neural upscale model
	var folder = UpscalerModelConfig.get_tile_folder(last_level_idx, current_tile_model)
	# Graceful fallback: if selected model's directory doesn't exist, use default (model 0)
	if current_tile_model > 0 and folder != "":
		var alb_dir = folder + "/albedo"
		if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(alb_dir)):
			folder = UpscalerModelConfig.get_tile_folder(last_level_idx, 0)
	return folder

func get_pbr_or_base_texture(piece_id: int) -> Texture2D:
	if pbr_texture_cache.has(piece_id):
		return pbr_texture_cache[piece_id]

	# Always fetch authentic ground-truth engine piece for validation & fallback
	var base_tex: Texture2D = null
	if diablo_bridge and _has_piece_texture:
		base_tex = diablo_bridge.get_dungeon_piece_texture(piece_id)

	# If HD is disabled (Authentic 1996) or Town level (GEMINI.md Rule #1: Town Isolation), return pure engine texture:
	if not hd_graphics_enabled or is_town_level():
		if base_tex:
			pbr_texture_cache[piece_id] = base_tex
		return base_tex

	var base_folder = get_pbr_folder_for_level()
	if base_folder == "":
		if base_tex:
			pbr_texture_cache[piece_id] = base_tex
		return base_tex
	var alb_path = "%s/albedo/piece_%d.png" % [base_folder, piece_id]
	var norm_path = "%s/normal/piece_%d_n.png" % [base_folder, piece_id]
	var spec_path = "%s/specular/piece_%d_s.png" % [base_folder, piece_id]

	# Fallback to secondary PBR directory if primary 4X folder doesn't have this piece
	if not FileAccess.file_exists(alb_path):
		if is_cathedral_level():
			# Try model-specific fallback first, then default model's fallback
			var fb = UpscalerModelConfig.get_fallback_tile_folder(last_level_idx, current_tile_model)
			if fb == "" or not FileAccess.file_exists("%s/albedo/piece_%d.png" % [fb, piece_id]):
				fb = UpscalerModelConfig.get_fallback_tile_folder(last_level_idx, 0)
			if fb != "":
				alb_path = "%s/albedo/piece_%d.png" % [fb, piece_id]
				norm_path = "%s/normal/piece_%d_n.png" % [fb, piece_id]
				spec_path = "%s/specular/piece_%d_s.png" % [fb, piece_id]
		elif current_tile_model != 0:
			var default_folder = UpscalerModelConfig.get_tile_folder(last_level_idx, 0)
			if default_folder != "" and FileAccess.file_exists("%s/albedo/piece_%d.png" % [default_folder, piece_id]):
				alb_path = "%s/albedo/piece_%d.png" % [default_folder, piece_id]
				norm_path = "%s/normal/piece_%d_n.png" % [default_folder, piece_id]
				spec_path = "%s/specular/piece_%d_s.png" % [default_folder, piece_id]

	if FileAccess.file_exists(alb_path) and FileAccess.file_exists(norm_path):
		var alb_img = Image.load_from_file(ProjectSettings.globalize_path(alb_path))
		var norm_img = Image.load_from_file(ProjectSettings.globalize_path(norm_path))
		if alb_img and not alb_img.is_empty() and norm_img and not norm_img.is_empty():
			# Validate that PBR asset world height matches authentic engine piece height
			if base_tex != null:
				var pbr_world_h = int(round(float(alb_img.get_height()) * (64.0 / float(alb_img.get_width()))))
				if abs(pbr_world_h - base_tex.get_height()) > 4:
					# Defective/mismatched crop on disk, bypass and use authentic engine texture!
					pbr_texture_cache[piece_id] = base_tex
					return base_tex
			alb_img.generate_mipmaps()
			norm_img.generate_mipmaps()
			var ct = CanvasTexture.new()
			ct.diffuse_texture = ImageTexture.create_from_image(alb_img)
			ct.normal_texture = ImageTexture.create_from_image(norm_img)
			var orm_path = "%s/orm/piece_%d_orm.png" % [base_folder, piece_id]
			var final_spec_path = spec_path if FileAccess.file_exists(spec_path) else (orm_path if FileAccess.file_exists(orm_path) else "")
			if final_spec_path != "":
				var spec_img = Image.load_from_file(ProjectSettings.globalize_path(final_spec_path))
				if spec_img and not spec_img.is_empty():
					spec_img.generate_mipmaps()
					ct.specular_texture = ImageTexture.create_from_image(spec_img)
					ct.specular_shininess = 1.0
					ct.specular_color = Color(1.0, 1.0, 1.0)
			ct.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			pbr_texture_cache[piece_id] = ct
			return ct

	# Fallback to vanilla engine texture (in HD mode, this still gets linear filtering and real-time procedural relief!)
	if base_tex:
		pbr_texture_cache[piece_id] = base_tex
		return base_tex
	return null

func get_pbr_or_base_special_texture(special_id: int) -> Texture2D:
	if pbr_special_cache.has(special_id):
		return pbr_special_cache[special_id]

	# Always fetch authentic ground-truth special cel
	var base_tex: Texture2D = null
	if diablo_bridge and _has_special_cel:
		base_tex = diablo_bridge.get_special_cel_texture(special_id)

	# If HD is disabled (Authentic 1996) or non-Cathedral level, return pure engine special cel.
	if not hd_graphics_enabled or not is_cathedral_level():
		if base_tex:
			pbr_special_cache[special_id] = base_tex
		return base_tex

	var base_folder = get_pbr_folder_for_level()
	var alb_path = "%s/albedo/special_%d.png" % [base_folder, special_id]
	var norm_path = "%s/normal/special_%d_n.png" % [base_folder, special_id]
	var spec_path = "%s/specular/special_%d_s.png" % [base_folder, special_id]

	# Fallback to secondary PBR directory if primary 4X folder doesn't have this special
	if not FileAccess.file_exists(alb_path):
		if is_cathedral_level():
			# Try model-specific fallback first, then default model's fallback
			var fb = UpscalerModelConfig.get_fallback_tile_folder(last_level_idx, current_tile_model)
			if fb == "" or not FileAccess.file_exists("%s/albedo/special_%d.png" % [fb, special_id]):
				fb = UpscalerModelConfig.get_fallback_tile_folder(last_level_idx, 0)
			if fb != "":
				alb_path = "%s/albedo/special_%d.png" % [fb, special_id]
				norm_path = "%s/normal/special_%d_n.png" % [fb, special_id]
				spec_path = "%s/specular/special_%d_s.png" % [fb, special_id]

	if FileAccess.file_exists(alb_path) and FileAccess.file_exists(norm_path):
		var alb_img = Image.load_from_file(ProjectSettings.globalize_path(alb_path))
		var norm_img = Image.load_from_file(ProjectSettings.globalize_path(norm_path))
		if alb_img and not alb_img.is_empty() and norm_img and not norm_img.is_empty():
			if base_tex != null:
				var pbr_world_h = int(round(float(alb_img.get_height()) * (64.0 / float(alb_img.get_width()))))
				if abs(pbr_world_h - base_tex.get_height()) > 4:
					pbr_special_cache[special_id] = base_tex
					return base_tex
			alb_img.generate_mipmaps()
			norm_img.generate_mipmaps()
			var ct = CanvasTexture.new()
			ct.diffuse_texture = ImageTexture.create_from_image(alb_img)
			ct.normal_texture = ImageTexture.create_from_image(norm_img)
			var orm_path = "%s/orm/special_%d_orm.png" % [base_folder, special_id]
			var final_spec_path = spec_path if FileAccess.file_exists(spec_path) else (orm_path if FileAccess.file_exists(orm_path) else "")
			if final_spec_path != "":
				var spec_img = Image.load_from_file(ProjectSettings.globalize_path(final_spec_path))
				if spec_img and not spec_img.is_empty():
					spec_img.generate_mipmaps()
					ct.specular_texture = ImageTexture.create_from_image(spec_img)
					ct.specular_shininess = 1.0
					ct.specular_color = Color(1.0, 1.0, 1.0)
			ct.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			pbr_special_cache[special_id] = ct
			return ct

	if base_tex:
		pbr_special_cache[special_id] = base_tex
		return base_tex
	return null

func ensure_pbr_assets_for_level(grid: PackedInt32Array, special_grid: PackedInt32Array):
	if last_level_idx <= 0:
		return
	var base_folder = get_pbr_folder_for_level()
	if base_folder == "":
		return
	var missing_count = 0
	var raw_dir = "%s/raw" % base_folder
	var alb_dir = "%s/albedo" % base_folder

	var needed_pieces: Dictionary = {}
	for idx in range(grid.size()):
		var pid = grid[idx]
		if pid >= 0:
			needed_pieces[pid] = true

	for pid in needed_pieces.keys():
		var alb_file = "%s/piece_%d.png" % [alb_dir, pid]
		if not FileAccess.file_exists(alb_file):
			var raw_file = "%s/piece_%d.png" % [raw_dir, pid]
			if not FileAccess.file_exists(raw_file):
				if diablo_bridge and _has_piece_texture:
					var rtex = diablo_bridge.get_dungeon_piece_texture(pid)
					if rtex:
						var rimg = rtex.get_image()
						if rimg and not rimg.is_empty():
							rimg.save_png(ProjectSettings.globalize_path(raw_file))
							missing_count += 1

	for idx in range(special_grid.size()):
		var sid = special_grid[idx]
		if sid > 0:
			var alb_file = "%s/special_%d.png" % [alb_dir, sid]
			if not FileAccess.file_exists(alb_file):
				var raw_file = "%s/special_%d.png" % [raw_dir, sid]
				if not FileAccess.file_exists(raw_file):
					if diablo_bridge and _has_special_cel:
						var stex = diablo_bridge.get_special_cel_texture(sid)
						if stex:
							var simg = stex.get_image()
							if simg and not simg.is_empty():
								simg.save_png(ProjectSettings.globalize_path(raw_file))
								missing_count += 1

	if missing_count > 0:
		print("[Native 2.5D View] %d tiles lack prebaked 4x PBR maps; using engine texture fallback." % missing_count)
	load_pbr_occluders()

func rebuild_dungeon_tiles():
	if not diablo_bridge or not _has_dungeon_grid:
		return

	var grid = diablo_bridge.get_dungeon_grid()
	if grid.size() < 112 * 112:
		return

	# Clear previous tile sprites
	for pos_key in tile_sprites:
		var spr = tile_sprites[pos_key]
		if is_instance_valid(spr):
			spr.queue_free()
	tile_sprites.clear()
	tile_piece_ids.clear()
	tile_special_ids.clear()

	# Clear previous upper wall and scenery sprites
	for pos_key in wall_sprites:
		var spr = wall_sprites[pos_key]
		if is_instance_valid(spr):
			spr.queue_free()
	wall_sprites.clear()
	last_visible_tiles.clear()
	pbr_texture_cache.clear()
	pbr_special_cache.clear()

	# Clear previous tile occluders
	for occ in tile_occluders.values():
		if is_instance_valid(occ):
			occ.queue_free()
	tile_occluders.clear()

	# Clear previous special cel sprites (arches / column tops)
	for pos_key in special_sprites:
		var spr = special_sprites[pos_key]
		if is_instance_valid(spr):
			spr.queue_free()
	special_sprites.clear()

	# Clear previous objects
	for o_id in object_sprites:
		var spr = object_sprites[o_id]
		if is_instance_valid(spr):
			spr.queue_free()
	object_sprites.clear()
	object_textures.clear()

	# Clear previous ground items
	for i_id in item_nodes:
		var node = item_nodes[i_id]
		if is_instance_valid(node):
			node.queue_free()
	item_nodes.clear()
	item_textures.clear()
	item_is_hd.clear()

	# Clear previous corpses
	for pos_key in corpse_sprites:
		var spr = corpse_sprites[pos_key]
		if is_instance_valid(spr):
			spr.queue_free()
	corpse_sprites.clear()
	corpse_textures.clear()
	corpse_is_hd.clear()

	# Clear previous missiles
	for m_id in missile_nodes:
		var node = missile_nodes[m_id]
		if is_instance_valid(node):
			node.queue_free()
	missile_nodes.clear()
	missile_textures.clear()

	# Clear previous monsters / NPCs
	for m_id in monster_nodes:
		var node = monster_nodes[m_id]
		if is_instance_valid(node):
			node.queue_free()
	monster_nodes.clear()
	monster_textures.clear()
	monster_last_frame.clear()
	monster_last_dir.clear()
	monster_shadow_materials.clear()

	player_texture = null
	last_player_frame = -999
	last_player_dir = -999
	last_player_mode = -999

	var special_grid = PackedInt32Array()
	if _has_special_grid:
		special_grid = diablo_bridge.get_dungeon_special_grid()

	var solidity_grid = PackedByteArray()
	if _has_solidity_grid:
		solidity_grid = diablo_bridge.get_dungeon_solidity_grid()

	ensure_pbr_assets_for_level(grid, special_grid)
	if dungeon_tile_material:
		dungeon_tile_material.set_shader_parameter("is_town", last_level_idx == 0)
		dungeon_tile_material.set_shader_parameter("is_lava_level", last_level_idx >= 9)

	var count = 0
	var special_count = 0
	for y in range(112):
		for x in range(112):
			var idx = y * 112 + x
			var piece_id = grid[idx]
			var special_id = special_grid[idx] if idx < special_grid.size() else 0
			# Y-sort depth key = bottom vertex of the tile diamond (position.y), matching vanilla D1's
			# depth ordering: sprites are sorted by their feet position, tiles by their south point.
			var tile_pos = Vector2(float(x - y) * 32.0, float(x + y) * 16.0 + 16.0)

			# 1. Base Dungeon Piece (Floor & Walls) - PBR Normal Mapped & Delighted
			var is_valid_piece = (piece_id >= 0)

			if is_valid_piece:
				var tex: Texture2D = get_pbr_or_base_texture(piece_id)
				if tex != null:
					var tw = tex.get_width()
					var th = tex.get_height()
					var scale_factor = 64.0 / float(tw)
					var floor_h = int(round(float(tw) * 0.5)) # 32 for 64w, 128 for 256w
					var is_wall = (th > floor_h)

					var is_hd_asset = (tw >= 256)
					var spr = Sprite2D.new()
					spr.texture = tex
					spr.material = dungeon_tile_material
					spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if (hd_graphics_enabled and is_hd_asset) else CanvasItem.TEXTURE_FILTER_NEAREST
					spr.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
					spr.centered = false
					spr.scale = Vector2(scale_factor, scale_factor)
					spr.position = tile_pos
					spr.offset = Vector2(-float(tw) * 0.5, -float(th))
					spr.self_modulate = Color(1.0, 1.0, 1.0)
					spr.visible = false
					spr.z_index = 0 if is_wall else -2
					if is_wall:
						world_root.add_child(spr)
					else:
						floor_root.add_child(spr)
					if is_wall:
						wall_sprites[Vector2i(x, y)] = spr
					else:
						tile_sprites[Vector2i(x, y)] = spr
					tile_piece_ids[Vector2i(x, y)] = piece_id
					count += 1

			# 2. Milestone 1: Special CELs (Archways, Column Tops, Doorways) - PBR (Cathedral only)
			if special_id > 0 and is_cathedral_level() and (solidity_grid.size() < 112 * 112 or solidity_grid[idx] != 0):
				tile_special_ids[Vector2i(x, y)] = special_id
				var arch_tex: Texture2D = get_pbr_or_base_special_texture(special_id)
				if arch_tex != null:
					var arch_spr = Sprite2D.new()
					arch_spr.texture = arch_tex
					arch_spr.material = dungeon_tile_material
					arch_spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if hd_graphics_enabled else CanvasItem.TEXTURE_FILTER_NEAREST
					arch_spr.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
					arch_spr.centered = false
					var atw = arch_tex.get_width()
					var ath = arch_tex.get_height()
					var a_scale = 64.0 / float(atw)
					arch_spr.scale = Vector2(a_scale, a_scale)
					arch_spr.position = tile_pos
					arch_spr.offset = Vector2(-float(atw) * 0.5, -float(ath))
					# Initialize hidden in deep gothic darkness / fog of war
					arch_spr.self_modulate = Color(1.0, 1.0, 1.0)
					arch_spr.visible = false
					arch_spr.z_index = 0 # Y-sorted with walls!
					world_root.add_child(arch_spr)
					special_sprites[Vector2i(x, y)] = arch_spr
					special_count += 1

			# 3. Environment Wall & Pillar Linear Spine Occluders (PCF13)
			if is_cathedral_level() and enable_wall_occluders and idx < solidity_grid.size() and solidity_grid[idx] == 2:
				var occ_key = "piece_%d" % piece_id
				var occ_data = pbr_occluders_cache.get(occ_key, null)
				if occ_data and occ_data.get("type", "none") != "none":
					var pts = occ_data.get("points", [])
					if pts.size() >= 2:
						var occ = LightOccluder2D.new()
						var occ_poly = OccluderPolygon2D.new()
						var p_arr = PackedVector2Array()
						for pt in pts:
							p_arr.append(Vector2(float(pt[0]), float(pt[1])))
						occ_poly.polygon = p_arr
						occ_poly.cull_mode = OccluderPolygon2D.CULL_DISABLED
						occ.occluder = occ_poly
						occ.position = tile_pos
						occ.visible = false
						world_root.add_child(occ)
						tile_occluders[Vector2i(x, y)] = occ

	last_dungeon_hash = hash(grid)
	if _has_current_level and diablo_bridge:
		last_level_idx = diablo_bridge.get_current_level()
	print("[Native 2.5D View] Rebuilt %d dungeon tiles and %d special archways/column tops" % [count, special_count])

func _apply_zoom_vision(z: float) -> void:
	var zoom_boost = clampf(1.5 / z, 1.0, 2.2)
	var d1_rad = int(clampf(10.0 * zoom_boost, 10.0, 15.0))
	if diablo_bridge and _has_zoom_vision:
		diablo_bridge.set_zoom_vision_radius(d1_rad)
	if player_light:
		player_light.texture_scale = 2.4 * zoom_boost
		player_light.energy = 1.05 * clampf(zoom_boost, 1.0, 1.35)

func update_lighting_and_transparency(light_grid: PackedByteArray, solidity_grid: PackedByteArray, player_pos: Dictionary):
	if not diablo_bridge:
		return



	var flags_grid: PackedByteArray = PackedByteArray()
	if _has_flags_grid:
		flags_grid = diablo_bridge.get_dungeon_flags_grid()



	var trans_grid: PackedByteArray = PackedByteArray()
	if _has_trans_grid:
		trans_grid = diablo_bridge.get_dungeon_trans_grid()

	var trans_mask: PackedByteArray = PackedByteArray()
	if _has_trans_mask:
		trans_mask = diablo_bridge.get_dungeon_trans_mask()

	var trans_list: PackedByteArray = PackedByteArray()
	if _has_trans_list:
		trans_list = diablo_bridge.get_trans_list()

	var special_grid: PackedInt32Array = PackedInt32Array()
	if _has_special_grid:
		special_grid = diablo_bridge.get_dungeon_special_grid()

	var has_light = (light_grid.size() >= 112 * 112)
	var has_flags = (flags_grid.size() >= 112 * 112)
	var has_solidity = (solidity_grid.size() >= 112 * 112)
	var has_trans = (trans_grid.size() >= 112 * 112 and trans_list.size() >= 256)
	var has_trans_mask = (trans_mask.size() >= 112 * 112)

	var p_pos = player_pos
	var p_tx = int(p_pos.get("pos_x", 25.0))
	var p_ty = int(p_pos.get("pos_y", 25.0))

	var z = camera.zoom.x if camera else 1.0
	var zoom_boost = clampf(1.5 / z, 1.0, 2.2)
	var rad_x = int(clamp(60.0 / z, 44.0, 80.0))
	var rad_y = int(clamp(50.0 / z, 36.0, 70.0))
	var min_x = max(0, p_tx - rad_x)
	var max_x = min(111, p_tx + rad_x)
	var min_y = max(0, p_ty - rad_y)
	var max_y = min(111, p_ty + rad_y)

	var new_active_keys: Dictionary = {}

	var is_town = (last_level_idx == 0)
	if dungeon_tile_material:
		dungeon_tile_material.set_shader_parameter("is_town", is_town)
		dungeon_tile_material.set_shader_parameter("is_lava_level", last_level_idx >= 9)

	# Milestone 2: Continuous GPU Bilinear Lightmap Update (0.01ms update, silky-smooth pixel lighting)
	var light_bytes = PackedByteArray()
	if has_light and light_image and light_map_texture:
		light_bytes.resize(112 * 112)
		for ty in range(112):
			for tx in range(112):
				var i = ty * 112 + tx
				var solid = solidity_grid[i] if has_solidity else 1

				# In Cathedral, uncarved rock outside rooms is pitch black void
				if solid == 0 and is_cathedral_level():
					light_bytes[i] = 0
					continue

				var l_val = light_grid[i]
				var factor = 0.0
				if l_val < 15:
					factor = pow(clampf((15.0 - float(l_val)) / 15.0, 0.0, 1.0), 0.72)

				if is_town:
					light_bytes[i] = int(clampf((15.0 - float(l_val)) / 15.0, 0.0, 1.0) * 255.0)
				else:
					light_bytes[i] = int(clampf(factor * 255.0, 0.0, 255.0))
		light_image.set_data(112, 112, false, Image.FORMAT_R8, light_bytes)
		light_map_texture.update(light_image)

	for ty in range(min_y, max_y + 1):
		for tx in range(min_x, max_x + 1):
			var pos_key = Vector2i(tx, ty)
			var spr = tile_sprites.get(pos_key, null)
			var wall_spr = wall_sprites.get(pos_key, null)
			var arch_spr = special_sprites.get(pos_key, null)
			if spr == null and wall_spr == null and arch_spr == null:
				continue

			var idx = ty * 112 + tx
			new_active_keys[pos_key] = true

			if spr:
				spr.visible = true
				spr.self_modulate = Color(1.0, 1.0, 1.0)
				spr.modulate.a = 1.0 # Floor diamond is ALWAYS 100% solid opaque!

			var wall_alpha = 1.0
			if has_trans and has_trans_mask and trans_mask[idx] != 0:
				var trans_val = trans_grid[idx]
				if trans_val > 0 and trans_val < trans_list.size() and trans_list[trans_val] != 0:
					wall_alpha = 0.65 # Soft natural stone translucency

			if wall_spr:
				wall_spr.visible = true
				wall_spr.self_modulate = Color(1.0, 1.0, 1.0)
				wall_spr.modulate.a = wall_alpha

			if arch_spr:
				arch_spr.visible = true
				arch_spr.self_modulate = Color(1.0, 1.0, 1.0)
				arch_spr.modulate.a = wall_alpha

			if enable_wall_occluders:
				var occ = tile_occluders.get(pos_key, null)
				if occ:
					occ.visible = true

	# Hide tiles that moved outside viewport or active range
	for prev_key in last_visible_tiles:
		if not new_active_keys.has(prev_key):
			var old_spr = tile_sprites.get(prev_key, null)
			if old_spr:
				old_spr.visible = false
				old_spr.modulate.a = 1.0
			var old_wall = wall_sprites.get(prev_key, null)
			if old_wall:
				old_wall.visible = false
				old_wall.modulate.a = 1.0
			var old_arch = special_sprites.get(prev_key, null)
			if old_arch:
				old_arch.visible = false
				old_arch.modulate.a = 1.0
			if enable_wall_occluders:
				var old_occ = tile_occluders.get(prev_key, null)
				if old_occ: old_occ.visible = false
	last_visible_tiles = new_active_keys

func calculate_shadow_skew_for_position(world_pos: Vector2) -> Dictionary:
	var result = {
		"skew": Vector2(0.24, 0.42),
		"length": 0.85,
		"opacity": 0.52
	}
	if not diablo_bridge or not _has_active_lights:
		return result

	var lights: Array = diablo_bridge.get_active_lights()
	var best_dist: float = 999999.0
	var best_light_pos: Vector2 = Vector2.ZERO
	var found_env_light: bool = false

	# Check active environmental and spell lights (torches, braziers, fireballs at index 1..N)
	for i in range(1, lights.size()):
		var l_info = lights[i]
		var tx = float(l_info.get("tile_x", 0))
		var ty = float(l_info.get("tile_y", 0))
		var lp = Vector2((tx - ty) * 32.0, (tx + ty) * 16.0 - 10.0)
		var d = world_pos.distance_to(lp)
		var rad_px = float(l_info.get("radius", 6)) * 42.0
		if d < rad_px and d < best_dist:
			best_dist = d
			best_light_pos = lp
			found_env_light = true

	if found_env_light:
		var delta = world_pos - best_light_pos
		var d = max(16.0, delta.length())
		var dir = delta / d
		# Shadow casts away from light
		# Horizontal skew up to +/- 0.85
		var sx = clampf(dir.x * 0.75, -0.85, 0.85)
		# Vertical skew compressed for 2:1 isometric ground plane
		var sy = clampf(dir.y * 0.45, -0.65, 0.65)
		# Prevent slit degeneration if light is exactly lateral
		if abs(sy) < 0.20:
			sy = 0.20 if sy >= 0.0 else -0.20

		var slen = clampf(0.65 + (d / 180.0) * 0.60, 0.60, 1.40)
		var sop = clampf(0.60 * (1.0 - (d / 380.0)), 0.25, 0.60)
		result["skew"] = Vector2(sx, sy)
		result["length"] = slen
		result["opacity"] = sop
	else:
		# Ambient / hero torch held in hand (slightly in front/right)
		result["skew"] = Vector2(0.24, 0.42)
		result["length"] = 0.85
		result["opacity"] = 0.50

	return result

func get_hd_player_sprite(p_class: int, mode: int, dir: int, frame: int) -> Texture2D:
	if not hd_graphics_enabled:
		return null
	# Hero sprites in Diablo 1 are dynamically composed by DevilutionX based on class
	# (Warrior=0, Rogue=1, Sorcerer=2, Monk=3, Bard=4, Barbarian=5), equipped armor tiers
	# (cloth/leather/plate), weapons (staff, bow, sword, axe, shield), and class TRN palettes.
	# For non-Warrior classes (e.g. Sorcerer, Rogue) or when live equipment rendering is active,
	# return null so the engine falls back to diablo_bridge.get_player_sprite_data().
	# This ensures 100% authentic hero visuals, proper equipment, authentic class colors,
	# and prevents the 'dark warrior silhouette' regression, while still benefiting from
	# real-time GPU subpixel upscaling via entity_hd_upscaler.gdshader (xBRZ / SDF).
	if p_class != 0:
		return null

	# Pre-rendered warrior sprites currently lack class TRN translation (causing pitch-black silhouettes)
	# and do not reflect equipped weapons/armors. Returning null allows DevilutionX's live RGBA
	# extraction to render the authentic hero with full equipment and correct palette.
	return null

const MONSTER_NAME_MAP: Dictionary = {
	"zombie": "zombie_zombie",
	"ghoul": "zombie_zombie",
	"rotting carcass": "zombie_zombie",
	"black death": "zombie_zombie",
	"fallen one": "falspear_phall",
	"carver": "falspear_phall",
	"devil kin": "falspear_phall",
	"dark one": "falspear_phall",
	"skeleton": "skelaxe_sklax",
	"corpse axe": "skelaxe_sklax",
	"burning dead": "skelaxe_sklax",
	"horror": "skelaxe_sklax",
	"skeleton captain": "skelsd_sklsr",
	"corpse captain": "skelsd_sklsr",
	"burning dead captain": "skelsd_sklsr",
	"horror captain": "skelsd_sklsr",
	"corpse bow": "skelbow_sklbw",
	"burning dead bow": "skelbow_sklbw",
	"horror bow": "skelbow_sklbw",
	"scavenger": "scav_scav",
	"plague eater": "scav_scav",
	"shadow beast": "scav_scav",
	"bone gasher": "scav_scav",
	"hidden": "sneak_sneak",
	"stalker": "sneak_sneak",
	"unseen": "sneak_sneak",
	"illusion weaver": "sneak_sneak",
	"the butcher": "fatc_fatc",
	"butcher": "fatc_fatc",
	"skeleton king": "sking_sking",
	"king leoric": "sking_sking",
	"diablo": "diablo_diablo",
	"the dark lord": "diablo_diablo",
	"overlord": "fat_fat",
	"mud man": "fat_fat",
	"toad demon": "fat_fat",
	"flayed one": "fat_fat",
	"satyr lord": "goatlord_goatl",
	"goat lord": "goatlord_goatl",
	"flesh clan": "goatmace_goat",
	"stone clan": "goatmace_goat",
	"fire clan": "goatmace_goat",
	"night clan": "goatmace_goat",
	"flesh clan bow": "goatbow_goatb",
	"stone clan bow": "goatbow_goatb",
	"fire clan bow": "goatbow_goatb",
	"night clan bow": "goatbow_goatb",
	"fiend": "bat_bat",
	"blink": "bat_bat",
	"gloom": "bat_bat",
	"familiar": "bat_bat",
	"acid beast": "acid_acid",
	"poison spitter": "acid_acid",
	"pit beast": "acid_acid",
	"lava maw": "acid_acid",
	"wyrm": "worm_worm",
	"cave slug": "worm_worm",
	"devil wyrm": "worm_worm",
	"devourer": "worm_worm",
	"magma demon": "magma_magma",
	"blood stone": "magma_magma",
	"hell stone": "magma_magma",
	"lava lord": "magma_magma",
	"horned demon": "rhino_rhino",
	"mud runner": "rhino_rhino",
	"frost charger": "rhino_rhino",
	"obsidian lord": "rhino_rhino",
	"gargoyle": "gargoyle_gargo",
	"blood claw": "gargoyle_gargo",
	"death wing": "gargoyle_gargo",
	"winged-demon": "gargoyle_gargo",
	"succubus": "succ_scbs",
	"snow witch": "succ_scbs",
	"hell spawn": "succ_scbs",
	"soul burner": "succ_scbs",
	"black knight": "black_black",
	"doom guard": "black_black",
	"steel lord": "black_black",
	"blood knight": "black_black",
	"mage": "mage_mage",
	"cabalist": "mage_mage",
	"advocate": "mage_mage",
	"counselor": "mage_mage",
	"magistrate": "mage_mage",
	"dark mage": "darkmage_dmage",
	"the arch-litch malignus": "darkmage_dmage",
	"snake": "snake_snake",
	"viper": "snake_snake",
	"cave viper": "snake_snake",
	"fire drake": "snake_snake",
	"gold viper": "snake_snake",
	"azure drake": "snake_snake",
	"spider": "spider_spider",
	"arachnon": "spider_spider",
	"spider lord": "bspidr_bspidr",
	"black spider": "bspidr_bspidr",
	"balrog": "mega_mega",
	"slayer": "mega_mega",
	"guardian": "mega_mega",
	"vortex lord": "mega_mega",
	"fire man": "fireman_firem",
	"fireman": "fireman_firem",
	"hell burner": "fireman_firem",
	"flame lord": "fireman_firem",
	"incinerator": "fireman_firem",
	"doom fire": "fireman_firem",
	"golem": "golem_golem",
	"hork demon": "horkd_horkd",
	"hork spawn": "spawn_spawn",
	"unraveler": "unrav_unrav",
	"hollow one": "unrav_unrav",
	"pain master": "unrav_unrav",
	"reality weaver": "unrav_unrav",
	"the shredded": "unrav_unrav",
	"bone demon": "demskel_demskl",
	"skullwing": "demskel_demskl",
	"biclops": "byclps_byclps",
	"crypt demon": "bubba_bubba",
	"gravedigger": "gravdg_gravdg",
	"hellbug": "hellbug_hellbg",
	"hellboar": "fork_fork",
	"flesh thing": "flesh_flesh",
	"lashworm": "clasp_clasp",
	"lich": "lich_lich",
	"arch lich": "lich2_lich2",
	"litch demon": "thin_thin",
	"maelstrom": "thin_thin",
	"red death": "thin_thin",
	"red storm": "thin_thin",
	"storm lord": "thin_thin",
	"storm rider": "thin_thin",
	"undead balrog": "thin_thin",
	"na-krul": "nkr_nkr",
	"tomb rat": "rat_rat",
	"reaper": "reaper_reap",
	"scorpion": "scorp_scorp",
	"stinger": "scorp_scorp",
	"venomtail": "wscorp_wscorp",
	"eye": "eye_eye",
	"psychorb": "eye_eye",
	"eye2": "eye2_eye2",
	"necromorb": "eye2_eye2",
	"griswold": "towners_smith_smithn",
	"pepin": "towners_healer_healer",
	"cain": "towners_strytell_strytell",
	"deckard cain": "towners_strytell_strytell",
	"ogden": "towners_twnf_twnfn",
	"adria": "towners_townwmn1_witch",
	"gillian": "towners_townwmn1_wmnn",
	"wirt": "towners_townboy_pegkid1",
	"farnham": "towners_drunk_twndrunk",
	"cow": "towners_animals_cow",
	"wounded townsman": "towners_butch_deadguy"
}

var _corrupted_sprites_log: Dictionary = {
	"corrupted_files": {},
	"live_fallbacks": {}
}
var _log_file_dirty: bool = false

func _log_corrupted_hd_file(file_path: String, reason: String = "Corrupted black texture") -> void:
	if not _corrupted_sprites_log["corrupted_files"].has(file_path):
		_corrupted_sprites_log["corrupted_files"][file_path] = {
			"timestamp": Time.get_datetime_string_from_system(),
			"reason": reason
		}
		_log_file_dirty = true
		push_warning("[HD Fallback] Corrupted sprite detected: %s (%s)" % [file_path, reason])

func _log_live_fallback(entity_type: String, name_or_id: String, details: String) -> void:
	var key = "%s:%s" % [entity_type, name_or_id]
	if not _corrupted_sprites_log["live_fallbacks"].has(key):
		_corrupted_sprites_log["live_fallbacks"][key] = {
			"timestamp": Time.get_datetime_string_from_system(),
			"type": entity_type,
			"name": name_or_id,
			"details": details
		}
		_log_file_dirty = true
		print("[HD Fallback] Live engine extraction active for %s: %s (%s)" % [entity_type, name_or_id, details])

func _flush_corrupted_log() -> void:
	if not _log_file_dirty:
		return
	_log_file_dirty = false
	var json_text = JSON.stringify(_corrupted_sprites_log, "\t")
	var paths = [
		ProjectSettings.globalize_path("res://logs/corrupted_hd_sprites.json"),
		"user://corrupted_hd_sprites.json"
	]
	for p in paths:
		var f = FileAccess.open(p, FileAccess.WRITE)
		if f:
			f.store_string(json_text)
			f.close()

func _is_texture_corrupted_black(img: Image) -> bool:
	if img == null or img.is_empty():
		return true
	var w = img.get_width()
	var h = img.get_height()
	var opaque_count = 0
	var max_rgb = 0.0
	# Sample dense grid across the sprite bounding area
	var step_x = max(1, w / 16)
	var step_y = max(1, h / 16)
	for y in range(0, h, step_y):
		for x in range(0, w, step_x):
			var col = img.get_pixel(x, y)
			if col.a > 0.15:
				opaque_count += 1
				var rgb_val = maxf(col.r, maxf(col.g, col.b))
				if rgb_val > max_rgb:
					max_rgb = rgb_val
				if max_rgb > 0.08:
					# Found colorful pixels, definitely not pitch black!
					return false
	if opaque_count == 0:
		# If grid missed, check crosshair axes
		for x in range(0, w, max(1, w / 32)):
			for y in [h / 4, h / 2, 3 * h / 4]:
				var col = img.get_pixel(x, y)
				if col.a > 0.15:
					opaque_count += 1
					var rgb_val = maxf(col.r, maxf(col.g, col.b))
					if rgb_val > max_rgb:
						max_rgb = rgb_val
					if max_rgb > 0.08:
						return false
	# If opaque pixels exist and all are near pitch-black (max_rgb <= 0.06), it is corrupted!
	if opaque_count > 0 and max_rgb <= 0.06:
		return true
	return false

func get_hd_monster_sprite(m_name: String, mode: int, dir: int, frame: int, _m_type: int = -1) -> Texture2D:
	if not hd_graphics_enabled:
		return null

	var name_lower = m_name.strip_edges().to_lower()
	var prefix = MONSTER_NAME_MAP.get(name_lower, "")
	if prefix == "":
		if "butcher" in name_lower:
			prefix = "fatc_fatc"
		elif "leoric" in name_lower or "skeleton king" in name_lower:
			prefix = "sking_sking"
		elif "diablo" in name_lower:
			prefix = "diablo_diablo"
		elif "skeleton" in name_lower or "skel" in name_lower:
			prefix = "skelaxe_sklax"
		elif "fallen" in name_lower or "carver" in name_lower:
			prefix = "falspear_phall"
		elif "zombie" in name_lower or "ghoul" in name_lower:
			prefix = "zombie_zombie"
		elif "overlord" in name_lower or "fat" in name_lower:
			prefix = "fat_fat"
		elif "scav" in name_lower or "beast" in name_lower:
			prefix = "scav_scav"
		elif "goat" in name_lower or "satyr" in name_lower:
			prefix = "goatmace_goat"
		elif "bat" in name_lower or "fiend" in name_lower:
			prefix = "bat_bat"
		elif "spider" in name_lower:
			prefix = "spider_spider"
		elif "acid" in name_lower or "spitter" in name_lower:
			prefix = "acid_acid"
		elif "knight" in name_lower:
			prefix = "black_black"
		elif "witch" in name_lower or "succubus" in name_lower:
			prefix = "succ_scbs"
		elif "gargoyle" in name_lower:
			prefix = "gargoyle_gargo"
		elif "magma" in name_lower:
			prefix = "magma_magma"
		elif "snake" in name_lower or "viper" in name_lower:
			prefix = "snake_snake"
		elif "mage" in name_lower:
			prefix = "mage_mage"

	if prefix == "":
		return null

	# Towner NPCs (Cain, Griswold, Ogden, Gillian, Wirt, Farnham, Adria) currently lack textured HD models.
	# Fall back to live DevilutionX engine rasterization with real-time GPU xBRZ/SDF upscaling.
	if prefix.begins_with("towners_"):
		return null

	var act = "walk"
	match mode:
		0, 13, 17:
			act = "stand"
		1, 2, 3:
			act = "walk"
		4, 10, 14:
			act = "attack"
		5:
			act = "hit"
		6:
			act = "death"
		7, 8, 9, 11, 12, 16:
			act = "special"
		_:
			act = "walk"

	var cache_key = "%s_%s_%d_%d_%d" % [prefix, act, dir, frame, current_tile_model]
	if monster_hd_cache.has(cache_key):
		return monster_hd_cache[cache_key]

	# Build candidate directories: start with canonical family_action directory
	var folder = UpscalerModelConfig.get_sprite_folder(current_tile_model)
	var candidate_dirs: Array[String] = [
		"%s/monsters/%s_%s" % [folder, prefix, act]
	]

	# Also check legacy directory aliases
	if prefix == "skelaxe_sklax":
		candidate_dirs.append("%s/monsters/%s" % [folder, "skeleton_death" if act == "death" else "skeleton_walk"])
	elif prefix == "falspear_phall" and act == "walk":
		candidate_dirs.append("%s/monsters/fallen_walk" % folder)
	elif prefix == "zombie_zombie" and act == "walk":
		candidate_dirs.append("%s/monsters/zombie_walk" % folder)
	elif prefix == "fatc_fatc":
		candidate_dirs.append("%s/monsters/butcher_%s" % [folder, act])
	elif prefix == "sking_sking":
		candidate_dirs.append("%s/monsters/sking_%s" % [folder, act])
	elif prefix == "diablo_diablo":
		candidate_dirs.append("%s/monsters/diablo_%s" % [folder, act])

	# Check each candidate directory for dir_X_frame_Y.png or gX_fY.png
	for c_dir in candidate_dirs:
		var file_candidates = [
			"%s/dir_%d_frame_%d.png" % [c_dir, dir, frame],
			"%s/g%d_f%03d.png" % [c_dir, dir, frame],
			"%s/g%d_f%d.png" % [c_dir, dir, frame]
		]
		for f_path in file_candidates:
			if FileAccess.file_exists(f_path):
				var img = Image.load_from_file(ProjectSettings.globalize_path(f_path))
				if img and not img.is_empty():
					if _is_texture_corrupted_black(img):
						_log_corrupted_hd_file(f_path, "Corrupted black texture (max RGB <= 0.06)")
					else:
						img.generate_mipmaps()
						var tex = ImageTexture.create_from_image(img)
						monster_hd_cache[cache_key] = tex
						return tex

	# Fallback to model 0 (UltraSharp) if current model didn't have the frame
	if current_tile_model != 0:
		var default_folder = UpscalerModelConfig.get_sprite_folder(0)
		for c_dir in candidate_dirs:
			var default_c_dir = c_dir.replace(folder, default_folder)
			var file_candidates = [
				"%s/dir_%d_frame_%d.png" % [default_c_dir, dir, frame],
				"%s/g%d_f%03d.png" % [default_c_dir, dir, frame],
				"%s/g%d_f%d.png" % [default_c_dir, dir, frame]
			]
			for f_path in file_candidates:
				if FileAccess.file_exists(f_path):
					var img = Image.load_from_file(ProjectSettings.globalize_path(f_path))
					if img and not img.is_empty():
						if _is_texture_corrupted_black(img):
							_log_corrupted_hd_file(f_path, "Corrupted black texture (max RGB <= 0.06)")
						else:
							img.generate_mipmaps()
							var tex = ImageTexture.create_from_image(img)
							monster_hd_cache[cache_key] = tex
							return tex

	monster_hd_cache[cache_key] = null
	return null

func update_player(delta: float, light_grid: PackedByteArray, player_pos: Dictionary):
	if not diablo_bridge or not _has_player_pos:
		return

	var p_data = diablo_bridge.get_player_continuous_pos()
	var px = p_data.get("pos_x", 25.0)
	var py = p_data.get("pos_y", 25.0)
	var dir = p_data.get("dir", 0)
	var anim_frame = p_data.get("anim_frame", -1)
	var mode = p_data.get("mode", 0)

	# Target position in isometric coordinates
	# Y-sort depth key = hero's feet (position.y), matching vanilla D1's depth ordering:
	# the sprite is sorted by its feet position, not its origin.
	player_target_pos = Vector2(float(px - py) * 32.0, float(px + py) * 16.0 + 16.0)
	if player_node.position == Vector2.ZERO or player_node.position.distance_to(player_target_pos) > 200.0:
		player_node.position = player_target_pos
	else:
		player_node.position = player_node.position.lerp(player_target_pos, delta * 24.0)

	# Smooth camera follow with integer rounding to eliminate sub-pixel tile seams
	if camera:
		camera.position = camera.position.lerp(player_node.position, delta * 20.0).round()

	# Update animated player sprite (supports all Diablo 1 & Hellfire classes: Monk, Bard, Barbarian, Sorcerer, Rogue, Warrior)
	if _has_player_sprite:
		if anim_frame != last_player_frame or dir != last_player_dir or mode != last_player_mode or player_texture == null:
			last_player_frame = anim_frame
			last_player_dir = dir
			last_player_mode = mode

			# 1. Try loading 4X Native HD Sprite PNG from the active neural model directory
			var p_class = diablo_bridge.get_player_class() if diablo_bridge.has_method("get_player_class") else -1
			var hd_tex = get_hd_player_sprite(p_class, mode, dir, anim_frame)
			if hd_tex:
				player_texture = hd_tex
				player_sprite.texture = player_texture
				player_sprite.scale = Vector2(0.25, 0.25)
				player_sprite.offset = Vector2(0, -float(hd_tex.get_height()) * 0.5)
			else:
				# 2. Fallback to real-time DevilutionX C++ sprite extraction
				var s_data: Dictionary = diablo_bridge.get_player_sprite_data()
				var sw = s_data.get("width", 0)
				var sh = s_data.get("height", 0)
				var rgba: PackedByteArray = s_data.get("rgba", PackedByteArray())
				if sw > 0 and sh > 0 and rgba.size() == sw * sh * 4:
					var img = Image.create_from_data(sw, sh, false, Image.FORMAT_RGBA8, rgba)
					player_texture = ImageTexture.create_from_image(img)
					player_sprite.texture = player_texture
					player_sprite.scale = Vector2(1.0, 1.0)
					# Sprite center sits at position.y (feet); exact foot baseline prevents floating
					player_sprite.offset = Vector2(0, -float(sh) * 0.5)

	# Disable artificial secondary shadow so authentic Diablo 1 grounded foot shadow renders cleanly
	if player_shadow:
		player_shadow.visible = false

	var s_info = calculate_shadow_skew_for_position(player_node.position)
	current_player_shadow_skew = current_player_shadow_skew.lerp(s_info["skew"], delta * 12.0)
	current_player_shadow_length = lerpf(current_player_shadow_length, s_info["length"], delta * 12.0)
	current_player_shadow_opacity = lerpf(current_player_shadow_opacity, s_info["opacity"], delta * 12.0)

	if player_shadow_material:
		player_shadow_material.set_shader_parameter("shadow_skew", current_player_shadow_skew * current_player_shadow_length)
		player_shadow_material.set_shader_parameter("shadow_color", Color(0.0, 0.0, 0.0, current_player_shadow_opacity))

	var is_town = (last_level_idx == 0)

	if player_light:
		if is_town or not hero_torchlight_enabled:
			player_light.enabled = false
		else:
			player_light.enabled = true
			var p_flicker = 1.0 + 0.04 * sin(time_accum * 11.7) * cos(time_accum * 6.3)
			var z = camera.zoom.x if camera else 1.0
			var zoom_boost = clampf(1.5 / z, 1.0, 2.2)
			player_light.energy = 0.45 * p_flicker
			player_light.texture_scale = 2.6 * zoom_boost
			player_light.color = Color(1.0, 0.94, 0.85)

	# Authentic per-tile lighting on player
	var p_light_grid = light_grid
	var p_tile_idx = clamp(int(py), 0, 111) * 112 + clamp(int(px), 0, 111)
	# In Diablo 1, the local hero carries their own light/torch and is always fully illuminated (ClxDraw).
	player_sprite.self_modulate = Color(1.50, 1.46, 1.38) if is_town else Color(1.48, 1.44, 1.36)

func update_monsters(delta: float, light_grid: PackedByteArray):
	if not diablo_bridge or not _has_monster_data:
		return

	var monsters: Array = diablo_bridge.get_active_monsters_data()
	var seen_ids: Dictionary = {}

	for m in monsters:
		var m_id = m.get("id", -1)
		var is_alive = m.get("is_alive", true)
		var is_visible = m.get("is_visible", true)
		if m_id < 0 or not is_alive or not is_visible:
			if monster_nodes.has(m_id) and is_instance_valid(monster_nodes[m_id]):
				monster_nodes[m_id].visible = false
			continue

		seen_ids[m_id] = true
		var is_new = not monster_nodes.has(m_id)
		var node = get_or_create_monster_node(m_id)

		var mx = m.get("pos_x", 0.0)
		var my = m.get("pos_y", 0.0)
		var dir = m.get("dir", 0)
		var anim_frame = m.get("anim_frame", -1)

		# Y-sort depth key = monster's feet (position.y), matching vanilla D1's depth ordering
		var target_pos = Vector2(float(mx - my) * 32.0, float(mx + my) * 16.0 + 20.0)
		if is_new or node.position == Vector2.ZERO or node.position.distance_to(target_pos) > 200.0:
			node.position = target_pos
		else:
			node.position = node.position.lerp(target_pos, delta * 18.0)

		# Update monster sprite
		var m_sprite = node.get_node_or_null("Sprite") as Sprite2D
		var last_f = monster_last_frame.get(m_id, -999)
		var last_d = monster_last_dir.get(m_id, -999)
		var cur_tex: Texture2D = monster_textures.get(m_id, null)

		var m_name = str(m.get("name", ""))
		var m_mode = int(m.get("mode", 0))

		if _has_monster_sprite:
			if anim_frame != last_f or dir != last_d or cur_tex == null:
				monster_last_frame[m_id] = anim_frame
				monster_last_dir[m_id] = dir

				# 1. Try loading 4X Native HD Sprite PNG from the active neural model directory
				var m_type = int(m.get("type", -1))
				var m_hd_tex = get_hd_monster_sprite(m_name, m_mode, dir, anim_frame, m_type)
				if m_hd_tex:
					cur_tex = m_hd_tex
					monster_textures[m_id] = cur_tex
					if m_sprite:
						m_sprite.texture = cur_tex
						m_sprite.scale = Vector2(0.25, 0.25)
						m_sprite.offset = Vector2(0, -float(m_hd_tex.get_height()) * 0.5)
				else:
					# 2. Fallback to real-time DevilutionX C++ monster sprite extraction
					_log_live_fallback("monster", m_name, "mode=%d, dir=%d, frame=%d" % [m_mode, dir, anim_frame])
					var ms_data: Dictionary = diablo_bridge.get_monster_sprite_data(m_id)
					var mw = ms_data.get("width", 0)
					var mh = ms_data.get("height", 0)
					var m_rgba: PackedByteArray = ms_data.get("rgba", PackedByteArray())
					if mw > 0 and mh > 0 and m_rgba.size() == mw * mh * 4:
						var m_img = Image.create_from_data(mw, mh, false, Image.FORMAT_RGBA8, m_rgba)
						cur_tex = ImageTexture.create_from_image(m_img)
						monster_textures[m_id] = cur_tex
						if m_sprite:
							m_sprite.texture = cur_tex
							m_sprite.scale = Vector2(1.0, 1.0)
							m_sprite.offset = Vector2(0, -float(mh) * 0.5)

		# Milestone 2: Per-Tile Authentic Lighting on Monsters, Ground Shadows & Fog of War
		
		var m_tx = clamp(int(mx), 0, 111)
		var m_ty = clamp(int(my), 0, 111)
		var m_idx = m_ty * 112 + m_tx
		var is_town = (last_level_idx == 0)
		var m_shadow = node.get_node_or_null("Shadow") as Sprite2D
		if m_shadow:
			m_shadow.visible = false

		if is_town:
			# Town NPCs (Griswold, Pepin, Cain, Ogden, Gillian, Wirt, Farnham, Adria): full clean daylight
			if m_sprite:
				m_sprite.self_modulate = Color(1.50, 1.46, 1.38)
			node.visible = true
		elif light_grid.size() >= 112 * 112:
			var m_light = light_grid[m_idx]
			if m_light >= 15:
				node.visible = false
				continue
			var m_norm = clamp(1.0 - float(m_light) / 14.5, 0.0, 1.0)
			var m_bright = clampf(lerpf(0.25, 1.0, m_norm), 0.25, 1.0)
			if m_sprite:
				m_sprite.self_modulate = Color(1.0, 0.98, 0.95) * m_bright
			node.visible = true
		else:
			node.visible = true

	# Hide monsters that are no longer active
	for m_id in monster_nodes:
		if not seen_ids.has(m_id):
			monster_nodes[m_id].visible = false
			if monster_shadow_materials.has(m_id):
				monster_shadow_materials.erase(m_id)

func get_or_create_monster_node(m_id: int) -> Node2D:
	if monster_nodes.has(m_id) and is_instance_valid(monster_nodes[m_id]):
		return monster_nodes[m_id]

	var m_root = Node2D.new()
	m_root.name = "Monster_%d" % m_id
	m_root.z_index = 0
	world_root.add_child(m_root)

	var shadow = Sprite2D.new()
	shadow.name = "Shadow"
	shadow.centered = true
	shadow.position = Vector2.ZERO
	shadow.z_index = -1
	m_root.add_child(shadow)

	var spr = Sprite2D.new()
	spr.name = "Sprite"
	spr.centered = true
	if entity_hd_material:
		spr.material = entity_hd_material
	m_root.add_child(spr)

	monster_nodes[m_id] = m_root
	return m_root

func update_torches(light_grid: PackedByteArray, player_pos: Dictionary):
	if not diablo_bridge or not _has_active_lights:
		return

	var lights = diablo_bridge.get_active_lights()
	var needed = lights.size()

	# Expand torch light pool if needed
	while torch_lights.size() < needed:
		var pl = PointLight2D.new()
		pl.texture = shared_radial_light_texture if shared_radial_light_texture else create_radial_light_texture(512)
		pl.texture_scale = 1.4
		pl.shadow_enabled = enable_wall_occluders
		pl.shadow_filter = Light2D.SHADOW_FILTER_PCF13
		pl.shadow_filter_smooth = 4.5
		pl.shadow_color = Color(0.0, 0.0, 0.0, 0.38)
		world_root.add_child(pl)
		torch_lights.append(pl)

	
	var p_pos = player_pos
	var p_tx = float(p_pos.get("pos_x", 25.0))
	var p_ty = float(p_pos.get("pos_y", 25.0))
	var is_town = (last_level_idx == 0)

	# Index 0 is the hero torch; environmental lights are 1..N
	for i in range(torch_lights.size()):
		var pl: PointLight2D = torch_lights[i]
		if i < lights.size() and i > 0: # Environmental lights (wall torches, fireballs)
			var info = lights[i]
			var l_type = info.get("type", 1)
			var tx = float(info.get("tile_x", 0))
			var ty = float(info.get("tile_y", 0))
			var t_idx = clamp(int(ty), 0, 111) * 112 + clamp(int(tx), 0, 111)

			var is_torch_lit = true
			if not is_town and light_grid.size() >= 112 * 112:
				if light_grid[t_idx] >= 15:
					is_torch_lit = false

			var p_dist = Vector2(tx, ty).distance_to(Vector2(p_tx, p_ty))
			if not is_torch_lit or p_dist > 22.0:
				pl.visible = false
				continue

			var l_pos = Vector2((tx - ty) * 32.0, (tx + ty) * 16.0 - 10.0)
			pl.position = l_pos
			pl.visible = true

			var phase = float(i) * 1.83
			var t_flicker = 1.0 + 0.10 * sin(time_accum * 13.1 + phase) * cos(time_accum * 7.9 + phase * 2.0)
			var rad = float(info.get("radius", 6))

			if l_type == 1: # Wall torch / brazier
				var hdr_torch_energy = [0.80, 1.00, 1.25, 1.50][current_hdr_level]
				pl.color = Color(1.0, 0.72 + float(current_hdr_level) * 0.04, 0.35 + float(current_hdr_level) * 0.05)
				pl.energy = hdr_torch_energy * t_flicker
				pl.texture_scale = clampf(rad * (0.20 + float(current_hdr_level) * 0.03), 1.0, 1.9)
			elif l_type == 2: # Spell / missile (Fireball, flame)
				var hdr_missile_energy = [1.00, 1.30, 1.65, 1.95][current_hdr_level]
				pl.color = Color(1.0, 0.88, 0.50)
				pl.energy = hdr_missile_energy * t_flicker
				pl.texture_scale = clampf(rad * (0.24 + float(current_hdr_level) * 0.03), 1.2, 2.2)
			else:
				pl.color = Color(0.95, 0.70, 0.40)
				pl.energy = 0.70
				pl.texture_scale = 1.3
		else:
			pl.visible = false

# Real-time Door & Interactive Tile Synchronization (Opens/Closes doors smoothly on screen)
func _sync_door_tile_if_changed(x: int, y: int):
	if x < 0 or x >= 112 or y < 0 or y >= 112 or not diablo_bridge:
		return
	var pos_key = Vector2i(x, y)
	var idx = y * 112 + x
	var cur_pid = diablo_bridge.get_dungeon_tile(x, y) if _has_dungeon_tile else -1
	if cur_pid < 0:
		return

	var old_pid = tile_piece_ids.get(pos_key, -1)
	var spec_grid = diablo_bridge.get_dungeon_special_grid() if _has_special_grid else PackedInt32Array()
	var cur_spec = spec_grid[idx] if (idx < spec_grid.size()) else 0
	var old_spec = tile_special_ids.get(pos_key, 0)

	if cur_pid == old_pid and cur_spec == old_spec:
		return

	tile_piece_ids[pos_key] = cur_pid
	tile_special_ids[pos_key] = cur_spec

	var tile_pos = Vector2(float(x - y) * 32.0, float(x + y) * 16.0 + 16.0)
	var tex: Texture2D = get_pbr_or_base_texture(cur_pid)
	if tex != null:
		var tw = tex.get_width()
		var th = tex.get_height()
		var scale_factor = 64.0 / float(tw)
		var floor_h = int(round(float(tw) * 0.5))
		var is_wall = (th > floor_h)
		var is_hd_asset = (tw >= 256)

		var spr: Sprite2D = null
		if is_wall:
			if tile_sprites.has(pos_key):
				var old_s = tile_sprites[pos_key]
				if is_instance_valid(old_s):
					old_s.queue_free()
				tile_sprites.erase(pos_key)
			spr = wall_sprites.get(pos_key, null)
		else:
			if wall_sprites.has(pos_key):
				var old_s = wall_sprites[pos_key]
				if is_instance_valid(old_s):
					old_s.queue_free()
				wall_sprites.erase(pos_key)
			spr = tile_sprites.get(pos_key, null)

		if spr == null or not is_instance_valid(spr):
			spr = Sprite2D.new()
			spr.material = dungeon_tile_material
			spr.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
			spr.centered = false
			spr.position = tile_pos
			spr.self_modulate = Color(1.0, 1.0, 1.0)
			spr.z_index = 0 if is_wall else -2
			if is_wall:
				world_root.add_child(spr)
				wall_sprites[pos_key] = spr
			else:
				floor_root.add_child(spr)
				tile_sprites[pos_key] = spr

		spr.texture = tex
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if (hd_graphics_enabled and is_hd_asset) else CanvasItem.TEXTURE_FILTER_NEAREST
		spr.scale = Vector2(scale_factor, scale_factor)
		spr.offset = Vector2(-float(tw) * 0.5, -float(th))
		spr.visible = true

	# Update special cel archway if present
	if cur_spec > 0 and is_cathedral_level():
		var arch_tex = get_pbr_or_base_special_texture(cur_spec)
		if arch_tex != null:
			var arch_spr = special_sprites.get(pos_key, null)
			if arch_spr == null or not is_instance_valid(arch_spr):
				arch_spr = Sprite2D.new()
				arch_spr.material = dungeon_tile_material
				arch_spr.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
				arch_spr.centered = false
				arch_spr.position = tile_pos
				arch_spr.self_modulate = Color(1.0, 1.0, 1.0)
				arch_spr.z_index = 0
				world_root.add_child(arch_spr)
				special_sprites[pos_key] = arch_spr
			arch_spr.texture = arch_tex
			arch_spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if hd_graphics_enabled else CanvasItem.TEXTURE_FILTER_NEAREST
			var atw = arch_tex.get_width()
			var ath = arch_tex.get_height()
			var a_scale = 64.0 / float(atw)
			arch_spr.scale = Vector2(a_scale, a_scale)
			arch_spr.offset = Vector2(-float(atw) * 0.5, -float(ath))
			arch_spr.visible = true
	else:
		if special_sprites.has(pos_key):
			var old_arch = special_sprites[pos_key]
			if is_instance_valid(old_arch):
				old_arch.queue_free()
			special_sprites.erase(pos_key)

# Milestone 4: Dungeon Objects (Animated Torches, Barrels, Chests, Shrines)
func update_objects(light_grid: PackedByteArray, player_pos: Dictionary):
	if not diablo_bridge or not _has_active_objects:
		return

	var objects: Array = diablo_bridge.get_active_objects()
	var seen_ids: Dictionary = {}
	var has_light = (light_grid.size() >= 112 * 112)

	# Camera-visible tile window around the hero, using the same math as update_lighting_and_transparency().
	# Without this cull every door/chest/barrel/arches anywhere in the level renders on screen.
	var p_pos = player_pos
	var ppx = float(p_pos.get("pos_x", 25.0))
	var ppy = float(p_pos.get("pos_y", 25.0))
	var cam_z = camera.zoom.x if camera else 1.0
	var rad_x = int(clamp(60.0 / cam_z, 44.0, 80.0))
	var rad_y = int(clamp(50.0 / cam_z, 36.0, 70.0))
	var min_x = int(clamp(int(ppx) - rad_x, 0, 111))
	var max_x = int(clamp(int(ppx) + rad_x, 0, 111))
	var min_y = int(clamp(int(ppy) - rad_y, 0, 111))
	var max_y = int(clamp(int(ppy) + rad_y, 0, 111))

	for obj in objects:
		var o_id = obj.get("id", -1)
		if o_id < 0:
			continue
		seen_ids[o_id] = true

		var tx = obj.get("tile_x", 0)
		var ty = obj.get("tile_y", 0)

		# Cull anything outside the visible tile window (doors, chests, barrels, arches...).
		if tx < min_x or tx > max_x or ty < min_y or ty > max_y:
			var old_spr = object_sprites.get(o_id, null)
			if old_spr:
				old_spr.visible = false
			continue

		seen_ids[o_id] = true
		var o_type = obj.get("type", 0)
		var anim_frame = obj.get("anim_frame", 1)
		var pre_flag = obj.get("pre_flag", false)

		var spr: Sprite2D = object_sprites.get(o_id, null)
		if spr == null:
			spr = Sprite2D.new()
			spr.name = "Object_%d" % o_id
			spr.centered = false
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			world_root.add_child(spr)
			object_sprites[o_id] = spr

		# Y-sort depth key = object's bottom vertex (position.y), matching vanilla D1's depth ordering
		var tile_pos = Vector2(float(tx - ty) * 32.0, float(tx + ty) * 16.0 + (19.0 if not pre_flag else 16.0))
		spr.position = tile_pos
		spr.z_index = 0

		# Texture caching by (type, anim_frame)
		var cache_key = "%d_%d" % [o_type, anim_frame]
		var tex: ImageTexture = object_textures.get(cache_key, null)
		if tex == null and diablo_bridge.has_method("get_object_sprite_data"):
			var s_data = diablo_bridge.get_object_sprite_data(o_id)
			var sw = s_data.get("width", 0)
			var sh = s_data.get("height", 0)
			var rgba = s_data.get("rgba", PackedByteArray())
			if sw > 0 and sh > 0 and rgba.size() == sw * sh * 4:
				var img = Image.create_from_data(sw, sh, false, Image.FORMAT_RGBA8, rgba)
				tex = ImageTexture.create_from_image(img)
				object_textures[cache_key] = tex

		if tex:
			spr.texture = tex
			spr.offset = Vector2(-float(tex.get_width()) * 0.5, -float(tex.get_height()) - (2.0 if not pre_flag else 0.0))

		# Authentic per-tile lighting (Objects in Diablo 1 are NEVER transparent!)
		spr.modulate.a = 1.0

		var tile_idx = clamp(ty, 0, 111) * 112 + clamp(tx, 0, 111)
		var is_door = (o_type in [1, 2, 148, 149, 180, 181, 211, 212])
		if is_door:
			_sync_door_tile_if_changed(tx, ty)
			_sync_door_tile_if_changed(tx + 1, ty)
			_sync_door_tile_if_changed(tx - 1, ty)
			_sync_door_tile_if_changed(tx, ty + 1)
			_sync_door_tile_if_changed(tx, ty - 1)
			if tex == null:
				spr.visible = false
				continue

		var is_flame = (o_type in [0, 3, 8, 9, 10, 106, 109, 114, 115, 116, 120, 121, 150, 151, 152, 153, 155, 171, 193, 210])
		var is_sarc = (o_type in [154, 214])
		var is_town = (last_level_idx == 0)

		var flame_mod = Color(1.0, 0.96, 0.92)
		if current_hdr_level == 1:
			flame_mod = Color(1.4, 1.1, 0.7)
		elif current_hdr_level == 2:
			flame_mod = Color(1.8, 1.45, 0.95)
		elif current_hdr_level == 3:
			flame_mod = Color(2.1, 1.65, 1.1)

		if is_town:
			if is_flame:
				spr.self_modulate = flame_mod
			else:
				spr.self_modulate = Color(1.50, 1.46, 1.38)
			spr.visible = true
		elif has_light:
			var light_val = light_grid[tile_idx]
			if is_door:
				# Doors sit in doorways between rooms: check adjacent floor tiles to see if doorway is illuminated
				if tx > 0 and light_grid[tile_idx - 1] < light_val:
					light_val = light_grid[tile_idx - 1]
				if tx < 111 and light_grid[tile_idx + 1] < light_val:
					light_val = light_grid[tile_idx + 1]
				if ty > 0 and light_grid[tile_idx - 112] < light_val:
					light_val = light_grid[tile_idx - 112]
				if ty < 111 and light_grid[tile_idx + 112] < light_val:
					light_val = light_grid[tile_idx + 112]
			elif is_sarc:
				# Sarcophagi are 2-tile objects occupying (tx, ty) and (tx, ty - 1)
				if ty > 0 and light_grid[tile_idx - 112] < light_val:
					light_val = light_grid[tile_idx - 112]

			if is_flame:
				spr.self_modulate = flame_mod
			else:
				var o_norm = clamp(1.0 - float(light_val) / 14.5, 0.0, 1.0)
				if light_val >= 15:
					spr.self_modulate = Color(0.25, 0.24, 0.23)
				else:
					var o_bright = clampf(lerpf(0.35, 1.0, o_norm), 0.35, 1.0)
					spr.self_modulate = Color(1.05, 1.02, 0.98) * o_bright
			spr.visible = true
		else:
			if is_flame:
				spr.self_modulate = flame_mod
			else:
				spr.self_modulate = Color(1.0, 1.0, 1.0)
			spr.visible = true

	for o_id in object_sprites:
		if not seen_ids.has(o_id):
			object_sprites[o_id].visible = false

# Milestone 4: Ground Items & Loot with Authentic Labels
func update_ground_items(light_grid: PackedByteArray):
	if not diablo_bridge or not _has_active_items or world_root == null:
		return

	var items: Array = diablo_bridge.get_active_items()
	var seen_ids: Dictionary = {}
	var has_light = (light_grid.size() >= 112 * 112)

	for item in items:
		var i_id = item.get("id", -1)
		if i_id < 0:
			continue
		seen_ids[i_id] = true

		var tx = item.get("tile_x", 0)
		var ty = item.get("tile_y", 0)
		var quality = item.get("quality", 0)
		var iname = item.get("name", "")

		var node: Node2D = item_nodes.get(i_id, null)
		if node == null:
			node = Node2D.new()
			node.name = "GroundItem_%d" % i_id
			node.z_index = 0 # Y-sorted dungeon entity
			world_root.add_child(node)

			var spr = Sprite2D.new()
			spr.name = "Sprite"
			spr.centered = false
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			node.add_child(spr)

			# Authentic Diablo loot name label
			var lbl = Label.new()
			lbl.name = "Label"
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.add_theme_font_override("font", FONT_EXOCET)
			lbl.add_theme_font_size_override("font_size", 12)
			lbl.z_as_relative = false
			lbl.z_index = 20
			node.add_child(lbl)

			item_nodes[i_id] = node

		var is_item_lit = true
		if has_light and last_level_idx != 0:
			var i_tile_idx = clamp(ty, 0, 111) * 112 + clamp(tx, 0, 111)
			if light_grid[i_tile_idx] >= 15:
				is_item_lit = false
		node.visible = is_item_lit
		var tile_pos = Vector2(float(tx - ty) * 32.0, float(tx + ty) * 16.0 + 16.0)
		node.position = tile_pos

		var spr = node.get_node_or_null("Sprite") as Sprite2D
		if spr:
			var ent_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if (hd_graphics_enabled and current_upscaler_mode != 4) else CanvasItem.TEXTURE_FILTER_NEAREST
			spr.texture_filter = ent_filter
			if entity_hd_material and spr.material == null:
				spr.material = entity_hd_material

		var curs_id = item.get("curs_id", 0)
		var anim_frame = item.get("anim_frame", 0)
		var cache_key = "%d_%d_%d" % [curs_id, anim_frame, current_tile_model]
		var tex: Texture2D = item_textures.get(cache_key, null)
		var is_hd = item_is_hd.get(cache_key, false)

		if tex == null and hd_graphics_enabled:
			var folder = UpscalerModelConfig.get_sprite_folder(current_tile_model)
			var p1 = "%s/items/curs_%d_f%d.png" % [folder, curs_id, anim_frame]
			var p2 = "%s/items/curs_%d.png" % [folder, curs_id]
			var chosen_path = ""
			if FileAccess.file_exists(p1):
				chosen_path = p1
			elif FileAccess.file_exists(p2):
				chosen_path = p2
			else:
				var fb_folder = UpscalerModelConfig.get_sprite_folder(0)
				var fb1 = "%s/items/curs_%d_f%d.png" % [fb_folder, curs_id, anim_frame]
				var fb2 = "%s/items/curs_%d.png" % [fb_folder, curs_id]
				if FileAccess.file_exists(fb1):
					chosen_path = fb1
				elif FileAccess.file_exists(fb2):
					chosen_path = fb2

			if chosen_path != "":
				var img = Image.load_from_file(ProjectSettings.globalize_path(chosen_path))
				if img and not img.is_empty():
					img.generate_mipmaps()
					tex = ImageTexture.create_from_image(img)
					item_textures[cache_key] = tex
					item_is_hd[cache_key] = true
					is_hd = true

		if tex == null and diablo_bridge.has_method("get_ground_item_sprite_data"):
			var s_data = diablo_bridge.get_ground_item_sprite_data(i_id)
			var sw = s_data.get("width", 0)
			var sh = s_data.get("height", 0)
			var rgba = s_data.get("rgba", PackedByteArray())
			if sw > 0 and sh > 0 and rgba.size() == sw * sh * 4:
				var img = Image.create_from_data(sw, sh, false, Image.FORMAT_RGBA8, rgba)
				img.generate_mipmaps()
				tex = ImageTexture.create_from_image(img)
				item_textures[cache_key] = tex
				item_is_hd[cache_key] = false
				is_hd = false

		if tex and spr:
			spr.texture = tex
			if is_hd:
				spr.scale = Vector2(0.25, 0.25)
			else:
				spr.scale = Vector2(1.0, 1.0)
			spr.offset = Vector2(-float(tex.get_width()) * 0.5, -float(tex.get_height()))

		# Lighting & Fog of War
		var tile_idx = clamp(ty, 0, 111) * 112 + clamp(tx, 0, 111)
		var is_town = (last_level_idx == 0)
		if spr:
			if is_town:
				spr.self_modulate = Color(1.0, 1.0, 1.0)
				node.visible = true
			elif has_light:
				var light_val = light_grid[tile_idx]
				var brightness = pow(clamp(1.0 - float(light_val) / 14.5, 0.0, 1.0), 1.8)
				spr.self_modulate = Color(0.040, 0.042, 0.055).lerp(Color(1.0, 0.96, 0.92), max(0.0, brightness))
				node.visible = true
			else:
				node.visible = true

		# Diablo IV Style Loot Beam (Magic & Unique/Legendary)
		var beam_node = node.get_node_or_null("LootBeam")
		if quality >= 1:
			if beam_node == null:
				beam_node = Node2D.new()
				beam_node.name = "LootBeam"
				beam_node.z_as_relative = false
				beam_node.z_index = 10 # Above floor and item sprite, below label
				node.add_child(beam_node)

				if loot_beam_material == null:
					loot_beam_material = CanvasItemMaterial.new()
					loot_beam_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

				# 1. Ground flare disc on the floor
				var flare = Sprite2D.new()
				flare.name = "GroundFlare"
				flare.texture = TEX_LOOT_FLARE
				flare.centered = true
				flare.position = Vector2(0, 4)
				flare.material = loot_beam_material
				beam_node.add_child(flare)

				# 2. Vertical luminous light pillar (64x256)
				var pillar = Sprite2D.new()
				pillar.name = "Pillar"
				pillar.texture = TEX_LOOT_BEAM
				pillar.centered = false
				pillar.offset = Vector2(-32, -256) # Bottom-centered on origin
				pillar.position = Vector2(0, 4)
				pillar.material = loot_beam_material
				beam_node.add_child(pillar)

				# 3. Rising luminous sparks / motes
				var particles = CPUParticles2D.new()
				particles.name = "Particles"
				particles.material = loot_beam_material
				particles.amount = 14
				particles.lifetime = 1.3
				particles.preprocess = 0.5
				particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
				particles.emission_rect_extents = Vector2(8, 2)
				particles.direction = Vector2(0, -1)
				particles.spread = 4.0
				particles.gravity = Vector2(0, -18)
				particles.initial_velocity_min = 40.0
				particles.initial_velocity_max = 85.0
				particles.scale_amount_min = 1.5
				particles.scale_amount_max = 3.0
				particles.position = Vector2(0, 4)
				beam_node.add_child(particles)

				# Breathing pulse animations
				var tw = beam_node.create_tween().set_loops()
				tw.tween_property(pillar, "scale", Vector2(0.85, 0.95), 0.9).set_trans(Tween.TRANS_SINE)
				tw.parallel().tween_property(pillar, "modulate:a", 0.70, 0.9).set_trans(Tween.TRANS_SINE)
				tw.tween_property(pillar, "scale", Vector2(1.05, 1.0), 0.9).set_trans(Tween.TRANS_SINE)
				tw.parallel().tween_property(pillar, "modulate:a", 0.95, 0.9).set_trans(Tween.TRANS_SINE)

				var tw_f = flare.create_tween().set_loops()
				tw_f.tween_property(flare, "scale", Vector2(1.3, 1.3), 1.1).set_trans(Tween.TRANS_SINE)
				tw_f.tween_property(flare, "scale", Vector2(0.9, 0.9), 1.1).set_trans(Tween.TRANS_SINE)

			# Color modulate based on quality with HDR boost
			var hdr_loot_mult = [1.0, 1.6, 2.4, 3.4][current_hdr_level]
			var base_beam = COLOR_MAGIC if quality == 1 else COLOR_UNIQUE
			var beam_col = Color(base_beam.r * hdr_loot_mult, base_beam.g * hdr_loot_mult, base_beam.b * hdr_loot_mult, base_beam.a)
			var flare_sprite = beam_node.get_node_or_null("GroundFlare") as Sprite2D
			var pillar_sprite = beam_node.get_node_or_null("Pillar") as Sprite2D
			var parts = beam_node.get_node_or_null("Particles") as CPUParticles2D
			if flare_sprite:
				flare_sprite.self_modulate = beam_col
			if pillar_sprite:
				pillar_sprite.self_modulate = beam_col
			if parts:
				parts.color = beam_col
				parts.emitting = true
			beam_node.visible = true
		else:
			if beam_node != null:
				beam_node.visible = false
				var parts = beam_node.get_node_or_null("Particles") as CPUParticles2D
				if parts:
					parts.emitting = false

		# Ground item label
		var lbl = node.get_node_or_null("Label") as Label
		if lbl and iname != "":
			lbl.text = iname
			lbl.add_theme_font_override("font", FONT_EXOCET)
			lbl.add_theme_font_size_override("font_size", 12)

			var quality_col: Color
			if quality == 1:
				quality_col = COLOR_MAGIC # Magic Blue
			elif quality >= 2:
				quality_col = COLOR_UNIQUE # Unique Gold
			else:
				quality_col = COLOR_NORMAL # Normal White / Slate

			lbl.add_theme_color_override("font_color", quality_col)
			lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
			lbl.add_theme_constant_override("shadow_outline_size", 2)

			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.06, 0.05, 0.08, 0.88)
			style.border_width_left = 1
			style.border_width_top = 1
			style.border_width_right = 1
			style.border_width_bottom = 1
			style.border_color = quality_col.lerp(Color(0.25, 0.22, 0.20, 0.8), 0.35)
			style.corner_radius_top_left = 3
			style.corner_radius_top_right = 3
			style.corner_radius_bottom_left = 3
			style.corner_radius_bottom_right = 3
			style.content_margin_left = 7.0
			style.content_margin_right = 7.0
			style.content_margin_top = 3.0
			style.content_margin_bottom = 3.0
			lbl.add_theme_stylebox_override("normal", style)

			lbl.reset_size()
			var sz = lbl.get_combined_minimum_size()

			# Anchor the label directly above the floor diamond and ground item sprite (matching DevilutionX Mode 0)
			lbl.position = Vector2(-sz.x * 0.5, -34.0 - sz.y)
			lbl.z_as_relative = false
			lbl.z_index = 20
			var show_labels = diablo_bridge.is_item_label_highlight_enabled() if diablo_bridge.has_method("is_item_label_highlight_enabled") else true
			lbl.visible = show_labels

	for i_id in item_nodes:
		if not seen_ids.has(i_id):
			item_nodes[i_id].visible = false

# Milestone 4: Corpses & Fallen Monsters on the Floor
func update_corpses(light_grid: PackedByteArray):
	if not diablo_bridge or not _has_active_corpses:
		return

	var corpses: Array = diablo_bridge.get_active_corpses()
	var seen_keys: Dictionary = {}


	var has_light = (light_grid.size() >= 112 * 112)

	for c in corpses:
		var tx = c.get("tile_x", 0)
		var ty = c.get("tile_y", 0)
		var corpse_idx = c.get("corpse_idx", 0)
		var dir = c.get("dir", 0)

		var pos_key = Vector2i(tx, ty)
		seen_keys[pos_key] = true

		var spr: Sprite2D = corpse_sprites.get(pos_key, null)
		if spr == null:
			spr = Sprite2D.new()
			spr.name = "Corpse_%d_%d" % [tx, ty]
			spr.centered = true
			spr.z_index = -1
			world_root.add_child(spr)
			corpse_sprites[pos_key] = spr

		var ent_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if (hd_graphics_enabled and current_upscaler_mode != 4) else CanvasItem.TEXTURE_FILTER_NEAREST
		spr.texture_filter = ent_filter
		if entity_hd_material and spr.material == null:
			spr.material = entity_hd_material

		# Lighting & Fog of War
		var tile_idx = clamp(ty, 0, 111) * 112 + clamp(tx, 0, 111)
		var is_town = (last_level_idx == 0)
		if is_town:
			spr.self_modulate = Color(1.45, 1.42, 1.35)
			spr.visible = true
		elif has_light:
			var light_val = light_grid[tile_idx]
			if light_val >= 15:
				# Ambient visibility for explored tiles so corpses remain visible in shadow
				spr.self_modulate = Color(0.20, 0.19, 0.18)
				spr.visible = true
			else:
				var norm = clamp(1.0 - float(light_val) / 14.5, 0.0, 1.0)
				var bright = clampf(lerpf(0.35, 1.0, norm), 0.35, 1.0)
				spr.self_modulate = Color(1.05, 1.02, 0.98) * bright
				spr.visible = true
		else:
			spr.visible = true
		var tile_pos = Vector2(float(tx - ty) * 32.0, float(tx + ty) * 16.0 + 16.0)
		spr.position = tile_pos

		var m_name = c.get("monster_name", "")
		var frame = c.get("frame", 0)
		var cache_key = "%s_%d_%d_%d_%d" % [m_name, corpse_idx, dir, frame, current_tile_model]
		var tex: Texture2D = corpse_textures.get(cache_key, null)
		var is_hd = corpse_is_hd.get(cache_key, false)

		if tex == null and hd_graphics_enabled and m_name != "":
			# Mode 6 = MonsterGraphic::Death in get_hd_monster_sprite
			var hd_tex = get_hd_monster_sprite(m_name, 6, dir, frame)
			if hd_tex:
				var test_img = hd_tex.get_image()
				if test_img and not test_img.is_empty():
					if _is_texture_corrupted_black(test_img):
						_log_corrupted_hd_file("corpse_%s_dir%d_f%d" % [m_name, dir, frame], "Corrupted black corpse")
					else:
						tex = hd_tex
						is_hd = true
						corpse_textures[cache_key] = tex
						corpse_is_hd[cache_key] = true

		if tex == null and diablo_bridge.has_method("get_corpse_sprite_data"):
			_log_live_fallback("corpse", m_name if m_name != "" else ("idx_%d" % corpse_idx), "dir=%d, frame=%d" % [dir, frame])
			var s_data = diablo_bridge.get_corpse_sprite_data(corpse_idx, dir)
			var sw = s_data.get("width", 0)
			var sh = s_data.get("height", 0)
			var rgba = s_data.get("rgba", PackedByteArray())
			if sw > 0 and sh > 0 and rgba.size() == sw * sh * 4:
				var img = Image.create_from_data(sw, sh, false, Image.FORMAT_RGBA8, rgba)
				img.generate_mipmaps()
				tex = ImageTexture.create_from_image(img)
				is_hd = false
				corpse_textures[cache_key] = tex
				corpse_is_hd[cache_key] = false
			else:
				corpse_textures[cache_key] = null
				corpse_is_hd[cache_key] = false
		elif tex == null:
			corpse_textures[cache_key] = null
			corpse_is_hd[cache_key] = false

		if tex:
			spr.texture = tex
			spr.centered = true
			if is_hd:
				spr.scale = Vector2(0.25, 0.25)
			else:
				spr.scale = Vector2(1.0, 1.0)
			spr.offset = Vector2(0, -float(tex.get_height()) * 0.5)
			spr.z_index = -1
			spr.visible = true
		else:
			spr.visible = false

	for k in corpse_sprites:
		if not seen_keys.has(k):
			corpse_sprites[k].visible = false

# D1DE Combat VFX: Native Godot 2.5D GPUParticles2D bursts (Blood / Bone Shards / Fireball Explosion)
# The C++ engine queues events per hit/kill/cast; we drain them here while Mode 1 is active.
func update_visual_effects():
	if not diablo_bridge or not diablo_bridge.has_method("poll_visual_events"):
		return

	var events = diablo_bridge.poll_visual_events()
	for ev in events:
		var ev_type = int(ev.get("type", 0))
		if ev_type <= 0 or not ev.has("tile"):
			continue
		var tile := Vector2(ev["tile"])
		if tile.x < 0.0 or tile.y < 0.0:
			continue

		# Tile -> world mapping matches the dungeon tile layout: ((x - y) * 32, (x + y) * 16 + 16)
		var world_pos = Vector2(float(tile.x - tile.y) * 32.0, float(tile.x + tile.y) * 16.0 + 16.0)
		var ev_scale = clampf(float(ev.get("intensity", 1.0)), 0.8, 1.5)
		var p_instance: GPUParticles2D = null

		if ev_type == 1: # Blood Splatter (Fleshy / Demon)
			p_instance = blood_splatter_2d_scene.instantiate()
		elif ev_type == 2: # Bone Shards (Undead / Skeleton / Stone)
			p_instance = bone_shards_2d_scene.instantiate()
		elif ev_type == 3: # Fireball / Spell Explosion
			p_instance = fireball_explosion_2d_scene.instantiate()

		if p_instance:
			p_instance.z_index = 15
			p_instance.position = world_pos
			p_instance.scale = Vector2(ev_scale, ev_scale)
			world_root.add_child(p_instance)

		# On heavy hit or fatal kill gore (intensity >= 1.35), spawn a secondary burst for visceral volume
		if ev_type == 1 and ev_scale >= 1.35:
			var extra_gore = blood_splatter_2d_scene.instantiate()
			extra_gore.z_index = 15
			extra_gore.position = world_pos + Vector2(randf_range(-10, 10), randf_range(-7, 7))
			extra_gore.scale = Vector2(ev_scale * 1.1, ev_scale * 1.1)
			world_root.add_child(extra_gore)
		elif ev_type == 2 and ev_scale >= 1.35:
			var extra_bones = bone_shards_2d_scene.instantiate()
			extra_bones.z_index = 15
			extra_bones.position = world_pos + Vector2(randf_range(-8, 8), randf_range(-6, 6))
			extra_bones.scale = Vector2(ev_scale * 1.05, ev_scale * 1.05)
			world_root.add_child(extra_bones)

# Projectiles & Spells (Arrows, Firebolts, Fireballs, Lightning, Holy Bolts)
func update_missiles(light_grid: PackedByteArray):
	if not diablo_bridge or not _has_active_missiles:
		return

	var missiles: Array = diablo_bridge.get_active_missiles()
	var seen_ids: Dictionary = {}


	var has_light = (light_grid.size() >= 112 * 112)

	for m in missiles:
		var m_id = m.get("id", -1)
		if m_id < 0:
			continue
		seen_ids[m_id] = true

		var m_type = m.get("type", 0)
		var m_dir = m.get("dir", 0)
		var px = m.get("pos_x", 0.0)
		var py = m.get("pos_y", 0.0)
		var m_tx = m.get("tile_x", 0)
		var m_ty = m.get("tile_y", 0)
		var anim_frame = m.get("anim_frame", 0)
		var light_flag = m.get("light_flag", false)
		var pre_flag = m.get("pre_flag", false)

		var node: Node2D = missile_nodes.get(m_id, null)
		if node == null:
			node = Node2D.new()
			node.name = "Missile_%d" % m_id
			world_root.add_child(node)

			var spr = Sprite2D.new()
			spr.name = "Sprite"
			spr.centered = false
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			node.add_child(spr)

			missile_nodes[m_id] = node

		node.z_index = 0
		# Y-sort depth key = missile's bottom vertex (position.y), matching vanilla D1's depth ordering
		node.position = Vector2(px, py + 16.0)

		var spr = node.get_node_or_null("Sprite") as Sprite2D

		# Lighting: glowing spell missiles (fireball, firebolt, lightning) stay fully lit
		# Non-glowing missiles (arrows) sample the dungeon light grid
		if spr:
			if light_flag:
				var m_mod = Color(1.0, 1.0, 1.0)
				if current_hdr_level == 1:
					m_mod = Color(1.4, 1.15, 0.9)
				elif current_hdr_level == 2:
					m_mod = Color(1.75, 1.4, 1.05)
				elif current_hdr_level == 3:
					m_mod = Color(2.1, 1.6, 1.2)
				spr.self_modulate = m_mod
			elif has_light:
				var tile_idx = clamp(m_ty, 0, 111) * 112 + clamp(m_tx, 0, 111)
				var l_val = light_grid[tile_idx]
				if l_val >= 15:
					node.visible = false
					continue
				var brightness = pow(clamp(1.0 - float(l_val) / 14.5, 0.0, 1.0), 1.8)
				spr.self_modulate = Color(0.04, 0.07, 0.11).lerp(Color(1.0, 0.96, 0.92), brightness)

		node.visible = true

		# Texture caching by (type, dir, anim_frame)
		var cache_key = "%d_%d_%d" % [m_type, m_dir, anim_frame]
		var tex: ImageTexture = missile_textures.get(cache_key, null)
		if tex == null and diablo_bridge.has_method("get_missile_sprite_data"):
			var s_data = diablo_bridge.get_missile_sprite_data(m_id)
			var sw = s_data.get("width", 0)
			var sh = s_data.get("height", 0)
			var rgba = s_data.get("rgba", PackedByteArray())
			if sw > 0 and sh > 0 and rgba.size() == sw * sh * 4:
				var img = Image.create_from_data(sw, sh, false, Image.FORMAT_RGBA8, rgba)
				tex = ImageTexture.create_from_image(img)
				missile_textures[cache_key] = tex

		if spr and tex:
			spr.texture = tex
			spr.offset = Vector2(-float(tex.get_width()) * 0.5, -float(tex.get_height()))

	# Hide inactive missiles
	for m_id in missile_nodes:
		if not seen_ids.has(m_id):
			missile_nodes[m_id].visible = false

func get_world_mouse_position(screen_pos: Vector2) -> Vector2:
	var vp_size = get_viewport().get_visible_rect().size
	var cam_pos = camera.position if camera else Vector2.ZERO
	var cam_z = camera.zoom.x if camera else 1.0
	return (screen_pos - vp_size * 0.5) / cam_z + cam_pos

func handle_input(event: InputEvent) -> bool:
	if not is_active:
		return false

	# If the game is not actively in a dungeon/game session (e.g. main menu, hero select, character create),
	# do NOT intercept input with world-space raycasting! Pass through to classic UI!
	if diablo_bridge and _has_game_running and not diablo_bridge.is_game_running():
		return false

	# When a modal menu, store, or dialog is active, pass input through to screen-space UI
	if diablo_bridge and diablo_bridge.has_method("is_modal_active") and diablo_bridge.is_modal_active():
		return false

	# When entering text (chat, naming, gold drop), pass input through to D1
	if diablo_bridge and _has_text_input and diablo_bridge.is_text_input_active():
		return false

	# Mouse Wheel Zoom
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if current_zoom_idx < zoom_levels.size() - 1:
				current_zoom_idx += 1
				var z = zoom_levels[current_zoom_idx]
				camera.zoom = Vector2(z, z)
				_apply_zoom_vision(z)
			return true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if current_zoom_idx > 0:
				current_zoom_idx -= 1
				var z = zoom_levels[current_zoom_idx]
				camera.zoom = Vector2(z, z)
				_apply_zoom_vision(z)
			return true

	# Mouse Click & Motion Conversion
	if event is InputEventMouseButton:
		var d1_pos = Vector2i.ZERO
		if diablo_bridge and diablo_bridge.has_method("map_world_to_screen"):
			var mouse_world = get_world_mouse_position(event.position)
			d1_pos = diablo_bridge.map_world_to_screen(mouse_world)
		else:
			var d1_w = diablo_bridge.get_frame_width() if (diablo_bridge and diablo_bridge.has_method("get_frame_width")) else 640
			var d1_h = diablo_bridge.get_frame_height() if (diablo_bridge and diablo_bridge.has_method("get_frame_height")) else 480
			var vp_size = get_viewport().get_visible_rect().size
			var norm_x = event.position.x / float(vp_size.x)
			var norm_y = event.position.y / float(vp_size.y)
			d1_pos = Vector2i(clampi(int(norm_x * float(d1_w)), 0, d1_w - 1), clampi(int(norm_y * float(d1_h)), 0, d1_h - 1))

		var btn = 1
		if event.button_index == MOUSE_BUTTON_RIGHT:
			btn = 3
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			btn = 2
		var state = 1 if event.pressed else 0

		if diablo_bridge and diablo_bridge.has_method("send_input"):
			diablo_bridge.send_input(2, btn, state, d1_pos.x, d1_pos.y)
		return true

	elif event is InputEventMouseMotion:
		var d1_pos = Vector2i.ZERO
		if diablo_bridge and diablo_bridge.has_method("map_world_to_screen"):
			var mouse_world = get_world_mouse_position(event.position)
			d1_pos = diablo_bridge.map_world_to_screen(mouse_world)
		else:
			var d1_w = diablo_bridge.get_frame_width() if (diablo_bridge and diablo_bridge.has_method("get_frame_width")) else 640
			var d1_h = diablo_bridge.get_frame_height() if (diablo_bridge and diablo_bridge.has_method("get_frame_height")) else 480
			var vp_size = get_viewport().get_visible_rect().size
			var norm_x = event.position.x / float(vp_size.x)
			var norm_y = event.position.y / float(vp_size.y)
			d1_pos = Vector2i(clampi(int(norm_x * float(d1_w)), 0, d1_w - 1), clampi(int(norm_y * float(d1_h)), 0, d1_h - 1))

		if diablo_bridge and diablo_bridge.has_method("send_input"):
			diablo_bridge.send_input(1, 0, 0, d1_pos.x, d1_pos.y)
		return true

	return false
