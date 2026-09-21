class_name UIController
extends Control
## Root controller of game_board.tscn. Owns every widget on the phone-portrait
## board: header, live score panel, category panel, current word, submitted
## words list, letter tiles, bottom controls, and the category-select /
## final-score overlays. Display only - game state lives in main.gd.
##
## Presentation pass: retro-2000s glossy web-game skin (background + board-face
## textures, navy glass panels, chunky outlined type) plus snappy tweens for
## tile pops, timer panic pulse, toast slide, score count-up, accept flash /
## reject shake, floating bonus tags, category stagger, and round transitions.

signal submit_requested
signal clear_requested
signal backspace_requested
signal shuffle_requested
signal letter_tapped(letter: String)
signal category_chosen(category: int)
signal play_again_requested
signal rules_requested

const LetterTileScene := preload("res://scenes/letter_tile.tscn")
const TEX_BACKGROUND := preload("res://assets/generated/background_texture.png")
const TEX_BOARD_FACE := preload("res://assets/generated/board_face.png")

const CATEGORY_NAMES := [
	"3-LETTER WORDS",
	"4-LETTER WORDS",
	"5+ LETTER WORDS",
	"FULL HOUSE",
	"FLUSH",
	"WILD",
]

const TILE_SIZE := Vector2(76, 76)
const TOAST_TIME := 1.6

# --- Retro palette -----------------------------------------------------------
const COLOR_PANEL_BG := Color(0.07, 0.12, 0.22, 0.82)
const COLOR_PANEL_BORDER := Color(0.42, 0.55, 0.78, 0.85)
const COLOR_ROW_BG := Color(0.05, 0.09, 0.18, 0.62)
const COLOR_ROW_BORDER := Color(0.36, 0.48, 0.7, 0.6)
const COLOR_OUTLINE := Color(0.02, 0.05, 0.12, 0.92)
const COLOR_TEXT := Color(0.96, 0.97, 0.99)
const COLOR_TEXT_SOFT := Color(0.82, 0.88, 0.96)
const COLOR_GOLD := Color(1.0, 0.84, 0.32)
const COLOR_GOLD_SOFT := Color(1.0, 0.88, 0.55)
const COLOR_LOCKED := Color(0.94, 0.4, 0.34)
const COLOR_TIMER_HOT := Color(1.0, 0.42, 0.38)
const COLOR_FLASH_GOLD := Color(1.45, 1.2, 0.45)
const COLOR_SELECT_BG := Color(0.12, 0.22, 0.42)
const COLOR_SELECT_BORDER := Color(0.55, 0.72, 0.95)

# --- Tween timings -----------------------------------------------------------
const ROUND_FADE_PEAK := 0.55
const ROUND_FADE_HALF := 0.15
const TILE_POP_STAGGER := 0.03
const TOTAL_COUNT_TIME := 0.4
const PULSE_TIME := 0.25

@onready var _round_label: Label = %RoundLabel
@onready var _total_label: Label = %TotalLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _live_score_label: Label = %LiveScoreLabel
@onready var _target_label: Label = %TargetLabel
@onready var _category_list: VBoxContainer = %CategoryList
@onready var _current_word_label: Label = %CurrentWordLabel
@onready var _last_word_label: Label = %LastWordLabel
@onready var _words_scroll: ScrollContainer = %WordsScroll
@onready var _words_list: VBoxContainer = %WordsList
@onready var _letter_area: HBoxContainer = %LetterArea
@onready var _category_buttons_box: VBoxContainer = %CategoryButtons
@onready var _category_select_overlay: ColorRect = %CategorySelect
@onready var _final_overlay: ColorRect = %FinalOverlay
@onready var _final_title: Label = %FinalTitle
@onready var _final_history: VBoxContainer = %FinalHistory
@onready var _toast: PanelContainer = %Toast
@onready var _toast_label: Label = %ToastLabel

var _tiles: Array = []
var _category_rows: Array = []
var _category_select_buttons: Array = []
var _veil: ColorRect
var _toast_timer: Timer
var _tweens: Dictionary = {}
var _timer_pulse_tween: Tween
var _timer_pulsing := false
var _total_shown := 0
var _toast_base_y := -1.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_backdrop()
	_build_category_rows()
	_build_category_select_buttons()
	_wire_bottom_buttons()
	_style_static_labels()
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.wait_time = TOAST_TIME
	_toast_timer.timeout.connect(_hide_toast)
	add_child(_toast_timer)
	_toast.visible = false
	_category_select_overlay.visible = false
	_final_overlay.visible = false
	set_current_word("")
	set_last_word("")
	set_time_left(int(ScoreManager.ROUND_TIME))


## --- Backdrop / board face --------------------------------------------------


## Bottom layers: full-bleed background art, glossy blue board face, rounded
## frame, and the round-transition veil (above the layout, below overlays).
func _build_backdrop() -> void:
	var background := TextureRect.new()
	background.name = "Backdrop"
	background.texture = TEX_BACKGROUND
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	move_child(background, 0)

	var board := Panel.new()
	board.name = "BoardFace"
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face := StyleBoxTexture.new()
	face.texture = TEX_BOARD_FACE
	face.set_texture_margin_all(64.0)
	board.add_theme_stylebox_override("panel", face)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.offset_left = 10.0
	board.offset_top = 10.0
	board.offset_right = -10.0
	board.offset_bottom = -10.0
	add_child(board)
	move_child(board, 1)

	var frame := Panel.new()
	frame.name = "BoardFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_style := StyleBoxFlat.new()
	frame_style.draw_center = false
	frame_style.set_corner_radius_all(22)
	frame_style.set_border_width_all(4)
	frame_style.border_color = Color(0.01, 0.05, 0.14, 0.85)
	frame.add_theme_stylebox_override("panel", frame_style)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 6.0
	frame.offset_top = 6.0
	frame.offset_right = -6.0
	frame.offset_bottom = -6.0
	add_child(frame)
	move_child(frame, 2)

	var veil := ColorRect.new()
	veil.name = "RoundVeil"
	veil.color = Color(0.01, 0.03, 0.08, 0.0)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	move_child(veil, 3)
	_veil = veil


## Chunky outlined type everywhere, so labels read over the glossy board.
func _style_static_labels() -> void:
	_style_label(_round_label, 22, COLOR_TEXT, 4)
	_style_label(_total_label, 22, COLOR_GOLD_SOFT, 4)
	_style_label(_timer_label, 48, COLOR_GOLD, 6)
	_style_label(_live_score_label, 20, COLOR_TEXT, 4)
	_style_label(_target_label, 20, COLOR_GOLD_SOFT, 4)
	_style_label(_current_word_label, 50, Color(1.0, 0.97, 0.88), 7)
	_style_label(_last_word_label, 20, COLOR_GOLD_SOFT, 4)
	_style_label(_final_title, 40, COLOR_GOLD, 7)
	_style_label(_toast_label, 24, COLOR_TEXT, 5)
	var select_title := find_child("CategorySelectTitle", true, false) as Label
	if select_title != null:
		_style_label(select_title, 28, COLOR_GOLD, 5)
	_center_pivot_on_resize(_timer_label)
	_center_pivot_on_resize(_last_word_label)


func _style_label(label: Label, font_size: int, color: Color, outline: int) -> void:
	if label == null:
		return
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	label.add_theme_constant_override("outline_size", outline)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.02, 0.08, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 3)
	label.add_theme_constant_override("shadow_outline_size", 2)


func _center_pivot_on_resize(control: Control) -> void:
	if control == null:
		return
	control.pivot_offset = control.size * 0.5
	control.resized.connect(func() -> void:
		control.pivot_offset = control.size * 0.5)


## --- Header / panel setters -------------------------------------------------


func set_round(round_number: int) -> void:
	_round_label.text = "ROUND %d" % round_number


func set_total(total: int) -> void:
	if total == _total_shown:
		_total_label.text = "TOTAL: %d" % total
		return
	if not is_inside_tree():
		_total_shown = total
		_total_label.text = "TOTAL: %d" % total
		return
	var tween := _tw(_total_label)
	tween.tween_method(_show_counting_total, float(_total_shown), float(total),
		TOTAL_COUNT_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _show_counting_total(value: float) -> void:
	_total_shown = int(roundf(value))
	_total_label.text = "TOTAL: %d" % _total_shown


func set_time_left(secs: float) -> void:
	var whole := int(ceilf(maxf(secs, 0.0)))
	_timer_label.text = "%d:%02d" % [whole / 60, whole % 60]
	_update_timer_pulse(whole)


## Gentle ~2Hz pulse + red shift when the clock hits the panic zone.
func _update_timer_pulse(whole: int) -> void:
	var should_pulse := whole <= 10 and whole > 0
	if should_pulse == _timer_pulsing:
		return
	_timer_pulsing = should_pulse
	if _timer_label == null or not _timer_label.is_inside_tree():
		return
	if _timer_pulse_tween != null and _timer_pulse_tween.is_valid():
		_timer_pulse_tween.kill()
	if should_pulse:
		_timer_label.pivot_offset = _timer_label.size * 0.5
		_timer_pulse_tween = create_tween().set_loops()
		_timer_pulse_tween.tween_property(_timer_label, "scale",
			Vector2(1.08, 1.08), PULSE_TIME).set_trans(Tween.TRANS_SINE) \
			.set_ease(Tween.EASE_IN_OUT)
		_timer_pulse_tween.parallel().tween_property(_timer_label, "modulate",
			COLOR_TIMER_HOT, PULSE_TIME).set_trans(Tween.TRANS_SINE) \
			.set_ease(Tween.EASE_IN_OUT)
		_timer_pulse_tween.tween_property(_timer_label, "scale",
			Vector2.ONE, PULSE_TIME).set_trans(Tween.TRANS_SINE) \
			.set_ease(Tween.EASE_IN_OUT)
		_timer_pulse_tween.parallel().tween_property(_timer_label, "modulate",
			Color.WHITE, PULSE_TIME).set_trans(Tween.TRANS_SINE) \
			.set_ease(Tween.EASE_IN_OUT)
	else:
		_timer_label.scale = Vector2.ONE
		_timer_label.modulate = Color.WHITE


func set_score_panel(live_score: int, target: int) -> void:
	_live_score_label.text = "SCORE: %d" % live_score
	_target_label.text = "TARGET: %d" % target


## --- Letters ----------------------------------------------------------------


## Rebuild the 8 tiles from a letters array (e.g. ["A","B","C",...]).
func set_letters(letters: Array) -> void:
	for child in _letter_area.get_children():
		child.queue_free()
	_tiles.clear()
	_play_round_transition()
	for i in range(letters.size()):
		var tile: LetterTile = LetterTileScene.instantiate()
		tile.custom_minimum_size = TILE_SIZE
		tile.set_letter(String(letters[i]))
		tile.tile_tapped.connect(func(tapped: String) -> void: letter_tapped.emit(tapped))
		_letter_area.add_child(tile)
		_tiles.append(tile)
		tile.pop_in(ROUND_FADE_HALF * 0.8 + float(i) * TILE_POP_STAGGER)


## Brief full-board dip to dark at the start of a fresh round.
func _play_round_transition() -> void:
	if _veil == null or not _veil.is_inside_tree():
		return
	var tween := _tw(_veil)
	tween.tween_property(_veil, "color:a", ROUND_FADE_PEAK, ROUND_FADE_HALF) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_veil, "color:a", 0.0, ROUND_FADE_HALF) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## Reorder the 8 tile widgets randomly. Display only - letters themselves are
## unchanged, so the current word's letters stay valid.
func shuffle_tiles() -> void:
	if _tiles.size() < 2:
		return
	var letters: Array = []
	for tile in _tiles:
		letters.append(String(tile.letter))
	letters.shuffle()
	for i in range(_tiles.size()):
		_tiles[i].set_letter(String(letters[i]))


## Dim tiles whose letter is used up in the current word.
## `usage` maps letter -> times that letter is used in the current word
## (missing key = 0). A tile dims when its usage count reaches the number of
## identical letters in the pool.
func set_tile_consumed(usage: Dictionary) -> void:
	var availability := {}
	for tile in _tiles:
		var letter := String(tile.letter)
		availability[letter] = int(availability.get(letter, 0)) + 1
	for tile in _tiles:
		var letter := String(tile.letter)
		var used := int(usage.get(letter, 0))
		tile.set_enabled_tile(used < int(availability.get(letter, 0)))


func deselect_all_tiles() -> void:
	for tile in _tiles:
		tile.deselect()


## Highlight the tiles used by `word` (selected look), consuming the rest.
## Counts the letters the word needs and lights exactly one tile per usage -
## surplus pool letters and non-word letters stay in the resting look.
func mark_word_tiles(word: String) -> void:
	deselect_all_tiles()
	var to_light := {}
	for i in range(word.length()):
		var letter := word[i]
		to_light[letter] = int(to_light.get(letter, 0)) + 1
	for tile in _tiles:
		var letter := String(tile.letter)
		if int(to_light.get(letter, 0)) > 0:
			to_light[letter] = int(to_light[letter]) - 1
			tile.select()
		else:
			tile.deselect()


## --- Word displays ----------------------------------------------------------


func set_current_word(word: String) -> void:
	_current_word_label.text = word if not word.is_empty() else "-"


func set_last_word(text: String) -> void:
	_last_word_label.text = text
	if text.is_empty() or not _last_word_label.is_inside_tree():
		return
	_last_word_label.pivot_offset = _last_word_label.size * 0.5
	_last_word_label.scale = Vector2(1.15, 1.15)
	var tween := _tw(_last_word_label)
	tween.tween_property(_last_word_label, "scale", Vector2.ONE, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Adds a pill row to the submitted-words list and scrolls to it.
func add_submitted_word(word: String, letter_points: int, bonus: int) -> void:
	var text := ""
	if bonus > 0:
		text = "%s  (+%d, +%d bonus)" % [word, letter_points, bonus]
	else:
		text = "%s  (+%d)" % [word, letter_points]
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _make_pill_style())
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", COLOR_TEXT_SOFT)
	label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	label.add_theme_constant_override("outline_size", 3)
	row.add_child(label)
	_words_list.add_child(row)
	if bonus > 0:
		_spawn_bonus_float(bonus)
	_scroll_words_to_bottom.call_deferred()


## Gold "+bonus" tag that floats up from the current word and fades out.
func _spawn_bonus_float(bonus: int) -> void:
	if not is_inside_tree():
		return
	var tag := Label.new()
	tag.text = "+%d" % bonus
	tag.add_theme_font_size_override("font_size", 36)
	tag.add_theme_color_override("font_color", COLOR_GOLD)
	tag.add_theme_color_override("font_outline_color", Color(0.12, 0.05, 0.0, 0.95))
	tag.add_theme_constant_override("outline_size", 6)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.z_index = 30
	add_child(tag)
	var origin := _current_word_label.get_global_rect().get_center()
	tag.reset_size()
	tag.global_position = origin + Vector2(-tag.size.x * 0.5, -tag.size.y)
	var tween := tag.create_tween()
	tween.set_parallel(true)
	tween.tween_property(tag, "position:y", tag.position.y - 56.0, 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(tag, "modulate:a", 0.0, 0.4).set_delay(0.2)
	tween.chain().tween_callback(tag.queue_free)


func clear_word_state() -> void:
	set_current_word("")
	set_last_word("")
	for child in _words_list.get_children():
		child.queue_free()
	_words_scroll.scroll_vertical = 0
	deselect_all_tiles()


func _scroll_words_to_bottom() -> void:
	_words_scroll.scroll_vertical = int(_words_list.size.y)


## --- Category panel / overlays ----------------------------------------------


func set_category_scores(scores: Dictionary, used: Array) -> void:
	for i in range(_category_rows.size()):
		var category: int = ScoreManager.category_ids()[i]
		var points := int(scores.get(category, 0))
		var row: Dictionary = _category_rows[i]
		row["points"].text = str(points)
		var locked: Label = row["locked"]
		locked.visible = used.has(category)
		row["name"].add_theme_color_override(
			"font_color",
			Color(0.5, 0.56, 0.66) if used.has(category) else COLOR_TEXT
		)
		row["points"].add_theme_color_override(
			"font_color",
			Color(0.5, 0.56, 0.66) if used.has(category) else COLOR_GOLD_SOFT
		)


func show_category_select(scores: Dictionary, used: Array) -> void:
	for i in range(_category_select_buttons.size()):
		var category: int = ScoreManager.category_ids()[i]
		var button: Button = _category_select_buttons[i]
		button.text = "%s - %d pts" % [CATEGORY_NAMES[i], int(scores.get(category, 0))]
		button.disabled = used.has(category)
	_category_select_overlay.visible = true
	_animate_category_buttons()


## Overlay fades in while the category cards stagger up from the bottom.
func _animate_category_buttons() -> void:
	if not _category_select_overlay.is_inside_tree():
		return
	_category_select_overlay.modulate.a = 0.0
	var overlay_tween := _tw(_category_select_overlay)
	overlay_tween.tween_property(_category_select_overlay, "modulate:a", 1.0, 0.12)
	for i in range(_category_select_buttons.size()):
		var button: Button = _category_select_buttons[i]
		if button == null or not button.is_inside_tree():
			continue
		button.pivot_offset = Vector2(button.size.x * 0.5, button.size.y)
		button.scale = Vector2(1.0, 0.55)
		button.modulate.a = 0.0
		var tween := _tw(button)
		tween.set_parallel(true)
		tween.tween_property(button, "scale:y", 1.0, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
			.set_delay(float(i) * 0.04)
		tween.tween_property(button, "modulate:a", 1.0, 0.15) \
			.set_delay(float(i) * 0.04)


func hide_category_select() -> void:
	_category_select_overlay.visible = false


func show_final(history: Array, total: int) -> void:
	_final_title.text = "FINAL SCORE: %d" % total
	for child in _final_history.get_children():
		child.queue_free()
	for entry in history:
		var row := HBoxContainer.new()
		var round_label := Label.new()
		round_label.text = "R%d" % int(entry.get("round", 0))
		round_label.custom_minimum_size = Vector2(60, 0)
		var name_label := Label.new()
		name_label.text = _category_display_name(int(entry.get("category", 0)))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var points_label := Label.new()
		var points := int(entry.get("category_points", 0)) + int(entry.get("bonus_points", 0))
		points_label.text = "%d pts" % points
		points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		for label in [round_label, name_label, points_label]:
			_style_label(label, 20, COLOR_TEXT, 3)
		points_label.add_theme_color_override("font_color", COLOR_GOLD_SOFT)
		row.add_child(round_label)
		row.add_child(name_label)
		row.add_child(points_label)
		_final_history.add_child(row)
	_final_overlay.visible = true
	_animate_final_overlay()


## Overlay fades in and the result card springs in from 90% scale.
func _animate_final_overlay() -> void:
	if not _final_overlay.is_inside_tree():
		return
	_final_overlay.modulate.a = 0.0
	var overlay_tween := _tw(_final_overlay)
	overlay_tween.tween_property(_final_overlay, "modulate:a", 1.0, 0.15)
	var panel := _final_overlay.get_node_or_null("FinalPanelBox") as Control
	if panel == null:
		return
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.9, 0.9)
	var tween := _tw(panel)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func hide_final() -> void:
	_final_overlay.visible = false


## Transient accept/reject feedback near the top of the board.
func show_toast(text: String) -> void:
	_toast_label.text = text
	_toast.visible = true
	_animate_toast_in()
	_toast_timer.start()
	if text.begins_with("+"):
		_flash_current_word()
	else:
		_shake_current_word()


## Toast pops up 12px with a quick fade-in; timed fade-out in _hide_toast.
func _animate_toast_in() -> void:
	if not _toast.is_inside_tree():
		return
	if _toast_base_y < 0.0:
		_toast_base_y = _toast.position.y
	var tween := _tw(_toast)
	_toast.modulate.a = 0.0
	_toast.position.y = _toast_base_y + 12.0
	tween.set_parallel(true)
	tween.tween_property(_toast, "modulate:a", 1.0, 0.15)
	tween.tween_property(_toast, "position:y", _toast_base_y, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _hide_toast() -> void:
	if not _toast.visible or not _toast.is_inside_tree():
		return
	var tween := _tw(_toast)
	tween.tween_property(_toast, "modulate:a", 0.0, 0.22)
	tween.tween_callback(func() -> void: _toast.visible = false)


## Accepted: the current-word area flashes gold.
func _flash_current_word() -> void:
	if _current_word_label == null or not _current_word_label.is_inside_tree():
		return
	var tween := _tw(_current_word_label)
	tween.tween_property(_current_word_label, "modulate", COLOR_FLASH_GOLD, 0.08)
	tween.tween_property(_current_word_label, "modulate", Color.WHITE, 0.22)


## Rejected: the current-word label shakes left/right, ~0.2s total.
func _shake_current_word() -> void:
	if _current_word_label == null or not _current_word_label.is_inside_tree():
		return
	var base_x := _current_word_label.position.x
	var tween := _tw(_current_word_label)
	tween.tween_property(_current_word_label, "position:x", base_x + 8.0, 0.05)
	tween.tween_property(_current_word_label, "position:x", base_x - 8.0, 0.05)
	tween.tween_property(_current_word_label, "position:x", base_x + 5.0, 0.05)
	tween.tween_property(_current_word_label, "position:x", base_x, 0.05)


func _category_display_name(category: int) -> String:
	var ids := ScoreManager.category_ids()
	var index := ids.find(category)
	if index >= 0 and index < CATEGORY_NAMES.size():
		return CATEGORY_NAMES[index]
	return "CATEGORY %d" % category


## --- Widget construction ----------------------------------------------------


func _build_category_rows() -> void:
	for child in _category_list.get_children():
		child.queue_free()
	_category_rows.clear()
	var ids := ScoreManager.category_ids()
	for i in range(ids.size()):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var name_label := Label.new()
		name_label.text = CATEGORY_NAMES[i]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 18)
		name_label.add_theme_color_override("font_color", COLOR_TEXT)
		name_label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
		name_label.add_theme_constant_override("outline_size", 3)
		row.add_child(name_label)

		var locked := Label.new()
		locked.text = "LOCKED"
		locked.add_theme_font_size_override("font_size", 14)
		locked.add_theme_color_override("font_color", COLOR_LOCKED)
		locked.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
		locked.add_theme_constant_override("outline_size", 3)
		locked.visible = false
		row.add_child(locked)

		var points_label := Label.new()
		points_label.text = "0"
		points_label.custom_minimum_size = Vector2(48, 0)
		points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		points_label.add_theme_font_size_override("font_size", 18)
		points_label.add_theme_color_override("font_color", COLOR_GOLD_SOFT)
		points_label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
		points_label.add_theme_constant_override("outline_size", 3)
		row.add_child(points_label)

		_category_list.add_child(row)
		_category_rows.append({
			"name": name_label,
			"locked": locked,
			"points": points_label,
		})


func _build_category_select_buttons() -> void:
	for child in _category_buttons_box.get_children():
		child.queue_free()
	_category_select_buttons.clear()
	var ids := ScoreManager.category_ids()
	for i in range(ids.size()):
		var category: int = ids[i]
		var button := Button.new()
		button.text = "%s - 0 pts" % CATEGORY_NAMES[i]
		button.custom_minimum_size = Vector2(0, 72)
		button.add_theme_font_size_override("font_size", 22)
		button.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
		button.add_theme_constant_override("outline_size", 3)

		var normal := _make_choice_style(COLOR_SELECT_BG, COLOR_SELECT_BORDER)
		button.add_theme_stylebox_override("normal", normal)
		var hover := _make_choice_style(COLOR_SELECT_BG.lightened(0.08), COLOR_SELECT_BORDER)
		button.add_theme_stylebox_override("hover", hover)
		var pressed_style := _make_choice_style(Color(0.9, 0.66, 0.14), Color(1.0, 0.92, 0.6))
		button.add_theme_stylebox_override("pressed", pressed_style)
		var disabled_style := _make_choice_style(Color(0.15, 0.17, 0.22), Color(0.28, 0.31, 0.4))
		button.add_theme_stylebox_override("disabled", disabled_style)
		button.add_theme_color_override("font_pressed_color", Color(0.28, 0.17, 0.02))
		button.add_theme_color_override("font_disabled_color", Color(0.52, 0.55, 0.62))
		button.pressed.connect(func() -> void: category_chosen.emit(category))
		_category_buttons_box.add_child(button)
		_category_select_buttons.append(button)


func _make_choice_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_top = 3
	style.border_width_bottom = 4
	style.border_width_left = 2
	style.border_width_right = 2
	style.set_corner_radius_all(16)
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	style.shadow_color = Color(0.0, 0.04, 0.12, 0.4)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 3)
	return style


func _make_pill_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_ROW_BG
	style.border_color = COLOR_ROW_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


func _wire_bottom_buttons() -> void:
	%SubmitButton.pressed.connect(func() -> void: submit_requested.emit())
	%ClearButton.pressed.connect(func() -> void: clear_requested.emit())
	%BackspaceButton.pressed.connect(func() -> void: backspace_requested.emit())
	%ShuffleButton.pressed.connect(func() -> void: shuffle_requested.emit())
	%RulesButton.pressed.connect(func() -> void: rules_requested.emit())
	%PlayAgainButton.pressed.connect(func() -> void: play_again_requested.emit())


## --- Tween helpers ----------------------------------------------------------


## Per-node tween slot: kills whatever was running on this node first.
func _tw(node: Node) -> Tween:
	var existing: Tween = _tweens.get(node)
	if existing != null and existing.is_valid():
		existing.kill()
	var tween := node.create_tween()
	_tweens[node] = tween
	return tween
