class_name LetterTile
extends Button
## One letter tile: glossy ivory plastic face (tile_face.png) with a big
## uppercase letter + small scrabble-style value in the top-right corner.
## Presentation only - the tap signal and state methods are unchanged.

signal tile_tapped(letter: String)

const TILE_FACE := preload("res://assets/generated/tile_face.png")

const MIN_TILE_SIZE := Vector2(72, 72)
const FACE_INSET := 3.0
const CORNER_RADIUS := 14
const EDGE_WIDTH := 3
const LETTER_FONT_SIZE := 46
const VALUE_FONT_SIZE := 17
const LIFT_OFFSET := -4.0
const PRESS_SCALE := 0.92
const POP_SCALE := 0.6
const POP_TIME := 0.18

const COLOR_TEXT := Color(0.2, 0.15, 0.08)
const COLOR_TEXT_DIM := Color(0.2, 0.15, 0.08, 0.4)
const COLOR_EDGE_REST := Color(0.45, 0.38, 0.26, 0.42)
const COLOR_EDGE_SELECTED := Color(1.0, 0.72, 0.08)
const COLOR_EDGE_DISABLED := Color(0.15, 0.18, 0.24, 0.3)
const COLOR_SHADOW := Color(0.0, 0.03, 0.1, 0.5)
const COLOR_SHADOW_SELECTED := Color(1.0, 0.66, 0.05, 0.75)
const FACE_TINT_SELECTED := Color(1.1, 0.99, 0.6)
const FACE_TINT_DISABLED := Color(0.7, 0.72, 0.78, 0.55)

var letter := ""

var _letter_label: Label
var _value_label: Label
var _visual: Control
var _face: TextureRect
var _edge: Panel
var _edge_style: StyleBoxFlat
var _enabled := true
var _selected := false
var _tween: Tween


func _init() -> void:
	custom_minimum_size = MIN_TILE_SIZE
	focus_mode = Control.FOCUS_NONE
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, empty)
	_build_visuals()
	_apply_state()
	pressed.connect(_on_pressed)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		pivot_offset = size * 0.5
		_layout_labels()


## Set the displayed letter (upper-cased) and its corner value.
func set_letter(new_letter: String) -> void:
	letter = String(new_letter).to_upper()
	if _letter_label != null:
		_letter_label.text = letter
	_update_value()


## Visual "this tile is in the current word" state: gold ring + lift.
func select() -> void:
	_selected = true
	_apply_state()
	_set_lift(true)


## Back to the resting look.
func deselect() -> void:
	_selected = false
	_apply_state()
	_set_lift(false)


## Dim the tile when its letter is used up in the current word.
func set_enabled_tile(enabled: bool) -> void:
	_enabled = enabled
	disabled = not enabled
	_apply_state()
	_set_lift(_selected)


func is_selected() -> bool:
	return _selected


## Pop-in used when a fresh round deals the letters. `delay` staggers tiles.
func pop_in(delay: float = 0.0) -> void:
	if not is_inside_tree():
		scale = Vector2.ONE
		return
	_kill_tween()
	scale = Vector2(POP_SCALE, POP_SCALE)
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE, POP_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(maxf(delay, 0.0))


func _on_pressed() -> void:
	if _enabled:
		tile_tapped.emit(letter)


func _on_button_down() -> void:
	if not _enabled or not is_inside_tree():
		return
	_kill_tween()
	pivot_offset = size * 0.5
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2(PRESS_SCALE, PRESS_SCALE), 0.06) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_button_up() -> void:
	if not is_inside_tree():
		return
	_kill_tween()
	pivot_offset = size * 0.5
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build_visuals() -> void:
	_visual = Control.new()
	_visual.name = "Visual"
	_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_visual)

	_face = TextureRect.new()
	_face.name = "Face"
	_face.texture = TILE_FACE
	_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face.stretch_mode = TextureRect.STRETCH_SCALE
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visual.add_child(_face)

	_edge = Panel.new()
	_edge.name = "Edge"
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge_style = StyleBoxFlat.new()
	_edge_style.draw_center = false
	_edge_style.set_corner_radius_all(CORNER_RADIUS)
	_edge_style.set_border_width_all(EDGE_WIDTH)
	_edge_style.shadow_size = 4
	_edge_style.shadow_offset = Vector2(0, 3)
	_edge_style.shadow_color = COLOR_SHADOW
	_edge.add_theme_stylebox_override("panel", _edge_style)
	_visual.add_child(_edge)

	_letter_label = Label.new()
	_letter_label.name = "Letter"
	_letter_label.text = letter
	_letter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_letter_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_letter_label.add_theme_font_size_override("font_size", LETTER_FONT_SIZE)
	_letter_label.add_theme_color_override("font_color", COLOR_TEXT)
	_letter_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visual.add_child(_letter_label)

	_value_label = Label.new()
	_value_label.name = "Value"
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_value_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_value_label.add_theme_font_size_override("font_size", VALUE_FONT_SIZE)
	_value_label.add_theme_color_override("font_color", COLOR_TEXT)
	_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visual.add_child(_value_label)
	_update_value()
	_layout_labels()


func _apply_state() -> void:
	if _edge_style == null:
		return
	if _selected:
		_edge_style.border_color = COLOR_EDGE_SELECTED
		_edge_style.shadow_color = COLOR_SHADOW_SELECTED
		_edge_style.set_border_width_all(EDGE_WIDTH + 1)
	elif not _enabled:
		_edge_style.border_color = COLOR_EDGE_DISABLED
		_edge_style.shadow_color = COLOR_SHADOW
		_edge_style.set_border_width_all(2)
	else:
		_edge_style.border_color = COLOR_EDGE_REST
		_edge_style.shadow_color = COLOR_SHADOW
		_edge_style.set_border_width_all(2)
	if _face != null:
		_face.modulate = FACE_TINT_SELECTED if _selected else (
			FACE_TINT_DISABLED if not _enabled else Color.WHITE)
	if _letter_label != null:
		_letter_label.add_theme_color_override(
			"font_color", COLOR_TEXT_DIM if not _enabled else COLOR_TEXT)
	if _value_label != null:
		_value_label.add_theme_color_override(
			"font_color", COLOR_TEXT_DIM if not _enabled else COLOR_TEXT)


func _set_lift(up: bool) -> void:
	if _visual == null:
		return
	var target := LIFT_OFFSET if up else 0.0
	if not is_inside_tree():
		_visual.position.y = target
		return
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_visual, "position:y", target, 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()


func _update_value() -> void:
	if _value_label == null:
		return
	var value := int(ScoreManager.LETTER_VALUES.get(letter, 0))
	_value_label.text = str(value)


func _layout_labels() -> void:
	if _visual == null or _face == null or _edge == null:
		return
	var area := size
	if area.x <= 0.0:
		area = custom_minimum_size
	_face.position = Vector2(FACE_INSET, FACE_INSET)
	_face.size = area - Vector2(FACE_INSET, FACE_INSET) * 2.0
	_edge.position = Vector2.ZERO
	_edge.size = area
	if _letter_label != null:
		_letter_label.position = Vector2(0, 0)
		_letter_label.size = Vector2(area.x, area.y - 2)
	if _value_label != null:
		_value_label.position = Vector2(area.x - 24.0, 4.0)
		_value_label.size = Vector2(20, 20)
