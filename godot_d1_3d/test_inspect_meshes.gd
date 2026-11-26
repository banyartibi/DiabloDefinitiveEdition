@tool
extends SceneTree

func _init() -> void:
	var paths = [
		"res://assets/models/dungeon/floor_cathedral.glb",
		"res://assets/models/dungeon/wall_block.glb",
		"res://assets/models/dungeon/wall_ns.glb",
		"res://assets/models/dungeon/wall_ew.glb",
		"res://assets/models/dungeon/pillar.glb",
		"res://assets/models/dungeon/arch_door.glb"
	]
	for p in paths:
		var scene = load(p)
		if scene:
			var node = scene.instantiate()
			print("=== Mesh: %s ===" % p)
			_print_node(node, "  ")
		else:
			print("FAIL load: %s" % p)
	quit(0)

func _print_node(n: Node, indent: String):
	if n is MeshInstance3D and n.mesh:
		var aabb = n.mesh.get_aabb()
		print("%s%s (%s): AABB pos=%s, size=%s" % [indent, n.name, n.get_class(), str(aabb.position), str(aabb.size)])
	else:
		print("%s%s (%s)" % [indent, n.name, n.get_class()])
	for c in n.get_children():
		_print_node(c, indent + "  ")
