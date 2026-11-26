extends SceneTree
const HdSpriteProvider = preload("res://scripts/hd_sprite_provider.gd")
func _init() -> void:
	for spec in [["monk","mha","stand",3],["sorceror","sha","stand",2],["sorceror","sha","attack",2],["monk","mma","stand",3]]:
		var t = HdSpriteProvider.get_player_sprite(spec[3], spec[2], 3, 2, 1, spec[1])
		var n := 0
		while HdSpriteProvider.pending_count() > 0 and n < 200:
			HdSpriteProvider.pump(8); n += 1
		var t2 = HdSpriteProvider.get_player_sprite(spec[3], spec[2], 3, 2, 1, spec[1])
		print("CASE %s_%s_%s first=%s pumped=%d second=%s created=%d pending=%d" % [spec[1], spec[2], spec[3], t != null, n, t2 != null, int(HdSpriteProvider.stat_created), HdSpriteProvider.pending_count()])
	quit()
