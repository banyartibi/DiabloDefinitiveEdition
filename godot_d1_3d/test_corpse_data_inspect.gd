extends SceneTree

func _init():
	var mock = preload("res://test_task_corpse_and_lava.gd").new()
	var d = mock.mock_bridge.get_corpse_sprite_data(2, 3)
	print("Corpse sprite data: width=", d.get("width"), " height=", d.get("height"))
	quit(0)
