extends SceneTree
# Proves the Mode 2 missile HD path in-game: walks the hero around level 1 until
# projectiles exist, then reports the on-screen Missile_* sprite textures.

const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

var bridge
var scene
var max_missiles := 0
var hd := 0
var onex := 0
var samples := {}

func _sprite_info(n: Node) -> void:
	if n is Sprite3D:
		var sp = n as Sprite3D
		var t = sp.texture
		if t == null:
			return
		var key = "%dx%d px=%.5f" % [t.get_width(), t.get_height(), sp.pixel_size]
		samples[key] = int(samples.get(key, 0)) + 1
		if sp.pixel_size < 0.01:
			hd += 1
		else:
			onex += 1
	for c in n.get_children():
		_sprite_info(c)

func _init() -> void:
	_run()

func _run() -> void:
	bridge = ClassDB.instantiate("DiabloBridge")
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
	scene = load("res://scenes/sandbox/native_3d_sandbox.tscn").instantiate()
	vp.add_child(scene)
	await process_frame
	scene.diablo_bridge = bridge
	scene.activate()

	var dirs = [Vector2i(8, 0), Vector2i(0, 8), Vector2i(-8, 0), Vector2i(0, -8),
		Vector2i(6, 6), Vector2i(-6, -6), Vector2i(6, -6), Vector2i(-6, 6)]
	var chase_name := ""
	for f in range(900):
		await process_frame
		if f % 20 == 0:
			var tp = bridge.get_player_tile_pos()
			var tx = int(tp.x) if tp is Vector2i else int(tp.get("x", 0))
			var ty = int(tp.y) if tp is Vector2i else int(tp.get("y", 0))
			var best = null
			var bd := 100000
			for m in bridge.get_active_monsters_data():
				if not bool(m.get("is_alive", false)):
					continue
				var dd = absi(int(m.get("pos_x", 0)) - tx) + absi(int(m.get("pos_y", 0)) - ty)
				if dd < bd:
					bd = dd
					best = m
			if best != null:
				chase_name = str(best.get("name", ""))
				if bd > 3:
					bridge.walk_to_tile(int(best.get("pos_x", 0)), int(best.get("pos_y", 0)))
				else:
					bridge.interact_with_monster(int(best.get("id", -1)))
		if f % 100 == 0:
			print("MISSILE frame=%d missiles=%d hp=%d chasing=%s" % [
				f, bridge.get_active_missiles().size(), int(bridge.get_player_hp()), chase_name])
		var ms = bridge.get_active_missiles()
		max_missiles = max(max_missiles, ms.size())
		if f % 10 == 0 and ms.size() > 0:
			var mr = scene.get_node_or_null("MissilesRoot")
			if mr != null:
				for c in mr.get_children():
					_sprite_info(c)
		if hd + onex > 40:
			break

	print("MISSILE max_on_screen=%d sprite_samples_hd=%d onex=%d" % [max_missiles, hd, onex])
	var keys = samples.keys()
	keys.sort()
	for k in keys:
		print("MISSILE tex %s x%d" % [k, samples[k]])
	quit(0)
