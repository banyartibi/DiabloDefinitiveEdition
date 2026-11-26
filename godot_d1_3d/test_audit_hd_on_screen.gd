extends SceneTree

# Measures what the Mode 2 renderer actually put on screen: HD sprite frames
# vs 1x bridge rasters, plus an HD-off frame for pixel comparison.

const HdSpriteProvider = preload("res://scripts/hd_sprite_provider.gd")
const UpscalerModelConfig = preload("res://scripts/upscaler_model_config.gd")

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"
const OUT_DIR = "/home/biti/antigravity/magical-bell/scratch"

var hd_big := 0
var hd_small := 0
var sizes := {}
var owners := {}

func _owner_path(n: Node) -> String:
	var p = n.name
	var par = n.get_parent()
	if par != null:
		p = str(par.name) + "/" + p
	return p

func _walk(n: Node) -> void:
	if n is Sprite3D:
		var sp = n as Sprite3D
		var t = sp.texture
		if t != null:
			var s = t.get_size()
			var key = "%dx%d" % [s.x, s.y]
			sizes[key] = int(sizes.get(key, 0)) + 1
			# HD sprites are placed with PIXEL_SIZE_HD (~0.0067); 1x bridge rasters
			# use PIXEL_SIZE_1X (~0.027). Texture size alone is unreliable: HD item
			# frames are cropped to their used rect and can be smaller than 200px.
			if sp.pixel_size < 0.01:
				hd_big += 1
			else:
				hd_small += 1
				print("AUDIT fallback %s tex=%dx%d px=%.5f" % [_owner_path(n), s.x, s.y, sp.pixel_size])
			var grp = str(n.get_parent().name) if n.get_parent() != null else "?"
			owners[grp] = int(owners.get(grp, 0)) + 1
	elif n is MeshInstance3D:
		var mi = n as MeshInstance3D
		var mat = mi.material_override as StandardMaterial3D
		if mat == null:
			mat = mi.get_active_material(0)
		if mat != null and mat.albedo_texture != null:
			var s2 = mat.albedo_texture.get_size()
			var key2 = "mesh %dx%d" % [s2.x, s2.y]
			sizes[key2] = int(sizes.get(key2, 0)) + 1
	for c in n.get_children():
		_walk(c)

func _init() -> void:
	var bridge = ClassDB.instantiate("DiabloBridge")
	root.add_child(bridge)
	bridge.init_engine(MPQ_DIR)
	while not bridge.is_engine_ready():
		OS.delay_msec(20)
	bridge.menu_select_single_player()
	OS.delay_msec(500)
	bridge.launch_hero_game(2, 0, true)
	while not bridge.is_game_running():
		OS.delay_msec(20)
	OS.delay_msec(2000)

	var vp = SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var scene = load("res://scenes/sandbox/native_3d_sandbox.tscn").instantiate()
	vp.add_child(scene)
	await process_frame
	scene.diablo_bridge = bridge
	scene.activate()

	var hd_model = OS.get_environment("HD_MODEL")
	if hd_model != "":
		var t0 = Time.get_ticks_msec()
		scene.set_tile_model(int(hd_model))
		for i in range(240):
			await process_frame
		print("AUDIT tile_model=%d switch_ms=%d" % [int(hd_model), Time.get_ticks_msec() - t0])
	else:
		print("AUDIT tile_model_default=%d" % scene.current_tile_model)
		if bridge.has_method("get_d1de_tile_model"):
			print("AUDIT bridge_tile_model=%d" % int(bridge.get_d1de_tile_model()))

	for i in range(120):
		await process_frame

	var img_hd = vp.get_texture().get_image()
	img_hd.save_png(OUT_DIR + "/audit_hd_on.png")
	_walk(vp)
	print("AUDIT sprite3d_hd=%d sprite3d_1x=%d" % [hd_big, hd_small])

	# Hero: which class/action is live and does HD resolve?
	var pd = bridge.get_player_continuous_pos()
	var pclass = bridge.get_player_class()
	var cel_parts = str(bridge.get_player_cel_path()).replace("/", "\\").split("\\")
	var gfx_prefix = str(cel_parts[2]).to_lower() if cel_parts.size() >= 3 else ""
	var hd_hero = HdSpriteProvider.get_player_sprite(pclass, str(pd.get("action", "STAND")),
		int(pd.get("dir", 0)), int(pd.get("anim_frame", 0)), scene.current_tile_model, gfx_prefix)
	# HD frames load asynchronously; re-query after a few frames so a null here
	# means "missing asset", not "still loading".
	for i in range(30):
		if hd_hero != null:
			break
		await process_frame
		hd_hero = HdSpriteProvider.get_player_sprite(pclass, str(pd.get("action", "STAND")),
			int(pd.get("dir", 0)), int(pd.get("anim_frame", 0)), scene.current_tile_model, gfx_prefix)
	# Drain the async decode queue explicitly, then re-query and probe why a null persists.
	for i in range(60):
		HdSpriteProvider.pump(16)
		await process_frame
	hd_hero = HdSpriteProvider.get_player_sprite(pclass, str(pd.get("action", "STAND")),
		int(pd.get("dir", 0)), int(pd.get("anim_frame", 0)), scene.current_tile_model, gfx_prefix)
	var cls_name = HdSpriteProvider.PLAYER_CLASS_NAMES[pclass]
	var sfx = UpscalerModelConfig.get_sprite_folder(scene.current_tile_model)
	for sub in ["player/%s_%s_stand" % [cls_name, gfx_prefix], "player/%s_stand" % cls_name]:
		var d = sfx + "/" + sub
		var f0 = d + "/dir_0_frame_0.png"
		print("AUDIT hero_probe %s dir_exists=%s cached=%s pending=%s bad=%s pending_total=%d"
			% [sub, str(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(d))),
				str(HdSpriteProvider._cache.has(f0)), str(HdSpriteProvider._pending.has(f0)),
				str(HdSpriteProvider._bad_folders.has(d)), HdSpriteProvider.pending_count()])
	print("AUDIT hero class=%d action=%s cel=%s hd=%s"
		% [pclass, str(pd.get("action", "")), str(bridge.get_player_cel_path()),
			("null" if hd_hero == null else str(hd_hero.get_size()))])

	# Ground items: report every curs id whose HD frame is missing.
	var items = bridge.get_active_items()
	var miss := 0
	for it in items:
		var cid = int(it.get("curs_id", it.get("cursId", -1)))
		var fr = int(it.get("anim_frame", 0))
		if HdSpriteProvider.get_item_sprite(cid, fr, scene.current_tile_model) == null:
			# Distinguish a genuinely missing asset from an async load still in flight.
			var folder = UpscalerModelConfig.get_sprite_folder(scene.current_tile_model)
			var have = FileAccess.file_exists(folder + "/items/curs_%d_f%d.png" % [cid, fr]) \
				or FileAccess.file_exists(folder + "/items/curs_%d.png" % cid)
			miss += 1
			print("AUDIT item_missing_hd curs=%d frame=%d name=%s asset_on_disk=%s" % [cid, fr, str(it.get("name", "")), str(have)])
	print("AUDIT items=%d missing_hd=%d" % [items.size(), miss])

	var keys = sizes.keys()
	keys.sort()
	for k in keys:
		print("AUDIT tex %s x%d" % [k, sizes[k]])
	var ok = owners.keys()
	ok.sort()
	for k in ok:
		print("AUDIT group %s x%d" % [k, owners[k]])

	scene.set_hd_graphics_enabled(false)
	for i in range(60):
		await process_frame
	var img_off = vp.get_texture().get_image()
	img_off.save_png(OUT_DIR + "/audit_hd_off.png")

	var diff := 0
	var tot := 0
	for y in range(0, 720, 4):
		for x in range(0, 1280, 4):
			tot += 1
			if img_hd.get_pixel(x, y) != img_off.get_pixel(x, y):
				diff += 1
	print("AUDIT pixels_changed_by_hd=%d/%d (%.1f%%)" % [diff, tot, 100.0 * diff / tot])
	print("AUDIT objects=%d monsters=%d missiles=%d" % [
		bridge.get_active_objects().size(),
		bridge.get_active_monsters_data().size(),
		bridge.get_active_missiles().size()])
	quit(0)
