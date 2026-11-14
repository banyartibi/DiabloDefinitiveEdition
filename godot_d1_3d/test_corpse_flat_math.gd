extends SceneTree

func _init():
	print("--- Testing Corpse Flat Plane Math ---")
	var spr = Sprite3D.new()
	spr.axis = Vector3.AXIS_Y
	print("spr.axis set to AXIS_Y successfully: ", spr.axis == Vector3.AXIS_Y)
	spr.queue_free()
	quit(0)
