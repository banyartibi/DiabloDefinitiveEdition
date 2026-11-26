extends SceneTree
func _initialize():
	var s = load("res://scripts/native_3d_sandbox.gd")
	print("COMPILE OK ", s != null)
	quit()
