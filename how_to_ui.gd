class_name HowToUi
extends Control
## Compact "HOW TO PLAY" modal overlay. Opened from the board's HOW TO PLAY
## button (and never forced on first launch - level 1 starts immediately).
## The owner pauses the game timer before open() and resumes on closed().

signal closed()
signal word_set_changed(tier: String)
signal sound_toggled(enabled: bool)

const COLOR_DIM := Color(0.01, 0.03, 0.08, 0.72)
const COLOR_PANEL_BG := Color(0.07, 0.12, 0.22, 0.97)
const COLOR_PANEL_BORDER := Color(0.42, 0.55, 0.78, 0.9)
const COLOR_OUTLINE := Color(0.02, 0.05, 0.12, 0.92)
const COLOR_TITLE := Color(1.0, 0.88, 0.5)
const COLOR_BODY := Color(0.94, 0.96, 0.99)
const COLOR_KEYS := Color(0.55, 0.95, 0.65)

const BULLETS := [
	"Make words of 3 or more letters from the 8 tiles.",
	"Each letter is usable only as often as it appears.",
	"Reach the TARGET before the timer ends.",
	"Longer words score more: 3=4 · 4=6 · 5=8 · 6=12 · 7=18 · 8=30.",
	"Using all 8 letters completes the level instantly.",
	"Every 5th level is a BONUS round — unscramble the full word in 60s (no penalty for missing).",
	"Type or tap the tiles.",
]

const KEYS_LINE := "ENTER submit · BACKSPACE remove last · ESC clear · SPACE shuffle"

const WORD_SET_EXPLAINER := "COMMON = everyday words · STANDARD = dictionary standard · EXPERT = deep dictionary (US & UK spellings). Takes effect from your next level."

## Tier cycle order for the WORD SET button: COMMON -> STANDARD -> EXPERT -> ...
const TIERS := ["common", "standard", "expert"]

var _scroll: ScrollContainer
var _word_set_button: CircleButton
var _word_set_tier := "common"
var _sound_button: CircleButton
var _sound_on := true


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


## Show the how-to and scroll back to the top.
func open() -> void:
	visible = true
	if _scroll != null:
		_scroll.scroll_vertical = 0
		_scroll.set_deferred("scroll_vertical", 0)


## Sync the cycler with the live dictionary tier (no signal emitted - the
## button must mirror WordDatabase, not drive it).
func set_word_set(tier: String) -> void:
	_word_set_tier = String(tier).to_lower() if TIERS.has(String(tier).to_lower()) else "common"
	if _word_set_button != null:
		_word_set_button.text = _word_set_tier.to_upper()


## Hide the overlay and tell the caller to resume.
func close() -> void:
	visible = false
	closed.emit()


## Mirror the live sound state onto the toggle. Safe before the UI is built -
## the flag is stored and the button (created with it) reflects it later.
func set_sound(on: bool) -> void:
	_sound_on = on
	if _sound_button != null:
		_sound_button.text = "SOUND ON" if on else "SOUND OFF"
		_sound_button.accent = "gold" if on else "blue"


## Flip the stored state and announce the new one; the owner applies + persists.
func _on_sound_pressed() -> void:
	var enabled := not _sound_on
	set_sound(enabled)
	sound_toggled.emit(enabled)


## Cycle COMMON -> STANDARD -> EXPERT -> COMMON and announce the requested set.
func _on_word_set_pressed() -> void:
	var next: String = TIERS[(TIERS.find(_word_set_tier) + 1) % TIERS.size()]
	set_word_set(next)
	word_set_changed.emit(next)


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = COLOR_DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 0.06
	panel.anchor_top = 0.1
	panel.anchor_right = 0.94
	panel.anchor_bottom = 0.9
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)

	var layout := VBoxContainer.new()
	layout.name = "Layout"
	layout.add_theme_constant_override("separation", 10)
	panel.add_child(layout)

	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "HOW TO PLAY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", COLOR_TITLE)
	title.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	title.add_theme_constant_override("outline_size", 5)
	layout.add_child(title)

	var divider := ColorRect.new()
	divider.color = COLOR_TITLE
	divider.custom_minimum_size = Vector2(0.0, 2.0)
	layout.add_child(divider)

	_scroll = ScrollContainer.new()
	_scroll.name = "RulesScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(_scroll)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	_scroll.add_child(content)

	for item in BULLETS:
		_add_bullet(content, "•  " + String(item), COLOR_BODY)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 4.0)
	content.add_child(gap)
	_add_bullet(content, KEYS_LINE, COLOR_KEYS)

	# WORD SET row: stays below the scroll so it is visible without scrolling.
	var word_set_row := HBoxContainer.new()
	word_set_row.name = "WordSetRow"
	word_set_row.add_theme_constant_override("separation", 14)
	layout.add_child(word_set_row)

	var word_set_label := Label.new()
	word_set_label.name = "WordSetLabel"
	word_set_label.text = "WORD SET"
	word_set_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	word_set_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	word_set_label.add_theme_font_size_override("font_size", 24)
	word_set_label.add_theme_color_override("font_color", COLOR_TITLE)
	word_set_label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	word_set_label.add_theme_constant_override("outline_size", 4)
	word_set_row.add_child(word_set_label)

	_word_set_button = CircleButton.new()
	_word_set_button.name = "WordSetButton"
	_word_set_button.accent = "gold"
	_word_set_button.text = _word_set_tier.to_upper()
	_word_set_button.custom_minimum_size = Vector2(170, 56)
	_word_set_button.add_theme_font_size_override("font_size", 20)
	_word_set_button.pressed.connect(_on_word_set_pressed)
	word_set_row.add_child(_word_set_button)

	# SOUND toggle sits beside the WORD SET row controls.
	_sound_button = CircleButton.new()
	_sound_button.name = "SoundButton"
	_sound_button.accent = "gold" if _sound_on else "blue"
	_sound_button.text = "SOUND ON" if _sound_on else "SOUND OFF"
	_sound_button.custom_minimum_size = Vector2(170, 56)
	_sound_button.add_theme_font_size_override("font_size", 20)
	_sound_button.pressed.connect(_on_sound_pressed)
	word_set_row.add_child(_sound_button)

	var word_set_note := Label.new()
	word_set_note.name = "WordSetNote"
	word_set_note.text = WORD_SET_EXPLAINER
	word_set_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	word_set_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	word_set_note.add_theme_font_size_override("font_size", 18)
	word_set_note.add_theme_color_override("font_color", COLOR_BODY)
	word_set_note.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	word_set_note.add_theme_constant_override("outline_size", 3)
	layout.add_child(word_set_note)

	var button_row := HBoxContainer.new()
	button_row.name = "ButtonRow"
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 16)
	layout.add_child(button_row)

	var back := CircleButton.new()
	back.name = "BackButton"
	back.accent = "blue"
	back.text = "BACK"
	back.custom_minimum_size = Vector2(170, 70)
	back.add_theme_font_size_override("font_size", 24)
	back.pressed.connect(close)
	button_row.add_child(back)

	var got_it := CircleButton.new()
	got_it.name = "GotItButton"
	got_it.accent = "gold"
	got_it.text = "GOT IT"
	got_it.custom_minimum_size = Vector2(240, 70)
	got_it.add_theme_font_size_override("font_size", 24)
	got_it.pressed.connect(close)
	button_row.add_child(got_it)


func _add_bullet(parent: Control, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	label.add_theme_constant_override("outline_size", 4)
	parent.add_child(label)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL_BG
	style.border_color = COLOR_PANEL_BORDER
	style.set_corner_radius_all(22)
	style.set_border_width_all(2)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 26.0
	style.content_margin_bottom = 22.0
	style.shadow_color = Color(0.0, 0.02, 0.08, 0.5)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 5)
	return style
