extends SceneTree
## Headless smoke of the menu shell: boot main.tscn -> ModeMenu appears ->
## select_arena() starts the arena game with letters dealt; then ZoneMapUi and
## ShopUi are instantiated standalone to prove their signals and the buy flow
## (against a fresh Progression stub) work; finally FeedbackUi is exercised
## standalone (open/close/tags/send signal - the HTTP send itself is never
## tested here, there is no network headless).
## Run: godot --headless --path <project> --script res://tests/smoke_menu.gd
## Exits 0 when every check passes, 1 otherwise.

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	# Deferred start: the coroutine awaits process_frame, so it must begin once
	# the tree is actually ticking.
	_summary.call_deferred()


func _summary() -> void:
	await _run()
	print("")
	print("Ran %d menu smoke checks: %d passed, %d failed" % [
		_checks, _checks - _failures, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, check_name: String, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("PASS: " + check_name)
	else:
		_failures += 1
		print("FAIL: " + check_name + ((" - " + detail) if detail != "" else ""))


func _run() -> void:
	await _test_boot_and_arena()
	await _test_zone_map_standalone()
	await _test_shop_standalone()
	await _test_feedback_standalone()


## --- Part 1: boot -> ModeMenu -> select_arena -------------------------------


func _test_boot_and_arena() -> void:
	# Fresh save so the boot state is deterministic.
	var sd := SaveData.new()
	sd.save(0, 0, {"tutorial_seen": true, "smoke": true})

	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var menu := _find_mode_menu(main)
	_check(menu != null, "ModeMenu appears on boot")
	_check(menu != null and _find_button_by_text(menu, "EIGHT LETTERS") != null,
		"menu has an EIGHT LETTERS button")

	# FEEDBACK channel: the corner button exists, opens the overlay via main,
	# the auto-context names the current mode, CANCEL closes it again.
	var feedback_button: BaseButton = _find_button_by_text(menu, "FEEDBACK")
	_check(feedback_button != null, "menu has a FEEDBACK button")
	_check(feedback_button != null and String(feedback_button.get("accent")) == "gold",
		"FEEDBACK button is gold")
	if feedback_button != null:
		feedback_button.pressed.emit()
		await process_frame
	var overlay: Control = main.get("_feedback")
	_check(overlay != null and overlay.visible,
		"FEEDBACK button opens the overlay through main")
	if overlay != null:
		var context_label: Label = _find_node(overlay, "ContextLabel") as Label
		_check(context_label != null and String(context_label.text).contains("MENU"),
			"overlay shows the auto-context (menu mode)")
	var closes: Array = []
	if overlay != null:
		overlay.closed.connect(func() -> void: closes.append(1))
		var cancel: BaseButton = _find_node(overlay, "CancelButton") as BaseButton
		if cancel != null:
			cancel.pressed.emit()
	var overlay_hidden: bool = overlay != null and not overlay.visible
	_check(closes.size() == 1 and overlay_hidden, "CANCEL emits closed and hides the overlay")

	var progression: Object = main.get("progression")
	_check(progression != null, "main built a Progression from the save")
	var game: Object = main.get("game")
	_check(game != null and int(game.get("state")) == GameManager.GameState.MENU,
		"game sits in MENU until a mode is chosen (state=%s)" % str(game.get("state")))

	if menu == null:
		return
	menu.call("select_arena")
	await process_frame
	await process_frame

	_check(int(game.get("state")) == GameManager.GameState.PLAYING,
		"select_arena starts the game (state=%d)" % int(game.get("state")))
	var letters: Array = game.get("letters")
	_check(letters.size() == 8, "arena dealt 8 letters (%s)" % str(letters).substr(0, 24))
	_check(_find_mode_menu(main) == null, "ModeMenu gone after choosing a mode")


## --- Part 2: ZoneMapUi standalone -------------------------------------------


func _test_zone_map_standalone() -> void:
	var map: Control = (load("res://scenes/zone_map.tscn") as PackedScene).instantiate()
	_check(map.has_signal("encounter_selected"), "ZoneMapUi exposes encounter_selected")
	_check(map.has_signal("back_pressed"), "ZoneMapUi exposes back_pressed")

	var progression := Progression.new()
	progression.level = 3
	progression.xp = 20
	progression.gold = 120
	progression.zone = 2
	progression.encounter = 1

	map.setup(progression)
	root.add_child(map)
	await process_frame
	await process_frame

	_check(_find_node(map, "Zone_5") != null, "zone map built all 5 zone nodes")
	_check(_find_node(map, "BackButton") != null, "zone map has a BACK button")

	# Zone 1 fully cleared, zone 2 encounter 1 current, zone 3+ locked.
	var cleared_chip: BaseButton = _find_node(map, "Chip_1_1")
	var current_chip: BaseButton = _find_node(map, "Chip_2_1")
	var locked_chip: BaseButton = _find_node(map, "Chip_3_1")
	_check(cleared_chip != null and not cleared_chip.disabled,
		"cleared encounter stays replayable (enabled)")
	_check(current_chip != null and not current_chip.disabled,
		"current encounter is tappable")
	_check(locked_chip != null and locked_chip.disabled,
		"future encounter chip is locked (disabled)")

	var selected: Array = []
	map.encounter_selected.connect(func(zone: int, encounter: int) -> void:
		selected.append([zone, encounter]))
	if cleared_chip != null:
		cleared_chip.pressed.emit()
	_check(selected == [[1, 1]], "tapping a cleared node emits encounter_selected(1, 1)")

	var backs: Array = []
	map.back_pressed.connect(func() -> void: backs.append(1))
	var back_button: BaseButton = _find_node(map, "BackButton")
	if back_button != null:
		back_button.pressed.emit()
	_check(backs.size() == 1, "BACK button emits back_pressed")

	map.queue_free()
	await process_frame


## --- Part 3: ShopUi standalone (buy flow against a Progression stub) --------


func _test_shop_standalone() -> void:
	var shop: Control = (load("res://scenes/shop.tscn") as PackedScene).instantiate()
	_check(shop.has_signal("closed"), "ShopUi exposes closed")
	_check(shop.has_signal("item_bought"), "ShopUi exposes item_bought")

	var progression := Progression.new()
	progression.gold = 200

	shop.setup(progression)
	root.add_child(shop)
	await process_frame
	await process_frame

	var bought: Array = []
	shop.item_bought.connect(func(item_id: String) -> void: bought.append(item_id))

	var gold_label: Label = _find_node(shop, "GoldLabel")
	_check(gold_label != null and gold_label.text == "200", "shop shows the gold total")

	var quill_row: Control = _find_node(shop, "Row_sharp_quill")
	_check(quill_row != null, "shop built a row for sharp_quill")
	var quill_buy: BaseButton = _find_node(shop, "Row_sharp_quill/BuyButton")
	_check(quill_buy != null and not quill_buy.disabled, "BUY enabled when affordable")

	if quill_buy != null:
		quill_buy.pressed.emit()
		await process_frame
	_check(int(progression.upgrades.get("sharp_quill", 0)) == 1,
		"buying a stack lands in progression.upgrades")
	_check(int(progression.gold) == 170, "gold deducted (200 -> 170)")
	_check(bought == ["sharp_quill"], "item_bought emitted with the item id")

	# Escalation + max: 30 base -> 48 -> 76 (floored 1.6^2=2.56x). Gold 170
	# buys stack 2 (48), leaving 122; stack 3 costs 76, leaving 46.
	var quill_buy2: BaseButton = _find_node(shop, "Row_sharp_quill/BuyButton")
	if quill_buy2 != null:
		quill_buy2.pressed.emit()
		await process_frame
		quill_buy2.pressed.emit()
		await process_frame
	_check(int(progression.upgrades.get("sharp_quill", 0)) == 3, "stacks accumulate (3)")
	_check(int(progression.gold) == 46, "escalating costs charged (170 - 48 - 76 = 46)")
	_check(quill_buy2 != null and quill_buy2.disabled,
		"BUY disables when the gold runs out")

	# A maxed item can never be bought again.
	var max_progression := Progression.new()
	max_progression.gold = 9999
	shop.setup(max_progression)
	await process_frame
	for i in range(int(RpgConfig.SHOP_ITEMS["lucky_kelp"]["max_stacks"])):
		var kelp_buy: BaseButton = _find_node(shop, "Row_lucky_kelp/BuyButton")
		if kelp_buy == null:
			break
		kelp_buy.pressed.emit()
		await process_frame
	var kelp_final: BaseButton = _find_node(shop, "Row_lucky_kelp/BuyButton")
	_check(kelp_final != null and kelp_final.disabled, "BUY disables at max stacks")
	_check(kelp_final != null and kelp_final.text == "MAX", "maxed BUY reads MAX")

	var closes: Array = []
	shop.closed.connect(func() -> void: closes.append(1))
	var leave: BaseButton = _find_node(shop, "LeaveButton")
	if leave != null:
		leave.pressed.emit()
	_check(closes.size() == 1, "LEAVE emits closed")

	shop.queue_free()
	await process_frame


## --- Part 4: FeedbackUi standalone (no HTTP - nothing here hits the network) --


func _test_feedback_standalone() -> void:
	var overlay: Control = FeedbackUi.new()
	_check(overlay.has_signal("closed"), "FeedbackUi exposes closed")
	_check(overlay.has_signal("send_requested"), "FeedbackUi exposes send_requested")
	_check(not overlay.visible, "FeedbackUi starts hidden")

	root.add_child(overlay)
	await process_frame
	await process_frame

	overlay.open({"mode": "eight", "level": 4, "score": 120})
	_check(overlay.visible, "open() shows the overlay")
	var context_label: Label = _find_node(overlay, "ContextLabel") as Label
	_check(context_label != null and String(context_label.text).contains("EIGHT")
		and String(context_label.text).contains("4"),
		"open() renders the auto-context (mode + level)")

	var edit: TextEdit = _find_node(overlay, "MessageEdit") as TextEdit
	_check(edit != null, "overlay has a message TextEdit")
	var hint: Label = _find_node(overlay, "HintLabel") as Label
	_check(hint != null and hint.visible, "hint shows while the draft is empty")

	var sent: Array = []
	overlay.send_requested.connect(func(text: String) -> void: sent.append(text))

	edit.text = "more octopus colors please"
	await process_frame
	var tag: BaseButton = _find_node(overlay, "TagButton_4") as BaseButton
	if tag != null:
		tag.pressed.emit()
	_check(edit.text == "LOVE IT more octopus colors please",
		"tapping a tag prepends it to the draft (%s)" % edit.text)
	_check(hint != null and not hint.visible, "hint hides once there is a draft")

	var send: BaseButton = _find_node(overlay, "SendButton") as BaseButton
	if send != null:
		send.pressed.emit()
	_check(sent == ["LOVE IT more octopus colors please"],
		"SEND emits send_requested with the typed text")

	var closes: Array = []
	overlay.closed.connect(func() -> void: closes.append(1))
	overlay.close()
	_check(closes.size() == 1 and not overlay.visible, "close() hides + emits closed")

	overlay.open({"mode": "menu"})
	_check(overlay.visible and edit.text == "LOVE IT more octopus colors please",
		"reopening keeps the draft (a failed send never eats the text)")

	overlay.queue_free()
	await process_frame


## --- Helpers -----------------------------------------------------------------


func _find_mode_menu(main: Node) -> Node:
	for child in main.get_children():
		if child.has_method("select_arena"):
			return child
	return null


## Depth-first search for a button with an exact caption (menu buttons are built
## in code, so there is no stable node name to look up).
func _find_button_by_text(from: Node, text_value: String) -> Node:
	var stack: Array = [from]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is BaseButton and String(node.get("text")) == text_value:
			return node
		for child in node.get_children():
			stack.append(child)
	return null


## find_child does not understand "/" paths, so walk segment by segment.
func _find_node(from: Node, path_or_name: String) -> Node:
	var current := from
	for part in path_or_name.split("/"):
		if current == null:
			return null
		current = current.find_child(part, true, false)
	return current
