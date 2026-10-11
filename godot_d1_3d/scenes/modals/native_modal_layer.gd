extends Control
## Native Godot modal overlay for D1 menus (pause/gamemenu, NPC dialog/store,
## death-restart, quest narrative speech).
##
## Interactive Control nodes:
## - Non-selectable rows (e.g. "The Town Elder", "Would you like to:") are rendered as Labels.
## - Selectable rows (e.g. "Talk to Cain", "Identify an item", "Say goodbye") are rendered as
##   interactive Buttons connected to diablo_bridge.activate_modal_item(idx).
## - When quest speech / narrative text (qtextflag) is active, renders the narrative text with a Continue button.

var diablo_bridge = null
var current_type := -1
var row_controls: Array = []
var last_item_count := -1
var last_sel := -2
var last_qtext_active := false
var last_qtext_line_count := -1
var last_is_dead := false

const FONT_EXOCET = preload("res://assets/fonts/Exocet.ttf")
const UpscalerModelConfig = preload("res://scripts/upscaler_model_config.gd")

func _apply_font_recursive(node: Node):
	if node is Label or node is Button or node is LineEdit:
		node.add_theme_font_override("font", FONT_EXOCET)
	for child in node.get_children():
		_apply_font_recursive(child)

var _panel: PanelContainer
var _default_panel_style: StyleBoxFlat
var _death_panel_style: StyleBoxEmpty
var _title_label: Label
var _default_title_style: StyleBoxFlat
var _death_title_style: StyleBoxEmpty
var _gold_label: Label
var _rows_container: VBoxContainer
var _qtext_container: VBoxContainer
var _qtext_label: Label
var _qtext_button: Button

# --- Native Options panel (Music / Sound / Gamma / Speed sliders) ---
const OPT_VOLUME_MIN := -1600   # D1 volume units: -1600 = mute, 0 = max
const OPT_VOLUME_MAX := 0
const OPT_GAMMA_MIN := 30       # vanilla gamma slider range (percent)
const OPT_GAMMA_MAX := 100
const OPT_SPEED_MIN := 20       # ticks per second
const OPT_SPEED_MAX := 50
const OPT_BRIGHTNESS_MIN := 50   # Godot-native global brightness (percent), via GameView post-process
const OPT_BRIGHTNESS_MAX := 150

var _options_panel: Control     # full-rect input blocker hosting the options UI
var _opt_music_slider: HSlider
var _opt_sound_slider: HSlider
var _opt_gamma_slider: HSlider
var _opt_brightness_slider: HSlider
var _opt_speed_slider: HSlider
var _opt_hd_button: Button = null
# --- Definitive Edition (D1DE) effect toggles + graphics rows (menu-driven; no hotkeys) ---
var _opt_torchlight_button: Button = null
var _opt_fog_button: Button = null
var _opt_color_button: Button = null
var _opt_hdr_button: Button = null
var _opt_upscaler_button: Button = null
var _opt_relief_button: Button = null
var _opt_tile_model_button: Button = null  # Neural upscale model selector (6 offline AI models)
var _opt_wet_floor_button: Button = null
var _opt_effects_button: Button = null
var _opt_display_mode_button: Button = null
var _opt_vsync_button: Button = null
var _opt_show_fps_button: Button = null
var brightness_host = null   # bridge_receiver (owns GameView + global brightness)
var _opt_music_value: Label
var _opt_sound_value: Label
var _opt_gamma_value: Label
var _opt_brightness_value: Label
var _opt_speed_value: Label
var _options_open := false
var _options_closing := false   # waiting for D1 to leave its own options screen (flow B)
var _closing_frames := 0
var _options_refreshing := false

func set_bridge(b) -> void:
	diablo_bridge = b

# Host that owns the Godot-native global Brightness (bridge_receiver / GameView).
func set_brightness_host(host) -> void:
	brightness_host = host

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = PanelContainer.new()
	_panel.name = "ModalPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	margin.mouse_filter = Control.MOUSE_FILTER_PASS

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("v_separation", 14)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS

	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.custom_minimum_size = Vector2(400, 36)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(_title_label)

	_gold_label = Label.new()
	_gold_label.name = "GoldLabel"
	_gold_label.custom_minimum_size = Vector2(400, 24)
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gold_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25, 1.0))
	_gold_label.add_theme_font_size_override("font_size", 15)
	_gold_label.visible = false
	vbox.add_child(_gold_label)

	# Container for standard menu / store items
	_rows_container = VBoxContainer.new()
	_rows_container.name = "Rows"
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_container.add_theme_constant_override("v_separation", 8)
	_rows_container.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(_rows_container)

	# Container for speech narrative text (qtextflag)
	_qtext_container = VBoxContainer.new()
	_qtext_container.name = "QTextContainer"
	_qtext_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_qtext_container.add_theme_constant_override("v_separation", 14)
	_qtext_container.visible = false
	_qtext_container.mouse_filter = Control.MOUSE_FILTER_PASS

	_qtext_label = Label.new()
	_qtext_label.name = "QTextLabel"
	_qtext_label.custom_minimum_size = Vector2(480, 160)
	_qtext_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_qtext_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qtext_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_qtext_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55, 1.0))
	_qtext_label.add_theme_font_size_override("font_size", 16)
	_qtext_container.add_child(_qtext_label)

	_qtext_button = Button.new()
	_qtext_button.name = "QTextButton"
	_qtext_button.text = "Continue [Space / Esc]"
	_qtext_button.custom_minimum_size = Vector2(240, 38)
	_qtext_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_qtext_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_qtext_button.add_theme_stylebox_override("normal", _button_normal_box())
	_qtext_button.add_theme_stylebox_override("hover", _button_hover_box())
	_qtext_button.add_theme_stylebox_override("pressed", _button_selected_box())
	_qtext_button.add_theme_stylebox_override("focus", _button_hover_box())
	_qtext_button.add_theme_color_override("font_color", Color(0.95, 0.88, 0.72, 1.0))
	_qtext_button.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.50, 1.0))
	_qtext_button.pressed.connect(_on_qtext_dismiss_pressed)
	_qtext_container.add_child(_qtext_button)

	vbox.add_child(_qtext_container)

	margin.add_child(vbox)
	_panel.add_child(margin)
	add_child(_panel)

	# Gothic panel styling
	_default_panel_style = StyleBoxFlat.new()
	_default_panel_style.bg_color = Color(0.05, 0.05, 0.08, 0.96)
	_default_panel_style.border_color = Color(0.65, 0.50, 0.22, 1.0)
	_default_panel_style.border_width_left = 2
	_default_panel_style.border_width_top = 2
	_default_panel_style.border_width_right = 2
	_default_panel_style.border_width_bottom = 2
	_default_panel_style.corner_radius_top_left = 6
	_default_panel_style.corner_radius_top_right = 6
	_default_panel_style.corner_radius_bottom_right = 6
	_default_panel_style.corner_radius_bottom_left = 6
	_default_panel_style.shadow_color = Color(0, 0, 0, 0.85)
	_default_panel_style.shadow_size = 16

	_death_panel_style = StyleBoxEmpty.new()
	_panel.add_theme_stylebox_override("panel", _default_panel_style)

	_default_title_style = StyleBoxFlat.new()
	_default_title_style.bg_color = Color(0.18, 0.13, 0.06, 0.95)
	_default_title_style.border_color = Color(0.85, 0.68, 0.25, 0.8)
	_default_title_style.border_width_bottom = 1
	_default_title_style.content_margin_top = 6
	_default_title_style.content_margin_bottom = 6

	_death_title_style = StyleBoxEmpty.new()

	_title_label.add_theme_stylebox_override("normal", _default_title_style)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45, 1.0))
	_title_label.add_theme_font_size_override("font_size", 24)

	# --- Native Options panel (Music/Sound/Gamma/Speed), hidden until opened ---
	_options_panel = Control.new()
	_options_panel.name = "OptionsPanel"
	_options_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_options_panel.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow all mouse input over the screen
	_options_panel.visible = false

	var opt_box := PanelContainer.new()
	opt_box.name = "OptBox"
	opt_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	opt_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	opt_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	opt_box.mouse_filter = Control.MOUSE_FILTER_STOP

	var opt_margin := MarginContainer.new()
	opt_margin.add_theme_constant_override("margin_left", 28)
	opt_margin.add_theme_constant_override("margin_right", 28)
	opt_margin.add_theme_constant_override("margin_top", 22)
	opt_margin.add_theme_constant_override("margin_bottom", 22)
	opt_margin.mouse_filter = Control.MOUSE_FILTER_PASS

	var opt_vbox := VBoxContainer.new()
	opt_vbox.name = "OptVBox"
	opt_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt_vbox.add_theme_constant_override("v_separation", 14)
	opt_vbox.mouse_filter = Control.MOUSE_FILTER_PASS

	var opt_title := Label.new()
	opt_title.name = "OptionsTitle"
	opt_title.text = "Options"
	opt_title.custom_minimum_size = Vector2(400, 36)
	opt_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opt_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	opt_title.mouse_filter = Control.MOUSE_FILTER_PASS
	opt_title.add_theme_stylebox_override("normal", _default_title_style)
	opt_title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45, 1.0))
	opt_title.add_theme_font_size_override("font_size", 24)
	opt_vbox.add_child(opt_title)

	var opt_hint := Label.new()
	opt_hint.name = "OptionsHint"
	opt_hint.text = "Changes apply immediately - Close with Esc"
	opt_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opt_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opt_hint.add_theme_color_override("font_color", Color(0.75, 0.70, 0.60, 0.9))
	opt_hint.add_theme_font_size_override("font_size", 13)
	opt_vbox.add_child(opt_hint)

	var music_row := _add_option_row(opt_vbox, "Music", 0, 100)
	_opt_music_slider = music_row.get_node("Slider")
	_opt_music_value = music_row.get_node("ValueLabel")
	_opt_music_slider.value_changed.connect(_on_opt_music_changed)

	var sound_row := _add_option_row(opt_vbox, "Sound", 0, 100)
	_opt_sound_slider = sound_row.get_node("Slider")
	_opt_sound_value = sound_row.get_node("ValueLabel")
	_opt_sound_slider.value_changed.connect(_on_opt_sound_changed)

	var gamma_row := _add_option_row(opt_vbox, "Gamma", OPT_GAMMA_MIN, OPT_GAMMA_MAX)
	_opt_gamma_slider = gamma_row.get_node("Slider")
	_opt_gamma_value = gamma_row.get_node("ValueLabel")
	_opt_gamma_slider.value_changed.connect(_on_opt_gamma_changed)

	# Godot-native global Brightness (SubViewport post-process) - independent of C++/palette gamma.
	var brightness_row := _add_option_row(opt_vbox, "Brightness", OPT_BRIGHTNESS_MIN, OPT_BRIGHTNESS_MAX)
	_opt_brightness_slider = brightness_row.get_node("Slider")
	_opt_brightness_value = brightness_row.get_node("ValueLabel")
	_opt_brightness_slider.value_changed.connect(_on_opt_brightness_changed)

	var speed_row := _add_option_row(opt_vbox, "Speed", OPT_SPEED_MIN, OPT_SPEED_MAX)
	_opt_speed_slider = speed_row.get_node("Slider")
	_opt_speed_value = speed_row.get_node("ValueLabel")
	_opt_speed_slider.value_changed.connect(_on_opt_speed_changed)

	var hd_row := _add_option_button_row(opt_vbox, "Visuals", "Definitive Edition 4x HD")
	_opt_hd_button = hd_row.get_node("Button")
	_opt_hd_button.pressed.connect(_on_opt_hd_toggled)

	var torchlight_row := _add_option_button_row(opt_vbox, "Soft Torchlight", "Off")
	_opt_torchlight_button = torchlight_row.get_node("Button")
	_opt_torchlight_button.pressed.connect(_on_opt_torchlight_toggled)

	var fog_row := _add_option_button_row(opt_vbox, "Atmospheric Fog", "Cycle")
	_opt_fog_button = fog_row.get_node("Button")
	_opt_fog_button.pressed.connect(_on_opt_fog_cycled)

	var color_row := _add_option_button_row(opt_vbox, "Color Profile", "Cycle")
	_opt_color_button = color_row.get_node("Button")
	_opt_color_button.pressed.connect(_on_opt_color_cycled)

	var hdr_row := _add_option_button_row(opt_vbox, "Engine HDR Glow", "Cycle")
	_opt_hdr_button = hdr_row.get_node("Button")
	_opt_hdr_button.pressed.connect(_on_opt_hdr_cycled)

	var upscaler_row := _add_option_button_row(opt_vbox, "Upscaler", "Cycle")
	_opt_upscaler_button = upscaler_row.get_node("Button")
	_opt_upscaler_button.pressed.connect(_on_opt_upscaler_cycled)

	var relief_row := _add_option_button_row(opt_vbox, "3D Surface Relief", "Cycle")
	_opt_relief_button = relief_row.get_node("Button")
	_opt_relief_button.pressed.connect(_on_opt_relief_cycled)

	var tile_model_row := _add_option_button_row(opt_vbox, "Tile Upscale Model", "Cycle")
	_opt_tile_model_button = tile_model_row.get_node("Button")
	_opt_tile_model_button.pressed.connect(_on_opt_tile_model_cycled)

	var wet_floor_row := _add_option_button_row(opt_vbox, "Wet Floor", "On")
	_opt_wet_floor_button = wet_floor_row.get_node("Button")
	_opt_wet_floor_button.pressed.connect(_on_opt_wet_floor_toggled)

	var effects_row := _add_option_button_row(opt_vbox, "Definitive Effects", "On")
	_opt_effects_button = effects_row.get_node("Button")
	_opt_effects_button.pressed.connect(_on_opt_d1de_effects_toggled)

	var display_mode_row := _add_option_button_row(opt_vbox, "Display Mode", "Cycle")
	_opt_display_mode_button = display_mode_row.get_node("Button")
	_opt_display_mode_button.pressed.connect(_on_opt_display_mode_switched)

	var vsync_row := _add_option_button_row(opt_vbox, "V-Sync", "On")
	_opt_vsync_button = vsync_row.get_node("Button")
	_opt_vsync_button.pressed.connect(_on_opt_vsync_toggled)

	var fps_row := _add_option_button_row(opt_vbox, "Show FPS", "Off")
	_opt_show_fps_button = fps_row.get_node("Button")
	_opt_show_fps_button.pressed.connect(_on_opt_show_fps_toggled)

	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "Close [Esc]"
	close_btn.custom_minimum_size = Vector2(240, 38)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_stylebox_override("normal", _button_normal_box())
	close_btn.add_theme_stylebox_override("hover", _button_hover_box())
	close_btn.add_theme_stylebox_override("pressed", _button_hover_box())
	close_btn.add_theme_color_override("font_color", Color(0.92, 0.88, 0.80, 1.0))
	close_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.50, 1.0))
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(_on_opt_close_pressed)
	opt_vbox.add_child(close_btn)

	opt_margin.add_child(opt_vbox)
	opt_box.add_child(opt_margin)
	_options_panel.add_child(opt_box)

	var opt_bg := StyleBoxFlat.new()
	opt_bg.bg_color = Color(0.05, 0.05, 0.08, 0.96)
	opt_bg.border_color = Color(0.65, 0.50, 0.22, 1.0)
	opt_bg.border_width_left = 2
	opt_bg.border_width_top = 2
	opt_bg.border_width_right = 2
	opt_bg.border_width_bottom = 2
	opt_bg.corner_radius_top_left = 6
	opt_bg.corner_radius_top_right = 6
	opt_bg.corner_radius_bottom_right = 6
	opt_bg.corner_radius_bottom_left = 6
	opt_bg.shadow_color = Color(0, 0, 0, 0.85)
	opt_bg.shadow_size = 16
	opt_box.add_theme_stylebox_override("panel", opt_bg)

	add_child(_options_panel)
	_apply_font_recursive(self)

func _on_qtext_dismiss_pressed() -> void:
	if diablo_bridge and diablo_bridge.has_method("dismiss_qtext"):
		diablo_bridge.dismiss_qtext()

func _on_item_pressed(idx: int) -> void:
	if diablo_bridge and diablo_bridge.has_method("activate_modal_item"):
		diablo_bridge.activate_modal_item(idx)

func _on_item_hovered(idx: int) -> void:
	if diablo_bridge and diablo_bridge.has_method("select_modal_item"):
		diablo_bridge.select_modal_item(idx)

# --- Native Options panel (Music/Sound/Gamma/Speed sliders) ---

func _on_options_row_pressed(idx: int) -> void:
	# Mouse flow: align D1's selection with this row, then open the native panel.
	if diablo_bridge and diablo_bridge.has_method("select_modal_item"):
		diablo_bridge.select_modal_item(idx)
	_open_options_panel()

func _on_opt_close_pressed() -> void:
	_close_options_panel()

func _open_options_panel() -> void:
	if _options_open or _options_closing:
		return
	_refresh_option_values()
	_options_open = true
	_options_closing = false
	_closing_frames = 0
	visible = true
	_panel.visible = false
	_options_panel.visible = true

func _close_options_panel() -> void:
	if not (_options_open or _options_closing):
		return
	var items: Array = diablo_bridge.get_current_menu_items() if diablo_bridge and diablo_bridge.has_method("get_current_menu_items") else []
	var prev_idx := -1
	for i in range(items.size()):
		if str(items[i].get("text", "")) == "Previous Menu":
			prev_idx = i
			break
	if prev_idx >= 0:
		# Keyboard flow: D1 is on its own options screen. Ask it to go back and
		# keep the panel visible until the menu actually switches (async engine thread).
		if diablo_bridge.has_method("activate_modal_item"):
			diablo_bridge.activate_modal_item(prev_idx)
		_options_open = false
		_options_closing = true
		_closing_frames = 0
	else:
		_finalize_options_close()

func _finalize_options_close() -> void:
	_options_open = false
	_options_closing = false
	_closing_frames = 0
	if _options_panel != null:
		_options_panel.visible = false
	if _panel != null:
		_panel.visible = true

func _reset_options_state() -> void:
	_options_open = false
	_options_closing = false
	_closing_frames = 0
	_options_refreshing = false
	if _options_panel != null:
		_options_panel.visible = false
	if _panel != null:
		_panel.visible = true

func _items_contain(items: Array, text: String) -> bool:
	for d in items:
		if str(d.get("text", "")) == text:
			return true
	return false

# --- Slider helpers (D1 volume units <-> percent display) ---

func _pct_to_vol(pct: int) -> int:
	var v := OPT_VOLUME_MIN + pct * 16
	return clampi(v, OPT_VOLUME_MIN, OPT_VOLUME_MAX)

func _vol_to_pct(vol: int) -> float:
	return clampf((vol - OPT_VOLUME_MIN) / 16.0, 0.0, 100.0)

func _volume_label(pct: int) -> String:
	return "Off" if pct <= 0 else "%d%%" % pct

func _speed_label(rate: int) -> String:
	if rate >= 50:
		return "%d - Fastest" % rate
	elif rate >= 40:
		return "%d - Faster" % rate
	elif rate >= 30:
		return "%d - Fast" % rate
	return "%d - Normal" % rate

func _refresh_option_values() -> void:
	if not diablo_bridge:
		return
	_options_refreshing = true
	var mv := OPT_VOLUME_MIN
	var sv := OPT_VOLUME_MIN
	var g := 50
	var s := OPT_SPEED_MIN
	if diablo_bridge.has_method("get_music_volume"):
		mv = int(diablo_bridge.get_music_volume())
	if diablo_bridge.has_method("get_sound_volume"):
		sv = int(diablo_bridge.get_sound_volume())
	if brightness_host and brightness_host.has_method("get_gamma_pct"):
		g = clampi(int(brightness_host.get_gamma_pct()), OPT_GAMMA_MIN, OPT_GAMMA_MAX)
	elif diablo_bridge.has_method("get_gamma"):
		g = clampi(int(diablo_bridge.get_gamma()), OPT_GAMMA_MIN, OPT_GAMMA_MAX)
	if diablo_bridge.has_method("get_speed"):
		s = clampi(int(diablo_bridge.get_speed()), OPT_SPEED_MIN, OPT_SPEED_MAX)

	var mp := int(round(_vol_to_pct(mv)))
	var sp := int(round(_vol_to_pct(sv)))
	_opt_music_slider.value = float(mp)
	_opt_music_value.text = _volume_label(mp)
	_opt_sound_slider.value = float(sp)
	_opt_sound_value.text = _volume_label(sp)
	_opt_gamma_slider.value = float(g)
	_opt_gamma_value.text = "%d%%" % g
	_opt_speed_slider.value = float(s)
	_opt_speed_value.text = _speed_label(s)
	var b := 100
	if brightness_host and brightness_host.has_method("get_brightness"):
		b = clampi(int(brightness_host.get_brightness()), OPT_BRIGHTNESS_MIN, OPT_BRIGHTNESS_MAX)
	_opt_brightness_slider.value = float(b)
	_opt_brightness_value.text = "%d%%" % b
	if _opt_hd_button:
		var is_hd := true
		if brightness_host and brightness_host.has_method("get_hd_graphics_enabled"):
			is_hd = brightness_host.get_hd_graphics_enabled()
		_opt_hd_button.text = "Definitive Edition 4x HD" if is_hd else "Authentic 1996"
	_set_row_text(_opt_torchlight_button, "Definitive Edition", "Soft Torchlight")
	_set_row_text(_opt_fog_button, "Definitive Edition", "Atmospheric Fog")
	_set_row_text(_opt_color_button, "Definitive Edition", "Color Profile")
	_set_row_text(_opt_hdr_button, "Definitive Edition", "Engine HDR Glow")
	_set_row_text(_opt_upscaler_button, "Definitive Edition", "Upscaler")
	_set_row_text(_opt_relief_button, "Definitive Edition", "3D Surface Relief")
	_set_row_text(_opt_tile_model_button, "Definitive Edition", "AI Tile Upscale Model")
	if _opt_tile_model_button and _opt_tile_model_button.text == "":
		var tm: int = 0
		if brightness_host and brightness_host.has_method("get_tile_model_index"):
			tm = int(brightness_host.get_tile_model_index())
		_opt_tile_model_button.text = UpscalerModelConfig.get_model_display_name(tm)
	_set_row_text(_opt_wet_floor_button, "Definitive Edition", "Wet Floor")
	_set_row_text(_opt_effects_button, "Definitive Edition", "Definitive Effects")
	_set_row_text(_opt_display_mode_button, "Definitive Edition", "Display Mode")
	_set_row_text(_opt_vsync_button, "Graphics", "V-Sync")
	_set_row_text(_opt_show_fps_button, "Graphics", "Show FPS")
	_options_refreshing = false

func _on_opt_hd_toggled() -> void:
	if _options_refreshing:
		return
	if brightness_host and brightness_host.has_method("toggle_hd_graphics"):
		var is_hd: bool = brightness_host.toggle_hd_graphics()
		if _opt_hd_button:
			_opt_hd_button.text = "Definitive Edition 4x HD" if is_hd else "Authentic 1996"

# --- Definitive Edition (D1DE) effect toggles + graphics rows (menu-driven; no hotkeys) ---

func _get_bridge_entry(cat_name: String, entry_name: String) -> Variant:
	if diablo_bridge == null or not diablo_bridge.has_method("get_settings_categories"):
		return null
	var cat_id := -1
	for cat in diablo_bridge.get_settings_categories():
		var c_name = str(cat.get("name", ""))
		if c_name == cat_name or (cat_name == "Definitive Edition" and c_name == "Resurrected"):
			cat_id = int(cat.get("id", 0))
			break
	if cat_id < 0 or not diablo_bridge.has_method("get_settings_entries"):
		return null
	for entry in diablo_bridge.get_settings_entries(cat_id):
		var e_name = str(entry.get("name", ""))
		if e_name == entry_name or (entry_name == "Definitive Effects" and e_name == "Resurrected Effects"):
			var info = {
				"cat_id": cat_id,
				"id": int(entry.get("id", 0)),
				"type": int(entry.get("type", -1)),
				"bool_val": bool(entry.get("bool_val", false)),
				"list_index": int(entry.get("list_index", 0)),
				"list_options": entry.get("list_options", []),
			}
			return info
	return null

func _set_row_text(btn: Button, cat_name: String, entry_name: String) -> void:
	var info = _get_bridge_entry(cat_name, entry_name)
	if btn == null or info == null:
		return
	if int(info["type"]) == 0:
		btn.text = "On" if bool(info["bool_val"]) else "Off"
	elif int(info["type"]) == 1:
		var opts = info["list_options"]
		var idx := int(info["list_index"])
		if idx >= 0 and idx < opts.size():
			btn.text = str(opts[idx])

func _toggle_d1de_bool(btn: Button, cat_name: String, entry_name: String) -> void:
	if _options_refreshing or diablo_bridge == null:
		return
	var info = _get_bridge_entry(cat_name, entry_name)
	if info == null:
		return
	var next_v := not bool(info["bool_val"])
	if diablo_bridge.has_method("set_setting_bool"):
		diablo_bridge.set_setting_bool(int(info["cat_id"]), int(info["id"]), bool(next_v))
	if diablo_bridge.has_method("save_settings"):
		diablo_bridge.save_settings()
	_set_row_text(btn, cat_name, entry_name)

func _toggle_resurrected_bool(btn: Button, cat_name: String, entry_name: String) -> void:
	_toggle_d1de_bool(btn, cat_name, entry_name)

func _cycle_d1de_list(btn: Button, cat_name: String, entry_name: String) -> void:
	if _options_refreshing or diablo_bridge == null:
		return
	var info = _get_bridge_entry(cat_name, entry_name)
	if info == null:
		return
	var opts = info["list_options"]
	var sz := int(opts.size())
	if int(info["type"]) != 1 or sz <= 0:
		return
	var next_idx := (int(info["list_index"]) + 1) % sz
	if diablo_bridge.has_method("set_setting_list"):
		diablo_bridge.set_setting_list(int(info["cat_id"]), int(info["id"]), int(next_idx))
	if diablo_bridge.has_method("save_settings"):
		diablo_bridge.save_settings()
	_set_row_text(btn, cat_name, entry_name)

func _cycle_resurrected_list(btn: Button, cat_name: String, entry_name: String) -> void:
	_cycle_d1de_list(btn, cat_name, entry_name)

func _on_opt_torchlight_toggled() -> void:
	_toggle_d1de_bool(_opt_torchlight_button, "Definitive Edition", "Soft Torchlight")

func _on_opt_fog_cycled() -> void:
	_cycle_d1de_list(_opt_fog_button, "Definitive Edition", "Atmospheric Fog")

func _on_opt_color_cycled() -> void:
	_cycle_d1de_list(_opt_color_button, "Definitive Edition", "Color Profile")

func _on_opt_hdr_cycled() -> void:
	_cycle_d1de_list(_opt_hdr_button, "Definitive Edition", "Engine HDR Glow")

func _on_opt_upscaler_cycled() -> void:
	_cycle_d1de_list(_opt_upscaler_button, "Definitive Edition", "Upscaler")

func _on_opt_relief_cycled() -> void:
	_cycle_d1de_list(_opt_relief_button, "Definitive Edition", "3D Surface Relief")

func _on_opt_tile_model_cycled() -> void:
	if _options_refreshing:
		return
	if diablo_bridge != null and diablo_bridge.has_method("set_setting_list"):
		_cycle_d1de_list(_opt_tile_model_button, "Definitive Edition", "AI Tile Upscale Model")
		var info = _get_bridge_entry("Definitive Edition", "AI Tile Upscale Model")
		if info:
			var new_id = int(info.get("list_index", 0))
			if brightness_host and brightness_host.has_method("set_tile_model"):
				brightness_host.set_tile_model(new_id)
			return
	# Standalone fallback
	var current: int = 0
	if brightness_host and brightness_host.has_method("get_tile_model_index"):
		current = int(brightness_host.get_tile_model_index())
	var next_id = (current + 1) % UpscalerModelConfig.get_model_count()
	if brightness_host and brightness_host.has_method("set_tile_model"):
		brightness_host.set_tile_model(next_id)
	if _opt_tile_model_button:
		_opt_tile_model_button.text = UpscalerModelConfig.get_model_display_name(next_id)

func _on_opt_wet_floor_toggled() -> void:
	_toggle_d1de_bool(_opt_wet_floor_button, "Definitive Edition", "Wet Floor")

func _on_opt_d1de_effects_toggled() -> void:
	_toggle_d1de_bool(_opt_effects_button, "Definitive Edition", "Definitive Effects")

func _on_opt_resurrected_effects_toggled() -> void:
	_on_opt_d1de_effects_toggled()

func _on_opt_display_mode_switched() -> void:
	_cycle_d1de_list(_opt_display_mode_button, "Definitive Edition", "Display Mode")

func _on_opt_vsync_toggled() -> void:
	_toggle_d1de_bool(_opt_vsync_button, "Graphics", "V-Sync")

func _on_opt_show_fps_toggled() -> void:
	_toggle_d1de_bool(_opt_show_fps_button, "Graphics", "Show FPS")

func _on_opt_music_changed(v: float) -> void:
	if _options_refreshing:
		return
	var pct := int(round(v))
	_opt_music_value.text = _volume_label(pct)
	if diablo_bridge and diablo_bridge.has_method("set_music_volume"):
		diablo_bridge.set_music_volume(_pct_to_vol(pct))

func _on_opt_sound_changed(v: float) -> void:
	if _options_refreshing:
		return
	var pct := int(round(v))
	_opt_sound_value.text = _volume_label(pct)
	if diablo_bridge and diablo_bridge.has_method("set_sound_volume"):
		diablo_bridge.set_sound_volume(_pct_to_vol(pct))

func _on_opt_gamma_changed(v: float) -> void:
	if _options_refreshing:
		return
	var g := int(round(v))
	_opt_gamma_value.text = "%d%%" % g
	if brightness_host and brightness_host.has_method("set_gamma_pct"):
		brightness_host.set_gamma_pct(g)
	if diablo_bridge and diablo_bridge.has_method("set_gamma"):
		diablo_bridge.set_gamma(g)

func _on_opt_brightness_changed(v: float) -> void:
	if _options_refreshing:
		return
	var pct := int(round(v))
	_opt_brightness_value.text = "%d%%" % pct
	if brightness_host and brightness_host.has_method("set_brightness"):
		brightness_host.set_brightness(pct)

func _on_opt_speed_changed(v: float) -> void:
	if _options_refreshing:
		return
	var s := int(round(v))
	_opt_speed_value.text = _speed_label(s)
	if diablo_bridge and diablo_bridge.has_method("set_speed"):
		diablo_bridge.set_speed(s)

func _add_option_button_row(parent: Control, text: String, default_btn_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "OptionButtonRow"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("h_separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	var lbl := Label.new()
	lbl.name = "Label"
	lbl.text = text
	lbl.custom_minimum_size = Vector2(130, 0)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)

	var btn := Button.new()
	btn.name = "Button"
	btn.text = default_btn_text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 32)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_stylebox_override("normal", _button_normal_box())
	btn.add_theme_stylebox_override("hover", _button_hover_box())
	btn.add_theme_stylebox_override("pressed", _button_hover_box())
	btn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 0.70, 1.0))
	btn.add_theme_font_size_override("font_size", 14)
	row.add_child(btn)

	parent.add_child(row)
	return row

func _add_option_row(parent: Control, text: String, min_v: float, max_v: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "OptionRow"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("h_separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	var lbl := Label.new()
	lbl.name = "Label"
	lbl.text = text
	lbl.custom_minimum_size = Vector2(130, 0)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.name = "Slider"
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_NONE
	row.add_child(slider)

	var val := Label.new()
	val.name = "ValueLabel"
	val.custom_minimum_size = Vector2(110, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	val.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55, 1.0))
	row.add_child(val)

	parent.add_child(row)
	return row

func _build_rows(_mtype_arg: int, items: Array, sel: int) -> void:
	for c in row_controls:
		c.queue_free()
	row_controls.clear()

	var is_dead = diablo_bridge.is_player_dead() if (diablo_bridge and diablo_bridge.has_method("is_player_dead")) else false
	if is_dead:
		_panel.add_theme_stylebox_override("panel", _death_panel_style)
		_title_label.add_theme_stylebox_override("normal", _death_title_style)
		_title_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.12, 1.0))
		_title_label.add_theme_font_size_override("font_size", 34)
	else:
		_panel.add_theme_stylebox_override("panel", _default_panel_style)
		_title_label.add_theme_stylebox_override("normal", _default_title_style)
		_title_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45, 1.0))
		_title_label.add_theme_font_size_override("font_size", 24)

	var visible_idx := 0
	var is_first_row := true
	for d in items:
		var item_idx = visible_idx
		visible_idx += 1

		var text = str(d.get("text", ""))
		var enabled = bool(d.get("enabled", true))
		var selectable = bool(d.get("selectable", true))
		var price = int(d.get("price", 0))

		if not selectable:
			# If the first non-selectable item is identical to the title label, skip repeating it
			if is_first_row and text.strip_edges() == _title_label.text.strip_edges():
				is_first_row = false
				continue
			is_first_row = false

			# Non-selectable header or prompt (e.g. "The Town Elder", "Would you like to:")
			var lbl := Label.new()
			lbl.name = "HeaderLabel"
			lbl.text = text
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.add_theme_color_override("font_color", Color(0.80, 0.75, 0.65, 0.9))
			lbl.add_theme_font_size_override("font_size", 14)
			_rows_container.add_child(lbl)
			row_controls.append(lbl)
		else:
			is_first_row = false
			# Interactive menu option button
			var btn := Button.new()
			btn.name = "MenuItem_%d" % item_idx
			btn.custom_minimum_size = Vector2(460, 42)
			btn.mouse_filter = Control.MOUSE_FILTER_STOP
			btn.focus_mode = Control.FOCUS_NONE

			if is_dead:
				btn.add_theme_stylebox_override("normal", _death_panel_style)
				btn.add_theme_stylebox_override("hover", _death_panel_style)
				btn.add_theme_stylebox_override("pressed", _death_panel_style)
				btn.add_theme_stylebox_override("disabled", _death_panel_style)
				btn.add_theme_font_size_override("font_size", 20)
				if not enabled:
					btn.disabled = true
					btn.text = text.to_upper()
					btn.add_theme_color_override("font_disabled_color", Color(0.42, 0.36, 0.30, 0.7))
				elif item_idx == sel:
					btn.text = "⛤  %s  ⛤" % text.to_upper()
					btn.add_theme_color_override("font_color", Color(1.0, 0.20, 0.08, 1.0))
					btn.add_theme_color_override("font_hover_color", Color(1.0, 0.20, 0.08, 1.0))
				else:
					btn.text = text.to_upper()
					btn.add_theme_color_override("font_color", Color(0.85, 0.75, 0.45, 0.95))
					btn.add_theme_color_override("font_hover_color", Color(1.0, 0.25, 0.12, 1.0))
			else:
				var normal_sb := _button_normal_box()
				var hover_sb := _button_hover_box()

				if not enabled:
					btn.disabled = true
					btn.add_theme_color_override("font_color", Color(0.42, 0.42, 0.45, 1.0))
					btn.add_theme_color_override("font_disabled_color", Color(0.35, 0.35, 0.38, 1.0))
				else:
					btn.add_theme_stylebox_override("normal", normal_sb)
					btn.add_theme_stylebox_override("hover", hover_sb)
					btn.add_theme_stylebox_override("pressed", hover_sb)
					btn.add_theme_color_override("font_color", Color(0.92, 0.88, 0.80, 1.0))
					btn.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.50, 1.0))
					btn.add_theme_font_size_override("font_size", 16)

				if item_idx == sel:
					btn.add_theme_stylebox_override("normal", _button_selected_box())
					btn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45, 1.0))

			if text == "Options":
				# Intercept D1's Options row -> open the native slider panel.
				btn.pressed.connect(_on_options_row_pressed.bind(item_idx))
			else:
				btn.pressed.connect(_on_item_pressed.bind(item_idx))
			btn.mouse_entered.connect(_on_item_hovered.bind(item_idx))

			if is_dead:
				btn.text = ("⛤  %s  ⛤" % text.to_upper()) if (item_idx == sel and enabled) else text.to_upper()
			elif price > 0:
				btn.text = ""
				var hbox := HBoxContainer.new()
				hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				hbox.offset_left = 16
				hbox.offset_right = -16
				hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

				var name_lbl := Label.new()
				name_lbl.text = text
				name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
				name_lbl.add_theme_font_size_override("font_size", 15)
				if not enabled:
					name_lbl.add_theme_color_override("font_color", Color(0.42, 0.42, 0.45, 1.0))
				elif item_idx == sel:
					name_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45, 1.0))
				else:
					name_lbl.add_theme_color_override("font_color", Color(0.92, 0.88, 0.80, 1.0))
				hbox.add_child(name_lbl)

				var price_lbl := Label.new()
				price_lbl.text = "%s Gold" % _format_number(price)
				price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				price_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				price_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
				price_lbl.add_theme_font_size_override("font_size", 15)
				if not enabled:
					price_lbl.add_theme_color_override("font_color", Color(0.5, 0.45, 0.3, 1.0))
				else:
					price_lbl.add_theme_color_override("font_color", Color(1.0, 0.84, 0.25, 1.0))
				hbox.add_child(price_lbl)

				btn.add_child(hbox)
			else:
				btn.text = text

			_rows_container.add_child(btn)
			row_controls.append(btn)
	_apply_font_recursive(_rows_container)

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

func _button_normal_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.09, 0.12, 0.92)
	sb.border_color = Color(0.45, 0.36, 0.22, 0.8)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_right = 4
	sb.corner_radius_bottom_left = 4
	return sb

func _button_hover_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.24, 0.18, 0.08, 0.96)
	sb.border_color = Color(1.0, 0.82, 0.30, 1.0)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_right = 4
	sb.corner_radius_bottom_left = 4
	return sb

func _button_selected_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.28, 0.20, 0.07, 0.95)
	sb.border_color = Color(1.0, 0.85, 0.35, 1.0)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_right = 4
	sb.corner_radius_bottom_left = 4
	return sb

func _set_title(t: int, is_qtext: bool) -> void:
	if is_qtext:
		var title = diablo_bridge.get_qtext_title() if diablo_bridge and diablo_bridge.has_method("get_qtext_title") else ""
		_title_label.text = title if not title.is_empty() else "Dialogue"
		return

	var is_dead = diablo_bridge.is_player_dead() if (diablo_bridge and diablo_bridge.has_method("is_player_dead")) else false
	if is_dead:
		var is_hf = diablo_bridge.is_hellfire() if (diablo_bridge and diablo_bridge.has_method("is_hellfire")) else true
		_title_label.text = "HELLFIRE" if is_hf else "DIABLO"
		return

	match t:
		1: _title_label.text = "Game Menu"
		2:
			var talker = diablo_bridge.get_qtext_title() if diablo_bridge and diablo_bridge.has_method("get_qtext_title") else ""
			_title_label.text = talker if not talker.is_empty() else "Dialogue"
		_: _title_label.text = ""

# Drive visibility + refresh each frame from D1's modal state
func _process(_delta: float) -> void:
	if not diablo_bridge or not diablo_bridge.has_method("is_modal_active"):
		visible = false
		_reset_options_state()
		return

	var active: bool = diablo_bridge.is_modal_active()
	if not active:
		visible = false
		current_type = -1
		last_item_count = -1
		last_sel = -2
		last_qtext_active = false
		_reset_options_state()
		return

	var is_qtext: bool = diablo_bridge.is_qtext_active() if diablo_bridge.has_method("is_qtext_active") else false

	if is_qtext:
		# Quest narrative speech dialogue
		_reset_options_state()
		visible = true
		_rows_container.visible = false
		_qtext_container.visible = true
		if _gold_label != null:
			_gold_label.visible = false

		var qlines: Array = diablo_bridge.get_qtext_lines() if diablo_bridge.has_method("get_qtext_lines") else []
		var new_text: String = "\n".join(qlines)
		if not last_qtext_active or _qtext_label.text != new_text:
			last_qtext_active = true
			last_qtext_line_count = qlines.size()
			_set_title(2, true)
			_qtext_label.text = new_text
		return

	# Regular menu / dialogue list
	_qtext_container.visible = false
	_rows_container.visible = true
	last_qtext_active = false

	var mtype: int = diablo_bridge.get_modal_type() if diablo_bridge.has_method("get_modal_type") else 0
	var items: Array = diablo_bridge.get_current_menu_items() if diablo_bridge.has_method("get_current_menu_items") else []
	var item_count := items.size()

	if item_count == 0:
		visible = false
		current_type = -1
		last_item_count = -1
		last_sel = -2
		_reset_options_state()
		return

	# --- Native Options panel state machine (Music/Sound/Gamma/Speed) ---
	var has_prev_menu := _items_contain(items, "Previous Menu")

	if _options_closing:
		# Waiting for D1 to leave its own options screen after "Previous Menu" activation.
		_closing_frames += 1
		if not has_prev_menu or _closing_frames > 60:
			_finalize_options_close()
		return

	if _options_open:
		visible = true
		_panel.visible = false
		_options_panel.visible = true
		return

	if mtype == 1 and has_prev_menu:
		# D1 switched to its own options screen (keyboard flow) -> open native panel.
		_open_options_panel()
		return

	visible = true

	var store_gold := -1
	if diablo_bridge and diablo_bridge.has_method("get_store_gold"):
		store_gold = diablo_bridge.get_store_gold()
	if store_gold >= 0:
		_gold_label.visible = true
		_gold_label.text = "Your Gold: %s" % _format_number(store_gold)
	else:
		_gold_label.visible = false

	var sel := -1
	if diablo_bridge.has_method("get_modal_selection_index"):
		sel = diablo_bridge.get_modal_selection_index()

	var is_dead = diablo_bridge.is_player_dead() if (diablo_bridge and diablo_bridge.has_method("is_player_dead")) else false

	if mtype != current_type or item_count != last_item_count or sel != last_sel or is_dead != last_is_dead:
		current_type = mtype
		last_item_count = item_count
		last_sel = sel
		last_is_dead = is_dead
		_set_title(mtype, false)
		_build_rows(mtype, items, sel)

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if _options_open or _options_closing:
			# Swallow every key while the options panel is open/closing so D1's menu
			# (and e.g. "Quit Game") can't be triggered by accident.
			get_viewport().set_input_as_handled()
			if event.keycode == KEY_ESCAPE:
				_close_options_panel()
			return
		if diablo_bridge and diablo_bridge.has_method("is_qtext_active") and diablo_bridge.is_qtext_active():
			if event.keycode == KEY_SPACE or event.keycode == KEY_ESCAPE or event.keycode == KEY_ENTER:
				_on_qtext_dismiss_pressed()
				get_viewport().set_input_as_handled()
