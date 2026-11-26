@tool
extends SceneTree

func _init() -> void:
	var meshes = [
		"res://assets/models/dungeon/wall_block.glb",
		"res://assets/models/dungeon/wall_ns.glb",
		"res://assets/models/dungeon/wall_ew.glb",
		"res://assets/models/dungeon/pillar.glb",
		"res://assets/models/dungeon/arch_door.glb",
		"res://assets/models/dungeon/floor_cathedral.glb"
	]
	for p in meshes:
		var scene = load(p)
		print("\n--- %s ---" % p)
		if scene is PackedScene:
			var inst = scene.instantiate()
			print("Instantiated class: ", inst.get_class())
			for c in inst.get_children():
				if c is MeshInstance3D and c.mesh:
					print("  Child mesh: ", c.name, " aabb=", c.mesh.get_aabb())
		elif scene is Mesh:
			print("Mesh aabb: ", scene.get_aabb())

	quit(0)
