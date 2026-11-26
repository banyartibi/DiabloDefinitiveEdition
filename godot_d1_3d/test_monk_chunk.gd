extends SceneTree
const HdSpriteProvider = preload("res://scripts/hd_sprite_provider.gd")
const UpscalerModelConfig = preload("res://scripts/upscaler_model_config.gd")
func _init() -> void:
	var prefixes = ["mha","mhb","mhd","mhh","mhm","mhn","mhs","mht","mhu","mla","mlb","mld","mlh","mlm","mln","mls","mlt","mlu","mma","mmb","mmd","mmh","mmm","mmn","mms","mmt","mmu"]
	for model in [1]:
		var cases := []
		for p in prefixes:
			cases.append([p + "/stand", func(): return HdSpriteProvider.get_player_sprite(3, "stand", 3, 2, model, p)])
			cases.append([p + "/walk", func(): return HdSpriteProvider.get_player_sprite(3, "walk", 3, 2, model, p)])
		for c in cases:
			c[1].call()
		var pump := 0
		while HdSpriteProvider.pending_count() > 0 and pump < 400:
			HdSpriteProvider.pump(8); pump += 1
		print("drain pumps=", pump, " cache=", HdSpriteProvider.cache_count(), " pending=", HdSpriteProvider.pending_count(), " evicted=", int(HdSpriteProvider.stat_evicted))
		var miss := []
		for c in cases:
			if c[1].call() == null:
				miss.append(c[0])
		print("model=%d miss=%d %s" % [model, miss.size(), ", ".join(miss)])
	quit()
