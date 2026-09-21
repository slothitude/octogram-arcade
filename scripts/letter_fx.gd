class_name LetterFx
extends RefCounted
## Letter-shaped particles for battle_ui.gd: submitted words LAUNCH letter by
## letter from the word board into the enemy, dead enemies d-i-s-s-o-l-v-e into
## a burst of letters, and victories pop dictionary words like fireworks.
## Static spawners only; Labels + Tweens (compat renderer safe).

const OUTLINE := Color(0.02, 0.05, 0.12, 0.95)
const COLOR_LAUNCH := Color(1.0, 0.97, 0.9)
const COLOR_BURST := Color(0.82, 0.9, 1.0)
const COLOR_FIREWORK := Color(1.0, 0.84, 0.32)

const FLIGHT_TIME := 0.35
const LAUNCH_STAGGER := 0.03
const LAUNCH_ARC_HEIGHT := 64.0

const ALPHABET := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"


## One small Label per letter of `word`: rises off the current-word display,
## then curves into the enemy center (`to`), fading on impact. Staggered.
static func launch_word(parent: Control, from: Vector2, to: Vector2, word: String) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	for i in range(word.length()):
		var label := _make_label(parent, word[i], 30, COLOR_LAUNCH)
		var delay := float(i) * LAUNCH_STAGGER
		label.global_position = from - Vector2(label.size.x * 0.5, label.size.y * 0.5)
		var mid := Vector2(lerpf(from.x, to.x, 0.3), minf(from.y, to.y) - LAUNCH_ARC_HEIGHT)
		var tween := label.create_tween()
		tween.tween_interval(delay)
		tween.tween_property(label, "global_position", mid, FLIGHT_TIME * 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(label, "global_position", to, FLIGHT_TIME * 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(label, "modulate:a", 0.0, FLIGHT_TIME * 0.35) \
			.set_delay(FLIGHT_TIME * 0.15)
		tween.tween_callback(label.queue_free)


## Enemy death: `count` letters explode outward from `from`, tumbling + fading.
static func explode_letters(parent: Control, from: Vector2, count: int = 14) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	for i in range(count):
		var letter := ALPHABET[randi() % ALPHABET.length()]
		var label := _make_label(parent, letter, randi_range(26, 40), COLOR_BURST)
		label.global_position = from - label.size * 0.5
		var angle := randf() * TAU
		var distance := randf_range(80.0, 220.0)
		var target := from + Vector2(cos(angle), sin(angle)) * distance
		var flight := randf_range(0.55, 0.8)
		var tween := label.create_tween()
		tween.set_parallel(true)
		tween.tween_property(label, "global_position", target - label.size * 0.5, flight) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(label, "rotation", randf_range(-2.4, 2.4), flight) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(label, "modulate:a", 0.0, flight * 0.7).set_delay(flight * 0.3)
		tween.chain().tween_callback(label.queue_free)


## Victory fireworks: `words` burst from `center` and fall away, gold.
static func fireworks(parent: Control, center: Vector2, words: Array) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var pool: Array = words.duplicate()
	pool.shuffle()
	var count := mini(pool.size(), randi_range(8, 12))
	for i in range(count):
		var word := String(pool[i]).to_upper()
		var label := _make_label(parent, word, randi_range(24, 34), COLOR_FIREWORK)
		label.global_position = center - label.size * 0.5
		var angle := randf() * TAU
		var distance := randf_range(120.0, 300.0)
		var target := center + Vector2(cos(angle) * distance, sin(angle) * distance * 0.6)
		var flight := randf_range(0.45, 0.8)
		var tween := label.create_tween()
		tween.tween_interval(float(i) * 0.06)
		tween.tween_property(label, "global_position", target, flight) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(label, "modulate:a", 0.0, flight * 0.6) \
			.set_delay(flight * 0.4)
		tween.tween_callback(label.queue_free)


static func _make_label(parent: Control, text: String, font_size: int,
		color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 55
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_constant_override("outline_size", 5)
	parent.add_child(label)
	label.reset_size()
	return label
