class_name FeedbackUi
extends Control
## Full-screen "SEND FEEDBACK" modal - the Game Making Pipeline's intake. This
## screen only collects the message (typed text + quick-tap tags) and emits
## send_requested; main owns the HTTPRequest that POSTs it to Telegram. Visual
## language matches HowToUi: dim backdrop, navy panel, gold title, CircleButton
## actions.

signal closed()
signal send_requested(text: String)

const COLOR_DIM := Color(0.01, 0.03, 0.08, 0.72)
const COLOR_PANEL_BG := Color(0.07, 0.12, 0.22, 0.97)
const COLOR_PANEL_BORDER := Color(0.42, 0.55, 0.78, 0.9)
const COLOR_OUTLINE := Color(0.02, 0.05, 0.12, 0.92)
const COLOR_TITLE := Color(1.0, 0.88, 0.5)
const COLOR_BODY := Color(0.94, 0.96, 0.99)
const COLOR_CONTEXT := Color(0.7, 0.79, 0.92)
const COLOR_STATUS_OK := Color(0.55, 0.95, 0.65)
const COLOR_STATUS_BAD := Color(1.0, 0.62, 0.55)

const TITLE_TEXT := "SEND FEEDBACK"
const EXPLAINER_TEXT := "Tell us anything — what to change, what you love, what's broken. It goes straight to the makers and the Game Making Pipeline."
const MESSAGE_HINT_TEXT := "Type here (or tap a tag)…"
const TAGS := ["TOO HARD", "TOO EASY", "MORE COLORS", "SOUND OFF?", "LOVE IT"]
const MESSAGE_MIN_HEIGHT := 200.0
const TAG_FONT_SIZE := 13
const TAG_SEPARATION := 6.0
## How long the success note stays up before the overlay closes itself.
const NOTE_CLOSE_DELAY := 1.4

var _context_label: Label
var _hint_label: Label
var _message_edit: TextEdit
var _status_label: Label
var _note_tween: Tween


func _init() -> void:
	# Hidden before _ready builds the panel - an overlay must never flash.
	visible = false


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


## Show the overlay with the auto-context main reports (mode, score/level...).
## Any draft from a previous visit survives - a failed send must not eat it.
func open(context: Dictionary) -> void:
	if _context_label != null:
		_context_label.text = _summarize(context)
	_hide_note()
	_update_hint()
	visible = true
	_message_edit.grab_focus.call_deferred()


## Hide the overlay and tell the caller.
func close() -> void:
	visible = false
	closed.emit()


## The dim summary line under the title - main reuses it verbatim as the first
## line of the Telegram message so what the player saw is what the makers get.
func context_summary() -> String:
	return _context_label.text


## The typed message.
func message() -> String:
	return _message_edit.text


## Forget the draft (main calls this only after a successful send).
func clear_message() -> void:
	_message_edit.text = ""
	_update_hint()


## A toast-style note inside the panel: green when the send worked (with a
## short auto-close - the board's own toast is off-screen behind the menu),
## red when it failed (overlay stays up, draft intact).
func show_note(note: String, is_success: bool = false) -> void:
	if _note_tween != null and _note_tween.is_valid():
		_note_tween.kill()
		_note_tween = null
	_status_label.text = note
	_status_label.add_theme_color_override("font_color",
		COLOR_STATUS_OK if is_success else COLOR_STATUS_BAD)
	_status_label.visible = true
	if is_success:
		_note_tween = create_tween()
		_note_tween.tween_interval(NOTE_CLOSE_DELAY)
		_note_tween.tween_callback(_close_if_visible)


func _close_if_visible() -> void:
	if visible:
		close()


func _hide_note() -> void:
	if _note_tween != null and _note_tween.is_valid():
		_note_tween.kill()
		_note_tween = null
	_status_label.visible = false


## Quick-tap tag: prepended to whatever is already written.
func _on_tag_pressed(tag: String) -> void:
	var current := _message_edit.text.strip_edges()
	_message_edit.text = tag if current.is_empty() else "%s %s" % [tag, current]
	_message_edit.set_caret_column(_message_edit.text.length())
	_update_hint()


func _on_send_pressed() -> void:
	send_requested.emit(_message_edit.text)


func _on_message_changed() -> void:
	_update_hint()


func _update_hint() -> void:
	_hint_label.visible = _message_edit.text.is_empty()


## "ARENA · ROUND 3 · SCORE 120" style line: mode first, then whatever the
## caller passed in (insertion order).
func _summarize(context: Dictionary) -> String:
	var bits := PackedStringArray()
	bits.append(String(context.get("mode", "menu")).to_upper())
	for key in context:
		if String(key) == "mode":
			continue
		bits.append("%s %s" % [String(key).to_upper(), str(context[key])])
	return " · ".join(bits)


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
	title.text = TITLE_TEXT
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

	var explainer := Label.new()
	explainer.name = "ExplainerLabel"
	explainer.text = EXPLAINER_TEXT
	explainer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explainer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	explainer.add_theme_font_size_override("font_size", 20)
	explainer.add_theme_color_override("font_color", COLOR_BODY)
	explainer.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	explainer.add_theme_constant_override("outline_size", 3)
	layout.add_child(explainer)

	_context_label = Label.new()
	_context_label.name = "ContextLabel"
	_context_label.text = "MENU"
	_context_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_context_label.add_theme_font_size_override("font_size", 18)
	_context_label.add_theme_color_override("font_color", COLOR_CONTEXT)
	_context_label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	_context_label.add_theme_constant_override("outline_size", 3)
	layout.add_child(_context_label)

	_message_edit = TextEdit.new()
	_message_edit.name = "MessageEdit"
	_message_edit.custom_minimum_size = Vector2(0.0, MESSAGE_MIN_HEIGHT)
	_message_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_message_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_message_edit.add_theme_font_size_override("font_size", 22)
	_message_edit.add_theme_color_override("font_color", COLOR_BODY)
	_message_edit.add_theme_color_override("caret_color", COLOR_TITLE)
	_message_edit.add_theme_stylebox_override("normal", _edit_style())
	_message_edit.add_theme_stylebox_override("focus", _edit_style())
	_message_edit.text_changed.connect(_on_message_changed)
	layout.add_child(_message_edit)

	_hint_label = Label.new()
	_hint_label.name = "HintLabel"
	_hint_label.text = MESSAGE_HINT_TEXT
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.add_theme_font_size_override("font_size", 20)
	_hint_label.add_theme_color_override("font_color", Color(0.6, 0.66, 0.76, 0.85))
	_hint_label.position = Vector2(16.0, 12.0)
	_message_edit.add_child(_hint_label)

	var tag_row := HBoxContainer.new()
	tag_row.name = "TagRow"
	tag_row.add_theme_constant_override("separation", int(TAG_SEPARATION))
	layout.add_child(tag_row)
	for i in range(TAGS.size()):
		var tag := CircleButton.new()
		tag.name = "TagButton_%d" % i
		tag.text = String(TAGS[i])
		tag.accent = "blue"
		tag.custom_minimum_size = Vector2(0.0, 56.0)
		tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tag.add_theme_font_size_override("font_size", TAG_FONT_SIZE)
		tag.pressed.connect(_on_tag_pressed.bind(String(TAGS[i])))
		tag_row.add_child(tag)

	_status_label = Label.new()
	_status_label.name = "StatusNote"
	_status_label.visible = false
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.add_theme_font_size_override("font_size", 22)
	_status_label.add_theme_color_override("font_color", COLOR_STATUS_OK)
	_status_label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	_status_label.add_theme_constant_override("outline_size", 4)
	layout.add_child(_status_label)

	var button_row := HBoxContainer.new()
	button_row.name = "ButtonRow"
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 16)
	layout.add_child(button_row)

	var cancel := CircleButton.new()
	cancel.name = "CancelButton"
	cancel.accent = "blue"
	cancel.text = "CANCEL"
	cancel.custom_minimum_size = Vector2(170, 70)
	cancel.add_theme_font_size_override("font_size", 24)
	cancel.pressed.connect(close)
	button_row.add_child(cancel)

	var send := CircleButton.new()
	send.name = "SendButton"
	send.accent = "gold"
	send.text = "SEND"
	send.custom_minimum_size = Vector2(170, 70)
	send.add_theme_font_size_override("font_size", 24)
	send.pressed.connect(_on_send_pressed)
	button_row.add_child(send)


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


func _edit_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.06, 0.13, 0.92)
	style.border_color = COLOR_PANEL_BORDER
	style.set_corner_radius_all(14)
	style.set_border_width_all(2)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style
