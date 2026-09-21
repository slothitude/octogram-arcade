class_name CircleButton
extends Button
## Glossy pill/round touch button (retro-2000s web-game style): candy body with
## a light top edge + dark bottom edge, pressed state pushes the label in.
## `accent` picks the palette: "blue" (default) or "gold" (primary actions).
## Works with mouse, touch, and keyboard focus.

const MIN_BUTTON_SIZE := Vector2(56, 56)
const FONT_SIZE := 18

## Blue accent (secondary buttons).
const BLUE_BG := Color(0.14, 0.26, 0.52)
const BLUE_BG_HOVER := Color(0.18, 0.32, 0.62)
const BLUE_BG_DOWN := Color(0.1, 0.19, 0.4)
const BLUE_EDGE_TOP := Color(0.55, 0.72, 0.95)
const BLUE_EDGE_SIDE := Color(0.3, 0.44, 0.72)
const BLUE_EDGE_BOTTOM := Color(0.02, 0.07, 0.18)
const BLUE_TEXT := Color(0.97, 0.98, 1.0)

## Gold accent (primary actions: SUBMIT / PLAY AGAIN).
const GOLD_BG := Color(0.9, 0.66, 0.14)
const GOLD_BG_HOVER := Color(0.98, 0.74, 0.22)
const GOLD_BG_DOWN := Color(0.76, 0.53, 0.09)
const GOLD_EDGE_TOP := Color(1.0, 0.92, 0.6)
const GOLD_EDGE_SIDE := Color(0.72, 0.5, 0.1)
const GOLD_EDGE_BOTTOM := Color(0.36, 0.22, 0.02)
const GOLD_TEXT := Color(0.28, 0.17, 0.02)

const COLOR_DISABLED_BG := Color(0.16, 0.18, 0.24)
const COLOR_DISABLED_BORDER := Color(0.28, 0.31, 0.4)
const COLOR_DISABLED_TEXT := Color(0.52, 0.55, 0.62)

@export_enum("blue", "gold") var accent: String = "blue":
	set(value):
		accent = value
		if is_inside_tree():
			_apply_accent()

var _style_normal: StyleBoxFlat
var _style_hover: StyleBoxFlat
var _style_pressed: StyleBoxFlat
var _style_focus: StyleBoxFlat
var _tween: Tween


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	_style_normal = _make_style()
	_style_hover = _make_style()
	_style_pressed = _make_style()
	_style_focus = _make_style()
	add_theme_stylebox_override("normal", _style_normal)
	add_theme_stylebox_override("hover", _style_hover)
	add_theme_stylebox_override("pressed", _style_pressed)
	add_theme_stylebox_override("focus", _style_focus)
	add_theme_stylebox_override("disabled", _make_disabled_style())
	add_theme_color_override("font_outline_color", Color(0.0, 0.04, 0.12, 0.85))
	add_theme_constant_override("outline_size", 3)
	_apply_accent()
	resized.connect(_update_radius)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		pivot_offset = size * 0.5
		_update_radius()


func _ready() -> void:
	# Scene-file sizes/font overrides win; only supply defaults when absent.
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = MIN_BUTTON_SIZE
	if not has_theme_font_size_override("font_size"):
		add_theme_font_size_override("font_size", FONT_SIZE)
	_apply_accent()


## Circular look: corner radius half the smaller axis.
func _update_radius() -> void:
	var radius := _current_radius()
	for style in [_style_normal, _style_hover, _style_pressed, _style_focus]:
		if style != null:
			style.set_corner_radius_all(radius)


func _current_radius() -> int:
	var radius := int(minf(size.x, size.y) * 0.5)
	if radius <= 0:
		radius = int(MIN_BUTTON_SIZE.y * 0.5)
	return radius


func _apply_accent() -> void:
	var gold := accent == "gold"
	if _style_normal != null:
		_glossify(_style_normal,
			GOLD_BG if gold else BLUE_BG,
			GOLD_EDGE_TOP if gold else BLUE_EDGE_TOP,
			GOLD_EDGE_SIDE if gold else BLUE_EDGE_SIDE,
			GOLD_EDGE_BOTTOM if gold else BLUE_EDGE_BOTTOM, false)
	if _style_hover != null:
		_glossify(_style_hover,
			GOLD_BG_HOVER if gold else BLUE_BG_HOVER,
			GOLD_EDGE_TOP if gold else BLUE_EDGE_TOP,
			GOLD_EDGE_SIDE if gold else BLUE_EDGE_SIDE,
			GOLD_EDGE_BOTTOM if gold else BLUE_EDGE_BOTTOM, false)
	if _style_pressed != null:
		_glossify(_style_pressed,
			GOLD_BG_DOWN if gold else BLUE_BG_DOWN,
			GOLD_EDGE_SIDE if gold else BLUE_EDGE_SIDE,
			GOLD_EDGE_SIDE if gold else BLUE_EDGE_SIDE,
			GOLD_EDGE_BOTTOM if gold else BLUE_EDGE_BOTTOM, true)
	if _style_focus != null:
		_glossify(_style_focus,
			GOLD_BG_HOVER if gold else BLUE_BG_HOVER,
			Color(1.0, 0.85, 0.3) if gold else Color(0.7, 0.85, 1.0),
			GOLD_EDGE_SIDE if gold else BLUE_EDGE_SIDE,
			GOLD_EDGE_BOTTOM if gold else BLUE_EDGE_BOTTOM, false)
	add_theme_color_override("font_color", GOLD_TEXT if gold else BLUE_TEXT)
	add_theme_color_override("font_hover_color", GOLD_TEXT if gold else BLUE_TEXT)
	add_theme_color_override("font_focus_color", GOLD_TEXT if gold else BLUE_TEXT)
	add_theme_color_override("font_pressed_color", GOLD_TEXT if gold else BLUE_TEXT)
	add_theme_color_override("font_hover_pressed_color", GOLD_TEXT if gold else BLUE_TEXT)
	add_theme_color_override("font_disabled_color", COLOR_DISABLED_TEXT)


## Glossy body: light top edge, dark bottom edge, deeper drop shadow when down.
func _glossify(style: StyleBoxFlat, body: Color, top: Color, side: Color,
		bottom: Color, pressed: bool) -> void:
	style.bg_color = body
	style.border_color = top  # corner blend uses the lightest edge
	style.set_corner_radius_all(_current_radius())
	style.border_width_top = 3
	style.border_width_bottom = 4
	style.border_width_left = 2
	style.border_width_right = 2
	# Per-side colors are approximated by blending: Godot StyleBoxFlat supports a
	# single border color, so the light-top/dark-bottom feel comes from stacking a
	# slightly darker bottom border via shadow offset instead.
	style.shadow_color = Color(0.0, 0.04, 0.12, 0.35 if not pressed else 0.55)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 3 if not pressed else 4)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 7.0 if not pressed else 9.0
	style.content_margin_bottom = 7.0 if not pressed else 5.0


func _make_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(_current_radius())
	return style


func _make_disabled_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_DISABLED_BG
	style.border_color = COLOR_DISABLED_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(_current_radius())
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


func _on_button_down() -> void:
	if not is_inside_tree():
		return
	_kill_tween()
	pivot_offset = size * 0.5
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2(0.96, 0.96), 0.06) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_button_up() -> void:
	if not is_inside_tree():
		return
	_kill_tween()
	pivot_offset = size * 0.5
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
