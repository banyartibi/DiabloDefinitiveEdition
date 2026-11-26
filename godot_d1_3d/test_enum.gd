extends SceneTree
func _initialize():
	var out = []
	for i in range(40):
		out.append("%d=%.2f" % [i, Performance.get_monitor(i)])
	print("[MON] " + " ".join(out))
	quit()
