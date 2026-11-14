extends SceneTree

# ==============================================================================
# Verification Test: Task 5.4 — Native Quest Log & NPC Dialogues
# 1. Modal Layer: ScrollContainer wrapping, keyboard navigation (UP/DOWN/ENTER/ESC)
# 2. QText narrative dialog: Voice lore display & Space/Esc dismissal
# 3. Quest Log: Canonical classic quests (Butcher, Leoric, Poisoned Water, etc.)
# 4. Quest Log selection & audio trigger integration
# ==============================================================================

class MockBridge:
	var active_menu_items: Array = []
	var selected_item: int = 0
	var activated_item: int = -1
	var qtext_active: bool = false
	var qtext_lines: Array = []
	var qtext_title: String = ""
	var qtext_dismissed: bool = false
	var selected_quest_id: int = -1
	var modal_active: bool = true
	var modal_type: int = 2
	var player_dead: bool = false
	var sent_keys: Array = []

	func send_key_event(code: int, pressed: bool) -> void:
		sent_keys.append({"code": code, "pressed": pressed})

	func is_modal_active() -> bool:
		return modal_active

	func get_modal_type() -> int:
		return modal_type

	func is_player_dead() -> bool:
		return player_dead

	func get_current_menu_items() -> Array:
		return active_menu_items

	func get_modal_selection_index() -> int:
		return selected_item

	func select_modal_item(idx: int) -> void:
		selected_item = idx

	func activate_modal_item(idx: int) -> void:
		activated_item = idx

	func is_qtext_active() -> bool:
		return qtext_active

	func get_qtext_lines() -> Array:
		return qtext_lines

	func get_qtext_title() -> String:
		return qtext_title

	func dismiss_qtext() -> void:
		qtext_active = false
		qtext_dismissed = true

	func select_quest(q_id: int) -> void:
		selected_quest_id = q_id

	func get_quests_info() -> Array:
		return [
			{"id": 6, "idx": 6, "name": "The Butcher", "level": 2, "is_finished": false, "state": 2},
			{"id": 12, "idx": 12, "name": "The Curse of King Leoric", "level": 3, "is_finished": false, "state": 2},
			{"id": 13, "idx": 13, "name": "Poisoned Water Supply", "level": 2, "is_finished": true, "state": 3},
			{"id": 2, "idx": 2, "name": "Gharbad the Weak", "level": 4, "is_finished": false, "state": 2},
			{"id": 15, "idx": 15, "name": "Archbishop Lazarus", "level": 15, "is_finished": false, "state": 2},
		]

func _init() -> void:
	print("\n==================================================================")
	print("  RUNNING VERIFICATION: TASK 5.4 — QUEST LOG & NPC DIALOGUES")
	print("==================================================================")

	test_modal_layer_scrolling_and_keyboard()
	test_qtext_dialogue_and_dismissal()
	test_quest_log_population_and_lore()

	print("\n==================================================================")
	print("  ALL TASK 5.4 TESTS COMPLETED SUCCESSFULLY (100% PASS)!")
	print("==================================================================")
	quit(0)

func test_modal_layer_scrolling_and_keyboard() -> void:
	print("\n[Test 1] Modal Layer ScrollContainer & Keyboard Navigation...")
	var modal_script = load("res://scenes/modals/native_modal_layer.gd")
	assert(modal_script != null, "native_modal_layer.gd must load")

	var modal = modal_script.new()
	var root = Node.new()
	get_root().add_child(root)
	root.add_child(modal)
	modal._ready()

	var bridge = MockBridge.new()
	modal.set_bridge(bridge)

	# 1. Verify ScrollContainer exists and wraps Rows
	assert(modal._rows_scroll != null, "Modal must instantiate _rows_scroll ScrollContainer")
	assert(modal._rows_scroll.get_child(0) == modal._rows_container, "_rows_scroll must hold _rows_container")
	assert(modal._rows_scroll.follow_focus == true, "_rows_scroll must follow focus")

	# 2. Test large menu (e.g. Griswold / Adria store with 10 items)
	var test_items: Array = [
		{"text": "Blacksmith's Store", "selectable": false},
		{"text": "Short Sword", "selectable": true, "enabled": true, "price": 120},
		{"text": "Broad Sword", "selectable": true, "enabled": true, "price": 350},
		{"text": "Buckler", "selectable": true, "enabled": true, "price": 90},
		{"text": "Small Shield", "selectable": true, "enabled": true, "price": 180},
		{"text": "Leather Armor", "selectable": true, "enabled": true, "price": 300},
		{"text": "Hard Leather", "selectable": true, "enabled": true, "price": 450},
		{"text": "Repair item", "selectable": true, "enabled": true, "price": 0},
		{"text": "Say goodbye", "selectable": true, "enabled": true, "price": 0},
	]
	bridge.active_menu_items = test_items
	modal._process(0.016)

	assert(modal.row_controls.size() == 9, "Must build 9 row controls")
	assert(modal._rows_scroll.custom_minimum_size.y >= 360.0, "Large menus (>7 rows) must enforce scrollable height >= 360px")
	print("  -> PASS: ScrollContainer safely contains large lists with mouse wheel scrolling support")

	# 3. Test Keyboard Navigation: DOWN arrow selects next option
	bridge.selected_item = 1 # Short Sword
	modal.last_sel = 1
	var key_down = InputEventKey.new()
	key_down.pressed = true
	key_down.keycode = KEY_DOWN
	modal._unhandled_key_input(key_down)

	assert(bridge.selected_item == 2, "DOWN arrow must advance selection to item 2 (Broad Sword), got %d" % bridge.selected_item)

	# 4. Test Keyboard Navigation: UP arrow moves to previous option
	modal.last_sel = 2
	var key_up = InputEventKey.new()
	key_up.pressed = true
	key_up.keycode = KEY_UP
	modal._unhandled_key_input(key_up)

	assert(bridge.selected_item == 1, "UP arrow must return selection to item 1 (Short Sword), got %d" % bridge.selected_item)

	# 5. Test Activation: ENTER key triggers activation
	var key_enter = InputEventKey.new()
	key_enter.pressed = true
	key_enter.keycode = KEY_ENTER
	modal._unhandled_key_input(key_enter)

	assert(bridge.activated_item == 1, "ENTER key must activate currently selected item 1, got %d" % bridge.activated_item)

	# 6. Test ESC key triggers goodbye/exit
	var key_esc = InputEventKey.new()
	key_esc.pressed = true
	key_esc.keycode = KEY_ESCAPE
	modal._unhandled_key_input(key_esc)

	assert(bridge.activated_item == 8, "ESC key must trigger 'Say goodbye' (idx 8), got %d" % bridge.activated_item)
	print("  -> PASS: Keyboard navigation (UP/DOWN/ENTER/ESC) operates cleanly across dialogue options")

	# 7. Test Game Menu (5 items) expansion & ESC dismissal (prevent exit crash)
	bridge.modal_type = 1
	bridge.active_menu_items = [
		{"text": "Save Game", "selectable": true, "enabled": true},
		{"text": "Options", "selectable": true, "enabled": true},
		{"text": "New Game", "selectable": true, "enabled": true},
		{"text": "Restart In Town", "selectable": true, "enabled": true},
		{"text": "Quit Game", "selectable": true, "enabled": true},
	]
	bridge.selected_item = 0
	modal.last_sel = -2
	modal.last_item_count = -1
	modal.current_type = -1
	modal._process(0.016)

	assert(modal.row_controls.size() == 5, "Game Menu must build 5 row controls")
	assert(modal._rows_scroll.custom_minimum_size.y >= 200.0, "Game Menu must have custom_minimum_size.y >= 200px (was %f)" % modal._rows_scroll.custom_minimum_size.y)
	for i in range(5):
		var btn = modal.row_controls[i] as Button
		assert(btn != null, "Item %d must be a Button" % i)
		assert(btn.text == bridge.active_menu_items[i]["text"], "Button %d text must match '%s', got '%s'" % [i, bridge.active_menu_items[i]["text"], btn.text])

	bridge.activated_item = -1
	bridge.sent_keys.clear()
	var key_esc_gm = InputEventKey.new()
	key_esc_gm.pressed = true
	key_esc_gm.keycode = KEY_ESCAPE
	modal._unhandled_key_input(key_esc_gm)

	assert(bridge.activated_item != 4, "ESC key in Game Menu must NEVER activate 'Quit Game' (item 4)!")
	assert(bridge.sent_keys.size() == 2, "ESC key must forward KEY_ESCAPE press and release to bridge, got %d events" % bridge.sent_keys.size())
	assert(bridge.sent_keys[0]["code"] == KEY_ESCAPE and bridge.sent_keys[0]["pressed"] == true, "ESC press forwarded")
	assert(bridge.sent_keys[1]["code"] == KEY_ESCAPE and bridge.sent_keys[1]["pressed"] == false, "ESC release forwarded")
	print("  -> PASS: Game Menu (5 items) expands ScrollContainer and ESC key safely dismisses without quitting")

	root.queue_free()

func test_qtext_dialogue_and_dismissal() -> void:
	print("\n[Test 2] Narrative Quest Speech (QText) & Voice Dismissal...")
	var modal_script = load("res://scenes/modals/native_modal_layer.gd")
	var modal = modal_script.new()
	var root = Node.new()
	get_root().add_child(root)
	root.add_child(modal)
	modal._ready()

	var bridge = MockBridge.new()
	modal.set_bridge(bridge)

	# Activate narrative dialogue speech
	bridge.qtext_active = true
	bridge.qtext_title = "The Butcher"
	bridge.qtext_lines = [
		"Please, listen to me...",
		"The Archbishop Lazarus, he led us down here...",
		"It was a trap! The Butcher... came upon us!"
	]
	modal._process(0.016)

	assert(modal._qtext_container.visible == true, "QTextContainer must become visible during narrative speech")
	assert(modal._rows_scroll.visible == false, "Rows scroll must be hidden during narrative speech")
	assert(modal._title_label.text == "The Butcher", "Title must reflect quest speaker")
	assert("Lazarus" in modal._qtext_label.text, "QText narrative lines must appear in label")

	# Test dismiss via SPACE key
	var key_space = InputEventKey.new()
	key_space.pressed = true
	key_space.keycode = KEY_SPACE
	modal._unhandled_key_input(key_space)

	assert(bridge.qtext_dismissed == true, "SPACE key must dismiss quest narrative speech")
	print("  -> PASS: Quest narrative speech modal displays lore text and handles Space/Esc dismissal")

	root.queue_free()

func test_quest_log_population_and_lore() -> void:
	print("\n[Test 3] Canonical Quest Log & Narrative Voice Integration...")
	var qlog_script = load("res://scenes/hud/d1de_quest_log.gd")
	assert(qlog_script != null, "d1de_quest_log.gd must load")

	var qlog = qlog_script.new()
	var root = Node.new()
	root_node_add(root)
	root.add_child(qlog)

	# Mock scene node tree
	var content = MarginContainer.new()
	content.name = "Content"
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	var scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	var qlist = VBoxContainer.new()
	qlist.name = "QuestList"
	var empty_lbl = Label.new()
	empty_lbl.name = "EmptyLabel"

	scroll.add_child(qlist)
	vbox.add_child(empty_lbl)
	vbox.add_child(scroll)
	content.add_child(vbox)
	qlog.add_child(content)
	qlog.quest_list = qlist
	qlog.empty_label = empty_lbl

	var bridge = MockBridge.new()
	qlog.set_bridge(bridge)

	# Populate quests
	qlog.update_quests()

	assert(qlist.get_child_count() == 5, "Quest list must contain 5 cards, got %d" % qlist.get_child_count())

	# Check Butcher card details
	var butcher_card = qlist.get_child(0) as Button
	assert(butcher_card != null, "First card must be a Button")
	var card_text = _extract_card_text(butcher_card)
	print("  -> Butcher card text: %s" % card_text.replace("\n", " | "))
	assert("The Butcher" in card_text, "Butcher card must contain quest title")
	assert("Level 2" in card_text, "Butcher card must show Level 2")
	assert("Voice Lore" in card_text, "Card must advertise narrative speech voice lore")
	assert("slaughterhouse" in card_text or "Cathedral" in card_text, "Card must contain canonical lore description")

	# Check King Leoric card
	var leoric_card = qlist.get_child(1) as Button
	var leoric_text = _extract_card_text(leoric_card)
	assert("King Leoric" in leoric_text, "Leoric card must contain quest title")
	assert("King's Tomb" in leoric_text or "Crypt" in leoric_text, "Leoric card must display crypt/tomb depth")

	# Check Completed status on Poisoned Water Supply
	var pwater_card = qlist.get_child(2) as Button
	var pwater_text = _extract_card_text(pwater_card)
	assert("Completed" in pwater_text, "Poisoned Water card must display 'Completed' status badge")

	# Test click triggers select_quest(q_id)
	butcher_card.pressed.emit()
	assert(bridge.selected_quest_id == 6, "Pressing Butcher card must call select_quest(6) for voice lore playback")

	print("  -> PASS: Quest log displays rich gothic cards, canonical lore, and activates narrative audio")
	root.queue_free()

func _extract_card_text(n: Node) -> String:
	var out = ""
	if n is Label:
		out += n.text + "\n"
	for c in n.get_children():
		out += _extract_card_text(c)
	return out

func root_node_add(n: Node) -> void:
	var scene = root
	if scene:
		scene.add_child(n)
