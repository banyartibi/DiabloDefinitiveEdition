extends SceneTree

# End-to-end: does the sandbox actually put HD textures on hero/monster sprites?
const HdSpriteProvider = preload("res://scripts/hd_sprite_provider.gd")
const MPQ_DIR = "/home/biti/.local/share/diasurgical/devilution"

func _init() -> void:
	var bridge = ClassDB.instantiate("DiabloBridge")
	root.add_child(bridge)
	bridge.init_engine(MPQ_DIR)
	while not bridge.is_engine_ready():
		OS.delay_msec(20)
	bridge.menu_select_single_player()
	OS.delay_msec(400)
	bridge.launch_hero_game(2, 0, true)
	while not bridge.is_game_running():
		OS.delay_msec(20)
	OS.delay_msec(1500)
	var scene = load("res://scenes/sandbox/native_3d_sandbox.tscn").instantiate()
	root.add_child(scene)
	scene.diablo_bridge = bridge
	scene.activate()
	for i in range(90):
		await process_frame
		HdSpriteProvider.pump(16)
	var hd := 0
	var one_x := 0
	var no_tex := 0
	var names := {}
	var stacks: Array = []
	_collect(root, stacks)
	for sp in stacks:
		var t: Texture2D = sp.texture
		if t == null:
			no_tex += 1
			continue
		if sp.pixel_size < 0.01:
			hd += 1
			var g := str(sp.get_parent().name)
			names[g] = int(names.get(g, 0)) + 1
		else:
			one_x += 1
	print("ATTACHED hd=%d one_x=%d none=%d groups=%s" % [hd, one_x, no_tex, JSON.stringify(names)])
	var pd = bridge.get_player_continuous_pos()
	var cel = str(bridge.get_player_cel_path()).replace("/", "\\").split("\\")
	var prefix = str(cel[2]).to_lower() if cel.size() >= 3 else ""
	var hero = HdSpriteProvider.get_player_sprite(int(bridge.get_player_class()), str(pd.get("action", "STAND")),
		int(pd.get("dir", 0)), int(pd.get("anim_frame", 0)), scene.current_tile_model, prefix)
	# The first lookup only queues the file; drain, then re-query.
	for i in range(40):
		if hero != null:
			break
		HdSpriteProvider.pump(16)
		await process_frame
	hero = HdSpriteProvider.get_player_sprite(int(bridge.get_player_class()), str(pd.get("action", "STAND")),
		int(pd.get("dir", 0)), int(pd.get("anim_frame", 0)), scene.current_tile_model, prefix)
	print("HERO class=%s action=%s prefix=%s hd=%s size=%s pending=%d" % [
		HdSpriteProvider.PLAYER_CLASS_NAMES[int(bridge.get_player_class())], pd.get("action"), prefix,
		hero != null, hero.get_size() if hero != null else "-", HdSpriteProvider.pending_count()])
	var mons := {}
	for m in bridge.get_monsters():
		var mn := str(m.get("name", ""))
		if mn == "" or mons.has(mn):
			continue
		mons[mn] = [int(m.get("mode", 0)), int(m.get("type", -1))]
	var ok := 0
	var bad := []
	for mn in mons.keys():
		var v = mons[mn]
		for pump_i in range(20):
			if HdSpriteProvider.get_monster_sprite(mn, v[0], 3, 2, scene.current_tile_model, v[1]) != null:
				break
			HdSpriteProvider.pump(16)
			await process_frame
		if HdSpriteProvider.get_monster_sprite(mn, v[0], 3, 2, scene.current_tile_model, v[1]) != null:
			ok += 1
		else:
			bad.append("%s(mode %d, type %d)" % [mn, v[0], v[1]])
	print("MONSTERS live_names=%d hd_ok=%d miss=%s" % [mons.size(), ok, ", ".join(bad)])
	quit()

func _collect(n: Node, out: Array) -> void:
	if n is Sprite3D:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)
