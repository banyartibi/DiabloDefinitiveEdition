extends SceneTree

func _init():
	print("[AudioDiag] Testing DiabloBridge audio stream loading...")
	if not ClassDB.can_instantiate("DiabloBridge"):
		print("[AudioDiag] DiabloBridge class not registered!")
		quit(1)
		return

	var bridge = ClassDB.instantiate("DiabloBridge")
	bridge.init_engine("/home/biti/.local/share/diasurgical/devilution")
	OS.delay_msec(600)

	var paths = [
		"sfx/items/crclos.wav",
		"sfx/misc/blank.wav",
		"sfx/warrior/warior01.wav",
		"sfx/misc/walk1.wav",
		"sfx/misc/cast2.wav",
		"sfx/monsters/butcher.wav",
		"music/dintro.wav"
	]
	for p in paths:
		var st = bridge.load_wav_stream(p, false)
		var sz = st.data.size() if st else 0
		var fmt = st.format if st else -1
		var rate = st.mix_rate if st else 0
		print("[AudioDiag] Path: %-32s -> valid: %-5s, bytes: %6d, rate: %5d, fmt: %d" % [p, str(st != null), sz, rate, fmt])

	bridge.quit_engine()
	quit(0)
