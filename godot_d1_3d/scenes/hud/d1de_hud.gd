extends CanvasLayer

@export var bridge_receiver: Node3D = null

# Node references
@onready var life_globe: ColorRect = $Root/HBox/LifeContainer/LifeGlobe
@onready var life_label: Label = $Root/HBox/LifeContainer/LifeLabel
@onready var life_tooltip: Control = $Root/HBox/LifeContainer/LifeTooltipArea

@onready var mana_globe: ColorRect = $Root/HBox/ManaContainer/ManaGlobe
@onready var mana_label: Label = $Root/HBox/ManaContainer/ManaLabel
@onready var mana_tooltip: Control = $Root/HBox/ManaContainer/ManaTooltipArea

const TEX_HEAL = preload("res://assets/hud/potion_heal.png")
const TEX_MANA = preload("res://assets/hud/potion_mana.png")
const TEX_REJUV = preload("res://assets/hud/potion_rejuv.png")
const TEX_SCROLL = preload("res://assets/hud/scroll.png")
const TEX_OIL = preload("res://assets/hud/potion_oil.png")
const TEX_PORTAL = preload("res://assets/hud/portal_icon.png")
const FONT_EXOCET = preload("res://assets/fonts/Exocet.ttf")

# Town Portal & Smart Potion Slots
@onready var town_portal_slot: Control = $Root/HBox/TownPortalSlot
@onready var hp_potion_slot: Control = $Root/HBox/HealthPotionSlot
@onready var mana_potion_slot: Control = $Root/HBox/ManaPotionSlot
@onready var rejuv_potion_slot: Control = $Root/HBox/RejuvPotionSlot

# Action Bar
@onready var action_bar: Control = $Root/HBox/CenterPanel/VBox/ActionBar
@onready var skill_slots: Array[Control] = [
	$Root/HBox/CenterPanel/VBox/ActionBar/SkillSlot1,
	$Root/HBox/CenterPanel/VBox/ActionBar/SkillSlot2,
	$Root/HBox/CenterPanel/VBox/ActionBar/SkillSlot3,
	$Root/HBox/CenterPanel/VBox/ActionBar/SkillSlot4
]

# Center Frame Node
@onready var center_gothic_frame: Control = find_child("CenterGothicFrame", true, false)

# Durability Warnings
@onready var durability_container: HBoxContainer = $Root/DurabilityContainer
@onready var durability_slots: Array[TextureRect] = [
	$Root/DurabilityContainer/DurabilitySlot0,
	$Root/DurabilityContainer/DurabilitySlot1,
	$Root/DurabilityContainer/DurabilitySlot2,
	$Root/DurabilityContainer/DurabilitySlot3
]
var durability_pulse_time: float = 0.0

# XP & Level
@onready var xp_bar: ProgressBar = find_child("XPBar", true, false)
@onready var level_label: Label = find_child("LevelLabel", true, false)
@onready var gold_label: Label = find_child("GoldLabel", true, false)

# Item Tooltip Popup
@onready var item_tooltip: PanelContainer = $ItemTooltip
@onready var item_title_label: Label = $ItemTooltip/Margin/VBox/TitleLabel
@onready var item_divider: ColorRect = $ItemTooltip/Margin/VBox/Divider
@onready var item_stats_label: Label = $ItemTooltip/Margin/VBox/StatsLabel

# Enemy Health Bar (Top Center)
@onready var enemy_health_bar: Control = $EnemyHealthBar
@onready var enemy_name_label: Label = $EnemyHealthBar/VBox/MonsterName
@onready var enemy_sub_label: Label = $EnemyHealthBar/VBox/SubTitle
@onready var enemy_health_prog: ProgressBar = $EnemyHealthBar/VBox/BarCenter/BarContainer/HealthBar
@onready var enemy_ghost_prog: ProgressBar = $EnemyHealthBar/VBox/BarCenter/BarContainer/GhostBar
@onready var enemy_bar_frame: Panel = $EnemyHealthBar/VBox/BarCenter/BarContainer/BarFrame
@onready var enemy_hp_label: Label = $EnemyHealthBar/VBox/BarCenter/BarContainer/HpLabel
@onready var enemy_boss_crest: Label = $EnemyHealthBar/VBox/BarCenter/BarContainer/BossCrest

var current_target_monster_id: int = -1
var target_linger_timer: float = 0.0
var target_ghost_ratio: float = 1.0
var target_display_hp_ratio: float = 1.0
var enemy_bar_alpha: float = 0.0

# Skill Selector (Speedbook Ribbon)
@onready var skill_selector: PanelContainer = $SkillSelector
@onready var skill_list: HBoxContainer = $SkillSelector/Margin/SkillList

# Unified Tabbed Menu (Character, Inventory, Spellbook, Quests) & Stash Frame
const TABBED_MENU_SCENE = preload("res://scenes/hud/d1de_tabbed_menu.tscn")
const STASH_FRAME_SCENE = preload("res://scenes/hud/d1de_stash.tscn")
var tabbed_menu: Control = null
var stash_frame: Control = null


@onready var level_up_btn: Button = $Root/LevelUpBtn

var diablo_bridge = null
var current_spell_id: int = -1
var current_spell_type: int = -1
var is_speedbook_showing: bool = false
var hovered_speedbook_spell_id: int = -1
var hovered_speedbook_spell_type: int = -1
var quick_slot_spell_data: Array[Dictionary] = [{}, {}, {}, {}]
var spell_icon_cache: Dictionary = {}
var belt_icon_cache: Dictionary = {}
var tooltip_style: StyleBoxFlat

const QUALITY_TITLE_COLORS = {
	0: Color(0.92, 0.90, 0.85, 1.0),   # Normal: Crisp Silver/Bone
	1: Color(0.38, 0.68, 1.0, 1.0),    # Magic: Arcane Sky Blue
	2: Color(1.0, 0.84, 0.30, 1.0),    # Unique: Radiance Gold
	3: Color(1.0, 0.32, 0.32, 1.0)     # Unmet requirements / Red
}

const QUALITY_BORDER_COLORS = {
	0: Color(0.55, 0.52, 0.45, 0.9),   # Normal: Weathered Stone Gray
	1: Color(0.22, 0.52, 0.95, 0.95),  # Magic: Arcane Azure Glow
	2: Color(0.92, 0.74, 0.25, 1.0),   # Unique: Ornate Imperial Gold
	3: Color(0.92, 0.22, 0.22, 0.95)   # Unmet requirements / Crimson Warning
}

# Cache materials
var life_mat: ShaderMaterial
var mana_mat: ShaderMaterial

# Smooth display values
var display_hp: float = 100.0
var display_mana: float = 50.0

# Optimistic (native-predicted) item effect, shown while the engine action is still queued.
# Only applied when D1LogicAuthority reports AUTH_NATIVE for inventory_item_use.
var _optimistic: Dictionary = {}
const OPTIMISTIC_TTL_MS := 1500


## AUTH_NATIVE consumer: the native mirror predicted the item effect, so the globes react on the
## click instead of waiting for the engine thread to drain the queued action. The offset is dropped
## as soon as the engine's action sequence advances - from that frame on the engine value already
## contains the change, so keeping the offset would double count it.
func apply_optimistic_item_delta(hp_delta: int, mana_delta: int, seq_at_push: int) -> void:
	if hp_delta == 0 and mana_delta == 0:
		return
	_optimistic = {
		"hp": hp_delta,
		"mana": mana_delta,
		"seq": seq_at_push,
		"until": Time.get_ticks_msec() + OPTIMISTIC_TTL_MS,
	}

const SPELL_NAMES = {
	0: "Attack / Skill",
	1: "Firebolt",
	2: "Healing",
	3: "Lightning",
	4: "Flash",
	5: "Identify",
	6: "Fire Wall",
	7: "Town Portal",
	8: "Stone Curse",
	9: "Infravision",
	10: "Phasing",
	11: "Mana Shield",
	12: "Fireball",
	13: "Guardian",
	14: "Chain Lightning",
	15: "Flame Wave",
	16: "Doom Serpents",
	17: "Blood Ritual",
	18: "Nova",
	19: "Invisibility",
	20: "Inferno",
	21: "Golem",
	22: "Rage",
	23: "Teleport",
	24: "Apocalypse",
	25: "Etherealize",
	26: "Item Repair",
	27: "Staff Recharge",
	28: "Trap Disarm",
	29: "Elemental",
	30: "Charged Bolt",
	31: "Holy Bolt",
	32: "Resurrect",
	33: "Telekinesis",
	34: "Heal Other",
	35: "Blood Star",
	36: "Bone Spirit",
	37: "Mana",
	38: "Magi",
	39: "Jester",
	40: "Lightning Wall",
	41: "Immolation",
	42: "Warp",
	43: "Reflect",
	44: "Berserk",
	45: "Ring of Fire",
	46: "Search",
	47: "Rune of Fire",
	48: "Rune of Light",
	49: "Rune of Nova",
	50: "Rune of Immolation",
	51: "Rune of Stone"
}

const SPELL_TYPE_NAMES = {
	0: "Skill",
	1: "Spell",
	2: "Scroll",
	3: "Staff / Charges"
}

const SPELL_TYPE_COLORS = {
	0: Color(1.2, 1.25, 1.4, 1.0),   # Skill: Silver Steel / Golden
	1: Color(0.2, 0.65, 1.8, 1.0),   # Spell: Arcane Cyan/Blue
	2: Color(1.8, 1.4, 0.25, 1.0),   # Scroll: Ancient Gold
	3: Color(1.8, 0.55, 0.1, 1.0)    # Charges: Fiery Orange
}

func _ready():
	add_to_group("d1de_hud")
	if life_globe and life_globe.material is ShaderMaterial:
		life_mat = life_globe.material as ShaderMaterial
	if mana_globe and mana_globe.material is ShaderMaterial:
		mana_mat = mana_globe.material as ShaderMaterial

	if item_tooltip:
		var base_sb = item_tooltip.get_theme_stylebox("panel")
		if base_sb is StyleBoxFlat:
			tooltip_style = base_sb.duplicate()
			item_tooltip.add_theme_stylebox_override("panel", tooltip_style)

	# Instance Unified Tabbed Menu & Stash
	tabbed_menu = TABBED_MENU_SCENE.instantiate()
	tabbed_menu.visible = false
	add_child(tabbed_menu)

	stash_frame = STASH_FRAME_SCENE.instantiate()
	stash_frame.visible = false
	add_child(stash_frame)

	if diablo_bridge:
		set_bridge(diablo_bridge)



	# Ensure HUD root and popups start hidden until player is actually in-game
	$Root.visible = false
	if item_tooltip:
		item_tooltip.visible = false
	if skill_selector:
		skill_selector.visible = false
	if enemy_health_bar:
		enemy_health_bar.visible = false

	# Disable all keyboard focus grabbing on HUD elements so TAB key always toggles automap!
	_disable_focus_recursive(self)

	_apply_font_recursive($Root)
	if enemy_health_bar:
		_apply_font_recursive(enemy_health_bar)

	setup_button_events()

func _apply_font_recursive(node: Node):
	if node is Label:
		node.add_theme_font_override("font", FONT_EXOCET)
	elif node is Button:
		node.add_theme_font_override("font", FONT_EXOCET)
	for child in node.get_children():
		_apply_font_recursive(child)

func _disable_focus_recursive(node: Node):
	if node is Control:
		node.focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_disable_focus_recursive(child)

func set_bridge(bridge):
	diablo_bridge = bridge
	if tabbed_menu and tabbed_menu.has_method("set_bridge"):
		tabbed_menu.set_bridge(bridge)

	if stash_frame and stash_frame.has_method("set_bridge"):
		stash_frame.set_bridge(bridge)



func setup_button_events():
	# Town Portal Click
	if town_portal_slot:
		town_portal_slot.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				if diablo_bridge and diablo_bridge.has_method("use_smart_town_portal"):
					diablo_bridge.use_smart_town_portal()
		)

	# Smart Potion Clicks
	if hp_potion_slot:
		hp_potion_slot.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				if diablo_bridge and diablo_bridge.has_method("use_smart_potion"):
					diablo_bridge.use_smart_potion(0)
		)
	if mana_potion_slot:
		mana_potion_slot.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				if diablo_bridge and diablo_bridge.has_method("use_smart_potion"):
					diablo_bridge.use_smart_potion(1)
		)
	if rejuv_potion_slot:
		rejuv_potion_slot.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				if diablo_bridge and diablo_bridge.has_method("use_smart_potion"):
					diablo_bridge.use_smart_potion(2)
		)

	# Quick Skill Slots 1-4 Clicks
	for i in range(skill_slots.size()):
		var slot = skill_slots[i]
		var idx = i
		if slot:
			slot.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.pressed:
					if event.button_index == MOUSE_BUTTON_LEFT:
						var data = quick_slot_spell_data[idx] if idx < quick_slot_spell_data.size() else {}
						if data.is_empty():
							open_speedbook()
						else:
							if diablo_bridge and diablo_bridge.has_method("quick_cast_hotkey"):
								diablo_bridge.quick_cast_hotkey(idx)
					elif event.button_index == MOUSE_BUTTON_RIGHT:
						var data = quick_slot_spell_data[idx] if idx < quick_slot_spell_data.size() else {}
						if not data.is_empty():
							var s_id = data.get("id", 0)
							var s_type = data.get("type", 0)
							if diablo_bridge and diablo_bridge.has_method("select_spell"):
								diablo_bridge.select_spell(s_id, s_type)
							update_quick_skills()
						else:
							open_speedbook()
			)

	# Level Up Button (opens character sheet)
	if level_up_btn:
		level_up_btn.focus_mode = Control.FOCUS_NONE
		level_up_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		level_up_btn.pressed.connect(func():
			if tabbed_menu:
				tabbed_menu.open_tab(0)
		)

	# Durability Warning Slot Clicks (opens inventory)
	for slot in durability_slots:
		if slot:
			slot.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					if tabbed_menu:
						tabbed_menu.open_tab(1)
			)


func _input(event: InputEvent):
	if not visible:
		return
	var root_node = get_node_or_null("Root")
	if root_node and not root_node.visible:
		return

	var is_ingame = diablo_bridge.is_game_running() if (diablo_bridge and diablo_bridge.has_method("is_game_running")) else false
	if not is_ingame:
		return

	var is_text_active = diablo_bridge.is_text_input_active() if (diablo_bridge and diablo_bridge.has_method("is_text_input_active")) else false
	if is_text_active:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var kc = event.keycode

		# Smart Health Potion (Key Q)
		if kc == KEY_Q:
			if diablo_bridge and diablo_bridge.has_method("use_smart_potion"):
				diablo_bridge.use_smart_potion(0)
			get_viewport().set_input_as_handled()
			return
		# Smart Mana Potion (Key W)
		elif kc == KEY_W:
			if diablo_bridge and diablo_bridge.has_method("use_smart_potion"):
				diablo_bridge.use_smart_potion(1)
			get_viewport().set_input_as_handled()
			return
		# Smart Rejuvenation Potion (Key E)
		elif kc == KEY_E:
			if diablo_bridge and diablo_bridge.has_method("use_smart_potion"):
				diablo_bridge.use_smart_potion(2)
			get_viewport().set_input_as_handled()
			return
		# Smart Town Portal (Key T)
		elif kc == KEY_T:
			if diablo_bridge and diablo_bridge.has_method("use_smart_town_portal"):
				diablo_bridge.use_smart_town_portal()
			get_viewport().set_input_as_handled()
			return

		# Number Keys 1 - 9: Speedbook binding OR Quick Cast
		elif kc >= KEY_1 and kc <= KEY_9:
			var slot_idx = kc - KEY_1
			if is_speedbook_showing and hovered_speedbook_spell_id >= 0:
				if diablo_bridge and diablo_bridge.has_method("bind_spell_hotkey"):
					diablo_bridge.bind_spell_hotkey(hovered_speedbook_spell_id, hovered_speedbook_spell_type, slot_idx)
				if diablo_bridge and diablo_bridge.has_method("select_spell"):
					diablo_bridge.select_spell(hovered_speedbook_spell_id, hovered_speedbook_spell_type)
				populate_speedbook()
				update_quick_skills()
				get_viewport().set_input_as_handled()
				return
			else:
				if diablo_bridge and diablo_bridge.has_method("quick_cast_hotkey"):
					diablo_bridge.quick_cast_hotkey(slot_idx)
				get_viewport().set_input_as_handled()
				return

		# F1 - F4 Function Keys: Speedbook binding OR Quick Cast for HUD skill slots
		elif kc >= KEY_F1 and kc <= KEY_F12:
			var slot_idx = kc - KEY_F1
			if is_speedbook_showing and hovered_speedbook_spell_id >= 0:
				if diablo_bridge and diablo_bridge.has_method("bind_spell_hotkey"):
					diablo_bridge.bind_spell_hotkey(hovered_speedbook_spell_id, hovered_speedbook_spell_type, slot_idx)
				if diablo_bridge and diablo_bridge.has_method("select_spell"):
					diablo_bridge.select_spell(hovered_speedbook_spell_id, hovered_speedbook_spell_type)
				populate_speedbook()
				update_quick_skills()
				get_viewport().set_input_as_handled()
				return
			else:
				if diablo_bridge and diablo_bridge.has_method("quick_cast_hotkey"):
					diablo_bridge.quick_cast_hotkey(slot_idx)
				get_viewport().set_input_as_handled()
				return

		# Speedbook ribbon / select spell (hotkey S)
		elif kc == KEY_S:
			toggle_speedbook()
			get_viewport().set_input_as_handled()
			return
		# SpellBook grimoire window (hotkey B)
		elif kc == KEY_B:
			if tabbed_menu:
				tabbed_menu.toggle_tab(2)
			get_viewport().set_input_as_handled()
			return
		# Character Panel (hotkey C)
		elif kc == KEY_C:
			if tabbed_menu:
				tabbed_menu.toggle_tab(0)
			get_viewport().set_input_as_handled()
			return
		# Inventory Panel (hotkey I)
		elif kc == KEY_I:
			if tabbed_menu:
				tabbed_menu.toggle_tab(1)
			get_viewport().set_input_as_handled()
			return
		# Quest Log / Journal (hotkey J by default)
		elif kc == KEY_J:
			if tabbed_menu:
				tabbed_menu.toggle_tab(3)
			get_viewport().set_input_as_handled()
			return
		# Automap (hotkey Tab)
		elif kc == KEY_TAB:
			send_key(KEY_TAB)
			get_viewport().set_input_as_handled()
			return
		elif kc == KEY_ESCAPE:
			if diablo_bridge and diablo_bridge.has_method("get_cursor_id"):
				var cid = diablo_bridge.get_cursor_id()
				if cid > 1 and cid < 12:
					if diablo_bridge.has_method("cancel_targeting_cursor"):
						diablo_bridge.cancel_targeting_cursor()
					var vp = get_viewport()
					if vp: vp.set_input_as_handled()
					return
			if is_speedbook_showing:
				close_speedbook()
				var vp = get_viewport()
				if vp: vp.set_input_as_handled()
				return
			if stash_frame and stash_frame.visible:
				if diablo_bridge and diablo_bridge.has_method("close_stash"):
					diablo_bridge.close_stash()
				stash_frame.visible = false
				var vp = get_viewport()
				if vp: vp.set_input_as_handled()
				return
			if tabbed_menu and tabbed_menu.visible:
				tabbed_menu.close_menu()
				var vp = get_viewport()
				if vp: vp.set_input_as_handled()
				return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if diablo_bridge and diablo_bridge.has_method("get_cursor_id"):
				var cid = diablo_bridge.get_cursor_id()
				if cid > 1 and cid < 12:
					if diablo_bridge.has_method("cancel_targeting_cursor"):
						diablo_bridge.cancel_targeting_cursor()
					var vp = get_viewport()
					if vp: vp.set_input_as_handled()
					return

		if is_speedbook_showing:
			if skill_selector and skill_selector.visible:
				if not skill_selector.get_global_rect().has_point(event.position):
					if action_bar and not action_bar.get_global_rect().has_point(event.position):
						close_speedbook()

func toggle_spell_book():
	if diablo_bridge and diablo_bridge.has_method("toggle_spell_book"):
		diablo_bridge.toggle_spell_book()
	else:
		send_key(KEY_B)

func get_cached_spell_icon(spell_id: int, spell_type: int) -> Texture2D:
	var key = "%d_%d" % [spell_id, spell_type]
	if spell_icon_cache.has(key) and spell_icon_cache[key] != null:
		return spell_icon_cache[key]

	var hr_path = "res://assets/skills/%d.png" % spell_id
	if FileAccess.file_exists(hr_path):
		var img = Image.load_from_file(ProjectSettings.globalize_path(hr_path))
		if img != null:
			var hr_tex = ImageTexture.create_from_image(img)
			spell_icon_cache[key] = hr_tex
			return hr_tex

	if diablo_bridge and diablo_bridge.has_method("get_spell_icon_texture"):
		var tex = diablo_bridge.get_spell_icon_texture(spell_id, spell_type)
		if tex != null:
			spell_icon_cache[key] = tex
			return tex
	return null

func toggle_speedbook():
	if is_speedbook_showing:
		close_speedbook()
	else:
		open_speedbook()

func open_speedbook():
	if not diablo_bridge:
		return
	if diablo_bridge.has_method("get_player_spell"):
		current_spell_id = diablo_bridge.get_player_spell()
		current_spell_type = diablo_bridge.get_player_spell_type()
	is_speedbook_showing = true
	populate_speedbook()
	if skill_selector:
		skill_selector.visible = true
		skill_selector.reset_size()

func close_speedbook():
	is_speedbook_showing = false
	hovered_speedbook_spell_id = -1
	hovered_speedbook_spell_type = -1
	if skill_selector:
		skill_selector.visible = false

func populate_speedbook():
	if not skill_list:
		return
	for child in skill_list.get_children():
		child.queue_free()

	if not diablo_bridge or not diablo_bridge.has_method("get_available_spells"):
		return

	var spells = diablo_bridge.get_available_spells()
	if spells.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "No skills or spells available"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_color_override("font_color", Color(0.7, 0.65, 0.6))
		empty_lbl.add_theme_font_size_override("font_size", 11)
		empty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		skill_list.add_child(empty_lbl)
		return

	for spell_info in spells:
		var s_id: int = spell_info.get("id", 0)
		var s_type: int = spell_info.get("type", 0)
		var s_name: String = spell_info.get("name", "Spell")
		var mana: int = spell_info.get("mana_cost", 0)
		var hotkey: String = spell_info.get("hotkey", "")

		var btn = Button.new()
		btn.custom_minimum_size = Vector2(38, 38)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_filter = Control.MOUSE_FILTER_STOP

		var is_current = (s_id == current_spell_id and s_type == current_spell_type)

		# Diablo 4 style framed slots: radiant gold for active, crimson for scrolls, amber for staves, dark stone for spells/skills
		var normal_sb = StyleBoxFlat.new()
		normal_sb.set_corner_radius_all(3)
		if is_current:
			normal_sb.bg_color = Color(0.26, 0.20, 0.07, 0.90)
			normal_sb.border_color = Color(1.0, 0.84, 0.25, 1.0)
			normal_sb.border_width_left = 2
			normal_sb.border_width_top = 2
			normal_sb.border_width_right = 2
			normal_sb.border_width_bottom = 2
			normal_sb.shadow_color = Color(1.0, 0.8, 0.2, 0.45)
			normal_sb.shadow_size = 4
		elif s_type == 2: # Scroll (Classic Red Frame)
			normal_sb.bg_color = Color(0.18, 0.06, 0.06, 0.85)
			normal_sb.border_color = Color(0.80, 0.24, 0.24, 0.85)
			normal_sb.border_width_left = 1
			normal_sb.border_width_top = 1
			normal_sb.border_width_right = 1
			normal_sb.border_width_bottom = 1
		elif s_type == 3: # Staff / Charges (Classic Amber Frame)
			normal_sb.bg_color = Color(0.18, 0.11, 0.04, 0.85)
			normal_sb.border_color = Color(0.85, 0.55, 0.18, 0.85)
			normal_sb.border_width_left = 1
			normal_sb.border_width_top = 1
			normal_sb.border_width_right = 1
			normal_sb.border_width_bottom = 1
		else: # Memorized Spell or Skill
			normal_sb.bg_color = Color(0.08, 0.07, 0.09, 0.80)
			normal_sb.border_color = Color(0.35, 0.30, 0.22, 0.70)
			normal_sb.border_width_left = 1
			normal_sb.border_width_top = 1
			normal_sb.border_width_right = 1
			normal_sb.border_width_bottom = 1

		btn.add_theme_stylebox_override("normal", normal_sb)
		btn.add_theme_stylebox_override("focus", normal_sb)

		var hover_sb = normal_sb.duplicate()
		hover_sb.border_color = Color(1.0, 0.92, 0.50, 1.0)
		hover_sb.border_width_left = 2
		hover_sb.border_width_top = 2
		hover_sb.border_width_right = 2
		hover_sb.border_width_bottom = 2
		hover_sb.bg_color = Color(0.30, 0.24, 0.10, 0.95)
		btn.add_theme_stylebox_override("hover", hover_sb)
		btn.add_theme_stylebox_override("pressed", hover_sb)

		# Icon
		var icon_tex = get_cached_spell_icon(s_id, s_type)
		if icon_tex != null:
			var tex_rect = TextureRect.new()
			tex_rect.texture = icon_tex
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.custom_minimum_size = Vector2(34, 34)
			tex_rect.anchors_preset = Control.PRESET_FULL_RECT
			tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if is_current:
				tex_rect.modulate = Color(1.2, 1.15, 1.05)
			elif s_type == 2:
				# Subtle red warmth to match classic scroll tone
				tex_rect.modulate = Color(1.08, 0.96, 0.96)
			elif s_type == 3:
				# Subtle amber warmth to match classic staff tone
				tex_rect.modulate = Color(1.08, 1.02, 0.92)
			btn.add_child(tex_rect)

		# Active indicator badge (Gold Checkmark)
		if is_current:
			var active_badge = Label.new()
			active_badge.text = "✓"
			active_badge.add_theme_font_size_override("font_size", 11)
			active_badge.add_theme_color_override("font_color", Color(1.0, 0.90, 0.3, 1.0))
			active_badge.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1.0))
			active_badge.add_theme_constant_override("shadow_outline_size", 3)
			active_badge.position = Vector2(25, 23)
			active_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(active_badge)

		# Scroll / Staff Type Badge
		if s_type == 2: # Scroll indicator
			var scrl_badge = Label.new()
			scrl_badge.text = "📜"
			scrl_badge.add_theme_font_size_override("font_size", 10)
			scrl_badge.position = Vector2(1, 22)
			scrl_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(scrl_badge)
		elif s_type == 3: # Staff indicator
			var stf_badge = Label.new()
			stf_badge.text = "⚡"
			stf_badge.add_theme_font_size_override("font_size", 10)
			stf_badge.position = Vector2(1, 22)
			stf_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(stf_badge)

		# Hotkey badge
		if hotkey != "":
			var hk_lbl = Label.new()
			hk_lbl.text = hotkey
			hk_lbl.add_theme_font_size_override("font_size", 9)
			hk_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.4, 1.0))
			hk_lbl.position = Vector2(3, 1)
			hk_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(hk_lbl)

		var tip = ""
		if s_type == 2:
			tip = "Scroll of %s\n[Single Use - Consumable]" % s_name
		elif s_type == 3:
			tip = "Staff of %s\n[Charged Weapon Skill]" % s_name
		elif s_type == 0:
			tip = "%s (Innate Skill)" % s_name
		else:
			tip = "%s (Spell)" % s_name
			if mana > 0:
				tip += "\nMana Cost: %d" % mana

		if is_current:
			tip += "\n★ Currently Active (RMB)"
		if hotkey != "":
			tip += "\nHotkey: %s" % hotkey
		tip += "\n[Hover + F1-F12] Bind Quick Cast Hotkey"
		btn.tooltip_text = tip

		# Classic mouse hover binding detection
		btn.mouse_entered.connect(func():
			hovered_speedbook_spell_id = s_id
			hovered_speedbook_spell_type = s_type
		)
		btn.mouse_exited.connect(func():
			if hovered_speedbook_spell_id == s_id and hovered_speedbook_spell_type == s_type:
				hovered_speedbook_spell_id = -1
				hovered_speedbook_spell_type = -1
		)

		btn.pressed.connect(func():
			current_spell_id = s_id
			current_spell_type = s_type
			if diablo_bridge and diablo_bridge.has_method("select_spell"):
				diablo_bridge.select_spell(s_id, s_type)
			close_speedbook()
			update_quick_skills()
		)

		skill_list.add_child(btn)

func get_sdl_key(keycode: int) -> int:
	if keycode == KEY_ESCAPE: return 27
	if keycode == KEY_ENTER: return 13
	if keycode == KEY_SPACE: return 32
	if keycode == KEY_TAB: return 9
	if keycode == KEY_BACKSPACE: return 8
	if keycode >= KEY_0 and keycode <= KEY_9: return keycode
	if keycode >= KEY_A and keycode <= KEY_Z: return keycode + 32
	return keycode

func send_key(keycode: int):
	if not diablo_bridge:
		return
	var sdl_key = get_sdl_key(keycode)
	if diablo_bridge.has_method("send_key_event"):
		diablo_bridge.send_key_event(sdl_key, true)
		get_tree().create_timer(0.06).timeout.connect(func():
			if diablo_bridge and diablo_bridge.has_method("send_key_event"):
				diablo_bridge.send_key_event(sdl_key, false)
		)
	elif diablo_bridge.has_method("send_input"):
		diablo_bridge.send_input(3, sdl_key, 1, sdl_key, 0)
		get_tree().create_timer(0.06).timeout.connect(func():
			if diablo_bridge and diablo_bridge.has_method("send_input"):
				diablo_bridge.send_input(3, sdl_key, 0, sdl_key, 0)
		)

func _process(delta: float):
	if not diablo_bridge or not diablo_bridge.has_method("is_engine_ready") or not diablo_bridge.is_engine_ready():
		$Root.visible = false
		if item_tooltip: item_tooltip.visible = false
		if skill_selector: skill_selector.visible = false
		if tabbed_menu: tabbed_menu.visible = false
		if stash_frame: stash_frame.visible = false
		if enemy_health_bar: enemy_health_bar.visible = false
		if durability_container: durability_container.visible = false
		_reset_custom_cursor()
		return

	if diablo_bridge.has_method("is_game_running") and not diablo_bridge.is_game_running():
		$Root.visible = false
		if item_tooltip: item_tooltip.visible = false
		if skill_selector: skill_selector.visible = false
		if tabbed_menu: tabbed_menu.visible = false
		if stash_frame: stash_frame.visible = false
		if enemy_health_bar: enemy_health_bar.visible = false
		if durability_container: durability_container.visible = false
		_reset_custom_cursor()
		return

	var is_modern = true
	if diablo_bridge.has_method("is_vanilla_hud_hidden"):
		is_modern = diablo_bridge.is_vanilla_hud_hidden()

	if not is_modern:
		$Root.visible = false
		if durability_container: durability_container.visible = false
		if tabbed_menu: tabbed_menu.visible = false
		if stash_frame: stash_frame.visible = false
		if level_up_btn: level_up_btn.visible = false
		_reset_custom_cursor()
		return

	$Root.visible = true

	update_health_and_mana(delta)
	update_xp_and_level()
	update_smart_town_portal()
	update_smart_potions()
	update_quick_skills()
	update_enemy_health_bar(delta)
	update_item_tooltip()
	update_durability_warnings(delta)
	update_panels()
	update_custom_cursor()

func update_health_and_mana(delta: float):
	var hp = diablo_bridge.get_player_hp()
	var max_hp = diablo_bridge.get_player_max_hp()
	var mana = diablo_bridge.get_player_mana()
	var max_mana = diablo_bridge.get_player_max_mana()

	if max_hp <= 0: max_hp = 1
	if max_mana <= 0: max_mana = 1

	if not _optimistic.is_empty():
		if diablo_bridge != null and diablo_bridge.get_last_action_seq() > int(_optimistic.get("seq", 0)):
			_optimistic = {}
		elif Time.get_ticks_msec() > int(_optimistic.get("until", 0)):
			_optimistic = {}
			print("[HUD] optimistic item prediction expired without engine confirmation")
		else:
			hp = clampi(hp + int(_optimistic.get("hp", 0)), 0, max_hp)
			mana = clampi(mana + int(_optimistic.get("mana", 0)), 0, max_mana)

	# Smooth lerp
	display_hp = lerpf(display_hp, float(hp), clamp(delta * 12.0, 0.0, 1.0))
	display_mana = lerpf(display_mana, float(mana), clamp(delta * 12.0, 0.0, 1.0))

	var hp_ratio = clamp(display_hp / float(max_hp), 0.0, 1.0)
	var mana_ratio = clamp(display_mana / float(max_mana), 0.0, 1.0)

	if life_mat:
		life_mat.set_shader_parameter("fill_amount", hp_ratio)
	if mana_mat:
		mana_mat.set_shader_parameter("fill_amount", mana_ratio)

	if life_label:
		life_label.text = "%d / %d" % [int(round(display_hp)), max_hp]
	if mana_label:
		mana_label.text = "%d / %d" % [int(round(display_mana)), max_mana]

	if life_tooltip:
		life_tooltip.tooltip_text = "Life: %d / %d\nRight click or press potion 1-4 to heal." % [hp, max_hp]
	if mana_tooltip:
		mana_tooltip.tooltip_text = "Mana: %d / %d\nRight click or press potion 1-4 to restore mana." % [mana, max_mana]

func update_xp_and_level():
	var lvl = diablo_bridge.get_player_level()
	var xp = diablo_bridge.get_player_xp()
	var next_xp = diablo_bridge.get_player_next_xp()
	var gold = diablo_bridge.get_player_gold()

	if level_label:
		level_label.text = "Lv %d" % lvl

	if xp_bar:
		var ratio = 0.0
		if next_xp > 0:
			ratio = clamp(float(xp) / float(next_xp), 0.0, 1.0)
		xp_bar.value = ratio * 100.0
		xp_bar.tooltip_text = "Experience: %s / %s (%d%%)" % [format_number(xp), format_number(next_xp), int(ratio * 100.0)]

func update_smart_town_portal():
	if not diablo_bridge or not diablo_bridge.has_method("get_town_portal_summary"):
		return
	if not town_portal_slot:
		return

	var summary = diablo_bridge.get_town_portal_summary()
	var has_spell: bool = summary.get("has_spell", false)
	var spell_mana: int = summary.get("spell_mana_cost", 0)
	var can_cast: bool = summary.get("can_cast_spell", false)
	var scroll_count: int = summary.get("scroll_count", 0)
	var charge_count: int = summary.get("charge_count", 0)
	var best_mode: int = summary.get("best_mode", 0)

	var icon = town_portal_slot.get_node_or_null("ItemIcon") as TextureRect
	var count_lbl = town_portal_slot.get_node_or_null("CountLabel") as Label

	var total_avail = scroll_count + charge_count
	var is_available = (has_spell and can_cast) or (total_avail > 0)

	if icon:
		icon.texture = TEX_PORTAL
		icon.visible = true
		if is_available:
			icon.modulate = Color(1.0, 1.0, 1.0, 1.0)
		else:
			icon.modulate = Color(0.35, 0.35, 0.35, 0.5)

	if count_lbl:
		if has_spell and can_cast:
			count_lbl.text = "∞"
			count_lbl.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0, 1.0))
		elif total_avail > 0:
			count_lbl.text = str(total_avail)
			count_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
		else:
			count_lbl.text = "0"
			count_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.8))

	var tip = "Town Portal [T]\n"
	if best_mode == 1:
		tip += "Mode: Spell (Cost: %d Mana)\n" % spell_mana
		if scroll_count > 0: tip += "Backup Scrolls: %d\n" % scroll_count
		tip += "[LMB / Key T] Cast Town Portal"
	elif best_mode == 2:
		tip += "Mode: Scroll of Town Portal\nRemaining Scrolls: %d\n" % scroll_count
		if has_spell: tip += "(Insufficient mana for spell, using scroll)\n"
		tip += "[LMB / Key T] Read Scroll"
	elif best_mode == 3:
		tip += "Mode: Staff / Item Charges\nRemaining Charges: %d\n" % charge_count
		tip += "[LMB / Key T] Use Charge"
	else:
		if has_spell:
			tip += "Mode: Spell (Needs %d Mana)\n(Not enough mana to cast)\n" % spell_mana
		else:
			tip += "(No Town Portal spell or scrolls available)\n"
	town_portal_slot.tooltip_text = tip

func update_smart_potions():
	if not diablo_bridge or not diablo_bridge.has_method("get_potion_summary"):
		return
	var summary = diablo_bridge.get_potion_summary()
	var hp_count: int = summary.get("hp_count", 0)
	var hp_type: int = summary.get("hp_best_type", 0)
	var mana_count: int = summary.get("mana_count", 0)
	var mana_type: int = summary.get("mana_best_type", 0)
	var rejuv_count: int = summary.get("rejuv_count", 0)
	var rejuv_type: int = summary.get("rejuv_best_type", 0)

	# Health Potion Slot (Q)
	if hp_potion_slot:
		var icon = hp_potion_slot.get_node_or_null("ItemIcon") as TextureRect
		var count_lbl = hp_potion_slot.get_node_or_null("CountLabel") as Label
		if icon:
			if hp_type == 8: # Scroll of Healing
				icon.texture = TEX_SCROLL
				icon.visible = true
				icon.modulate = Color(1.0, 1.0, 1.0, 1.0)
			elif hp_type > 0:
				icon.texture = TEX_HEAL
				icon.visible = true
				icon.modulate = Color(1.2, 1.1, 1.1, 1.0) if hp_type == 2 else Color(1.0, 1.0, 1.0, 1.0)
			else:
				icon.texture = TEX_HEAL
				icon.visible = true
				icon.modulate = Color(0.35, 0.35, 0.35, 0.5)

		if count_lbl:
			count_lbl.text = str(hp_count)
			count_lbl.visible = true
			if hp_count == 0:
				count_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.8))
			else:
				count_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))

		var tip_hp = "Health Potion [Q]\nRemaining: %d" % hp_count
		if hp_count > 0:
			if hp_type == 2: tip_hp += "\nBest: Potion of Full Healing"
			elif hp_type == 1: tip_hp += "\nBest: Potion of Healing"
			elif hp_type == 8: tip_hp += "\nBest: Scroll of Healing"
			tip_hp += "\n[LMB / Key Q] Drink potion"
		else:
			tip_hp += "\n(No healing potions or scrolls in inventory)"
		hp_potion_slot.tooltip_text = tip_hp

	# Mana Potion Slot (W)
	if mana_potion_slot:
		var icon = mana_potion_slot.get_node_or_null("ItemIcon") as TextureRect
		var count_lbl = mana_potion_slot.get_node_or_null("CountLabel") as Label
		if icon:
			if mana_type > 0:
				icon.texture = TEX_MANA
				icon.visible = true
				icon.modulate = Color(1.1, 1.1, 1.3, 1.0) if mana_type == 4 else Color(1.0, 1.0, 1.0, 1.0)
			else:
				icon.texture = TEX_MANA
				icon.visible = true
				icon.modulate = Color(0.35, 0.35, 0.35, 0.5)

		if count_lbl:
			count_lbl.text = str(mana_count)
			count_lbl.visible = true
			if mana_count == 0:
				count_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.8))
			else:
				count_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))

		var tip_mana = "Mana Potion [W]\nRemaining: %d" % mana_count
		if mana_count > 0:
			if mana_type == 4: tip_mana += "\nBest: Potion of Full Mana"
			elif mana_type == 3: tip_mana += "\nBest: Potion of Mana"
			tip_mana += "\n[LMB / Key W] Drink potion"
		else:
			tip_mana += "\n(No mana potions in inventory)"
		mana_potion_slot.tooltip_text = tip_mana

	# Rejuvenation Potion Slot (E)
	if rejuv_potion_slot:
		var icon = rejuv_potion_slot.get_node_or_null("ItemIcon") as TextureRect
		var count_lbl = rejuv_potion_slot.get_node_or_null("CountLabel") as Label
		if icon:
			if rejuv_type > 0:
				icon.texture = TEX_REJUV
				icon.visible = true
				icon.modulate = Color(1.2, 1.1, 1.3, 1.0) if rejuv_type == 6 else Color(1.0, 1.0, 1.0, 1.0)
			else:
				icon.texture = TEX_REJUV
				icon.visible = true
				icon.modulate = Color(0.35, 0.35, 0.35, 0.5)

		if count_lbl:
			count_lbl.text = str(rejuv_count)
			count_lbl.visible = true
			if rejuv_count == 0:
				count_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 0.8))
			else:
				count_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))

		var tip_rejuv = "Rejuvenation Potion [E]\nRemaining: %d" % rejuv_count
		if rejuv_count > 0:
			if rejuv_type == 6: tip_rejuv += "\nBest: Potion of Full Rejuvenation"
			elif rejuv_type == 5: tip_rejuv += "\nBest: Potion of Rejuvenation"
			tip_rejuv += "\n[LMB / Key E] Drink potion"
		else:
			tip_rejuv += "\n(No rejuvenation potions in inventory)"
		rejuv_potion_slot.tooltip_text = tip_rejuv

func update_quick_skills():
	if not diablo_bridge or not diablo_bridge.has_method("get_available_spells"):
		return
	var spells = diablo_bridge.get_available_spells()
	var cur_mana = diablo_bridge.get_player_mana() if diablo_bridge.has_method("get_player_mana") else 999
	var active_spell_id: int = diablo_bridge.get_player_spell() if diablo_bridge.has_method("get_player_spell") else -1
	var active_spell_type: int = diablo_bridge.get_player_spell_type() if diablo_bridge.has_method("get_player_spell_type") else -1
	current_spell_id = active_spell_id
	current_spell_type = active_spell_type

	# Map hotkeys "F1", "F2", "F3", "F4" (which correspond to slots 1..4)
	var bound_spells = {}
	for sp in spells:
		var hk = sp.get("hotkey", "")
		if hk != "":
			bound_spells[hk] = sp

	for i in range(skill_slots.size()):
		var slot = skill_slots[i]
		if not slot: continue
		var hk_tag = "F%d" % (i + 1)
		var num_tag = "%d" % (i + 1)
		var icon = slot.get_node_or_null("Icon") as TextureRect
		var mana_badge = slot.get_node_or_null("ManaBadge") as Label
		var active_border = slot.get_node_or_null("ActiveBorder") as Panel
		var rmb_badge = slot.get_node_or_null("RmbBadge") as Label

		if bound_spells.has(hk_tag):
			var sp = bound_spells[hk_tag]
			quick_slot_spell_data[i] = sp
			var s_id: int = sp.get("id", 0)
			var s_type: int = sp.get("type", 0)
			var s_name: String = sp.get("name", "Spell")
			var mana_cost: int = sp.get("mana_cost", 0)
			var is_active = (s_id == active_spell_id and s_type == active_spell_type)

			var tex = get_cached_spell_icon(s_id, s_type)
			if icon:
				icon.texture = tex
				icon.visible = (tex != null)
				if cur_mana < mana_cost and s_type != 2:
					icon.modulate = Color(0.45, 0.45, 0.5, 0.75)
				else:
					icon.modulate = Color(1.0, 1.0, 1.0, 1.0)

			if active_border:
				active_border.visible = is_active
			if rmb_badge:
				rmb_badge.visible = is_active

			if mana_badge:
				if mana_cost > 0 and s_type != 2:
					mana_badge.text = str(mana_cost)
					mana_badge.visible = true
					if cur_mana < mana_cost:
						mana_badge.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3, 1.0))
					else:
						mana_badge.add_theme_color_override("font_color", Color(0.4, 0.75, 1.0, 1.0))
				elif s_type == 2:
					mana_badge.text = "📜"
					mana_badge.visible = true
				else:
					mana_badge.text = ""
					mana_badge.visible = false

			var type_name = SPELL_TYPE_NAMES.get(s_type, "Skill")
			var tip = "%s (%s) [%s]\n" % [s_name, type_name, num_tag]
			if is_active:
				tip = "★ ACTIVE [RMB] SPELL ★\n" + tip
			if mana_cost > 0:
				tip += "Mana Cost: %d\n" % mana_cost
			tip += "[LMB / Key %s] Quick Cast\n[RMB] Select as Active RMB Spell" % num_tag
			slot.tooltip_text = tip
		else:
			quick_slot_spell_data[i] = {}
			if icon:
				icon.texture = null
				icon.visible = false
			if active_border:
				active_border.visible = false
			if rmb_badge:
				rmb_badge.visible = false
			if mana_badge:
				mana_badge.text = ""
				mana_badge.visible = false
			slot.tooltip_text = "Quick Spell %d [%s]\n(Unassigned)\nPress 'S' to open Speedbook, hover over a skill and press %s to bind." % [i + 1, num_tag, num_tag]

func format_item_stats(raw_stats: String) -> String:
	if raw_stats.strip_edges() == "":
		return ""
	var lines = raw_stats.split("\n")
	var result_lines: Array[String] = []
	for l in lines:
		var line = l.strip_edges()
		if line.is_empty():
			continue
		var parts = line.split("  ")
		for part in parts:
			var p = part.strip_edges()
			if p.is_empty():
				continue
			if " Dur: " in p:
				var idx = p.find(" Dur: ")
				var p1 = p.substr(0, idx).strip_edges()
				var p2 = p.substr(idx + 1).strip_edges()
				if not p1.is_empty(): result_lines.append(p1)
				if not p2.is_empty(): result_lines.append(p2)
			elif " Indestructible" in p:
				var idx = p.find(" Indestructible")
				var p1 = p.substr(0, idx).strip_edges()
				var p2 = p.substr(idx + 1).strip_edges()
				if not p1.is_empty(): result_lines.append(p1)
				if not p2.is_empty(): result_lines.append(p2)
			elif " Charges: " in p:
				var idx = p.find(" Charges: ")
				var p1 = p.substr(0, idx).strip_edges()
				var p2 = p.substr(idx + 1).strip_edges()
				if not p1.is_empty(): result_lines.append(p1)
				if not p2.is_empty(): result_lines.append(p2)
			else:
				result_lines.append(p)

	return "\n".join(result_lines)

func update_enemy_health_bar(delta: float):
	if not enemy_health_bar:
		return

	if not diablo_bridge or not diablo_bridge.has_method("get_target_monster_summary"):
		enemy_health_bar.visible = false
		return

	# 1. Query if a monster is hovered right now
	var hover_summary: Dictionary = diablo_bridge.get_target_monster_summary(-1)
	var active_summary: Dictionary = {}

	if hover_summary.get("has_target", false) and hover_summary.get("is_hovered", false):
		var h_id = hover_summary.get("monster_id", -1)
		if h_id != current_target_monster_id:
			current_target_monster_id = h_id
			var h_hp = hover_summary.get("hp", 0)
			var h_max = max(1, hover_summary.get("max_hp", 1))
			target_ghost_ratio = float(h_hp) / float(h_max)
			target_display_hp_ratio = target_ghost_ratio
		target_linger_timer = 2.5
		active_summary = hover_summary
	elif current_target_monster_id >= 0 and target_linger_timer > 0.0:
		target_linger_timer -= delta
		var live_summary: Dictionary = diablo_bridge.get_target_monster_summary(current_target_monster_id)
		if live_summary.get("has_target", false):
			active_summary = live_summary
		else:
			current_target_monster_id = -1
	else:
		current_target_monster_id = -1

	# 2. Render active summary or fade out
	if not active_summary.is_empty() and active_summary.get("has_target", false):
		enemy_bar_alpha = move_toward(enemy_bar_alpha, 1.0, delta * 9.0)
		enemy_health_bar.visible = true
		enemy_health_bar.modulate.a = enemy_bar_alpha

		var m_name: String = active_summary.get("name", "Monster")
		var hp: int = active_summary.get("hp", 0)
		var max_hp: int = max(1, active_summary.get("max_hp", 1))
		var is_uniq: bool = active_summary.get("is_unique", false)
		var is_champ: bool = active_summary.get("is_champion", false)
		var m_class_name: String = active_summary.get("class_name", "")
		var resists: String = active_summary.get("resists", "")
		var immunes: String = active_summary.get("immunes", "")

		# Name & Color
		if enemy_name_label:
			enemy_name_label.text = m_name
			if is_uniq:
				enemy_name_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.25, 1.0)) # Warm radiant gold
				if enemy_boss_crest: enemy_boss_crest.visible = true
			elif is_champ:
				enemy_name_label.add_theme_color_override("font_color", Color(0.42, 0.72, 1.0, 1.0)) # Arcane blue
				if enemy_boss_crest: enemy_boss_crest.visible = false
			else:
				enemy_name_label.add_theme_color_override("font_color", Color(0.92, 0.90, 0.86, 1.0)) # Crisp bone white
				if enemy_boss_crest: enemy_boss_crest.visible = false

		# Subtitle / Affixes / Resists
		if enemy_sub_label:
			var sub_parts: Array[String] = []
			if m_class_name != "":
				sub_parts.append(m_class_name)
			if is_uniq:
				sub_parts.append("Unique")
			elif is_champ:
				sub_parts.append("Champion")
			if immunes != "":
				if immunes.to_lower().begins_with("immune"):
					sub_parts.append(immunes)
				else:
					sub_parts.append("Immune: " + immunes)
			if resists != "":
				if resists.to_lower().begins_with("resist"):
					sub_parts.append(resists)
				else:
					sub_parts.append("Resists: " + resists)

			if sub_parts.is_empty():
				enemy_sub_label.visible = false
			else:
				enemy_sub_label.visible = true
				enemy_sub_label.text = " • ".join(sub_parts)

		# HP ratios
		var actual_ratio: float = clampf(float(hp) / float(max_hp), 0.0, 1.0)
		# Smooth primary health
		target_display_hp_ratio = move_toward(target_display_hp_ratio, actual_ratio, delta * 3.0)
		# Ghost damage lag
		if actual_ratio < target_ghost_ratio:
			target_ghost_ratio = move_toward(target_ghost_ratio, actual_ratio, delta * 0.45)
		else:
			target_ghost_ratio = actual_ratio

		if enemy_health_prog:
			enemy_health_prog.value = target_display_hp_ratio * 100.0
		if enemy_ghost_prog:
			enemy_ghost_prog.value = target_ghost_ratio * 100.0

		if enemy_hp_label:
			if hp <= 0:
				enemy_hp_label.text = "DEAD"
				target_linger_timer = minf(target_linger_timer, 0.7) # Fade out soon after kill
			else:
				enemy_hp_label.text = "%d / %d (%d%%)" % [hp, max_hp, int(round(actual_ratio * 100.0))]

		# Frame border color: Gold for Unique, Antique Bronze for Normal
		if enemy_bar_frame:
			var sb: StyleBoxFlat = enemy_bar_frame.get_theme_stylebox("panel")
			if sb:
				if is_uniq:
					sb.border_color = Color(0.95, 0.80, 0.25, 1.0)
				else:
					sb.border_color = Color(0.55, 0.46, 0.32, 1.0)
	else:
		enemy_bar_alpha = move_toward(enemy_bar_alpha, 0.0, delta * 5.0)
		if enemy_bar_alpha <= 0.001:
			enemy_health_bar.visible = false
			current_target_monster_id = -1
		else:
			enemy_health_bar.modulate.a = enemy_bar_alpha

func update_item_tooltip():
	if not diablo_bridge or not diablo_bridge.has_method("has_hover_item"):
		if item_tooltip and item_tooltip.visible:
			item_tooltip.visible = false
		return

	if not diablo_bridge.has_hover_item():
		if item_tooltip and item_tooltip.visible:
			item_tooltip.visible = false
		return

	var info = diablo_bridge.get_hover_item_info()
	var is_inv: bool = info.get("is_inventory", false)
	var is_monster: bool = info.get("is_monster", false)
	if is_monster:
		if item_tooltip and item_tooltip.visible:
			item_tooltip.visible = false
		return
	var item_name: String = info.get("name", "")
	if item_name.strip_edges() == "":
		if item_tooltip and item_tooltip.visible:
			item_tooltip.visible = false
		return

	# If mouse cursor is hovering over the modernized HUD container itself, or open windows (stash, tabbed menu), don't show ground item tooltips
	var cur_mouse = get_viewport().get_mouse_position()
	if not is_inv and not is_monster:
		if $Root.visible and $Root.get_global_rect().has_point(cur_mouse):
			if item_tooltip and item_tooltip.visible: item_tooltip.visible = false
			return
		if stash_frame and stash_frame.visible and stash_frame.get_global_rect().has_point(cur_mouse):
			if item_tooltip and item_tooltip.visible: item_tooltip.visible = false
			return
		if tabbed_menu and tabbed_menu.visible and tabbed_menu.get_global_rect().has_point(cur_mouse):
			if item_tooltip and item_tooltip.visible: item_tooltip.visible = false
			return

	var raw_stats: String = info.get("stats", "")
	var stats: String = format_item_stats(raw_stats)
	var quality: int = info.get("quality", 0)
	var mouse_pos: Vector2i = info.get("mouse_pos", Vector2i.ZERO)

	item_title_label.text = item_name
	item_stats_label.text = stats
	var has_stats = (stats != "")
	item_stats_label.visible = has_stats
	if item_divider:
		item_divider.visible = has_stats

	var title_col = QUALITY_TITLE_COLORS.get(quality, QUALITY_TITLE_COLORS[0])
	var border_col = QUALITY_BORDER_COLORS.get(quality, QUALITY_BORDER_COLORS[0])
	if is_monster and quality == 0:
		title_col = Color(0.96, 0.32, 0.32)
		border_col = Color(0.68, 0.18, 0.18)

	item_title_label.add_theme_color_override("font_color", title_col)
	if tooltip_style:
		tooltip_style.border_color = border_col
		if item_divider:
			item_divider.color = Color(border_col.r, border_col.g, border_col.b, 0.6)

	item_tooltip.visible = true
	item_tooltip.reset_size()

	var vp_size = get_viewport().get_visible_rect().size
	var d1_w = float(diablo_bridge.get_frame_width())
	var d1_h = float(diablo_bridge.get_frame_height())
	if d1_w <= 0: d1_w = 640.0
	if d1_h <= 0: d1_h = 480.0

	var scale_x = vp_size.x / d1_w
	var scale_y = vp_size.y / d1_h

	var tooltip_w = item_tooltip.size.x
	var tooltip_h = item_tooltip.size.y

	var target_pos = Vector2.ZERO
	if is_inv:
		# Classic D1 inventory is on the right 320px: place card cleanly to the left of the window
		var inv_left_x = (d1_w - 320.0) * scale_x
		target_pos.x = inv_left_x - tooltip_w - 14.0
		target_pos.y = clampf(float(mouse_pos.y) * scale_y - tooltip_h * 0.35, 20.0, vp_size.y - tooltip_h - 20.0)
		if target_pos.x < 10.0:
			target_pos.x = 10.0
	elif is_monster:
		# Monster Info Card: Top-center of screen (authentic ARPG header)
		target_pos.x = (vp_size.x - tooltip_w) * 0.5
		target_pos.y = 28.0
	else:
		# Ground / Belt hover: next to mouse cursor
		target_pos.x = cur_mouse.x + 18.0
		target_pos.y = cur_mouse.y + 12.0
		if target_pos.x + tooltip_w > vp_size.x - 10.0:
			target_pos.x = cur_mouse.x - tooltip_w - 14.0
		if target_pos.y + tooltip_h > vp_size.y - 10.0:
			target_pos.y = vp_size.y - tooltip_h - 10.0
		if target_pos.x < 10.0: target_pos.x = 10.0
		if target_pos.y < 10.0: target_pos.y = 10.0

	item_tooltip.position = target_pos

func format_number(n: int) -> String:
	if n <= 0: return "0"
	var s = str(n)
	var result = ""
	var cnt = 0
	for i in range(s.length() - 1, -1, -1):
		result = s[i] + result
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			result = "," + result
	return result

func update_panels():
	if not diablo_bridge:
		return

	var is_modern = true
	if diablo_bridge.has_method("is_vanilla_hud_hidden"):
		is_modern = diablo_bridge.is_vanilla_hud_hidden()

	if not is_modern:
		if tabbed_menu: tabbed_menu.visible = false
		if stash_frame: stash_frame.visible = false
		if level_up_btn: level_up_btn.visible = false
		return

	var vp_size = get_viewport().get_visible_rect().size

	# Geometry for Unified Tabbed Menu (Docked on Top-Right)
	if tabbed_menu:
		var menu_w = 544.0
		var menu_h = min(vp_size.y - 40.0, 660.0)
		var menu_x = vp_size.x - menu_w - 16.0
		var menu_y = 16.0
		tabbed_menu.position = Vector2(menu_x, menu_y)
		tabbed_menu.size = Vector2(menu_w, menu_h)

	# Geometry for Stash Frame (Docked on Left)
	if stash_frame:
		var stash_w = clampf(vp_size.x * 0.28, 440.0, 520.0)
		var stash_h = min(vp_size.y - 40.0, 740.0)
		stash_frame.position = Vector2(16.0, 16.0)
		stash_frame.size = Vector2(stash_w, stash_h)

		var stash_open = diablo_bridge.is_stash_open() if diablo_bridge.has_method("is_stash_open") else false
		if stash_frame.visible != stash_open:
			stash_frame.visible = stash_open
			if stash_open and stash_frame.has_method("update_stash"):
				stash_frame.update_stash()
		elif stash_open and stash_frame.has_method("check_and_update"):
			stash_frame.check_and_update()

	# Engine bridge sync for Tabbed Menu:
	if tabbed_menu:
		if diablo_bridge.has_method("get_active_ui_panel"):
			var active_engine_panel = diablo_bridge.get_active_ui_panel()
			if active_engine_panel >= 0:
				if not tabbed_menu.visible or tabbed_menu.get_current_tab() != active_engine_panel:
					tabbed_menu.open_tab(active_engine_panel)
			elif active_engine_panel == -1 and tabbed_menu.visible:
				tabbed_menu.visible = false

		if tabbed_menu.visible and tabbed_menu.has_method("check_and_update"):
			tabbed_menu.check_and_update()

	# Level-up indicator on HUD & BtnChar
	var stat_pts = 0
	if diablo_bridge.has_method("get_character_info"):
		var cinfo = diablo_bridge.get_character_info()
		stat_pts = cinfo.get("stat_pts", 0)

	if level_up_btn:
		if stat_pts > 0:
			level_up_btn.visible = true
			level_up_btn.text = "★ LEVEL UP! (%d Points) ★" % stat_pts
			var pulse = 0.75 + 0.35 * sin(Time.get_ticks_msec() * 0.008)
			level_up_btn.modulate = Color(1.0 + pulse * 0.5, 0.85 + pulse * 0.4, 0.2 + pulse * 0.3, 1.0)
		else:
			level_up_btn.visible = false

func update_durability_warnings(delta: float):
	if not durability_container:
		return

	if not diablo_bridge or not diablo_bridge.has_method("get_player_durability_warnings"):
		durability_container.visible = false
		return

	var warnings = diablo_bridge.get_player_durability_warnings()
	if warnings.is_empty():
		durability_container.visible = false
		for slot in durability_slots:
			if slot:
				slot.visible = false
		return

	durability_pulse_time += delta
	durability_container.visible = true

	var pulse = 0.7 + 0.3 * sin(durability_pulse_time * 6.0)

	for i in range(durability_slots.size()):
		var slot = durability_slots[i]
		if not slot:
			continue
		if i < warnings.size():
			var w = warnings[i]
			var icon_idx = w.get("icon_idx", 0)
			var cur_dur = w.get("durability", 0)
			var max_dur = w.get("max_durability", 0)
			var status = w.get("status", 1)
			var item_name = w.get("name", "Equipped Item")

			var tex = null
			if diablo_bridge.has_method("get_durability_icon_composite"):
				tex = diablo_bridge.get_durability_icon_composite(icon_idx, cur_dur)
			if tex == null and diablo_bridge.has_method("get_durability_icon"):
				tex = diablo_bridge.get_durability_icon(w.get("frame_idx", 0))

			slot.texture = tex
			slot.visible = (tex != null)

			var status_str = "Damaged"
			if cur_dur <= 0:
				status_str = "Broken"
			elif status == 2:
				status_str = "Critically Damaged"

			slot.tooltip_text = "%s\nDurability: %d / %d (%s)\n[LMB] Open Inventory" % [
				item_name, cur_dur, max_dur, status_str
			]

			# Subtle pulse effect for critical/broken items (status 2)
			if status == 2 or cur_dur <= 0:
				slot.modulate = Color(1.0, pulse, pulse, 1.0)
			else:
				slot.modulate = Color(1.0, 1.0, 1.0, 1.0)
		else:
			slot.visible = false

var last_custom_cursor_id: int = -1

func _reset_custom_cursor():
	if last_custom_cursor_id != -1:
		Input.set_custom_mouse_cursor(null)
		last_custom_cursor_id = -1

func update_custom_cursor():
	if not diablo_bridge or not diablo_bridge.has_method("get_cursor_id"):
		_reset_custom_cursor()
		return

	var cid: int = diablo_bridge.get_cursor_id()
	if cid == last_custom_cursor_id:
		return

	last_custom_cursor_id = cid

	# Targeting cursors: 2=Identify, 3=Repair, 4=Recharge, 5=Disarm, 6=Oil, 7=Telekinesis, 8=Resurrect, 9=Teleport, 10=HealOther, 11=Hourglass
	if cid > 1 and cid < 12:
		var tex: Texture2D = null
		if diablo_bridge.has_method("get_cursor_texture"):
			tex = diablo_bridge.get_cursor_texture(cid)
		if tex:
			Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, Vector2.ZERO)
		else:
			Input.set_custom_mouse_cursor(null)
	else:
		Input.set_custom_mouse_cursor(null)

func _exit_tree():
	_reset_custom_cursor()
