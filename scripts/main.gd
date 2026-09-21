class_name Main
extends Control
## Composition root: owns the GameManager, TimerController, SaveData,
## Progression, UIController (from game_board.tscn), WordDatabase,
## LetterGenerator, the debug panel, and the menu routing. All game state lives
## here / in GameManager; ui.gd is display.
##
## Boot: load save -> build Progression -> ModeMenu. CAMPAIGN goes ZoneMap ->
## battle -> Wordshop -> ZoneMap; ARENA is the original 6-round game untouched;
## EIGHT LETTERS is a self-contained run (board8.tscn + GameEight + how-to);
## RULES opens the tutorial over the menu.

const GameBoardScene := preload("res://scenes/game_board.tscn")
const TutorialScene := preload("res://scenes/tutorial_screen.tscn")
const ModeMenuScene := preload("res://scenes/mode_menu.tscn")
const ZoneMapScene := preload("res://scenes/zone_map.tscn")
const ShopScene := preload("res://scenes/shop.tscn")
const DebugPanelScript := preload("res://scripts/debug_panel.gd")

## Loaded at runtime (not preloaded): the battle scene is built in parallel and
## a missing preload would break this script's compile.
const BATTLE_SCENE_PATH := "res://scenes/battle.tscn"

## Loaded at runtime like the battle scene (same pattern).
const BOARD8_SCENE_PATH := "res://scenes/board8.tscn"

## Tutorial destinations: where the player lands after closing it.
const TUTORIAL_DEST_MENU := "menu"
const TUTORIAL_DEST_ARENA := "arena"

## Rejection reason -> player-facing text.
const REASON_TEXT := {
	"empty": "Type a word first",
	"too_short": "Too short",
	"letters_unavailable": "Letters not available",
	"not_in_dictionary": "Not a word",
	"duplicate": "Already used",
	"invalid_characters": "Letters only",
	"not_playing": "Round not running",
}

## Eight Letters rejection texts (kept separate from the arena's so each mode
## keeps its own wording, e.g. "Already found" vs "Already used").
const EIGHT_REASON_TEXT := {
	"empty": "Type a word first",
	"too_short": "Too short",
	"letters_unavailable": "Letters not available",
	"not_in_dictionary": "Not a word",
	"duplicate": "Already found",
	"invalid_characters": "Letters only",
	"not_playing": "Round not running",
	"bonus_round": "Bonus round — find the 8-letter word!",
}

## --- Feedback channel (the Game Making Pipeline's intake) ---------------------
##
## FEEDBACK on the mode menu opens the overlay; sending POSTs the message to the
## Telegram bot (form-urlencoded sendMessage — web-safe, no preflight). The
## HTTPRequest lives here, created once and reused, one send in flight at a
## time. Offline/headless it just fails: the overlay notes it and the draft
## survives. The overlay's own note is the toast (the arena board is hidden
## behind the menu, so ui.show_toast would be invisible).

const TELEGRAM_BOT_TOKEN := "8563469356:AAFAG3Uk3To3L1BtnPB_HC7LBn-ITnKSehs"
const TELEGRAM_CHAT_ID := "5597932516"
const TELEGRAM_SEND_URL := "https://api.telegram.org/bot8563469356:AAFAG3Uk3To3L1BtnPB_HC7LBn-ITnKSehs/sendMessage"
const FEEDBACK_TIMEOUT := 15.0
const FEEDBACK_OK_NOTE := "Thank you! Sent to the makers 💌"
const FEEDBACK_FAIL_NOTE := "Couldn't send — try again later"

@onready var ui: UIController = $GameBoard

var game: GameManager
var timer: TimerController
var save_data: SaveData
var word_db: WordDatabase
var letter_gen: LetterGenerator
var debug_panel: DebugPanel
var progression: Progression
var sfx: SfxManager

var current_word := ""

var _settings: Dictionary = {}
var _saved_totals: Dictionary = {"total_score": 0, "highest_round": 0}
var _tutorial: Node = null
var _tutorial_first_time := false
var _tutorial_destination := TUTORIAL_DEST_ARENA
var _mode_menu: ModeMenu = null
var _zone_map: ZoneMapUi = null
var _shop: ShopUi = null
var _battle: Node = null
var _battle_is_current := false

## --- Feedback channel (overlay + its one reusable HTTPRequest) ----------------

var _feedback: FeedbackUi = null
var _feedback_http: HTTPRequest = null
var _feedback_context := {}
var _feedback_sending := false

## --- Eight Letters (EIGHT mode; its own board, timer, reveal, how-to) -------

## Game logic unit; null until the player enters EIGHT LETTERS.
var game8: GameEight = null
## Letter source built from the shared word_db at the moment the mode starts
## (tier is applied during boot, before any mode can start).
var letter_source: LetterSource = null
## The Eight Letters play board while that mode is up (exposed for tests, same
## name the standalone game's main used).
var board: Board8 = null
## The how-to overlay, created with the board; exists only inside EIGHT mode.
var how_to: HowToUi = null

var _eight_best_score := 0
var _eight_best_level := 0


func _ready() -> void:
	word_db = WordDatabase.new()
	letter_gen = LetterGenerator.new()

	game = GameManager.new()
	game.setup(word_db, letter_gen)

	timer = TimerController.new()
	timer.timeout.connect(_on_timer_timeout)

	save_data = SaveData.new()
	var data := save_data.load_data()
	_settings = data.get("settings", {})
	# Word set: COMMON (everyday words) unless the save says STANDARD or EXPERT.
	# Battle scenes share this word_db instance, so validation follows the tier
	# immediately.
	var saved_tier := String(_settings.get("word_set", "common")).to_lower()
	word_db.set_tier(saved_tier if WordDatabase.TIER_PATHS.has(saved_tier) else "common")
	_saved_totals = {
		"total_score": int(data.get("total_score", 0)),
		"highest_round": int(data.get("highest_round", 0)),
	}
	# Eight Letters bests live in their own [eight] save section; missing keys
	# (v1/v2 saves) fall back to zero.
	_eight_best_score = maxi(0, int(data.get("best_score", 0)))
	_eight_best_level = maxi(0, int(data.get("best_level", 0)))
	progression = _restore_progression(data.get("rpg", {}))

	sfx = SfxManager.new()
	sfx.set_muted(not bool(_settings.get("sound", true)))
	add_child(sfx)

	debug_panel = DebugPanelScript.new()
	debug_panel.main = self
	add_child(debug_panel)

	_connect_game_signals()
	_connect_ui_signals()

	_show_mode_menu()


func _process(delta: float) -> void:
	if game.state == GameManager.GameState.PLAYING and timer.is_running():
		timer.tick(delta)
		ui.set_time_left(timer.time_left)
	if game8 != null and _eight_accepting_input():
		game8.timer.tick(delta)
		board.set_time_left(game8.timer.time_left)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle"):
		debug_panel.toggle()
		get_viewport().set_input_as_handled()
		return
	# EIGHT LETTERS owns the keyboard while its board is up.
	if game8 != null:
		_eight_unhandled_input(event)
		return
	if is_instance_valid(_tutorial) or is_instance_valid(_battle):
		return
	if game.state != GameManager.GameState.PLAYING:
		return
	if event.is_action_pressed("submit"):
		_submit_word()
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


## --- Current word (single source of truth is here) --------------------------


func _append_letter(letter: String) -> void:
	if game.state != GameManager.GameState.PLAYING:
		return
	if not _letter_available(letter):
		return
	current_word += letter
	if sfx != null:
		sfx.play("click")
	_update_word_ui()


func _remove_last() -> void:
	if game.state != GameManager.GameState.PLAYING:
		return
	if current_word.is_empty():
		return
	current_word = current_word.substr(0, current_word.length() - 1)
	_update_word_ui()


func _clear_word() -> void:
	if game.state != GameManager.GameState.PLAYING:
		return
	current_word = ""
	_update_word_ui()


func _shuffle() -> void:
	ui.shuffle_tiles()
	_update_word_ui()


func _submit_word() -> void:
	if game.state != GameManager.GameState.PLAYING:
		return
	if current_word.is_empty():
		ui.show_toast(String(REASON_TEXT["empty"]))
		return
	var result := game.submit_word(current_word)
	if bool(result.get("accepted", false)):
		current_word = ""
		_update_word_ui()
	else:
		if sfx != null:
			sfx.play("reject")
		var reason := String(result.get("reason", ""))
		ui.show_toast(String(REASON_TEXT.get(reason, "Try again")))


func _letter_available(letter: String) -> bool:
	var available := 0
	for pool_letter in game.letters:
		if String(pool_letter) == letter:
			available += 1
	var usage := _word_usage()
	return int(usage.get(letter, 0)) < available


## letter -> times that letter appears in the current word.
func _word_usage() -> Dictionary:
	var usage := {}
	for i in range(current_word.length()):
		var letter := current_word[i]
		usage[letter] = int(usage.get(letter, 0)) + 1
	return usage


func _update_word_ui() -> void:
	ui.set_current_word(current_word)
	ui.set_tile_consumed(_word_usage())
	ui.mark_word_tiles(current_word)
	_update_score_panel()
	debug_panel.refresh()


func _update_score_panel() -> void:
	ui.set_score_panel(game.best_category_value(), game.category_potential())


## --- Game signal wiring -----------------------------------------------------


func _connect_game_signals() -> void:
	game.state_changed.connect(_on_state_changed)
	game.round_started.connect(_on_round_started)
	game.total_score_changed.connect(_on_total_score_changed)
	game.word_accepted.connect(_on_word_accepted)
	game.round_ended.connect(_on_round_ended)
	game.category_chosen.connect(_on_category_chosen)
	game.game_complete.connect(_on_game_complete)


func _connect_ui_signals() -> void:
	ui.submit_requested.connect(_submit_word)
	ui.clear_requested.connect(_clear_word)
	ui.backspace_requested.connect(_remove_last)
	ui.shuffle_requested.connect(_shuffle)
	ui.letter_tapped.connect(_append_letter)
	ui.category_chosen.connect(game.choose_category)
	ui.play_again_requested.connect(_on_play_again)
	ui.rules_requested.connect(_open_rules)


func _on_round_started(round_number: int, letters: Array) -> void:
	current_word = ""
	ui.hide_final()
	ui.hide_category_select()
	ui.set_round(round_number)
	ui.set_letters(letters)
	ui.clear_word_state()
	timer.start(ScoreManager.ROUND_TIME)
	ui.set_time_left(timer.time_left)
	_update_score_panel()
	debug_panel.refresh()


func _on_total_score_changed(new_total: int) -> void:
	ui.set_total(new_total)


func _on_word_accepted(word: String, bonus: int, letter_points: int) -> void:
	if sfx != null:
		sfx.play("crit" if bonus > 0 else "accept")
	ui.set_last_word("LAST WORD: %s (+%d pts, +%d bonus)" % [word, letter_points, bonus])
	ui.add_submitted_word(word, letter_points, bonus)
	ui.show_toast("+%d" % (bonus + letter_points))
	_update_score_panel()
	debug_panel.refresh()


func _on_round_ended(_round_number: int, category_scores: Dictionary) -> void:
	timer.stop()
	ui.set_category_scores(category_scores, game.used_categories)
	ui.show_category_select(category_scores, game.used_categories)
	debug_panel.refresh()


func _on_category_chosen(_category: int, _points: int) -> void:
	if sfx != null:
		sfx.play("coin")
	ui.hide_category_select()
	ui.set_category_scores(
		ScoreManager.all_category_scores(game.current_words), game.used_categories
	)
	debug_panel.refresh()


func _on_state_changed(_old_state: int, _new_state: int) -> void:
	debug_panel.refresh()


func _on_game_complete(final_total: int) -> void:
	if sfx != null:
		sfx.play("victory")
	timer.stop()
	ui.hide_category_select()
	ui.show_final(game.round_history, final_total)
	_save_progress(final_total)
	debug_panel.refresh()


func _on_timer_timeout() -> void:
	game.end_round()


func _on_play_again() -> void:
	current_word = ""
	ui.hide_final()
	game.reset_game()


## --- Menu routing -----------------------------------------------------------


func _show_mode_menu() -> void:
	_clear_menu_screens()
	ui.visible = false
	_mode_menu = ModeMenuScene.instantiate()
	_mode_menu.mode_selected.connect(_on_mode_selected)
	_mode_menu.feedback_requested.connect(_open_feedback)
	add_child(_mode_menu)


func _show_zone_map() -> void:
	_clear_menu_screens()
	ui.visible = false
	_zone_map = ZoneMapScene.instantiate()
	_zone_map.setup(progression)
	_zone_map.encounter_selected.connect(_on_encounter_selected)
	_zone_map.back_pressed.connect(_show_mode_menu)
	add_child(_zone_map)


func _show_shop() -> void:
	_clear_menu_screens()
	ui.visible = false
	_shop = ShopScene.instantiate()
	_shop.setup(progression)
	_shop.item_bought.connect(_on_item_bought)
	_shop.closed.connect(_show_zone_map)
	add_child(_shop)


## Free whatever menu-level screen is up (menu / zone map / wordshop).
func _clear_menu_screens() -> void:
	for screen in [_mode_menu, _zone_map, _shop]:
		if is_instance_valid(screen):
			screen.queue_free()
	_mode_menu = null
	_zone_map = null
	_shop = null


func _on_mode_selected(mode: String) -> void:
	match String(mode):
		"campaign":
			_show_zone_map()
		"arena":
			_start_arena()
		"eight":
			_start_eight()
		"rules":
			_open_tutorial(false, TUTORIAL_DEST_MENU)


## ARENA: the original word-poker flow, exactly as it shipped.
func _start_arena() -> void:
	_clear_menu_screens()
	ui.visible = true
	game.start_game()


## --- Campaign battles -------------------------------------------------------


func _on_encounter_selected(zone: int, encounter: int) -> void:
	var enemy := EnemyDef.enemy_at(int(zone), int(encounter))
	if enemy.is_empty():
		return
	# Locked (ahead of the real progression): ignore the tap.
	if _encounter_index(int(zone), int(encounter)) > _encounter_index(progression.zone, progression.encounter):
		return
	_start_battle(enemy, int(zone) == progression.zone and int(encounter) == progression.encounter)


func _start_battle(enemy: Dictionary, is_current: bool) -> void:
	var packed: PackedScene = load(BATTLE_SCENE_PATH)
	if packed == null:
		push_error("Main: battle scene missing at %s" % BATTLE_SCENE_PATH)
		return
	_clear_menu_screens()
	ui.visible = false
	_battle = packed.instantiate()
	_battle_is_current = is_current
	add_child(_battle)
	_battle.setup(enemy, progression, word_db, letter_gen)
	_battle.set("sfx", sfx)
	_battle.battle_finished.connect(_on_battle_finished)
	_battle.begin()


func _on_battle_finished(won: bool, rewards: Dictionary) -> void:
	if is_instance_valid(_battle):
		_battle.queue_free()
	_battle = null
	var was_current := _battle_is_current
	_battle_is_current = false
	if bool(won):
		progression.add_gold(int(rewards.get("gold", 0)))
		progression.add_xp(int(rewards.get("xp", 0)))
		if bool(rewards.get("leveled_up", false)) and sfx != null:
			sfx.play("levelup")
		if was_current:
			progression.advance_encounter()
	_save_all()
	if bool(won):
		_show_shop()  # soothing: no pressure, spend (or hoard) and then move on
	else:
		_show_zone_map()  # retry = tap the node again


func _on_item_bought(_item_id: String) -> void:
	if sfx != null:
		sfx.play("coin")
	_save_all()


func _encounter_index(zone: int, encounter: int) -> int:
	return (zone - 1) * RpgConfig.ENCOUNTERS_PER_ZONE + (encounter - 1)


## --- Eight Letters (EIGHT mode) ----------------------------------------------
##
## A self-contained run on its own board: GameEight holds the state, main ticks
## its timer from _process and translates its signals into board8 calls (the
## same shape the standalone game's main used, namespaced under eight_*).


func _start_eight() -> void:
	var packed: PackedScene = load(BOARD8_SCENE_PATH)
	if packed == null:
		push_error("Main: Eight Letters board missing at %s" % BOARD8_SCENE_PATH)
		return
	_clear_menu_screens()
	ui.visible = false
	# LetterSource snapshots the word list at construction; build it now so the
	# run deals from the tier that is active at mode start.
	letter_source = LetterSource.new(word_db)
	game8 = GameEight.new(word_db, letter_source)
	game8.level_started.connect(_on_eight_level_started)
	game8.word_accepted.connect(_on_eight_word_accepted)
	game8.word_rejected.connect(_on_eight_word_rejected)
	game8.target_reached.connect(_on_eight_target_reached)
	game8.bonus_started.connect(_on_eight_bonus_started)
	game8.bonus_solved.connect(_on_eight_bonus_solved)
	game8.bonus_failed.connect(_on_eight_bonus_failed)
	game8.game_over.connect(_on_eight_game_over)
	board = packed.instantiate()
	add_child(board)
	board.sfx = sfx
	board.submit_requested.connect(_eight_submit_word)
	board.clear_requested.connect(_eight_clear_word)
	board.backspace_requested.connect(_eight_remove_last)
	board.shuffle_requested.connect(_eight_shuffle)
	board.letter_tapped.connect(_eight_append_letter)
	board.how_to_requested.connect(_open_eight_how_to)
	board.play_again_requested.connect(_on_eight_play_again)
	board.menu_requested.connect(_on_eight_to_menu)
	_eight_build_how_to()
	game8.start_run()


## Leave Eight Letters back to the mode menu (reveal MENU button).
func _on_eight_to_menu() -> void:
	game8.timer.stop()
	if is_instance_valid(board):
		board.queue_free()
	board = null
	_show_mode_menu()


## --- Eight input (keyboard + board buttons; single source of truth here) -----


func _eight_unhandled_input(event: InputEvent) -> void:
	if how_to != null and how_to.visible:
		return
	if event.is_action_pressed("submit"):
		_eight_submit_word()
	elif event.is_action_pressed("clear"):
		_eight_clear_word()
	elif event.is_action_pressed("shuffle"):
		_eight_shuffle()
	elif event.is_action_pressed("remove_last"):
		_eight_remove_last()
	elif event is InputEventKey and event.is_pressed() and not event.is_echo():
		var unicode := (event as InputEventKey).unicode
		if unicode >= 65 and unicode <= 90:
			_eight_append_letter(char(unicode))
		elif unicode >= 97 and unicode <= 122:
			_eight_append_letter(char(unicode - 32))


func _eight_accepting_input() -> bool:
	return game8 != null and (game8.state == GameEight.State.PLAYING
		or game8.state == GameEight.State.BONUS)


func _eight_append_letter(letter: String) -> void:
	if not _eight_accepting_input():
		return
	if current_word.length() >= Rules8.LETTER_COUNT:
		return
	if not _eight_letter_available(letter):
		board.show_toast(String(EIGHT_REASON_TEXT["letters_unavailable"]))
		return
	current_word += letter
	board.set_current_word(current_word)
	if sfx != null:
		sfx.play("click")


func _eight_remove_last() -> void:
	if not _eight_accepting_input() or current_word.is_empty():
		return
	current_word = current_word.substr(0, current_word.length() - 1)
	board.set_current_word(current_word)


func _eight_clear_word() -> void:
	if not _eight_accepting_input() or current_word.is_empty():
		return
	current_word = ""
	board.set_current_word(current_word)


## SPACE: display-only tile reorder via the game (pool letters never change),
## so the current word's letters stay valid.
func _eight_shuffle() -> void:
	if not _eight_accepting_input():
		return
	board.set_letters(game8.shuffle_letters())
	board.set_current_word(current_word)


func _eight_submit_word() -> void:
	if not _eight_accepting_input():
		return
	if current_word.is_empty():
		board.show_toast(String(EIGHT_REASON_TEXT["empty"]))
		return
	# Accepted words are cleared in _on_eight_word_accepted; rejected words stay
	# so the player can edit them.
	game8.submit_word(current_word)


func _eight_letter_available(letter: String) -> bool:
	var available := 0
	for pool_letter in game8.letters:
		if String(pool_letter) == letter:
			available += 1
	var usage := {}
	for i in range(current_word.length()):
		var used: String = current_word[i]
		usage[used] = int(usage.get(used, 0)) + 1
	return int(usage.get(letter, 0)) < available


## --- Eight game signal handlers ----------------------------------------------


func _on_eight_level_started(_level: int, letters: Array, target: int) -> void:
	current_word = ""
	board.hide_reveal()
	board.set_bonus_mode(false)
	board.set_level(game8.level)
	board.set_letters(letters)
	board.set_scores(game8.round_score, target)
	board.clear_word_state()
	board.set_time_left(game8.timer.time_left)
	debug_panel.refresh()


func _on_eight_word_accepted(word: String, _points: int) -> void:
	# An 8-letter word also completes the level; "crit" rides on top of the
	# board's own levelup jingle.
	if sfx != null:
		sfx.play("crit" if word.length() >= Rules8.LETTER_COUNT else "accept")
	board.add_found_word(word)
	board.set_scores(game8.round_score, game8.target)
	current_word = ""
	board.set_current_word(current_word)
	debug_panel.refresh()


func _on_eight_word_rejected(_word: String, reason: String) -> void:
	board.show_toast(String(EIGHT_REASON_TEXT.get(reason, "Try again")))


## Emitted for both the target path and the 8-letter instant win.
func _on_eight_target_reached(_level: int, round_score: int) -> void:
	board.celebrate_level(round_score)


func _on_eight_bonus_started(_bonus_number: int, letters: Array) -> void:
	current_word = ""
	board.set_level(game8.level)
	board.set_letters(letters)
	board.clear_word_state()
	board.set_bonus_mode(true)
	board.set_time_left(game8.timer.time_left)
	board.show_toast("BONUS ROUND!", false)
	debug_panel.refresh()


func _on_eight_bonus_solved(points: int) -> void:
	if sfx != null:
		sfx.play("coin")
	board.set_bonus_mode(false)
	board.show_toast("+%d BONUS!" % points, false)


func _on_eight_bonus_failed() -> void:
	board.set_bonus_mode(false)
	board.show_toast("No bonus — on to the next level!", false)


func _on_eight_game_over(total_score: int, level: int, found_words: Array,
		possible_words: Array) -> void:
	_eight_best_score = maxi(_eight_best_score, int(total_score))
	_eight_best_level = maxi(_eight_best_level, int(level))
	_save_all()
	board.show_reveal(found_words, possible_words, int(total_score), int(level),
		_eight_best_score, _eight_best_level)
	debug_panel.refresh()


func _on_eight_play_again() -> void:
	current_word = ""
	game8.start_run()


## --- Eight how-to (pauses the level timer, never restarts it) -----------------


func _eight_build_how_to() -> void:
	how_to = HowToUi.new()
	how_to.closed.connect(_on_eight_how_to_closed)
	how_to.word_set_changed.connect(_on_eight_word_set_changed)
	how_to.sound_toggled.connect(_on_eight_sound_toggled)
	how_to.set_sound(bool(_settings.get("sound", true)))
	add_child(how_to)


func _open_eight_how_to() -> void:
	if how_to == null:
		_eight_build_how_to()
	if how_to.visible:
		return
	game8.timer.pause()
	how_to.set_word_set(word_db.tier())
	how_to.open()


func _on_eight_how_to_closed() -> void:
	game8.timer.resume()


## WORD SET cycler in the eight how-to: swap the shared dictionary tier (the
## arena and campaign read the same word_db), persist it, and deal future eight
## levels from the new set. The current level keeps its letters.
func _on_eight_word_set_changed(tier: String) -> void:
	word_db.set_tier(tier)
	_settings["word_set"] = String(tier).to_lower()
	letter_source = LetterSource.new(word_db)
	game8.set("_letter_source", letter_source)
	_save_all()
	board.show_toast("Word set: %s" % String(tier).to_upper(), false)


## SOUND toggle in the eight how-to: flips the shared mute + setting, so the
## arena and campaign are silent too, and persists it.
func _on_eight_sound_toggled(enabled: bool) -> void:
	_settings["sound"] = bool(enabled)
	if sfx != null:
		sfx.set_muted(not bool(enabled))
	_save_all()
	board.show_toast("Sound %s" % ("ON" if bool(enabled) else "OFF"), false)


## --- Tutorial ---------------------------------------------------------------


func _open_tutorial(first_time: bool, destination: String = TUTORIAL_DEST_ARENA) -> void:
	if is_instance_valid(_tutorial):
		return
	_tutorial_first_time = first_time
	_tutorial_destination = destination
	_tutorial = TutorialScene.instantiate()
	add_child(_tutorial)
	if _tutorial.has_signal("closed"):
		_tutorial.connect("closed", _on_tutorial_closed)
		if _tutorial.has_signal("word_set_changed"):
			_tutorial.connect("word_set_changed", _on_word_set_changed)
		if _tutorial.has_method("set_word_set"):
			_tutorial.call("set_word_set", word_db.tier())
		if _tutorial.has_signal("sound_toggled"):
			_tutorial.connect("sound_toggled", _on_sound_toggled)
			if _tutorial.has_method("set_sound"):
				_tutorial.call("set_sound", bool(_settings.get("sound", true)))
		_tutorial.open()
	else:
		push_warning("Main: tutorial screen has no 'closed' signal; closing it again")
		_on_tutorial_closed()


func _on_tutorial_closed() -> void:
	# tutorial_seen is only ever earned through the RULES flow now: the
	# tutorial no longer auto-opens on boot.
	if _tutorial_first_time or (
			_tutorial_destination == TUTORIAL_DEST_MENU
			and not bool(_settings.get("tutorial_seen", false))):
		_settings["tutorial_seen"] = true
		_save_all()
	_tutorial = null
	if _tutorial_destination == TUTORIAL_DEST_MENU:
		_show_mode_menu()
	elif game.state == GameManager.GameState.PLAYING:
		# Mid-round RULES check: resume exactly where we left off, no restart.
		if timer != null and not timer.is_running():
			timer.resume()
	else:
		game.start_game()


func _open_rules() -> void:
	# Reading the rules mid-round must not cost the player their timer.
	if game.state == GameManager.GameState.PLAYING and timer != null and timer.is_running():
		timer.pause()
	_open_tutorial(false, TUTORIAL_DEST_ARENA)


## WORD SET cycler from the rules panel: swap the dictionary tier, persist the
## choice, and toast on the arena board when it is on screen (menu-rules flow
## just persists).
func _on_word_set_changed(tier: String) -> void:
	word_db.set_tier(tier)
	_settings["word_set"] = tier.to_lower()
	_save_all()
	if ui.visible:
		ui.show_toast("WORD SET: %s" % tier.to_upper())


## SOUND ON/OFF pill from the rules panel: flip the live mute, persist the
## choice, no toast (the button itself is the feedback).
func _on_sound_toggled(enabled: bool) -> void:
	_settings["sound"] = bool(enabled)
	if sfx != null:
		sfx.set_muted(not bool(enabled))
	_save_all()


## --- Feedback channel (mode menu button -> Telegram) -------------------------


## Built on first open so it draws above whatever screen is up, and kept for
## every later open (draft included).
func _open_feedback() -> void:
	if _feedback == null:
		_feedback = FeedbackUi.new()
		_feedback.send_requested.connect(_on_feedback_send_requested)
		add_child(_feedback)
	_feedback.move_to_front()
	_feedback_context = _feedback_context_snapshot()
	_feedback.open(_feedback_context)


## What the player was doing when they tapped FEEDBACK - shown in the overlay
## and sent as the message's first line.
func _feedback_context_snapshot() -> Dictionary:
	if game8 != null:
		return {"mode": "eight", "level": game8.level, "score": game8.total_score}
	if _battle != null:
		return {
			"mode": "campaign",
			"zone": progression.zone,
			"encounter": progression.encounter,
		}
	if game.state == GameManager.GameState.PLAYING:
		return {"mode": "arena", "round": game.current_round, "score": game.total_score}
	return {"mode": "menu"}


## One send in flight, ever: ignored taps while a request is pending, and the
## request node is created once and reused (no leaks). An empty draft is not a
## send.
func _on_feedback_send_requested(text: String) -> void:
	if _feedback_sending:
		return
	var message := String(text).strip_edges()
	if message.is_empty():
		return
	var payload := "[FEEDBACK][arcade] %s\n%s" % [_feedback.context_summary(), message]
	if _feedback_http == null:
		_feedback_http = HTTPRequest.new()
		_feedback_http.timeout = FEEDBACK_TIMEOUT
		_feedback_http.request_completed.connect(_on_feedback_request_completed)
		add_child(_feedback_http)
	var body := "chat_id=%s&text=%s" % [
		TELEGRAM_CHAT_ID.uri_encode(), payload.uri_encode()]
	var err := _feedback_http.request(
		TELEGRAM_SEND_URL,
		PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]),
		HTTPClient.METHOD_POST, body)
	if err != OK:
		# request() refused (busy, bad URL...) and will NOT emit - fail in place.
		_feedback.show_note(FEEDBACK_FAIL_NOTE)
		return
	_feedback_sending = true


## The send landed (or timed out after FEEDBACK_TIMEOUT): success clears the
## draft, thanks the player and closes; anything else keeps the overlay and the
## text so the tap is never wasted. Headless/offline lands here too.
func _on_feedback_request_completed(result: int, response_code: int,
		_headers: PackedStringArray, _body: PackedByteArray) -> void:
	_feedback_sending = false
	if _feedback == null:
		return
	var sent := result == HTTPRequest.RESULT_SUCCESS and response_code == 200
	if sent:
		_feedback.clear_message()
	_feedback.show_note(FEEDBACK_OK_NOTE if sent else FEEDBACK_FAIL_NOTE, sent)


## --- Persistence ------------------------------------------------------------


## One save call for every persist moment: arena totals + settings + campaign +
## Eight Letters bests.
func _save_all() -> void:
	save_data.save(
		int(_saved_totals["total_score"]), int(_saved_totals["highest_round"]),
		_settings, _progression_dict(), _eight_bests_dict())


## Inline serialization of the Eight Letters bests (their own save section).
func _eight_bests_dict() -> Dictionary:
	return {"best_score": _eight_best_score, "best_level": _eight_best_level}


func _save_progress(final_total: int) -> void:
	var highest := maxi(int(_saved_totals["highest_round"]), ScoreManager.TOTAL_ROUNDS)
	_saved_totals["total_score"] = maxi(int(_saved_totals["total_score"]), final_total)
	_saved_totals["highest_round"] = highest
	_save_all()


## Inline serialization of Progression (the logic file itself stays untouched).
func _progression_dict() -> Dictionary:
	if progression == null:
		return {}
	return {
		"level": progression.level,
		"xp": progression.xp,
		"gold": progression.gold,
		"zone": progression.zone,
		"encounter": progression.encounter,
		"upgrades": progression.upgrades.duplicate(),
		"ng_plus": progression.ng_plus,
	}


## Rebuild the campaign state from the save's [rpg] dict (v1 saves / missing
## keys fall back to fresh defaults).
func _restore_progression(rpg: Dictionary) -> Progression:
	var restored := Progression.new()
	restored.level = maxi(1, int(rpg.get("level", 1)))
	restored.xp = maxi(0, int(rpg.get("xp", 0)))
	restored.gold = maxi(0, int(rpg.get("gold", 0)))
	restored.zone = clampi(int(rpg.get("zone", 1)), 1, RpgConfig.TOTAL_ZONES)
	restored.encounter = clampi(int(rpg.get("encounter", 1)), 1, RpgConfig.ENCOUNTERS_PER_ZONE)
	var upgrades: Variant = rpg.get("upgrades", {})
	if upgrades is Dictionary:
		restored.upgrades = (upgrades as Dictionary).duplicate()
	restored.ng_plus = bool(rpg.get("ng_plus", false))
	return restored


## --- Debug hooks (test shortcuts, not gameplay) -----------------------------


func debug_add_score(amount: int) -> void:
	game.total_score += amount
	game.total_score_changed.emit(game.total_score)


func debug_complete_round() -> void:
	timer.stop()
	game.end_round()


func debug_new_round() -> void:
	if game.state == GameManager.GameState.ROUND_COMPLETE:
		var available := game.available_categories()
		if not available.is_empty():
			game.choose_category(int(available[0]))
	elif game.state == GameManager.GameState.PLAYING:
		game.end_round()


func debug_reshuffle() -> void:
	_shuffle()


func debug_reset_game() -> void:
	current_word = ""
	game.reset_game()
