extends SceneTree

const HdSpriteProvider = preload("res://scripts/hd_sprite_provider.gd")
const UpscalerModelConfig = preload("res://scripts/upscaler_model_config.gd")

func _init() -> void:
	var dp: String = UpscalerModelConfig.get_sprite_folder(0) + "/monsters/golem_golem_death"
	var t = HdSpriteProvider._load_frame(dp, 3, 2)
	print("first=", t, " queue=", HdSpriteProvider._queue, " created=", int(HdSpriteProvider.stat_created))
	var n := 0
	while HdSpriteProvider.pending_count() > 0 and n < 20:
		HdSpriteProvider.pump(8)
		n += 1
	print("pumped=", n, " created=", int(HdSpriteProvider.stat_created), " queue=", HdSpriteProvider._queue, " cache=", HdSpriteProvider._cache.keys())
	for k in HdSpriteProvider._cache.keys():
		print("  val ", k, " -> ", HdSpriteProvider._cache[k], " black_hits=", HdSpriteProvider._black_hits)
	print("second=", HdSpriteProvider._load_frame(dp, 3, 2))
	quit()
