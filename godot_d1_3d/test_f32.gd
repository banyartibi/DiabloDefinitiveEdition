extends SceneTree
func _initialize():
	var s = Sprite3D.new()
	s.pixel_size = 0.00673825
	s.sorting_offset = 0.05
	print("pix_eq=%s sort_eq=%s pix=%s sort=%s" % [s.pixel_size == 0.00673825, s.sorting_offset == 0.05, s.pixel_size, s.sorting_offset])
	quit()
