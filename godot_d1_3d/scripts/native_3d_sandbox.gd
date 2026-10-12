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
var main_receiver = null
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
var piece_is_floor_cache: Dictionary = {} # pid (int) -> bool

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

# --- Scenery Billboards (Town Buildings & Trees, Dungeon Walls & Arches) ---
var town_scenery_root: Node3D = null
var town_scenery_nodes: Dictionary = {}  # tile_idx (int) -> Sprite3D
var special_scenery_nodes: Dictionary = {} # tile_idx (int) -> Sprite3D
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

# --- Monster Entities ---
var monsters_root: Node3D
var monster_instances: Dictionary = {}    # id (int) -> Node3D
var monster_textures: Dictionary = {}     # id (int) -> ImageTexture
var monster_last_frame: Dictionary = {}   # id (int) -> int
var monster_last_dir: Dictionary = {}     # id (int) -> int
var last_gamma_value: int = -1

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

# --- Waypoint / Click Feedback ---
var click_marker: MeshInstance3D
var click_fade: float = 0.0

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
		return not diablo_bridge.is_level_loading()
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
	env.glow_enabled = true
	env.glow_intensity = 0.50
	env.glow_bloom = 0.20
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.005
	env.volumetric_fog_albedo = Color(0.35, 0.38, 0.48, 1.0)

	# 2. Directional Key Light
	dir_light = DirectionalLight3D.new()
	dir_light.name = "SandboxSunlight"
	dir_light.transform = Transform3D(
		Basis().rotated(Vector3.UP, deg_to_rad(-35.0)).rotated(Vector3.RIGHT, deg_to_rad(-55.0)),
		Vector3(0, 15, 0)
	)
	dir_light.light_color = Color(0.70, 0.80, 0.98, 1.0)
	dir_light.light_energy = 0.50
	dir_light.shadow_enabled = true
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

	# 7. Click Marker
	setup_click_marker()

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
	load_dungeon_piece_types()

func load_dungeon_piece_types():
	var json_path = "res://assets/data/dungeon_piece_types.json"
	if not FileAccess.file_exists(json_path):
		return
	var f = FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		return
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
	print("[Native 3D Sandbox] Loaded dungeon piece classifications for %d themes." % dungeon_piece_floors.size())

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

# ==============================================================================
# Modular 3D Dungeon Kit Pipeline
# ==============================================================================

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
	# Expand diamond boundary slightly by 2.5% (+1.875cm) so adjacent tiles overlap and eliminate all black background seams
	var ts_v = ts * 1.025
	var skirt_h = 0.12

	# Exact bijective diamond geometry matching Diablo 1's 2:1 isometric tile coordinates:
	# Inset UVs safely (3.5 texels) into the solid paver core away from transparent edges:
	var uv_dx = 3.5 / 256.0
	var uv_dy = 3.5 / 128.0

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

func get_floor_material(piece_id: int, cur_level: int) -> StandardMaterial3D:
	var f_key = "%d_%d" % [cur_level, piece_id]
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

	if is_dungeon:
		var pbr_folder = "res://assets/dungeon_pbr_%s_4x" % theme
		var alb_p = "%s/albedo/piece_%d.png" % [pbr_folder, piece_id]
		var norm_p = "%s/normal/piece_%d_n.png" % [pbr_folder, piece_id]
		var spec_p = "%s/specular/piece_%d_s.png" % [pbr_folder, piece_id]

		if not FileAccess.file_exists(alb_p) and theme == "cathedral":
			var fb_folder = "res://assets/dungeon_pbr_4x"
			if FileAccess.file_exists("%s/albedo/piece_%d.png" % [fb_folder, piece_id]):
				pbr_folder = fb_folder
				alb_p = "%s/albedo/piece_%d.png" % [pbr_folder, piece_id]
				norm_p = "%s/normal/piece_%d_n.png" % [pbr_folder, piece_id]
				spec_p = "%s/specular/piece_%d_s.png" % [pbr_folder, piece_id]

		if FileAccess.file_exists(alb_p):
			var img = Image.load_from_file(ProjectSettings.globalize_path(alb_p))
			if img and not img.is_empty():
				var tw = img.get_width()
				var th = img.get_height()
				var floor_h = int(round(float(tw) * 0.5))
				if th > floor_h:
					img = img.get_region(Rect2i(0, th - floor_h, tw, floor_h))
				img.generate_mipmaps()
				alb_tex = ImageTexture.create_from_image(img)

		if FileAccess.file_exists(norm_p):
			var n_img = Image.load_from_file(ProjectSettings.globalize_path(norm_p))
			if n_img and not n_img.is_empty():
				var n_tw = n_img.get_width()
				var n_th = n_img.get_height()
				var n_floor_h = int(round(float(n_tw) * 0.5))
				if n_th > n_floor_h:
					n_img = n_img.get_region(Rect2i(0, n_th - n_floor_h, n_tw, n_floor_h))
				n_img.generate_mipmaps()
				norm_tex = ImageTexture.create_from_image(n_img)

		if FileAccess.file_exists(spec_p):
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
					floor_img.generate_mipmaps()
					alb_tex = ImageTexture.create_from_image(floor_img)
					if not is_dungeon:
						base_floor_texture_cache[f_key] = alb_tex

	if alb_tex:
		mat.albedo_texture = alb_tex
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		# Town uses warm natural daylight; dungeons use balanced natural reflectance
		mat.albedo_color = Color(1.10, 1.08, 1.02) if cur_level == 0 else Color(1.12, 1.10, 1.08)
	else:
		mat.albedo_color = Color(0.25, 0.35, 0.18) if cur_level == 0 else Color(0.85, 0.82, 0.78)

	if norm_tex:
		mat.normal_enabled = true
		mat.normal_texture = norm_tex
		mat.normal_scale = 0.90
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	floor_material_cache[f_key] = mat
	return mat

func get_scenery_piece_texture(piece_id: int, cur_level: int) -> Texture2D:
	var s_key = "%d_%d" % [cur_level, piece_id]
	if scenery_texture_cache.has(s_key):
		return scenery_texture_cache[s_key]

	var tex: Texture2D = null
	var is_dungeon = (cur_level > 0)

	if is_dungeon:
		var theme = get_theme_name(cur_level)
		var pbr_folder = "res://assets/dungeon_pbr_%s_4x" % theme
		var alb_p = "%s/albedo/piece_%d.png" % [pbr_folder, piece_id]

		if not FileAccess.file_exists(alb_p) and theme == "cathedral":
			var fb_folder = "res://assets/dungeon_pbr_4x"
			if FileAccess.file_exists("%s/albedo/piece_%d.png" % [fb_folder, piece_id]):
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
	var spec_key = "%d_%d" % [cur_level, special_id]
	if scenery_special_cache.has(spec_key):
		return scenery_special_cache[spec_key]

	# Strictly Cathedral only (GEMINI.md Rule #2: Special CEL Archways Gating)
	if cur_level < 1 or cur_level > 4:
		return null

	var tex: Texture2D = null
	var alb_p = "res://assets/dungeon_pbr_cathedral_4x/albedo/special_%d.png" % special_id
	if not FileAccess.file_exists(alb_p):
		alb_p = "res://assets/dungeon_pbr_4x/albedo/special_%d.png" % special_id

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

	# 0.6 Dungeon Base Continuous Stone Foundation Plane (Eliminates black void holes beneath Dungeons)
	dungeon_base_ground = MeshInstance3D.new()
	dungeon_base_ground.name = "DungeonBaseGroundPlane"
	var dp_mesh = PlaneMesh.new()
	dp_mesh.size = Vector2(240.0, 240.0)
	dungeon_base_ground.mesh = dp_mesh
	dungeon_base_ground.position = Vector3(0.0, -0.02, 84.0)
	var dg_mat = StandardMaterial3D.new()
	dg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	dg_mat.roughness = 0.85
	dg_mat.metallic = 0.04
	dg_mat.albedo_color = Color(0.12, 0.12, 0.14)
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
	var arch_mesh = get_or_load_mesh("res://assets/models/dungeon/arch_open.glb")

	# For Caves (L9..12), use broken / organic rock walls instead of straight drywall
	if theme == "caves":
		var wall_broken = get_or_load_mesh("res://assets/models/dungeon/wall_broken.glb")
		if wall_broken:
			wall_ns_mesh = wall_broken
			wall_ew_mesh = wall_broken

	var floor_mat = get_pbr_material_for_theme(theme, false)
	var wall_mat = get_pbr_material_for_theme(theme, true)

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
				var stone_alb = "res://assets/dungeon_pbr_%s_4x/albedo/piece_1.png" % theme
				var stone_norm = "res://assets/dungeon_pbr_%s_4x/normal/piece_1_n.png" % theme
				if ResourceLoader.exists(stone_alb):
					base_mat.albedo_texture = load(stone_alb)
				elif FileAccess.file_exists(ProjectSettings.globalize_path(stone_alb)):
					var img = Image.load_from_file(ProjectSettings.globalize_path(stone_alb))
					if img and not img.is_empty():
						img.generate_mipmaps()
						base_mat.albedo_texture = ImageTexture.create_from_image(img)
				if ResourceLoader.exists(stone_norm):
					base_mat.normal_enabled = true
					base_mat.normal_texture = load(stone_norm)
				elif FileAccess.file_exists(ProjectSettings.globalize_path(stone_norm)):
					var nimg = Image.load_from_file(ProjectSettings.globalize_path(stone_norm))
					if nimg and not nimg.is_empty():
						nimg.generate_mipmaps()
						base_mat.normal_enabled = true
						base_mat.normal_texture = ImageTexture.create_from_image(nimg)
				base_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				base_mat.uv1_scale = Vector3(160.0, 160.0, 1.0)
				base_mat.albedo_color = Color(0.70, 0.70, 0.72)

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
			dir_light.shadow_enabled = true
			dir_light.directional_shadow_max_distance = 40.0
			dir_light.shadow_bias = 0.05

			if theme == "cathedral":
				dir_light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
				dir_light.light_color = Color(0.60, 0.70, 0.88, 1.0)
				dir_light.light_energy = 0.55
			elif theme == "catacombs":
				dir_light.rotation_degrees = Vector3(-50.0, -40.0, 0.0)
				dir_light.light_color = Color(0.48, 0.58, 0.44, 1.0)
				dir_light.light_energy = 0.45
			elif theme == "caves":
				# Upward/diagonal reflection from molten magma flows below
				dir_light.rotation_degrees = Vector3(-35.0, -20.0, 0.0)
				dir_light.light_color = Color(0.90, 0.45, 0.18, 1.0)
				dir_light.light_energy = 0.65
			elif theme == "hell":
				# Fierce infernal brimstone downpour
				dir_light.rotation_degrees = Vector3(-60.0, -30.0, 0.0)
				dir_light.light_color = Color(1.0, 0.28, 0.12, 1.0)
				dir_light.light_energy = 0.75

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
	monster_last_frame.clear()
	monster_last_dir.clear()

	# 5. Clear all ground items
	if items_root:
		for c in items_root.get_children():
			c.queue_free()
	item_instances.clear()
	item_textures.clear()
	item_is_hd_cache.clear()

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
			if o_type in [1, 2, 148, 149, 180, 181, 211, 212]:
				door_tiles[pos_k] = obj

	var floor_piece_transforms: Dictionary = {} # piece_id (int) -> Array[Transform3D]
	var total_floor_count = 0

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

			# 1. Floor diamond: All tiles have a procedural floor diamond on the ground plane
			if not floor_piece_transforms.has(pid):
				floor_piece_transforms[pid] = []
			floor_piece_transforms[pid].append(f_tf)
			total_floor_count += 1

			# Extract the authentic base paver region from row 0 for the foundation floor diamond
			if is_wall_scenery and not base_floor_texture_cache.has(pid):
				var img = tex.get_image()
				if img and not img.is_empty():
					var floor_rect = Rect2i(0, th - floor_h, tw, floor_h)
					var floor_img = img.get_region(floor_rect)
					floor_img.generate_mipmaps()
					base_floor_texture_cache[pid] = ImageTexture.create_from_image(floor_img)

			# 2. Scenery Billboard Sprite (Town Buildings & Trees, Dungeon Walls, Columns & Bookshelves)
			if is_wall_scenery and not is_door_tile:
				var spr = Sprite3D.new()
				spr.name = "Scenery_%d_%d" % [x, y]
				spr.texture = tex
				spr.centered = true
				spr.billboard = BaseMaterial3D.BILLBOARD_DISABLED
				spr.rotation.x = deg_to_rad(-camera_pitch)
				spr.rotation.y = deg_to_rad(camera_yaw)
				spr.shaded = false
				spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
				spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				var p_scale = 1.50 / float(tw)
				spr.pixel_size = p_scale
				spr.offset = Vector2(0.0, float(th) * 0.5)
				spr.position = Vector3(wpos.x, 0.01, wpos.z)
				# Unshaded healthy illumination per Rule #4 in GEMINI.md
				spr.modulate = Color(1.48, 1.45, 1.38) if (cur_level == 0) else Color(1.48, 1.44, 1.36)
				town_scenery_root.add_child(spr)
				town_scenery_nodes[idx] = spr

			# 3. Special CEL Archways & Column Tops (Cathedral only per GEMINI.md Rule #2)
			var special_id = special_grid[idx] if idx < special_grid.size() else 0
			if special_id > 0 and is_cathedral and (solidity.size() < 112 * 112 or solidity[idx] != 0):
				var arch_tex = get_scenery_special_texture(special_id, cur_level)
				if arch_tex:
					var aspr = Sprite3D.new()
					aspr.name = "Special_%d_%d" % [x, y]
					aspr.texture = arch_tex
					aspr.centered = true
					aspr.billboard = BaseMaterial3D.BILLBOARD_DISABLED
					aspr.rotation.x = deg_to_rad(-camera_pitch)
					aspr.rotation.y = deg_to_rad(camera_yaw)
					aspr.shaded = false
					aspr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
					aspr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
					aspr.pixel_size = 1.50 / float(arch_tex.get_width())
					aspr.offset = Vector2(0.0, float(arch_tex.get_height()) * 0.5)
					aspr.position = Vector3(wpos.x, 0.02, wpos.z)
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

	# Modular 3D cubes completely disabled in favor of authentic billboard sprites!
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

	print("[Native 3D Sandbox] Reconstructed 3D world (L%d): %d floors (%d unique pieces), %d scenery sprites, %d special archways" % [
		cur_level, total_floor_count, floor_piece_transforms.size(),
		town_scenery_nodes.size(), special_scenery_nodes.size()
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
	player_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	player_root.add_child(player_sprite)

	# Soft Ground Contact Shadow Disc
	var shadow_disc = MeshInstance3D.new()
	shadow_disc.name = "PlayerShadowDisc"
	var disc_mesh = CylinderMesh.new()
	disc_mesh.top_radius = 0.38
	disc_mesh.bottom_radius = 0.42
	disc_mesh.height = 0.01
	shadow_disc.mesh = disc_mesh
	shadow_disc.position.y = 0.01
	var s_mat = StandardMaterial3D.new()
	s_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.55)
	s_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_disc.material_override = s_mat
	player_root.add_child(shadow_disc)

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

func update_player_entity(delta: float):
	var p_data = diablo_bridge.get_player_continuous_pos()
	var px = p_data.get("pos_x", 25.0)
	var py = p_data.get("pos_y", 25.0)
	var dir = p_data.get("dir", 0)
	var anim_frame = p_data.get("anim_frame", -1)

	player_target_pos = tile_to_world_3d(px, py)
	player_root.position = player_root.position.lerp(player_target_pos, delta * 14.0)

	player_arrow.rotation_degrees.y = float(dir) * 45.0

	# Fetch authentic animated player sprite
	if diablo_bridge and diablo_bridge.has_method("get_player_sprite_data"):
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
				player_sprite.pixel_size = PIXEL_SIZE_1X
				player_sprite.offset = Vector2(0, float(sh) * 0.5)

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
		var node = get_or_create_monster_node(m_id)
		node.visible = true

		var mx = m.get("pos_x", 0.0)
		var my = m.get("pos_y", 0.0)
		var dir = m.get("dir", 0)
		var anim_frame = m.get("anim_frame", -1)
		var hp = m.get("hp", 1)
		var max_hp = max(1, m.get("max_hp", 1))
		var m_name = m.get("name", "Monster")

		var target_pos = tile_to_world_3d(mx, my)
		if delta <= 0.0:
			node.position = target_pos
		else:
			node.position = node.position.lerp(target_pos, delta * 12.0)

		# Update Monster Sprite3D
		var m_sprite = node.get_node_or_null("MonsterSprite3D") as Sprite3D
		var last_f = monster_last_frame.get(m_id, -999)
		var last_d = monster_last_dir.get(m_id, -999)
		var cur_tex: ImageTexture = monster_textures.get(m_id, null)

		if diablo_bridge and diablo_bridge.has_method("get_monster_sprite_data"):
			if anim_frame != last_f or dir != last_d or cur_tex == null:
				monster_last_frame[m_id] = anim_frame
				monster_last_dir[m_id] = dir
				var ms_data: Dictionary = diablo_bridge.get_monster_sprite_data(m_id)
				var mw = ms_data.get("width", 0)
				var mh = ms_data.get("height", 0)
				var m_rgba: PackedByteArray = ms_data.get("rgba", PackedByteArray())
				if mw > 0 and mh > 0 and m_rgba.size() == mw * mh * 4:
					var m_img = Image.create_from_data(mw, mh, false, Image.FORMAT_RGBA8, m_rgba)
					m_img.generate_mipmaps()
					if cur_tex == null or cur_tex.get_width() != mw or cur_tex.get_height() != mh:
						cur_tex = ImageTexture.create_from_image(m_img)
						monster_textures[m_id] = cur_tex
						if m_sprite:
							m_sprite.texture = cur_tex
					else:
						cur_tex.update(m_img)

					if m_sprite:
						m_sprite.pixel_size = PIXEL_SIZE_1X
						m_sprite.offset = Vector2(0, float(mh) * 0.5)

					# Dynamic HP bar & name label height
					var m_scale = m_sprite.pixel_size if m_sprite else PIXEL_SIZE_1X
					var head_y = float(mh) * m_scale + 0.20
					var hp_r = node.get_node_or_null("HPRoot")
					if hp_r:
						hp_r.position.y = head_y
					var n_lbl = node.get_node_or_null("NameLabel")
					if n_lbl:
						n_lbl.position.y = head_y + 0.22

		var cur_lvl = diablo_bridge.get_current_level() if diablo_bridge.has_method("get_current_level") else 1
		var is_town = (cur_lvl == 0)

		# Update HP Bar (Dungeon monsters only; hide on friendly Town NPCs)
		var hp_r = node.get_node_or_null("HPRoot")
		if hp_r:
			hp_r.visible = not is_town
		var hp_bar = node.get_node_or_null("HPRoot/HPBar") as MeshInstance3D
		if hp_bar and not is_town:
			var ratio = clamp(float(hp) / float(max_hp), 0.0, 1.0)
			hp_bar.scale.x = max(0.01, ratio)
			var fg_mat = hp_bar.material_override as StandardMaterial3D
			if fg_mat:
				if ratio > 0.5:
					fg_mat.albedo_color = Color(0.2, 0.85, 0.25).lerp(Color(0.9, 0.8, 0.1), (1.0 - ratio) * 2.0)
				else:
					fg_mat.albedo_color = Color(0.9, 0.8, 0.1).lerp(Color(0.9, 0.15, 0.15), (0.5 - ratio) * 2.0)

		# Update Name Label (Dungeon monsters only; hide on friendly Town NPCs)
		var label = node.get_node_or_null("NameLabel") as Label3D
		if label:
			label.visible = not is_town
			if not is_town:
				label.text = "%s [%d/%d]" % [m_name, hp, max_hp]

	# Hide inactive monsters
	for id in monster_instances.keys():
		if not seen_ids.has(id):
			monster_instances[id].visible = false

func get_or_create_monster_node(m_id: int) -> Node3D:
	if monster_instances.has(m_id):
		return monster_instances[m_id]

	var node = Node3D.new()
	node.name = "Monster_%d" % m_id

	# 3D Billboard Sprite (Unshaded with healthy illumination & ground contact shadow)
	var sprite = Sprite3D.new()
	sprite.name = "MonsterSprite3D"
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.shaded = false
	sprite.pixel_size = PIXEL_SIZE_1X
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	sprite.modulate = Color(1.38, 1.35, 1.28)
	node.add_child(sprite)

	# Soft Ground Contact Shadow Disc
	var shadow_disc = MeshInstance3D.new()
	shadow_disc.name = "MonsterShadowDisc"
	var disc_mesh = CylinderMesh.new()
	disc_mesh.top_radius = 0.32
	disc_mesh.bottom_radius = 0.36
	disc_mesh.height = 0.01
	shadow_disc.mesh = disc_mesh
	shadow_disc.position.y = 0.01
	var s_mat = StandardMaterial3D.new()
	s_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.50)
	s_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_disc.material_override = s_mat
	node.add_child(shadow_disc)

	# Floating 3D Name Label
	var label = Label3D.new()
	label.name = "NameLabel"
	label.position = Vector3(0, 1.85, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 17
	label.modulate = Color(1.0, 0.90, 0.55)
	label.outline_render_priority = 1
	label.outline_size = 4
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	node.add_child(label)

	# Floating 3D HP Bar
	var hp_root = Node3D.new()
	hp_root.name = "HPRoot"
	hp_root.position = Vector3(0, 1.60, 0)

	var hp_bg = MeshInstance3D.new()
	var q_bg = QuadMesh.new()
	q_bg.size = Vector2(0.82, 0.08)
	hp_bg.mesh = q_bg
	var bg_mat = StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.albedo_color = Color(0.08, 0.08, 0.08, 0.85)
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg_mat.no_depth_test = true
	hp_bg.material_override = bg_mat
	hp_root.add_child(hp_bg)

	var hp_fg = MeshInstance3D.new()
	var q_fg = QuadMesh.new()
	q_fg.size = Vector2(0.80, 0.06)
	hp_fg.mesh = q_fg
	hp_fg.name = "HPBar"
	var fg_mat = StandardMaterial3D.new()
	fg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fg_mat.albedo_color = Color(0.85, 0.15, 0.15, 0.95)
	fg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fg_mat.no_depth_test = true
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

	for obj in objects:
		var o_id = obj.get("id", -1)
		if o_id < 0:
			continue
		seen_ids[o_id] = true

		var o_type = obj.get("type", 0)
		var tx = obj.get("tile_x", 0)
		var ty = obj.get("tile_y", 0)
		var anim_frame = obj.get("anim_frame", 1)

		var prop = get_or_create_prop_node(o_id, o_type, tx, ty)
		prop.visible = true

		# Update object animations & interactive states
		var is_door = (o_type in [1, 2, 148, 149, 180, 181, 211, 212])
		var is_chest = (o_type in [5, 6, 7, 174, 175, 176])
		var is_sarc = (o_type in [154, 214])
		var is_fire = (o_type in [0, 3, 8, 9, 10, 106, 109, 114, 115, 116, 120, 121, 150, 151, 152, 153, 155, 171, 193, 210])

		if is_door:
			var pivot = prop.get_node_or_null("DoorContainer/DoorPivot")
			if pivot:
				# In Diablo 1, obj.pre_flag indicates open state (true when open, false when closed)
				# Also support anim_frame > 1, solid == false, or open door piece IDs
				var is_open = bool(obj.get("pre_flag", false)) or (anim_frame > 1) or (not bool(obj.get("solid", true)))
				if not is_open and diablo_bridge and diablo_bridge.has_method("get_dungeon_tile"):
					var cur_pid = diablo_bridge.get_dungeon_tile(tx, ty)
					if cur_pid in [392, 394, 12, 16, 537, 540, 205, 208]:
						is_open = true
				var target_deg = 85.0 if is_open else 0.0
				pivot.rotation_degrees.y = lerp(pivot.rotation_degrees.y, target_deg, delta * 12.0)
		elif is_chest:
			var lid = prop.get_node_or_null("ChestLid")
			if lid:
				var target_rot = -70.0 if anim_frame > 1 else 0.0
				lid.rotation_degrees.x = lerp(lid.rotation_degrees.x, target_rot, delta * 8.0)
		elif is_sarc:
			var s_lid = prop.get_node_or_null("SarcLid")
			if s_lid:
				var target_offset = Vector3(0.4, 0.0, 0.0) if anim_frame > 1 else Vector3.ZERO
				s_lid.position = s_lid.position.lerp(target_offset, delta * 6.0)
		elif is_fire:
			var light = prop.get_node_or_null("TorchLight") as OmniLight3D
			if light == null:
				light = prop.get_node_or_null("WallTorch/TorchLight") as OmniLight3D
			if light:
				var flicker = 1.45 + 0.18 * sin(time_accum * 8.0 + float(o_id)) * cos(time_accum * 4.5)
				light.light_energy = flicker
		else:
			var obj_spr = prop.get_node_or_null("ObjectSprite3D") as Sprite3D
			if obj_spr:
				var last_f = prop_last_frame.get(o_id, -999)
				if anim_frame != last_f or obj_spr.texture == null:
					prop_last_frame[o_id] = anim_frame
					if diablo_bridge and diablo_bridge.has_method("get_object_sprite_data"):
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

	# Clean up inactive props
	for id in prop_instances.keys():
		if not seen_ids.has(id):
			prop_instances[id].visible = false

func get_or_create_prop_node(o_id: int, o_type: int, tx: int, ty: int) -> Node3D:
	if prop_instances.has(o_id):
		return prop_instances[o_id]

	var node = Node3D.new()
	node.name = "Prop_%d" % o_id
	var wpos = tile_to_world_3d(float(tx), float(ty))
	node.position = wpos

	var is_door = (o_type in [1, 2, 148, 149, 180, 181, 211, 212])
	var is_wall_torch = (o_type in [150, 151, 152, 153])
	var is_standing_fire = (o_type in [0, 3, 8, 9, 10, 106, 109, 114, 115, 116, 120, 121, 155, 171, 193, 210])
	var is_chest = (o_type in [5, 6, 7, 174, 175, 176])
	var is_sarc = (o_type in [154, 214])
	var is_barrel = (o_type in [163, 164])
	var is_shrine = (o_type in [165, 166, 185, 186])

	if is_door:
		var is_l_door = (o_type in [1, 148, 180, 211])
		var basis_tile = Basis().rotated(Vector3.UP, deg_to_rad(-45.0))
		var arch_basis = basis_tile
		if is_l_door:
			arch_basis = basis_tile.rotated(Vector3.UP, deg_to_rad(-90.0))

		var door_container = Node3D.new()
		door_container.name = "DoorContainer"
		door_container.transform = Transform3D(arch_basis, Vector3.ZERO)

		var pivot = Node3D.new()
		pivot.name = "DoorPivot"
		pivot.position = Vector3(-0.40, 0.0, 0.0)

		var leaf = MeshInstance3D.new()
		leaf.name = "DoorLeaf"
		leaf.mesh = get_or_load_mesh("res://assets/models/dungeon/door_leaf.glb")
		leaf.scale = Vector3(1.48, 1.08, 1.0)
		var door_mat = StandardMaterial3D.new()
		door_mat.albedo_color = Color(0.25, 0.18, 0.12)
		door_mat.roughness = 0.72
		door_mat.metallic = 0.08
		leaf.material_override = door_mat
		pivot.add_child(leaf)

		door_container.add_child(pivot)
		node.add_child(door_container)

	elif is_wall_torch:
		var basis_tile = Basis().rotated(Vector3.UP, deg_to_rad(-45.0))
		var is_l_torch = (o_type in [150, 152])
		var rot: Basis
		var offset: Vector3
		var wall_step = 1.06066
		var wall_h_thick = 0.52

		# Check whether the torch is on the wall tile itself, or placed on an adjacent floor tile:
		var is_wall_tile = false
		if last_solidity_grid.size() >= 112 * 112:
			is_wall_tile = (last_solidity_grid[ty * 112 + tx] == 2)

		if is_wall_tile:
			# Placed directly on the wall tile. Wall front face is at +0.14m from center:
			if is_l_torch:
				# Left wall torch: mounted on wall along Y (wall_ew), facing +X into room
				rot = basis_tile.rotated(Vector3.UP, deg_to_rad(90.0))
				offset = basis_tile * Vector3(wall_h_thick, 1.35, 0.0)
			else:
				# Right wall torch: mounted on wall along X (wall_ns), facing +Z into room
				rot = basis_tile
				offset = basis_tile * Vector3(0.0, 1.35, wall_h_thick)
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
		# Standing brazier / fire basin resting on the floor
		var mesh_inst = MeshInstance3D.new()
		mesh_inst.mesh = get_or_load_mesh("res://assets/models/props/standing_brazier.glb")
		mesh_inst.material_override = get_pbr_material_for_theme(get_theme_name(last_level_idx), true)
		node.add_child(mesh_inst)

		var light = OmniLight3D.new()
		light.name = "TorchLight"
		light.position = Vector3(0, 1.15, 0)
		light.light_color = Color(1.0, 0.68, 0.35)
		light.light_energy = 1.75
		light.omni_range = 9.5
		light.omni_attenuation = 1.20
		light.shadow_enabled = true
		light.shadow_bias = 0.15
		light.shadow_normal_bias = 1.5
		node.add_child(light)

		var embers = create_ember_particles()
		embers.position = Vector3(0, 1.05, 0)
		node.add_child(embers)

	elif is_chest:
		var chest_node = Node3D.new()
		chest_node.name = "ChestProp"
		var mesh_inst = MeshInstance3D.new()
		mesh_inst.mesh = get_or_load_mesh("res://assets/models/props/chest.glb")
		mesh_inst.material_override = get_pbr_material_for_theme(get_theme_name(last_level_idx), true)
		chest_node.add_child(mesh_inst)

		var lid_pivot = Node3D.new()
		lid_pivot.name = "ChestLid"
		lid_pivot.position = Vector3(0, 0.36, -0.22)
		chest_node.add_child(lid_pivot)
		node.add_child(chest_node)

	elif is_sarc:
		var sarc_inst = MeshInstance3D.new()
		sarc_inst.mesh = get_or_load_mesh("res://assets/models/props/sarcophagus.glb")
		sarc_inst.material_override = get_pbr_material_for_theme(get_theme_name(last_level_idx), true)
		var lid_node = Node3D.new()
		lid_node.name = "SarcLid"
		lid_node.add_child(sarc_inst)
		node.add_child(lid_node)

	elif is_barrel:
		var barrel_inst = MeshInstance3D.new()
		barrel_inst.mesh = get_or_load_mesh("res://assets/models/props/barrel.glb")
		barrel_inst.material_override = get_pbr_material_for_theme(get_theme_name(last_level_idx), true)
		node.add_child(barrel_inst)

	elif is_shrine:
		var shrine_inst = MeshInstance3D.new()
		shrine_inst.mesh = get_or_load_mesh("res://assets/models/props/shrine.glb")
		shrine_inst.material_override = get_pbr_material_for_theme(get_theme_name(last_level_idx), true)
		node.add_child(shrine_inst)

		var shrine_light = OmniLight3D.new()
		shrine_light.name = "ShrineLight"
		shrine_light.position = Vector3(0, 1.2, 0)
		shrine_light.light_color = Color(0.4, 0.85, 1.0)
		shrine_light.light_energy = 1.2
		shrine_light.omni_range = 5.0
		node.add_child(shrine_light)

	else:
		# Universal Interactive Object Billboard Sprite (Book Pedestals, Candles, Crucifixes, Cauldrons, Blood Wells, Altars, Levers, etc.)
		var spr = Sprite3D.new()
		spr.name = "ObjectSprite3D"
		spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		spr.shaded = false
		spr.pixel_size = PIXEL_SIZE_1X
		spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		spr.modulate = Color(1.45, 1.42, 1.35)

		var shadow_disc = MeshInstance3D.new()
		shadow_disc.name = "PropShadowDisc"
		var disc_mesh = CylinderMesh.new()
		disc_mesh.top_radius = 0.28
		disc_mesh.bottom_radius = 0.32
		disc_mesh.height = 0.01
		shadow_disc.mesh = disc_mesh
		shadow_disc.position.y = 0.01
		var s_mat = StandardMaterial3D.new()
		s_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		s_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.45)
		s_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shadow_disc.material_override = s_mat
		node.add_child(shadow_disc)

		if diablo_bridge and diablo_bridge.has_method("get_object_sprite_data"):
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
		node.add_child(spr)

	props_root.add_child(node)
	prop_instances[o_id] = node
	return node

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

	# Index 0 is player lantern; index 1..N are environmental torches, braziers, and spells
	for i in range(1, lights.size()):
		var l_info = lights[i]
		var tx = l_info.get("tile_x", -1)
		var ty = l_info.get("tile_y", -1)
		if tx < 0 or ty < 0:
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

	# If placed directly on a solid wall tile, shift outwards into the adjacent room/floor
	if last_solidity_grid.size() >= 112 * 112 and last_solidity_grid[ty * 112 + tx] == 2:
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

# ==============================================================================
# Ground Items & Loot Drops Pipeline
# ==============================================================================

func update_ground_items(delta: float):
	if not diablo_bridge or not diablo_bridge.has_method("get_active_items"):
		return

	var items: Array = diablo_bridge.get_active_items()
	var seen_ids: Dictionary = {}

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

		var node = get_or_create_item_node(i_id, curs_id, anim_frame, quality, iname, tx, ty)
		node.visible = true

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

func get_or_create_item_node(i_id: int, curs_id: int, anim_frame: int, quality: int, iname: String, tx: int, ty: int) -> Node3D:
	if item_instances.has(i_id):
		return item_instances[i_id]

	var node = Node3D.new()
	node.name = "GroundItem_%d" % i_id
	var wpos = tile_to_world_3d(float(tx), float(ty))
	node.position = wpos + Vector3(0, 0.06, 0)

	# Fetch texture from HD disk cache or diablo_bridge
	var cache_key = "%d_%d" % [curs_id, anim_frame]
	var tex: ImageTexture = item_textures.get(cache_key, null)
	var item_is_hd: bool = item_is_hd_cache.get(cache_key, false)
	if tex == null:
		var p_hd1 = "res://assets/hd_sprites_x4plus/items/curs_%d_f%d.png" % [curs_id, anim_frame]
		var p_hd2 = "res://assets/hd_sprites_x4plus/items/curs_%d.png" % curs_id
		var p_hd3 = "res://assets/hd_sprites/items/curs_%d_f%d.png" % [curs_id, anim_frame]
		var p_hd4 = "res://assets/hd_sprites/items/curs_%d.png" % curs_id
		var found_p = ""
		for p in [p_hd1, p_hd2, p_hd3, p_hd4]:
			if FileAccess.file_exists(p):
				found_p = p
				break
		if found_p != "":
			var img = Image.load_from_file(ProjectSettings.globalize_path(found_p))
			if img and not img.is_empty():
				img.generate_mipmaps()
				tex = ImageTexture.create_from_image(img)
				item_textures[cache_key] = tex
				item_is_hd = true
				item_is_hd_cache[cache_key] = true

		if tex == null and diablo_bridge and diablo_bridge.has_method("get_ground_item_sprite_data"):
			var s_data: Dictionary = diablo_bridge.get_ground_item_sprite_data(i_id)
			var sw = s_data.get("width", 0)
			var sh = s_data.get("height", 0)
			var rgba: PackedByteArray = s_data.get("rgba", PackedByteArray())
			if sw > 0 and sh > 0 and rgba.size() == sw * sh * 4:
				var img = Image.create_from_data(sw, sh, false, Image.FORMAT_RGBA8, rgba)
				img.generate_mipmaps()
				tex = ImageTexture.create_from_image(img)
				item_textures[cache_key] = tex
				item_is_hd = false
				item_is_hd_cache[cache_key] = false

	# 3D Item Sprite (billboarded slightly above floor)
	var spr = Sprite3D.new()
	spr.name = "ItemSprite"
	spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.shaded = false
	# Generous +75% item scale boost ensures dropped items are clearly visible and legible in 3D
	var item_scale_boost = 1.75
	spr.pixel_size = (PIXEL_SIZE_HD if item_is_hd else PIXEL_SIZE_1X) * item_scale_boost
	spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if tex:
		spr.texture = tex
		spr.offset = Vector2(0, float(tex.get_height()) * 0.5)
	spr.modulate = Color(1.35, 1.35, 1.35)
	node.add_child(spr)

	# Soft ground contact shadow disc
	var shadow_disc = MeshInstance3D.new()
	shadow_disc.name = "ItemShadowDisc"
	var disc_mesh = CylinderMesh.new()
	disc_mesh.top_radius = 0.28
	disc_mesh.bottom_radius = 0.32
	disc_mesh.height = 0.005
	shadow_disc.mesh = disc_mesh
	shadow_disc.position.y = -0.04
	var s_mat = StandardMaterial3D.new()
	s_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.45)
	s_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_disc.material_override = s_mat
	node.add_child(shadow_disc)

	# Authentic Loot Label (White / Blue / Gold)
	var lbl = Label3D.new()
	lbl.name = "ItemLabel"
	lbl.position = Vector3(0, 0.55, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.font_size = 20
	lbl.outline_render_priority = 1
	lbl.outline_size = 4
	lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	lbl.text = iname

	if quality == 1:
		lbl.modulate = Color(0.35, 0.65, 1.0) # Magic: Blue
	elif quality == 2:
		lbl.modulate = Color(1.0, 0.84, 0.25) # Unique: Gold
	else:
		lbl.modulate = Color(0.92, 0.92, 0.92) # Normal: White
	node.add_child(lbl)

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
		var b_mat = StandardMaterial3D.new()
		b_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		b_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if quality == 1:
			b_mat.albedo_color = Color(0.30, 0.60, 1.0, 0.35)
		else:
			b_mat.albedo_color = Color(1.0, 0.80, 0.20, 0.45)
		beam.material_override = b_mat
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
	print("[Native 3D Sandbox] Deactivated. Classic 2.5D view restored.")

func snap_camera_to_player():
	if not diablo_bridge:
		return
	var p_data = diablo_bridge.get_player_continuous_pos()
	var px = p_data.get("pos_x", 25.0)
	var py = p_data.get("pos_y", 25.0)
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
			monster_last_frame.clear()

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

	# Update interactive 3D props & environmental torches (every 0.2s)
	if last_prop_check_timer >= 0.2:
		last_prop_check_timer = 0.0
		update_props(delta)
		update_environmental_torches(delta)

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
	camera_target = camera_target.lerp(player_target_pos, delta * 7.5)
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

	camera.position = camera_target + cam_offset
	if camera.is_inside_tree():
		camera.look_at(camera_target + Vector3(0, 0.75, 0), Vector3.UP)

	# Keep all scenery and special archways aligned uniformly in parallel with camera yaw and pitch
	# Eliminates domino/blinds saw-tooth slicing when orbiting across ALL levels
	if is_sandbox_active:
		var yaw_rad = deg_to_rad(camera_yaw)
		var pitch_rad = deg_to_rad(-camera_pitch)
		if abs(yaw_rad - last_applied_scenery_yaw) > 0.001:
			last_applied_scenery_yaw = yaw_rad
			for spr in town_scenery_nodes.values():
				if is_instance_valid(spr):
					spr.rotation.x = pitch_rad
					spr.rotation.y = yaw_rad
			for aspr in special_scenery_nodes.values():
				if is_instance_valid(aspr):
					aspr.rotation.x = pitch_rad
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

	if event is InputEventMouseMotion and is_orbiting:
		var delta_pos = event.position - last_mouse_pos
		last_mouse_pos = event.position
		camera_yaw = fposmod(camera_yaw - delta_pos.x * 0.4, 360.0)
		camera_pitch = clamp(camera_pitch + delta_pos.y * 0.3, 25.0, 75.0)
		return true

	# 3D Click-to-Move Raycast Navigation
	if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		var mouse_pos = event.position
		var ray_origin = camera.project_ray_origin(mouse_pos)
		var ray_dir = camera.project_ray_normal(mouse_pos)
		var ground_plane = Plane(Vector3.UP, 0.0)
		var hit = ground_plane.intersects_ray(ray_origin, ray_dir)

		if hit != null:
			var target_tile = world_3d_to_tile(hit)
			var target_tx = clamp(int(round(target_tile.x)), 0, 111)
			var target_ty = clamp(int(round(target_tile.y)), 0, 111)

			# Spawn glowing 3D waypoint feedback ring
			if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				click_marker.position = Vector3(hit.x, 0.04, hit.z)
				click_marker.visible = true
				click_fade = 0.85
				var mat = click_marker.material_override as StandardMaterial3D
				if mat:
					mat.albedo_color.a = click_fade

			# Dispatch click command to Diablo logic engine
			if diablo_bridge and event.pressed:
				var btn = 1 if event.button_index == MOUSE_BUTTON_LEFT else 2
				if diablo_bridge.has_method("send_click_to_tile"):
					diablo_bridge.send_click_to_tile(target_tx, target_ty, btn)
				else:
					var screen_x: int = 0
					var screen_y: int = 0
					if diablo_bridge.has_method("map_world_to_screen"):
						var target_world = Vector2(float(target_tx - target_ty) * 32.0, float(target_tx + target_ty) * 16.0)
						var screen_pos = diablo_bridge.map_world_to_screen(target_world)
						screen_x = screen_pos.x
						screen_y = screen_pos.y
					var raw_btn = 1 if event.button_index == MOUSE_BUTTON_LEFT else 3
					var state = 1 if event.pressed else 0
					diablo_bridge.send_input(2, raw_btn, state, screen_x, screen_y)
				return true

	return false
