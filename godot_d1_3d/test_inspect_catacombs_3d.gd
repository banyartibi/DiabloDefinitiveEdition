extends SceneTree

func _init():
	var mesh = load("res://assets/models/aaa/catacombs/wall_ns_catacombs.res") as ArrayMesh
	var mat = mesh.surface_get_material(0) as StandardMaterial3D
	var img = mat.albedo_texture.get_image()
	print("Image width:", img.get_width(), "height:", img.get_height())
	print("Format:", img.get_format())
	print("Pixel 100,100:", img.get_pixel(100, 100))
	quit(0)
