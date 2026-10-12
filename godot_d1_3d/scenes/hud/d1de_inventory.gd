extends Control

var diablo_bridge = null
# Explicit HUD wiring (set by the scene that owns both). Falls back to the "d1de_hud" group, which
# is how it is found at runtime; the direct reference keeps the wiring testable without a tree.
var hud: Node = null

# --- Task 2 Step 5: native logic authority (shadow mode) ---
# C++ still executes; the native layer predicts and compares. Nothing is handed
# over until D1LogicAuthority reports enough clean parity checks.
var logic_authority = preload("res://scripts/logic/d1_logic_authority.gd").new()
var item_logic = preload("res://scripts/logic/d1_item_logic.gd")
var rng_class = preload("res://scripts/logic/d1_rng.gd")
var _pending_prediction: Dictionary = {}


func _player_state() -> Dictionary:
	if diablo_bridge == null:
		return {}
	return {
		"hp": diablo_bridge.get_player_hp(),
		"max_hp": diablo_bridge.get_player_max_hp(),
		"mana": diablo_bridge.get_player_mana(),
		"max_mana": diablo_bridge.get_player_max_mana(),
		# The mirror predicts in 64ths; without the raw values it falls back to display units and
		# is off by one whenever the sub-64th remainder is non-zero.
		"hp_raw": diablo_bridge.get_player_hp_raw(),
		"max_hp_raw": diablo_bridge.get_player_max_hp_raw(),
		"mana_raw": diablo_bridge.get_player_mana_raw(),
		"max_mana_raw": diablo_bridge.get_player_max_mana_raw(),
		"item_flags": diablo_bridge.get_player_item_flags(),
		"class": diablo_bridge.get_player_class(),
		"spell_levels": {},
	}


func _item_at(slot_type: int, idx: int) -> Dictionary:
	if diablo_bridge == null:
		return {}
	var items: Array = diablo_bridge.get_player_equipment() if slot_type == 0 else diablo_bridge.get_player_backpack()
	for it in items:
		if slot_type == 2:
			if int(it.get("inv_list_index", -1)) == idx:
				return it
		elif int(it.get("slot_id", -1)) == idx:
			return it
	return {}


func _belt_item_at(belt_idx: int) -> Dictionary:
	if diablo_bridge == null:
		return {}
	var items: Array = diablo_bridge.get_belt_items()
	if belt_idx < 0 or belt_idx >= items.size():
		return {}
	return items[belt_idx]


func _find_hud() -> Node:
	if hud != null:
		return hud
	var tree = get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("d1de_hud")


func _shadow_use(item: Dictionary) -> void:
	if diablo_bridge == null or item.is_empty():
		return
	if logic_authority.get_authority("inventory_item_use") == logic_authority.AUTH_CPP:
		return
	var ctx = {"hellfire": diablo_bridge.is_hellfire()}
	if not item_logic.is_usable(item, ctx):
		return
	# The action is only QUEUED here (PushBridgeAction). The engine thread executes it on the
	# next drain, so we cannot compare yet: store the baseline and verify in _process() once the
	# drain counter moves.
	_pending_prediction = {
		"item": item,
		"before": _player_state(),
		"seq_before": diablo_bridge.get_last_action_seq(),
		"deadline": Time.get_ticks_msec() + 2000,
	}
	# AUTH_NATIVE handover: the mirror's prediction is trusted, so the HUD reacts on the click
	# instead of waiting for the engine thread to drain the queued action. This does not replace the
	# drain-time comparison in _shadow_verify(), which stays the parity record: if the two disagree,
	# the sequence has already advanced, the offset is dropped, and the engine value takes over.
	# The seed here is the push-time seed, not the execution-time seed, so the optimistic number can
	# be off; that is exactly what the drain check measures.
	if logic_authority.get_authority("inventory_item_use") == logic_authority.AUTH_NATIVE:
		var pred_now = item_logic.predict_use_item(
			item, _pending_prediction["before"], rng_class.new(diablo_bridge.get_rng_seed()), ctx)
		var d_hp := int(pred_now.get("effects", {}).get("hp", 0))
		var d_mana := int(pred_now.get("effects", {}).get("mana", 0))
		if d_hp != 0 or d_mana != 0:
			var target = _find_hud()
			if target != null and target.has_method("apply_optimistic_item_delta"):
				target.apply_optimistic_item_delta(d_hp, d_mana, int(_pending_prediction["seq_before"]))


func _shadow_verify() -> void:
	if _pending_prediction.is_empty() or diablo_bridge == null:
		return
	var seq_before := int(_pending_prediction.get("seq_before", 0))
	if diablo_bridge.get_last_action_seq() <= seq_before:
		if Time.get_ticks_msec() > int(_pending_prediction.get("deadline", 0)):
			_pending_prediction = {}  # action was dropped by the engine (not executed)
		return  # still queued on the engine thread - do not compare state that has not changed
	var item: Dictionary = _pending_prediction.get("item", {})
	var before: Dictionary = _pending_prediction.get("before", {})
	var ctx = {"hellfire": diablo_bridge.is_hellfire()}
	# Predict with the seed the engine had AT EXECUTION TIME. Reading the seed at push time is not
	# deterministic: the engine consumes RNG between the read and the drain.
	# Caveat: in combat the player can be damaged between push and drain, which is outside the
	# item-use model; those checks are only trustworthy in a quiescent state (town / no monsters).
	var pred = item_logic.predict_use_item(item, before, rng_class.new(diablo_bridge.get_last_action_rng_seed()), ctx)
	var after = _player_state()
	var native_result = {"hp": pred["effects"]["hp"], "mana": pred["effects"]["mana"]}
	var cpp_result = {"hp": after["hp"] - before["hp"], "mana": after["mana"] - before["mana"]}
	var ok = logic_authority.record("inventory_item_use", native_result, cpp_result)
	print("[PARITY] %s  native=%s cpp=%s seed=%d%s" % [
		"OK" if ok else "MISMATCH", native_result, cpp_result, diablo_bridge.get_last_action_rng_seed(),
		"  [rng]" if pred["rng_dependent"] else "  [deterministic]"])
	_pending_prediction = {}


func _process(_delta: float) -> void:
	# Deferred parity check: runs on the frame AFTER the engine thread drained the queued action.
	if not _pending_prediction.is_empty():
		_shadow_verify()


func _exit_tree() -> void:
	print("[PARITY REPORT] ", logic_authority.report())

# Equipment slot indices (matching DevilutionX inv_body_loc)
const EQUIP_HEAD = 0
const EQUIP_RING_LEFT = 1
const EQUIP_RING_RIGHT = 2
const EQUIP_AMULET = 3
const EQUIP_HAND_LEFT = 4
const EQUIP_HAND_RIGHT = 5
const EQUIP_CHEST = 6

const FONT_EXOCET = preload("res://assets/fonts/Exocet.ttf")

# Quality border & text colors
const COLOR_NORMAL = Color(0.85, 0.82, 0.75, 1.0)
const COLOR_MAGIC = Color(0.45, 0.70, 1.0, 1.0)
const COLOR_UNIQUE = Color(1.0, 0.85, 0.35, 1.0)
const COLOR_UNUSABLE = Color(0.85, 0.28, 0.28, 1.0)

# Cell dimensions for backpack grid - enlarged to 40px to fill the window
const CELL_SIZE = 40.0
const CELL_GAP = 2.0
const CELL_STEP = CELL_SIZE + CELL_GAP # 42.0

# Node references
@onready var gold_label: Label = find_child("GoldLabel", true, false)
@onready var close_btn: Button = find_child("CloseBtn", true, false)

# Paperdoll slots
@onready var slot_head: Control = find_child("HeadSlot", true, false)
@onready var slot_amulet: Control = find_child("AmuletSlot", true, false)
@onready var slot_hand_left: Control = find_child("HandLeftSlot", true, false)
@onready var slot_chest: Control = find_child("ChestSlot", true, false)
@onready var slot_hand_right: Control = find_child("HandRightSlot", true, false)
@onready var slot_ring_left: Control = find_child("RingLeftSlot", true, false)
@onready var slot_ring_right: Control = find_child("RingRightSlot", true, false)

# Backpack nodes
@onready var grid_cells: GridContainer = find_child("GridCells", true, false)
@onready var items_overlay: Control = find_child("ItemsOverlay", true, false)

# Textures
const TEX_HEAL = preload("res://assets/hud/potion_heal.png")
const TEX_MANA = preload("res://assets/hud/potion_mana.png")
const TEX_REJUV = preload("res://assets/hud/potion_rejuv.png")
const TEX_SCROLL = preload("res://assets/hud/scroll.png")
const TEX_OIL = preload("res://assets/hud/potion_oil.png")
const TEX_SLOT_FRAME = preload("res://assets/hud/slot_frame.png")
const TEX_SLOT_9PATCH = preload("res://assets/hud/gothic_slot_9patch.png")
const TEX_SOCKET_LOCKED = preload("res://assets/hud/gothic_socket_locked.png")

# Dedicated Item Tooltip
@onready var tooltip: PanelContainer = $Tooltip
@onready var tooltip_title: Label = $Tooltip/Margin/VBox/TitleLabel
@onready var tooltip_divider: ColorRect = $Tooltip/Margin/VBox/Divider
@onready var tooltip_stats: Label = $Tooltip/Margin/VBox/StatsLabel

# Belt nodes (8 active sockets with 2 decorative disabled sockets on outer ends)
@onready var belt_cells: HBoxContainer = find_child("BeltCells", true, false)
var belt_slot_nodes: Array[Control] = []

var equip_slots_map: Dictionary = {}
var hovered_item_data = null
var last_inventory_version: int = -1
var hd_item_cache: Dictionary = {}

func get_item_texture_hd(curs_id: int) -> Texture2D:
	if curs_id <= 0:
		return null
	if hd_item_cache.has(curs_id):
		return hd_item_cache[curs_id]

	var hd_path = "res://assets/items_hd/%d.png" % curs_id
	if FileAccess.file_exists(hd_path):
		var img = Image.load_from_file(ProjectSettings.globalize_path(hd_path))
		if img and not img.is_empty() and not _is_black_silhouette(img):
			var tex = ImageTexture.create_from_image(img)
			hd_item_cache[curs_id] = tex
			return tex

	if diablo_bridge and diablo_bridge.has_method("get_item_texture"):
		var tex = diablo_bridge.get_item_texture(curs_id)
		if tex:
			hd_item_cache[curs_id] = tex
			return tex
	return null

func _is_black_silhouette(img: Image) -> bool:
	var w = img.get_width()
	var h = img.get_height()
	if w <= 0 or h <= 0:
		return true
	var max_val: float = 0.0
	for sy in [0.25, 0.5, 0.75]:
		for sx in [0.25, 0.5, 0.75]:
			var c = img.get_pixel(int(w * sx), int(h * sy))
			if c.a > 0.1:
				max_val = max(max_val, c.r, c.g, c.b)
	return max_val < 0.03

func _ready():
	equip_slots_map = {
		EQUIP_HEAD: slot_head,
		EQUIP_RING_LEFT: slot_ring_left,
		EQUIP_RING_RIGHT: slot_ring_right,
		EQUIP_AMULET: slot_amulet,
		EQUIP_HAND_LEFT: slot_hand_left,
		EQUIP_HAND_RIGHT: slot_hand_right,
		EQUIP_CHEST: slot_chest,
	}

	if close_btn:
		close_btn.pressed.connect(func():
			if diablo_bridge and diablo_bridge.has_method("toggle_inventory"):
				diablo_bridge.toggle_inventory()
			visible = false
		)

	_init_equipment_slots()
	_init_belt_cells()
	_init_backpack_cells()
	if tooltip:
		tooltip.visible = false

func set_bridge(bridge):
	diablo_bridge = bridge
	update_inventory()

func _init_equipment_slots():
	for slot_idx in equip_slots_map:
		var slot_node: Control = equip_slots_map[slot_idx]
		if slot_node:
			slot_node.mouse_filter = Control.MOUSE_FILTER_STOP
			slot_node.gui_input.connect(func(event: InputEvent):
				_on_equip_slot_gui_input(slot_idx, event)
			)
			slot_node.mouse_entered.connect(func():
				_on_equip_slot_mouse_entered(slot_idx)
			)
			slot_node.mouse_exited.connect(func():
				_on_item_mouse_exited()
			)

func _init_belt_cells():
	if not belt_cells:
		return
	for child in belt_cells.get_children():
		child.queue_free()
	belt_slot_nodes.clear()

	for col in range(10):
		var cell = Control.new()
		cell.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
		cell.size = Vector2(CELL_SIZE, CELL_SIZE)

		if col == 0 or col == 9:
			# Inactive / locked decorative sockets on outer edges
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var lock_tex = TextureRect.new()
			lock_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
			lock_tex.texture = TEX_SOCKET_LOCKED
			lock_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			lock_tex.stretch_mode = TextureRect.STRETCH_SCALE
			lock_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(lock_tex)
		else:
			# Active Belt slot 0..7
			var belt_idx = col - 1
			cell.mouse_filter = Control.MOUSE_FILTER_STOP
			var frame_tex = TextureRect.new()
			frame_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
			frame_tex.texture = TEX_SLOT_FRAME
			frame_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			frame_tex.stretch_mode = TextureRect.STRETCH_SCALE
			frame_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(frame_tex)

			# Slot number indicator badge (1..8)
			var num_lbl = Label.new()
			num_lbl.text = str(belt_idx + 1)
			num_lbl.position = Vector2(4, 2)
			num_lbl.add_theme_font_override("font", FONT_EXOCET)
			num_lbl.add_theme_font_size_override("font_size", 10)
			num_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45, 1.0))
			num_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1.0))
			num_lbl.add_theme_constant_override("shadow_outline_size", 3)
			num_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(num_lbl)

			# Item Icon TextureRect
			var icon_rect = TextureRect.new()
			icon_rect.name = "ItemIcon"
			icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon_rect.visible = false
			cell.add_child(icon_rect)

			# Count Label
			var count_lbl = Label.new()
			count_lbl.name = "CountLabel"
			count_lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			count_lbl.offset_left = -18.0
			count_lbl.offset_top = -16.0
			count_lbl.add_theme_font_override("font", FONT_EXOCET)
			count_lbl.add_theme_font_size_override("font_size", 10)
			count_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
			count_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
			count_lbl.add_theme_constant_override("shadow_outline_size", 2)
			count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			count_lbl.visible = false
			cell.add_child(count_lbl)

			# Event handling
			cell.gui_input.connect(func(event: InputEvent):
				_on_belt_slot_gui_input(belt_idx, event)
			)
			cell.mouse_entered.connect(func():
				_on_belt_slot_mouse_entered(belt_idx, cell.global_position)
			)
			cell.mouse_exited.connect(func():
				_on_item_mouse_exited()
			)

			belt_slot_nodes.append(cell)

		belt_cells.add_child(cell)

func _init_backpack_cells():
	if not grid_cells:
		return
	for child in grid_cells.get_children():
		child.queue_free()

	for i in range(40):
		var cell = Panel.new()
		cell.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		var cell_style = StyleBoxTexture.new()
		cell_style.texture = TEX_SLOT_9PATCH
		cell_style.texture_margin_left = 6
		cell_style.texture_margin_top = 6
		cell_style.texture_margin_right = 6
		cell_style.texture_margin_bottom = 6
		cell_style.modulate_color = Color(0.55, 0.52, 0.48, 0.45)
		cell.add_theme_stylebox_override("panel", cell_style)

		var cell_idx = i
		cell.gui_input.connect(func(event: InputEvent):
			_on_backpack_cell_gui_input(cell_idx, event)
		)
		grid_cells.add_child(cell)

func check_and_update():
	if not diablo_bridge:
		return
	var ver = 0
	if diablo_bridge.has_method("get_inventory_version"):
		ver = diablo_bridge.get_inventory_version()
	if ver != last_inventory_version:
		update_inventory()

func update_inventory():
	if not diablo_bridge:
		return
	if diablo_bridge.has_method("get_inventory_version"):
		last_inventory_version = diablo_bridge.get_inventory_version()

	# 1. Update Gold readout
	if gold_label and diablo_bridge.has_method("get_player_gold"):
		var gold = diablo_bridge.get_player_gold()
		gold_label.text = "Gold: %s" % _format_number(gold)

	# 2. Update Equipment Paperdoll
	_update_equipment()

	# 3. Update Belt Sockets
	_update_belt()

	# 4. Update Backpack Items
	_update_backpack()

func _update_belt():
	if not diablo_bridge or not diablo_bridge.has_method("get_belt_items"):
		return
	var belt = diablo_bridge.get_belt_items()
	for i in range(min(belt_slot_nodes.size(), belt.size())):
		var slot_node = belt_slot_nodes[i]
		var item = belt[i]
		var type = item.get("type", 0)
		var count = item.get("count", 0)
		var item_name = item.get("name", "")

		var icon = slot_node.get_node_or_null("ItemIcon") as TextureRect
		var count_lbl = slot_node.get_node_or_null("CountLabel") as Label

		if type != 0 and item_name != "":
			slot_node.set_meta("belt_item", item)
			var slot_tex: Texture2D = null
			if diablo_bridge.has_method("get_belt_item_texture"):
				slot_tex = diablo_bridge.get_belt_item_texture(i)
			if not slot_tex:
				match type:
					1, 2: slot_tex = TEX_HEAL
					3, 4: slot_tex = TEX_MANA
					5, 6, 7: slot_tex = TEX_REJUV
					8: slot_tex = TEX_SCROLL
					9: slot_tex = TEX_OIL
			if icon:
				icon.texture = slot_tex
				icon.visible = (slot_tex != null)
			if count_lbl:
				if count > 1:
					count_lbl.text = "x%d" % count
					count_lbl.visible = true
				else:
					count_lbl.visible = false
		else:
			slot_node.remove_meta("belt_item")
			if icon:
				icon.texture = null
				icon.visible = false
			if count_lbl:
				count_lbl.visible = false

func _update_equipment():
	if not diablo_bridge or not diablo_bridge.has_method("get_player_equipment"):
		return

	var eq_items = diablo_bridge.get_player_equipment()
	var equipped_by_slot = {}
	for it in eq_items:
		var s = it.get("slot_id", -1)
		if s >= 0:
			equipped_by_slot[s] = it

	for slot_idx in equip_slots_map:
		var slot_node: Control = equip_slots_map[slot_idx]
		if not slot_node:
			continue

		var icon_rect: TextureRect = slot_node.get_node_or_null("Icon")
		var border_panel: Panel = slot_node.get_node_or_null("Border")
		var placeholder: Label = slot_node.get_node_or_null("Placeholder")

		if slot_idx in equipped_by_slot:
			var item = equipped_by_slot[slot_idx]
			slot_node.set_meta("item_data", item)

			var curs_id = item.get("curs_id", 0)
			var tex = get_item_texture_hd(curs_id)
			if icon_rect:
				icon_rect.texture = tex
				icon_rect.visible = (tex != null)
				if not item.get("can_use", true):
					icon_rect.modulate = COLOR_UNUSABLE
				else:
					icon_rect.modulate = Color.WHITE

			if placeholder:
				placeholder.visible = false

			if border_panel:
				var q = item.get("quality", 0)
				var bcol = COLOR_NORMAL
				if q == 1: bcol = COLOR_MAGIC
				elif q == 2: bcol = COLOR_UNIQUE
				if not item.get("can_use", true):
					bcol = COLOR_UNUSABLE
				_set_slot_border_color(border_panel, bcol)
		else:
			slot_node.remove_meta("item_data")
			if icon_rect:
				icon_rect.texture = null
				icon_rect.visible = false
			if placeholder:
				placeholder.visible = true
			if border_panel:
				_set_slot_border_color(border_panel, Color(0.35, 0.28, 0.20, 0.5))

func _update_backpack():
	if not diablo_bridge or not diablo_bridge.has_method("get_player_backpack"):
		return
	if not items_overlay:
		return

	# Clear previous overlay item controls
	for c in items_overlay.get_children():
		c.queue_free()

	var bp_items = diablo_bridge.get_player_backpack()
	for it in bp_items:
		var cell_x = it.get("cell_x", 0)
		var cell_y = it.get("cell_y", 0)
		var cell_w = it.get("cell_w", 1)
		var cell_h = it.get("cell_h", 1)
		var curs_id = it.get("curs_id", 0)
		var quality = it.get("quality", 0)
		var can_use = it.get("can_use", true)
		var cell_idx = it.get("slot_id", cell_y * 10 + cell_x)
		var inv_list_idx = it.get("inv_list_index", -1)

		var pos_x = float(cell_x) * CELL_STEP
		var pos_y = float(cell_y) * CELL_STEP
		var size_w = float(cell_w) * CELL_STEP - CELL_GAP
		var size_h = float(cell_h) * CELL_STEP - CELL_GAP

		var item_ctrl = Control.new()
		item_ctrl.position = Vector2(pos_x, pos_y)
		item_ctrl.size = Vector2(size_w, size_h)
		item_ctrl.custom_minimum_size = Vector2(size_w, size_h)
		item_ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
		item_ctrl.set_meta("item_data", it)

		# Backdrop panel
		var panel = Panel.new()
		panel.set_anchors_preset(PRESET_FULL_RECT)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb = StyleBoxTexture.new()
		sb.texture = TEX_SLOT_9PATCH
		sb.texture_margin_left = 11
		sb.texture_margin_top = 11
		sb.texture_margin_right = 11
		sb.texture_margin_bottom = 11
		panel.add_theme_stylebox_override("panel", sb)

		if quality == 1:
			panel.modulate = Color(0.55, 0.75, 1.0, 0.85)
		elif quality == 2:
			panel.modulate = Color(1.05, 0.92, 0.55, 0.90)
		elif not can_use:
			panel.modulate = Color(0.95, 0.45, 0.45, 0.85)
		else:
			panel.modulate = Color(0.85, 0.82, 0.78, 0.80)

		item_ctrl.add_child(panel)

		# Item Sprite Texture
		var tex_rect = TextureRect.new()
		tex_rect.set_anchors_preset(PRESET_FULL_RECT)
		tex_rect.offset_left = 2.0
		tex_rect.offset_top = 2.0
		tex_rect.offset_right = -2.0
		tex_rect.offset_bottom = -2.0
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tex = get_item_texture_hd(curs_id)
		if tex:
			tex_rect.texture = tex
		if not can_use:
			tex_rect.modulate = COLOR_UNUSABLE
		item_ctrl.add_child(tex_rect)

		# Input handling
		item_ctrl.gui_input.connect(func(event: InputEvent):
			_on_backpack_item_gui_input(cell_idx, inv_list_idx, event)
		)
		item_ctrl.mouse_entered.connect(func():
			_show_item_tooltip(it, item_ctrl.global_position)
		)
		item_ctrl.mouse_exited.connect(func():
			_on_item_mouse_exited()
		)

		items_overlay.add_child(item_ctrl)

func _set_slot_border_color(panel: Panel, col: Color):
	if not panel: return
	if col == COLOR_MAGIC:
		panel.modulate = Color(0.55, 0.75, 1.0, 0.85)
	elif col == COLOR_UNIQUE:
		panel.modulate = Color(1.05, 0.92, 0.55, 0.90)
	elif col == COLOR_UNUSABLE:
		panel.modulate = Color(0.95, 0.45, 0.45, 0.85)
	else:
		panel.modulate = Color(0.85, 0.82, 0.78, 0.75)

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if diablo_bridge and diablo_bridge.has_method("get_cursor_id"):
			var cid = diablo_bridge.get_cursor_id()
			if cid > 1 and cid < 12:
				if diablo_bridge.has_method("cancel_targeting_cursor"):
					diablo_bridge.cancel_targeting_cursor()
				update_inventory()
				_on_item_mouse_exited()
				accept_event()

func _on_equip_slot_gui_input(slot_idx: int, event: InputEvent):
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var mb = event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if diablo_bridge and diablo_bridge.has_method("click_inventory_slot"):
			diablo_bridge.click_inventory_slot(0, slot_idx, mb.shift_pressed, mb.ctrl_pressed)
			update_inventory()
			_on_item_mouse_exited()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		if diablo_bridge and diablo_bridge.has_method("get_cursor_id"):
			var cid = diablo_bridge.get_cursor_id()
			if cid > 1 and cid < 12:
				if diablo_bridge.has_method("cancel_targeting_cursor"):
					diablo_bridge.cancel_targeting_cursor()
				update_inventory()
				_on_item_mouse_exited()
				return
		if diablo_bridge and diablo_bridge.has_method("use_inventory_slot"):
			_shadow_use(_item_at(0, slot_idx))
			diablo_bridge.use_inventory_slot(0, slot_idx)
			update_inventory()
			_shadow_verify()
			_on_item_mouse_exited()

func _on_backpack_cell_gui_input(cell_idx: int, event: InputEvent):
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var mb = event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if diablo_bridge and diablo_bridge.has_method("click_inventory_slot"):
			diablo_bridge.click_inventory_slot(1, cell_idx, mb.shift_pressed, mb.ctrl_pressed)
			update_inventory()
			_on_item_mouse_exited()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		if diablo_bridge and diablo_bridge.has_method("get_cursor_id"):
			var cid = diablo_bridge.get_cursor_id()
			if cid > 1 and cid < 12:
				if diablo_bridge.has_method("cancel_targeting_cursor"):
					diablo_bridge.cancel_targeting_cursor()
				update_inventory()
				_on_item_mouse_exited()
				return
		if diablo_bridge and diablo_bridge.has_method("use_inventory_slot"):
			_shadow_use(_item_at(1, cell_idx))
			diablo_bridge.use_inventory_slot(1, cell_idx)
			update_inventory()
			_shadow_verify()
			_on_item_mouse_exited()

func _on_backpack_item_gui_input(cell_idx: int, inv_list_idx: int, event: InputEvent):
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var mb = event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if diablo_bridge and diablo_bridge.has_method("click_inventory_slot"):
			diablo_bridge.click_inventory_slot(1, cell_idx, mb.shift_pressed, mb.ctrl_pressed)
			update_inventory()
			_on_item_mouse_exited()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		if diablo_bridge and diablo_bridge.has_method("get_cursor_id"):
			var cid = diablo_bridge.get_cursor_id()
			if cid > 1 and cid < 12:
				if diablo_bridge.has_method("cancel_targeting_cursor"):
					diablo_bridge.cancel_targeting_cursor()
				update_inventory()
				_on_item_mouse_exited()
				return
		if diablo_bridge and diablo_bridge.has_method("use_inventory_slot"):
			if inv_list_idx >= 0:
				_shadow_use(_item_at(2, inv_list_idx))
				diablo_bridge.use_inventory_slot(2, inv_list_idx)
			else:
				_shadow_use(_item_at(1, cell_idx))
				diablo_bridge.use_inventory_slot(1, cell_idx)
			update_inventory()
			_shadow_verify()
			_on_item_mouse_exited()

func _on_belt_slot_gui_input(belt_idx: int, event: InputEvent):
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var mb = event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if diablo_bridge and diablo_bridge.has_method("click_belt_slot"):
			diablo_bridge.click_belt_slot(belt_idx)
			update_inventory()
			_on_item_mouse_exited()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		if diablo_bridge and diablo_bridge.has_method("get_cursor_id"):
			var cid = diablo_bridge.get_cursor_id()
			if cid > 1 and cid < 12:
				if diablo_bridge.has_method("cancel_targeting_cursor"):
					diablo_bridge.cancel_targeting_cursor()
				update_inventory()
				_on_item_mouse_exited()
				return
		if diablo_bridge and diablo_bridge.has_method("use_belt_slot"):
			_shadow_use(_belt_item_at(belt_idx))
			diablo_bridge.use_belt_slot(belt_idx)
			update_inventory()
			_shadow_verify()
			_on_item_mouse_exited()

func _on_belt_slot_mouse_entered(belt_idx: int, pos: Vector2):
	if belt_idx >= 0 and belt_idx < belt_slot_nodes.size():
		var slot_node = belt_slot_nodes[belt_idx]
		if slot_node.has_meta("belt_item"):
			var it = slot_node.get_meta("belt_item")
			_show_item_tooltip(it, pos)

func _on_equip_slot_mouse_entered(slot_idx: int):
	var slot_node: Control = equip_slots_map.get(slot_idx)
	if slot_node and slot_node.has_meta("item_data"):
		var it = slot_node.get_meta("item_data")
		_show_item_tooltip(it, slot_node.global_position)

func _show_item_tooltip(item: Dictionary, global_pos: Vector2):
	hovered_item_data = item
	if not tooltip:
		return

	var iname = item.get("name", "")
	var stats = item.get("stats", "")
	var quality = item.get("quality", 0)
	var can_use = item.get("can_use", true)

	if iname.strip_edges() == "":
		tooltip.visible = false
		return

	if stats.strip_edges() == "":
		var t = item.get("type", 0)
		match t:
			1: stats = "Restores partial Life\n[Right Click] Drink"
			2: stats = "Restores all Life\n[Right Click] Drink"
			3: stats = "Restores partial Mana\n[Right Click] Drink"
			4: stats = "Restores all Mana\n[Right Click] Drink"
			5: stats = "Restores partial Life & Mana\n[Right Click] Drink"
			6, 7: stats = "Restores all Life & Mana\n[Right Click] Drink"
			8: stats = "Single use spell scroll\n[Right Click] Cast"
			9: stats = "Oil\n[Right Click] Apply"
			10: stats = "Rune\n[Right Click] Cast"
			_:
				if "Potion of Healing" in iname: stats = "Restores Life\n[Right Click] Drink"
				elif "Potion of Mana" in iname: stats = "Restores Mana\n[Right Click] Drink"
				elif "Rejuvenation" in iname: stats = "Restores Life & Mana\n[Right Click] Drink"
				elif "Scroll of" in iname: stats = "Spell scroll\n[Right Click] Cast"

	tooltip_title.text = iname
	var title_col = COLOR_NORMAL
	if quality == 1: title_col = COLOR_MAGIC
	elif quality == 2: title_col = COLOR_UNIQUE
	if not can_use:
		title_col = COLOR_UNUSABLE
	tooltip_title.add_theme_color_override("font_color", title_col)

	var has_stats = (stats.strip_edges() != "")
	tooltip_stats.text = stats
	tooltip_stats.visible = has_stats
	if tooltip_divider:
		tooltip_divider.visible = has_stats
		tooltip_divider.color = Color(title_col.r, title_col.g, title_col.b, 0.6)

	tooltip.visible = true
	tooltip.reset_size()

	# Position tooltip to the left of the inventory panel
	var tt_w = tooltip.size.x
	var tt_h = tooltip.size.y
	var panel_global_x = global_position.x
	var target_x = panel_global_x - tt_w - 12.0
	var target_y = clampf(global_pos.y - tt_h * 0.3, 20.0, get_viewport_rect().size.y - tt_h - 20.0)
	if target_x < 10.0:
		target_x = 10.0
	tooltip.global_position = Vector2(target_x, target_y)

func _on_item_mouse_exited():
	hovered_item_data = null
	if tooltip:
		tooltip.visible = false

func _format_number(n: int) -> String:
	if n <= 0: return "0"
	var s = str(n)
	var res = ""
	var cnt = 0
	for i in range(s.length() - 1, -1, -1):
		res = s[i] + res
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			res = "," + res
	return res
