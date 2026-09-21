class_name DebugPanel
extends CanvasLayer
## Hidden-by-default test overlay. Toggle with the "debug_toggle" action
## (F12 / backtick). The buttons are TEST SHORTCUTS, not gameplay features:
## they poke the game state directly so rounds can be walked through quickly.

const PANEL_BG := Color(0.07, 0.12, 0.22, 0.92)

var main: Node = null

var _state_label: Label
var _round_label: Label
var _total_label: Label
var _letters_label: Label
var _word_label: Label
var _last_word_label: Label
var _scores_label: Label
var _refresh_accum := 0.0


func _ready() -> void:
	visible = false
	layer = 50
	_build_ui()


func toggle() -> void:
	visible = not visible
	refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_accum += delta
	if _refresh_accum >= 0.25:
		_refresh_accum = 0.0
		refresh()


func refresh() -> void:
	if main == null or not visible:
		return
	var game: GameManager = main.game
	if game == null:
		return
	_state_label.text = "state: %s" % _state_name(game.state)
	_round_label.text = "round: %d" % game.current_round
	_total_label.text = "total_score: %d" % game.total_score
	var letters_text := " ".join(game.letters)
	_letters_label.text = "letters: %s" % letters_text
	_word_label.text = "current_word: %s" % main.current_word
	var last := "-"
	if not game.current_words.is_empty():
		last = String(game.current_words.back())
	_last_word_label.text = "last_word: %s" % last
	_scores_label.text = "best: %d  potential: %d" % [
		game.best_category_value(), game.category_potential()
	]


func _state_name(state: int) -> String:
	match state:
		GameManager.GameState.MENU:
			return "MENU"
		GameManager.GameState.ROUND_START:
			return "ROUND_START"
		GameManager.GameState.PLAYING:
			return "PLAYING"
		GameManager.GameState.WORD_SUBMITTED:
			return "WORD_SUBMITTED"
		GameManager.GameState.ROUND_COMPLETE:
			return "ROUND_COMPLETE"
		GameManager.GameState.GAME_COMPLETE:
			return "GAME_COMPLETE"
	return "UNKNOWN(%d)" % state


func _build_ui() -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = Color(0.42, 0.55, 0.78, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 10.0
	style.content_margin_top = 10.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 10.0
	style.shadow_color = Color(0.0, 0.02, 0.08, 0.4)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(420, 0)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(8, 8)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	_state_label = _add_label(box)
	_round_label = _add_label(box)
	_total_label = _add_label(box)
	_letters_label = _add_label(box)
	_word_label = _add_label(box)
	_last_word_label = _add_label(box)
	_scores_label = _add_label(box)

	var separator := HSeparator.new()
	box.add_child(separator)

	var buttons_row := HBoxContainer.new()
	buttons_row.add_theme_constant_override("separation", 6)
	box.add_child(buttons_row)

	_add_debug_button(buttons_row, "+10 SCORE", func() -> void:
		main.debug_add_score(10))
	_add_debug_button(buttons_row, "RESHUFFLE", func() -> void:
		main.debug_reshuffle())

	var buttons_row2 := HBoxContainer.new()
	buttons_row2.add_theme_constant_override("separation", 6)
	box.add_child(buttons_row2)
	_add_debug_button(buttons_row2, "COMPLETE ROUND", func() -> void:
		main.debug_complete_round())
	_add_debug_button(buttons_row2, "NEW ROUND", func() -> void:
		main.debug_new_round())

	var buttons_row3 := HBoxContainer.new()
	buttons_row3.add_theme_constant_override("separation", 6)
	box.add_child(buttons_row3)
	_add_debug_button(buttons_row3, "RESET GAME", func() -> void:
		main.debug_reset_game())


func _add_label(parent: Control) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.97))
	parent.add_child(label)
	return label


func _add_debug_button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 13)
	button.custom_minimum_size = Vector2(0, 36)
	button.pressed.connect(action)
	parent.add_child(button)
