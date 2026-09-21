class_name ShopUi
extends Control
## THE ARCANE WORDSHOP: the between-battles upgrade stop. Five rows from
## RpgConfig.SHOP_ITEMS with owned stacks, escalating cost and a BUY button
## that only lights up when the gold is there. Display only - setup(progression)
## wires the live Progression, and main.gd answers item_bought (to save) and
## closed (to head back to the zone map).

signal item_bought(item_id: String)
signal closed()

const TEX_BACKGROUND := preload("res://assets/generated/background_texture.png")
const CircleButtonScene := preload("res://scenes/button.tscn")

const TITLE_TEXT := "THE ARCANE WORDSHOP"
const SUBTITLE_TEXT := "spend your gold, power your spells"
const LEAVE_TEXT := "LEAVE"
const BUY_TEXT := "BUY"
const MAX_TEXT := "MAX"
const OWNED_TEXT := "%d/%d"

# --- Retro palette (matches ui.gd) -------------------------------------------
const COLOR_PANEL_BG := Color(0.07, 0.12, 0.22, 0.82)
const COLOR_PANEL_BORDER := Color(0.42, 0.55, 0.78, 0.85)
const COLOR_ROW_BG := Color(0.05, 0.09, 0.18, 0.62)
const COLOR_ROW_BORDER := Color(0.36, 0.48, 0.7, 0.6)
const COLOR_OUTLINE := Color(0.02, 0.05, 0.12, 0.92)
const COLOR_TEXT := Color(0.96, 0.97, 0.99)
const COLOR_TEXT_SOFT := Color(0.82, 0.88, 0.96)
const COLOR_GOLD := Color(1.0, 0.84, 0.32)
const COLOR_GOLD_SOFT := Color(1.0, 0.88, 0.55)
const COLOR_COIN_EDGE := Color(0.72, 0.5, 0.1)
const COLOR_SPARK := Color(1.0, 0.9, 0.5)

# --- Layout / motion ---------------------------------------------------------
const SIDE_MARGIN := 24.0
const TITLE_FONT_SIZE := 38
const SUBTITLE_FONT_SIZE := 20
const ITEM_NAME_FONT_SIZE := 24
const ITEM_DESC_FONT_SIZE := 17
const SMALL_FONT_SIZE := 19
const ROW_MIN_HEIGHT := 128.0
const ROW_SEPARATION := 12.0
const BUY_BUTTON_MIN_SIZE := Vector2(118.0, 72.0)
const LEAVE_BUTTON_MIN_HEIGHT := 88.0
const LEAVE_FONT_SIZE := 28
const SPARK_COUNT := 8
const SPARK_TIME := 0.5

var _progression: Progression
var _rows: Array = []
var _gold_label: Label
var _rows_box: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_backdrop()
	_build_layout()
	if _progression != null:
		refresh()


## Wire the live campaign state. Safe to call before or after adding to tree.
func setup(progression: Progression) -> void:
	_progression = progression
	if is_inside_tree():
		refresh()


## Re-read the progression: gold display, stacks, costs, button states.
func refresh() -> void:
	if _progression == null or not is_inside_tree():
		return
	_gold_label.text = str(_progression.gold)
	for row in _rows:
		var item_id := String(row["id"])
		var item: Dictionary = RpgConfig.SHOP_ITEMS.get(item_id, {})
		if item.is_empty():
			continue
		var owned := int(_progression.upgrades.get(item_id, 0))
		var max_stacks := int(item["max_stacks"])
		var cost := _progression.item_cost(item_id)
		var maxed := owned >= max_stacks
		var owned_label: Label = row["owned"]
		owned_label.text = OWNED_TEXT % [owned, max_stacks]
		var cost_label: Label = row["cost"]
		cost_label.text = str(cost)
		var buy_button: CircleButton = row["buy"]
		buy_button.text = MAX_TEXT if maxed else BUY_TEXT
		buy_button.disabled = maxed or _progression.gold < cost


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
	margin.add_theme_constant_override("margin_left", int(SIDE_MARGIN))
	margin.add_theme_constant_override("margin_top", 20.0)
	margin.add_theme_constant_override("margin_right", int(SIDE_MARGIN))
	margin.add_theme_constant_override("margin_bottom", 20.0)
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.name = "Layout"
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)

	_build_header(layout)

	_rows_box = VBoxContainer.new()
	_rows_box.name = "Rows"
	_rows_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", int(ROW_SEPARATION))
	layout.add_child(_rows_box)

	for item_id in RpgConfig.SHOP_ITEMS.keys():
		_rows_box.add_child(_make_item_row(String(item_id)))

	var leave_button: CircleButton = CircleButtonScene.instantiate()
	leave_button.name = "LeaveButton"
	leave_button.text = LEAVE_TEXT
	leave_button.accent = "blue"
	leave_button.custom_minimum_size = Vector2(0.0, LEAVE_BUTTON_MIN_HEIGHT)
	leave_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leave_button.add_theme_font_size_override("font_size", LEAVE_FONT_SIZE)
	leave_button.pressed.connect(func() -> void: closed.emit())
	layout.add_child(leave_button)


func _build_header(layout: VBoxContainer) -> void:
	var header := PanelContainer.new()
	header.name = "Header"
	header.add_theme_stylebox_override("panel", _panel_style())
	layout.add_child(header)

	var header_box := VBoxContainer.new()
	header_box.add_theme_constant_override("separation", 2)
	header.add_child(header_box)

	var title := Label.new()
	title.text = TITLE_TEXT
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", COLOR_GOLD)
	title.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	title.add_theme_constant_override("outline_size", 6)
	header_box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = SUBTITLE_TEXT
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", SUBTITLE_FONT_SIZE)
	subtitle.add_theme_color_override("font_color", COLOR_TEXT_SOFT)
	subtitle.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	subtitle.add_theme_constant_override("outline_size", 3)
	header_box.add_child(subtitle)

	var gold_row := HBoxContainer.new()
	gold_row.alignment = BoxContainer.ALIGNMENT_CENTER
	gold_row.add_theme_constant_override("separation", 8)
	header_box.add_child(gold_row)
	gold_row.add_child(_make_coin())
	_gold_label = Label.new()
	_gold_label.name = "GoldLabel"
	_gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gold_label.add_theme_font_size_override("font_size", 30)
	_gold_label.add_theme_color_override("font_color", COLOR_GOLD_SOFT)
	_gold_label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	_gold_label.add_theme_constant_override("outline_size", 5)
	gold_row.add_child(_gold_label)


func _make_item_row(item_id: String) -> Control:
	var item: Dictionary = RpgConfig.SHOP_ITEMS.get(item_id, {})

	var row := PanelContainer.new()
	row.name = "Row_%s" % item_id
	row.custom_minimum_size = Vector2(0.0, ROW_MIN_HEIGHT)
	row.add_theme_stylebox_override("panel", _row_style())

	var row_box := HBoxContainer.new()
	row_box.add_theme_constant_override("separation", 10)
	row.add_child(row_box)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_box.add_theme_constant_override("separation", 2)
	row_box.add_child(text_box)

	var name_label := Label.new()
	name_label.text = String(item.get("name", item_id))
	name_label.add_theme_font_size_override("font_size", ITEM_NAME_FONT_SIZE)
	name_label.add_theme_color_override("font_color", COLOR_GOLD_SOFT)
	name_label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	name_label.add_theme_constant_override("outline_size", 4)
	text_box.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = String(item.get("desc", ""))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", ITEM_DESC_FONT_SIZE)
	desc_label.add_theme_color_override("font_color", COLOR_TEXT_SOFT)
	desc_label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	desc_label.add_theme_constant_override("outline_size", 3)
	text_box.add_child(desc_label)

	var owned_label := Label.new()
	owned_label.text = OWNED_TEXT % [0, 0]
	owned_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	owned_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	owned_label.add_theme_color_override("font_color", COLOR_TEXT)
	owned_label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	owned_label.add_theme_constant_override("outline_size", 3)
	row_box.add_child(owned_label)

	var cost_tag := HBoxContainer.new()
	cost_tag.alignment = BoxContainer.ALIGNMENT_CENTER
	cost_tag.add_theme_constant_override("separation", 5)
	cost_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row_box.add_child(cost_tag)
	cost_tag.add_child(_make_coin())
	var cost_label := Label.new()
	cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE + 3)
	cost_label.add_theme_color_override("font_color", COLOR_GOLD_SOFT)
	cost_label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	cost_label.add_theme_constant_override("outline_size", 3)
	cost_tag.add_child(cost_label)

	var buy_button: CircleButton = CircleButtonScene.instantiate()
	buy_button.name = "BuyButton"
	buy_button.text = BUY_TEXT
	buy_button.accent = "gold"
	buy_button.custom_minimum_size = BUY_BUTTON_MIN_SIZE
	buy_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy_button.add_theme_font_size_override("font_size", 24)
	buy_button.pressed.connect(func() -> void: _on_buy_pressed(item_id, buy_button))
	row_box.add_child(buy_button)

	_rows.append({
		"id": item_id,
		"owned": owned_label,
		"cost": cost_label,
		"buy": buy_button,
	})
	return row


## --- Buying ------------------------------------------------------------------


func _on_buy_pressed(item_id: String, button: CircleButton) -> void:
	if _progression == null:
		return
	if not _progression.buy(item_id):
		return  # can't afford / maxed: the button was disabled anyway
	_sparkle(button)
	item_bought.emit(item_id)
	refresh()


## Little burst of gold sparks off the BUY button on a successful purchase.
func _sparkle(button: CircleButton) -> void:
	if not button.is_inside_tree():
		return
	button.pivot_offset = button.size * 0.5
	var pop := button.create_tween()
	pop.tween_property(button, "scale", Vector2(1.12, 1.12), 0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pop.tween_property(button, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var origin := button.get_global_rect().get_center()
	for i in range(SPARK_COUNT):
		var spark_size := 6.0 + float(i % 3) * 3.0
		var spark := Panel.new()
		spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spark.z_index = 30
		var style := StyleBoxFlat.new()
		style.bg_color = COLOR_SPARK
		style.set_corner_radius_all(int(spark_size * 0.5))
		spark.add_theme_stylebox_override("panel", style)
		spark.size = Vector2(spark_size, spark_size)
		get_parent().add_child(spark)
		spark.global_position = origin - Vector2(spark_size, spark_size) * 0.5
		var angle := TAU * float(i) / float(SPARK_COUNT) + 0.4
		var distance := 44.0 + float(i % 4) * 12.0
		var target := origin + Vector2(cos(angle), sin(angle)) * distance
		var tween := spark.create_tween()
		tween.set_parallel(true)
		tween.tween_property(spark, "global_position", target - spark.size * 0.5, SPARK_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(spark, "modulate:a", 0.0, SPARK_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.chain().tween_callback(spark.queue_free)


## --- Styles ------------------------------------------------------------------


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL_BG
	style.border_color = COLOR_PANEL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	style.shadow_color = Color(0.0, 0.02, 0.08, 0.35)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	return style


func _row_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_ROW_BG
	style.border_color = COLOR_ROW_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _make_coin() -> Control:
	var coin := Panel.new()
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin_style := StyleBoxFlat.new()
	coin_style.bg_color = COLOR_GOLD
	coin_style.border_color = COLOR_COIN_EDGE
	coin_style.set_border_width_all(2)
	coin_style.set_corner_radius_all(11)
	coin.add_theme_stylebox_override("panel", coin_style)
	coin.custom_minimum_size = Vector2(22.0, 22.0)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return coin
