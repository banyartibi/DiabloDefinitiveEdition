@tool
extends SceneTree

func _init() -> void:
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = 5
	var tf = Transform3D(Basis.IDENTITY, Vector3(10, 20, 30))
	mm.set_instance_transform(0, tf)
	print("With mesh mm[0] = ", mm.get_instance_transform(0))
	print("Buffer size: ", mm.buffer.size())
	quit(0)
