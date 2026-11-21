@tool
extends SceneTree

# Provider-only coverage probe: how many of the on-disk HD object/missile
# families actually resolve through HdSpriteProvider (frame 0, dir 0).

const HdSpriteProvider = preload("res://scripts/hd_sprite_provider.gd")

func _init() -> void:
	for kind in ["objects", "missiles"]:
		var root_dir = "res://assets/hd_sprites/" + kind
		var da = DirAccess.open(root_dir)
		if da == null:
			print(kind, ": folder missing")
			continue
		var total = 0
		var ok = 0
		var bad = []
		da.list_dir_begin()
		var name = da.get_next()
		while name != "":
			if da.current_is_dir():
				total += 1
				var tex = null
				if kind == "objects":
					tex = HdSpriteProvider.get_object_sprite(name, 1, 0)
				else:
					tex = HdSpriteProvider.get_missile_sprite(name, 0, 1, 0)
				if tex != null:
					ok += 1
				else:
					bad.append(name)
			name = da.get_next()
		da.list_dir_end()
		print("%-8s families=%d  hd_resolved=%d" % [kind, total, ok])
		if bad.size() > 0:
			print("   unresolved: ", str(bad.slice(0, 20)))
	quit(0)
