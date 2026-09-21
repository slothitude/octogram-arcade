class_name ModeMenu
extends Control
## Boot screen: CAMPAIGN / ARENA / EIGHT LETTERS / RULES over the ocean
## backdrop, the Octogram hero bobbing under the logo. Display only - main.gd
## owns the routing and reacts to mode_selected (and feedback_requested, the
## small gold FEEDBACK button in the top-right corner).

signal mode_selected(mode: String)
signal feedback_requested()

const TEX_BACKGROUND := preload("res://assets/generated/background_texture.png")
const TEX_LOGO := preload("res://assets/generated/logo_plate.png")
const TEX_HERO := preload("res://assets/generated/rpg/hero_octogram.png")
const CircleButtonScene := preload("res://scenes/button.tscn")

const MODE_CAMPAIGN := "campaign"
const MODE_ARENA := "arena"
const MODE_EIGHT := "eight"
const MODE_RULES := "rules"

const FEEDBACK_TEXT := "FEEDBACK"
const FEEDBACK_BUTTON_SIZE := Vector2(120.0, 52.0)
const FEEDBACK_BUTTON_MARGIN := 16.0
const FEEDBACK_BUTTON_FONT_SIZE := 18

const TITLE_TEXT := "OCTOGRAM ARCADE"
const SUBTITLE_TEXT := "three word games, one ocean"
const CAMPAIGN_TEXT := "CAMPAIGN"
const ARENA_TEXT := "ARENA"
const EIGHT_TEXT := "EIGHT LETTERS"
const RULES_TEXT := "RULES"

# --- Retro palette (matches ui.gd) -------------------------------------------
const COLOR_OUTLINE := Color(0.02, 0.05, 0.12, 0.92)
const COLOR_GOLD := Color(1.0, 0.84, 0.32)
const COLOR_GOLD_SOFT := Color(1.0, 0.88, 0.55)
const COLOR_TEXT_SOFT := Color(0.82, 0.88, 0.96)

# --- Layout / motion ---------------------------------------------------------
const MENU_MARGIN := 26.0
const LOGO_MIN_HEIGHT := 140.0
const TITLE_FONT_SIZE := 46
const SUBTITLE_FONT_SIZE := 26
const HERO_HOLDER_SIZE := Vector2(380.0, 400.0)
const HERO_SIZE := Vector2(360.0, 380.0)
const HERO_BOB_HEIGHT := 14.0
const HERO_BOB_TIME := 1.8
const BUTTON_MIN_HEIGHT := 96.0
const BUTTON_FONT_SIZE := 32
const BUTTON_SEPARATION := 22.0
const FADE_IN_TIME := 0.25

var _campaign_button: CircleButton
var _arena_button: CircleButton
var _eight_button: CircleButton
var _rules_button: CircleButton
var _feedback_button: CircleButton
var _hero: TextureRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_backdrop()
	_build_layout()
	_build_feedback_button()
	_animate_in()


## Test/automation hook: select ARENA exactly like tapping the button.
func select_arena() -> void:
	mode_selected.emit(MODE_ARENA)


## Test/automation hook: select EIGHT LETTERS exactly like tapping the button.
func select_eight() -> void:
	mode_selected.emit(MODE_EIGHT)


## --- Construction ------------------------------------------------------------


func _build_backdrop() -> void:
	var background := TextureRect.new()
	background.name = "Backdrop"
	background.texture = TEX_BACKGROUND
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)


func _build_layout() -> void:
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(MENU_MARGIN))
	margin.add_theme_constant_override("margin_top", int(MENU_MARGIN))
	margin.add_theme_constant_override("margin_right", int(MENU_MARGIN))
	margin.add_theme_constant_override("margin_bottom", int(MENU_MARGIN))
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.name = "Layout"
	layout.add_theme_constant_override("separation", 6)
	margin.add_child(layout)

	var logo := TextureRect.new()
	logo.name = "Logo"
	logo.texture = TEX_LOGO
	logo.custom_minimum_size = Vector2(0.0, LOGO_MIN_HEIGHT)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(logo)

	_add_label(layout, TITLE_TEXT, TITLE_FONT_SIZE, COLOR_GOLD, 7)
	_add_label(layout, SUBTITLE_TEXT, SUBTITLE_FONT_SIZE, COLOR_TEXT_SOFT, 4)

	layout.add_child(_make_hero_holder())

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(spacer)

	layout.add_child(_make_buttons())


func _make_hero_holder() -> Control:
	var holder := Control.new()
	holder.name = "HeroHolder"
	holder.custom_minimum_size = HERO_HOLDER_SIZE
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_hero = TextureRect.new()
	_hero.name = "Hero"
	_hero.texture = TEX_HERO
	_hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero.size = HERO_SIZE
	_hero.position = Vector2(
		(HERO_HOLDER_SIZE.x - HERO_SIZE.x) * 0.5, (HERO_HOLDER_SIZE.y - HERO_SIZE.y) * 0.5)
	holder.add_child(_hero)

	# Gentle idle bob: the Octogram floats over the menu.
	var bob := _hero.create_tween().set_loops()
	bob.tween_property(_hero, "position:y", _hero.position.y - HERO_BOB_HEIGHT, HERO_BOB_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(_hero, "position:y", _hero.position.y, HERO_BOB_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return holder


func _make_buttons() -> Control:
	var box := VBoxContainer.new()
	box.name = "Buttons"
	box.add_theme_constant_override("separation", int(BUTTON_SEPARATION))

	_campaign_button = _make_button(CAMPAIGN_TEXT, "gold")
	_campaign_button.pressed.connect(func() -> void: mode_selected.emit(MODE_CAMPAIGN))
	box.add_child(_campaign_button)

	_arena_button = _make_button(ARENA_TEXT, "blue")
	_arena_button.pressed.connect(func() -> void: mode_selected.emit(MODE_ARENA))
	box.add_child(_arena_button)

	_eight_button = _make_button(EIGHT_TEXT, "blue")
	_eight_button.pressed.connect(func() -> void: mode_selected.emit(MODE_EIGHT))
	box.add_child(_eight_button)

	_rules_button = _make_button(RULES_TEXT, "blue")
	_rules_button.pressed.connect(func() -> void: mode_selected.emit(MODE_RULES))
	box.add_child(_rules_button)
	return box


## Small gold FEEDBACK pill, pinned to the top-right corner (outside the margin
## layout so it floats over the logo backdrop).
func _build_feedback_button() -> void:
	_feedback_button = CircleButtonScene.instantiate()
	_feedback_button.name = "FeedbackButton"
	_feedback_button.text = FEEDBACK_TEXT
	_feedback_button.accent = "gold"
	_feedback_button.custom_minimum_size = FEEDBACK_BUTTON_SIZE
	_feedback_button.add_theme_font_size_override("font_size",
		FEEDBACK_BUTTON_FONT_SIZE)
	_feedback_button.focus_mode = Control.FOCUS_NONE
	_feedback_button.anchor_left = 1.0
	_feedback_button.anchor_right = 1.0
	_feedback_button.offset_left = -FEEDBACK_BUTTON_MARGIN - FEEDBACK_BUTTON_SIZE.x
	_feedback_button.offset_top = FEEDBACK_BUTTON_MARGIN
	_feedback_button.offset_right = -FEEDBACK_BUTTON_MARGIN
	_feedback_button.offset_bottom = FEEDBACK_BUTTON_MARGIN + FEEDBACK_BUTTON_SIZE.y
	_feedback_button.pressed.connect(func() -> void: feedback_requested.emit())
	add_child(_feedback_button)


func _make_button(text_value: String, accent: String) -> CircleButton:
	var button: CircleButton = CircleButtonScene.instantiate()
	button.text = text_value
	button.accent = accent
	button.custom_minimum_size = Vector2(0.0, BUTTON_MIN_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	return button


func _add_label(parent: Control, text_value: String, font_size: int, color: Color,
		outline: int) -> void:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	label.add_theme_constant_override("outline_size", outline)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.02, 0.08, 0.6))
	label.add_theme_constant_override("shadow_offset_y", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)


## CAMPAIGN is the headline mode: it gets default focus for keyboard/enter.
func _animate_in() -> void:
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, FADE_IN_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_campaign_button.grab_focus.call_deferred()
