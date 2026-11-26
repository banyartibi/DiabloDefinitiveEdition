extends SceneTree
func _initialize():
	var keys = Performance.Track.keys()
	for i in keys.size():
		print("%s=%s" % [keys[i], str(Performance.get_monitor(keys[i]))])
	quit()
