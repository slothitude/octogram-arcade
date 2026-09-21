class_name DamageNumber
extends RefCounted
## Floating combat text, spawned by battle_ui.gd. Static spawners only: each
## call builds one outlined Label, tweens it (scale-in -> rise + drift -> fade)
## and frees it. Compatibility-renderer safe (Labels + Tweens, no particles).

const OUTLINE := Color(0.02, 0.05, 0.12, 0.95)
const COLOR_DAMAGE := Color(1.0, 0.97, 0.9)
const COLOR_CRIT := Color(1.0, 0.84, 0.32)
const COLOR_EAT := Color(1.0, 0.42, 0.38)

const SCALE_IN_TIME := 0.12
const FADE_TIME := 0.4
const RISE_MIN := 60.0
const RISE_MAX := 90.0
const FONT_SIZE := 40
const CRIT_FONT_MULT := 1.8


## Standard attack number at `global_pos` (enemy). Crits are 1.8x size + gold.
static func spawn_damage(parent: Control, global_pos: Vector2, amount: float,
		is_crit: bool) -> void:
	var text := "-%d" % int(roundf(amount))
	if is_crit:
		text += "!"
	var size := int(float(FONT_SIZE) * (CRIT_FONT_MULT if is_crit else 1.0))
	var color := COLOR_CRIT if is_crit else COLOR_DAMAGE
	var drift := randf_range(-18.0, 18.0)
	var rise := randf_range(RISE_MIN, RISE_MAX)
	_spawn(parent, global_pos, text, color, size, rise, drift)


## Red "-Ns" flying off the battle timer when the enemy eats time.
static func spawn_timer_eat(parent: Control, timer_global_pos: Vector2, amount: int) -> void:
	_spawn(parent, timer_global_pos, "-%ds" % amount, COLOR_EAT, 34, 74.0,
		randf_range(10.0, 26.0))


## Shared flight: scale in over SCALE_IN_TIME, rise `rise` px with `drift` x
## drift, fade over FADE_TIME, then free.
static func _spawn(parent: Control, global_pos: Vector2, text: String, color: Color,
		font_size: int, rise: float, drift: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 60
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.02, 0.08, 0.6))
	label.add_theme_constant_override("shadow_offset_y", 3)
	parent.add_child(label)
	label.reset_size()
	label.global_position = global_pos - Vector2(label.size.x * 0.5, label.size.y * 0.5)
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2(0.4, 0.4)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2.ONE, SCALE_IN_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", label.position.y - rise, 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:x", label.position.x + drift, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, FADE_TIME).set_delay(0.1)
	tween.chain().tween_callback(label.queue_free)
