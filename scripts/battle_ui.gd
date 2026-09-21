class_name BattleUi
extends Control
## Root controller of battle.tscn: one campaign battle on the phone-portrait
## board. Owns the word flow (typing, tiles, submit validation), the player
## battle timer, and every animation: enemy idle/hit/lunge/death, ghost-trail
## HP bar, launching letters, floating damage numbers, crit hit-stop + screen
## shake, combo meter, victory fireworks and the defeat retry overlay.
## Game state lives in BattleManager (scripts/battle.gd); this is presentation.

signal battle_finished(won: bool, rewards: Dictionary)

const LetterTileScene := preload("res://scenes/letter_tile.tscn")
const TEX_BACKGROUND := preload("res://assets/generated/background_texture.png")
const TEX_BOARD_FACE := preload("res://assets/generated/board_face.png")

## Rejection reason -> player-facing text (same order/copy as arena).
const REASON_TEXT := {
	"empty": "Type a word first",
	"too_short": "Too short",
	"letters_unavailable": "Letters not available",
	"not_in_dictionary": "Not a word",
	"duplicate": "Already used",
	"invalid_characters": "Letters only",
}

# --- Style (matches ui.gd) ---------------------------------------------------
const COLOR_PANEL_BG := Color(0.07, 0.12, 0.22, 0.82)
const COLOR_PANEL_BORDER := Color(0.42, 0.55, 0.78, 0.85)
const COLOR_ROW_BG := Color(0.05, 0.09, 0.18, 0.62)
const COLOR_ROW_BORDER := Color(0.36, 0.48, 0.7, 0.6)
const COLOR_OUTLINE := Color(0.02, 0.05, 0.12, 0.92)
const COLOR_TEXT := Color(0.96, 0.97, 0.99)
const COLOR_TEXT_SOFT := Color(0.82, 0.88, 0.96)
const COLOR_GOLD := Color(1.0, 0.84, 0.32)
const COLOR_GOLD_SOFT := Color(1.0, 0.88, 0.55)
const COLOR_TIMER_HOT := Color(1.0, 0.42, 0.38)
const COLOR_HP_FILL := Color(0.36, 0.85, 0.42)
const COLOR_HP_GHOST := Color(0.96, 0.97, 0.99, 0.75)
const COLOR_HP_BACK := Color(0.02, 0.05, 0.1, 0.9)
const COLOR_COMBO := Color(1.0, 0.7, 0.2)
const COLOR_COMBO_GRAY := Color(0.55, 0.58, 0.64)
const COLOR_ERROR := Color(1.0, 0.45, 0.4)

# --- Timings (snappy: 0.06-0.8s) ---------------------------------------------
const TILE_POP_STAGGER := 0.04
const SHAKE_TIME := 0.25
const SHAKE_CRIT := 8.0
const SHAKE_MEGA := 16.0
const HIT_STOP_SCALE := 0.15
const HIT_STOP_REAL_SECS := 0.06
const FLASH_TIME := 0.08
const VIGNETTE_TIME := 0.3
const LUNGE_TIME := 0.18
const HIT_SQUASH_TIME := 0.12
const VICTORY_TIME := 0.9
const TAUNT_HOLD := 3.2

const TILE_SIZE := Vector2(76, 76)
const VOWELS := ["A", "E", "I", "O", "U"]
const VOWEL_REDRAW_MAX_ATTEMPTS := 200

# --- Public state (battle is exposed for tests/headless drivers) -------------
var battle: BattleManager
var sfx: SfxManager  ## Shared sound bank; main passes its instance (see setup).
var letters: Array = []
var battle_time: float = 0.0
var current_word := ""
var submitted_words: Array = []

var _enemy: Dictionary = {}
var _progression: Progression
var _word_db: WordDatabase
var _letter_gen: LetterGenerator
var _setup_done := false
var _running := false
var _finished := false
var _best_category := 0
var _word_set: Dictionary = {}

# --- Widget refs --------------------------------------------------------------
var _zone_label: Label
var _enemy_name_label: Label
var _taunt_bubble: PanelContainer
var _taunt_label: Label
var _enemy_panel: Panel
var _portrait_wrap: Control
var _portrait_bob: Control
var _portrait: TextureRect
var _portrait_fallback: Label
var _boss_badge: PanelContainer
var _hp_host: Control
var _hp_ghost_rect: ColorRect
var _hp_fill_rect: ColorRect
var _hp_label: Label
var _gold_flash: ColorRect
var _timer_label: Label
var _combo_label: Label
var _word_label: Label
var _letter_area: HBoxContainer
var _words_scroll: ScrollContainer
var _words_list: VBoxContainer
var _submit_button: Button
var _clear_button: Button
var _del_button: Button
var _shuf_button: Button
var _vignette: ColorRect
var _toast: PanelContainer
var _toast_label: Label
var _toast_timer: Timer
var _toast_base_y := -1.0
var _lose_overlay: ColorRect
var _lose_title: Label
var _retry_button: Button
var _back_button: Button
var _victory_title: Label

# --- Animation state ----------------------------------------------------------
var _tiles: Array = []
var _hp_ratio := 1.0
var _hp_ghost := 1.0
var _timer_pulsing := false
var _timer_pulse_tween: Tween
var _idle_tween: Tween
var _shake_tween: Tween
var _toast_tween: Tween
var _hit_stop_busy := false
var _combo_shown := 1.0
var _taunt_hide_timer: Timer

var _tweens: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_backdrop()
	_build_top_strip()
	_build_enemy_panel()
	_build_board()
	_build_bottom_controls()
	_build_overlays()
	_taunt_hide_timer = Timer.new()
	_taunt_hide_timer.one_shot = true
	_taunt_hide_timer.wait_time = TAUNT_HOLD
	_taunt_hide_timer.timeout.connect(_hide_taunt)
	add_child(_taunt_hide_timer)
	_lose_overlay.visible = false
	_victory_title.visible = false
	_taunt_bubble.visible = false
	_toast.visible = false
	_boss_badge.visible = false
	if _setup_done:
		_apply_setup()


func _process(delta: float) -> void:
	if not _running or battle == null or battle.is_over:
		return
	battle_time = maxf(0.0, battle_time - delta)
	battle.tick(delta, battle_time)
	if battle.is_over:
		return
	_update_timer_label()
	_update_hp_bars(delta)


func _exit_tree() -> void:
	# Never leave the engine slowed down if the scene dies mid hit-stop.
	Engine.time_scale = 1.0


# --- Public API ---------------------------------------------------------------


## Wire one battle: enemy dict, player progression, dictionary, letter drawer.
## Creates the BattleManager (exposed as `battle` for tests/headless drivers).
func setup(enemy: Dictionary, progression: Progression, word_db: WordDatabase,
		letter_gen: LetterGenerator) -> void:
	_enemy = enemy
	_progression = progression
	_word_db = word_db
	_letter_gen = letter_gen
	_setup_done = true
	battle = BattleManager.new()
	battle.setup(_enemy, progression.level, progression.upgrades, progression.ng_plus)
	battle.enemy_eat.connect(_on_enemy_eat)
	battle.combo_changed.connect(_on_combo_changed)
	battle.battle_lost.connect(_on_battle_lost)
	# Smoke tests / headless drivers call setup() without main: fall back to a
	# private SfxManager so every play site below is always safe to call.
	if sfx == null:
		sfx = SfxManager.new()
		if is_inside_tree():
			add_child(sfx)
	if is_inside_tree():
		_apply_setup()


## Deal letters, start the clock, show the taunt.
func begin() -> void:
	if battle == null or _enemy.is_empty():
		return
	if is_inside_tree():
		_kill_all_tweens()
		_lose_overlay.visible = false
		_victory_title.visible = false
		_vignette.color = Color(0.7, 0.08, 0.06, 0.0)
	submitted_words = []
	_word_set = {}
	_best_category = 0
	current_word = ""
	_hp_ratio = 1.0
	_hp_ghost = 1.0
	battle_time = _progression.start_timer_seconds()
	_deal_letters()
	_rebuild_tiles()
	_update_word_display()
	_reset_word_tiles()
	if is_inside_tree():
		_apply_bar_widths()
		_update_timer_label()
		_start_idle_animations()
		_show_taunt()
		_pop_in_enemy_panel()
	_finished = false
	_running = true


## Retry the same encounter: fresh BattleManager state, fresh letters.
func retry_same_battle() -> void:
	if battle == null:
		return
	battle.setup(_enemy, _progression.level, _progression.upgrades, _progression.ng_plus)
	begin()


# --- Input / word flow --------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if not _running or battle == null or battle.is_over:
		return
	if event.is_action_pressed("submit"):
		submit_current_word()
	elif event.is_action_pressed("clear"):
		_clear_word()
	elif event.is_action_pressed("shuffle"):
		_shuffle()
	elif event.is_action_pressed("remove_last"):
		_remove_last()
	elif event is InputEventKey and event.is_pressed() and not event.is_echo():
		var unicode := (event as InputEventKey).unicode
		if unicode >= 65 and unicode <= 90:
			_append_letter(char(unicode))
		elif unicode >= 97 and unicode <= 122:
			_append_letter(char(unicode - 32))


func _append_letter(letter: String) -> void:
	if not _running or battle == null or battle.is_over:
		return
	if not _letter_available(letter):
		return
	current_word += letter
	_update_word_display()
	_mark_word_tiles()


func _remove_last() -> void:
	if not _running or current_word.is_empty():
		return
	current_word = current_word.substr(0, current_word.length() - 1)
	_update_word_display()
	_mark_word_tiles()


func _clear_word() -> void:
	if not _running or current_word.is_empty():
		return
	current_word = ""
	_update_word_display()
	_mark_word_tiles()


func _shuffle() -> void:
	if _tiles.size() < 2:
		return
	var pool: Array = []
	for tile in _tiles:
		pool.append(String(tile.letter))
	pool.shuffle()
	for i in range(_tiles.size()):
		_tiles[i].set_letter(String(pool[i]))
	_tiles[randi() % _tiles.size()].pop_in(0.0)


## The exact function the ENTER key triggers (also the SUBMIT button).
func submit_current_word() -> void:
	if not _running or battle == null or battle.is_over:
		return
	var candidate := current_word.strip_edges().to_upper()
	# Validation order copied from RoundManager.submit_word (scripts/round.gd):
	# empty -> invalid_characters -> too_short -> letters_unavailable ->
	# not_in_dictionary -> duplicate.
	if candidate.is_empty():
		_reject("empty")
		return
	for i in range(candidate.length()):
		if candidate[i] < "A" or candidate[i] > "Z":
			_reject("invalid_characters")
			return
	if candidate.length() < ScoreManager.MIN_WORD_LENGTH:
		_reject("too_short")
		return
	if not _can_build(candidate):
		_reject("letters_unavailable")
		return
	if not _word_db.is_valid_word(candidate):
		_reject("not_in_dictionary")
		return
	if _word_set.has(candidate):
		_reject("duplicate")
		return
	_accept_word(candidate)


func _reject(reason: String) -> void:
	if sfx != null:
		sfx.play("reject")
	show_toast(String(REASON_TEXT.get(reason, "Try again")), true)
	_shake_current_word()
	if _word_label != null and _word_label.is_inside_tree():
		var tween := _tw(_word_label)
		tween.tween_property(_word_label, "modulate", COLOR_ERROR, 0.08)
		tween.tween_property(_word_label, "modulate", Color.WHITE, 0.2)


func _accept_word(word: String) -> void:
	var res := battle.on_word_accepted(word, battle.elapsed)
	if float(res.get("damage", 0.0)) <= 0.0 and battle.is_over:
		return
	submitted_words.append(word)
	_word_set[word] = true
	_best_category = maxi(_best_category, ScoreManager.best_category_value(submitted_words))

	var is_crit := bool(res.get("is_crit", false))
	var damage := float(res.get("damage", 0.0))
	if sfx != null:
		sfx.play("crit" if is_crit else "accept")
	_add_word_row(word, damage)
	_launch_letters_at_enemy(word)
	DamageNumber.spawn_damage(self, _enemy_center(), damage, is_crit)
	_hit_enemy_portrait()
	if is_crit:
		_play_crit_juice(word.length() >= ScoreManager.LETTER_COUNT, _enemy_center())
	current_word = ""
	_update_word_display()
	_mark_word_tiles()
	if battle.check_win():
		_finish_win()


## Multiset check: each tile may be used once per word (same as RoundManager).
func _can_build(word: String) -> bool:
	var available := {}
	for letter in letters:
		var key := String(letter).to_upper()
		available[key] = int(available.get(key, 0)) + 1
	for i in range(word.length()):
		var key := word[i]
		if int(available.get(key, 0)) <= 0:
			return false
		available[key] = int(available[key]) - 1
	return true


func _letter_available(letter: String) -> bool:
	var available := 0
	for pool_letter in letters:
		if String(pool_letter) == letter:
			available += 1
	var usage := {}
	for i in range(current_word.length()):
		var key := current_word[i]
		usage[key] = int(usage.get(key, 0)) + 1
	return int(usage.get(letter, 0)) < available


# --- Battle signals -----------------------------------------------------------


## Enemy time-eat: burn seconds off the clock and play the lunge + vignette.
func _on_enemy_eat(amount: int) -> void:
	if battle == null or battle.is_over:
		return
	if sfx != null:
		sfx.play("eat")
	battle_time = maxf(0.0, battle_time - float(amount))
	_update_timer_label()
	DamageNumber.spawn_timer_eat(self, _timer_center(), amount)
	_play_enemy_attack()


func _on_combo_changed(new_combo: float) -> void:
	if _combo_label == null or not _combo_label.is_inside_tree():
		return
	var broke := new_combo <= 1.0 and _combo_shown > 1.0
	_combo_shown = new_combo
	_combo_label.text = "COMBO x%.2f" % new_combo
	if broke:
		var tween := _tw(_combo_label)
		tween.tween_property(_combo_label, "modulate", COLOR_COMBO_GRAY, 0.06)
		tween.tween_property(_combo_label, "scale", Vector2(0.9, 0.9), 0.1) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(_combo_label, "modulate", Color.WHITE, 0.25) \
			.set_delay(0.1)
		tween.tween_property(_combo_label, "scale", Vector2.ONE, 0.15) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_combo_label.pivot_offset = _combo_label.size * 0.5
		var heat := clampf((new_combo - 1.0) / (RpgConfig.COMBO_CAP - 1.0), 0.0, 1.0)
		var tween := _tw(_combo_label)
		tween.tween_property(_combo_label, "scale", Vector2(1.0 + 0.35 * heat, 1.0 + 0.35 * heat), 0.1) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(_combo_label, "modulate",
			Color(1.0 + 0.5 * heat, 0.7 + 0.3 * heat, 0.2), 0.08)
		tween.tween_property(_combo_label, "scale", Vector2.ONE, 0.18) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_battle_lost() -> void:
	if _finished:
		return
	_running = false
	_finished = true
	_show_defeat_overlay()


# --- Win / lose ---------------------------------------------------------------


func _finish_win() -> void:
	if _finished:
		return
	_running = false
	_finished = true
	_hp_ratio = 0.0
	_hp_ghost = 0.0
	if is_inside_tree():
		_apply_bar_widths()
		_hp_label.text = "0 / %d" % int(battle.enemy_max_hp)
		_play_death_dissolve()
	var rewards := battle.finish_win(battle_time, _best_category)
	# Peek only — main.gd is the single place rewards are applied (no double payout).
	var leveled_up := false
	if _progression != null and _progression.has_method("xp_for_next_level"):
		leveled_up = int(_progression.xp) + int(rewards.get("xp", 0)) >= int(_progression.xp_for_next_level())
	_play_victory_sequence({
		"gold": int(rewards.get("gold", 0)),
		"xp": int(rewards.get("xp", 0)),
		"leveled_up": leveled_up,
	})


func _play_victory_sequence(rewards: Dictionary) -> void:
	if sfx != null:
		sfx.play("victory")
	if not is_inside_tree():
		battle_finished.emit(true, rewards)
		return
	_victory_title.text = "VICTORY!  +%dg  +%dxp" % [
		int(rewards.get("gold", 0)), int(rewards.get("xp", 0))]
	_victory_title.visible = true
	_victory_title.pivot_offset = _victory_title.size * 0.5
	_victory_title.scale = Vector2(0.4, 0.4)
	_victory_title.modulate = COLOR_GOLD
	var tween := _tw(_victory_title)
	tween.tween_property(_victory_title, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	LetterFx.fireworks(self, size * 0.5, submitted_words)
	_gold_flash_rect(_enemy_panel, 0.2)
	await get_tree().create_timer(VICTORY_TIME).timeout
	if not is_inside_tree():
		return
	battle_finished.emit(true, rewards)


func _show_defeat_overlay() -> void:
	if not is_inside_tree():
		return
	if sfx != null:
		sfx.play("gameover")
	if _timer_pulse_tween != null and _timer_pulse_tween.is_valid():
		_timer_pulse_tween.kill()
	_timer_pulsing = false
	_timer_label.modulate = Color.WHITE
	_taunt_bubble.visible = false
	_lose_overlay.visible = true
	_lose_overlay.color = Color(0.02, 0.04, 0.1, 0.0)
	var tween := _tw(_lose_overlay)
	tween.tween_property(_lose_overlay, "color:a", 0.72, 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_lose_title.pivot_offset = _lose_title.size * 0.5
	_lose_title.scale = Vector2(0.6, 0.6)
	var title_tween := _tw(_lose_title)
	title_tween.tween_property(_lose_title, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_retry_button.visible = true
	_back_button.visible = true


func _on_retry_pressed() -> void:
	if sfx != null:
		sfx.play("click")
	retry_same_battle()


func _on_back_pressed() -> void:
	if sfx != null:
		sfx.play("click")
	_running = false
	battle_finished.emit(false, {})


# --- Animations ---------------------------------------------------------------


## Idle loop: portrait bobs y +/-6px and wobbles rotation (calm at rest).
## Lives on the inner bob box so it never fights the lunge tween on the wrap.
func _start_idle_animations() -> void:
	if _portrait_bob == null or not _portrait_bob.is_inside_tree():
		return
	if _idle_tween != null and _idle_tween.is_valid():
		_idle_tween.kill()
	_portrait_bob.position.y = 0.0
	_portrait_bob.rotation = 0.0
	_idle_tween = create_tween().set_loops()
	_idle_tween.tween_property(_portrait_bob, "position:y", -6.0, 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.parallel().tween_property(_portrait_bob, "rotation", 0.035, 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_property(_portrait_bob, "position:y", 6.0, 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.parallel().tween_property(_portrait_bob, "rotation", -0.035, 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_property(_portrait_bob, "position:y", 0.0, 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.parallel().tween_property(_portrait_bob, "rotation", 0.0, 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Hit: white flash + squash (TRANS_BACK 0.12s) on the portrait.
func _hit_enemy_portrait() -> void:
	if _portrait == null or not _portrait.is_inside_tree():
		return
	_portrait.pivot_offset = _portrait.size * 0.5
	var tween := _tw(_portrait)
	tween.tween_property(_portrait, "modulate", Color(4.0, 4.0, 4.0), 0.06)
	tween.parallel().tween_property(_portrait, "scale",
		Vector2(1.08, 0.92), HIT_SQUASH_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_portrait, "modulate", Color.WHITE, 0.12)
	tween.parallel().tween_property(_portrait, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Eat attack: portrait lunges toward the board + red vignette pulse.
func _play_enemy_attack() -> void:
	if _portrait_wrap != null and _portrait_wrap.is_inside_tree():
		var tween := _tw(_portrait_wrap)
		tween.tween_property(_portrait_wrap, "position:y", 18.0, LUNGE_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(_portrait_wrap, "position:y", 0.0, LUNGE_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _vignette != null and _vignette.is_inside_tree():
		var vignette_tween := _tw(_vignette)
		vignette_tween.tween_property(_vignette, "color:a", 0.22, VIGNETTE_TIME * 0.4)
		vignette_tween.tween_property(_vignette, "color:a", 0.0, VIGNETTE_TIME * 0.6)


## Crit juice: hit-stop (Engine.time_scale dip), screen shake, gold flash.
func _play_crit_juice(mega: bool, at: Vector2) -> void:
	_screen_shake(SHAKE_MEGA if mega else SHAKE_CRIT)
	_gold_flash_rect(_enemy_panel, FLASH_TIME)
	_hit_stop()


func _hit_stop() -> void:
	if _hit_stop_busy or not is_inside_tree():
		return
	_hit_stop_busy = true
	Engine.time_scale = HIT_STOP_SCALE
	var timer := get_tree().create_timer(HIT_STOP_REAL_SECS, true, false, true)
	await timer.timeout
	Engine.time_scale = 1.0
	_hit_stop_busy = false


## Random-offset shake of the root Control, decaying to zero over 0.25s.
func _screen_shake(amplitude: float) -> void:
	if not is_inside_tree():
		return
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	_shake_tween.tween_method(_apply_shake, amplitude, 0.0, SHAKE_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_shake_tween.tween_callback(func() -> void: position = Vector2.ZERO)


func _apply_shake(amount: float) -> void:
	position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amount


func _gold_flash_rect(panel: Control, time: float) -> void:
	if _gold_flash == null or not _gold_flash.is_inside_tree() or panel == null:
		return
	_gold_flash.global_position = panel.global_position
	_gold_flash.size = panel.size
	_gold_flash.color = Color(1.0, 0.84, 0.32, 0.0)
	var tween := _tw(_gold_flash)
	tween.tween_property(_gold_flash, "color:a", 0.4, maxf(time, 0.06))
	tween.tween_property(_gold_flash, "color:a", 0.0, 0.18)


## Death: dissolve the portrait into flying letters.
func _play_death_dissolve() -> void:
	if not is_inside_tree():
		return
	LetterFx.explode_letters(self, _enemy_center(), randi_range(12, 16))
	var tween := _tw(_portrait)
	tween.tween_property(_portrait, "modulate:a", 0.0, 0.4)
	tween.parallel().tween_property(_portrait, "scale", Vector2(1.3, 1.3), 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _shake_current_word() -> void:
	if _word_label == null or not _word_label.is_inside_tree():
		return
	var base_x := _word_label.position.x
	var tween := _tw(_word_label)
	tween.tween_property(_word_label, "position:x", base_x + 8.0, 0.05)
	tween.tween_property(_word_label, "position:x", base_x - 8.0, 0.05)
	tween.tween_property(_word_label, "position:x", base_x + 5.0, 0.05)
	tween.tween_property(_word_label, "position:x", base_x, 0.05)


func _show_taunt() -> void:
	if _taunt_bubble == null or not _taunt_bubble.is_inside_tree():
		return
	_taunt_label.text = String(_enemy.get("taunt", ""))
	if sfx != null:
		sfx.play("bonus")
	_taunt_bubble.visible = true
	_taunt_bubble.modulate.a = 0.0
	_taunt_bubble.pivot_offset = Vector2(_taunt_bubble.size.x * 0.5, _taunt_bubble.size.y)
	_taunt_bubble.scale = Vector2(0.7, 0.7)
	var tween := _tw(_taunt_bubble)
	tween.set_parallel(true)
	tween.tween_property(_taunt_bubble, "modulate:a", 1.0, 0.15)
	tween.tween_property(_taunt_bubble, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_taunt_hide_timer.start()


func _hide_taunt() -> void:
	if _taunt_bubble == null or not _taunt_bubble.visible or not _taunt_bubble.is_inside_tree():
		return
	var tween := _tw(_taunt_bubble)
	tween.tween_property(_taunt_bubble, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func() -> void: _taunt_bubble.visible = false)


func _pop_in_enemy_panel() -> void:
	if _enemy_panel == null or not _enemy_panel.is_inside_tree():
		return
	_enemy_panel.pivot_offset = _enemy_panel.size * 0.5
	_enemy_panel.scale = Vector2(0.94, 0.94)
	var tween := _tw(_enemy_panel)
	tween.tween_property(_enemy_panel, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --- HP / timer widgets -------------------------------------------------------


func _update_hp_bars(delta: float) -> void:
	var max_hp := maxf(battle.enemy_max_hp, 1.0)
	var target := clampf(battle.enemy_hp / max_hp, 0.0, 1.0)
	_hp_ratio = lerpf(_hp_ratio, target, clampf(delta * 14.0, 0.0, 1.0))
	if target >= _hp_ghost:
		_hp_ghost = target
	else:
		_hp_ghost = maxf(target, lerpf(_hp_ghost, target, clampf(delta * 2.2, 0.0, 1.0)))
	_apply_bar_widths()
	_hp_label.text = "%d / %d" % [int(ceilf(battle.enemy_hp)), int(battle.enemy_max_hp)]


func _apply_bar_widths() -> void:
	if _hp_fill_rect == null:
		return
	var inner := _hp_host.size - Vector2(8, 8)
	_hp_fill_rect.size = Vector2(inner.x * _hp_ratio, inner.y)
	_hp_ghost_rect.size = Vector2(inner.x * _hp_ghost, inner.y)


func _update_timer_label() -> void:
	var whole := int(ceilf(maxf(battle_time, 0.0)))
	_timer_label.text = "%d:%02d" % [whole / 60, whole % 60]
	_update_timer_pulse(whole)


func _update_timer_pulse(whole: int) -> void:
	var should_pulse := whole <= 10 and whole > 0 and _running
	if should_pulse == _timer_pulsing:
		return
	_timer_pulsing = should_pulse
	if not _timer_label.is_inside_tree():
		return
	if _timer_pulse_tween != null and _timer_pulse_tween.is_valid():
		_timer_pulse_tween.kill()
	if should_pulse:
		_timer_label.pivot_offset = _timer_label.size * 0.5
		_timer_pulse_tween = create_tween().set_loops()
		_timer_pulse_tween.tween_property(_timer_label, "modulate", COLOR_TIMER_HOT, 0.25) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_timer_pulse_tween.tween_property(_timer_label, "modulate", Color.WHITE, 0.25) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		_timer_label.modulate = Color.WHITE


# --- Letters / word board -----------------------------------------------------


func _deal_letters() -> void:
	letters = _letter_gen.generate()
	var need := maxi(_progression.guaranteed_vowels(), 1)
	var attempts := 0
	while _vowel_count() < need and attempts < VOWEL_REDRAW_MAX_ATTEMPTS:
		letters = _letter_gen.generate()
		attempts += 1


func _vowel_count() -> int:
	var count := 0
	for letter in letters:
		if VOWELS.has(String(letter)):
			count += 1
	return count


func _rebuild_tiles() -> void:
	if _letter_area == null or not _letter_area.is_inside_tree():
		return
	for child in _letter_area.get_children():
		child.queue_free()
	_tiles.clear()
	for i in range(letters.size()):
		var tile: LetterTile = LetterTileScene.instantiate()
		tile.custom_minimum_size = TILE_SIZE
		tile.focus_mode = Control.FOCUS_NONE
		tile.set_letter(String(letters[i]))
		tile.tile_tapped.connect(_append_letter)
		_letter_area.add_child(tile)
		_tiles.append(tile)
		tile.pop_in(float(i) * TILE_POP_STAGGER)


func _reset_word_tiles() -> void:
	for tile in _tiles:
		tile.deselect()
		tile.set_enabled_tile(true)


## Light the tiles the current word uses, dim tiles whose letters are used up.
func _mark_word_tiles() -> void:
	var availability := {}
	for tile in _tiles:
		var letter := String(tile.letter)
		availability[letter] = int(availability.get(letter, 0)) + 1
	var usage := {}
	for i in range(current_word.length()):
		var letter := current_word[i]
		usage[letter] = int(usage.get(letter, 0)) + 1
	for tile in _tiles:
		var letter := String(tile.letter)
		var used := int(usage.get(letter, 0))
		tile.set_enabled_tile(used < int(availability.get(letter, 0)))
	var to_light := usage.duplicate()
	for tile in _tiles:
		var letter := String(tile.letter)
		if int(to_light.get(letter, 0)) > 0:
			to_light[letter] = int(to_light[letter]) - 1
			tile.select()
		else:
			tile.deselect()


func _update_word_display() -> void:
	_word_label.text = current_word if not current_word.is_empty() else "-"


func _add_word_row(word: String, damage: float) -> void:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _make_pill_style())
	var label := Label.new()
	label.text = "%s  -%d HP" % [word, int(roundf(damage))]
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", COLOR_TEXT_SOFT)
	label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	label.add_theme_constant_override("outline_size", 3)
	row.add_child(label)
	_words_list.add_child(row)
	if _words_list.get_child_count() > 6:
		_words_list.get_child(0).queue_free()
	_scroll_words_to_bottom.call_deferred()


func _scroll_words_to_bottom() -> void:
	_words_scroll.scroll_vertical = int(_words_list.size.y)


func _launch_letters_at_enemy(word: String) -> void:
	if not is_inside_tree():
		return
	LetterFx.launch_word(self, _word_center(), _enemy_center(), word)


func _enemy_center() -> Vector2:
	if _enemy_panel != null and _enemy_panel.is_inside_tree():
		return _enemy_panel.get_global_rect().get_center() + Vector2(0, -20)
	return size * 0.25


func _word_center() -> Vector2:
	if _word_label != null and _word_label.is_inside_tree():
		return _word_label.get_global_rect().get_center()
	return size * 0.5


func _timer_center() -> Vector2:
	if _timer_label != null and _timer_label.is_inside_tree():
		return _timer_label.get_global_rect().get_center()
	return Vector2(size.x - 120.0, 60.0)


# --- Toast --------------------------------------------------------------------


func show_toast(text: String, is_error: bool = false) -> void:
	_toast_label.text = text
	_toast_label.add_theme_color_override("font_color",
		COLOR_ERROR if is_error else COLOR_TEXT)
	_toast.visible = true
	if _toast_base_y < 0.0:
		_toast_base_y = _toast.position.y
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.set_parallel(true)
	_toast.modulate.a = 0.0
	_toast.position.y = _toast_base_y + 12.0
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.15)
	_toast_tween.tween_property(_toast, "position:y", _toast_base_y, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_toast_timer.start()


func _hide_toast() -> void:
	if not _toast.visible or not _toast.is_inside_tree():
		return
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.22)
	_toast_tween.tween_callback(func() -> void: _toast.visible = false)


# --- Widget construction ------------------------------------------------------


func _build_backdrop() -> void:
	var background := TextureRect.new()
	background.name = "Backdrop"
	background.texture = TEX_BACKGROUND
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var board := Panel.new()
	board.name = "BoardFace"
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face := StyleBoxTexture.new()
	face.texture = TEX_BOARD_FACE
	face.set_texture_margin_all(64.0)
	board.add_theme_stylebox_override("panel", face)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.offset_left = 10.0
	board.offset_top = 10.0
	board.offset_right = -10.0
	board.offset_bottom = -10.0
	add_child(board)

	var frame := Panel.new()
	frame.name = "BoardFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_style := StyleBoxFlat.new()
	frame_style.draw_center = false
	frame_style.set_corner_radius_all(22)
	frame_style.set_border_width_all(4)
	frame_style.border_color = Color(0.01, 0.05, 0.14, 0.85)
	frame.add_theme_stylebox_override("panel", frame_style)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 6.0
	frame.offset_top = 6.0
	frame.offset_right = -6.0
	frame.offset_bottom = -6.0
	add_child(frame)


func _build_top_strip() -> void:
	_zone_label = Label.new()
	_zone_label.name = "ZoneLabel"
	_zone_label.position = Vector2(24, 16)
	_zone_label.add_theme_font_size_override("font_size", 20)
	_style_label(_zone_label, 20, COLOR_GOLD_SOFT, 4)
	add_child(_zone_label)

	_enemy_name_label = Label.new()
	_enemy_name_label.name = "EnemyNameLabel"
	_enemy_name_label.position = Vector2(0, 12)
	_enemy_name_label.size = Vector2(720, 34)
	_enemy_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(_enemy_name_label, 28, COLOR_TEXT, 5)
	add_child(_enemy_name_label)

	_taunt_bubble = PanelContainer.new()
	_taunt_bubble.name = "TauntBubble"
	_taunt_bubble.add_theme_stylebox_override("panel", _make_panel_style())
	_taunt_bubble.position = Vector2(90, 52)
	_taunt_bubble.size = Vector2(540, 54)
	add_child(_taunt_bubble)
	_taunt_label = Label.new()
	_taunt_label.name = "TauntLabel"
	_taunt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_taunt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_taunt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_label(_taunt_label, 18, COLOR_TEXT_SOFT, 3)
	_taunt_bubble.add_child(_taunt_label)

	# Concede: leave the battle any time (zero-punishment — XP/gold already
	# earned stay earned). Reuses the defeat overlay's BACK signal so main's
	# handler routes back to the zone map.
	var concede := _make_action_button("BACK", "blue", Vector2(116, 52), 20)
	concede.name = "ConcedeButton"
	concede.position = Vector2(580, 14)
	concede.pressed.connect(_on_back_pressed)
	add_child(concede)


func _build_enemy_panel() -> void:
	_enemy_panel = Panel.new()
	_enemy_panel.name = "EnemyPanel"
	_enemy_panel.add_theme_stylebox_override("panel", _make_panel_style())
	_enemy_panel.position = Vector2(20, 118)
	_enemy_panel.size = Vector2(680, 330)
	_enemy_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_enemy_panel)

	_portrait_wrap = Control.new()
	_portrait_wrap.name = "PortraitWrap"
	_portrait_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_wrap.position = Vector2(240, 14)
	_portrait_wrap.size = Vector2(200, 230)
	_portrait_wrap.pivot_offset = Vector2(100, 115)
	_enemy_panel.add_child(_portrait_wrap)

	_portrait_bob = Control.new()
	_portrait_bob.name = "PortraitBob"
	_portrait_bob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_bob.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait_bob.pivot_offset = Vector2(100, 115)
	_portrait_wrap.add_child(_portrait_bob)

	_portrait = TextureRect.new()
	_portrait.name = "Portrait"
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_bob.add_child(_portrait)

	_portrait_fallback = Label.new()
	_portrait_fallback.name = "PortraitFallback"
	_portrait_fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait_fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait_fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_style_label(_portrait_fallback, 72, COLOR_GOLD, 8)
	_portrait_fallback.visible = false
	_portrait_bob.add_child(_portrait_fallback)

	_boss_badge = PanelContainer.new()
	_boss_badge.name = "BossBadge"
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(0.9, 0.66, 0.14, 0.95)
	badge_style.border_color = Color(1.0, 0.92, 0.6)
	badge_style.set_border_width_all(2)
	badge_style.set_corner_radius_all(14)
	badge_style.content_margin_left = 12.0
	badge_style.content_margin_right = 12.0
	badge_style.content_margin_top = 4.0
	badge_style.content_margin_bottom = 4.0
	_boss_badge.add_theme_stylebox_override("panel", badge_style)
	_boss_badge.position = Vector2(16, 14)
	_enemy_panel.add_child(_boss_badge)
	var badge_label := Label.new()
	badge_label.text = "CROWN BOSS"
	_style_label(badge_label, 18, Color(0.28, 0.17, 0.02), 3)
	_boss_badge.add_child(badge_label)

	# Chunky HP bar: dark back, white GHOST trail behind, green fill on top.
	_hp_host = Control.new()
	_hp_host.name = "HpBar"
	_hp_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_host.position = Vector2(36, 264)
	_hp_host.size = Vector2(608, 34)
	_enemy_panel.add_child(_hp_host)

	var hp_back := ColorRect.new()
	hp_back.name = "HpBack"
	hp_back.color = COLOR_HP_BACK
	hp_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hp_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_host.add_child(hp_back)

	_hp_ghost_rect = ColorRect.new()
	_hp_ghost_rect.name = "HpGhost"
	_hp_ghost_rect.color = COLOR_HP_GHOST
	_hp_ghost_rect.position = Vector2(4, 4)
	_hp_ghost_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_host.add_child(_hp_ghost_rect)

	_hp_fill_rect = ColorRect.new()
	_hp_fill_rect.name = "HpFill"
	_hp_fill_rect.color = COLOR_HP_FILL
	_hp_fill_rect.position = Vector2(4, 4)
	_hp_fill_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_host.add_child(_hp_fill_rect)

	_hp_label = Label.new()
	_hp_label.name = "HpLabel"
	_hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_style_label(_hp_label, 20, COLOR_TEXT, 4)
	_hp_host.add_child(_hp_label)

	_gold_flash = ColorRect.new()
	_gold_flash.name = "GoldFlash"
	_gold_flash.color = Color(1.0, 0.84, 0.32, 0.0)
	_gold_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gold_flash.z_index = 20
	add_child(_gold_flash)


func _build_board() -> void:
	_timer_label = Label.new()
	_timer_label.name = "TimerLabel"
	_timer_label.position = Vector2(492, 452)
	_timer_label.size = Vector2(210, 64)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style_label(_timer_label, 52, COLOR_GOLD, 6)
	add_child(_timer_label)

	_combo_label = Label.new()
	_combo_label.name = "ComboLabel"
	_combo_label.text = "COMBO x1.00"
	_combo_label.position = Vector2(24, 462)
	_combo_label.size = Vector2(300, 40)
	_style_label(_combo_label, 26, COLOR_COMBO, 5)
	add_child(_combo_label)

	_word_label = Label.new()
	_word_label.name = "CurrentWordLabel"
	_word_label.text = "-"
	_word_label.position = Vector2(0, 540)
	_word_label.size = Vector2(720, 66)
	_word_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(_word_label, 48, Color(1.0, 0.97, 0.88), 7)
	add_child(_word_label)

	_letter_area = HBoxContainer.new()
	_letter_area.name = "LetterArea"
	_letter_area.position = Vector2(26, 612)
	_letter_area.size = Vector2(668, 84)
	_letter_area.add_theme_constant_override("separation", 6)
	_letter_area.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_letter_area)

	var words_panel := PanelContainer.new()
	words_panel.name = "WordsPanel"
	words_panel.add_theme_stylebox_override("panel", _make_panel_style())
	words_panel.position = Vector2(60, 706)
	words_panel.size = Vector2(600, 210)
	add_child(words_panel)
	_words_scroll = ScrollContainer.new()
	_words_scroll.name = "WordsScroll"
	_words_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_words_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	words_panel.add_child(_words_scroll)
	_words_list = VBoxContainer.new()
	_words_list.name = "WordsList"
	_words_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_words_list.add_theme_constant_override("separation", 3)
	_words_scroll.add_child(_words_list)


func _build_bottom_controls() -> void:
	var controls := HBoxContainer.new()
	controls.name = "BottomControls"
	controls.position = Vector2(16, 936)
	controls.size = Vector2(688, 96)
	controls.add_theme_constant_override("separation", 8)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(controls)

	_submit_button = _make_action_button("SUBMIT", "gold", Vector2(150, 84), 24)
	_submit_button.pressed.connect(submit_current_word)
	controls.add_child(_submit_button)
	_clear_button = _make_action_button("CLEAR", "gold", Vector2(132, 84), 24)
	_clear_button.pressed.connect(_clear_word)
	controls.add_child(_clear_button)
	_del_button = _make_action_button("DEL", "blue", Vector2(84, 66), 18)
	_del_button.pressed.connect(_remove_last)
	controls.add_child(_del_button)
	_shuf_button = _make_action_button("SHUF", "blue", Vector2(96, 66), 18)
	_shuf_button.pressed.connect(_shuffle)
	controls.add_child(_shuf_button)


func _make_action_button(text: String, accent: String, min_size: Vector2,
		font_size: int) -> Button:
	var button := CircleButton.new()
	button.text = text
	button.accent = accent
	button.custom_minimum_size = min_size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", font_size)
	return button


func _build_overlays() -> void:
	_vignette = ColorRect.new()
	_vignette.name = "Vignette"
	_vignette.color = Color(0.7, 0.08, 0.06, 0.0)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.z_index = 30
	add_child(_vignette)

	_toast = PanelContainer.new()
	_toast.name = "Toast"
	_toast.add_theme_stylebox_override("panel", _make_panel_style())
	_toast.position = Vector2(140, 150)
	_toast.size = Vector2(440, 56)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.z_index = 40
	add_child(_toast)
	_toast_label = Label.new()
	_toast_label.name = "ToastLabel"
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_style_label(_toast_label, 22, COLOR_TEXT, 5)
	_toast.add_child(_toast_label)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.wait_time = 1.6
	_toast_timer.timeout.connect(_hide_toast)
	add_child(_toast_timer)

	_victory_title = Label.new()
	_victory_title.name = "VictoryTitle"
	_victory_title.position = Vector2(0, 470)
	_victory_title.size = Vector2(720, 70)
	_victory_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(_victory_title, 40, COLOR_GOLD, 7)
	_victory_title.z_index = 45
	_victory_title.visible = false
	add_child(_victory_title)

	_lose_overlay = ColorRect.new()
	_lose_overlay.name = "LoseOverlay"
	_lose_overlay.color = Color(0.02, 0.04, 0.1, 0.72)
	_lose_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lose_overlay.z_index = 50
	add_child(_lose_overlay)

	var lose_box := VBoxContainer.new()
	lose_box.name = "LoseBox"
	lose_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lose_box.offset_top = 380.0
	lose_box.add_theme_constant_override("separation", 20)
	lose_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_lose_overlay.add_child(lose_box)

	_lose_title = Label.new()
	_lose_title.name = "LoseTitle"
	_lose_title.text = "TIME'S UP!"
	_lose_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(_lose_title, 52, COLOR_TIMER_HOT, 7)
	lose_box.add_child(_lose_title)

	var hint := Label.new()
	hint.name = "LoseHint"
	hint.text = "The enemy drank your words."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(hint, 22, COLOR_TEXT_SOFT, 4)
	lose_box.add_child(hint)

	_retry_button = CircleButton.new()
	_retry_button.name = "RetryButton"
	_retry_button.text = "RETRY"
	_retry_button.accent = "gold"
	_retry_button.custom_minimum_size = Vector2(280, 92)
	_retry_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_retry_button.focus_mode = Control.FOCUS_NONE
	_retry_button.add_theme_font_size_override("font_size", 28)
	_retry_button.pressed.connect(_on_retry_pressed)
	lose_box.add_child(_retry_button)

	_back_button = CircleButton.new()
	_back_button.name = "BackButton"
	_back_button.text = "BACK"
	_back_button.accent = "blue"
	_back_button.custom_minimum_size = Vector2(160, 60)
	_back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back_button.focus_mode = Control.FOCUS_NONE
	_back_button.add_theme_font_size_override("font_size", 20)
	_back_button.pressed.connect(_on_back_pressed)
	lose_box.add_child(_back_button)


# --- Setup application / helpers ----------------------------------------------


func _apply_setup() -> void:
	_zone_label.text = "ZONE %d - %s" % [
		int(_enemy.get("zone", 1)), EnemyDef.zone_name(int(_enemy.get("zone", 1)))]
	_enemy_name_label.text = String(_enemy.get("display_name", "ENEMY"))
	var initials := ""
	for part in String(_enemy.get("display_name", "")).split(" ", false):
		initials += part.substr(0, 1)
	_portrait_fallback.text = initials
	var art_path := String(_enemy.get("art", ""))
	if art_path != "" and ResourceLoader.exists(art_path):
		_portrait.texture = load(art_path)
		_portrait.visible = true
		_portrait_fallback.visible = false
	else:
		_portrait.texture = null
		_portrait.visible = false
		_portrait_fallback.visible = true
	_boss_badge.visible = bool(_enemy.get("is_boss", false))
	_hp_label.text = "%d / %d" % [int(battle.enemy_max_hp), int(battle.enemy_max_hp)]
	_apply_bar_widths()
	_combo_label.text = "COMBO x1.00"


func _style_label(label: Label, font_size: int, color: Color, outline: int) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	label.add_theme_constant_override("outline_size", outline)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.02, 0.08, 0.6))
	label.add_theme_constant_override("shadow_offset_y", 3)
	label.add_theme_constant_override("shadow_outline_size", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL_BG
	style.border_color = COLOR_PANEL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0.0, 0.02, 0.08, 0.35)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


func _make_pill_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_ROW_BG
	style.border_color = COLOR_ROW_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	return style


func _tw(node: Node) -> Tween:
	var existing: Tween = _tweens.get(node)
	if existing != null and existing.is_valid():
		existing.kill()
	var tween := node.create_tween()
	_tweens[node] = tween
	return tween


func _kill_all_tweens() -> void:
	for node in _tweens.keys():
		var tween: Tween = _tweens[node]
		if tween != null and tween.is_valid():
			tween.kill()
	_tweens.clear()
	if _idle_tween != null and _idle_tween.is_valid():
		_idle_tween.kill()
	if _timer_pulse_tween != null and _timer_pulse_tween.is_valid():
		_timer_pulse_tween.kill()
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
