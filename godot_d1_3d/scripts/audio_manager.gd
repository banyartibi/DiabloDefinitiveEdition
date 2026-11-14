extends Node
class_name D1AudioManager

# References
var diablo_bridge: Node = null
var parent_3d: Node3D = null

# Audio stream RAM cache: path -> AudioStreamWAV
var stream_cache: Dictionary = {}

# Music System (Dual-Player Crossfade)
var music_player_a: AudioStreamPlayer = null
var music_player_b: AudioStreamPlayer = null
var active_music_player: AudioStreamPlayer = null
var current_music_path: String = ""
var music_tween: Tween = null
var music_volume_db: float = -6.0

# SFX Pools
var sfx_2d_pool: Array[AudioStreamPlayer] = []
var sfx_3d_pool: Array[AudioStreamPlayer3D] = []
var pool_size_2d: int = 16
var pool_size_3d: int = 24
var sfx_volume_db: float = 4.0

# Speech / Dialogue Player
var speech_player: AudioStreamPlayer = null

func init(p_bridge: Node, p_parent_3d: Node3D) -> void:
	diablo_bridge = p_bridge
	parent_3d = p_parent_3d
	
	setup_audio_buses()
	setup_music_players()
	setup_speech_player()
	setup_sfx_pools()
	print("[Godot-D1 Audio] Native Godot 4.7 Audio Engine initialized with 3D Spatial SFX and Crossfade Music!")

func setup_audio_buses() -> void:
	# Ensure "Music" bus exists (Atmospheric dungeon ambient background)
	var m_idx = AudioServer.get_bus_index("Music")
	if m_idx == -1:
		m_idx = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(m_idx, "Music")
		AudioServer.set_bus_send(m_idx, "Master")
	AudioServer.set_bus_volume_db(m_idx, -8.0)
		
	# Ensure "SFX" bus exists with subtle environmental dungeon reverb and punchy presence
	var s_idx = AudioServer.get_bus_index("SFX")
	if s_idx == -1:
		s_idx = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(s_idx, "SFX")
		AudioServer.set_bus_send(s_idx, "Master")
		
		var reverb = AudioEffectReverb.new()
		reverb.room_size = 0.18
		reverb.damping = 0.5
		reverb.wet = 0.03
		reverb.dry = 1.0
		AudioServer.add_bus_effect(s_idx, reverb)
	AudioServer.set_bus_volume_db(s_idx, 4.0)

func setup_music_players() -> void:
	music_player_a = AudioStreamPlayer.new()
	music_player_a.name = "D1_MusicPlayerA"
	music_player_a.bus = "Music"
	add_child(music_player_a)
	
	music_player_b = AudioStreamPlayer.new()
	music_player_b.name = "D1_MusicPlayerB"
	music_player_b.bus = "Music"
	add_child(music_player_b)
	
	active_music_player = music_player_a

func setup_speech_player() -> void:
	speech_player = AudioStreamPlayer.new()
	speech_player.name = "D1_SpeechPlayer"
	speech_player.bus = "SFX"
	add_child(speech_player)

func setup_sfx_pools() -> void:
	# 2D SFX Pool (UI, menus, speech, level-up, inventory)
	for i in range(pool_size_2d):
		var p = AudioStreamPlayer.new()
		p.name = "SFX2D_%02d" % i
		p.bus = "SFX"
		add_child(p)
		sfx_2d_pool.append(p)
		
	# 3D Positional SFX Pool (Monsters, doors, spells, chests, barrels, footsteps)
	var pool_root_3d = Node3D.new()
	pool_root_3d.name = "SFX3D_Pool"
	if parent_3d:
		parent_3d.add_child(pool_root_3d)
	else:
		add_child(pool_root_3d)
		
	for i in range(pool_size_3d):
		var p3 = AudioStreamPlayer3D.new()
		p3.name = "SFX3D_%02d" % i
		p3.bus = "SFX"
		p3.unit_size = 28.0
		p3.max_distance = 140.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
		p3.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		pool_root_3d.add_child(p3)
		sfx_3d_pool.append(p3)

func process_audio_events(events: Array, player_tile: Vector2i) -> void:
	for ev in events:
		var type = ev.get("type", 0)
		var path = ev.get("path", "")
		if type == 1: # MUSIC_PLAY
			play_music(path)
		elif type == 2: # MUSIC_STOP
			stop_music()
		elif type == 3: # SFX_PLAY
			var has_pos = ev.get("has_pos", false)
			var tile_x = ev.get("tile_x", 0)
			var tile_y = ev.get("tile_y", 0)
			var vol = ev.get("volume", 0)
			play_sfx(path, tile_x, tile_y, has_pos, player_tile, vol)
		elif type == 4: # STREAM_PLAY (Speech/Dialogue)
			var vol = ev.get("volume", 0)
			play_speech(path, vol)
		elif type == 5: # STREAM_STOP (Stop Speech/Dialogue)
			stop_speech()

func play_music(raw_path: String) -> void:
	var clean_path = raw_path.replace("\\", "/").strip_edges()
	if clean_path.is_empty():
		return
		
	# If already playing this track, ensure volume is up and don't re-trigger crossfade
	if clean_path == current_music_path and active_music_player and active_music_player.playing:
		if not music_tween or not music_tween.is_valid():
			active_music_player.volume_db = music_volume_db
		return
		
	var stream = get_or_load_stream(clean_path, true)
	if not stream:
		print("[Godot-D1 Audio] Warning: could not load music stream (MPQ not ready or missing): ", clean_path)
		return
		
	current_music_path = clean_path
	var incoming_player = music_player_b if active_music_player == music_player_a else music_player_a
	var outgoing_player = active_music_player
	
	incoming_player.stream = stream
	incoming_player.volume_db = -80.0
	if incoming_player.is_inside_tree():
		incoming_player.play()
	
	if music_tween and music_tween.is_valid():
		music_tween.kill()
		
	music_tween = create_tween().set_parallel(true)
	music_tween.tween_property(incoming_player, "volume_db", music_volume_db, 0.8).set_trans(Tween.TRANS_SINE)
	if outgoing_player and outgoing_player.playing:
		music_tween.tween_property(outgoing_player, "volume_db", -80.0, 0.8).set_trans(Tween.TRANS_SINE)
		music_tween.chain().tween_callback(outgoing_player.stop)
		
	active_music_player = incoming_player
	print("[Godot-D1 Audio] Crossfading to Music Track: ", clean_path)

func stop_music() -> void:
	current_music_path = ""
	if music_tween and music_tween.is_valid():
		music_tween.kill()
		music_tween = null
	var is_a_playing = music_player_a and music_player_a.playing
	var is_b_playing = music_player_b and music_player_b.playing
	if not is_a_playing and not is_b_playing:
		return
	music_tween = create_tween().set_parallel(true)
	if is_a_playing:
		music_tween.tween_property(music_player_a, "volume_db", -80.0, 0.6).set_trans(Tween.TRANS_SINE)
		music_tween.chain().tween_callback(music_player_a.stop)
	if is_b_playing:
		music_tween.tween_property(music_player_b, "volume_db", -80.0, 0.6).set_trans(Tween.TRANS_SINE)
		music_tween.chain().tween_callback(music_player_b.stop)

func play_speech(raw_path: String, vol_offset: int = 0) -> void:
	stop_speech()
	var clean_path = raw_path.replace("\\", "/").strip_edges()
	if clean_path.is_empty():
		return
	var stream = get_or_load_stream(clean_path, false)
	if not stream:
		return
	if speech_player:
		speech_player.volume_db = sfx_volume_db + clamp(float(vol_offset) / 100.0, -20.0, 6.0)
		speech_player.stream = stream
		if speech_player.is_inside_tree():
			speech_player.play()

func stop_speech() -> void:
	if speech_player:
		if speech_player.playing:
			speech_player.stop()
		speech_player.stream = null

func play_sfx(raw_path: String, tile_x: int, tile_y: int, has_pos: bool, player_tile: Vector2i, vol_offset: int = 0) -> void:
	var clean_path = raw_path.replace("\\", "/").strip_edges()
	if clean_path.is_empty():
		return
		
	var stream = get_or_load_stream(clean_path, false)
	if not stream:
		return

	# Check if native 3D sandbox is active
	var sandbox = null
	if parent_3d and "sandbox_instance" in parent_3d:
		sandbox = parent_3d.sandbox_instance
	var is_3d_active = (sandbox != null and sandbox.is_sandbox_active)

	if has_pos:
		# Play via 3D Positional Audio Pool
		var p3 = get_idle_3d_player()
		if not p3:
			return

		if is_3d_active:
			# Authentic 3D world coordinates in Sandbox
			var sound_wpos = sandbox.tile_to_world_3d(float(tile_x), float(tile_y)) + Vector3(0, 1.0, 0)
			p3.global_position = sound_wpos
		else:
			# Isometric spatial pan relative to player (Mode 0 / 2.5D / headless)
			var dx = float(tile_x - player_tile.x)
			var dy = float(tile_y - player_tile.y)
			var iso_x = (dx - dy) * 0.45
			var iso_y = (dx + dy) * 0.22
			p3.position = Vector3(iso_x, iso_y, 0.0)

		# Godot 3D spatial attenuation handles falloff naturally; avoid double software distance cut
		p3.volume_db = sfx_volume_db + 1.0
		p3.stream = stream
		if p3.is_inside_tree():
			p3.play()
	else:
		# Play via 2D Non-Positional Pool (UI, menus, speech, or Mode 0 / Mode 1 fallback)
		var p2 = get_idle_2d_player()
		if not p2:
			return
		p2.volume_db = sfx_volume_db + clampf(float(vol_offset) / 220.0, -7.0, 3.0)
		p2.stream = stream
		if p2.is_inside_tree():
			p2.play()

func get_idle_2d_player() -> AudioStreamPlayer:
	for p in sfx_2d_pool:
		if not p.playing:
			return p
	# Pool full: steal first player
	return sfx_2d_pool[0]

func get_idle_3d_player() -> AudioStreamPlayer3D:
	for p in sfx_3d_pool:
		if not p.playing:
			return p
	# Pool full: steal first player
	return sfx_3d_pool[0]

func get_or_load_stream(path: String, is_music: bool) -> AudioStreamWAV:
	if stream_cache.has(path):
		return stream_cache[path]
		
	var stream: AudioStreamWAV = null
	
	# 1. Check for HD asset override in local workspace
	var override_paths = [
		"res://assets/" + path,
		"/home/biti/antigravity/magical-bell/assets/" + path
	]
	for op in override_paths:
		if FileAccess.file_exists(op):
			var file = FileAccess.open(op, FileAccess.READ)
			if file:
				var bytes = file.get_buffer(file.get_length())
				stream = AudioStreamWAV.load_from_buffer(bytes)
				if stream:
					print("[Godot-D1 Audio] Loaded HD Audio Override from disk: ", op)
					break
					
	# 2. Load directly from MPQ via DiabloBridge GDExtension
	if not stream and diablo_bridge != null and diablo_bridge.has_method("load_wav_stream"):
		stream = diablo_bridge.load_wav_stream(path, is_music)
		
	if stream:
		if is_music:
			var bytes_per_sample = 2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1
			var channels = 2 if stream.stereo else 1
			var frame_size = bytes_per_sample * channels
			var total_frames = int(stream.data.size() / frame_size) if frame_size > 0 else 0
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = total_frames
		stream_cache[path] = stream
		return stream
		
	return null
