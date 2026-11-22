extends Node3D

# ==============================================================================
# Diablo: Definitive Edition — True Native 3D Engine (Mode 2)
# Authentic True-3D World in Godot 4.7 Forward+ Vulkan:
# - Modular 3D Dungeon Kit (.glb) with MultiMesh batching & PBR relief materials
# - Authentic animated characters & monsters with Forward+ 3D lighting & shadows
# - Interactive 3D props (braziers, torches, chests, sarcophagi, barrels, shrines)
# - GPUParticles3D fire embers and real-time organic light flicker
# - Tactical Orbit/Pitch/Zoom camera and 3D Ground-Plane Raycast Navigation
# ==============================================================================

var diablo_bridge = null
# Level-transition handover (see native_25d_view.gd): under AUTH_NATIVE the mirror decides when
# bridge state may be read. Resolved lazily because the bridge is injected after _ready().
var _gate_native: bool = false
var _gate_checked: bool = false
var _gate_canary: int = 0
var logic_authority = null  # injected in tests; otherwise the /root/logic_authority autoload
var transition_logic = preload("res://scripts/logic/d1_level_transition_logic.gd").new()
const FONT_EXOCET = preload("res://assets/fonts/Exocet.ttf")
const LAVA_3D_SHADER = preload("res://shaders/d1de_3d_lava.gdshader")
const ENTITY_HD_3D_SHADER = preload("res://shaders/entity_hd_upscaler_3d.gdshader")
const CORPSE_HD_3D_SHADER = preload("res://shaders/corpse_hd_upscaler_3d.gdshader")
const UpscalerModelConfig = preload("res://scripts/upscaler_model_config.gd")
const HdSpriteProvider = preload("res://scripts/hd_sprite_provider.gd")
var main_receiver = null

func _get_hud():
	if main_receiver == null:
		return null
	if main_receiver.get("modern_hud"):
		return main_receiver.get("modern_hud")
	if main_receiver.get("d1de_hud"):
		return main_receiver.get("d1de_hud")
	return null
var is_sandbox_active: bool = false

# --- Camera & Tracking ---
var camera: Camera3D = null
var camera_target: Vector3 = Vector3.ZERO
var camera_distance: float = 13.0
var camera_pitch: float = 30.0       # Pitch angle in degrees (range: 25° - 75°, default 30° true 2:1 isometric)
var camera_yaw: float = 0.0          # Yaw angle in degrees (Q/E orbit or MMB drag)
var camera_mode_perspective: bool = false # Default false: Pure 2:1 Isometric Orthogonal across all levels
var is_orbiting: bool = false
var last_mouse_pos: Vector2 = Vector2.ZERO
var dungeon_piece_floors: Dictionary = {} # theme (String) -> Dictionary of pid (int) -> true
var dungeon_piece_pillars: Dictionary = {} # theme (String) -> Dictionary of pid (int) -> bool
var piece_is_floor_cache: Dictionary = {} # pid (int) -> bool

const KNOWN_PILLAR_PIECES: Array[int] = [
	7, 8, 9, 15, 16, 24, 25, 26, 27, 28, 29, 33, 36, 37, 39, 40, 41, 46, 64, 105, 113, 117, 136, 269, 436, 440, 444, 447, 448
]

# --- Modular 3D Dungeon Kit MultiMeshes ---
var floor_root: Node3D = null
var floor_mmis: Dictionary = {}          # piece_id (int) -> MultiMeshInstance3D
var floor_diamond_mesh: Mesh = null
var floor_material_cache: Dictionary = {}# piece_id (int) -> StandardMaterial3D
var base_floor_texture_cache: Dictionary = {} # piece_id (int) -> ImageTexture (extracted row 0 paver for town buildings)
var floor_mmi: MultiMeshInstance3D       # fallback / baseline MMI
var wall_mmi: MultiMeshInstance3D
var wall_ns_mmi: MultiMeshInstance3D
var wall_ew_mmi: MultiMeshInstance3D
var pillar_mmi: MultiMeshInstance3D
var arch_mmi: MultiMeshInstance3D
var modular_3d_walls_enabled: bool = false # Modular 3D .glb boxes (disabled by default in favor of authentic 4K PBR gothic architecture)
var modular_3d_props_enabled: bool = false # Placeholder .glb props (disabled by default in favor of authentic gothic Blizzard North art with 3D lights)
var current_upscaler_mode: int = 0
var current_tile_model: int = 1
var current_hdr_level: int = 1
var hd_graphics_enabled: bool = true
var entity_materials: Dictionary = {} # Sprite3D -> ShaderMaterial

# --- Scenery Billboards (Town Buildings & Trees, Dungeon Walls & Arches) ---
var town_scenery_root: Node3D = null
var town_scenery_nodes: Dictionary = {}  # tile_idx (int) -> Sprite3D
var special_scenery_nodes: Dictionary = {} # tile_idx (int) -> Sprite3D
var translucent_scenery_indices: Dictionary = {} # tile_idx (int) -> true
var scenery_texture_cache: Dictionary = {} # piece_id (int) -> Texture2D
var scenery_special_cache: Dictionary = {} # special_id (int) -> Texture2D
var town_base_ground: MeshInstance3D = null
var dungeon_base_ground: MeshInstance3D = null
var stairs_root: Node3D = null
var stairs_nodes: Dictionary = {} # tile_idx (int) -> MeshInstance3D
var last_applied_scenery_yaw: float = 0.0

var dungeon_built: bool = false
var last_solidity_hash: int = 0
var last_level_idx: int = -999
var last_check_timer: float = 0.0
var mesh_cache: Dictionary = {}      # path (String) -> Mesh
var material_cache: Dictionary = {}  # key (String) -> Material
var last_solidity_grid: PackedByteArray = PackedByteArray()

# --- World Environment & Directional Light ---
var world_env: WorldEnvironment
var env: Environment
var dir_light: DirectionalLight3D

# --- Player Entity ---
var player_root: Node3D
var player_sprite: Sprite3D
var player_texture: ImageTexture = null
var last_player_frame: int = -1
var last_player_dir: int = -1
var player_lantern: OmniLight3D
var player_ring: MeshInstance3D
var player_arrow: MeshInstance3D
var player_target_pos: Vector3 = Vector3.ZERO
var hero_controller: Node3D = null
var current_player_class: int = -1
var warrior_controller: Node3D = null
var warrior_3d_enabled: bool = false

# --- Monster Entities ---
var monsters_root: Node3D
var monster_instances: Dictionary = {}    # id (int) -> Node3D
var monster_textures: Dictionary = {}     # id (int) -> ImageTexture
var monster_anim_cache: Dictionary = {}   # String (name_mode_dir_frame) -> Texture2D
var monster_last_frame: Dictionary = {}   # id (int) -> int
var monster_last_dir: Dictionary = {}     # id (int) -> int
var monster_unseen_frames: Dictionary = {}# id (int) -> int
var last_gamma_value: int = -1
var monsters_3d_enabled: bool = false

# --- Interactive 3D Props ---
var props_root: Node3D
var prop_instances: Dictionary = {}       # id (int) -> Node3D
var torch_instances: Dictionary = {}      # int (light index) -> Node3D
var last_prop_check_timer: float = 0.0

# --- Ground Items & Loot Drops ---
var items_root: Node3D
var item_instances: Dictionary = {}       # id (int) -> Node3D
var item_textures: Dictionary = {}        # String cache_key -> ImageTexture
var item_is_hd_cache: Dictionary = {}     # String cache_key -> bool
var last_item_check_timer: float = 0.0

# --- Missiles & Projectiles ---
var missiles_root: Node3D = null
var missile_instances: Dictionary = {}    # id (int) -> Node3D
var missile_textures: Dictionary = {}     # String cache_key -> ImageTexture

# --- Corpses & Fallen Entities ---
var corpses_root: Node3D = null
var corpse_instances: Dictionary = {}     # String key -> Node3D
var corpse_textures: Dictionary = {}      # String cache_key -> ImageTexture

# --- Waypoint / Click Feedback ---
var click_marker: MeshInstance3D
var click_fade: float = 0.0
var hovered_entity: Dictionary = {}
var last_hovered_item: Node3D = null

# --- Floating Combat Text & Hit VFX (Task 5.2) ---
const FloatingCombatTextManager = preload("res://scripts/floating_combat_text.gd")
var fct_manager: Node3D = null
var camera_trauma: float = 0.0
var flashing_entities: Dictionary = {}
var blood_splatter_scene: PackedScene = preload("res://scenes/effects/blood_splatter.tscn")
var bone_shards_scene: PackedScene = preload("res://scenes/effects/bone_shards.tscn")
var torch_sparks_scene: PackedScene = preload("res://scenes/effects/torch_sparks.tscn")
var fireball_explosion_scene: PackedScene = preload("res://scenes/effects/fireball_explosion.tscn")
var effects_root: Node3D = null

# --- Coordinate Math & Scale Constants ---
const TILE_SCALE: float = 0.75
const ENTITY_SCALE_MULT: float = 1.15        # Balanced heroic scale (fixes miniature cast & oversized idle)
const PIXEL_SIZE_1X: float = 0.0234375 * ENTITY_SCALE_MULT       # ~0.02695
const PIXEL_SIZE_HD: float = 0.005859375 * ENTITY_SCALE_MULT     # ~0.00674

var prop_last_frame: Dictionary = {}         # o_id (int) -> int (anim_frame)

# --- Time accumulator for lighting & animations ---
var time_accum: float = 0.0

func _bridge_read_gate_open() -> bool:
	if diablo_bridge == null:
		return true
	if not _gate_checked:
		_gate_checked = true
		var auth = logic_authority
		if auth == null and is_inside_tree():
			auth = get_node_or_null("/root/logic_authority")
		_gate_native = auth != null \
			and diablo_bridge.has_method("get_read_gate_state") \
			and auth.get_authority("level_transition") == auth.AUTH_NATIVE
		if _gate_native:
			print("[3D] level_transition gate: AUTH_NATIVE (native decision)")
	if not _gate_native:
		return not (diablo_bridge.is_level_loading() if diablo_bridge.has_method("is_level_loading") else false)
	var g = diablo_bridge.get_read_gate_state()
	var native_ok: bool = transition_logic.update_from_gate(g, int(diablo_bridge.get_current_level()))
	if native_ok != bool(g.get("safe", false)):
		_gate_canary += 1
		if _gate_canary <= 5 or _gate_canary % 300 == 0:
			push_warning("gate disagreement #%d native=%s engine=%s mirror_state=%d" % [
				_gate_canary, native_ok, g.get("safe", false), transition_logic.state])
	return native_ok


func _ready():
	setup_scene_nodes()
	set_process(false)

# ==============================================================================
# Scene Setup
# ==============================================================================

func setup_scene_nodes():
	# 1. Environment & Ambient Gothic Lighting
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.015, 0.02, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.45, 0.52, 1.0)
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	set_hdr_level(current_hdr_level)

	# AAA Forward+ Screen-Space Ambient Occlusion (SSAO)
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.8
	env.ssao_power = 1.5
	env.ssao_detail = 0.6

	# AAA Forward+ Screen-Space Indirect Lighting (SSIL)
	env.ssil_enabled = true
	env.ssil_radius = 3.2
	env.ssil_intensity = 0.95

	# Volumetric Fog & Atmospheric God-Rays
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(0.35, 0.38, 0.48, 1.0)
	env.volumetric_fog_emission = Color(0.03, 0.02, 0.01, 1.0)
	env.volumetric_fog_emission_energy = 0.4

	# Scene-wide WorldEnvironment
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	# 2. Directional Key Light
	dir_light = DirectionalLight3D.new()
	dir_light.name = "SandboxSunlight"
	dir_light.transform = Transform3D(
		Basis().rotated(Vector3.UP, deg_to_rad(-35.0)).rotated(Vector3.RIGHT, deg_to_rad(-55.0)),
		Vector3(0, 15, 0)
	)
	dir_light.light_color = Color(0.70, 0.80, 0.98, 1.0)
	dir_light.light_energy = 0.50
	dir_light.shadow_enabled = false
	add_child(dir_light)

	# 3. Procedural Modular 3D MultiMeshes
	setup_dungeon_multimeshes()

	# 3.5 Authentic Town Scenery Container (Buildings, Trees, Fences)
	town_scenery_root = Node3D.new()
	town_scenery_root.name = "TownSceneryRoot"
	add_child(town_scenery_root)

	# 3.8 Authentic 3D Stairs Container
	stairs_root = Node3D.new()
	stairs_root.name = "StairsRoot"
	add_child(stairs_root)

	# 4. Interactive 3D Props Container
	props_root = Node3D.new()
	props_root.name = "PropsRoot"
	add_child(props_root)

	# 4.5 Ground Items & Loot Drops Container
	items_root = Node3D.new()
	items_root.name = "ItemsRoot"
	add_child(items_root)

	# 5. Player Entity
	setup_player_entity()

	# 6. Monster Entities Container
	monsters_root = Node3D.new()
	monsters_root.name = "MonstersRoot"
	add_child(monsters_root)

	# 6.5 Missiles & Projectiles Container
	missiles_root = Node3D.new()
	missiles_root.name = "MissilesRoot"
	add_child(missiles_root)

	# 6.8 Corpses Container
	corpses_root = Node3D.new()
	corpses_root.name = "CorpsesRoot"
	add_child(corpses_root)

	# 6.9 Visual Effects & Particles Container
	effects_root = Node3D.new()
	effects_root.name = "EffectsRoot"
	add_child(effects_root)

	# 7. Click Marker
	setup_click_marker()

	# 7.5 Floating Combat Text Manager (Task 5.2)
	fct_manager = FloatingCombatTextManager.new()
	fct_manager.name = "FCTManager"
	add_child(fct_manager)

	# 8. Tactical Camera with Isolated Environment (True 2:1 Isometric Orthogonal standard)
	if not camera:
		camera = get_node_or_null("Camera3D")
	if not camera:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 14.5
		add_child(camera)
	camera.environment = env
	var listener = camera.get_node_or_null("AudioListener3D") as AudioListener3D
	if not listener:
		listener = AudioListener3D.new()
		listener.name = "AudioListener3D"
		camera.add_child(listener)
	listener.make_current()
	load_dungeon_piece_types()

func load_dungeon_piece_types():
	var json_path = "res://assets/data/dungeon_piece_types.json"
	if FileAccess.file_exists(json_path):
		var f = FileAccess.open(json_path, FileAccess.READ)
		if f != null:
			var text = f.get_as_text()
			var json = JSON.new()
			if json.parse(text) == OK and json.data is Dictionary:
				for theme in json.data.keys():
					var entry = json.data[theme]
					if entry is Dictionary and entry.has("floors"):
						var f_dict: Dictionary = {}
						for pid in entry["floors"]:
							f_dict[int(pid)] = true
						dungeon_piece_floors[theme] = f_dict

	# Load pillar piece classifications from occluders.json per theme
	for theme in ["cathedral", "catacombs", "caves", "hell"]:
		var occ_path = "res://assets/dungeon_pbr_%s_4x/occluders.json" % theme
		if not FileAccess.file_exists(occ_path) and theme == "cathedral":
			occ_path = "res://assets/dungeon_pbr_4x/occluders.json"
		if FileAccess.file_exists(occ_path):
			var occ_file = FileAccess.open(occ_path, FileAccess.READ)
			if occ_file:
				var occ_json = JSON.new()
				if occ_json.parse(occ_file.get_as_text()) == OK and occ_json.data is Dictionary:
					var p_dict: Dictionary = {}
					for k in occ_json.data.keys():
						var val = occ_json.data[k]
						if val is Dictionary and val.get("type", "") == "pillar":
							var pid_int = int(k.replace("piece_", ""))
							p_dict[pid_int] = true
					dungeon_piece_pillars[theme] = p_dict
	print("[Native 3D Sandbox] Loaded dungeon piece classifications for %d themes." % dungeon_piece_floors.size())

	# Certified AAA dark fantasy assets and interactive props
	set_theme_aaa_certified("cathedral", true)
	set_prop_aaa_certified("door", true)

func is_piece_pillar(piece_id: int, cur_level: int) -> bool:
	if cur_level == 0:
		return false
	var theme = get_theme_name(cur_level)
	if dungeon_piece_pillars.has(theme) and dungeon_piece_pillars[theme].has(piece_id):
		return true
	return piece_id in KNOWN_PILLAR_PIECES

func is_piece_floor(piece_id: int, cur_level: int) -> bool:
	if cur_level == 0:
		return true
	if piece_is_floor_cache.has(piece_id):
		return piece_is_floor_cache[piece_id]

	var theme = get_theme_name(cur_level)
	if dungeon_piece_floors.has(theme):
		var is_f = dungeon_piece_floors[theme].has(piece_id)
		piece_is_floor_cache[piece_id] = is_f
		return is_f

	# Fallback check from disk or bridge
	var alb_p = "res://assets/dungeon_pbr_%s_4x/albedo/piece_%d.png" % [theme, piece_id]
	if not FileAccess.file_exists(alb_p) and theme == "cathedral":
		alb_p = "res://assets/dungeon_pbr_4x/albedo/piece_%d.png" % piece_id
	if FileAccess.file_exists(alb_p):
		var img = Image.load_from_file(ProjectSettings.globalize_path(alb_p))
		if img and not img.is_empty():
			var tw = img.get_width()
			var th = img.get_height()
			var is_f = (th <= int(round(float(tw) * 0.5)))
			piece_is_floor_cache[piece_id] = is_f
			return is_f

	var is_f = (piece_id < 30)
	piece_is_floor_cache[piece_id] = is_f
	return is_f

static func _is_texture_pure_black(img: Image) -> bool:
	if img == null or img.is_empty():
		return true
	var w = img.get_width()
	var h = img.get_height()
	var step_x = max(1, w / 8)
	var step_y = max(1, h / 8)
	var found_color = false
	for sy in range(0, h, step_y):
		for sx in range(0, w, step_x):
			var col = img.get_pixel(sx, sy)
			if col.a > 0.05 and (col.r > 0.05 or col.g > 0.05 or col.b > 0.05):
				found_color = true
				break
		if found_color:
			break
	return not found_color

# ==============================================================================
# Modular 3D Dungeon Kit Pipeline & AAA Quality Certification
# ==============================================================================

# In accordance with project directives, any low-poly, prototype, or generic
# CC0 box meshes (e.g. 1 KB extruded wall cubes or modern white bathtubs) are
# strictly rejected from gameplay. Only models meeting AAA dark fantasy standards
# (sculpted reliefs, high polygon density, PBR maps, zero light leakage) are certified.

var aaa_certified_meshes: Dictionary = {}
var aaa_certified_themes: Dictionary = {}
var aaa_certified_props: Dictionary = {}

func is_mesh_aaa_certified(path: String) -> bool:
	if aaa_certified_meshes.has(path):
		return bool(aaa_certified_meshes[path])
	if path.begins_with("res://assets/models/aaa/"):
		return ResourceLoader.exists(path) or FileAccess.file_exists(ProjectSettings.globalize_path(path))
	return false

func can_use_modular_3d_walls(theme: String = "") -> bool:
	if not modular_3d_walls_enabled:
		return false
	if theme.is_empty():
		theme = get_theme_name(last_level_idx)
	return aaa_certified_themes.get(theme, false)

func can_use_modular_3d_prop(prop_key: String) -> bool:
	if not modular_3d_props_enabled:
		return false
	if prop_key in ["sarcophagus", "chest"]:
		# Sarcophagi and chests must use authentic Blizzard North gothic 4K PBR sprites
		# until fully certified gothic textured 3D models are provided (eliminates white bathtubs)
		return false
	return aaa_certified_props.get(prop_key, false)

func set_theme_aaa_certified(theme: String, certified: bool):
	aaa_certified_themes[theme] = certified

func set_prop_aaa_certified(prop_key: String, certified: bool):
	aaa_certified_props[prop_key] = certified

func set_mesh_aaa_certified(path: String, certified: bool):
	aaa_certified_meshes[path] = certified

func set_upscaler_mode(mode: int) -> void:
	current_upscaler_mode = clampi(mode, 0, 4)
	for mat in entity_materials.values():
		if is_instance_valid(mat):
			mat.set_shader_parameter("upscaler_mode", current_upscaler_mode)
			mat.set_shader_parameter("hd_enabled", hd_graphics_enabled)
	var filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if current_upscaler_mode == 4 else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if player_sprite:
		player_sprite.texture_filter = filter
	for m_node in monster_instances.values():
		if is_instance_valid(m_node):
			var spr = m_node.get_node_or_null("MonsterSprite3D") as Sprite3D
			if spr: spr.texture_filter = filter
	for p_node in prop_instances.values():
		if is_instance_valid(p_node):
			var spr = p_node.get_node_or_null("ObjectSprite3D") as Sprite3D
			if spr: spr.texture_filter = filter
	for it_node in item_instances.values():
		if is_instance_valid(it_node):
			var spr = it_node.get_node_or_null("ItemSprite") as Sprite3D
			if spr == null:
				spr = it_node.get_node_or_null("ItemSprite3D") as Sprite3D
			if spr: spr.texture_filter = filter
	for mis_node in missile_instances.values():
		if is_instance_valid(mis_node):
			var spr = mis_node.get_node_or_null("Sprite3D") as Sprite3D
			if spr: spr.texture_filter = filter
	for c_node in corpse_instances.values():
		if is_instance_valid(c_node):
			var spr = c_node.get_node_or_null("CorpseSprite") as Sprite3D
			if spr: spr.texture_filter = filter
	for spr in town_scenery_nodes.values():
		if is_instance_valid(spr):
			spr.texture_filter = filter
	for aspr in special_scenery_nodes.values():
		if is_instance_valid(aspr):
			aspr.texture_filter = filter
	for f_mat in floor_material_cache.values():
		if f_mat is BaseMaterial3D:
			f_mat.texture_filter = filter

func set_tile_model(model_id: int) -> void:
	var new_id = clampi(model_id, 0, UpscalerModelConfig.get_model_count() - 1)
	if current_tile_model == new_id:
		return
	current_tile_model = new_id
	floor_material_cache.clear()
	base_floor_texture_cache.clear()
	scenery_texture_cache.clear()
	scenery_special_cache.clear()
	HdSpriteProvider.clear_cache()
	rebuild_dungeon_if_needed(true)
	print("[Native 3D Sandbox] Tile Model switched to: %s" % UpscalerModelConfig.get_model_short_name(current_tile_model))

func get_tile_model() -> int:
	return current_tile_model

func set_hd_graphics_enabled(enabled: bool) -> void:
	if hd_graphics_enabled == enabled:
		return
	hd_graphics_enabled = enabled
	floor_material_cache.clear()
	base_floor_texture_cache.clear()
	scenery_texture_cache.clear()
	scenery_special_cache.clear()
	HdSpriteProvider.clear_cache()
	monster_anim_cache.clear()
	missile_textures.clear()
	corpse_textures.clear()
	item_textures.clear()
	item_is_hd_cache.clear()
	for mat in entity_materials.values():
		if is_instance_valid(mat):
			mat.set_shader_parameter("hd_enabled", hd_graphics_enabled)
	rebuild_dungeon_if_needed(true)

func get_hd_graphics_enabled() -> bool:
	return hd_graphics_enabled

func set_hdr_level(level: int) -> void:
	current_hdr_level = clampi(level, 0, 3)
	if env:
		match current_hdr_level:
			0:
				env.glow_enabled = false
				env.glow_intensity = 0.0
				env.glow_bloom = 0.0
			1:
				env.glow_enabled = true
				env.glow_intensity = 0.35
				env.glow_bloom = 0.08
			2:
				env.glow_enabled = true
				env.glow_intensity = 0.65
				env.glow_bloom = 0.18
			3:
				env.glow_enabled = true
				env.glow_intensity = 0.95
				env.glow_bloom = 0.30
	# Update emission energy across all active lava materials
	var emission_mult = 0.0 if current_hdr_level == 0 else (0.25 + float(current_hdr_level) * 0.25)
	for mat in floor_material_cache.values():
		if mat is ShaderMaterial and mat.shader == LAVA_3D_SHADER:
			mat.set_shader_parameter("emission_energy", emission_mult)

func apply_all_d1de_settings(torch: bool, fog: int, upscaler: int, relief: int, wet: bool, hdr: int = 1, tile_model: int = 0) -> void:
	set_upscaler_mode(upscaler)
	set_tile_model(tile_model)
	set_hdr_level(hdr)

func apply_all_resurrected_settings(torch: bool, fog: int, upscaler: int, relief: int, wet: bool, hdr: int = 1, tile_model: int = 0) -> void:
	apply_all_d1de_settings(torch, fog, upscaler, relief, wet, hdr, tile_model)

func apply_entity_hd_material(spr: Sprite3D, tex: Texture2D) -> void:
	if spr == null or tex == null:
		return
	var mat = entity_materials.get(spr, null) as ShaderMaterial
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = ENTITY_HD_3D_SHADER
		entity_materials[spr] = mat
		spr.material_override = mat
		if not spr.tree_exited.is_connected(_on_entity_sprite_tree_exited):
			spr.tree_exited.connect(_on_entity_sprite_tree_exited.bind(spr))

	if spr.render_priority != 0:
		mat.render_priority = spr.render_priority
	mat.set_shader_parameter("albedo_texture", tex)
	mat.set_shader_parameter("hd_enabled", hd_graphics_enabled)
	mat.set_shader_parameter("upscaler_mode", current_upscaler_mode)
	mat.set_shader_parameter("brightness", 1.0)
	var filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if current_upscaler_mode == 4 else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	spr.texture_filter = filter

func apply_corpse_hd_material(spr: Sprite3D, tex: Texture2D) -> void:
	if spr == null or tex == null:
		return
	var mat = entity_materials.get(spr, null) as ShaderMaterial
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = CORPSE_HD_3D_SHADER
		mat.render_priority = 1 # Corpse layer: above floor (0), strictly below items (2) and actors (3)
		entity_materials[spr] = mat
		spr.material_override = mat
		if not spr.tree_exited.is_connected(_on_entity_sprite_tree_exited):
			spr.tree_exited.connect(_on_entity_sprite_tree_exited.bind(spr))

	mat.render_priority = 1
	mat.set_shader_parameter("albedo_texture", tex)
	mat.set_shader_parameter("hd_enabled", hd_graphics_enabled)
	mat.set_shader_parameter("upscaler_mode", current_upscaler_mode)
	mat.set_shader_parameter("brightness", 1.0)
	var filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if current_upscaler_mode == 4 else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	spr.texture_filter = filter

func _on_entity_sprite_tree_exited(spr: Sprite3D) -> void:
	entity_materials.erase(spr)

func get_or_load_mesh(path: String) -> Mesh:
	if mesh_cache.has(path):
		return mesh_cache[path]

	var mesh: Mesh = null
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Mesh:
			mesh = res
		elif res is PackedScene:
			var inst = res.instantiate()
			if inst is MeshInstance3D:
				mesh = inst.mesh
			else:
				for child in inst.get_children():
					if child is MeshInstance3D:
						mesh = child.mesh
						break
			inst.free()

	if mesh == null:
		var global_p = ProjectSettings.globalize_path(path)
		var check_p = global_p if FileAccess.file_exists(global_p) else path
		if FileAccess.file_exists(check_p):
			var gltf_doc = GLTFDocument.new()
			var gltf_state = GLTFState.new()
			var err = gltf_doc.append_from_file(check_p, gltf_state)
			if err == OK:
				var root_node = gltf_doc.generate_scene(gltf_state)
				if root_node:
					if root_node is MeshInstance3D:
						mesh = root_node.mesh
					else:
						for child in root_node.get_children():
							if child is MeshInstance3D:
								mesh = child.mesh
								break
					root_node.free()

	if mesh == null:
		var fallback_box = BoxMesh.new()
		fallback_box.size = Vector3(1.06, 0.10, 1.06)
		mesh = fallback_box

	mesh_cache[path] = mesh
	return mesh

func get_theme_name(level_idx: int) -> String:
	if level_idx <= 0:
		return "town"
	elif level_idx >= 1 and level_idx <= 4:
		return "cathedral"
	elif level_idx >= 5 and level_idx <= 8:
		return "catacombs"
	elif level_idx >= 9 and level_idx <= 12:
		return "caves"
	else:
		return "hell"

func get_pbr_material_for_theme(theme: String, is_wall: bool = false) -> StandardMaterial3D:
	var cache_key = "%s_%s" % [theme, "wall" if is_wall else "floor"]
	if material_cache.has(cache_key):
		return material_cache[cache_key]

	var mat = StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

	if is_wall and theme != "town":
		var alb_p = "res://assets/textures/dungeon/%s_wall_albedo.png" % theme
		if not FileAccess.file_exists(alb_p):
			alb_p = "res://assets/textures/dungeon/%s_wall_albedo.jpg" % theme
		var norm_p = "res://assets/textures/dungeon/%s_wall_normal.png" % theme
		if not FileAccess.file_exists(norm_p):
			norm_p = "res://assets/textures/dungeon/%s_wall_normal.jpg" % theme
		var rough_p = "res://assets/textures/dungeon/%s_wall_roughness.png" % theme
		if not FileAccess.file_exists(rough_p):
			rough_p = "res://assets/textures/dungeon/%s_wall_roughness.jpg" % theme

		if not FileAccess.file_exists(alb_p):
			alb_p = "res://assets/kaykit_dungeon/texture/dungeon_texture_%s.png" % theme
			if not FileAccess.file_exists(alb_p):
				alb_p = "res://assets/kaykit_dungeon/texture/dungeon_texture.png"
		if not FileAccess.file_exists(norm_p):
			norm_p = "res://assets/kaykit_dungeon/texture/dungeon_texture_%s_normal.png" % theme
			if not FileAccess.file_exists(norm_p):
				norm_p = "res://assets/kaykit_dungeon/texture/dungeon_texture_normal.png"

		if FileAccess.file_exists(alb_p):
			var img = Image.load_from_file(ProjectSettings.globalize_path(alb_p))
			if img and not img.is_empty():
				img.generate_mipmaps()
				mat.albedo_texture = ImageTexture.create_from_image(img)
				mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

		if FileAccess.file_exists(norm_p):
			var nimg = Image.load_from_file(ProjectSettings.globalize_path(norm_p))
			if nimg and not nimg.is_empty():
				nimg.generate_mipmaps()
				mat.normal_texture = ImageTexture.create_from_image(nimg)
				mat.normal_enabled = true
				mat.normal_scale = 1.35
				mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

		if FileAccess.file_exists(rough_p):
			var rimg = Image.load_from_file(ProjectSettings.globalize_path(rough_p))
			if rimg and not rimg.is_empty():
				rimg.generate_mipmaps()
				mat.roughness_texture = ImageTexture.create_from_image(rimg)
				mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

		if theme == "hell":
			var em_p = "res://assets/textures/dungeon/hell_wall_emission.jpg"
			if not FileAccess.file_exists(em_p):
				em_p = "res://assets/kaykit_dungeon/texture/dungeon_texture_hell_emission.png"
			if FileAccess.file_exists(em_p):
				var eimg = Image.load_from_file(ProjectSettings.globalize_path(em_p))
				if eimg and not eimg.is_empty():
					eimg.generate_mipmaps()
					mat.emission_texture = ImageTexture.create_from_image(eimg)
					mat.emission_enabled = true
					mat.emission_energy_multiplier = 1.25
			else:
				mat.emission_enabled = true
				mat.emission = Color(0.85, 0.25, 0.05)
				mat.emission_energy_multiplier = 0.40

		if theme == "catacombs":
			# Ancient crypt limestone boost (compensates for dark 0.15 albedo map so walls match floor pavers)
			mat.albedo_color = Color(1.85, 1.80, 1.65)
		elif theme == "caves":
			# Warm cavern stone matching rock walls and D1 palette
			mat.albedo_color = Color(1.65, 1.30, 1.15)
		elif theme == "hell":
			mat.albedo_color = Color(1.45, 1.20, 1.10)
		elif theme == "cathedral":
			mat.albedo_color = Color(1.55, 1.50, 1.42)
		else:
			mat.albedo_color = Color(1.0, 1.0, 1.0)
		mat.roughness = 0.65
		mat.metallic = 0.04
	elif theme != "town":
		# Dungeon floor fallback
		mat.albedo_color = Color(0.85, 0.82, 0.78)
		mat.roughness = 0.65
		mat.metallic = 0.04
	else: # town (GEMINI.md Rule #1: Town Isolation)
		if not is_wall:
			mat.albedo_color = Color(0.40, 0.48, 0.30)
			mat.roughness = 0.80
			mat.metallic = 0.02
		else:
			mat.albedo_color = Color(0.45, 0.35, 0.24)
			mat.roughness = 0.70
			mat.metallic = 0.05

	material_cache[cache_key] = mat
	return mat

func get_floor_diamond_mesh() -> Mesh:
	if floor_diamond_mesh:
		return floor_diamond_mesh

	var arr_mesh = ArrayMesh.new()
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()

	var ts = TILE_SCALE # 0.75m
	# Clean 0.2% precision overlap (+1.5mm) eliminates numerical boundary gaps without cross-clipping adjacent diamond skirts
	var ts_v = ts * 1.002
	var skirt_h = 0.04 # 4cm skirt seals any subpixel vertical seams cleanly

	# Exact bijective diamond geometry matching Diablo 1's 2:1 isometric tile coordinates:
	# Inset UVs safely (2.0 texels) into the solid paver core away from transparent edges:
	var uv_dx = 2.0 / 256.0
	var uv_dy = 2.0 / 128.0

	var uv_north = Vector2(0.5, uv_dy)
	var uv_east  = Vector2(1.0 - uv_dx, 0.5)
	var uv_south = Vector2(0.5, 1.0 - uv_dy)
	var uv_west  = Vector2(uv_dx, 0.5)
	var uv_center = Vector2(0.5, 0.5)

	vertices.append_array([
		Vector3(0.0, 0.0, -ts_v),
		Vector3(+ts_v, 0.0, 0.0),
		Vector3(0.0, 0.0, +ts_v),
		Vector3(-ts_v, 0.0, 0.0),
		Vector3(0.0, 0.0, 0.0)
	])
	normals.append_array([
		Vector3(0, 1, 0), Vector3(0, 1, 0),
		Vector3(0, 1, 0), Vector3(0, 1, 0),
		Vector3(0, 1, 0)
	])
	uvs.append_array([
		uv_north,
		uv_east,
		uv_south,
		uv_west,
		uv_center
	])
	# 4 radial triangles from center to each quadrant (eliminates diagonal shear completely)
	indices.append_array([
		4, 1, 0, # Center -> East -> North (+Y normal)
		4, 2, 1, # Center -> South -> East (+Y normal)
		4, 3, 2, # Center -> West -> South (+Y normal)
		4, 0, 3  # Center -> North -> West (+Y normal)
	])

	# 2. Deep skirts on all 4 perimeter edges down to -skirt_h (eliminates tile seams completely)
	var norm_ne = Vector3(1, 0, -1).normalized()
	var norm_se = Vector3(1, 0, 1).normalized()
	var norm_sw = Vector3(-1, 0, 1).normalized()
	var norm_nw = Vector3(-1, 0, -1).normalized()

	_add_skirt_quad(vertices, normals, uvs, indices,
		Vector3(0, 0, -ts_v), Vector3(+ts_v, 0, 0),
		uv_north, uv_east, skirt_h, norm_ne)
	_add_skirt_quad(vertices, normals, uvs, indices,
		Vector3(+ts_v, 0, 0), Vector3(0, 0, +ts_v),
		uv_east, uv_south, skirt_h, norm_se)
	_add_skirt_quad(vertices, normals, uvs, indices,
		Vector3(0, 0, +ts_v), Vector3(-ts_v, 0, 0),
		uv_south, uv_west, skirt_h, norm_sw)
	_add_skirt_quad(vertices, normals, uvs, indices,
		Vector3(-ts_v, 0, 0), Vector3(0, 0, -ts_v),
		uv_west, uv_north, skirt_h, norm_nw)

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	floor_diamond_mesh = arr_mesh
	return floor_diamond_mesh

func _add_skirt_quad(verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array, idxs: PackedInt32Array, v_tl: Vector3, v_tr: Vector3, uv_l: Vector2, uv_r: Vector2, h: float, norm: Vector3):
	var base_idx = verts.size()
	var v_bl = v_tl - Vector3(0, h, 0)
	var v_br = v_tr - Vector3(0, h, 0)
	verts.append_array([v_tl, v_tr, v_br, v_bl])
	norms.append_array([norm, norm, norm, norm])
	uvs.append_array([uv_l, uv_r, uv_r, uv_l])
	idxs.append_array([base_idx, base_idx + 1, base_idx + 2, base_idx, base_idx + 2, base_idx + 3])

func _is_lava_piece(img: Image, theme: String) -> bool:
	if theme != "caves" and theme != "hell":
		return false
	if img == null or img.is_empty():
		return false
	var w = img.get_width()
	var h = img.get_height()
	var sample_step = max(1, w / 16)
	var red_dominant_count = 0
	var total_sampled = 0
	for y in range(0, h, sample_step):
		for x in range(0, w, sample_step):
			var c = img.get_pixel(x, y)
			if c.a > 0.10:
				total_sampled += 1
				if c.r > 0.35 and c.r > c.b * 1.8 and c.g > c.b * 1.1:
					red_dominant_count += 1
	if total_sampled > 0 and float(red_dominant_count) / float(total_sampled) > 0.015:
		return true
	return false

func get_theme_base_floor_piece_id(level_idx: int) -> int:
	if level_idx <= 0:
		return 218 # Town authentic grass
	elif level_idx >= 1 and level_idx <= 4:
		return 1 # Cathedral stone paver
	elif level_idx >= 5 and level_idx <= 8:
		return 1 # Catacombs stone paver
	elif level_idx >= 9 and level_idx <= 12:
		return 4 # Caves stone paver
	else:
		return 3 # Hell lava-rock paver

func _is_image_empty_or_transparent(img: Image) -> bool:
	if img == null or img.is_empty():
		return true
	var w = img.get_width()
	var h = img.get_height()
	var step_x = max(1, w / 16)
	var step_y = max(1, h / 16)
	var solid_count = 0
	for y in range(0, h, step_y):
		for x in range(0, w, step_x):
			if img.get_pixel(x, y).a > 0.05:
				solid_count += 1
				if solid_count >= 8:
					return false
	return true

func get_floor_material(piece_id: int, cur_level: int) -> Material:
	var f_key = "%d_%d_%d_%s" % [cur_level, piece_id, current_tile_model, str(hd_graphics_enabled)]
	if floor_material_cache.has(f_key):
		return floor_material_cache[f_key]

	var mat = StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.roughness = 0.65
	mat.metallic = 0.04

	var theme = get_theme_name(cur_level)
	var is_dungeon = (cur_level > 0)
	var alb_tex: Texture2D = null
	var norm_tex: Texture2D = null

	if is_dungeon and hd_graphics_enabled:
		var pbr_folder = UpscalerModelConfig.get_tile_folder(cur_level, current_tile_model)
		if current_tile_model > 0 and pbr_folder != "":
			var alb_dir = pbr_folder + "/albedo"
			if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(alb_dir)):
				pbr_folder = UpscalerModelConfig.get_tile_folder(cur_level, 0)

		var alb_p = "%s/albedo/piece_%d.png" % [pbr_folder, piece_id]
		var norm_p = "%s/normal/piece_%d_n.png" % [pbr_folder, piece_id]
		var spec_p = "%s/specular/piece_%d_s.png" % [pbr_folder, piece_id]

		if not FileAccess.file_exists(alb_p):
			var fb_folder = UpscalerModelConfig.get_fallback_tile_folder(cur_level, current_tile_model)
			if fb_folder == "" or not FileAccess.file_exists("%s/albedo/piece_%d.png" % [fb_folder, piece_id]):
				fb_folder = UpscalerModelConfig.get_fallback_tile_folder(cur_level, 0)
			if fb_folder != "" and FileAccess.file_exists("%s/albedo/piece_%d.png" % [fb_folder, piece_id]):
				alb_p = "%s/albedo/piece_%d.png" % [fb_folder, piece_id]
				norm_p = "%s/normal/piece_%d_n.png" % [fb_folder, piece_id]
				spec_p = "%s/specular/piece_%d_s.png" % [fb_folder, piece_id]

		if FileAccess.file_exists(alb_p):
			var img = Image.load_from_file(ProjectSettings.globalize_path(alb_p))
			if img and not img.is_empty():
				var tw = img.get_width()
				var th = img.get_height()
				var floor_h = int(round(float(tw) * 0.5))
				if th > floor_h:
					img = img.get_region(Rect2i(0, th - floor_h, tw, floor_h))
				if not _is_image_empty_or_transparent(img):
					img.generate_mipmaps()
					alb_tex = ImageTexture.create_from_image(img)
				else:
					alb_tex = null

		if alb_tex != null and FileAccess.file_exists(norm_p):
			var n_img = Image.load_from_file(ProjectSettings.globalize_path(norm_p))
			if n_img and not n_img.is_empty():
				var n_tw = n_img.get_width()
				var n_th = n_img.get_height()
				var n_floor_h = int(round(float(n_tw) * 0.5))
				if n_th > n_floor_h:
					n_img = n_img.get_region(Rect2i(0, n_th - n_floor_h, n_tw, n_floor_h))
				n_img.generate_mipmaps()
				norm_tex = ImageTexture.create_from_image(n_img)

		if alb_tex != null and FileAccess.file_exists(spec_p):
			var s_img = Image.load_from_file(ProjectSettings.globalize_path(spec_p))
			if s_img and not s_img.is_empty():
				var s_tw = s_img.get_width()
				var s_th = s_img.get_height()
				var s_floor_h = int(round(float(s_tw) * 0.5))
				if s_th > s_floor_h:
					s_img = s_img.get_region(Rect2i(0, s_th - s_floor_h, s_tw, s_floor_h))
				s_img.generate_mipmaps()
				mat.roughness_texture = ImageTexture.create_from_image(s_img)

	# Town (cur_level == 0): Use extracted row 0 foundation paver or direct bridge texture
	if not is_dungeon and base_floor_texture_cache.has(f_key):
		alb_tex = base_floor_texture_cache[f_key]

	# Fallback to engine bridge piece texture if no PBR file on disk (or strictly in Town per GEMINI.md Rule #1)
	if alb_tex == null and diablo_bridge and diablo_bridge.has_method("get_dungeon_piece_texture"):
		alb_tex = diablo_bridge.get_dungeon_piece_texture(piece_id)
		if alb_tex != null:
			var tw = alb_tex.get_width()
			var th = alb_tex.get_height()
			var floor_h = int(round(float(tw) * 0.5))
			if th > floor_h:
				var img = alb_tex.get_image()
				if img and not img.is_empty():
					var floor_img = img.get_region(Rect2i(0, th - floor_h, tw, floor_h))
					if not _is_image_empty_or_transparent(floor_img):
						floor_img.generate_mipmaps()
						alb_tex = ImageTexture.create_from_image(floor_img)
						if not is_dungeon:
							base_floor_texture_cache[f_key] = alb_tex
					else:
						alb_tex = null

	# If the piece has no solid floor paver in row 0, fallback to authentic theme base floor piece!
	var base_pid = get_theme_base_floor_piece_id(cur_level)
	if alb_tex == null and piece_id != base_pid:
		var fallback_mat = get_floor_material(base_pid, cur_level)
		floor_material_cache[f_key] = fallback_mat
		return fallback_mat

	if alb_tex:
		mat.albedo_texture = alb_tex
		var filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if current_upscaler_mode == 4 else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mat.texture_filter = filter
		# Town uses warm natural daylight; dungeons use thematic balanced reflectance
		if cur_level == 0:
			mat.albedo_color = Color(1.10, 1.08, 1.02)
		elif theme == "caves":
			# Warm reddish-brown cave stone boost matching rock walls and authentic D1 palette
			mat.albedo_color = Color(1.85, 1.35, 1.25)
		elif theme == "hell":
			# Volcanic paver rock boost
			mat.albedo_color = Color(1.70, 1.25, 1.15)
		elif theme == "catacombs":
			mat.albedo_color = Color(1.15, 1.18, 1.10)
		else:
			mat.albedo_color = Color(1.15, 1.15, 1.20)
	else:
		if cur_level == 0:
			mat.albedo_color = Color(0.25, 0.35, 0.18)
		elif theme == "caves":
			mat.albedo_color = Color(0.65, 0.42, 0.32)
		elif theme == "hell":
			mat.albedo_color = Color(0.60, 0.30, 0.24)
		else:
			mat.albedo_color = Color(0.85, 0.82, 0.78)

	if norm_tex:
		mat.normal_enabled = true
		mat.normal_texture = norm_tex
		mat.normal_scale = 0.90
		var filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if current_upscaler_mode == 4 else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mat.texture_filter = filter

	# Check for incandescent flowing lava in Caves & Hell
	if is_dungeon and (theme == "caves" or theme == "hell") and alb_tex != null:
		var img = alb_tex.get_image()
		if _is_lava_piece(img, theme):
			var l_mat = ShaderMaterial.new()
			l_mat.shader = LAVA_3D_SHADER
			l_mat.set_shader_parameter("albedo_texture", alb_tex)
			l_mat.set_shader_parameter("is_hell", theme == "hell")
			var emission_mult = 0.0 if current_hdr_level == 0 else (0.25 + float(current_hdr_level) * 0.25)
			l_mat.set_shader_parameter("emission_energy", emission_mult)
			if norm_tex:
				l_mat.set_shader_parameter("normal_texture", norm_tex)
			floor_material_cache[f_key] = l_mat
			return l_mat

	floor_material_cache[f_key] = mat
	return mat

func get_scenery_piece_texture(piece_id: int, cur_level: int) -> Texture2D:
	var s_key = "%d_%d_%d_%s" % [cur_level, piece_id, current_tile_model, str(hd_graphics_enabled)]
	if scenery_texture_cache.has(s_key):
		return scenery_texture_cache[s_key]

	var tex: Texture2D = null
	var is_dungeon = (cur_level > 0)

	if is_dungeon and hd_graphics_enabled:
		var theme = get_theme_name(cur_level)
		var pbr_folder = UpscalerModelConfig.get_tile_folder(cur_level, current_tile_model)
		if current_tile_model > 0 and pbr_folder != "":
			var alb_dir = pbr_folder + "/albedo"
			if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(alb_dir)):
				pbr_folder = UpscalerModelConfig.get_tile_folder(cur_level, 0)

		var alb_p = "%s/albedo/piece_%d.png" % [pbr_folder, piece_id]

		if not FileAccess.file_exists(alb_p):
			var fb_folder = UpscalerModelConfig.get_fallback_tile_folder(cur_level, current_tile_model)
			if fb_folder == "" or not FileAccess.file_exists("%s/albedo/piece_%d.png" % [fb_folder, piece_id]):
				fb_folder = UpscalerModelConfig.get_fallback_tile_folder(cur_level, 0)
			if fb_folder != "" and FileAccess.file_exists("%s/albedo/piece_%d.png" % [fb_folder, piece_id]):
				alb_p = "%s/albedo/piece_%d.png" % [fb_folder, piece_id]

		if FileAccess.file_exists(alb_p):
			var img = Image.load_from_file(ProjectSettings.globalize_path(alb_p))
			if img and not img.is_empty():
				img.generate_mipmaps()
				tex = ImageTexture.create_from_image(img)

	# Town (cur_level == 0) or fallback: strictly use engine bridge (GEMINI.md Rule #1: Town Isolation)
	if tex == null and diablo_bridge and diablo_bridge.has_method("get_dungeon_piece_texture"):
		tex = diablo_bridge.get_dungeon_piece_texture(piece_id)

	if tex:
		scenery_texture_cache[s_key] = tex
	return tex

func get_scenery_special_texture(special_id: int, cur_level: int) -> Texture2D:
	var spec_key = "%d_%d_%d_%s" % [cur_level, special_id, current_tile_model, str(hd_graphics_enabled)]
	if scenery_special_cache.has(spec_key):
		return scenery_special_cache[spec_key]

	# Strictly Cathedral only (GEMINI.md Rule #2: Special CEL Archways Gating)
	if cur_level < 1 or cur_level > 4:
		return null

	var tex: Texture2D = null
	if hd_graphics_enabled:
		var cath_folder = UpscalerModelConfig.get_tile_folder(cur_level, current_tile_model)
		if current_tile_model > 0 and cath_folder != "":
			if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(cath_folder + "/albedo")):
				cath_folder = UpscalerModelConfig.get_tile_folder(cur_level, 0)

		var alb_p = "%s/albedo/special_%d.png" % [cath_folder, special_id]
		if not FileAccess.file_exists(alb_p):
			var fb_folder = UpscalerModelConfig.get_fallback_tile_folder(cur_level, current_tile_model)
			if fb_folder == "" or not FileAccess.file_exists("%s/albedo/special_%d.png" % [fb_folder, special_id]):
				fb_folder = UpscalerModelConfig.get_fallback_tile_folder(cur_level, 0)
			if fb_folder != "" and FileAccess.file_exists("%s/albedo/special_%d.png" % [fb_folder, special_id]):
				alb_p = "%s/albedo/special_%d.png" % [fb_folder, special_id]

		if FileAccess.file_exists(alb_p):
			var img = Image.load_from_file(ProjectSettings.globalize_path(alb_p))
			if img and not img.is_empty():
				img.generate_mipmaps()
				tex = ImageTexture.create_from_image(img)

	if tex == null and diablo_bridge and diablo_bridge.has_method("get_special_cel_texture"):
		tex = diablo_bridge.get_special_cel_texture(special_id)

	if tex:
		scenery_special_cache[spec_key] = tex
	return tex

func setup_dungeon_multimeshes():
	# 0. Multi-Piece Floor MultiMeshes Container
	floor_root = Node3D.new()
	floor_root.name = "FloorMMIRoot"
	add_child(floor_root)

	# 0.5 Town Base Continuous Ground Plane (Eliminates sky-blue void holes beneath Town)
	town_base_ground = MeshInstance3D.new()
	town_base_ground.name = "TownBaseGroundPlane"
	var p_mesh = PlaneMesh.new()
	p_mesh.size = Vector2(240.0, 240.0)
	town_base_ground.mesh = p_mesh
	# Map center of 112x112 is at tx=56, ty=56 -> world pos is (0.0, -0.015, 84.0)
	town_base_ground.position = Vector3(0.0, -0.015, 84.0)
	var g_mat = StandardMaterial3D.new()
	g_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	g_mat.roughness = 0.85
	g_mat.metallic = 0.02
	g_mat.albedo_color = Color(1.10, 1.08, 1.02)
	g_mat.uv1_scale = Vector3(80.0, 80.0, 1.0)
	town_base_ground.material_override = g_mat
	town_base_ground.visible = false
	add_child(town_base_ground)

	# 0.6 Dungeon Base Continuous Deep Void Plane (Sits well below floor geometry at -1.0m, pitch-black void)
	dungeon_base_ground = MeshInstance3D.new()
	dungeon_base_ground.name = "DungeonBaseGroundPlane"
	var dp_mesh = PlaneMesh.new()
	dp_mesh.size = Vector2(240.0, 240.0)
	dungeon_base_ground.mesh = dp_mesh
	dungeon_base_ground.position = Vector3(0.0, -1.0, 84.0)
	var dg_mat = StandardMaterial3D.new()
	dg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	dg_mat.roughness = 1.0
	dg_mat.metallic = 0.0
	dg_mat.albedo_color = Color(0.0, 0.0, 0.0)
	dungeon_base_ground.material_override = dg_mat
	dungeon_base_ground.visible = false
	add_child(dungeon_base_ground)

	# 1. Fallback Floor MultiMesh (for town / legacy baseline)
	floor_mmi = MultiMeshInstance3D.new()
	floor_mmi.name = "FloorMultiMesh"
	var floor_mm = MultiMesh.new()
	floor_mm.transform_format = MultiMesh.TRANSFORM_3D
	floor_mmi.multimesh = floor_mm
	add_child(floor_mmi)

	# 2. Wall Blocks MultiMesh
	wall_mmi = MultiMeshInstance3D.new()
	wall_mmi.name = "WallMultiMesh"
	var wall_mm = MultiMesh.new()
	wall_mm.transform_format = MultiMesh.TRANSFORM_3D
	wall_mmi.multimesh = wall_mm
	add_child(wall_mmi)

	# 3. N-S Wall MultiMesh
	wall_ns_mmi = MultiMeshInstance3D.new()
	wall_ns_mmi.name = "WallNSMultiMesh"
	var wall_ns_mm = MultiMesh.new()
	wall_ns_mm.transform_format = MultiMesh.TRANSFORM_3D
	wall_ns_mmi.multimesh = wall_ns_mm
	add_child(wall_ns_mmi)

	# 4. E-W Wall MultiMesh
	wall_ew_mmi = MultiMeshInstance3D.new()
	wall_ew_mmi.name = "WallEWMultiMesh"
	var wall_ew_mm = MultiMesh.new()
	wall_ew_mm.transform_format = MultiMesh.TRANSFORM_3D
	wall_ew_mmi.multimesh = wall_ew_mm
	add_child(wall_ew_mmi)

	# 5. Pillars & Columns MultiMesh
	pillar_mmi = MultiMeshInstance3D.new()
	pillar_mmi.name = "PillarMultiMesh"
	var pillar_mm = MultiMesh.new()
	pillar_mm.transform_format = MultiMesh.TRANSFORM_3D
	pillar_mmi.multimesh = pillar_mm
	add_child(pillar_mmi)

	# 6. Doors & Arches MultiMesh
	arch_mmi = MultiMeshInstance3D.new()
	arch_mmi.name = "ArchMultiMesh"
	var arch_mm = MultiMesh.new()
	arch_mm.transform_format = MultiMesh.TRANSFORM_3D
	arch_mmi.multimesh = arch_mm
	add_child(arch_mmi)

	update_modular_dungeon_assets(1)

func update_modular_dungeon_assets(level_idx: int):
	last_level_idx = level_idx
	var theme = get_theme_name(level_idx)
	var is_dungeon = (level_idx > 0)

	# Load modular meshes for current theme
	var floor_mesh = get_or_load_mesh("res://assets/models/dungeon/floor_%s.glb" % theme)
	var wall_block_mesh = get_or_load_mesh("res://assets/models/dungeon/wall_block.glb")
	var wall_ns_mesh = get_or_load_mesh("res://assets/models/dungeon/wall_ns.glb")
	var wall_ew_mesh = get_or_load_mesh("res://assets/models/dungeon/wall_ew.glb")
	var pillar_mesh = get_or_load_mesh("res://assets/models/dungeon/pillar.glb")
	var arch_mesh = get_or_load_mesh("res://assets/models/dungeon/arch_door.glb")
	if arch_mesh == null or (arch_mesh is BoxMesh):
		arch_mesh = get_or_load_mesh("res://assets/models/dungeon/arch_open.glb")

	# Certified AAA Dark Fantasy Kits for ALL 4 Themes (Cathedral, Catacombs, Caves, Hell)
	var theme_suffix = "gothic" if theme == "cathedral" else theme
	var aaa_ns = "res://assets/models/aaa/%s/wall_ns_%s.res" % [theme, theme_suffix]
	var aaa_ew = "res://assets/models/aaa/%s/wall_ew_%s.res" % [theme, theme_suffix]
	var aaa_corner = "res://assets/models/aaa/%s/wall_corner_%s.res" % [theme, theme_suffix]
	var aaa_pillar = "res://assets/models/aaa/%s/pillar_%s.res" % [theme, theme_suffix]
	var aaa_arch = "res://assets/models/aaa/%s/arch_door_%s.res" % [theme, theme_suffix]

	if ResourceLoader.exists(aaa_ns) and ResourceLoader.exists(aaa_ew):
		wall_ns_mesh = get_or_load_mesh(aaa_ns)
		wall_ew_mesh = get_or_load_mesh(aaa_ew)
		wall_block_mesh = get_or_load_mesh(aaa_corner)
		pillar_mesh = get_or_load_mesh(aaa_pillar)
		if ResourceLoader.exists(aaa_arch):
			arch_mesh = get_or_load_mesh(aaa_arch)
		set_theme_aaa_certified(theme, true)

	var floor_mat = get_pbr_material_for_theme(theme, false)
	var wall_mat = get_pbr_material_for_theme(theme, true)
	if wall_mat:
		wall_mat.render_priority = 3 # Solid modular 3D walls, pillars, and arches match actor layer (3) and occlude corpses (1) and items (2)

	if floor_mmi and floor_mmi.multimesh:
		floor_mmi.multimesh.mesh = floor_mesh
		floor_mmi.material_override = floor_mat

	if wall_mmi and wall_mmi.multimesh:
		wall_mmi.multimesh.mesh = wall_block_mesh
		wall_mmi.material_override = wall_mat

	if wall_ns_mmi and wall_ns_mmi.multimesh:
		wall_ns_mmi.multimesh.mesh = wall_ns_mesh
		wall_ns_mmi.material_override = wall_mat

	if wall_ew_mmi and wall_ew_mmi.multimesh:
		wall_ew_mmi.multimesh.mesh = wall_ew_mesh
		wall_ew_mmi.material_override = wall_mat

	if pillar_mmi and pillar_mmi.multimesh:
		pillar_mmi.multimesh.mesh = pillar_mesh
		pillar_mmi.material_override = wall_mat

	if arch_mmi and arch_mmi.multimesh:
		arch_mmi.multimesh.mesh = arch_mesh
		arch_mmi.material_override = wall_mat

	# Update atmosphere & lighting for Town vs Dungeon
	if town_base_ground:
		town_base_ground.visible = not is_dungeon
		if not is_dungeon:
			var grass_tex: Texture2D = null
			if diablo_bridge and diablo_bridge.has_method("get_dungeon_piece_texture"):
				grass_tex = diablo_bridge.get_dungeon_piece_texture(218)
				if grass_tex == null:
					grass_tex = diablo_bridge.get_dungeon_piece_texture(0)
			if grass_tex != null:
				var g_mat = town_base_ground.material_override as StandardMaterial3D
				if g_mat:
					g_mat.albedo_texture = grass_tex
					g_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	if dungeon_base_ground:
		dungeon_base_ground.visible = is_dungeon
		if is_dungeon:
			var base_mat = dungeon_base_ground.material_override as StandardMaterial3D
			if base_mat:
				base_mat.albedo_texture = null
				base_mat.normal_enabled = false
				base_mat.albedo_color = Color(0.0, 0.0, 0.0)

	if not is_dungeon:
		# Town: Open-air daytime sunlit ambiance with Orthogonal Camera
		if camera:
			if camera_mode_perspective:
				camera.projection = Camera3D.PROJECTION_PERSPECTIVE
				camera.fov = 50.0
			else:
				camera.projection = Camera3D.PROJECTION_ORTHOGONAL
				camera.size = camera_distance * (14.5 / 13.0)
				camera_pitch = 30.0
				camera_yaw = 0.0
		if env:
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.48, 0.58, 0.72, 1.0) # Warm daylight sky
			env.ambient_light_color = Color(0.95, 0.96, 0.92, 1.0)
			env.ambient_light_energy = 1.35
			env.volumetric_fog_enabled = false
		if dir_light:
			dir_light.shadow_enabled = true
			dir_light.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
			dir_light.light_color = Color(1.0, 0.98, 0.90, 1.0)
			dir_light.light_energy = 2.20
			dir_light.directional_shadow_max_distance = 60.0
			dir_light.shadow_bias = 0.05
		if player_lantern:
			player_lantern.light_energy = 0.0
	else:
		# Dungeon: Distinct thematic atmosphere with True 2:1 Isometric Orthogonal Camera (matching Town's perfection)
		if camera:
			if camera_mode_perspective:
				camera.projection = Camera3D.PROJECTION_PERSPECTIVE
				camera.fov = 50.0
				if camera_pitch == 30.0:
					camera_pitch = 50.0
			else:
				camera.projection = Camera3D.PROJECTION_ORTHOGONAL
				camera.size = camera_distance * (14.5 / 13.0)
				camera_pitch = 30.0
				camera_yaw = 0.0
		if env:
			env.background_mode = Environment.BG_COLOR
			env.volumetric_fog_enabled = true

			if theme == "cathedral":
				env.background_color = Color(0.015, 0.015, 0.02, 1.0)
				env.ambient_light_color = Color(0.42, 0.45, 0.52, 1.0)
				env.ambient_light_energy = 0.85
				env.volumetric_fog_density = 0.005
				env.volumetric_fog_albedo = Color(0.65, 0.70, 0.85)
			elif theme == "catacombs":
				env.background_color = Color(0.012, 0.016, 0.012, 1.0)
				env.ambient_light_color = Color(0.38, 0.42, 0.35, 1.0)
				env.ambient_light_energy = 0.78
				env.volumetric_fog_density = 0.008
				env.volumetric_fog_albedo = Color(0.55, 0.65, 0.50)
			elif theme == "caves":
				env.background_color = Color(0.02, 0.012, 0.008, 1.0)
				env.ambient_light_color = Color(0.45, 0.32, 0.22, 1.0)
				env.ambient_light_energy = 0.80
				env.volumetric_fog_density = 0.012
				env.volumetric_fog_albedo = Color(0.75, 0.40, 0.20)
			elif theme == "hell":
				env.background_color = Color(0.025, 0.008, 0.006, 1.0)
				env.ambient_light_color = Color(0.50, 0.20, 0.15, 1.0)
				env.ambient_light_energy = 0.88
				env.volumetric_fog_density = 0.015
				env.volumetric_fog_albedo = Color(0.85, 0.18, 0.10)

		if dir_light:
			# Directional sunlight shadows only in Town (cur_level == 0); underground dungeons use omni lantern/torch lighting
			dir_light.shadow_enabled = false
			dir_light.directional_shadow_max_distance = 40.0
			dir_light.shadow_bias = 0.05

			if theme == "cathedral":
				dir_light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
				dir_light.light_color = Color(0.60, 0.70, 0.88, 1.0)
				dir_light.light_energy = 0.15
			elif theme == "catacombs":
				dir_light.rotation_degrees = Vector3(-50.0, -40.0, 0.0)
				dir_light.light_color = Color(0.48, 0.58, 0.44, 1.0)
				dir_light.light_energy = 0.08
			elif theme == "caves":
				# Upward/diagonal reflection from molten magma flows below
				dir_light.rotation_degrees = Vector3(-35.0, -20.0, 0.0)
				dir_light.light_color = Color(0.90, 0.45, 0.18, 1.0)
				dir_light.light_energy = 0.12
			elif theme == "hell":
				# Fierce infernal brimstone downpour
				dir_light.rotation_degrees = Vector3(-60.0, -30.0, 0.0)
				dir_light.light_color = Color(1.0, 0.28, 0.12, 1.0)
				dir_light.light_energy = 0.20

		if player_lantern:
			if theme == "hell":
				player_lantern.light_color = Color(1.0, 0.65, 0.42)
				player_lantern.light_energy = 2.60
			elif theme == "caves":
				player_lantern.light_color = Color(1.0, 0.72, 0.40)
				player_lantern.light_energy = 2.40
			else:
				player_lantern.light_color = Color(1.0, 0.80, 0.50)
				player_lantern.light_energy = 2.40
			player_lantern.omni_range = 16.0
			player_lantern.omni_attenuation = 1.05
			player_lantern.shadow_enabled = true
			player_lantern.light_cull_mask = 1
			player_lantern.shadow_bias = 0.06
			player_lantern.shadow_normal_bias = 1.2
			player_lantern.shadow_blur = 1.5
			player_lantern.omni_shadow_mode = OmniLight3D.SHADOW_CUBE

func _on_level_changed(new_lvl: int):
	last_level_idx = new_lvl
	last_solidity_hash = 0
	last_check_timer = 0.0

	# 1. Clear all floor MultiMeshes & caches
	if floor_root:
		for c in floor_root.get_children():
			c.queue_free()
	floor_mmis.clear()
	floor_material_cache.clear()
	base_floor_texture_cache.clear()
	piece_is_floor_cache.clear()

	# 2. Clear all scenery sprites & special arches & caches
	if town_scenery_root:
		for c in town_scenery_root.get_children():
			c.queue_free()
	town_scenery_nodes.clear()
	special_scenery_nodes.clear()
	translucent_scenery_indices.clear()
	scenery_texture_cache.clear()
	scenery_special_cache.clear()

	# 3. Clear stairs
	if stairs_root:
		for c in stairs_root.get_children():
			c.queue_free()
	stairs_nodes.clear()

	# 4. Clear all monsters
	if monsters_root:
		for c in monsters_root.get_children():
			c.queue_free()
	monster_instances.clear()
	monster_textures.clear()
	monster_anim_cache.clear()
	monster_last_frame.clear()
	monster_last_dir.clear()
	monster_unseen_frames.clear()

	# 5. Clear all ground items
	if items_root:
		for c in items_root.get_children():
			c.queue_free()
	item_instances.clear()
	item_textures.clear()
	item_is_hd_cache.clear()

	# 5.5 Clear missiles & corpses
	if missiles_root:
		for c in missiles_root.get_children():
			c.queue_free()
	missile_instances.clear()
	missile_textures.clear()

	if corpses_root:
		for c in corpses_root.get_children():
			c.queue_free()
	corpse_instances.clear()
	corpse_textures.clear()

	# 5.6 Clear visual effects
	if effects_root:
		for c in effects_root.get_children():
			c.queue_free()

	# Preserve player material while clearing freed entity materials
	var p_mat = entity_materials.get(player_sprite, null)
	entity_materials.clear()
	if player_sprite and p_mat:
		entity_materials[player_sprite] = p_mat

	# 6. Clear all props & torches
	if props_root:
		for c in props_root.get_children():
			c.queue_free()
	prop_instances.clear()
	torch_instances.clear()
	prop_last_frame.clear()

	# 7. Update atmosphere & camera
	update_modular_dungeon_assets(new_lvl)

	# 8. Rebuild dungeon geometry immediately
	rebuild_dungeon_if_needed(true)

func rebuild_dungeon_if_needed(force: bool = false):
	if not diablo_bridge or not diablo_bridge.has_method("get_dungeon_solidity_grid"):
		return
	if not _bridge_read_gate_open():
		return

	if wall_mmi == null:
		setup_dungeon_multimeshes()
	if town_scenery_root == null:
		town_scenery_root = Node3D.new()
		town_scenery_root.name = "TownSceneryRoot"
		add_child(town_scenery_root)

	var cur_level = diablo_bridge.get_current_level() if diablo_bridge.has_method("get_current_level") else 1
	if cur_level != last_level_idx:
		_on_level_changed(cur_level)
		return

	var solidity: PackedByteArray = diablo_bridge.get_dungeon_solidity_grid()
	if solidity.size() < 112 * 112:
		return

	var h = hash(solidity)
	if not force and dungeon_built and h == last_solidity_hash:
		return

	last_solidity_hash = h
	last_solidity_grid = solidity
	dungeon_built = true

	# Clear previous scenery sprites & specials
	if town_scenery_root:
		for c in town_scenery_root.get_children():
			c.queue_free()
	town_scenery_nodes.clear()
	special_scenery_nodes.clear()
	translucent_scenery_indices.clear()

	# Clear previous stairs
	if stairs_root:
		for c in stairs_root.get_children():
			c.queue_free()
	stairs_nodes.clear()

	var grid = diablo_bridge.get_dungeon_grid() if diablo_bridge.has_method("get_dungeon_grid") else PackedInt32Array()
	var has_grid = (grid.size() >= 112 * 112)
	var special_grid = diablo_bridge.get_dungeon_special_grid() if diablo_bridge.has_method("get_dungeon_special_grid") else PackedInt32Array()

	var is_dungeon = (cur_level > 0)
	var is_cathedral = (cur_level >= 1 and cur_level <= 4)
	var basis_tile = Basis().rotated(Vector3.UP, deg_to_rad(-45.0))

	# Full 112x112 grid scan guarantees all perimeter rooms, corridors, and stairs are built
	var min_bound = 0
	var max_bound = 112

	# Query active doors so they are not blocked by wall scenery
	var active_objects: Array = diablo_bridge.get_active_objects() if diablo_bridge.has_method("get_active_objects") else []
	var door_tiles: Dictionary = {} # Vector2i -> Dictionary
	for obj in active_objects:
		var o_type = obj.get("type", -1)
		var otx = obj.get("tile_x", -1)
		var oty = obj.get("tile_y", -1)
		if otx >= 0 and oty >= 0:
			var pos_k = Vector2i(otx, oty)
			var cat = str(obj.get("category", ""))
			if cat == "DOOR" or (o_type in [1, 2, 42, 43, 74, 75, 83, 84]):
				door_tiles[pos_k] = obj

	var floor_piece_transforms: Dictionary = {} # piece_id (int) -> Array[Transform3D]
	var total_floor_count = 0
	var wall_block_transforms: Array[Transform3D] = []
	var wall_ns_transforms: Array[Transform3D] = []
	var wall_ew_transforms: Array[Transform3D] = []
	var pillar_transforms: Array[Transform3D] = []
	var arch_transforms: Array[Transform3D] = []
	var cur_theme = get_theme_name(cur_level)
	var can_3d_walls = is_dungeon and can_use_modular_3d_walls(cur_theme)

	for y in range(min_bound, max_bound):
		for x in range(min_bound, max_bound):
			var idx = y * 112 + x
			var val = solidity[idx]
			var pid = grid[idx] if has_grid else 1
			if pid < 0:
				pid = 1

			var is_stair_piece = false
			if is_cathedral and (pid in [105, 106, 107, 108, 109, 111, 113, 114, 117, 126, 128, 129, 130, 131, 132, 134, 136, 137, 138, 139]):
				is_stair_piece = true
			elif (cur_level >= 5 and cur_level <= 8 and (pid in [265, 266, 268, 269, 270, 271, 557, 558])):
				is_stair_piece = true
			elif (cur_level >= 9 and cur_level <= 12 and (pid in [161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182])):
				is_stair_piece = true
			elif (cur_level >= 13 and (pid in [81, 82, 89, 119, 129, 130, 131, 132, 420, 421, 428])):
				is_stair_piece = true

			if is_dungeon and val == 0 and not is_stair_piece:
				# Check if this non-walkable tile borders the dungeon space (margin 4 tiles eliminates void holes)
				var is_boundary = false
				for dy in range(-4, 5):
					for dx in range(-4, 5):
						var nx = x + dx
						var ny = y + dy
						if nx >= min_bound and nx < max_bound and ny >= min_bound and ny < max_bound:
							if solidity[ny * 112 + nx] != 0:
								is_boundary = true
								break
					if is_boundary:
						break
				if not is_boundary:
					continue

			var wpos = tile_to_world_3d(float(x), float(y))
			var tile_pos_i = Vector2i(x, y)
			var f_tf = Transform3D(Basis.IDENTITY, Vector3(wpos.x, 0.0, wpos.z))

			var tex: Texture2D = get_scenery_piece_texture(pid, cur_level)

			# Town fallback for border/void tiles to authentic grass (piece 218 / 0)
			if not is_dungeon and tex == null:
				var eff_pid = 218
				tex = get_scenery_piece_texture(eff_pid, cur_level)
				if tex == null:
					eff_pid = 0
					tex = get_scenery_piece_texture(eff_pid, cur_level)
				pid = eff_pid

			if tex == null:
				continue

			var tw = tex.get_width()
			var th = tex.get_height()
			var floor_h = int(round(float(tw) * 0.5))
			var is_wall_scenery = (th > floor_h)
			var is_door_tile = door_tiles.has(tile_pos_i)

			# Modular 3D Door Archway (Cathedral / Dungeons)
			if is_door_tile and can_3d_walls:
				var d_obj = door_tiles[tile_pos_i]
				var o_type = d_obj.get("type", 1)
				var is_l_door = (o_type in [1, 42, 74, 83])
				var arch_basis = basis_tile.rotated(Vector3.UP, deg_to_rad(-90.0)) if is_l_door else basis_tile
				arch_transforms.append(Transform3D(arch_basis, Vector3(wpos.x, 0.0, wpos.z)))

			# Extract the authentic base paver region from row 0 for the foundation floor diamond
			var has_solid_paver = not is_wall_scenery
			if is_wall_scenery:
				if base_floor_texture_cache.has(pid):
					has_solid_paver = true
				else:
					var img = tex.get_image()
					if img and not img.is_empty():
						var floor_rect = Rect2i(0, th - floor_h, tw, floor_h)
						var floor_img = img.get_region(floor_rect)
						if not _is_image_empty_or_transparent(floor_img):
							floor_img.generate_mipmaps()
							base_floor_texture_cache[pid] = ImageTexture.create_from_image(floor_img)
							has_solid_paver = true

			# 1. Floor diamond: ensure every active dungeon tile has a solid ground paver
			var eff_floor_pid = pid
			if not has_solid_paver:
				eff_floor_pid = get_theme_base_floor_piece_id(cur_level)
			if not floor_piece_transforms.has(eff_floor_pid):
				floor_piece_transforms[eff_floor_pid] = []
			floor_piece_transforms[eff_floor_pid].append(f_tf)
			total_floor_count += 1

			# 2. Wall & Scenery Geometry:
			# If modular 3D walls are enabled in Dungeon: generate true 3D modular meshes for solid walls
			if is_wall_scenery and (not can_3d_walls or not is_door_tile):
				if can_3d_walls and val == 2:
					var has_wall_nx = (x > 0 and (solidity[y * 112 + (x - 1)] == 2 or door_tiles.has(Vector2i(x - 1, y))))
					var has_wall_px = (x < 111 and (solidity[y * 112 + (x + 1)] == 2 or door_tiles.has(Vector2i(x + 1, y))))
					var has_wall_ny = (y > 0 and (solidity[(y - 1) * 112 + x] == 2 or door_tiles.has(Vector2i(x, y - 1))))
					var has_wall_py = (y < 111 and (solidity[(y + 1) * 112 + x] == 2 or door_tiles.has(Vector2i(x, y + 1))))

					var neighbor_x_count = (1 if has_wall_nx else 0) + (1 if has_wall_px else 0)
					var neighbor_y_count = (1 if has_wall_ny else 0) + (1 if has_wall_py else 0)
					var total_neighbors = neighbor_x_count + neighbor_y_count

					var w_tf = Transform3D(basis_tile, Vector3(wpos.x, 0.0, wpos.z))

					if total_neighbors == 0:
						pillar_transforms.append(w_tf)
					elif neighbor_x_count > 0 and neighbor_y_count == 0:
						wall_ns_transforms.append(w_tf)
					elif neighbor_y_count > 0 and neighbor_x_count == 0:
						wall_ew_transforms.append(w_tf)
					else:
						wall_block_transforms.append(w_tf)
				elif not can_3d_walls or cur_level == 0:
					# In dungeons, cull completely buried interior walls (all 4 cardinal neighbors solid wall)
					if cur_level > 0 and val == 2:
						var is_buried = (x > 0 and solidity[y * 112 + (x - 1)] == 2 and not door_tiles.has(Vector2i(x - 1, y))) and \
										(x < 111 and solidity[y * 112 + (x + 1)] == 2 and not door_tiles.has(Vector2i(x + 1, y))) and \
										(y > 0 and solidity[(y - 1) * 112 + x] == 2 and not door_tiles.has(Vector2i(x, y - 1))) and \
										(y < 111 and solidity[(y + 1) * 112 + x] == 2 and not door_tiles.has(Vector2i(x, y + 1)))
						if is_buried:
							continue

					# Town Buildings & Trees (Level 0), or authentic 4K PBR billboard scenery when modular 3D is disabled
					var spr = Sprite3D.new()
					spr.name = "Scenery_%d_%d" % [x, y]
					spr.texture = tex
					spr.centered = true
					spr.billboard = BaseMaterial3D.BILLBOARD_DISABLED
					spr.rotation.x = 0.0
					spr.rotation.y = deg_to_rad(camera_yaw)
					spr.shaded = false
					spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
					var sc_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if current_upscaler_mode == 4 else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
					spr.texture_filter = sc_filter
					var p_scale = 1.50 / float(tw)
					spr.pixel_size = p_scale
					spr.offset = Vector2(0.0, float(th) * 0.5)
					spr.position = Vector3(wpos.x, 0.01, wpos.z)
					spr.render_priority = 3
					spr.modulate = Color(1.48, 1.45, 1.38) if (cur_level == 0) else Color(1.48, 1.44, 1.36)
					town_scenery_root.add_child(spr)
					town_scenery_nodes[idx] = spr

			# 3. Special CEL Archways & Column Tops (Cathedral only per GEMINI.md Rule #2, only when modular 3D meshes are disabled)
			var special_id = special_grid[idx] if idx < special_grid.size() else 0
			if special_id > 0 and is_cathedral and (not can_3d_walls) and (solidity.size() < 112 * 112 or solidity[idx] != 0):
				var arch_tex = get_scenery_special_texture(special_id, cur_level)
				if arch_tex:
					var aspr = Sprite3D.new()
					aspr.name = "Special_%d_%d" % [x, y]
					aspr.texture = arch_tex
					aspr.centered = true
					aspr.billboard = BaseMaterial3D.BILLBOARD_DISABLED
					aspr.rotation.x = 0.0
					aspr.rotation.y = deg_to_rad(camera_yaw)
					aspr.shaded = false
					aspr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
					aspr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST if current_upscaler_mode == 4 else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
					aspr.pixel_size = 1.50 / float(arch_tex.get_width())
					aspr.offset = Vector2(0.0, float(arch_tex.get_height()) * 0.5)
					aspr.position = Vector3(wpos.x, 0.02, wpos.z + 0.005)
					aspr.sorting_offset = 1.0
					aspr.render_priority = 3
					aspr.modulate = Color(1.48, 1.44, 1.36)
					town_scenery_root.add_child(aspr)
					special_scenery_nodes[idx] = aspr

			# 4. Authentic 3D staircase model at primary entrance/exit stair locations
			if is_cathedral and (pid in [105, 126]) and stairs_root:
				var stair_node = MeshInstance3D.new()
				stair_node.name = "Stairs3D_%d_%d" % [x, y]
				stair_node.mesh = get_or_load_mesh("res://assets/models/dungeon/stairs_down_cathedral.glb")
				stair_node.material_override = get_pbr_material_for_theme("cathedral", true)
				var st_rot = basis_tile if pid == 126 else basis_tile.rotated(Vector3.UP, deg_to_rad(180.0))
				stair_node.transform = Transform3D(st_rot, Vector3(wpos.x, 0.0, wpos.z))
				stairs_root.add_child(stair_node)
				stairs_nodes[idx] = stair_node

	# Populate Multi-Piece Floor MultiMeshes (Both Town and Dungeons)
	var seen_pids: Dictionary = {}
	for f_pid in floor_piece_transforms.keys():
		seen_pids[f_pid] = true
		var tfs: Array = floor_piece_transforms[f_pid]
		var mmi: MultiMeshInstance3D = floor_mmis.get(f_pid, null)
		if mmi == null:
			mmi = MultiMeshInstance3D.new()
			mmi.name = "FloorMMI_%d" % f_pid
			var mm = MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = get_floor_diamond_mesh()
			mmi.multimesh = mm
			mmi.material_override = get_floor_material(f_pid, cur_level)
			floor_root.add_child(mmi)
			floor_mmis[f_pid] = mmi
		else:
			mmi.visible = true
			mmi.material_override = get_floor_material(f_pid, cur_level)

		_populate_multimesh(mmi.multimesh, tfs)

	for old_pid in floor_mmis.keys():
		if not seen_pids.has(old_pid):
			floor_mmis[old_pid].visible = false

	if floor_mmi:
		floor_mmi.visible = false

	# Modular 3D Kit MultiMeshes
	if is_dungeon and can_3d_walls:
		if wall_mmi and wall_mmi.multimesh:
			_populate_multimesh(wall_mmi.multimesh, wall_block_transforms)
			wall_mmi.visible = (wall_block_transforms.size() > 0)
		if wall_ns_mmi and wall_ns_mmi.multimesh:
			_populate_multimesh(wall_ns_mmi.multimesh, wall_ns_transforms)
			wall_ns_mmi.visible = (wall_ns_transforms.size() > 0)
		if wall_ew_mmi and wall_ew_mmi.multimesh:
			_populate_multimesh(wall_ew_mmi.multimesh, wall_ew_transforms)
			wall_ew_mmi.visible = (wall_ew_transforms.size() > 0)
		if pillar_mmi and pillar_mmi.multimesh:
			_populate_multimesh(pillar_mmi.multimesh, pillar_transforms)
			pillar_mmi.visible = (pillar_transforms.size() > 0)
		if arch_mmi and arch_mmi.multimesh:
			_populate_multimesh(arch_mmi.multimesh, arch_transforms)
			arch_mmi.visible = (arch_transforms.size() > 0)
	else:
		if wall_mmi and wall_mmi.multimesh:
			wall_mmi.multimesh.instance_count = 0
			wall_mmi.visible = false
		if wall_ns_mmi and wall_ns_mmi.multimesh:
			wall_ns_mmi.multimesh.instance_count = 0
			wall_ns_mmi.visible = false
		if wall_ew_mmi and wall_ew_mmi.multimesh:
			wall_ew_mmi.multimesh.instance_count = 0
			wall_ew_mmi.visible = false
		if pillar_mmi and pillar_mmi.multimesh:
			pillar_mmi.multimesh.instance_count = 0
			pillar_mmi.visible = false
		if arch_mmi and arch_mmi.multimesh:
			arch_mmi.multimesh.instance_count = 0
			arch_mmi.visible = false

	var total_modular_walls = wall_block_transforms.size() + wall_ns_transforms.size() + wall_ew_transforms.size() + pillar_transforms.size() + arch_transforms.size()
	print("[Native 3D Sandbox] Reconstructed 3D world (L%d): %d floors (%d unique pieces), %d scenery sprites, %d special archways, %d 3D modular walls (%d NS, %d EW, %d corners, %d pillars, %d arches)" % [
		cur_level, total_floor_count, floor_piece_transforms.size(),
		town_scenery_nodes.size(), special_scenery_nodes.size(),
		total_modular_walls,
		wall_ns_transforms.size(), wall_ew_transforms.size(), wall_block_transforms.size(), pillar_transforms.size(), arch_transforms.size()
	])

func _populate_multimesh(mm: MultiMesh, transforms: Array):
	if not mm:
		return
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])

# ==============================================================================
# 3D Entity Pipeline (Heroes & Monsters)
# ==============================================================================

func setup_player_entity():
	player_root = Node3D.new()
	player_root.name = "PlayerEntity"
	add_child(player_root)

	# Authentic Animated 3D Billboard Sprite (Unshaded with healthy illumination per GEMINI.md Rule #4)
	player_sprite = Sprite3D.new()
	player_sprite.name = "PlayerSprite3D"
	player_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	player_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	player_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	player_sprite.shaded = false
	player_sprite.pixel_size = PIXEL_SIZE_1X
	player_sprite.layers = 2
	player_sprite.render_priority = 3
	player_sprite.sorting_offset = 0.05
	player_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	player_root.add_child(player_sprite)

	# Golden Rune Ring at Feet
	player_ring = MeshInstance3D.new()
	var ring_torus = TorusMesh.new()
	ring_torus.inner_radius = 0.44
	ring_torus.outer_radius = 0.52
	ring_torus.rings = 16
	ring_torus.ring_segments = 8
	player_ring.mesh = ring_torus
	player_ring.position.y = 0.03
	var ring_mat = StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(1.0, 0.85, 0.4, 0.85)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	player_ring.material_override = ring_mat
	player_ring.visible = false
	player_root.add_child(player_ring)

	# Dynamic Warm Lantern Light
	player_lantern = OmniLight3D.new()
	player_lantern.name = "HeroLantern"
	player_lantern.position = Vector3(0, 1.45, 0)
	player_lantern.light_color = Color(1.0, 0.74, 0.42)
	player_lantern.light_energy = 1.80
	player_lantern.omni_range = 14.0
	player_lantern.omni_attenuation = 1.25
	player_lantern.shadow_enabled = true
	player_lantern.light_cull_mask = 1
	player_lantern.shadow_bias = 0.06
	player_lantern.shadow_normal_bias = 1.2
	player_lantern.shadow_blur = 1.5
	player_lantern.omni_shadow_mode = OmniLight3D.SHADOW_CUBE
	player_root.add_child(player_lantern)

	# Direction Indicator Arrow (disabled by default for clean gothic immersion)
	player_arrow = MeshInstance3D.new()
	var arrow_mesh = PrismMesh.new()
	arrow_mesh.size = Vector3(0.24, 0.35, 0.06)
	player_arrow.mesh = arrow_mesh
	player_arrow.rotation_degrees = Vector3(-90, 0, 0)
	player_arrow.position = Vector3(0, 0.04, 0.70)
	var arrow_mat = StandardMaterial3D.new()
	arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow_mat.albedo_color = Color(1.0, 0.8, 0.2, 0.7)
	arrow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	player_arrow.material_override = arrow_mat
	player_arrow.visible = false
	player_root.add_child(player_arrow)

	# AAA Hero 3D Controller
	setup_hero_controller_for_class(0)

func setup_hero_controller_for_class(p_class: int):
	if current_player_class == p_class and hero_controller != null and is_instance_valid(hero_controller):
		return
	current_player_class = p_class
	if hero_controller and is_instance_valid(hero_controller):
		hero_controller.queue_free()
		hero_controller = null

	var script_path = "res://scripts/entities/warrior_3d_controller.gd"
	if p_class == 1:
		script_path = "res://scripts/entities/rogue_3d_controller.gd"
	elif p_class == 2:
		script_path = "res://scripts/entities/sorcerer_3d_controller.gd"

	var hero_script = load(script_path)
	if hero_script:
		hero_controller = hero_script.new()
		hero_controller.name = "Hero3DController"
		hero_controller.visible = false
		player_root.add_child(hero_controller)
		warrior_controller = hero_controller

func update_player_entity(delta: float):
	if not diablo_bridge or not diablo_bridge.has_method("get_player_continuous_pos"):
		return
	var p_data = diablo_bridge.get_player_continuous_pos()
	if not p_data or p_data.is_empty() or not p_data.has("pos_x"):
		return
	var px = float(p_data.get("pos_x", 0.0))
	var py = float(p_data.get("pos_y", 0.0))
	var dir = p_data.get("dir", 0)
	var anim_frame = p_data.get("anim_frame", -1)

	var p_class = diablo_bridge.get_player_class() if diablo_bridge and diablo_bridge.has_method("get_player_class") else 0
	setup_hero_controller_for_class(p_class)

	player_target_pos = tile_to_world_3d(px, py)
	var p_dist = player_root.position.distance_to(player_target_pos)
	if delta <= 0.0 or player_root.position == Vector3.ZERO or p_dist > 4.0:
		player_root.position = player_target_pos
	else:
		player_root.position = player_root.position.lerp(player_target_pos, delta * 14.0)

	player_arrow.rotation_degrees.y = float(dir) * 45.0

	# 3D Hero Quality-Gated Sync
	if hero_controller:
		var p_action = str(p_data.get("action", "IDLE"))
		hero_controller.set_direction(dir)
		hero_controller.set_action(p_action)
		var is_moving = (player_root.position.distance_to(player_target_pos) > 0.05)
		hero_controller.update_animation(delta, Vector3.ZERO, is_moving)

		var cert_path = "res://assets/models/aaa/characters/warrior_gothic.res"
		if p_class == 1: cert_path = "res://assets/models/aaa/characters/rogue_gothic.res"
		elif p_class == 2: cert_path = "res://assets/models/aaa/characters/sorcerer_gothic.res"

		var use_3d = warrior_3d_enabled and is_mesh_aaa_certified(cert_path)
		hero_controller.visible = use_3d
		player_sprite.visible = not use_3d

	# HD hero frames first (assets/hd_sprites*/player/<class>_<action>); the 1x
	# bridge raster stays as the fallback for class/action pairs never upscaled.
	var hd_hero_tex: Texture2D = null
	if hd_graphics_enabled:
		# LoadPlrGFX records the exact armor/weapon CEL set the hero renders with
		# ("plrgfx\monk\mlt\mltbl" -> "mlt"); HD sets are keyed by it.
		var gfx_prefix := ""
		if diablo_bridge and diablo_bridge.has_method("get_player_cel_path"):
			var cel_parts = str(diablo_bridge.get_player_cel_path()).replace("/", "\\").split("\\")
			if cel_parts.size() >= 3:
				gfx_prefix = str(cel_parts[2]).to_lower()
		hd_hero_tex = HdSpriteProvider.get_player_sprite(p_class,
			str(p_data.get("action", "STAND")), dir, anim_frame, current_tile_model, gfx_prefix)

	if hd_hero_tex != null:
		if player_sprite.texture != hd_hero_tex:
			player_sprite.texture = hd_hero_tex
			player_sprite.offset = Vector2(0, float(hd_hero_tex.get_height()) * 0.5)
			player_sprite.pixel_size = PIXEL_SIZE_HD
			apply_entity_hd_material(player_sprite, hd_hero_tex)
	elif diablo_bridge and diablo_bridge.has_method("get_player_sprite_data"):
		if anim_frame != last_player_frame or dir != last_player_dir or player_texture == null:
			last_player_frame = anim_frame
			last_player_dir = dir
			var s_data: Dictionary = diablo_bridge.get_player_sprite_data()
			var sw = s_data.get("width", 0)
			var sh = s_data.get("height", 0)
			var rgba: PackedByteArray = s_data.get("rgba", PackedByteArray())
			if sw > 0 and sh > 0 and rgba.size() == sw * sh * 4:
				var img = Image.create_from_data(sw, sh, false, Image.FORMAT_RGBA8, rgba)
				img.generate_mipmaps()
				if player_texture == null or player_texture.get_width() != sw or player_texture.get_height() != sh:
					player_texture = ImageTexture.create_from_image(img)
					player_sprite.texture = player_texture
				else:
					player_texture.update(img)
				player_sprite.pixel_size = PIXEL_SIZE_HD if sw >= 200 else PIXEL_SIZE_1X
				player_sprite.offset = Vector2(0, float(sh) * 0.5)
				apply_entity_hd_material(player_sprite, player_texture)

	if player_sprite and player_texture and player_sprite.material_override == null:
		apply_entity_hd_material(player_sprite, player_texture)

	# Healthy illumination modulation (Rule #4 in GEMINI.md)
	var cur_lvl = diablo_bridge.get_current_level() if diablo_bridge.has_method("get_current_level") else 1
	if cur_lvl == 0:
		player_sprite.modulate = Color(1.50, 1.46, 1.38) # Town daylight
	else:
		player_sprite.modulate = Color(1.48, 1.44, 1.36) # Dungeon torchlit ambient

	# Lantern flicker
	if player_lantern and cur_lvl > 0:
		var flicker = 1.70 + 0.16 * sin(time_accum * 7.5) * cos(time_accum * 4.2)
		player_lantern.light_energy = flicker

	# Rune Ring rotation
	if player_ring:
		player_ring.rotation_degrees.y += delta * 30.0

func update_monster_entities(delta: float):
	if not diablo_bridge or not diablo_bridge.has_method("get_active_monsters_data"):
		return

	var monsters: Array = diablo_bridge.get_active_monsters_data()
	var seen_ids: Dictionary = {}

	for m in monsters:
		var m_id = m.get("id", -1)
		var is_alive = m.get("is_alive", true)
		if m_id < 0 or not is_alive:
			continue

		seen_ids[m_id] = true
		var mx = m.get("pos_x", 0.0)
		var my = m.get("pos_y", 0.0)
		var dir = m.get("dir", 0)
		var anim_frame = m.get("anim_frame", -1)
		var hp = m.get("hp", 1)
		var max_hp = max(1, m.get("max_hp", 1))
		var m_name = m.get("name", "Monster")
		var node = get_or_create_monster_node(m_id, m_name)
		node.visible = true

		var target_pos = tile_to_world_3d(mx, my)
		node.set_meta("tile_x", int(round(mx)))
		node.set_meta("tile_y", int(round(my)))
		node.set_meta("name", m_name)
		node.set_meta("hp", hp)
		node.set_meta("max_hp", max_hp)
		if delta <= 0.0 or node.position == Vector3.ZERO:
			node.position = target_pos
		else:
			node.position = node.position.lerp(target_pos, delta * 12.0)

		# Update Monster Sprite3D
		var m_sprite = node.get_node_or_null("MonsterSprite3D") as Sprite3D

		# 3D Monster Controller Quality-Gated Sync
		var m_ctrl = node.get_node_or_null("Monster3DController")
		var m_action = str(m.get("action", "IDLE"))
		if hp <= 0:
			m_action = "DEATH"
		if m_ctrl:
			m_ctrl.set_direction(dir)
			m_ctrl.set_action(m_action)
			var is_moving = (delta > 0.0 and node.position.distance_to(target_pos) > 0.02)
			m_ctrl.update_animation(delta, is_moving)

			var use_3d = monsters_3d_enabled and is_mesh_aaa_certified("res://assets/models/aaa/monsters/skeleton_gothic.res")
			m_ctrl.visible = use_3d
			if m_sprite:
				m_sprite.visible = not use_3d
		var last_f = monster_last_frame.get(m_id, -999)
		var last_d = monster_last_dir.get(m_id, -999)
		var cur_tex: Texture2D = monster_textures.get(m_id, null)

		if diablo_bridge and diablo_bridge.has_method("get_monster_sprite_data"):
			if anim_frame != last_f or dir != last_d or cur_tex == null:
				monster_last_frame[m_id] = anim_frame
				monster_last_dir[m_id] = dir
				var m_mode = int(m.get("mode", 0))
				var m_type = int(m.get("type", -1))
				var anim_cache_key = "%s_%d_%d_%d_%d" % [m_name, m_mode, dir, anim_frame, m_type]
				if monster_anim_cache.has(anim_cache_key):
					cur_tex = monster_anim_cache[anim_cache_key]
				else:
					# 1. Offline-upscaled HD frame (assets/hd_sprites*/monsters/<family>_<action>/)
					var hd_m_tex = HdSpriteProvider.get_monster_sprite(m_name, m_mode, dir, anim_frame, current_tile_model) if hd_graphics_enabled else null
					if hd_m_tex != null:
						cur_tex = hd_m_tex
						monster_anim_cache[anim_cache_key] = cur_tex
					else:
						# 2. Fallback: authentic 1x bridge rasterization
						var ms_data: Dictionary = diablo_bridge.get_monster_sprite_data(m_id)
						var mw = ms_data.get("width", 0)
						var mh = ms_data.get("height", 0)
						var m_rgba: PackedByteArray = ms_data.get("rgba", PackedByteArray())
						if mw > 0 and mh > 0 and m_rgba.size() == mw * mh * 4:
							var m_img = Image.create_from_data(mw, mh, false, Image.FORMAT_RGBA8, m_rgba)
							m_img.generate_mipmaps()
							cur_tex = ImageTexture.create_from_image(m_img)
							monster_anim_cache[anim_cache_key] = cur_tex
						else:
							monster_anim_cache[anim_cache_key] = null

				monster_textures[m_id] = cur_tex
				if m_sprite and cur_tex:
					m_sprite.texture = cur_tex
					m_sprite.pixel_size = PIXEL_SIZE_HD if cur_tex.get_width() >= 200 else PIXEL_SIZE_1X
					m_sprite.offset = Vector2(0, float(cur_tex.get_height()) * 0.5)
					apply_entity_hd_material(m_sprite, cur_tex)

		if m_sprite and cur_tex and m_sprite.material_override == null:
			apply_entity_hd_material(m_sprite, cur_tex)

		var cur_lvl = diablo_bridge.get_current_level() if diablo_bridge.has_method("get_current_level") else 1
		var is_town = (cur_lvl == 0)
		var is_active_alive = (not is_town) and (hp > 0)

		# Dynamic HP bar & name label height (computed every frame above monster head)
		var m_scale = m_sprite.pixel_size if m_sprite else PIXEL_SIZE_1X
		var spr_h = cur_tex.get_height() if cur_tex else 96
		var head_y = float(spr_h) * m_scale + 0.22

		# Update HP Bar (Dungeon monsters only; hide on friendly Town NPCs or dead corpses)
		var hp_r = node.get_node_or_null("HPRoot")
		if hp_r:
			hp_r.position.y = head_y
			hp_r.visible = is_active_alive
		var hp_bar = node.get_node_or_null("HPRoot/HPBar") as MeshInstance3D
		if hp_bar and is_active_alive:
			var ratio = clamp(float(hp) / float(max_hp), 0.0, 1.0)
			if hp_bar.mesh is QuadMesh:
				(hp_bar.mesh as QuadMesh).size.x = 0.80 * ratio
			hp_bar.position.x = -0.40 * (1.0 - ratio)
			var fg_mat = hp_bar.material_override as StandardMaterial3D
			if fg_mat:
				if ratio > 0.5:
					fg_mat.albedo_color = Color(0.22, 0.88, 0.28).lerp(Color(0.96, 0.76, 0.14), (1.0 - ratio) * 2.0)
				else:
					fg_mat.albedo_color = Color(0.96, 0.76, 0.14).lerp(Color(0.92, 0.12, 0.12), (0.5 - ratio) * 2.0)

		# Update Name Label (Dungeon monsters only; hide on friendly Town NPCs or dead corpses)
		var label = node.get_node_or_null("NameLabel") as Label3D
		if label:
			label.position.y = head_y + 0.24
			label.visible = is_active_alive
			if is_active_alive:
				label.text = "%s [%d/%d]" % [m_name, hp, max_hp]

	# Prune inactive / despawned monsters cleanly
	var dead_ids = []
	for id in monster_instances.keys():
		if not seen_ids.has(id):
			monster_instances[id].visible = false
			monster_unseen_frames[id] = monster_unseen_frames.get(id, 0) + 1
			if monster_unseen_frames[id] > 90:
				dead_ids.append(id)
		else:
			monster_unseen_frames[id] = 0

	for d_id in dead_ids:
		if monster_instances.has(d_id):
			var n = monster_instances[d_id]
			if is_instance_valid(n):
				n.queue_free()
			monster_instances.erase(d_id)
		monster_textures.erase(d_id)
		monster_last_frame.erase(d_id)
		monster_last_dir.erase(d_id)
		monster_unseen_frames.erase(d_id)

func get_or_create_monster_node(m_id: int, m_name: String = "") -> Node3D:
	if monster_instances.has(m_id):
		return monster_instances[m_id]

	var node = Node3D.new()
	node.name = "Monster_%d" % m_id
	node.set_meta("monster_id", m_id)

	# 3D Billboard Sprite (Unshaded with healthy illumination & ground contact shadow)
	var sprite = Sprite3D.new()
	sprite.name = "MonsterSprite3D"
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.shaded = false
	sprite.pixel_size = PIXEL_SIZE_1X
	sprite.render_priority = 3
	sprite.sorting_offset = 0.05
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	sprite.modulate = Color(1.38, 1.35, 1.28)
	node.add_child(sprite)

	# AAA Monster 3D Controller (Boss-specific controller vs standard monster controller)
	var is_butcher = ("Butcher" in m_name) or ("Hentes" in m_name)
	var is_leoric = ("Skeleton King" in m_name) or ("Leoric" in m_name) or ("Csontváz Király" in m_name)
	var is_lazarus = ("Lazarus" in m_name) or ("Archbishop" in m_name) or ("Érsek" in m_name)
	var is_diablo = ("Diablo" in m_name) or ("Lord of Terror" in m_name)

	var monster_script = null
	if is_butcher:
		monster_script = load("res://scripts/entities/butcher_3d_controller.gd")
	elif is_leoric:
		monster_script = load("res://scripts/entities/leoric_3d_controller.gd")
	elif is_lazarus:
		monster_script = load("res://scripts/entities/lazarus_3d_controller.gd")
	elif is_diablo:
		monster_script = load("res://scripts/entities/diablo_3d_controller.gd")
	else:
		monster_script = load("res://scripts/entities/monster_3d_controller.gd")

	if monster_script:
		var mc = monster_script.new()
		mc.name = "Monster3DController"
		mc.monster_id = m_id
		mc.visible = false
		if is_butcher and mc.has_signal("cleaver_impact"):
			mc.cleaver_impact.connect(func(pos):
				camera_trauma = minf(camera_trauma + 0.40, 1.0)
			)
		elif is_leoric:
			if mc.has_signal("sword_impact"):
				mc.sword_impact.connect(func(pos):
					camera_trauma = minf(camera_trauma + 0.28, 1.0)
				)
			if mc.has_signal("resurrection_pulse"):
				mc.resurrection_pulse.connect(func(pos):
					camera_trauma = minf(camera_trauma + 0.15, 1.0)
				)
		elif is_lazarus and mc.has_signal("hellfire_cast"):
			mc.hellfire_cast.connect(func(pos):
				camera_trauma = minf(camera_trauma + 0.20, 1.0)
			)
		elif is_diablo:
			if mc.has_signal("apocalypse_strike"):
				mc.apocalypse_strike.connect(func(pos):
					camera_trauma = minf(camera_trauma + 0.50, 1.0)
				)
			if mc.has_signal("heavy_step"):
				mc.heavy_step.connect(func(pos):
					camera_trauma = minf(camera_trauma + 0.12, 1.0)
				)
		node.add_child(mc)

	# Floating 3D Name Label (Authentic Exocet font, crisp readable sizing and render priority)
	var label = Label3D.new()
	label.name = "NameLabel"
	label.position = Vector3(0, 1.85, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font = FONT_EXOCET
	label.font_size = 20
	label.pixel_size = 0.0075
	label.modulate = Color(1.0, 0.92, 0.65)
	label.outline_render_priority = 26
	label.outline_size = 3
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.98)
	label.render_priority = 27
	node.add_child(label)

	# Floating 3D HP Bar
	var hp_root = Node3D.new()
	hp_root.name = "HPRoot"
	hp_root.position = Vector3(0, 1.60, 0)

	# 1. Outer Frame / Border Quad
	var hp_border = MeshInstance3D.new()
	hp_border.name = "HPBorder"
	var q_border = QuadMesh.new()
	q_border.size = Vector2(0.92, 0.16)
	hp_border.mesh = q_border
	var border_mat = StandardMaterial3D.new()
	border_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	border_mat.albedo_color = Color(0.02, 0.02, 0.02, 0.96)
	border_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	border_mat.no_depth_test = true
	border_mat.render_priority = 20
	hp_border.material_override = border_mat
	hp_root.add_child(hp_border)

	# 2. Dark Slate Background Quad
	var hp_bg = MeshInstance3D.new()
	hp_bg.name = "HPBg"
	var q_bg = QuadMesh.new()
	q_bg.size = Vector2(0.86, 0.12)
	hp_bg.mesh = q_bg
	var bg_mat = StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.albedo_color = Color(0.08, 0.08, 0.10, 0.92)
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg_mat.no_depth_test = true
	bg_mat.render_priority = 21
	hp_bg.material_override = bg_mat
	hp_root.add_child(hp_bg)

	# 3. Dynamic Health Foreground Quad (pinned left, drains to right)
	var hp_fg = MeshInstance3D.new()
	var q_fg = QuadMesh.new()
	q_fg.size = Vector2(0.80, 0.08)
	hp_fg.mesh = q_fg
	hp_fg.name = "HPBar"
	hp_fg.position = Vector3(0.0, 0.0, 0.005)
	var fg_mat = StandardMaterial3D.new()
	fg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fg_mat.albedo_color = Color(0.88, 0.14, 0.14, 0.98)
	fg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fg_mat.no_depth_test = true
	fg_mat.render_priority = 22
	hp_fg.material_override = fg_mat
	hp_root.add_child(hp_fg)

	node.add_child(hp_root)
	monsters_root.add_child(node)
	monster_instances[m_id] = node
	return node

# ==============================================================================
# Interactive 3D Props & Objects Pipeline
# ==============================================================================

func update_props(delta: float):
	if not diablo_bridge or not diablo_bridge.has_method("get_active_objects"):
		return
	if props_root == null:
		setup_scene_nodes()

	var objects: Array = diablo_bridge.get_active_objects()
	var seen_ids: Dictionary = {}

	var cur_lvl = diablo_bridge.get_current_level() if diablo_bridge.has_method("get_current_level") else 1
	var flags_grid: PackedByteArray = diablo_bridge.get_dungeon_flags_grid() if diablo_bridge.has_method("get_dungeon_flags_grid") else PackedByteArray()
	var light_grid: PackedByteArray = diablo_bridge.get_dungeon_light_grid() if diablo_bridge.has_method("get_dungeon_light_grid") else PackedByteArray()
	var has_flags = (flags_grid.size() >= 112 * 112)
	var has_light = (light_grid.size() >= 112 * 112)

	for obj in objects:
		var o_id = obj.get("id", -1)
		if o_id < 0:
			continue
		seen_ids[o_id] = true

		var o_type = obj.get("type", 0)
		var tx = obj.get("tile_x", 0)
		var ty = obj.get("tile_y", 0)
		var anim_frame = obj.get("anim_frame", 1)
		var category = str(obj.get("category", ""))
		var graphic = str(obj.get("graphic", ""))

		var prop = get_or_create_prop_node(o_id, o_type, tx, ty, category, graphic)
		var wpos = tile_to_world_3d(float(tx), float(ty))
		prop.position = wpos
		prop.set_meta("tile_x", tx)
		prop.set_meta("tile_y", ty)

		# Visibility / Fog-of-war gating for dungeon props
		var is_prop_visible = true
		if cur_lvl > 0 and has_flags:
			var t_idx = clamp(ty, 0, 111) * 112 + clamp(tx, 0, 111)
			var fl = flags_grid[t_idx]
			var is_visible = (fl & 2) != 0       # DungeonFlag::Visible
			var is_explored = (fl & 128) != 0    # DungeonFlag::Explored

			# Check neighbor tiles for wall-mounted objects (doors, torches, wall fixtures)
			if not is_visible and not is_explored:
				for noff in [-1, 1, -112, 112]:
					var n_idx = t_idx + noff
					if n_idx >= 0 and n_idx < 112 * 112:
						var n_fl = flags_grid[n_idx]
						if (n_fl & 2) != 0:
							is_visible = true
							break
						if (n_fl & 128) != 0:
							is_explored = true

			# Props require either active line-of-sight OR previous exploration
			is_prop_visible = is_visible or is_explored

		prop.visible = is_prop_visible
		if not is_prop_visible:
			continue

		# Update object animations & interactive states
		var is_open = bool(obj.get("is_open", false)) or bool(obj.get("pre_flag", false)) or (anim_frame > 1) or (not bool(obj.get("solid", true)))
		var is_door = (category == "DOOR") or (o_type in [1, 2, 42, 43, 74, 75, 83, 84])
		var is_chest = (category == "CHEST") or (o_type in [5, 6, 7, 68, 69, 70])
		var is_sarc = (category == "SARCOPHAGUS") or (o_type in [48, 96])
		var is_fire = (category == "TORCH") or (o_type in [0, 3, 8, 9, 10, 44, 45, 46, 47, 49, 85, 95, 150, 151])

		if is_chest:
			var lid = prop.get_node_or_null("ChestLid")
			if lid == null:
				lid = prop.get_node_or_null("ChestProp/ChestLid")
			if lid:
				var target_rot = -70.0 if anim_frame > 1 else 0.0
				lid.rotation_degrees.x = lerp(lid.rotation_degrees.x, target_rot, delta * 8.0)
		elif is_sarc:
			var s_lid = prop.get_node_or_null("SarcLid")
			if s_lid:
				var target_offset = Vector3(0.4, 0.0, 0.0) if anim_frame > 1 else Vector3.ZERO
				s_lid.position = s_lid.position.lerp(target_offset, delta * 6.0)
		elif is_door:
			var door_pivot = prop.get_node_or_null("DoorContainer/DoorPivot")
			if door_pivot:
				var target_rot = 85.0 if is_open else 0.0
				door_pivot.rotation_degrees.y = lerp(door_pivot.rotation_degrees.y, target_rot, delta * 12.0)
		# Light flickering for fire props (wall torches, standing braziers)
		if is_fire:
			var light = prop.get_node_or_null("TorchLight") as OmniLight3D
			if light == null:
				light = prop.get_node_or_null("WallTorch/TorchLight") as OmniLight3D
			if light:
				var flicker = 1.45 + 0.18 * sin(time_accum * 8.0 + float(o_id)) * cos(time_accum * 4.5)
				light.light_energy = flicker

		# Update billboard sprite animations for any prop using ObjectSprite3D
		var obj_spr = prop.get_node_or_null("ObjectSprite3D") as Sprite3D
		if obj_spr:
			var last_f = prop_last_frame.get(o_id, -999)
			if anim_frame != last_f or obj_spr.texture == null:
				prop_last_frame[o_id] = anim_frame
				# 1. Offline-upscaled HD frame (assets/hd_sprites*/objects/<graphic>/)
				var hd_graphic = str(prop.get_meta("hd_graphic", "")) if prop.has_meta("hd_graphic") else ""
				var hd_o_tex = HdSpriteProvider.get_object_sprite(hd_graphic, anim_frame, current_tile_model) if (hd_graphics_enabled and hd_graphic != "") else null
				if hd_o_tex != null:
					obj_spr.texture = hd_o_tex
					obj_spr.offset = Vector2(0, float(hd_o_tex.get_height()) * 0.5)
					obj_spr.sorting_offset = 0.05
					obj_spr.pixel_size = PIXEL_SIZE_HD
					apply_entity_hd_material(obj_spr, obj_spr.texture)
				elif diablo_bridge and diablo_bridge.has_method("get_object_sprite_data"):
					var s_data = diablo_bridge.get_object_sprite_data(o_id)
					var sw = s_data.get("width", 0)
					var sh = s_data.get("height", 0)
					var rgba = s_data.get("rgba", PackedByteArray())
					if sw > 0 and sh > 0 and rgba.size() == sw * sh * 4:
						var img = Image.create_from_data(sw, sh, false, Image.FORMAT_RGBA8, rgba)
						img.generate_mipmaps()
						if obj_spr.texture == null or obj_spr.texture.get_width() != sw or obj_spr.texture.get_height() != sh:
							obj_spr.texture = ImageTexture.create_from_image(img)
						else:
							obj_spr.texture.update(img)
						obj_spr.offset = Vector2(0, float(sh) * 0.5)
						obj_spr.sorting_offset = 0.05
						if sw >= 200:
							obj_spr.pixel_size = PIXEL_SIZE_HD
						else:
							obj_spr.pixel_size = PIXEL_SIZE_1X
						apply_entity_hd_material(obj_spr, obj_spr.texture)

			if obj_spr.texture and obj_spr.material_override == null:
				apply_entity_hd_material(obj_spr, obj_spr.texture)

	# Clean up inactive props
	for id in prop_instances.keys():
		if not seen_ids.has(id):
			prop_instances[id].visible = false

func get_or_create_prop_node(o_id: int, o_type: int, tx: int, ty: int, category: String = "", graphic: String = "") -> Node3D:
	if prop_instances.has(o_id):
		return prop_instances[o_id]

	var node = Node3D.new()
	node.name = "Prop_%d" % o_id
	var wpos = tile_to_world_3d(float(tx), float(ty))
	node.position = wpos
	node.set_meta("prop_id", o_id)
	node.set_meta("prop_type", o_type)
	node.set_meta("hd_graphic", graphic)
	node.set_meta("tile_x", tx)
	node.set_meta("tile_y", ty)

	var is_door = (category == "DOOR") or (o_type in [1, 2, 42, 43, 74, 75, 83, 84])
	var is_wall_torch = (o_type in [44, 45, 46, 47, 150, 151])
	var is_standing_fire = (o_type in [0, 3, 8, 9, 10, 49, 85, 95])
	var is_chest = (category == "CHEST") or (o_type in [5, 6, 7, 68, 69, 70])
	var is_sarc = (category == "SARCOPHAGUS") or (o_type in [48, 96])
	var is_barrel = (category == "BARREL") or (o_type in [57, 58])
	var is_shrine = (category == "SHRINE") or (o_type in [59, 60, 88, 89])
	node.set_meta("is_door", is_door)

	if is_door:
		if can_use_modular_3d_prop("door"):
			var basis_tile = Basis().rotated(Vector3.UP, deg_to_rad(-45.0))
			var is_l_door = (o_type in [1, 42, 74, 83])
			var d_basis = basis_tile.rotated(Vector3.UP, deg_to_rad(-90.0)) if is_l_door else basis_tile

			var door_container = Node3D.new()
			door_container.name = "DoorContainer"
			door_container.basis = d_basis

			var door_pivot = Node3D.new()
			door_pivot.name = "DoorPivot"
			door_pivot.position = Vector3(-0.45, 0.0, 0.0)

			var door_leaf = MeshInstance3D.new()
			door_leaf.name = "DoorLeaf"
			door_leaf.mesh = get_or_load_mesh("res://assets/models/dungeon/door_leaf.glb")
			if door_leaf.mesh == null:
				var box = BoxMesh.new()
				box.size = Vector3(0.9, 2.0, 0.1)
				door_leaf.mesh = box
			var d_mat = get_pbr_material_for_theme(get_theme_name(last_level_idx), true)
			if d_mat:
				door_leaf.material_override = d_mat
			door_leaf.position = Vector3(0.45, 1.0, 0.0)

			door_pivot.add_child(door_leaf)
			door_container.add_child(door_pivot)
			node.add_child(door_container)

	elif is_wall_torch:
		var basis_tile = Basis().rotated(Vector3.UP, deg_to_rad(-45.0))
		var is_l_torch = (o_type in [44, 46])
		var rot: Basis
		var offset: Vector3
		var wall_step = 1.06066
		var wall_h_thick = 0.52

		# Check whether the torch is on the wall tile itself, or placed on an adjacent floor tile:
		var is_wall_tile = false
		if last_solidity_grid.size() >= 112 * 112:
			is_wall_tile = (last_solidity_grid[ty * 112 + tx] == 2)

		if is_wall_tile:
			var open_px = (tx < 111 and last_solidity_grid.size() >= 112 * 112 and last_solidity_grid[ty * 112 + (tx + 1)] != 2)
			var open_py = (ty < 111 and last_solidity_grid.size() >= 112 * 112 and last_solidity_grid[(ty + 1) * 112 + tx] != 2)
			var open_nx = (tx > 0 and last_solidity_grid.size() >= 112 * 112 and last_solidity_grid[ty * 112 + (tx - 1)] != 2)
			var open_ny = (ty > 0 and last_solidity_grid.size() >= 112 * 112 and last_solidity_grid[(ty - 1) * 112 + tx] != 2)

			if open_py or (!is_l_torch and not open_px):
				rot = basis_tile
				offset = basis_tile * Vector3(0.0, 1.35, wall_h_thick)
			elif open_px or is_l_torch:
				rot = basis_tile.rotated(Vector3.UP, deg_to_rad(90.0))
				offset = basis_tile * Vector3(wall_h_thick, 1.35, 0.0)
			elif open_ny:
				rot = basis_tile.rotated(Vector3.UP, deg_to_rad(180.0))
				offset = basis_tile * Vector3(0.0, 1.35, -wall_h_thick)
			else:
				rot = basis_tile.rotated(Vector3.UP, deg_to_rad(-90.0))
				offset = basis_tile * Vector3(-wall_h_thick, 1.35, 0.0)
		else:
			# Placed on adjacent floor tile: find which neighbor tile contains the wall
			if is_l_torch:
				if tx < 111 and last_solidity_grid.size() >= 112 * 112 and last_solidity_grid[ty * 112 + (tx + 1)] == 2:
					rot = basis_tile.rotated(Vector3.UP, deg_to_rad(-90.0))
					offset = basis_tile * Vector3(wall_step - wall_h_thick, 1.35, 0.0)
				elif tx > 0 and last_solidity_grid.size() >= 112 * 112 and last_solidity_grid[ty * 112 + (tx - 1)] == 2:
					rot = basis_tile.rotated(Vector3.UP, deg_to_rad(90.0))
					offset = basis_tile * Vector3(-wall_step + wall_h_thick, 1.35, 0.0)
				else:
					rot = basis_tile.rotated(Vector3.UP, deg_to_rad(90.0))
					offset = basis_tile * Vector3(wall_h_thick, 1.35, 0.0)
			else:
				if ty < 111 and last_solidity_grid.size() >= 112 * 112 and last_solidity_grid[(ty + 1) * 112 + tx] == 2:
					rot = basis_tile.rotated(Vector3.UP, deg_to_rad(180.0))
					offset = basis_tile * Vector3(0.0, 1.35, wall_step - wall_h_thick)
				elif ty > 0 and last_solidity_grid.size() >= 112 * 112 and last_solidity_grid[(ty - 1) * 112 + tx] == 2:
					rot = basis_tile
					offset = basis_tile * Vector3(0.0, 1.35, -wall_step + wall_h_thick)
				else:
					rot = basis_tile
					offset = basis_tile * Vector3(0.0, 1.35, wall_h_thick)

		var torch_tf = Transform3D(rot, offset)
		var torch_node = Node3D.new()
		torch_node.name = "WallTorch"
		torch_node.transform = torch_tf

		if can_use_modular_3d_prop("wall_torch"):
			var sconce_mesh = MeshInstance3D.new()
			sconce_mesh.mesh = get_or_load_mesh("res://assets/models/props/torch_sconce.glb")
			sconce_mesh.material_override = get_pbr_material_for_theme(get_theme_name(last_level_idx), true)
			torch_node.add_child(sconce_mesh)

		var light = OmniLight3D.new()
		light.name = "TorchLight"
		light.position = Vector3(0, 0.28, 0.24)
		light.light_color = Color(1.0, 0.72, 0.38)
		light.light_energy = 1.75
		light.omni_range = 9.5
		light.omni_attenuation = 1.20
		light.shadow_enabled = true
		light.shadow_bias = 0.15
		light.shadow_normal_bias = 1.5
		torch_node.add_child(light)

		var embers = create_ember_particles()
		embers.position = Vector3(0, 0.28, 0.24)
		torch_node.add_child(embers)

		node.add_child(torch_node)

	elif is_standing_fire:
		if can_use_modular_3d_prop("standing_brazier"):
			# Standing brazier / fire basin resting on the floor
			var mesh_inst = MeshInstance3D.new()
			mesh_inst.mesh = get_or_load_mesh("res://assets/models/aaa/props/standing_brazier_gothic.res")
			node.add_child(mesh_inst)
		else:
			_attach_universal_object_sprite(node, o_id)

		# Standing brazier / fire basin on pillar (2.25m height) or floor (0.45m)
		var fire_y = 2.25 if o_type == 0 else 0.45
		var ember_y = 2.18 if o_type == 0 else 0.35

		var light = OmniLight3D.new()
		light.name = "TorchLight"
		light.position = Vector3(0, fire_y, 0)
		light.light_color = Color(1.0, 0.68, 0.35)
		light.light_energy = 1.85
		light.omni_range = 9.5
		light.omni_attenuation = 1.20
		light.shadow_enabled = true
		light.shadow_bias = 0.15
		light.shadow_normal_bias = 1.5
		node.add_child(light)

		var embers = create_ember_particles()
		embers.position = Vector3(0, ember_y, 0)
		node.add_child(embers)

	elif is_chest:
		if can_use_modular_3d_prop("chest"):
			var chest_node = Node3D.new()
			chest_node.name = "ChestProp"
			var mesh_inst = MeshInstance3D.new()
			mesh_inst.mesh = get_or_load_mesh("res://assets/models/aaa/props/chest_base.res")
			chest_node.add_child(mesh_inst)

			var lid_pivot = Node3D.new()
			lid_pivot.name = "ChestLid"
			lid_pivot.position = Vector3(0, 0.36, -0.22)
			var lid_inst = MeshInstance3D.new()
			lid_inst.mesh = get_or_load_mesh("res://assets/models/aaa/props/chest_lid.res")
			lid_pivot.add_child(lid_inst)
			chest_node.add_child(lid_pivot)
			node.add_child(chest_node)
		else:
			_attach_universal_object_sprite(node, o_id)

	elif is_sarc:
		if can_use_modular_3d_prop("sarcophagus"):
			var sarc_base = MeshInstance3D.new()
			sarc_base.mesh = get_or_load_mesh("res://assets/models/aaa/props/sarcophagus_base.res")
			node.add_child(sarc_base)

			var lid_node = Node3D.new()
			lid_node.name = "SarcLid"
			lid_node.position = Vector3(0, 0.44, 0)
			var lid_mesh = MeshInstance3D.new()
			lid_mesh.mesh = get_or_load_mesh("res://assets/models/aaa/props/sarcophagus_lid.res")
			lid_node.add_child(lid_mesh)
			node.add_child(lid_node)
		else:
			_attach_universal_object_sprite(node, o_id)

	elif is_barrel:
		if can_use_modular_3d_prop("barrel"):
			var barrel_inst = MeshInstance3D.new()
			barrel_inst.mesh = get_or_load_mesh("res://assets/models/props/barrel.glb")
			barrel_inst.material_override = get_pbr_material_for_theme(get_theme_name(last_level_idx), true)
			node.add_child(barrel_inst)
		else:
			_attach_universal_object_sprite(node, o_id)

	elif is_shrine:
		if can_use_modular_3d_prop("shrine"):
			var shrine_inst = MeshInstance3D.new()
			shrine_inst.mesh = get_or_load_mesh("res://assets/models/props/shrine.glb")
			shrine_inst.material_override = get_pbr_material_for_theme(get_theme_name(last_level_idx), true)
			node.add_child(shrine_inst)
		else:
			_attach_universal_object_sprite(node, o_id)

		var shrine_light = OmniLight3D.new()
		shrine_light.name = "ShrineLight"
		shrine_light.position = Vector3(0, 1.2, 0)
		shrine_light.light_color = Color(0.4, 0.85, 1.0)
		shrine_light.light_energy = 1.2
		shrine_light.omni_range = 5.0
		node.add_child(shrine_light)

	else:
		_attach_universal_object_sprite(node, o_id)

	if props_root == null:
		props_root = Node3D.new()
		props_root.name = "PropsRoot"
		add_child(props_root)
	props_root.add_child(node)
	prop_instances[o_id] = node
	return node

func _attach_universal_object_sprite(node: Node3D, o_id: int):
	# Universal Interactive Object Billboard Sprite (Book Pedestals, Sarcophagi, Chests, Barrels, Shrines, Altars, etc.)
	var spr = Sprite3D.new()
	spr.name = "ObjectSprite3D"
	spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.shaded = false
	spr.pixel_size = PIXEL_SIZE_1X
	spr.sorting_offset = 0.05
	spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	spr.modulate = Color(1.45, 1.42, 1.35)

	# 1. Offline-upscaled HD frame (assets/hd_sprites*/objects/<graphic>/frame 0);
	#    update_props refreshes later frames via the same provider each animation tick.
	var hd_graphic = str(node.get_meta("hd_graphic", "")) if node.has_meta("hd_graphic") else ""
	var hd_tex = HdSpriteProvider.get_object_sprite(hd_graphic, 1, current_tile_model) if (hd_graphics_enabled and hd_graphic != "") else null
	if hd_tex != null:
		spr.texture = hd_tex
		spr.offset = Vector2(0, float(hd_tex.get_height()) * 0.5)
		spr.pixel_size = PIXEL_SIZE_HD
		apply_entity_hd_material(spr, spr.texture)
	elif diablo_bridge and diablo_bridge.has_method("get_object_sprite_data"):
		var s_data = diablo_bridge.get_object_sprite_data(o_id)
		var sw = s_data.get("width", 0)
		var sh = s_data.get("height", 0)
		var rgba = s_data.get("rgba", PackedByteArray())
		if sw > 0 and sh > 0 and rgba.size() == sw * sh * 4:
			var img = Image.create_from_data(sw, sh, false, Image.FORMAT_RGBA8, rgba)
			img.generate_mipmaps()
			var tex = ImageTexture.create_from_image(img)
			spr.texture = tex
			spr.offset = Vector2(0, float(sh) * 0.5)
			if sw >= 200:
				spr.pixel_size = PIXEL_SIZE_HD
			else:
				spr.pixel_size = PIXEL_SIZE_1X
			if spr.texture:
				apply_entity_hd_material(spr, spr.texture)

	node.add_child(spr)

func update_environmental_torches(delta: float):
	if not diablo_bridge or not diablo_bridge.has_method("get_active_lights"):
		return

	var cur_lvl = diablo_bridge.get_current_level() if diablo_bridge.has_method("get_current_level") else 1
	if cur_lvl == 0:
		# Town is illuminated by Directional sunlight; suppress floating generic env torches
		for t in torch_instances.values():
			if is_instance_valid(t):
				t.visible = false
		return

	var lights: Array = diablo_bridge.get_active_lights()
	var seen_indices: Dictionary = {}
	var flags_grid: PackedByteArray = diablo_bridge.get_dungeon_flags_grid() if diablo_bridge.has_method("get_dungeon_flags_grid") else PackedByteArray()
	var has_flags = (flags_grid.size() >= 112 * 112)

	# Index 0 is player lantern; index 1..N are environmental torches, braziers, and spells
	for i in range(1, lights.size()):
		var l_info = lights[i]
		var tx = l_info.get("tile_x", -1)
		var ty = l_info.get("tile_y", -1)
		if tx < 0 or ty < 0:
			continue

		# Fog of war: suppress dynamic engine lights located inside completely unexplored areas
		if cur_lvl > 0 and has_flags:
			var t_idx = clamp(ty, 0, 111) * 112 + clamp(tx, 0, 111)
			var fl = flags_grid[t_idx]
			if (fl & (2 | 128)) == 0:
				continue

		# If an active prop (wall torch, brazier) already exists at or adjacent to this tile, let the prop illuminate it!
		var has_prop_light = false
		var wpos = tile_to_world_3d(float(tx), float(ty))
		for p in prop_instances.values():
			if is_instance_valid(p) and p.visible:
				var p_tl = p.get_node_or_null("TorchLight")
				if p_tl == null:
					p_tl = p.get_node_or_null("WallTorch/TorchLight")
				if p_tl and p.position.distance_to(wpos) < 2.2:
					has_prop_light = true
					break
		if has_prop_light:
			continue

		seen_indices[i] = true
		var l_type = l_info.get("type", 1)
		var t_node = get_or_create_env_torch(i, tx, ty, l_type)
		t_node.visible = true

		var o_light = t_node.get_node_or_null("TorchLight") as OmniLight3D
		if o_light:
			var rad = float(l_info.get("radius", 6))
			o_light.omni_range = maxf(9.0, rad * 1.5)
			var flicker = 1.85 + 0.22 * sin(time_accum * 7.0 + float(i) * 1.7) * cos(time_accum * 4.2 + float(i) * 0.9)
			o_light.light_energy = flicker

	for idx in torch_instances.keys():
		if not seen_indices.has(idx):
			torch_instances[idx].visible = false

func get_or_create_env_torch(idx: int, tx: int, ty: int, l_type: int = 1) -> Node3D:
	var h_offset = 0.65 if l_type == 2 else 1.35
	var wpos = tile_to_world_3d(float(tx), float(ty))

	# If placed directly on a solid vertical wall tile, shift outwards into the adjacent room/floor
	var is_actual_wall = false
	var pid = diablo_bridge.get_dungeon_tile(tx, ty) if diablo_bridge and diablo_bridge.has_method("get_dungeon_tile") else -1
	if pid > 0:
		var tex = get_scenery_piece_texture(pid, last_level_idx)
		if tex and tex.get_height() > int(round(float(tex.get_width()) * 0.5)):
			is_actual_wall = true

	if is_actual_wall and last_solidity_grid.size() >= 112 * 112 and last_solidity_grid[ty * 112 + tx] == 2:
		var basis_tile = Basis().rotated(Vector3.UP, deg_to_rad(-45.0))
		if ty < 111 and last_solidity_grid[(ty + 1) * 112 + tx] != 2:
			wpos += basis_tile * Vector3(0.0, 0.0, 0.45)
		elif tx < 111 and last_solidity_grid[ty * 112 + (tx + 1)] != 2:
			wpos += basis_tile * Vector3(0.45, 0.0, 0.0)
		elif ty > 0 and last_solidity_grid[(ty - 1) * 112 + tx] != 2:
			wpos += basis_tile * Vector3(0.0, 0.0, -0.45)
		elif tx > 0 and last_solidity_grid[ty * 112 + (tx - 1)] != 2:
			wpos += basis_tile * Vector3(-0.45, 0.0, 0.0)

	var target_pos = wpos + Vector3(0, h_offset, 0)
	if torch_instances.has(idx):
		var existing = torch_instances[idx]
		existing.position = target_pos
		return existing

	var node = Node3D.new()
	node.name = "EnvTorch_%d" % idx
	node.position = target_pos

	var light = OmniLight3D.new()
	light.name = "TorchLight"
	light.light_color = Color(1.0, 0.85, 0.50) if l_type == 2 else Color(1.0, 0.74, 0.40)
	light.light_energy = 1.85
	light.omni_range = 10.0
	light.omni_attenuation = 1.15
	light.shadow_enabled = false
	node.add_child(light)

	props_root.add_child(node)
	torch_instances[idx] = node
	return node

func create_ember_particles() -> GPUParticles3D:
	var particles = GPUParticles3D.new()
	particles.amount = 16
	particles.lifetime = 0.85
	particles.preprocess = 0.5
	particles.speed_scale = 1.0
	particles.explosiveness = 0.0
	particles.randomness = 0.4

	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.08
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 28.0
	mat.initial_velocity_min = 0.7
	mat.initial_velocity_max = 1.3
	mat.gravity = Vector3(0, 0.45, 0)
	mat.scale_min = 0.02
	mat.scale_max = 0.04
	mat.color = Color(1.0, 0.68, 0.22, 0.95)
	particles.process_material = mat

	var quad = QuadMesh.new()
	quad.size = Vector2(0.04, 0.04)
	var p_mat = StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	p_mat.albedo_color = Color(1.0, 0.7, 0.2)
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = p_mat
	particles.draw_pass_1 = quad

	return particles

func update_scenery_transparency():
	if not is_sandbox_active or not diablo_bridge:
		return
	var cur_lvl = diablo_bridge.get_current_level() if diablo_bridge.has_method("get_current_level") else 1
	if cur_lvl == 0:
		if not translucent_scenery_indices.is_empty():
			for idx in translucent_scenery_indices.keys():
				var spr = town_scenery_nodes.get(idx, null)
				if spr:
					spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
					spr.modulate.a = 1.0
					spr.render_priority = 3
				var aspr = special_scenery_nodes.get(idx, null)
				if aspr:
					aspr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
					aspr.modulate.a = 1.0
					aspr.render_priority = 3
			translucent_scenery_indices.clear()
		return

	if not diablo_bridge.has_method("get_dungeon_trans_grid") or not diablo_bridge.has_method("get_dungeon_trans_mask") or not diablo_bridge.has_method("get_trans_list"):
		return

	var trans_grid: PackedByteArray = diablo_bridge.get_dungeon_trans_grid()
	var trans_mask: PackedByteArray = diablo_bridge.get_dungeon_trans_mask()
	var trans_list: PackedByteArray = diablo_bridge.get_trans_list()

	if trans_grid.size() < 112 * 112 or trans_mask.size() < 112 * 112 or trans_list.size() < 256:
		return

	var grid = diablo_bridge.get_dungeon_grid() if diablo_bridge.has_method("get_dungeon_grid") else PackedInt32Array()
	var has_grid = (grid.size() >= 112 * 112)

	var ppos = diablo_bridge.get_player_continuous_pos() if diablo_bridge.has_method("get_player_continuous_pos") else {}
	var ptx = int(round(float(ppos.get("pos_x", 0.0))))
	var pty = int(round(float(ppos.get("pos_y", 0.0))))

	# Generous transparency scan radius covering current camera viewport plus margin
	var vis_rad = int(ceil(maxf(camera_distance * 1.5, 20.0)))
	var min_x = maxi(0, ptx - vis_rad)
	var max_x = mini(111, ptx + vis_rad)
	var min_y = maxi(0, pty - vis_rad)
	var max_y = mini(111, pty + vis_rad)

	var new_translucent: Dictionary = {}

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var idx = y * 112 + x
			if trans_mask[idx] != 0:
				var t_val = trans_grid[idx]
				if t_val > 0 and t_val < trans_list.size() and trans_list[t_val] != 0:
					# Freestanding columns and pillars must NEVER turn translucent!
					var pid = grid[idx] if has_grid else -1
					if pid >= 0 and is_piece_pillar(pid, cur_lvl):
						continue
					new_translucent[idx] = true

	# Restore walls that are no longer translucent
	for idx in translucent_scenery_indices.keys():
		if not new_translucent.has(idx):
			var spr = town_scenery_nodes.get(idx, null)
			if spr:
				spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
				spr.modulate.a = 1.0
				spr.render_priority = 3
			var aspr = special_scenery_nodes.get(idx, null)
			if aspr:
				aspr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
				aspr.modulate.a = 1.0
				aspr.render_priority = 3

	# Apply soft transparency to new translucent walls
	for idx in new_translucent.keys():
		if not translucent_scenery_indices.has(idx):
			var spr = town_scenery_nodes.get(idx, null)
			if spr:
				spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
				spr.modulate.a = 0.45
				spr.render_priority = 4
			var aspr = special_scenery_nodes.get(idx, null)
			if aspr:
				aspr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
				aspr.modulate.a = 0.45
				aspr.render_priority = 4

	translucent_scenery_indices = new_translucent

# ==============================================================================
# Ground Items & Loot Drops Pipeline
# ==============================================================================

func update_ground_items(delta: float):
	if not diablo_bridge or not diablo_bridge.has_method("get_active_items"):
		return

	var items: Array = diablo_bridge.get_active_items()
	var seen_ids: Dictionary = {}

	var cur_lvl = diablo_bridge.get_current_level() if diablo_bridge.has_method("get_current_level") else 1
	var flags_grid: PackedByteArray = diablo_bridge.get_dungeon_flags_grid() if diablo_bridge.has_method("get_dungeon_flags_grid") else PackedByteArray()
	var has_flags = (flags_grid.size() >= 112 * 112)

	for item in items:
		var i_id = item.get("id", -1)
		if i_id < 0:
			continue
		seen_ids[i_id] = true

		var tx = item.get("tile_x", 0)
		var ty = item.get("tile_y", 0)
		var quality = item.get("quality", 0)
		var iname = item.get("name", "")
		var curs_id = item.get("curs_id", 0)
		var anim_frame = item.get("anim_frame", 0)

		var node = get_or_create_item_node(i_id, curs_id, anim_frame, quality, iname, tx, ty, item)

		# Visibility / Fog-of-war gating for ground items
		var is_item_visible = true
		if cur_lvl > 0 and has_flags:
			var t_idx = clamp(ty, 0, 111) * 112 + clamp(tx, 0, 111)
			var fl = flags_grid[t_idx]
			is_item_visible = (fl & (2 | 128)) != 0

		node.visible = is_item_visible
		if not is_item_visible:
			continue

		node.set_meta("tile_x", tx)
		node.set_meta("tile_y", ty)

		# Update position in world
		var wpos = tile_to_world_3d(float(tx), float(ty))
		node.position = wpos + Vector3(0, 0.06, 0)

		# Light beam pulsing animation for Magic / Unique loot
		var beam = node.get_node_or_null("LootBeam")
		if beam:
			var pulse = 0.88 + 0.12 * sin(time_accum * 4.5 + float(i_id) * 1.5)
			beam.scale = Vector3(pulse, 1.0, pulse)

	# Clean up inactive ground items
	for id in item_instances.keys():
		if not seen_ids.has(id):
			item_instances[id].visible = false

func get_or_create_item_node(i_id: int, curs_id: int, anim_frame: int, quality: int, iname: String, tx: int, ty: int, item_data: Dictionary = {}) -> Node3D:
	if item_instances.has(i_id):
		return item_instances[i_id]

	var node = Node3D.new()
	node.name = "GroundItem_%d" % i_id
	var wpos = tile_to_world_3d(float(tx), float(ty))
	node.position = wpos + Vector3(0, 0.06, 0)
	node.set_meta("item_id", i_id)
	node.set_meta("curs_id", curs_id)
	node.set_meta("quality", quality)
	node.set_meta("quality_name", item_data.get("quality_name", "NORMAL"))
	node.set_meta("item_name", iname)
	node.set_meta("tile_x", tx)
	node.set_meta("tile_y", ty)
	node.set_meta("item_type", item_data.get("item_type", 0))
	node.set_meta("type_desc", item_data.get("type_desc", "Item"))
	node.set_meta("min_dam", item_data.get("min_dam", 0))
	node.set_meta("max_dam", item_data.get("max_dam", 0))
	node.set_meta("ac", item_data.get("ac", 0))
	node.set_meta("durability", item_data.get("durability", 0))
	node.set_meta("max_dur", item_data.get("max_dur", 0))
	node.set_meta("req_str", item_data.get("req_str", 0))
	node.set_meta("req_dex", item_data.get("req_dex", 0))
	node.set_meta("req_mag", item_data.get("req_mag", 0))
	node.set_meta("value", item_data.get("value", 0))
	node.set_meta("magic_desc", item_data.get("magic_desc", ""))

	# Fetch texture from HD disk cache or diablo_bridge
	var cache_key = "%d_%d" % [curs_id, anim_frame]
	var tex: Texture2D = null
	var item_is_hd: bool = false

	if item_textures.has(cache_key):
		tex = item_textures[cache_key]
		item_is_hd = item_is_hd_cache.get(cache_key, false)
	else:
		# 1. Offline-upscaled HD ground item sprite (assets/hd_sprites*/items/curs_*),
		#    model-aware with corruption screening.
		if hd_graphics_enabled:
			tex = HdSpriteProvider.get_item_sprite(curs_id, anim_frame, current_tile_model)
			if tex != null:
				item_is_hd = true

		# 2. Fallback: authentic Diablo 1 ground item sprite rasterization from bridge
		if tex == null and diablo_bridge:
			var s_data: Dictionary = {}
			if diablo_bridge.has_method("get_ground_item_sprite_data"):
				s_data = diablo_bridge.get_ground_item_sprite_data(i_id)
			elif diablo_bridge.has_method("get_item_sprite_data"):
				s_data = diablo_bridge.get_item_sprite_data(curs_id)
			var sw = s_data.get("width", 0)
			var sh = s_data.get("height", 0)
			var rgba: PackedByteArray = s_data.get("rgba", PackedByteArray())
			if sw > 0 and sh > 0 and rgba.size() == sw * sh * 4:
				var img = Image.create_from_data(sw, sh, false, Image.FORMAT_RGBA8, rgba)
				var used_rect = img.get_used_rect()
				if used_rect.size.x > 0 and used_rect.size.y > 0:
					img = img.get_region(used_rect)
				img.generate_mipmaps()
				tex = ImageTexture.create_from_image(img)
				item_is_hd = false

		item_textures[cache_key] = tex
		item_is_hd_cache[cache_key] = item_is_hd

	# 3D Item Sprite (grounded slightly above floor)
	var spr = Sprite3D.new()
	spr.name = "ItemSprite"
	spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.shaded = false
	spr.render_priority = 2 # Ground Items: strictly above corpses (render_priority=1)
	spr.sorting_offset = 0.02 + float(tx + ty) * 0.0001
	var item_scale_boost = 1.0
	spr.pixel_size = (PIXEL_SIZE_HD if item_is_hd else PIXEL_SIZE_1X) * item_scale_boost
	spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spr.centered = true
	spr.offset = Vector2.ZERO
	if tex:
		spr.texture = tex
		apply_entity_hd_material(spr, tex)
	spr.modulate = Color(1.35, 1.35, 1.35)
	node.add_child(spr)

	# Modern ARPG Ground Loot Label Container (Always Visible, y = 0.85m)
	var label_root = Node3D.new()
	label_root.name = "LabelRoot"
	label_root.position = Vector3(0, 0.85, 0)
	node.add_child(label_root)

	var quality_border: Color
	var quality_text: Color
	if quality == 1:
		quality_border = Color(0.30, 0.65, 1.0, 0.95) # Magic Blue
		quality_text = Color(0.45, 0.75, 1.0)
	elif quality == 2:
		quality_border = Color(1.0, 0.82, 0.22, 0.95) # Unique Gold
		quality_text = Color(1.0, 0.88, 0.35)
	else:
		quality_border = Color(0.75, 0.75, 0.78, 0.90) # Normal Silver/Slate
		quality_text = Color(0.92, 0.92, 0.94)

	# 1. Dark Slate Ground Label Box (QuadMesh)
	# Permanent comfortable larger size (font_size 22, height 0.28m) without jarring scale jumps
	var label_font_size = 22
	var text_sz = FONT_EXOCET.get_string_size(iname, HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size)
	var text_world_w = text_sz.x * 0.005 # Label3D default pixel_size is 0.005
	var box_w = maxf(text_world_w + 0.28, 0.75)
	var box_h = 0.28
	node.set_meta("box_w", box_w)

	var bg_quad = MeshInstance3D.new()
	bg_quad.name = "LabelBg"
	var q_mesh = QuadMesh.new()
	q_mesh.size = Vector2(box_w, box_h)
	bg_quad.mesh = q_mesh

	var bg_mat = StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg_mat.no_depth_test = true
	bg_mat.render_priority = 20
	bg_mat.albedo_color = Color(0.04, 0.04, 0.06, 0.88)
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_quad.material_override = bg_mat
	label_root.add_child(bg_quad)

	# 2. Quality Border Quad (slightly larger outline behind bg)
	var border_quad = MeshInstance3D.new()
	border_quad.name = "LabelBorder"
	var b_mesh = QuadMesh.new()
	b_mesh.size = Vector2(box_w + 0.04, box_h + 0.04)
	border_quad.mesh = b_mesh

	var b_mat = StandardMaterial3D.new()
	b_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	b_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	b_mat.no_depth_test = true
	b_mat.render_priority = 19
	b_mat.albedo_color = quality_border
	border_quad.material_override = b_mat
	label_root.add_child(border_quad)

	# 3. Label Text (billboarded above backing)
	var lbl = Label3D.new()
	lbl.name = "ItemLabel"
	lbl.font = FONT_EXOCET
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.render_priority = 21
	lbl.font_size = label_font_size
	lbl.outline_size = 4
	lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.98)
	lbl.modulate = quality_text
	lbl.text = iname
	label_root.add_child(lbl)

	# Vertical loot beam for Magic & Unique drops
	if quality >= 1:
		var beam = MeshInstance3D.new()
		beam.name = "LootBeam"
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.05
		cyl.bottom_radius = 0.12
		cyl.height = 1.80
		beam.mesh = cyl
		beam.position.y = 0.90
		var beam_mat = StandardMaterial3D.new()
		beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if quality == 1:
			beam_mat.albedo_color = Color(0.30, 0.60, 1.0, 0.35)
		else:
			beam_mat.albedo_color = Color(1.0, 0.80, 0.20, 0.45)
		beam.material_override = beam_mat
		node.add_child(beam)

	items_root.add_child(node)
	item_instances[i_id] = node
	return node

func setup_click_marker():
	click_marker = MeshInstance3D.new()
	click_marker.name = "ClickMarker"
	var marker_torus = TorusMesh.new()
	marker_torus.inner_radius = 0.32
	marker_torus.outer_radius = 0.40
	click_marker.mesh = marker_torus
	click_marker.position.y = 0.03
	var marker_mat = StandardMaterial3D.new()
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_mat.albedo_color = Color(0.9, 0.75, 0.2, 0.0)
	marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	click_marker.material_override = marker_mat
	click_marker.visible = false
	add_child(click_marker)

func spawn_click_ring(world_pos: Vector3, color: Color) -> void:
	if click_marker == null:
		return
	click_marker.position = Vector3(world_pos.x, 0.04, world_pos.z)
	click_marker.visible = true
	click_fade = 0.90
	var mat = click_marker.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = color
		mat.albedo_color.a = click_fade

# ==============================================================================
# Missiles & Projectiles 3D Pipeline
# ==============================================================================

func update_missiles(delta: float):
	if not diablo_bridge or not diablo_bridge.has_method("get_active_missiles") or missiles_root == null:
		return

	var missiles: Array = diablo_bridge.get_active_missiles()
	var seen_ids: Dictionary = {}
	var active_missile_lights: int = 0
	var active_missile_particles: int = 0

	for m in missiles:
		var m_id = m.get("id", -1)
		if m_id < 0:
			continue
		seen_ids[m_id] = true

		var m_type = m.get("type", 0)
		var m_dir = m.get("dir", 0)
		var px = m.get("pos_x", 0.0)
		var py = m.get("pos_y", 0.0)
		var anim_frame = m.get("anim_frame", 0)
		var light_flag = bool(m.get("light_flag", false))
		var pre_flag = bool(m.get("pre_flag", false))

		# Convert continuous tile/world pos to 3D world pos
		var tile_x = (px / 32.0 + py / 16.0) * 0.5
		var tile_y = (py / 16.0 - px / 32.0) * 0.5
		var pos_3d = tile_to_world_3d(tile_x, tile_y)

		# Ground/Wall effects (FireWall, LightningWall, TownPortal, Acid, RedPortal) vs flying projectiles
		var is_ground_skill = pre_flag or m_type in [4, 5, 6, 10, 33, 38, 59, 65, 70]
		if is_ground_skill:
			pos_3d.y = 0.04
		else:
			pos_3d.y = 0.85

		var node = missile_instances.get(m_id, null)
		if node == null:
			node = Node3D.new()
			node.name = "Missile_%d" % m_id
			missiles_root.add_child(node)

			var spr = Sprite3D.new()
			spr.name = "Sprite3D"
			spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			spr.pixel_size = PIXEL_SIZE_1X
			spr.shaded = false
			spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(spr)

			var m_light = OmniLight3D.new()
			m_light.name = "MissileLight"
			node.add_child(m_light)

			missile_instances[m_id] = node

		node.position = pos_3d

		# Dynamic animation update on frame or direction change with RAM texture caching
		var spr = node.get_node_or_null("Sprite3D") as Sprite3D
		var last_frame = node.get_meta("last_anim_frame", -1)
		var last_dir = node.get_meta("last_anim_dir", -1)
		var cache_key = "%d_%d_%d" % [m_type, m_dir, anim_frame]
		var tex: Texture2D = null

		if missile_textures.has(cache_key):
			tex = missile_textures[cache_key]
		else:
			node.set_meta("last_anim_frame", anim_frame)
			node.set_meta("last_anim_dir", m_dir)
			# 1. Offline-upscaled HD frame (assets/hd_sprites*/missiles/<cel>/)
			var hd_mis = HdSpriteProvider.get_missile_sprite(str(m.get("cel", "")), m_dir, anim_frame, current_tile_model) if hd_graphics_enabled else null
			if hd_mis != null:
				tex = hd_mis
				missile_textures[cache_key] = tex
			elif diablo_bridge.has_method("get_missile_sprite_data"):
				var ms_data = diablo_bridge.get_missile_sprite_data(m_id)
				var mw = ms_data.get("width", 0)
				var mh = ms_data.get("height", 0)
				var m_rgba = ms_data.get("rgba", PackedByteArray())
				if mw > 0 and mh > 0 and m_rgba.size() == mw * mh * 4:
					var m_img = Image.create_from_data(mw, mh, false, Image.FORMAT_RGBA8, m_rgba)
					m_img.generate_mipmaps()
					tex = ImageTexture.create_from_image(m_img)
					missile_textures[cache_key] = tex
				else:
					missile_textures[cache_key] = null

		if spr and tex:
			if spr.texture != tex:
				spr.texture = tex
				if is_ground_skill:
					spr.offset = Vector2(0, float(tex.get_height()) * 0.5)
				else:
					spr.offset = Vector2.ZERO
			if spr.material_override == null:
				apply_entity_hd_material(spr, spr.texture)

		# Dynamic 3D particle emitters for spell missiles (capped at 4 emitters max for 144 FPS)
		# Fire missiles (Fireball, Fire Wall, Flame Wave, Inferno, etc.)
		if m_type in [1, 4, 5, 9, 13, 14, 19, 20, 24, 30, 35, 44, 48, 67, 72]:
			var fire_p = node.get_node_or_null("MissileFireParticles") as GPUParticles3D
			if fire_p == null and active_missile_particles < 4:
				active_missile_particles += 1
				fire_p = create_ember_particles()
				fire_p.name = "MissileFireParticles"
				node.add_child(fire_p)
		# Lightning missiles (Lightning, Lightning Wall, Charged Bolt, Nova)
		elif m_type in [3, 8, 15, 21, 23, 26, 29, 42, 52, 56, 70]:
			var spark_p = node.get_node_or_null("MissileSparkParticles") as GPUParticles3D
			if spark_p == null and torch_sparks_scene and active_missile_particles < 4:
				active_missile_particles += 1
				spark_p = torch_sparks_scene.instantiate()
				spark_p.name = "MissileSparkParticles"
				spark_p.amount = 8
				spark_p.lifetime = 0.25
				node.add_child(spark_p)
		# Portals (Town Portal, Red Portal)
		elif m_type in [6, 10, 38, 65]:
			var portal_p = node.get_node_or_null("MissilePortalParticles") as CPUParticles3D
			if portal_p == null:
				portal_p = CPUParticles3D.new()
				portal_p.name = "MissilePortalParticles"
				portal_p.amount = 28
				portal_p.lifetime = 1.6
				portal_p.preprocess = 0.3
				portal_p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
				portal_p.emission_ring_radius = 0.75
				portal_p.emission_ring_inner_radius = 0.20
				portal_p.direction = Vector3(0, 1, 0)
				portal_p.spread = 20.0
				portal_p.gravity = Vector3(0, 0.8, 0)
				portal_p.initial_velocity_min = 0.4
				portal_p.initial_velocity_max = 1.1
				portal_p.angular_velocity_min = 60.0
				portal_p.angular_velocity_max = 180.0
				if m_type in [6, 10]:
					portal_p.color = Color(0.28, 0.68, 1.0, 0.85)
				else:
					portal_p.color = Color(1.0, 0.22, 0.15, 0.85)
				portal_p.position = Vector3(0, 0.2, 0)
				node.add_child(portal_p)

		# Dynamic 3D lighting & forward+ HDR illumination (capped at 4 simultaneous dynamic lights)
		var m_light = node.get_node_or_null("MissileLight") as OmniLight3D
		if m_light:
			var needs_light = light_flag or m_type in [1, 3, 4, 5, 6, 8, 9, 10, 13, 14, 15, 19, 20, 21, 23, 24, 26, 27, 28, 29, 30, 31, 32, 33, 35, 38, 42, 44, 48, 52, 53, 56, 57, 58, 59, 65, 67, 70, 72]
			if needs_light and active_missile_lights < 4:
				active_missile_lights += 1
				m_light.visible = true
				if m_type in [3, 8, 15, 21, 23, 26, 29, 42, 52, 56, 70]: # Lightning / Nova
					m_light.light_color = Color(0.35, 0.78, 1.0)
					m_light.light_energy = 3.2
					m_light.omni_range = 6.5
					m_light.omni_attenuation = 1.1
					if spr: spr.modulate = Color(1.5, 1.5, 1.6)
				elif m_type in [1, 4, 5, 9, 13, 14, 19, 20, 24, 30, 35, 44, 48, 67, 72]: # Fire / Fireball
					m_light.light_color = Color(1.0, 0.58, 0.18)
					m_light.light_energy = 2.8
					m_light.omni_range = 6.0
					m_light.omni_attenuation = 1.2
					if spr: spr.modulate = Color(1.5, 1.4, 1.2)
				elif m_type in [27, 28, 53]: # Holy Bolt
					m_light.light_color = Color(1.0, 0.95, 0.70)
					m_light.light_energy = 2.8
					m_light.omni_range = 5.5
					m_light.omni_attenuation = 1.2
					if spr: spr.modulate = Color(1.6, 1.6, 1.4)
				elif m_type in [31, 32, 33, 57, 58, 59]: # Acid / Poison
					m_light.light_color = Color(0.30, 1.0, 0.35)
					m_light.light_energy = 1.8
					m_light.omni_range = 4.5
					m_light.omni_attenuation = 1.3
					if spr: spr.modulate = Color(1.2, 1.5, 1.2)
				elif m_type in [6, 10, 38, 65]: # Town Portal / Red Portal
					m_light.light_color = Color(0.35, 0.60, 1.0) if m_type in [6, 10] else Color(1.0, 0.25, 0.25)
					m_light.light_energy = 2.6
					m_light.omni_range = 5.0
					m_light.omni_attenuation = 1.2
					if spr: spr.modulate = Color(1.4, 1.4, 1.4)
				else:
					m_light.light_color = Color(1.0, 0.80, 0.40)
					m_light.light_energy = 2.0
					m_light.omni_range = 4.5
					m_light.omni_attenuation = 1.3
			else:
				m_light.visible = false

	# Clean up expired missiles
	var to_remove = []
	for id in missile_instances.keys():
		if not seen_ids.has(id):
			var n = missile_instances[id]
			if is_instance_valid(n):
				n.queue_free()
			to_remove.append(id)
	for id in to_remove:
		missile_instances.erase(id)

# ==============================================================================
# Corpses & Fallen Entities 3D Pipeline
# ==============================================================================

func update_corpses():
	if not diablo_bridge or not diablo_bridge.has_method("get_active_corpses") or corpses_root == null:
		return

	var corpses: Array = diablo_bridge.get_active_corpses()
	var seen_keys: Dictionary = {}

	for c in corpses:
		var tx = c.get("tile_x", 0)
		var ty = c.get("tile_y", 0)
		var c_idx = c.get("corpse_idx", 0)
		var c_dir = c.get("dir", 0)
		var c_key = "%d_%d_%d" % [tx, ty, c_idx]
		seen_keys[c_key] = true

		if corpse_instances.has(c_key):
			continue

		var node = Node3D.new()
		node.name = "Corpse_" + c_key
		var c_pos = tile_to_world_3d(tx, ty)
		c_pos.y = 0.04
		node.position = c_pos
		corpses_root.add_child(node)

		var spr = Sprite3D.new()
		spr.name = "CorpseSprite"
		spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		spr.pixel_size = PIXEL_SIZE_1X
		spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		spr.shaded = false
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		spr.render_priority = 1 # Corpse layer: above floor (0), strictly below items (2) and actors (3)
		spr.sorting_offset = -0.05 + float(tx + ty) * 0.0001
		spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spr.modulate = Color(1.35, 1.32, 1.25)
		node.add_child(spr)

		var c_tex_key = "%d_%d" % [c_idx, c_dir]
		var c_tex: Texture2D = null
		if corpse_textures.has(c_tex_key):
			c_tex = corpse_textures[c_tex_key]
		else:
			# 1. Offline-upscaled HD death frame (assets/hd_sprites*/monsters/<family>_death/)
			var hd_c = HdSpriteProvider.get_corpse_sprite(str(c.get("monster_name", "")), c_dir, int(c.get("frame", 0)), current_tile_model) if hd_graphics_enabled else null
			if hd_c != null:
				c_tex = hd_c
			elif diablo_bridge.has_method("get_corpse_sprite_data"):
				var cs_data = diablo_bridge.get_corpse_sprite_data(c_idx, c_dir)
				var cw = cs_data.get("width", 0)
				var ch = cs_data.get("height", 0)
				var c_rgba = cs_data.get("rgba", PackedByteArray())
				if cw > 0 and ch > 0 and c_rgba.size() == cw * ch * 4:
					var c_img = Image.create_from_data(cw, ch, false, Image.FORMAT_RGBA8, c_rgba)
					c_img.generate_mipmaps()
					c_tex = ImageTexture.create_from_image(c_img)
				else:
					c_tex = null
			corpse_textures[c_tex_key] = c_tex

		if c_tex:
			spr.texture = c_tex
			spr.pixel_size = PIXEL_SIZE_HD if c_tex.get_width() >= 200 else PIXEL_SIZE_1X
			spr.offset = Vector2(0, float(c_tex.get_height()) * 0.5)
			apply_corpse_hd_material(spr, spr.texture)

		corpse_instances[c_key] = node

	var to_remove = []
	for k in corpse_instances.keys():
		if not seen_keys.has(k):
			var n = corpse_instances[k]
			if is_instance_valid(n):
				n.queue_free()
			to_remove.append(k)
	for k in to_remove:
		corpse_instances.erase(k)

# ==============================================================================
# Coordinate Mathematics Utilities
# ==============================================================================

func tile_to_world_3d(tx: float, ty: float) -> Vector3:
	return Vector3((tx - ty) * TILE_SCALE, 0.0, (tx + ty) * TILE_SCALE)

func world_3d_to_tile(pos: Vector3) -> Vector2:
	var tx = (pos.z + pos.x) / (2.0 * TILE_SCALE)
	var ty = (pos.z - pos.x) / (2.0 * TILE_SCALE)
	return Vector2(tx, ty)

# ==============================================================================
# Process & Lifecycle
# ==============================================================================

func activate():
	if camera == null:
		setup_scene_nodes()
	is_sandbox_active = true
	visible = true
	set_process(true)
	var cur_lvl = diablo_bridge.get_current_level() if diablo_bridge and diablo_bridge.has_method("get_current_level") else 0
	update_modular_dungeon_assets(cur_lvl)
	if dir_light:
		dir_light.visible = true
	if player_lantern:
		player_lantern.visible = (cur_lvl > 0)
	if items_root:
		items_root.visible = true
	if town_scenery_root:
		town_scenery_root.visible = true
	if town_base_ground:
		town_base_ground.visible = (cur_lvl == 0)
	if dungeon_base_ground:
		dungeon_base_ground.visible = (cur_lvl > 0)
	for t in torch_instances.values():
		if is_instance_valid(t):
			t.visible = (cur_lvl > 0)
	if camera:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = camera_distance * (14.5 / 13.0)
		camera.make_current()
		var listener = camera.get_node_or_null("AudioListener3D") as AudioListener3D
		if listener:
			listener.make_current()
	camera_pitch = 30.0
	camera_yaw = 0.0
	last_applied_scenery_yaw = -999.0
	rebuild_dungeon_if_needed(true)
	snap_camera_to_player()
	# Immediately snap entities to prevent sliding across map from stale positions
	update_props(0.0)
	update_monster_entities(0.0)
	update_ground_items(0.0)
	print("[Native 3D Sandbox] Activated! Real-time 3D world, modular kit, and PBR Forward+ lighting active.")

func deactivate():
	is_sandbox_active = false
	visible = false
	set_process(false)
	if dir_light:
		dir_light.visible = false
	if player_lantern:
		player_lantern.visible = false
	if items_root:
		items_root.visible = false
	if town_scenery_root:
		town_scenery_root.visible = false
	if town_base_ground:
		town_base_ground.visible = false
	if dungeon_base_ground:
		dungeon_base_ground.visible = false
	for t in torch_instances.values():
		if is_instance_valid(t):
			t.visible = false
	if camera:
		camera.current = false
		var listener = camera.get_node_or_null("AudioListener3D") as AudioListener3D
		if listener:
			listener.clear_current()
	print("[Native 3D Sandbox] Deactivated. Classic 2.5D view restored.")

func snap_camera_to_player():
	if not diablo_bridge or not diablo_bridge.has_method("get_player_continuous_pos"):
		return
	var p_data = diablo_bridge.get_player_continuous_pos()
	if not p_data or p_data.is_empty() or not p_data.has("pos_x"):
		return
	var px = float(p_data.get("pos_x", 0.0))
	var py = float(p_data.get("pos_y", 0.0))
	camera_target = tile_to_world_3d(px, py)
	player_target_pos = camera_target
	if player_root:
		player_root.position = player_target_pos
	update_camera_transform()

func _process(delta: float):
	if not is_sandbox_active or not diablo_bridge:
		return
	if not _bridge_read_gate_open():
		return

	# Instant level transition check (executed every frame, never waiting on 1.5s timer)
	var cur_lvl = diablo_bridge.get_current_level() if diablo_bridge.has_method("get_current_level") else 1
	if cur_lvl != last_level_idx:
		_on_level_changed(cur_lvl)

	# Gamma change check
	if diablo_bridge.has_method("get_gamma"):
		var cur_gamma = diablo_bridge.get_gamma()
		if cur_gamma != last_gamma_value:
			last_gamma_value = cur_gamma
			player_texture = null
			last_player_frame = -1
			last_player_dir = -1
			monster_textures.clear()
			monster_anim_cache.clear()
			monster_last_frame.clear()
			missile_textures.clear()
			corpse_textures.clear()

	time_accum += delta
	last_check_timer += delta
	last_prop_check_timer += delta

	# Check and rebuild dungeon if map changes (every 1.5s)
	if last_check_timer >= 1.5:
		last_check_timer = 0.0
		rebuild_dungeon_if_needed(false)

	# Update 3D entities
	update_player_entity(delta)
	update_monster_entities(delta)
	update_ground_items(delta)
	update_missiles(delta)
	update_corpses()

	# Native Godot 3D Combat Events & Floating Combat Text (Task 5.2)
	process_combat_events(delta)
	update_flashing(delta)
	update_visual_effects()

	# Update interactive 3D props & environmental torches (every 0.2s)
	if last_prop_check_timer >= 0.2:
		last_prop_check_timer = 0.0
		update_props(delta)
		update_environmental_torches(delta)

	# Update wall transparency (every frame for smooth responsive camera transitions)
	update_scenery_transparency()

	# Dynamic torch flame flicker animation
	for t_node in torch_instances.values():
		if is_instance_valid(t_node) and t_node.visible:
			var o_light = t_node.get_node_or_null("TorchLight") as OmniLight3D
			if o_light:
				var f = 1.85 + 0.22 * sin(time_accum * 7.5 + float(t_node.get_instance_id()) * 0.05) * cos(time_accum * 4.3)
				o_light.light_energy = f

	# Update smooth camera follow
	update_camera_tracking(delta)

	# Update click marker fade
	if click_fade > 0.0:
		click_fade -= delta * 2.5
		if click_fade <= 0.0:
			click_marker.visible = false
		else:
			var mat = click_marker.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color.a = click_fade

# ==============================================================================
# Camera & Controls
# ==============================================================================

func update_camera_tracking(delta: float):
	if not camera:
		return
	var cam_dist = camera_target.distance_to(player_target_pos)
	if cam_dist > 5.0:
		camera_target = player_target_pos
	else:
		camera_target = camera_target.lerp(player_target_pos, delta * 7.5)
	if camera_trauma > 0.0:
		camera_trauma = maxf(0.0, camera_trauma - delta * 2.5)
	update_camera_transform()

func update_camera_transform():
	if not camera:
		return
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		camera.size = camera_distance * (14.5 / 13.0)

	var rot_yaw = Basis().rotated(Vector3.UP, deg_to_rad(camera_yaw))
	var rot_pitch = Basis().rotated(Vector3.RIGHT, deg_to_rad(-camera_pitch))
	var cam_rot = rot_yaw * rot_pitch
	var cam_offset = cam_rot * Vector3(0, 0, camera_distance)

	var shake_offset = Vector3.ZERO
	if camera_trauma > 0.0:
		var shake_amount = camera_trauma * camera_trauma * 0.12
		shake_offset = Vector3(randf_range(-shake_amount, shake_amount), randf_range(-shake_amount, shake_amount), 0.0)

	camera.position = camera_target + cam_offset + shake_offset
	if camera.is_inside_tree():
		camera.look_at(camera_target + Vector3(0, 0.75, 0), Vector3.UP)

	# Keep all scenery and special archways aligned uniformly in parallel with camera yaw (strictly upright on Y)
	# Eliminates domino/blinds saw-tooth slicing when orbiting across ALL levels
	if is_sandbox_active:
		var yaw_rad = deg_to_rad(camera_yaw)
		if abs(yaw_rad - last_applied_scenery_yaw) > 0.001:
			last_applied_scenery_yaw = yaw_rad
			for spr in town_scenery_nodes.values():
				if is_instance_valid(spr):
					spr.rotation.x = 0.0
					spr.rotation.y = yaw_rad
			for aspr in special_scenery_nodes.values():
				if is_instance_valid(aspr):
					aspr.rotation.x = 0.0
					aspr.rotation.y = yaw_rad

# ==============================================================================
# 3D Input & Navigation Handling
# ==============================================================================

func handle_input(event: InputEvent) -> bool:
	if not is_sandbox_active:
		return false

	# Passthrough gates for menus, modals, and text entry
	if diablo_bridge and diablo_bridge.has_method("is_game_running") and not diablo_bridge.is_game_running():
		return false
	if diablo_bridge and diablo_bridge.has_method("is_modal_active") and diablo_bridge.is_modal_active():
		return false
	if diablo_bridge and diablo_bridge.has_method("is_text_input_active") and diablo_bridge.is_text_input_active():
		return false

	# Camera Tilt / Pitch Controls (PageUp / PageDown)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_PAGEUP:
			camera_pitch = clamp(camera_pitch + 5.0, 25.0, 75.0)
			if main_receiver:
				main_receiver.show_osd("[3D Camera] Tilt/Pitch: %.0f°" % camera_pitch, 1.2)
			return true
		elif event.keycode == KEY_PAGEDOWN:
			camera_pitch = clamp(camera_pitch - 5.0, 25.0, 75.0)
			if main_receiver:
				main_receiver.show_osd("[3D Camera] Tilt/Pitch: %.0f°" % camera_pitch, 1.2)
			return true
		elif event.keycode == KEY_Q:
			camera_yaw = fposmod(camera_yaw - 15.0, 360.0)
			if main_receiver:
				main_receiver.show_osd("[3D Camera] Yaw Rotate Left: %.0f°" % camera_yaw, 1.2)
			return true
		elif event.keycode == KEY_E:
			camera_yaw = fposmod(camera_yaw + 15.0, 360.0)
			if main_receiver:
				main_receiver.show_osd("[3D Camera] Yaw Rotate Right: %.0f°" % camera_yaw, 1.2)
			return true
		elif event.keycode == KEY_HOME or event.keycode == KEY_R:
			camera_pitch = 30.0
			camera_yaw = 0.0
			camera_distance = 13.0
			if camera and camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
				camera.size = 14.5
			if main_receiver:
				main_receiver.show_osd("[3D Camera] Reset to Default (30° Isometric Orthogonal)", 1.2)
			return true
		elif event.keycode == KEY_F8:
			camera_mode_perspective = not camera_mode_perspective
			if camera:
				if camera_mode_perspective:
					camera.projection = Camera3D.PROJECTION_PERSPECTIVE
					camera.fov = 50.0
					camera_pitch = 50.0
				else:
					camera.projection = Camera3D.PROJECTION_ORTHOGONAL
					camera.size = camera_distance * (14.5 / 13.0)
					camera_pitch = 30.0
					camera_yaw = 0.0
			if main_receiver:
				var m_name = "Tactical 3D Perspective" if camera_mode_perspective else "True 2:1 Isometric Orthogonal"
				main_receiver.show_osd("[3D Camera Mode] " + m_name, 1.5)
			return true

	# Mouse Orbit (Middle Click Drag)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			is_orbiting = event.pressed
			last_mouse_pos = event.position
			return true
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_distance = clamp(camera_distance - 1.0, 5.0, 25.0)
			if camera and camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
				camera.size = camera_distance * (14.5 / 13.0)
			if main_receiver:
				main_receiver.show_osd("[3D Camera] Distance: %.1fm (Size: %.1f)" % [camera_distance, camera.size if camera else 14.5], 1.0)
			return true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_distance = clamp(camera_distance + 1.0, 5.0, 25.0)
			if camera and camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
				camera.size = camera_distance * (14.5 / 13.0)
			if main_receiver:
				main_receiver.show_osd("[3D Camera] Distance: %.1fm (Size: %.1f)" % [camera_distance, camera.size if camera else 14.5], 1.0)
			return true

	if event is InputEventMouseMotion:
		if is_orbiting:
			var delta_pos = event.position - last_mouse_pos
			last_mouse_pos = event.position
			camera_yaw = fposmod(camera_yaw - delta_pos.x * 0.4, 360.0)
			camera_pitch = clamp(camera_pitch + delta_pos.y * 0.3, 25.0, 75.0)
			return true
		else:
			update_hover(event.position)

	# 3D Click-to-Move / Interact Raycast Navigation
	if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if diablo_bridge and diablo_bridge.has_method("get_cursor_id"):
				var cid = diablo_bridge.get_cursor_id()
				if cid > 1 and cid < 12:
					if diablo_bridge.has_method("cancel_targeting_cursor"):
						diablo_bridge.cancel_targeting_cursor()
					return true
			var r_hit = find_entity_under_ray(event.position)
			if diablo_bridge and r_hit.tile.x >= 0 and r_hit.tile.y >= 0:
				if diablo_bridge.has_method("send_click_to_tile"):
					diablo_bridge.send_click_to_tile(r_hit.tile.x, r_hit.tile.y, 2)
				return true

		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# 0. Check Held Item (Cursor holding item from inventory) - drop onto playfield
			if diablo_bridge and diablo_bridge.has_method("has_held_item") and diablo_bridge.has_held_item():
				if diablo_bridge.has_method("drop_held_item"):
					diablo_bridge.drop_held_item()
					var hud = _get_hud()
					if hud and hud.tabbed_menu and hud.tabbed_menu.get_node_or_null("MainMargin/MainVBox/ViewsContainer/InventoryPanel"):
						var inv = hud.tabbed_menu.get_node("MainMargin/MainVBox/ViewsContainer/InventoryPanel")
						if inv and inv.has_method("update_inventory"):
							inv.update_inventory()
					return true

			var hit = find_entity_under_ray(event.position)
			if hit.type == "ITEM":
				spawn_click_ring(hit.world_pos, Color(1.0, 0.85, 0.25, 0.95))
				if diablo_bridge:
					if diablo_bridge.has_method("interact_with_item"):
						diablo_bridge.interact_with_item(hit.id, hit.tile.x, hit.tile.y)
					elif diablo_bridge.has_method("send_click_to_tile"):
						diablo_bridge.send_click_to_tile(hit.tile.x, hit.tile.y, 1)
				return true
			elif hit.type == "OBJECT":
				spawn_click_ring(hit.world_pos, Color(0.20, 0.80, 1.0, 0.95))
				if diablo_bridge:
					if diablo_bridge.has_method("interact_with_object"):
						diablo_bridge.interact_with_object(hit.id, hit.tile.x, hit.tile.y)
					elif diablo_bridge.has_method("send_click_to_tile"):
						diablo_bridge.send_click_to_tile(hit.tile.x, hit.tile.y, 1)
				return true
			elif hit.type == "MONSTER":
				spawn_click_ring(hit.world_pos, Color(1.0, 0.22, 0.22, 0.95))
				if diablo_bridge:
					if diablo_bridge.has_method("interact_with_monster"):
						diablo_bridge.interact_with_monster(hit.id)
					elif diablo_bridge.has_method("send_click_to_tile"):
						diablo_bridge.send_click_to_tile(hit.tile.x, hit.tile.y, 1)
				return true
			elif hit.type == "GROUND":
				spawn_click_ring(hit.world_pos, Color(0.95, 0.80, 0.20, 0.85))
				if diablo_bridge:
					if diablo_bridge.has_method("walk_to_tile"):
						diablo_bridge.walk_to_tile(hit.tile.x, hit.tile.y)
					elif diablo_bridge.has_method("send_click_to_tile"):
						diablo_bridge.send_click_to_tile(hit.tile.x, hit.tile.y, 1)
				return true

	return false

# ==============================================================================
# 3D Raycast Hit-Testing & Hover Selection
# ==============================================================================

func get_ray_distance_to_point(ray_origin: Vector3, ray_dir: Vector3, point: Vector3) -> float:
	var v = point - ray_origin
	var t = v.dot(ray_dir)
	if t < 0.0:
		return 999999.0
	var c = ray_origin + ray_dir * t
	return (point - c).length()

func find_entity_under_ray(mouse_pos: Vector2) -> Dictionary:
	var result = {
		"type": "NONE",
		"id": -1,
		"node": null,
		"world_pos": Vector3.ZERO,
		"tile": Vector2i(-1, -1),
		"data": {}
	}
	if camera == null:
		return result

	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)

	var best_type: String = "NONE"
	var best_id: int = -1
	var best_node: Node3D = null
	var best_score: float = 999999.0
	var best_tile: Vector2i = Vector2i(-1, -1)
	var best_pos: Vector3 = Vector3.ZERO
	var best_data: Dictionary = {}

	# 1. Candidate Evaluation: Ground Items
	for i_id in item_instances.keys():
		var inode = item_instances[i_id]
		if not is_instance_valid(inode) or not inode.visible:
			continue
		var ipos = inode.position
		var ray_d = get_ray_distance_to_point(ray_origin, ray_dir, ipos + Vector3(0, 0.35, 0))
		var is_over_label = false
		var screen_d = 999999.0

		if camera.is_inside_tree() and camera.get_viewport():
			if not camera.is_position_behind(ipos + Vector3(0, 0.85, 0)):
				var lscreen = camera.unproject_position(ipos + Vector3(0, 0.85, 0))
				var box_w_val = float(inode.get_meta("box_w", 1.0))
				var half_w = maxf(40.0, box_w_val * 38.0)
				var half_h = 20.0
				var label_rect = Rect2(lscreen.x - half_w, lscreen.y - half_h, half_w * 2.0, half_h * 2.0)
				is_over_label = label_rect.has_point(mouse_pos)

			var iscreen = camera.unproject_position(ipos + Vector3(0, 0.25, 0))
			screen_d = mouse_pos.distance_to(iscreen)

		var hit_item = is_over_label or (ray_d < 0.50) or (screen_d < 36.0)
		if hit_item:
			var score = 0.05 if is_over_label else (min(ray_d, screen_d / 50.0) * 0.85)
			if score < best_score:
				best_score = score
				best_type = "ITEM"
				best_id = i_id
				best_node = inode
				best_pos = ipos
				var tx = inode.get_meta("tile_x", -1)
				var ty = inode.get_meta("tile_y", -1)
				if tx == -1 or ty == -1:
					var t = world_3d_to_tile(ipos)
					tx = int(round(t.x))
					ty = int(round(t.y))
				best_tile = Vector2i(tx, ty)
				best_data = {
					"id": i_id,
					"name": inode.get_meta("item_name", ""),
					"quality": inode.get_meta("quality", 0),
					"quality_name": inode.get_meta("quality_name", "NORMAL"),
					"item_type": inode.get_meta("item_type", 0),
					"type_desc": inode.get_meta("type_desc", "Item"),
					"min_dam": inode.get_meta("min_dam", 0),
					"max_dam": inode.get_meta("max_dam", 0),
					"ac": inode.get_meta("ac", 0),
					"durability": inode.get_meta("durability", 0),
					"max_dur": inode.get_meta("max_dur", 0),
					"req_str": inode.get_meta("req_str", 0),
					"req_dex": inode.get_meta("req_dex", 0),
					"req_mag": inode.get_meta("req_mag", 0),
					"value": inode.get_meta("value", 0),
					"magic_desc": inode.get_meta("magic_desc", "")
				}

	# 2. Candidate Evaluation: Monsters
	for m_id in monster_instances.keys():
		var mnode = monster_instances[m_id]
		if not is_instance_valid(mnode) or not mnode.visible:
			continue
		var mctrl = mnode.get_node_or_null("Monster3DController")
		if mctrl and mctrl.is_dead:
			continue
		var mpos = mnode.position
		var ray_d = get_ray_distance_to_point(ray_origin, ray_dir, mpos + Vector3(0, 0.90, 0))
		var screen_d = 999999.0
		if camera.is_inside_tree() and camera.get_viewport():
			var mscreen = camera.unproject_position(mpos + Vector3(0, 0.9, 0))
			screen_d = mouse_pos.distance_to(mscreen)

		if ray_d < 0.65 or screen_d < 44.0:
			var score = min(ray_d, screen_d / 50.0)
			if score < best_score:
				best_score = score
				best_type = "MONSTER"
				best_id = m_id
				best_node = mnode
				best_pos = mpos
				var mtx = mnode.get_meta("tile_x", -1)
				var mty = mnode.get_meta("tile_y", -1)
				if mtx == -1 or mty == -1:
					var mt = world_3d_to_tile(mpos)
					mtx = int(round(mt.x))
					mty = int(round(mt.y))
				best_tile = Vector2i(mtx, mty)
				best_data = {
					"name": mnode.get_meta("name", "Monster"),
					"id": m_id
				}

	# 3. Candidate Evaluation: Interactive Props & Doors
	for p_id in prop_instances.keys():
		var pnode = prop_instances[p_id]
		if not is_instance_valid(pnode) or not pnode.visible:
			continue
		var ppos = pnode.position
		var ray_d = get_ray_distance_to_point(ray_origin, ray_dir, ppos + Vector3(0, 0.70, 0))
		var screen_d = 999999.0
		if camera.is_inside_tree() and camera.get_viewport():
			var pscreen = camera.unproject_position(ppos + Vector3(0, 0.7, 0))
			screen_d = mouse_pos.distance_to(pscreen)

		if ray_d < 0.70 or screen_d < 40.0:
			var score = min(ray_d, screen_d / 50.0)
			if score < best_score:
				best_score = score
				best_type = "OBJECT"
				best_id = p_id
				best_node = pnode
				best_pos = ppos
				var ptx = pnode.get_meta("tile_x", -1)
				var pty = pnode.get_meta("tile_y", -1)
				if ptx == -1 or pty == -1:
					var pt = world_3d_to_tile(ppos)
					ptx = int(round(pt.x))
					pty = int(round(pt.y))
				best_tile = Vector2i(ptx, pty)
				best_data = {
					"type": pnode.get_meta("prop_type", 0)
				}

	# 4. Check Ground Plane & Door Tiles Intersection
	var ground_plane = Plane(Vector3.UP, 0.0)
	var ground_hit = ground_plane.intersects_ray(ray_origin, ray_dir)
	var g_tile = Vector2i(-1, -1)
	if ground_hit != null:
		var t = world_3d_to_tile(ground_hit)
		g_tile = Vector2i(clampi(int(round(t.x)), 0, 111), clampi(int(round(t.y)), 0, 111))

	# If no entity was hit directly, check if ground hit tile is a door:
	if best_type == "NONE" and g_tile.x >= 0 and g_tile.y >= 0:
		for p_id in prop_instances.keys():
			var pnode = prop_instances[p_id]
			if is_instance_valid(pnode) and pnode.visible:
				var ptx = pnode.get_meta("tile_x", -999)
				var pty = pnode.get_meta("tile_y", -999)
				if ptx == g_tile.x and pty == g_tile.y:
					var p_type = pnode.get_meta("prop_type", 0)
					if p_type in [1, 2, 42, 43, 74, 75, 83, 84] or pnode.get_meta("is_door", false):
						best_type = "OBJECT"
						best_id = p_id
						best_node = pnode
						best_pos = pnode.position
						best_tile = g_tile
						best_data = {"type": p_type, "is_door": true}
						break

	if best_type != "NONE":
		result.type = best_type
		result.id = best_id
		result.node = best_node
		result.world_pos = best_pos
		result.tile = best_tile
		result.data = best_data
		return result

	# 5. Ground Walk
	if ground_hit != null:
		result.type = "GROUND"
		result.world_pos = ground_hit
		result.tile = g_tile
		return result

	return result

func update_hover(mouse_pos: Vector2) -> void:
	if not is_sandbox_active or camera == null:
		return

	var hit = find_entity_under_ray(mouse_pos)
	hovered_entity = hit
	var hud = _get_hud()

	# 1. Item Hover Highlight & Diablo IV Tooltip Card
	if hit.type == "ITEM" and is_instance_valid(hit.node):
		if last_hovered_item != hit.node:
			if is_instance_valid(last_hovered_item):
				_reset_item_hover(last_hovered_item)
			last_hovered_item = hit.node
			_set_item_hover(hit.node, true)
		if hud and hud.has_method("show_ground_item_tooltip"):
			var anchor_screen = mouse_pos
			if camera:
				var label_node = hit.node.get_node_or_null("LabelRoot")
				if label_node:
					anchor_screen = camera.unproject_position(label_node.global_position + Vector3(0, 0.15, 0))
				else:
					anchor_screen = camera.unproject_position(hit.node.global_position + Vector3(0, 0.85, 0))
			hud.show_ground_item_tooltip(hit.data, anchor_screen)
	else:
		if is_instance_valid(last_hovered_item):
			_reset_item_hover(last_hovered_item)
			last_hovered_item = null
		if hud and hud.has_method("hide_ground_item_tooltip"):
			hud.hide_ground_item_tooltip()

	# 2. Monster Hover HUD Health Bar
	if hit.type == "MONSTER":
		if hud:
			if hud.has_method("set_target_monster"):
				hud.set_target_monster(hit.id)
			elif hud.get("enemy_health_bar") != null:
				var e_bar = hud.enemy_health_bar as Control
				if e_bar:
					e_bar.visible = true
					var n_lbl = hud.get("enemy_name_label") as Label
					if n_lbl:
						n_lbl.text = hit.data.get("name", "Monster")

func _set_item_hover(node: Node3D, hover: bool) -> void:
	if not is_instance_valid(node):
		return
	var l_root = node.get_node_or_null("LabelRoot") as Node3D
	if l_root:
		# Constant scale: no jarring scale jump, larger comfortable size is always preserved (per user spec)
		l_root.scale = Vector3.ONE
		var b_quad = l_root.get_node_or_null("LabelBorder") as MeshInstance3D
		if b_quad and b_quad.material_override is StandardMaterial3D:
			var mat = b_quad.material_override as StandardMaterial3D
			if hover:
				mat.albedo_color = Color(1.0, 0.95, 0.40, 1.0)
			else:
				var q = int(node.get_meta("quality", 0))
				if q == 1: mat.albedo_color = Color(0.30, 0.65, 1.0, 0.95)
				elif q == 2: mat.albedo_color = Color(1.0, 0.82, 0.22, 0.95)
				else: mat.albedo_color = Color(0.75, 0.75, 0.78, 0.90)

	var lbl = node.get_node_or_null("LabelRoot/ItemLabel") as Label3D
	if lbl == null:
		lbl = node.get_node_or_null("ItemLabel") as Label3D
	if lbl:
		lbl.scale = Vector3.ONE
		lbl.outline_modulate = Color(1.0, 1.0, 1.0, 0.98) if hover else Color(0.0, 0.0, 0.0, 0.95)

func _reset_item_hover(node: Node3D) -> void:
	_set_item_hover(node, false)

# ==============================================================================
# Native Combat Events & Floating Combat Text (Task 5.2)
# ==============================================================================

func process_combat_events(delta: float) -> void:
	if not diablo_bridge or not diablo_bridge.has_method("poll_combat_events"):
		return
	var events: Array = diablo_bridge.poll_combat_events()
	for ev in events:
		var ev_type = int(ev.get("type", 0))
		var tid = int(ev.get("target_id", -1))
		var sid = int(ev.get("source_id", -1))
		var tile = ev.get("tile", Vector2i.ZERO)
		var dam = int(ev.get("damage", 0))
		var cur_hp = int(ev.get("target_hp", 0))
		var max_hp = int(ev.get("target_max_hp", 1))
		var is_crit = bool(ev.get("is_crit", false))
		var exp_g = int(ev.get("exp_gained", 0))
		var new_lvl = int(ev.get("new_level", 0))

		var world_pos = tile_to_world_3d(float(tile.x), float(tile.y))
		if ev_type == 1 or ev_type == 3: # Monster target
			if monster_instances.has(tid) and is_instance_valid(monster_instances[tid]):
				world_pos = monster_instances[tid].global_position
		elif player_root:
			world_pos = player_root.global_position

		match ev_type:
			1: # DAMAGE_TO_MONSTER
				var txt = ("CRIT -" if is_crit else "-") + str(dam) + ("!" if is_crit else "")
				if fct_manager:
					fct_manager.spawn_fct(world_pos, txt, ev_type, is_crit)

				if is_crit:
					camera_trauma = minf(camera_trauma + 0.35, 1.0)

				if monster_instances.has(tid) and is_instance_valid(monster_instances[tid]):
					var mnode = monster_instances[tid]
					flash_entity(mnode, Color(2.5, 0.45, 0.45, 1.0))

					# Instant overhead HP bar update
					var hp_fg = mnode.get_node_or_null("HPRoot/HPBar") as MeshInstance3D
					if hp_fg and hp_fg.mesh is QuadMesh:
						var pct = clampf(float(cur_hp) / float(maxi(1, max_hp)), 0.0, 1.0)
						(hp_fg.mesh as QuadMesh).size.x = 0.80 * pct
						hp_fg.position.x = -0.40 * (1.0 - pct)

					# Monster flinch state
					var mc = mnode.get_node_or_null("Monster3DController")
					if mc and mc.has_method("set_action"):
						mc.set_action("HIT")

					# Spawn blood or bone particle burst
					var mname = str(mnode.get_meta("name", "")).to_lower()
					var is_undead = mname.contains("skeleton") or mname.contains("bone") or mname.contains("zombie")
					var p_scene = bone_shards_scene if is_undead else blood_splatter_scene
					if p_scene:
						var p_inst = p_scene.instantiate()
						p_inst.position = world_pos + Vector3(0, 0.75, 0)
						p_inst.scale = Vector3.ONE * (1.4 if is_crit else 1.0)
						add_child(p_inst)

			2: # DAMAGE_TO_PLAYER
				if fct_manager:
					fct_manager.spawn_fct(world_pos, "-" + str(dam), ev_type, false)

				camera_trauma = minf(camera_trauma + 0.45, 1.0)
				if player_root:
					flash_entity(player_root, Color(2.4, 0.4, 0.4, 1.0))
				if warrior_controller and warrior_controller.has_method("set_action"):
					warrior_controller.set_action("HIT")

				if blood_splatter_scene:
					var p_inst = blood_splatter_scene.instantiate()
					p_inst.position = world_pos + Vector3(0, 0.8, 0)
					add_child(p_inst)

			3: # MONSTER_DEATH
				if exp_g > 0 and fct_manager:
					fct_manager.spawn_fct(world_pos, "+" + str(exp_g) + " XP", ev_type, false)

				if monster_instances.has(tid) and is_instance_valid(monster_instances[tid]):
					var mnode = monster_instances[tid]
					var mc = mnode.get_node_or_null("Monster3DController")
					if mc and mc.has_method("trigger_death"):
						mc.trigger_death()

			5: # PLAYER_BLOCK
				if fct_manager:
					fct_manager.spawn_fct(world_pos, "BLOCKED", ev_type, false)
				if warrior_controller and warrior_controller.has_method("set_action"):
					warrior_controller.set_action("BLOCK")
				if torch_sparks_scene:
					var sparks = torch_sparks_scene.instantiate()
					sparks.position = world_pos + Vector3(0, 0.7, 0)
					add_child(sparks)

			6: # COMBAT_MISS
				if fct_manager:
					fct_manager.spawn_fct(world_pos, "MISS", ev_type, false)

			7: # PLAYER_LEVEL_UP
				if fct_manager:
					fct_manager.spawn_fct(world_pos, "★ LEVEL UP! (Lvl " + str(new_lvl) + ") ★", ev_type, false)
				camera_trauma = minf(camera_trauma + 0.5, 1.0)
				if torch_sparks_scene:
					var sparks = torch_sparks_scene.instantiate()
					sparks.position = world_pos + Vector3(0, 1.2, 0)
					sparks.scale = Vector3.ONE * 2.0
					add_child(sparks)

func flash_entity(node: Node3D, flash_col: Color) -> void:
	if not is_instance_valid(node):
		return
	var sprite: Sprite3D = null
	if node == player_root:
		sprite = player_sprite
	else:
		sprite = node.get_node_or_null("MonsterSprite3D") as Sprite3D

	if sprite:
		if not flashing_entities.has(node):
			flashing_entities[node] = {
				"timer": 0.08,
				"sprite": sprite,
				"orig": sprite.modulate
			}
		else:
			flashing_entities[node]["timer"] = 0.08
		sprite.modulate = flash_col

func update_flashing(delta: float) -> void:
	if flashing_entities.is_empty():
		return
	var keys = flashing_entities.keys()
	for node in keys:
		var data = flashing_entities[node]
		data.timer -= delta
		if data.timer <= 0.0:
			if is_instance_valid(data.sprite):
				data.sprite.modulate = data.orig
			flashing_entities.erase(node)

func update_visual_effects() -> void:
	if not diablo_bridge or not diablo_bridge.has_method("poll_visual_events") or effects_root == null:
		return

	var events: Array = diablo_bridge.poll_visual_events()
	if events.is_empty():
		return

	# Performance guard: cap active particle nodes to 12 max to maintain rock-solid 144 FPS
	var active_vfx = effects_root.get_child_count()
	if active_vfx >= 12:
		return
	for ev in events:
		var ev_type = int(ev.get("type", 0))
		if ev_type <= 0 or not ev.has("tile"):
			continue
		var tile = ev.get("tile", Vector2i(-1, -1))
		if tile.x < 0 or tile.y < 0:
			continue

		var wpos = tile_to_world_3d(float(tile.x), float(tile.y))
		wpos.y = 0.75 # Standard character hit center height
		var ev_scale = clampf(float(ev.get("intensity", 1.0)), 0.8, 2.0)
		var p_inst: GPUParticles3D = null

		if ev_type == 1: # Blood Splatter
			p_inst = blood_splatter_scene.instantiate()
		elif ev_type == 2: # Bone Shards
			p_inst = bone_shards_scene.instantiate()
		elif ev_type == 3: # Fireball / Spell Explosion
			p_inst = fireball_explosion_scene.instantiate()
		elif ev_type == 4: # Hit sparks / deflection
			p_inst = torch_sparks_scene.instantiate()
			p_inst.amount = 12
			p_inst.one_shot = true
			p_inst.explosiveness = 0.9
			var timer = get_tree().create_timer(p_inst.lifetime + 0.1)
			timer.timeout.connect(p_inst.queue_free)

		if p_inst:
			p_inst.position = wpos
			p_inst.scale = Vector3(ev_scale, ev_scale, ev_scale)
			effects_root.add_child(p_inst)

			# On heavy hit (intensity >= 1.5), add secondary burst
			if ev_type == 1 and ev_scale >= 1.5:
				var extra_bld = blood_splatter_scene.instantiate()
				extra_bld.position = wpos + Vector3(randf_range(-0.15, 0.15), randf_range(-0.1, 0.1), randf_range(-0.15, 0.15))
				extra_bld.scale = Vector3(ev_scale * 1.15, ev_scale * 1.15, ev_scale * 1.15)
				effects_root.add_child(extra_bld)
			elif ev_type == 2 and ev_scale >= 1.5:
				var extra_bone = bone_shards_scene.instantiate()
				extra_bone.position = wpos + Vector3(randf_range(-0.15, 0.15), randf_range(-0.1, 0.1), randf_range(-0.15, 0.15))
				extra_bone.scale = Vector3(ev_scale * 1.1, ev_scale * 1.1, ev_scale * 1.1)
				effects_root.add_child(extra_bone)
