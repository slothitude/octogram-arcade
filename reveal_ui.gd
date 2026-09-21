class_name RevealUi
extends Control
## Game-over reveal overlay (lives inside board8.tscn, hidden until the run
## ends): totals, best banner, found-X-of-Y, and every possible word grouped by
## length - the ones the player found in gold, the missed ones dim gray.
## Display only; main.gd decides what to feed in.

signal play_again_requested

const COLOR_DIM := Color(0.01, 0.03, 0.08, 0.86)
const COLOR_PANEL_BG := Color(0.07, 0.12, 0.22, 0.97)
const COLOR_PANEL_BORDER := Color(0.42, 0.55, 0.78, 0.9)
const COLOR_OUTLINE := Color(0.02, 0.05, 0.12, 0.92)
const COLOR_GOLD := Color(1.0, 0.84, 0.32)
const COLOR_GOLD_SOFT := Color(1.0, 0.88, 0.55)
const COLOR_TEXT := Color(0.96, 0.97, 0.99)
const COLOR_TEXT_SOFT := Color(0.82, 0.88, 0.96)
const COLOR_FOUND := Color(1.0, 0.84, 0.32)
const COLOR_MISSED := Color(0.55, 0.58, 0.66)

const MIN_WORD_LENGTH := 3
const MAX_WORD_LENGTH := 8

var _title_label: Label
var _total_label: Label
var _level_label: Label
var _best_label: Label
var _found_label: Label
var _scroll: ScrollContainer
var _words_box: VBoxContainer
var _pulse: Tween


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


## Fill the reveal and show it. `best_score`/`best_level` are the post-run
## maxima, so total >= best_score means the run just set the record.
func show_reveal(found: Array, possible: Array, total: int, level: int,
		best_score: int, best_level: int) -> void:
	_total_label.text = "TOTAL SCORE %d" % total
	_level_label.text = "LEVEL %d" % level
	_show_best_banner(total, level, best_score, best_level)
	_found_label.text = "You found %d of %d words" % [found.size(), possible.size()]
	_build_word_groups(found, possible)
	visible = true
	if _scroll != null:
		_scroll.scroll_vertical = 0


func hide_reveal() -> void:
	_stop_pulse()
	visible = false


func _show_best_banner(total: int, level: int, best_score: int, best_level: int) -> void:
	var new_best_score := total > 0 and total >= best_score
	var new_best_level := level > 0 and level >= best_level
	_stop_pulse()
	if new_best_score or new_best_level:
		_best_label.text = "NEW BEST!"
		_best_label.add_theme_color_override("font_color", COLOR_GOLD)
		_start_pulse()
	else:
		_best_label.text = "BEST %d  ·  LEVEL %d" % [best_score, best_level]
		_best_label.add_theme_color_override("font_color", COLOR_TEXT)


## Slow gold pulse on the NEW BEST banner - the only long tween in the game,
## and it lives on a screen where nothing else is happening.
func _start_pulse() -> void:
	if not _best_label.is_inside_tree():
		return
	_best_label.pivot_offset = _best_label.size * 0.5
	_pulse = create_tween().set_loops()
	_pulse.tween_property(_best_label, "scale", Vector2(1.07, 1.07), 0.35) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse.tween_property(_best_label, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_pulse() -> void:
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	_pulse = null
	if _best_label != null:
		_best_label.scale = Vector2.ONE


## All possible words grouped by length: header per length, gold for found,
## dim gray for missed, inside the scrollable list.
func _build_word_groups(found: Array, possible: Array) -> void:
	for child in _words_box.get_children():
		child.queue_free()
	var found_set := {}
	for entry in found:
		found_set[String(entry)] = true

	var by_length := {}
	for entry in possible:
		var word := String(entry)
		if not by_length.has(word.length()):
			by_length[word.length()] = []
		by_length[word.length()].append(word)

	var lengths: Array = by_length.keys()
	lengths.sort()
	for length in lengths:
		var header := Label.new()
		header.text = "%d LETTERS" % length
		header.add_theme_font_size_override("font_size", 20)
		header.add_theme_color_override("font_color", COLOR_GOLD_SOFT)
		header.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
		header.add_theme_constant_override("outline_size", 3)
		_words_box.add_child(header)

		var flow := HFlowContainer.new()
		flow.name = "Length%dWords" % length
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 4)
		for entry in by_length[length]:
			var word := String(entry)
			var word_label := Label.new()
			word_label.text = word
			word_label.add_theme_font_size_override("font_size", 19)
			word_label.add_theme_color_override("font_color",
				COLOR_FOUND if found_set.has(word) else COLOR_MISSED)
			word_label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
			word_label.add_theme_constant_override("outline_size", 3)
			flow.add_child(word_label)
		_words_box.add_child(flow)


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = COLOR_DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "RevealPanel"
	panel.anchor_left = 0.03
	panel.anchor_top = 0.02
	panel.anchor_right = 0.97
	panel.anchor_bottom = 0.98
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)

	var layout := VBoxContainer.new()
	layout.name = "Layout"
	layout.add_theme_constant_override("separation", 8)
	panel.add_child(layout)

	_title_label = _make_label("TitleLabel", "GAME OVER", 44, COLOR_GOLD, 6)
	layout.add_child(_title_label)

	_total_label = _make_label("TotalLabel", "TOTAL SCORE 0", 52, COLOR_GOLD, 7)
	layout.add_child(_total_label)

	_level_label = _make_label("LevelLabel", "LEVEL 1", 26, COLOR_TEXT, 4)
	layout.add_child(_level_label)

	_best_label = _make_label("BestLabel", "", 26, COLOR_GOLD, 4)
	_best_label.resized.connect(func() -> void:
		_best_label.pivot_offset = _best_label.size * 0.5)
	layout.add_child(_best_label)

	_found_label = _make_label("FoundLabel", "You found 0 of 0 words", 22, COLOR_TEXT_SOFT, 4)
	layout.add_child(_found_label)

	_scroll = ScrollContainer.new()
	_scroll.name = "WordsScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	layout.add_child(_scroll)

	_words_box = VBoxContainer.new()
	_words_box.name = "WordsBox"
	_words_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_words_box.add_theme_constant_override("separation", 6)
	_scroll.add_child(_words_box)

	var play_again := CircleButton.new()
	play_again.name = "PlayAgainButton"
	play_again.accent = "gold"
	play_again.text = "PLAY AGAIN"
	play_again.custom_minimum_size = Vector2(280, 76)
	play_again.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	play_again.add_theme_font_size_override("font_size", 24)
	play_again.pressed.connect(func() -> void: play_again_requested.emit())
	layout.add_child(play_again)


func _make_label(label_name: String, text: String, font_size: int, color: Color,
		outline: int) -> Label:
	var label := Label.new()
	label.name = label_name
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	label.add_theme_constant_override("outline_size", outline)
	return label


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL_BG
	style.border_color = COLOR_PANEL_BORDER
	style.set_corner_radius_all(22)
	style.set_border_width_all(2)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 24.0
	style.content_margin_bottom = 20.0
	style.shadow_color = Color(0.0, 0.02, 0.08, 0.5)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 5)
	return style
