class_name TutorialScreen
extends Control
## Full-screen "How to play" modal overlay.
## The owning screen preloads this scene, adds it as a child, calls open(),
## and connects to closed() to know when the player dismissed it.

signal closed()
signal word_set_changed(tier: String)
signal sound_toggled(enabled: bool)

const COLOR_DIM := Color(0.01, 0.03, 0.08, 0.72)
const COLOR_PANEL_BG := Color(0.07, 0.12, 0.22, 0.97)
const COLOR_PANEL_BORDER := Color(0.42, 0.55, 0.78, 0.9)
const COLOR_OUTLINE := Color(0.02, 0.05, 0.12, 0.92)
const COLOR_TITLE := Color(1.0, 0.88, 0.5)
const COLOR_HEADER := Color(1.0, 0.84, 0.32)
const COLOR_BODY := Color(0.94, 0.96, 0.99)
const COLOR_FOOTER := Color(0.85, 0.9, 0.97)
const COLOR_QUICK_HEADER := Color(0.55, 0.95, 0.65)
const COLOR_BUTTON_BG := Color(0.9, 0.66, 0.14)
const COLOR_BUTTON_HOVER := Color(0.98, 0.74, 0.22)
const COLOR_BUTTON_PRESSED := Color(0.76, 0.53, 0.09)
const COLOR_BUTTON_TEXT := Color(0.28, 0.17, 0.02)

const FONT_SIZE_TITLE := 52
const FONT_SIZE_SUBTITLE := 30
const FONT_SIZE_HEADER := 40
const FONT_SIZE_BODY := 28
const FONT_SIZE_BUTTON := 36

const BUTTON_MIN_HEIGHT := 76.0
const WORD_SET_BUTTON_MIN_HEIGHT := 56.0
const FONT_SIZE_SMALL_BUTTON := 28
const PANEL_WIDTH_ANCHOR := 0.04  # 4% inset each side -> 92% width
const PANEL_HEIGHT_ANCHOR := 0.02

const RULES_TITLE := "OCTOGRAM ARCADE"
const RULES_SUBTITLE := "HOW TO PLAY"
const RULES_FOOTER := "Good luck — Tash"
const RULES_BUTTON_TEXT := "LET'S PLAY"

const WORD_SET_HEADER := "WORD SET"
const WORD_SET_TIERS := ["COMMON", "STANDARD", "EXPERT"]
const WORD_SET_EXPLAINER := "COMMON = everyday words · STANDARD = full dictionary standard · EXPERT = deep dictionary (US & UK spellings)"

const SOUND_ON_TEXT := "SOUND ON"
const SOUND_OFF_TEXT := "SOUND OFF"

const QUICK_START_HEADER := "QUICK START"
const QUICK_START_ITEMS := [
	"Three games: Word Poker · Campaign · Eight Letters — pick a mode from the menu.",
	"Make words from the 8 letters — 3 letters or more.",
	"You have 90 seconds per round.",
	"When time's up, pick ONE category to bank its points.",
]

const RULE_SECTIONS := [
	{
		"header": "1. THE BASICS",
		"items": [
			"Each of the 6 rounds gives you 8 letters and 90 seconds.",
			"Build words of 3 or more letters — type on the keyboard or tap the tiles.",
			"Each letter can be used only as many times as it appears. Letters are reusable across DIFFERENT words.",
			"The same word can't be scored twice in one round.",
		],
	},
	{
		"header": "2. SCORING — pick ONE category per round",
		"items": [
			"When the timer hits zero, choose ONE scoring category. Its points go to your TOTAL SCORE and it locks for the rest of the game.",
			"3-LETTER WORDS: 4 points each",
			"4-LETTER WORDS: 6 points each",
			"5+ LETTER WORDS: 8 points each",
			"FULL HOUSE: 50 points for 15+ words, 150 points for 25+ words",
			"FLUSH: 10 x the number of words starting with your most common first letter",
			"WILD: 1/2/5/7/10/15 points per word of length 3/4/5/6/7/8",
		],
	},
	{
		"header": "CAMPAIGN — the magical adventure",
		"items": [
			"In CAMPAIGN you are the Octogram: words are spells, letters are mana glyphs.",
			"Your timer is your LIFE — enemies eat your seconds. Every word you cast jams their next attack.",
			"7-letter words CRIT (x2) and using all 8 letters MEGA-CRITs (x3).",
			"Chain words within 5 seconds to build your COMBO up to x2.",
			"Win gold and XP, spend them in the Arcane Wordshop, and beat the Lexicon Leech in zone 5.",
			"Lost a battle? Just retry — you always keep your XP and gold.",
		],
	},
	{
		"header": "3. BONUSES (added immediately)",
		"items": [
			"7-letter word: +50",
			"Using all 8 letters: +75",
			"Finishing a round: +10",
		],
	},
	{
		"header": "4. THE PANELS",
		"items": [
			"SCORE shows the best category value you have right now.",
			"TARGET shows the total of all six categories — your round potential.",
			"All six category values update live while you play.",
		],
	},
]

var _scroll: ScrollContainer
var _word_set_button: Button
var _word_set_tier := "COMMON"
var _sound_button: Button
var _sound_on := true


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


## Show the tutorial and scroll back to the top.
func open() -> void:
	visible = true
	if _scroll != null:
		_scroll.scroll_vertical = 0
		_scroll.set_deferred("scroll_vertical", 0)


## Hide the tutorial and tell the caller it is done.
func close() -> void:
	visible = false
	closed.emit()


## Sync the WORD SET cycler (and label) with the live dictionary. Accepts a tier
## name ("COMMON"/"STANDARD"/"EXPERT", case-insensitive); a bogus tier warns and
## leaves the label untouched. Emits word_set_changed only when the tier actually
## flips, so the initial sync never triggers a redundant save.
func set_word_set(tier: String) -> void:
	var key := tier.strip_edges().to_upper()
	if not WORD_SET_TIERS.has(key):
		push_warning("TutorialScreen: unknown word tier '%s' (expected COMMON/STANDARD/EXPERT)" % tier)
		return
	var changed := key != _word_set_tier
	_word_set_tier = key
	if _word_set_button != null:
		_word_set_button.text = key
	if changed:
		word_set_changed.emit(key)


## Press cycles the cycler COMMON -> STANDARD -> EXPERT -> COMMON.
func _on_word_set_pressed() -> void:
	var next: String = WORD_SET_TIERS[(WORD_SET_TIERS.find(_word_set_tier) + 1) % WORD_SET_TIERS.size()]
	set_word_set(next)


## Sync the SOUND pill with the persisted setting. Never emits sound_toggled —
## only the player's tap does (same contract as set_word_set).
func set_sound(on: bool) -> void:
	_sound_on = bool(on)
	if _sound_button != null:
		_sound_button.text = SOUND_ON_TEXT if _sound_on else SOUND_OFF_TEXT


## Tap flips the pill and tells the owner, which mutes SfxManager and persists.
func _on_sound_pressed() -> void:
	set_sound(not _sound_on)
	sound_toggled.emit(_sound_on)


## Compact WORD SET row: COMMON/STANDARD/EXPERT candy-pill cycler plus a one-line
## explainer.
func _add_word_set_row(parent: Control) -> void:
	_add_label(parent, WORD_SET_HEADER, FONT_SIZE_HEADER, COLOR_QUICK_HEADER, false)
	_add_divider(parent)

	var row := HBoxContainer.new()
	row.name = "WordSetRow"
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var toggle := Button.new()
	toggle.name = "WordSetButton"
	toggle.text = _word_set_tier
	toggle.custom_minimum_size = Vector2(0.0, WORD_SET_BUTTON_MIN_HEIGHT)
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle.add_theme_font_size_override("font_size", FONT_SIZE_SMALL_BUTTON)
	toggle.add_theme_color_override("font_color", COLOR_BUTTON_TEXT)
	toggle.add_theme_color_override("font_hover_color", COLOR_BUTTON_TEXT)
	toggle.add_theme_color_override("font_pressed_color", COLOR_BUTTON_TEXT)
	toggle.add_theme_color_override("font_focus_color", COLOR_BUTTON_TEXT)
	toggle.add_theme_stylebox_override("normal", _button_style(COLOR_BUTTON_BG))
	toggle.add_theme_stylebox_override("hover", _button_style(COLOR_BUTTON_HOVER))
	var pressed_style := _button_style(COLOR_BUTTON_PRESSED)
	pressed_style.content_margin_top = 9.0
	pressed_style.content_margin_bottom = 5.0
	toggle.add_theme_stylebox_override("pressed", pressed_style)
	toggle.pressed.connect(_on_word_set_pressed)
	row.add_child(toggle)
	_word_set_button = toggle

	# SOUND ON/OFF pill, riding beside the WORD SET cycler.
	var sound := Button.new()
	sound.name = "SoundButton"
	sound.text = SOUND_ON_TEXT if _sound_on else SOUND_OFF_TEXT
	sound.custom_minimum_size = Vector2(0.0, WORD_SET_BUTTON_MIN_HEIGHT)
	sound.add_theme_font_size_override("font_size", FONT_SIZE_SMALL_BUTTON)
	sound.add_theme_color_override("font_color", COLOR_BUTTON_TEXT)
	sound.add_theme_color_override("font_hover_color", COLOR_BUTTON_TEXT)
	sound.add_theme_color_override("font_pressed_color", COLOR_BUTTON_TEXT)
	sound.add_theme_color_override("font_focus_color", COLOR_BUTTON_TEXT)
	sound.add_theme_stylebox_override("normal", _button_style(Color(0.14, 0.26, 0.52)))
	sound.add_theme_stylebox_override("hover", _button_style(Color(0.18, 0.32, 0.62)))
	sound.add_theme_stylebox_override("pressed", _button_style(Color(0.10, 0.19, 0.40)))
	sound.pressed.connect(_on_sound_pressed)
	row.add_child(sound)
	_sound_button = sound

	_add_label(parent, WORD_SET_EXPLAINER, FONT_SIZE_BODY, COLOR_BODY, false)
	_add_gap(parent, 14.0)


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = COLOR_DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = PANEL_WIDTH_ANCHOR
	panel.anchor_top = PANEL_HEIGHT_ANCHOR
	panel.anchor_right = 1.0 - PANEL_WIDTH_ANCHOR
	panel.anchor_bottom = 1.0 - PANEL_HEIGHT_ANCHOR
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)

	var layout := VBoxContainer.new()
	layout.name = "Layout"
	layout.add_theme_constant_override("separation", 8)
	panel.add_child(layout)

	_add_label(layout, RULES_TITLE, FONT_SIZE_TITLE, COLOR_TITLE, true)
	_add_label(layout, RULES_SUBTITLE, FONT_SIZE_SUBTITLE, COLOR_HEADER, true)
	_add_gap(layout, 8.0)

	_scroll = ScrollContainer.new()
	_scroll.name = "RulesScroll"
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	layout.add_child(_scroll)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	_scroll.add_child(content)

	_add_word_set_row(content)

	_add_label(content, QUICK_START_HEADER, FONT_SIZE_HEADER, COLOR_QUICK_HEADER, false)
	_add_divider(content)
	for item in QUICK_START_ITEMS:
		_add_label(content, "•  " + item, FONT_SIZE_BODY, COLOR_BODY, false)
	_add_gap(content, 14.0)

	for section in RULE_SECTIONS:
		_add_label(content, String(section["header"]), FONT_SIZE_HEADER, COLOR_HEADER, false)
		_add_divider(content)
		for item in section["items"]:
			_add_label(content, "•  " + String(item), FONT_SIZE_BODY, COLOR_BODY, false)
		_add_gap(content, 14.0)

	_add_label(layout, RULES_FOOTER, FONT_SIZE_BODY, COLOR_FOOTER, true)

	var button_row := HBoxContainer.new()
	button_row.name = "ButtonRow"
	button_row.add_theme_constant_override("separation", 12)
	layout.add_child(button_row)

	var back_button := Button.new()
	back_button.name = "BackButton"
	back_button.text = "BACK"
	back_button.custom_minimum_size = Vector2(150.0, BUTTON_MIN_HEIGHT)
	back_button.add_theme_font_size_override("font_size", 28)
	back_button.add_theme_color_override("font_color", COLOR_BUTTON_TEXT)
	back_button.add_theme_color_override("font_hover_color", COLOR_BUTTON_TEXT)
	back_button.add_theme_color_override("font_pressed_color", COLOR_BUTTON_TEXT)
	back_button.add_theme_color_override("font_focus_color", COLOR_BUTTON_TEXT)
	back_button.add_theme_stylebox_override("normal", _button_style(Color(0.14, 0.26, 0.52)))
	back_button.add_theme_stylebox_override("hover", _button_style(Color(0.18, 0.32, 0.62)))
	var back_pressed := _button_style(Color(0.10, 0.19, 0.40))
	back_pressed.content_margin_top = 15.0
	back_pressed.content_margin_bottom = 9.0
	back_button.add_theme_stylebox_override("pressed", back_pressed)
	back_button.pressed.connect(close)
	button_row.add_child(back_button)

	var play_button := Button.new()
	play_button.name = "LetsPlayButton"
	play_button.text = RULES_BUTTON_TEXT
	play_button.custom_minimum_size = Vector2(0.0, BUTTON_MIN_HEIGHT)
	play_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_button.add_theme_font_size_override("font_size", FONT_SIZE_BUTTON)
	play_button.add_theme_color_override("font_color", COLOR_BUTTON_TEXT)
	play_button.add_theme_color_override("font_hover_color", COLOR_BUTTON_TEXT)
	play_button.add_theme_color_override("font_pressed_color", COLOR_BUTTON_TEXT)
	play_button.add_theme_color_override("font_focus_color", COLOR_BUTTON_TEXT)
	play_button.add_theme_stylebox_override("normal", _button_style(COLOR_BUTTON_BG))
	play_button.add_theme_stylebox_override("hover", _button_style(COLOR_BUTTON_HOVER))
	var pressed_style := _button_style(COLOR_BUTTON_PRESSED)
	pressed_style.content_margin_top = 15.0
	pressed_style.content_margin_bottom = 9.0
	play_button.add_theme_stylebox_override("pressed", pressed_style)
	play_button.pressed.connect(close)
	button_row.add_child(play_button)


func _add_label(parent: Control, text_value: String, font_size: int, color: Color, centered: bool) -> void:
	var label := Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	label.add_theme_constant_override("outline_size", 4)
	parent.add_child(label)


func _add_divider(parent: Control) -> void:
	var divider := ColorRect.new()
	divider.color = COLOR_HEADER
	divider.custom_minimum_size = Vector2(0.0, 2.0)
	parent.add_child(divider)


func _add_gap(parent: Control, height: float) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, height)
	parent.add_child(gap)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL_BG
	style.border_color = COLOR_PANEL_BORDER
	style.set_corner_radius_all(22)
	style.set_border_width_all(2)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 28.0
	style.content_margin_bottom = 24.0
	style.shadow_color = Color(0.0, 0.02, 0.08, 0.5)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 5)
	return style


## Glossy candy pill: light top edge, deep shadow underneath, pushed-in press.
func _button_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(1.0, 0.92, 0.6)
	style.border_width_top = 3
	style.border_width_bottom = 4
	style.border_width_left = 2
	style.border_width_right = 2
	style.set_corner_radius_all(38)  # pill: clamps to half the button height
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	style.shadow_color = Color(0.0, 0.04, 0.12, 0.45)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	return style
