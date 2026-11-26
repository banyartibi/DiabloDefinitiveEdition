extends SceneTree
func _initialize():
	for p in Performance.get_property_list():
		if p["name"].begins_with("TIME_") or p["name"].begins_with("RENDER_"):
			print("%s=%s" % [p["name"], str(p["value"])])
	quit()
