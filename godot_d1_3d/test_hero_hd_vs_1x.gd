extends SceneTree

# Does the HD hero frame the provider resolves match the frame the engine draws?
# Compares the 1x bridge raster (engine's own palette + CEL) against the HD PNG
# the provider would use for the same action/direction/frame: size ratio, opaque
# pixel coverage and mean luminance. A luminance far off the 1x mean means the
# HD asset was exported against the wrong palette.

const HdSpriteProvider = preload("res://scripts/hd_sprite_provider.gd")
const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

var bridge

func _init() -> void:
	bridge = ClassDB.instantiate("DiabloBridge")
	root.add_child(bridge)
	bridge.init_engine(MPQ_DIR)
	while not bridge.is_engine_ready():
		OS.delay_msec(20)
	bridge.menu_select_single_player()
	OS.delay_msec(500)
	bridge.launch_hero_game(2, 0, true)
	var waited := 0
	while not bridge.is_game_running() and waited < 30000:
		OS.delay_msec(20)
		waited += 20
	print("game_running=%s after %dms" % [bridge.is_game_running(), waited])
	OS.delay_msec(2500)

	var model := 1
	var env_model := OS.get_environment("HD_MODEL")
	if env_model != "":
		model = int(env_model)

	# get_player_sprite only queues a decode on the first miss, so query, drain
	# the provider's load queue, and query again until the frame resolves.
	for cycle in 4:
		for f in 10:
			await process_frame
		OS.delay_msec(150)
		await _check(model)

	bridge.deinit_engine()
	quit()

func _stats_rgba(bytes: PackedByteArray, w: int, h: int) -> Dictionary:
	var n := 0
	var sum := 0.0
	var top := {}
	for i in range(0, bytes.size(), 4):
		var a = bytes[i + 3]
		if a < 13:
			continue
		var r = bytes[i]
		var g = bytes[i + 1]
		var b = bytes[i + 2]
		sum += (r + g + b) / 3.0
		n += 1
		var key := "%d,%d,%d" % [r >> 4 << 4, g >> 4 << 4, b >> 4 << 4]
		top[key] = int(top.get(key, 0)) + 1
	return { "n": n, "mean": (sum / n if n > 0 else 0.0), "top": top }

func _stats_img(img: Image) -> Dictionary:
	var rect = img.get_used_rect()
	if rect.size.x <= 0 or rect.size.y <= 0:
		return { "n": 0, "mean": 0.0, "top": {} }
	var n := 0
	var sum := 0.0
	var top := {}
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var c = img.get_pixel(x, y)
			if c.a <= 0.05:
				continue
			sum += (c.r + c.g + c.b) / 3.0
			n += 1
			var key := "%d,%d,%d" % [int(c.r * 255) >> 4 << 4, int(c.g * 255) >> 4 << 4, int(c.b * 255) >> 4 << 4]
			top[key] = int(top.get(key, 0)) + 1
	return { "n": n, "mean": (sum / n if n > 0 else 0.0), "top": top }

func _top_str(stats: Dictionary) -> String:
	var pairs := []
	for k in stats.top:
		pairs.append([stats.top[k], k])
	pairs.sort_custom(func(a, b): return a[0] > b[0])
	var out := ""
	for i in range(min(4, pairs.size())):
		out += "%s(%d) " % [pairs[i][1], pairs[i][0]]
	return out

func _check(model: int) -> void:
	var p_class := int(bridge.get_player_class())
	var s: Dictionary = bridge.get_player_sprite_data()
	var w := int(s.get("width", 0))
	var h := int(s.get("height", 0))
	var pdata: Dictionary = bridge.get_player_continuous_pos() if bridge.has_method("get_player_continuous_pos") else {}
	var action := str(pdata.get("action", "STAND"))
	var dir := int(pdata.get("dir", s.get("dir", 0)))
	var frame := int(pdata.get("anim_frame", s.get("frame", 0)))
	var cel_path := str(bridge.get_player_cel_path()) if bridge.has_method("get_player_cel_path") else ""
	var parts := cel_path.replace("/", "\\").split("\\")
	var prefix := parts[2].to_lower() if parts.size() >= 3 else ""
	var cel_suffix := ""
	if parts.size() >= 4 and parts[2].length() < parts[3].length():
		cel_suffix = parts[3].to_lower().substr(parts[2].length())

	var one := _stats_rgba(s.get("rgba", PackedByteArray()), w, h)
	var tex: Texture2D = null
	for attempt in 8:
		tex = HdSpriteProvider.get_player_sprite(p_class, action, dir, frame, model, prefix)
		if tex != null:
			break
		for f in 4:
			await process_frame
			HdSpriteProvider.pump(200)
		OS.delay_msec(120)
	print("---- hero class=%d action=%s dir=%d frame=%d cel='%s' suffix='%s' prefix='%s'" % [p_class, action, dir, frame, cel_path, cel_suffix, prefix])
	print("  1x %dx%d opaque=%d mean=%.4f  top: %s" % [w, h, one.n, one.mean, _top_str(one)])
	if tex == null:
		print("  HD: NONE (falls back to the 1x bridge raster)")
		return
	var img = tex.get_image()
	var hd := _stats_img(img)
	var ratio = float(tex.get_width()) / float(max(w, 1))
	print("  HD %dx%d opaque=%d mean=%.4f ratio=%.2fx  top: %s" % [tex.get_width(), tex.get_height(), hd.n, hd.mean, ratio, _top_str(hd)])
	var dmean = absf(hd.mean - one.mean) / maxf(one.mean, 0.001)
	print("  verdict: size_ratio=%s luminance_delta=%.1f%% %s" % ["OK" if ratio > 3.0 and ratio < 5.0 else "WRONG", dmean * 100.0, "OK" if dmean < 0.35 else "SUSPECT"])
