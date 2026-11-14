@tool
extends SceneTree

func _init() -> void:
	print("--- Inspecting Item Sprite Data from DevilutionX Bridge ---")
	var bridge = ClassDB.instantiate("DiabloBridge")
	if bridge == null:
		print("ERROR: Could not instantiate DiabloBridge!")
		quit(1)
		return
	
	bridge.init_engine("/home/biti/.local/share/diasurgical/devilution")
	OS.delay_msec(600)
	
	print("Checking item sprite data...")
	for item_id in range(20):
		if bridge.has_method("get_ground_item_sprite_data"):
			var data = bridge.get_ground_item_sprite_data(item_id)
			var w = data.get("width", 0)
			var h = data.get("height", 0)
			if w > 0:
				print("Item %d: width=%d, height=%d, rgba_size=%d" % [item_id, w, h, data.get("rgba", PackedByteArray()).size()])
	quit(0)
