class_name ZoneMapUi
extends Control
## Campaign overworld: the five zones as a vertical winding path of chunky
## nodes, each with its three encounters (the 3rd being the boss). The current
## encounter glows gold with a pulse, cleared encounters show a check, and
## future encounters sit locked behind a small padlock glyph. Bubbles drift up
## the path to keep the Word Ocean alive.
##
## Display only: setup(progression) feeds it the live Progression, and main.gd
## answers encounter_selected / back_pressed (it clamps against real state).

signal encounter_selected(zone: int, encounter: int)
signal back_pressed()

const TEX_BACKGROUND := preload("res://assets/generated/background_texture.png")
const CircleButtonScene := preload("res://scenes/button.tscn")

# --- Retro palette (matches ui.gd) -------------------------------------------
const COLOR_PANEL_BG := Color(0.07, 0.12, 0.22, 0.82)
const COLOR_PANEL_BORDER := Color(0.42, 0.55, 0.78, 0.85)
const COLOR_OUTLINE := Color(0.02, 0.05, 0.12, 0.92)
const COLOR_TEXT := Color(0.96, 0.97, 0.99)
const COLOR_TEXT_SOFT := Color(0.82, 0.88, 0.96)
const COLOR_GOLD := Color(1.0, 0.84, 0.32)
const COLOR_GOLD_SOFT := Color(1.0, 0.88, 0.55)
const COLOR_CLEARED := Color(0.55, 0.95, 0.65)
const COLOR_LOCKED_TEXT := Color(0.55, 0.58, 0.66)
const COLOR_LOCK_METAL := Color(0.68, 0.72, 0.82)
const COLOR_BUBBLE := Color(0.5, 0.72, 0.98, 0.16)
const COLOR_BAR_BG := Color(0.05, 0.09, 0.18, 0.85)
const COLOR_BAR_BORDER := Color(0.36, 0.48, 0.7, 0.85)

# --- Layout / motion ---------------------------------------------------------
const HEADER_TITLE := "CAMPAIGN"
const BACK_TEXT := "BACK"
const CLEARED_TEXT := "%d/3 cleared"
const SIDE_MARGIN := 24.0
const HEADER_HEIGHT := 156.0
const PATH_TOP := 176.0
const ZONE_PANEL_WIDTH := 600.0
const ZONE_PANEL_HEIGHT := 152.0
const ZONE_GAP := 22.0
const PATH_SWAY := 44.0
const CHIP_HEIGHT := 48.0
const CHIP_FONT_SIZE := 22
const ZONE_NAME_FONT_SIZE := 24
const SMALL_FONT_SIZE := 18
const PULSE_TIME := 0.55
const BUBBLE_COUNT := 4
const BUBBLE_RISE_TIME := 9.0
const XP_BAR_HEIGHT := 22.0
const GLYPH_SIZE := Vector2(20.0, 20.0)

var _progression: Progression
var _zone_nodes: Array = []
var _current_pulse: Tween
var _gold_label: Label
var _level_label: Label
var _xp_fill: ColorRect
var _xp_label: Label
var _xp_bar_width := 100.0
var _path: Control
var _bubbles_built := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_backdrop()
	_build_header()
	_build_path()
	resized.connect(_layout_nodes)
	_layout_nodes.call_deferred()
	if _progression != null:
		refresh()


## Wire the live campaign state. Safe to call before or after adding to tree.
func setup(progression: Progression) -> void:
	_progression = progression
	if is_inside_tree():
		refresh()


## Re-read the progression and restyle every node (call after battles/buys).
func refresh() -> void:
	if _progression == null or not is_inside_tree():
		return
	_refresh_header()
	_refresh_zones()


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


func _build_header() -> void:
	var header := Panel.new()
	header.name = "Header"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_stylebox_override("panel", _panel_style())
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = SIDE_MARGIN
	header.offset_right = -SIDE_MARGIN
	header.offset_top = 10.0
	header.offset_bottom = HEADER_HEIGHT
	add_child(header)

	var layout := VBoxContainer.new()
	layout.name = "HeaderLayout"
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 16.0
	layout.offset_right = -16.0
	layout.offset_top = 10.0
	layout.offset_bottom = -12.0
	layout.add_theme_constant_override("separation", 8)
	header.add_child(layout)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	layout.add_child(row)

	var back_button: CircleButton = CircleButtonScene.instantiate()
	back_button.name = "BackButton"
	back_button.text = BACK_TEXT
	back_button.accent = "blue"
	back_button.custom_minimum_size = Vector2(150.0, 62.0)
	back_button.add_theme_font_size_override("font_size", 24)
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	row.add_child(back_button)

	var title := Label.new()
	title.text = HEADER_TITLE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", COLOR_GOLD)
	title.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	title.add_theme_constant_override("outline_size", 6)
	row.add_child(title)

	row.add_child(_make_gold_tag())
	_level_label = Label.new()
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_label.add_theme_font_size_override("font_size", 26)
	_level_label.add_theme_color_override("font_color", COLOR_TEXT)
	_level_label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	_level_label.add_theme_constant_override("outline_size", 5)
	row.add_child(_level_label)

	# XP bar: chunky retro trough + gold fill, level progress label on top.
	var bar := Panel.new()
	bar.name = "XpBar"
	bar.custom_minimum_size = Vector2(0.0, XP_BAR_HEIGHT)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("panel", _bar_style())
	layout.add_child(bar)

	_xp_fill = ColorRect.new()
	_xp_fill.name = "XpFill"
	_xp_fill.color = COLOR_GOLD
	_xp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_fill.position = Vector2(3.0, 3.0)
	_xp_fill.size = Vector2(100.0, XP_BAR_HEIGHT - 6.0)
	bar.add_child(_xp_fill)
	bar.resized.connect(func() -> void:
		_xp_bar_width = bar.size.x
		_refresh_xp_bar())

	_xp_label = Label.new()
	_xp_label.name = "XpLabel"
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_label.add_theme_font_size_override("font_size", 15)
	_xp_label.add_theme_color_override("font_color", Color(0.28, 0.17, 0.02))
	_xp_label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	_xp_label.add_theme_constant_override("outline_size", 2)
	_xp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(_xp_label)


func _build_path() -> void:
	_path = Control.new()
	_path.name = "Path"
	_path.mouse_filter = Control.MOUSE_FILTER_PASS
	_path.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_path.offset_top = PATH_TOP
	add_child(_path)

	_zone_nodes.clear()
	for zone in range(1, RpgConfig.TOTAL_ZONES + 1):
		_path.add_child(_make_zone_node(zone))


## Positions depend on the real size, which settles a frame after _ready.
func _layout_nodes() -> void:
	if _path == null:
		return
	for zone in range(1, RpgConfig.TOTAL_ZONES + 1):
		var panel: Panel = _path.get_node_or_null("Zone_%d" % zone)
		if panel == null:
			continue
		var sway := sin(float(zone - 1) * 1.6) * PATH_SWAY
		panel.position = Vector2((size.x - ZONE_PANEL_WIDTH) * 0.5 + sway,
			float(zone - 1) * (ZONE_PANEL_HEIGHT + ZONE_GAP))
	if not _bubbles_built:
		_bubbles_built = true
		_spawn_bubbles()


func _make_zone_node(zone: int) -> Panel:
	var panel := Panel.new()
	panel.name = "Zone_%d" % zone
	panel.size = Vector2(ZONE_PANEL_WIDTH, ZONE_PANEL_HEIGHT)
	panel.add_theme_stylebox_override("panel", _panel_style())

	var layout := VBoxContainer.new()
	layout.name = "Layout"
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 16.0
	layout.offset_right = -16.0
	layout.offset_top = 8.0
	layout.offset_bottom = -10.0
	layout.add_theme_constant_override("separation", 6)
	panel.add_child(layout)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	layout.add_child(name_row)

	var name_label := Label.new()
	name_label.text = "%d. %s" % [zone, EnemyDef.zone_name(zone)]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", ZONE_NAME_FONT_SIZE)
	name_label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	name_label.add_theme_constant_override("outline_size", 4)
	name_row.add_child(name_label)

	var progress_label := Label.new()
	progress_label.text = CLEARED_TEXT % 0
	progress_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	progress_label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	progress_label.add_theme_constant_override("outline_size", 3)
	name_row.add_child(progress_label)

	var chips := HBoxContainer.new()
	chips.name = "Chips"
	chips.add_theme_constant_override("separation", 10)
	layout.add_child(chips)

	var chip_refs: Array = []
	for encounter in range(1, RpgConfig.ENCOUNTERS_PER_ZONE + 1):
		var chip: CircleButton = CircleButtonScene.instantiate()
		chip.name = "Chip_%d_%d" % [zone, encounter]
		chip.text = str(encounter)
		chip.custom_minimum_size = Vector2(0.0, CHIP_HEIGHT)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.add_theme_font_size_override("font_size", CHIP_FONT_SIZE)
		var captured_zone := zone
		var captured_encounter := encounter
		chip.pressed.connect(func() -> void:
			encounter_selected.emit(captured_zone, captured_encounter))
		chips.add_child(chip)
		chip_refs.append({
			"encounter": encounter,
			"button": chip,
		})

	_zone_nodes.append({
		"zone": zone,
		"panel": panel,
		"name_label": name_label,
		"progress_label": progress_label,
		"chips": chip_refs,
	})
	return panel


## 3-4 small circles forever rising along the path, calm and slow.
func _spawn_bubbles() -> void:
	for i in range(BUBBLE_COUNT):
		var bubble_size := 14.0 + float(i) * 5.0
		var bubble := Panel.new()
		bubble.name = "Bubble_%d" % i
		bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = COLOR_BUBBLE
		style.set_corner_radius_all(int(bubble_size * 0.5))
		style.set_border_width_all(2)
		style.border_color = Color(COLOR_BUBBLE.r, COLOR_BUBBLE.g, COLOR_BUBBLE.b, 0.4)
		bubble.add_theme_stylebox_override("panel", style)
		var base_x := 70.0 + float(i) * 150.0
		var start_y := size.y + bubble_size
		bubble.position = Vector2(base_x, start_y)
		bubble.size = Vector2(bubble_size, bubble_size)
		_path.add_child(bubble)

		var sway := 26.0 + float(i) * 6.0
		var rise_time := BUBBLE_RISE_TIME + float(i) * 1.3
		var tween := bubble.create_tween().set_loops()
		tween.set_parallel(true)
		tween.tween_property(bubble, "position:y", -bubble_size * 2.0, rise_time) \
			.from(start_y).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(bubble, "position:x", base_x + sway, rise_time * 0.5) \
			.from(base_x - sway).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(bubble, "modulate:a", 0.9, rise_time * 0.2).from(0.0)
		tween.tween_property(bubble, "modulate:a", 0.0, rise_time * 0.3) \
			.set_delay(rise_time * 0.7)


## --- Refresh -----------------------------------------------------------------


func _refresh_header() -> void:
	_gold_label.text = str(_progression.gold)
	_level_label.text = "LVL %d" % _progression.level
	_refresh_xp_bar()


func _refresh_xp_bar() -> void:
	if _progression == null or _xp_fill == null:
		return
	var needed := maxi(_progression.xp_for_next_level(), 1)
	var ratio := clampf(float(_progression.xp) / float(needed), 0.0, 1.0)
	var width := maxf(_xp_bar_width - 6.0, 0.0)
	_xp_fill.size = Vector2(width * ratio, XP_BAR_HEIGHT - 6.0)
	_xp_label.text = "%d/%d XP" % [_progression.xp, needed]


func _refresh_zones() -> void:
	if _current_pulse != null and _current_pulse.is_valid():
		_current_pulse.kill()
		_current_pulse = null
	var current_index := _index_of(_progression.zone, _progression.encounter)
	for node in _zone_nodes:
		var zone := int(node["zone"])
		var zone_locked := _index_of(zone, 1) > current_index
		var cleared := 0
		for chip in node["chips"]:
			var index := _index_of(zone, int(chip["encounter"]))
			if index < current_index:
				cleared += 1
				_style_chip_cleared(chip)
			elif index == current_index:
				_style_chip_current(chip)
			else:
				_style_chip_locked(chip)
		var progress_label: Label = node["progress_label"]
		progress_label.text = CLEARED_TEXT % cleared
		progress_label.add_theme_color_override(
			"font_color", COLOR_LOCKED_TEXT if zone_locked else COLOR_TEXT_SOFT)
		var name_label: Label = node["name_label"]
		name_label.add_theme_color_override(
			"font_color", COLOR_LOCKED_TEXT if zone_locked else COLOR_TEXT)
		var panel: Panel = node["panel"]
		panel.modulate = Color(0.72, 0.74, 0.82, 0.9) if zone_locked else Color.WHITE


## Cleared: blue chip, small green check in the corner, still replayable.
func _style_chip_cleared(chip: Dictionary) -> void:
	var button: CircleButton = chip["button"]
	button.disabled = false
	button.accent = "blue"
	_set_glyph(button, _make_check_glyph(COLOR_CLEARED))


## Current: gold chip with a pulsing glow - the "you are here" beacon.
func _style_chip_current(chip: Dictionary) -> void:
	var button: CircleButton = chip["button"]
	button.disabled = false
	button.accent = "gold"
	_set_glyph(button, null)
	if _current_pulse == null or not _current_pulse.is_valid():
		_current_pulse = button.create_tween().set_loops()
		_current_pulse.tween_property(button, "modulate",
			Color(1.28, 1.16, 0.78), PULSE_TIME).set_trans(Tween.TRANS_SINE) \
			.set_ease(Tween.EASE_IN_OUT)
		_current_pulse.tween_property(button, "modulate", Color.WHITE, PULSE_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Future: gray chip, small padlock, not tappable.
func _style_chip_locked(chip: Dictionary) -> void:
	var button: CircleButton = chip["button"]
	button.disabled = true
	button.accent = "blue"
	_set_glyph(button, _make_lock_glyph())


func _glyph_holder(button: CircleButton) -> Control:
	var holder := button.get_node_or_null("GlyphHolder") as Control
	if holder == null:
		holder = Control.new()
		holder.name = "GlyphHolder"
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.size = GLYPH_SIZE
		holder.position = Vector2(button.size.x - 14.0, -4.0)
		button.add_child(holder)
		button.resized.connect(func() -> void:
			holder.position = Vector2(button.size.x - 14.0, -4.0))
	return holder


func _set_glyph(button: CircleButton, glyph: Control) -> void:
	var holder := _glyph_holder(button)
	for child in holder.get_children():
		child.queue_free()
	if glyph != null:
		holder.add_child(glyph)


## --- Glyphs (drawn from rects: font-independent, no emoji dependency) --------


## Chunky tick: two rotated bars joined into a check.
func _make_check_glyph(color: Color) -> Control:
	var glyph := Control.new()
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.size = GLYPH_SIZE
	glyph.add_child(_bar(color, Vector2(5.0, 10.0), Vector2(6.5, 12.5), -45.0))
	glyph.add_child(_bar(color, Vector2(5.0, 17.0), Vector2(13.0, 8.5), 45.0))
	return glyph


## Small padlock: rounded body + upside-down-U shackle.
func _make_lock_glyph() -> Control:
	var glyph := Control.new()
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.size = GLYPH_SIZE

	var body := Panel.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var body_style := StyleBoxFlat.new()
	body_style.bg_color = COLOR_LOCK_METAL
	body_style.set_corner_radius_all(3)
	body.add_theme_stylebox_override("panel", body_style)
	body.position = Vector2(4.0, 9.0)
	body.size = Vector2(12.0, 9.0)
	glyph.add_child(body)

	var shackle := Panel.new()
	shackle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shackle_style := StyleBoxFlat.new()
	shackle_style.draw_center = false
	shackle_style.set_border_width_all(3)
	shackle_style.border_color = COLOR_LOCK_METAL
	shackle_style.corner_radius_top_left = 5
	shackle_style.corner_radius_top_right = 5
	shackle.add_theme_stylebox_override("panel", shackle_style)
	shackle.position = Vector2(5.5, 4.0)
	shackle.size = Vector2(9.0, 8.0)
	glyph.add_child(shackle)
	return glyph


func _bar(color: Color, bar_size: Vector2, center: Vector2, rotation_deg: float) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = color
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.size = bar_size
	bar.pivot_offset = bar_size * 0.5
	bar.position = center - bar_size * 0.5
	bar.rotation_degrees = rotation_deg
	return bar


func _make_gold_tag() -> Control:
	var tag := HBoxContainer.new()
	tag.add_theme_constant_override("separation", 6)
	var coin := Panel.new()
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin_style := StyleBoxFlat.new()
	coin_style.bg_color = COLOR_GOLD
	coin_style.border_color = Color(0.72, 0.5, 0.1)
	coin_style.set_border_width_all(2)
	coin_style.set_corner_radius_all(11)
	coin.add_theme_stylebox_override("panel", coin_style)
	coin.custom_minimum_size = Vector2(22.0, 22.0)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.add_child(coin)
	_gold_label = Label.new()
	_gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gold_label.add_theme_font_size_override("font_size", 26)
	_gold_label.add_theme_color_override("font_color", COLOR_GOLD_SOFT)
	_gold_label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	_gold_label.add_theme_constant_override("outline_size", 5)
	tag.add_child(_gold_label)
	return tag


## --- Styles ------------------------------------------------------------------


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL_BG
	style.border_color = COLOR_PANEL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0.0, 0.02, 0.08, 0.35)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	return style


func _bar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BAR_BG
	style.border_color = COLOR_BAR_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(11)
	return style


func _index_of(zone: int, encounter: int) -> int:
	return (zone - 1) * RpgConfig.ENCOUNTERS_PER_ZONE + (encounter - 1)
