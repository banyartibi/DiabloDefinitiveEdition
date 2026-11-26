extends SceneTree
func _initialize():
	var s = load("res://scripts/hd_sprite_provider.gd")
	print("HD OK ", s != null)
	quit()
