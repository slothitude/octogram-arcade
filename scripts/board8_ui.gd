class_name Board8
extends Control
## Play screen for Eight Letters: header (title / level / timer), score + target
## with a chunky progress bar, the current word, the found-words list, 8 letter
## tiles, bottom controls, toast feedback, the level-up celebration and the
## game-over reveal. Display only - game state lives in GameEight and is driven
## by main.gd through the setters below.

signal submit_requested
signal clear_requested
signal backspace_requested
signal shuffle_requested
signal letter_tapped(letter: String)
signal how_to_requested
signal play_again_requested
signal menu_requested

const LetterTileScene := preload("res://scenes/letter_tile.tscn")
const TEX_BACKGROUND := preload("res://assets/generated/background_texture.png")
const TEX_BOARD_FACE := preload("res://assets/generated/board_face.png")

const TITLE_TEXT := "EIGHT LETTERS"
const BONUS_TITLE := "BONUS ROUND — unscramble the 8-letter word!"

const TILE_SIZE := Vector2(76, 76)
const TOAST_TIME := 1.2
const SHAKE_OFFSET := 8.0
const TILE_POP_BASE := 0.05
const TILE_POP_STAGGER := 0.03
const BAR_FILL_TIME := 0.18
const BAR_GHOST_TIME := 0.5
const PULSE_TIME := 0.25

# --- Retro palette (same skin as the octogram arena build) -------------------
const COLOR_PANEL_BORDER := Color(0.42, 0.55, 0.78, 0.85)
const COLOR_ROW_BG := Color(0.05, 0.09, 0.18, 0.62)
const COLOR_ROW_BORDER := Color(0.36, 0.48, 0.7, 0.6)
const COLOR_OUTLINE := Color(0.02, 0.05, 0.12, 0.92)
const COLOR_TEXT := Color(0.96, 0.97, 0.99)
const COLOR_TEXT_SOFT := Color(0.82, 0.88, 0.96)
const COLOR_GOLD := Color(1.0, 0.84, 0.32)
const COLOR_GOLD_SOFT := Color(1.0, 0.88, 0.55)
const COLOR_PURPLE := Color(0.78, 0.55, 1.0)
const COLOR_TIMER_HOT := Color(1.0, 0.42, 0.38)
const COLOR_FLASH_GOLD := Color(1.45, 1.2, 0.45)
const COLOR_BAR_GHOST := Color(1.0, 1.0, 1.0, 0.26)

@onready var _title_label: Label = %TitleLabel
@onready var _level_label: Label = %LevelLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _score_panel: PanelContainer = %ScorePanel
@onready var _score_label: Label = %ScoreLabel
@onready var _target_label: Label = %TargetLabel
@onready var _bar_slot: Control = %BarSlot
@onready var _current_word_label: Label = %CurrentWordLabel
@onready var _words_counter: Label = %WordsCounter
@onready var _words_scroll: ScrollContainer = %WordsScroll
@onready var _words_list: VBoxContainer = %WordsList
@onready var _letter_area: HBoxContainer = %LetterArea
@onready var _level_up_label: Label = %LevelUpLabel
@onready var _toast: PanelContainer = %Toast
@onready var _toast_label: Label = %ToastLabel
@onready var _reveal: RevealUi = %RevealOverlay

## Sound effects, injected by main (null-safe: the board stays silent when no
## manager is attached, e.g. in bare-scene tooling).
var sfx: SfxManager = null

var _tiles: Array = []
var _bar_track: Panel
var _bar_clip: Control
var _bar_ghost: Panel
var _bar_fill: Panel
var _fraction := 0.0
var _shown_score := -1
var _shown_word_length := 0
var _bonus_mode := false
var _found_count := 0
var _toast_timer: Timer
var _tweens: Dictionary = {}
var _timer_pulse_tween: Tween
var _timer_pulsing := false
var _toast_base_y := -1.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_backdrop()
	_build_progress_bar()
	_style_static_labels()
	_wire_bottom_buttons()
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.wait_time = TOAST_TIME
	_toast_timer.timeout.connect(_hide_toast)
	add_child(_toast_timer)
	_toast.visible = false
	_level_up_label.visible = false
	_reveal.play_again_requested.connect(_on_reveal_play_again)
	_reveal.menu_requested.connect(menu_requested.emit)
	set_current_word("")
	set_found_count(0)
	set_time_left(Rules8.LEVEL_TIME)


## --- Backdrop / board face (same layers as the arena board) -----------------


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


## Chunky outlined type everywhere so labels read over the glossy board.
func _style_static_labels() -> void:
	_style_label(_title_label, 44, COLOR_GOLD, 6)
	_style_label(_level_label, 24, COLOR_TEXT, 4)
	_style_label(_timer_label, 52, COLOR_GOLD, 6)
	_style_label(_score_label, 24, COLOR_TEXT, 4)
	_style_label(_target_label, 24, COLOR_GOLD_SOFT, 4)
	_style_label(_current_word_label, 50, Color(1.0, 0.97, 0.88), 7)
	_style_label(_words_counter, 18, COLOR_TEXT_SOFT, 3)
	_style_label(_level_up_label, 56, COLOR_GOLD, 8)
	_style_label(_toast_label, 22, COLOR_TEXT, 5)
	_center_pivot_on_resize(_timer_label)
	_center_pivot_on_resize(_current_word_label)
	_center_pivot_on_resize(_level_up_label)


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


## --- Header / score setters --------------------------------------------------


func set_level(level: int) -> void:
	_level_label.text = "LEVEL %d" % level


## mm:ss countdown; pulses red once the clock enters the panic zone.
func set_time_left(secs: float) -> void:
	var whole := int(ceilf(maxf(secs, 0.0)))
	_timer_label.text = "%d:%02d" % [floori(whole / 60.0), whole % 60]
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


## Instant numbers (fast tally law - no slow counting) + a quick pop on gain.
func set_scores(round_score: int, target: int) -> void:
	_score_label.text = "SCORE %d" % round_score
	_target_label.text = "TARGET %d" % target
	if _shown_score >= 0 and round_score > _shown_score:
		_pop(_score_label)
	_shown_score = round_score
	_fraction = 0.0 if target <= 0 else clampf(float(round_score) / float(target), 0.0, 1.0)
	_apply_bar(false)


func _build_progress_bar() -> void:
	_bar_track = Panel.new()
	_bar_track.name = "ScoreBarTrack"
	_bar_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track_style := StyleBoxFlat.new()
	track_style.bg_color = COLOR_ROW_BG
	track_style.border_color = COLOR_PANEL_BORDER
	track_style.set_border_width_all(2)
	track_style.set_corner_radius_all(12)
	_bar_track.add_theme_stylebox_override("panel", track_style)
	_bar_slot.add_child(_bar_track)
	_bar_track.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_bar_clip = Control.new()
	_bar_clip.name = "ScoreBarClip"
	_bar_clip.clip_contents = true
	_bar_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_track.add_child(_bar_clip)
	_bar_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar_clip.offset_left = 4.0
	_bar_clip.offset_top = 4.0
	_bar_clip.offset_right = -4.0
	_bar_clip.offset_bottom = -4.0
	_bar_clip.resized.connect(func() -> void: _apply_bar(true))

	# Ghost trail first (behind the fill), then the gold fill on top.
	_bar_ghost = _make_bar_fill(COLOR_BAR_GHOST)
	_bar_ghost.name = "ScoreBarGhost"
	_bar_fill = _make_bar_fill(COLOR_GOLD)
	_bar_fill.name = "ScoreBarFill"
	_apply_bar(true)


func _make_bar_fill(color: Color) -> Panel:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(8)
	if color == COLOR_GOLD:
		style.border_color = Color(1.0, 0.95, 0.7, 0.9)
		style.border_width_top = 2
	panel.add_theme_stylebox_override("panel", style)
	_bar_clip.add_child(panel)
	panel.position = Vector2.ZERO
	panel.size = Vector2(0, 0)
	return panel


## Sizes the fill (snappy) and the ghost trail (lags behind, HP-bar style).
func _apply_bar(instant: bool) -> void:
	if _bar_clip == null or _bar_fill == null:
		return
	var width := _bar_clip.size.x
	if width <= 0.0:
		return
	var target_width := width * _fraction
	if instant or not is_inside_tree():
		_kill_bar_tweens()
		_bar_fill.size = Vector2(target_width, _bar_clip.size.y)
		_bar_ghost.size = Vector2(target_width, _bar_clip.size.y)
		return
	var fill_tween := _tw(_bar_fill)
	fill_tween.tween_property(_bar_fill, "size:x", target_width, BAR_FILL_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var ghost_tween := _tw(_bar_ghost)
	ghost_tween.tween_property(_bar_ghost, "size:x", target_width, BAR_GHOST_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).set_delay(0.08)


func _kill_bar_tweens() -> void:
	for panel in [_bar_fill, _bar_ghost]:
		var existing: Tween = _tweens.get(panel)
		if existing != null and existing.is_valid():
			existing.kill()


## Bonus rounds trade the score chase for the anagram hunt: header copy swaps,
## the progress bar hides and the timer runs purple instead of gold.
func set_bonus_mode(on: bool) -> void:
	_bonus_mode = on
	if on:
		_play_sfx("bonus")
	_title_label.text = BONUS_TITLE if on else TITLE_TEXT
	_title_label.add_theme_font_size_override("font_size", 30 if on else 44)
	_score_panel.visible = not on
	_timer_label.add_theme_color_override("font_color", COLOR_PURPLE if on else COLOR_GOLD)


## --- Letters ----------------------------------------------------------------


## Rebuild the 8 tiles from a letters array (also used for SPACE shuffles,
## which are pure display reorders - the pool letters themselves never change).
func set_letters(letters: Array) -> void:
	for child in _letter_area.get_children():
		child.queue_free()
	_tiles.clear()
	for i in range(letters.size()):
		var tile: LetterTile = LetterTileScene.instantiate()
		tile.custom_minimum_size = TILE_SIZE
		tile.set_letter(String(letters[i]))
		tile.tile_tapped.connect(func(tapped: String) -> void: letter_tapped.emit(tapped))
		_letter_area.add_child(tile)
		_tiles.append(tile)
		tile.pop_in(TILE_POP_BASE + float(i) * TILE_POP_STAGGER)
	_mark_word_tiles(_current_word_label.text if _shown_word_length > 0 else "")


## Current word: letters pop in as typed, tiles light up / dim to match.
func set_current_word(word: String) -> void:
	var grew := word.length() > _shown_word_length
	_shown_word_length = word.length()
	_current_word_label.text = word if not word.is_empty() else "-"
	if grew:
		_pop(_current_word_label)
	_mark_word_tiles(word)


## Select one tile per letter usage; dim tiles whose letter is used up.
func _mark_word_tiles(word: String) -> void:
	if _tiles.is_empty():
		return
	var availability := {}
	for tile in _tiles:
		var letter := String(tile.letter)
		availability[letter] = int(availability.get(letter, 0)) + 1
	var usage := {}
	for i in range(word.length()):
		var letter: String = word[i]
		usage[letter] = int(usage.get(letter, 0)) + 1
	for tile in _tiles:
		var letter := String(tile.letter)
		var used := int(usage.get(letter, 0))
		if used > 0:
			usage[letter] = used - 1
			tile.select()
		else:
			tile.deselect()
		tile.set_enabled_tile(int(usage.get(letter, 0)) < int(availability.get(letter, 0)))


## --- Found words -------------------------------------------------------------


func set_found_count(count: int) -> void:
	_found_count = count
	_words_counter.text = "WORDS: %d" % count


## Adds a pill row for an accepted word and scrolls the list to it.
func add_found_word(word: String) -> void:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _make_pill_style())
	var label := Label.new()
	label.name = "WordPillLabel"
	label.text = String(word)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", COLOR_GOLD_SOFT)
	label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	label.add_theme_constant_override("outline_size", 3)
	row.add_child(label)
	row.modulate.a = 0.0
	_words_list.add_child(row)
	var tween := row.create_tween()
	tween.tween_property(row, "modulate:a", 1.0, 0.12)
	set_found_count(_found_count + 1)
	_scroll_words_to_bottom.call_deferred()


func clear_word_state() -> void:
	set_current_word("")
	set_found_count(0)
	for child in _words_list.get_children():
		child.queue_free()
	_words_scroll.scroll_vertical = 0


func _scroll_words_to_bottom() -> void:
	_words_scroll.scroll_vertical = int(_words_list.size.y)


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


## --- Toast (reject reasons) --------------------------------------------------


## Transient red-tinted feedback; reject texts shake the current word, "+" texts
## flash it gold instead. Reject toasts also play the reject blip - celebratory
## or informational toasts pass false to stay silent.
func show_toast(text: String, is_reject: bool = true) -> void:
	if is_reject:
		_play_sfx("reject")
	_toast_label.text = text
	_toast.visible = true
	_animate_toast_in()
	_toast_timer.start()
	if text.begins_with("+"):
		_flash_current_word()
	else:
		_shake_current_word()


func _animate_toast_in() -> void:
	if not _toast.is_inside_tree():
		return
	if _toast_base_y < 0.0:
		_toast_base_y = _toast.position.y
	var tween := _tw(_toast)
	_toast.modulate.a = 0.0
	_toast.position.y = _toast_base_y + 12.0
	tween.set_parallel(true)
	tween.tween_property(_toast, "modulate:a", 1.0, 0.12)
	tween.tween_property(_toast, "position:y", _toast_base_y, 0.15) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _hide_toast() -> void:
	if not _toast.visible or not _toast.is_inside_tree():
		return
	var tween := _tw(_toast)
	tween.tween_property(_toast, "modulate:a", 0.0, 0.18)
	tween.tween_callback(func() -> void: _toast.visible = false)


## Rejected: the current-word label shakes left/right, ~0.2s total.
func _shake_current_word() -> void:
	if _current_word_label == null or not _current_word_label.is_inside_tree():
		return
	var base_x := _current_word_label.position.x
	var tween := _tw(_current_word_label)
	tween.tween_property(_current_word_label, "position:x", base_x + SHAKE_OFFSET, 0.05)
	tween.tween_property(_current_word_label, "position:x", base_x - SHAKE_OFFSET, 0.05)
	tween.tween_property(_current_word_label, "position:x", base_x + 5.0, 0.05)
	tween.tween_property(_current_word_label, "position:x", base_x, 0.05)


## Accepted: the current-word area flashes gold.
func _flash_current_word() -> void:
	if _current_word_label == null or not _current_word_label.is_inside_tree():
		return
	var tween := _tw(_current_word_label)
	tween.tween_property(_current_word_label, "modulate", COLOR_FLASH_GOLD, 0.08)
	tween.tween_property(_current_word_label, "modulate", Color.WHITE, 0.22)


## --- Level-up celebration ----------------------------------------------------


## Quick gold confetti burst + "LEVEL UP!" pop (fast, no slow counting).
func celebrate_level(points: int) -> void:
	_play_sfx("levelup")
	_level_up_label.text = "LEVEL UP!"
	_pop(_level_up_label)
	_show_level_up()
	_burst_confetti()


func _show_level_up() -> void:
	if not _level_up_label.is_inside_tree():
		return
	_level_up_label.visible = true
	_level_up_label.pivot_offset = _level_up_label.size * 0.5
	_level_up_label.scale = Vector2(0.6, 0.6)
	_level_up_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var tween := _tw(_level_up_label)
	tween.tween_property(_level_up_label, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_level_up_label, "modulate:a", 1.0, 0.12)
	tween.tween_interval(0.3)
	tween.tween_property(_level_up_label, "modulate:a", 0.0, 0.16)
	tween.tween_callback(func() -> void: _level_up_label.visible = false)


## 12 small gold-family squares exploding outward from the board centre, 0.5s.
func _burst_confetti() -> void:
	if not is_inside_tree():
		return
	var origin := size * 0.5
	var palette := [COLOR_GOLD, COLOR_GOLD_SOFT, Color(1.0, 0.95, 0.75), Color(0.95, 0.72, 0.2)]
	for i in range(12):
		var bit := ColorRect.new()
		bit.name = "Confetti%d" % i
		bit.size = Vector2(10, 14)
		bit.color = palette[i % palette.size()]
		bit.pivot_offset = bit.size * 0.5
		bit.rotation = randf_range(0.0, TAU)
		bit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bit.z_index = 40
		add_child(bit)
		bit.position = origin - bit.size * 0.5
		var angle := randf_range(0.0, TAU)
		var distance := randf_range(90.0, 240.0)
		var target := bit.position + Vector2(cos(angle), sin(angle)) * distance
		var tween := bit.create_tween()
		tween.set_parallel(true)
		tween.tween_property(bit, "position", target, 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(bit, "rotation", bit.rotation + randf_range(-2.0, 2.0), 0.5)
		tween.tween_property(bit, "modulate:a", 0.0, 0.35).set_delay(0.15)
		tween.chain().tween_callback(bit.queue_free)


## --- Reveal ------------------------------------------------------------------


func show_reveal(found: Array, possible: Array, total: int, level: int,
		best_score: int, best_level: int) -> void:
	_play_sfx("gameover")
	_reveal.show_reveal(found, possible, total, level, best_score, best_level)


func hide_reveal() -> void:
	_reveal.hide_reveal()


## --- Sound hooks (sfx injected by main; every call is null-safe) --------------


func _play_sfx(sound_name: String) -> void:
	if sfx != null:
		sfx.play(sound_name)


## PLAY AGAIN is the board's own button, so its click lives here (main owns the
## submit path and the word-accept sounds).
func _on_reveal_play_again() -> void:
	_play_sfx("click")
	play_again_requested.emit()


## --- Widget wiring -----------------------------------------------------------


func _wire_bottom_buttons() -> void:
	%SubmitButton.pressed.connect(func() -> void: submit_requested.emit())
	%ClearButton.pressed.connect(func() -> void: clear_requested.emit())
	%DelButton.pressed.connect(func() -> void: backspace_requested.emit())
	%ShuffleButton.pressed.connect(func() -> void: shuffle_requested.emit())
	%HowToButton.pressed.connect(func() -> void: how_to_requested.emit())


## Quick scale pop used for score gains, typed letters and the LEVEL UP banner.
func _pop(label: Label) -> void:
	if label == null or not label.is_inside_tree():
		return
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2(1.18, 1.18)
	var tween := _tw(label)
	tween.tween_property(label, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Per-node tween slot: kills whatever was running on this node first.
func _tw(node: Node) -> Tween:
	var existing: Tween = _tweens.get(node)
	if existing != null and existing.is_valid():
		existing.kill()
	var tween := node.create_tween()
	_tweens[node] = tween
	return tween
