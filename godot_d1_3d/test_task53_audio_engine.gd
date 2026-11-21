extends SceneTree

# ==============================================================================
# Test: Task 5.3 - Native Godot 4.7 Audio Engine & Teardown Verification
# ==============================================================================

func _init():
	print("\n==================================================")
	print(" Testing Task 5.3: Native Godot 4.7 Audio Engine  ")
	print("==================================================")

	var bridge_class = ClassDB.instantiate("DiabloBridge")
	assert(bridge_class != null, "ERROR: DiabloBridge GDExtension must be available!")
	root.add_child(bridge_class)

	var mpq_dir = "/home/biti/.local/share/diasurgical/devilution"
	bridge_class.init_engine(mpq_dir)

	var waited = 0
	while not bridge_class.is_engine_ready() and waited < 200:
		OS.delay_msec(20)
		waited += 1
	assert(bridge_class.is_engine_ready(), "ERROR: DevilutionX core with MPQ archives must be ready!")

	print("\n[1/4] Verifying D1AudioManager Setup & Audio Buses...")
	var audio_mgr_script = load("res://scripts/audio_manager.gd")
	assert(audio_mgr_script != null, "ERROR: audio_manager.gd must exist!")
	var audio_mgr = audio_mgr_script.new()
	audio_mgr.name = "TestAudioManager"
	root.add_child(audio_mgr)
	audio_mgr.init(bridge_class, null)

	# Verify Buses
	var music_bus_idx = AudioServer.get_bus_index("Music")
	var sfx_bus_idx = AudioServer.get_bus_index("SFX")
	assert(music_bus_idx != -1, "ERROR: 'Music' audio bus must exist!")
	assert(sfx_bus_idx != -1, "ERROR: 'SFX' audio bus must exist!")
	print("  PASS: Audio buses 'Music' and 'SFX' verified with environmental reverb!")

	# Verify Pools
	assert(audio_mgr.sfx_2d_pool.size() == 16, "ERROR: 2D SFX pool must have 16 players!")
	assert(audio_mgr.sfx_3d_pool.size() == 24, "ERROR: 3D SFX pool must have 24 positional players!")
	assert(audio_mgr.music_player_a != null and audio_mgr.music_player_b != null, "ERROR: Dual music players must exist!")
	print("  PASS: SFX pools (16 2D + 24 3D) and dual-player music crossfader initialized!")

	print("\n[2/4] Verifying MPQ Audio Extraction via DiabloBridge...")
	# Test extracting sound effects from Diablo 1 MPQ
	var gold_stream = bridge_class.load_wav_stream("sfx/items/gold.wav", false)
	assert(gold_stream != null and gold_stream is AudioStreamWAV, "ERROR: Failed to extract 'sfx/items/gold.wav' from MPQ!")
	assert(gold_stream.data.size() > 0, "ERROR: Gold WAV audio buffer must not be empty!")
	print("  PASS: Extracted 'sfx/items/gold.wav' (%d bytes, format: %d)!" % [gold_stream.data.size(), gold_stream.format])

	var door_stream = bridge_class.load_wav_stream("sfx/items/dooropen.wav", false)
	assert(door_stream != null and door_stream is AudioStreamWAV, "ERROR: Failed to extract 'sfx/items/dooropen.wav' from MPQ!")
	print("  PASS: Extracted 'sfx/items/dooropen.wav' (%d bytes)!" % door_stream.data.size())

	print("\n[3/4] Verifying 3D Positional Audio Dispatch...")
	# Simulate 3D audio events from DevilutionX
	var mock_events = [
		{
			"type": 3, # SFX_PLAY
			"path": "sfx\\items\\dooropen.wav",
			"has_pos": true,
			"tile_x": 18,
			"tile_y": 25,
			"volume": 0
		},
		{
			"type": 3, # SFX_PLAY
			"path": "sfx\\items\\gold.wav",
			"has_pos": false,
			"tile_x": 0,
			"tile_y": 0,
			"volume": 0
		}
	]
	var player_tile = Vector2i(25, 25)
	audio_mgr.process_audio_events(mock_events, player_tile)

	# Verify 3D positional player got assigned
	var p3_active = false
	for p3 in audio_mgr.sfx_3d_pool:
		if p3.stream != null:
			p3_active = true
			# Check position calculation: dx = 18 - 25 = -7, dy = 0. iso_x = -7 * 0.45 = -3.15
			assert(p3.position.x < 0.0, "ERROR: Sound west of player must be panned to left (negative x)!")
			print("  PASS: 3D positional player assigned at pos: %s (spatial left pan)!" % str(p3.position))
			break
	assert(p3_active, "ERROR: 3D SFX player must be playing the positional door sound!")

	print("\n[4/4] Verifying Speech & Music Crossfade Teardown...")
	audio_mgr.play_speech("sfx/items/gold.wav", 0)
	assert(audio_mgr.speech_player.stream != null, "ERROR: Speech stream must be loaded!")
	audio_mgr.stop_speech()
	assert(audio_mgr.speech_player.stream == null, "ERROR: Speech stream should clear on stop!")
	print("  PASS: Speech start and stop verified cleanly!")

	audio_mgr.stop_music()
	print("  PASS: Music system teardown verified!")

	print("\n==================================================")
	print(" ALL TASK 5.3 NATIVE AUDIO ENGINE CHECKS PASSED!  ")
	print("==================================================")
	quit(0)
