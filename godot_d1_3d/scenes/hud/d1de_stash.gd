extends Control

var diablo_bridge = null

# Quality border & text colors (matching Diablo IV Modern HUD)
const COLOR_NORMAL = Color(0.75, 0.70, 0.60, 1.0)
const COLOR_MAGIC = Color(0.35, 0.60, 1.0, 1.0)
const COLOR_UNIQUE = Color(1.0, 0.82, 0.25, 1.0)
const COLOR_UNUSABLE = Color(1.0, 0.35, 0.35, 1.0)

# Cell dimensions for 10x10 stash grid (24px cell + 1px gap = 25px step)
const CELL_SIZE = 24.0
const CELL_GAP = 1.0
const CELL_STEP = CELL_SIZE + CELL_GAP # 25.0

# Node references
@onready var page_label: Label = find_child("PageLabel", true, false)
@onready var prev_10_btn: Button = find_child("Prev10Btn", true, false)
@onready var prev_btn: Button = find_child("PrevBtn", true, false)
@onready var next_btn: Button = find_child("NextBtn", true, false)
@onready var next_10_btn: Button = find_child("Next10Btn", true, false)
@onready var gold_label: Label = find_child("GoldLabel", true, false)
@onready var withdraw_gold_btn: Button = find_child("WithdrawGoldBtn", true, false)
@onready var close_btn: Button = find_child("CloseBtn", true, false)
@onready var grid_cells: GridContainer = find_child("GridCells", true, false)
@onready var items_overlay: Control = find_child("ItemsOverlay", true, false)

# Dedicated Item Tooltip
@onready var tooltip: PanelContainer = get_node_or_null("Tooltip")
@onready var tooltip_title: Label = get_node_or_null("Tooltip/Margin/VBox/TitleLabel")
@onready var tooltip_divider: ColorRect = get_node_or_null("Tooltip/Margin/VBox/Divider")
@onready var tooltip_stats: Label = get_node_or_null("Tooltip/Margin/VBox/StatsLabel")

var hovered_item_data = null
var last_inventory_version: int = -1
var last_stash_page: int = -1
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
	if close_btn:
		close_btn.pressed.connect(func():
			if diablo_bridge and diablo_bridge.has_method("close_stash"):
				diablo_bridge.close_stash()
			visible = false
		)

	if prev_10_btn:
		prev_10_btn.pressed.connect(func():
			if diablo_bridge and diablo_bridge.has_method("stash_change_page"):
				diablo_bridge.stash_change_page(-10)
				update_stash()
		)
	if prev_btn:
		prev_btn.pressed.connect(func():
			if diablo_bridge and diablo_bridge.has_method("stash_change_page"):
				diablo_bridge.stash_change_page(-1)
				update_stash()
		)
	if next_btn:
		next_btn.pressed.connect(func():
			if diablo_bridge and diablo_bridge.has_method("stash_change_page"):
				diablo_bridge.stash_change_page(1)
				update_stash()
		)
	if next_10_btn:
		next_10_btn.pressed.connect(func():
			if diablo_bridge and diablo_bridge.has_method("stash_change_page"):
				diablo_bridge.stash_change_page(10)
				update_stash()
		)

	if withdraw_gold_btn:
		withdraw_gold_btn.pressed.connect(func():
			if diablo_bridge and diablo_bridge.has_method("get_stash_info") and diablo_bridge.has_method("stash_withdraw_gold"):
				var info: Dictionary = diablo_bridge.get_stash_info()
				var g = int(info.get("gold", 0))
				if g > 0:
					diablo_bridge.stash_withdraw_gold(g)
					update_stash()
		)

	var nav_font = SystemFont.new()
	nav_font.font_names = PackedStringArray(["Trebuchet MS", "DejaVu Sans", "Liberation Sans", "sans-serif"])
	nav_font.font_weight = 700
	for btn in [prev_10_btn, prev_btn, next_btn, next_10_btn]:
		if btn:
			btn.add_theme_font_override("font", nav_font)
			btn.add_theme_font_size_override("font_size", 12)

	_init_stash_cells()
	if tooltip:
		tooltip.visible = false

func set_bridge(bridge):
	diablo_bridge = bridge
	update_stash()

func _init_stash_cells():
	if not grid_cells:
		return
	for child in grid_cells.get_children():
		child.queue_free()

	for i in range(100):
		var cell = Panel.new()
		cell.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		var cell_style = StyleBoxFlat.new()
		cell_style.bg_color = Color(0.08, 0.07, 0.09, 0.85)
		cell_style.border_color = Color(0.25, 0.20, 0.16, 0.6)
		cell_style.border_width_left = 1
		cell_style.border_width_top = 1
		cell_style.border_width_right = 1
		cell_style.border_width_bottom = 1
		cell_style.corner_radius_top_left = 1
		cell_style.corner_radius_top_right = 1
		cell_style.corner_radius_bottom_right = 1
		cell_style.corner_radius_bottom_left = 1
		cell.add_theme_stylebox_override("panel", cell_style)

		var cell_idx = i
		cell.gui_input.connect(func(event: InputEvent):
			_on_stash_cell_gui_input(cell_idx, event)
		)
		grid_cells.add_child(cell)

func _process(_delta: float) -> void:
	if visible or is_visible_in_tree():
		check_and_update()

func check_and_update():
	if not diablo_bridge:
		return
	var ver = 0
	if diablo_bridge.has_method("get_inventory_version"):
		ver = diablo_bridge.get_inventory_version()

	var cur_page = -1
	if diablo_bridge.has_method("get_stash_info"):
		var info = diablo_bridge.get_stash_info()
		cur_page = int(info.get("page", 1))

	if ver != last_inventory_version or cur_page != last_stash_page:
		update_stash()

func update_stash():
	if not diablo_bridge:
		return
	if diablo_bridge.has_method("get_inventory_version"):
		last_inventory_version = diablo_bridge.get_inventory_version()

	# 1. Update Page & Gold Info
	if diablo_bridge.has_method("get_stash_info"):
		var info: Dictionary = diablo_bridge.get_stash_info()
		var p = int(info.get("page", 1))
		var total = int(info.get("total_pages", 100))
		var gold = int(info.get("gold", 0))
		last_stash_page = p

		if page_label:
			page_label.text = "Page %d / %d" % [p, total]
		if gold_label:
			gold_label.text = "Stash Gold: %s" % _format_number(gold)
		if withdraw_gold_btn:
			withdraw_gold_btn.disabled = (gold <= 0)

	# 2. Update Stash Items
	_update_stash_items()

func _update_stash_items():
	if not diablo_bridge or not diablo_bridge.has_method("get_stash_items"):
		return
	if not items_overlay:
		return

	# Clear previous overlay item controls
	for c in items_overlay.get_children():
		c.queue_free()

	var stash_items = diablo_bridge.get_stash_items()
	for it in stash_items:
		var cell_x = it.get("cell_x", 0)
		var cell_y = it.get("cell_y", 0)
		var cell_w = it.get("cell_w", 1)
		var cell_h = it.get("cell_h", 1)
		var curs_id = it.get("curs_id", 0)
		var quality = it.get("quality", 0)
		var can_use = it.get("can_use", true)
		var cell_idx = it.get("slot_id", cell_y * 10 + cell_x)

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
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.10, 0.14, 0.88)
		var bcol = COLOR_NORMAL
		if quality == 1: bcol = COLOR_MAGIC
		elif quality == 2: bcol = COLOR_UNIQUE
		if not can_use:
			bcol = COLOR_UNUSABLE
			sb.bg_color = Color(0.25, 0.06, 0.06, 0.90)

		sb.border_color = bcol
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.corner_radius_top_left = 2
		sb.corner_radius_top_right = 2
		sb.corner_radius_bottom_right = 2
		sb.corner_radius_bottom_left = 2
		panel.add_theme_stylebox_override("panel", sb)
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
			_on_stash_item_gui_input(cell_idx, event)
		)
		item_ctrl.mouse_entered.connect(func():
			_show_item_tooltip(it, item_ctrl.global_position)
		)
		item_ctrl.mouse_exited.connect(func():
			_on_item_mouse_exited()
		)

		items_overlay.add_child(item_ctrl)

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if diablo_bridge and diablo_bridge.has_method("get_cursor_id"):
			var cid = diablo_bridge.get_cursor_id()
			if cid > 1 and cid < 12:
				if diablo_bridge.has_method("cancel_targeting_cursor"):
					diablo_bridge.cancel_targeting_cursor()
				update_stash()
				_on_item_mouse_exited()
				accept_event()

func _on_stash_cell_gui_input(cell_idx: int, event: InputEvent):
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var mb = event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if diablo_bridge and diablo_bridge.has_method("click_stash_slot"):
			diablo_bridge.click_stash_slot(cell_idx, mb.shift_pressed, mb.ctrl_pressed)
			update_stash()
			_on_item_mouse_exited()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		if diablo_bridge and diablo_bridge.has_method("get_cursor_id"):
			var cid = diablo_bridge.get_cursor_id()
			if cid > 1 and cid < 12:
				if diablo_bridge.has_method("cancel_targeting_cursor"):
					diablo_bridge.cancel_targeting_cursor()
				update_stash()
				_on_item_mouse_exited()
				return

func _on_stash_item_gui_input(cell_idx: int, event: InputEvent):
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var mb = event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if diablo_bridge and diablo_bridge.has_method("click_stash_slot"):
			diablo_bridge.click_stash_slot(cell_idx, mb.shift_pressed, mb.ctrl_pressed)
			update_stash()
			_on_item_mouse_exited()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		if diablo_bridge and diablo_bridge.has_method("get_cursor_id"):
			var cid = diablo_bridge.get_cursor_id()
			if cid > 1 and cid < 12:
				if diablo_bridge.has_method("cancel_targeting_cursor"):
					diablo_bridge.cancel_targeting_cursor()
				update_stash()
				_on_item_mouse_exited()
				return
		# Quick transfer item to player backpack on right-click (matching D1DE / ARPG standard)
		if diablo_bridge and diablo_bridge.has_method("click_stash_slot"):
			diablo_bridge.click_stash_slot(cell_idx, false, true)
			update_stash()
			_on_item_mouse_exited()

func _show_item_tooltip(item_data: Dictionary, global_item_pos: Vector2):
	if not tooltip or not item_data:
		return
	hovered_item_data = item_data

	var iname = item_data.get("name", "")
	var stats = item_data.get("stats", "")
	var quality = item_data.get("quality", 0)
	var can_use = item_data.get("can_use", true)

	if iname.strip_edges() == "":
		tooltip.visible = false
		return

	# Fallback descriptions if stats is empty (potions, scrolls, oils, runes)
	if stats.strip_edges() == "":
		var t = item_data.get("type", 0)
		match t:
			1: stats = "Restores partial Life"
			2: stats = "Restores all Life"
			3: stats = "Restores partial Mana"
			4: stats = "Restores all Mana"
			5: stats = "Restores partial Life & Mana"
			6, 7: stats = "Restores all Life & Mana"
			8: stats = "Single use spell scroll"
			9: stats = "Oil"
			10: stats = "Rune"
			_:
				if "Potion of Healing" in iname: stats = "Restores Life"
				elif "Potion of Mana" in iname: stats = "Restores Mana"
				elif "Rejuvenation" in iname: stats = "Restores Life & Mana"
				elif "Scroll of" in iname: stats = "Spell scroll"

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

	# Position tooltip cleanly to the RIGHT of the stash panel
	var vp_size = get_viewport_rect().size
	var tt_w = tooltip.size.x if tooltip.size.x > 0 else 220.0
	var tt_h = tooltip.size.y if tooltip.size.y > 0 else 80.0

	var panel_right = global_position.x + size.x + 12.0
	var pos_x = panel_right
	if pos_x + tt_w > vp_size.x - 10.0:
		# If screen is narrow, place to the left of the item
		pos_x = global_item_pos.x - tt_w - 10.0
		if pos_x < 10.0:
			pos_x = 10.0

	var pos_y = clampf(global_item_pos.y - tt_h * 0.3, 20.0, vp_size.y - tt_h - 20.0)

	tooltip.global_position = Vector2(pos_x, pos_y)

func _on_item_mouse_exited():
	hovered_item_data = null
	if tooltip:
		tooltip.visible = false

func _format_number(n: int) -> String:
	var s := str(n)
	var res := ""
	var cnt := 0
	for i in range(s.length() - 1, -1, -1):
		res = s[i] + res
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			res = "," + res
	return res
