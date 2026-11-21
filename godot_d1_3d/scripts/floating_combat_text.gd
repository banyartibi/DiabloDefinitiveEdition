class_name FloatingCombatTextManager
extends Node3D

# Combat Event Types matching D1CombatEventType
enum EventType {
	DAMAGE_TO_MONSTER = 1,
	DAMAGE_TO_PLAYER = 2,
	MONSTER_DEATH = 3,
	PLAYER_DEATH = 4,
	PLAYER_BLOCK = 5,
	COMBAT_MISS = 6,
	PLAYER_LEVEL_UP = 7
}

class FloatingTextNode extends Node3D:
	var label: Label3D
	var velocity: Vector3 = Vector3.ZERO
	var elapsed: float = 0.0
	var lifetime: float = 0.85
	var base_scale: float = 1.0

	func _init(text: String, color: Color, outline_color: Color, font_size: int, is_crit: bool = false):
		label = Label3D.new()
		label.text = text
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = color
		label.outline_modulate = outline_color
		label.outline_size = 14 if is_crit else 10
		label.font_size = font_size
		label.pixel_size = 0.007
		label.render_priority = 10
		add_child(label)

		base_scale = 1.35 if is_crit else 1.0
		scale = Vector3.ONE * 0.4
		
		# Initial pop velocity with random lateral drift
		var rx = randf_range(-0.35, 0.35)
		var rz = randf_range(-0.35, 0.35)
		var vy = 2.4 if is_crit else 1.8
		velocity = Vector3(rx, vy, rz)

	func _process(delta: float) -> void:
		elapsed += delta
		if elapsed >= lifetime:
			queue_free()
			return

		# Parabolic motion
		position += velocity * delta
		velocity.y -= 1.8 * delta # gravity / slowdown

		# Pop-in scaling
		if elapsed < 0.12:
			var t = elapsed / 0.12
			var cur_s = lerp(0.4, base_scale * 1.25, t)
			scale = Vector3.ONE * cur_s
		elif elapsed < 0.25:
			var t = (elapsed - 0.12) / 0.13
			var cur_s = lerp(base_scale * 1.25, base_scale, t)
			scale = Vector3.ONE * cur_s

		# Alpha fade out in last 40% of lifetime
		var fade_start = lifetime * 0.55
		if elapsed > fade_start:
			var alpha = 1.0 - ((elapsed - fade_start) / (lifetime - fade_start))
			label.modulate.a = clampf(alpha, 0.0, 1.0)
			label.outline_modulate.a = clampf(alpha, 0.0, 1.0)

func spawn_fct(world_pos: Vector3, text: String, event_type: int, is_crit: bool = false, custom_color: Color = Color.WHITE) -> FloatingTextNode:
	var color := Color.WHITE
	var outline := Color(0.05, 0.05, 0.05, 0.95)
	var fsize := 38

	match event_type:
		EventType.DAMAGE_TO_MONSTER:
			if is_crit:
				color = Color(1.0, 0.84, 0.15, 1.0) # Radiant Gold
				outline = Color(0.35, 0.15, 0.0, 1.0)
				fsize = 52
			else:
				color = Color(1.0, 0.22, 0.22, 1.0) # Crimson Red
				outline = Color(0.20, 0.0, 0.0, 1.0)
				fsize = 38
		EventType.DAMAGE_TO_PLAYER:
			color = Color(1.0, 0.45, 0.15, 1.0) # Intense Orange
			outline = Color(0.30, 0.0, 0.0, 1.0)
			fsize = 42
		EventType.MONSTER_DEATH:
			color = Color(1.0, 0.88, 0.35, 1.0) # XP Gold
			outline = Color(0.25, 0.18, 0.02, 1.0)
			fsize = 36
		EventType.PLAYER_BLOCK:
			color = Color(0.25, 0.85, 1.0, 1.0) # Shield Cyan
			outline = Color(0.02, 0.15, 0.25, 1.0)
			fsize = 34
		EventType.COMBAT_MISS:
			color = Color(0.75, 0.75, 0.75, 0.85) # Dim Slate
			outline = Color(0.12, 0.12, 0.12, 0.9)
			fsize = 30
		EventType.PLAYER_LEVEL_UP:
			color = Color(1.0, 0.95, 0.70, 1.0) # Radiant Holy
			outline = Color(0.50, 0.35, 0.05, 1.0)
			fsize = 56
		_:
			if custom_color != Color.WHITE:
				color = custom_color

	var fnode = FloatingTextNode.new(text, color, outline, fsize, is_crit)
	fnode.position = world_pos + Vector3(0, 0.75, 0)
	add_child(fnode)
	return fnode
