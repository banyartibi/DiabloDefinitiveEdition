extends SceneTree

func _init():
	var spr = Sprite3D.new()
	spr.axis = Vector3.AXIS_Y
	var aabb = spr.get_aabb()
	print("AABB size with empty tex: ", aabb.size)
	# create test image 64x32
	var img = Image.create(64, 32, false, Image.FORMAT_RGBA8)
	var tex = ImageTexture.create_from_image(img)
	spr.texture = tex
	spr.pixel_size = 0.02
	aabb = spr.get_aabb()
	print("AABB with 64x32 tex (axis=AXIS_Y): size=", aabb.size, " pos=", aabb.position)
	spr.queue_free()
	quit(0)
