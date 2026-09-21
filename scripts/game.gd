class_name GameManager
extends RefCounted
## Owns the whole game flow: 6 rounds, one category banked per round.
## Pure logic - the UI layer drives it and listens to its signals.

signal state_changed(old_state: int, new_state: int)
signal round_started(round_number: int, letters: Array)
signal total_score_changed(new_total: int)
signal word_accepted(word: String, bonus: int, letter_points: int)
signal round_ended(round_number: int, category_scores: Dictionary)
signal category_chosen(category: int, points: int)
signal game_complete(final_total: int)

enum GameState { MENU, ROUND_START, PLAYING, WORD_SUBMITTED, ROUND_COMPLETE, GAME_COMPLETE }

var state: int = GameState.MENU
var total_score: int = 0
var current_round: int = 0
var used_categories: Array = []
var round_history: Array = []
var letters: Array = []
var current_words: Array = []
var word_db: WordDatabase
var letter_gen: LetterGenerator

var _round: RoundManager
var _round_bonus_points: int = 0


func _init() -> void:
	_round = RoundManager.new()
	_round.word_accepted.connect(_on_round_word_accepted)


## Wire up the collaborators. State starts (or returns to) MENU.
func setup(db: WordDatabase, gen: LetterGenerator) -> void:
	word_db = db
	letter_gen = gen
	state = GameState.MENU


## PLAY AGAIN / new game: wipes scores and history, starts round 1.
func start_game() -> void:
	if not _is_ready():
		return
	total_score = 0
	used_categories = []
	round_history = []
	current_round = 1
	total_score_changed.emit(total_score)
	_begin_round()


## Alias of start_game() for the PLAY AGAIN button.
func reset_game() -> void:
	start_game()


## Submit a word for the current round. Only valid while PLAYING.
## Returns the RoundManager result dictionary:
## {accepted, reason, word, bonus, letter_points}
func submit_word(word: String) -> Dictionary:
	if state != GameState.PLAYING or not _is_ready():
		return {
			"accepted": false,
			"reason": "not_playing",
			"word": word.strip_edges().to_upper(),
			"bonus": 0,
			"letter_points": 0,
		}
	var result := _round.submit_word(word, word_db)
	if bool(result["accepted"]):
		var accepted_word := String(result["word"])
		current_words.append(accepted_word)
		total_score += int(result["bonus"])
		total_score_changed.emit(total_score)
		word_accepted.emit(accepted_word, int(result["bonus"]), int(result["letter_points"]))
	return result


## Close the current round (timer hit zero, or debug "complete round").
func end_round() -> void:
	if state != GameState.PLAYING or not _is_ready():
		return
	total_score += ScoreManager.ROUND_COMPLETE_BONUS
	total_score_changed.emit(total_score)
	_set_state(GameState.ROUND_COMPLETE)
	round_ended.emit(current_round, ScoreManager.all_category_scores(current_words))


## Bank one category for the current round. Only once per category per game,
## and only while ROUND_COMPLETE. Advances to the next round, or finishes
## the game after the last round.
func choose_category(category: int) -> void:
	if state != GameState.ROUND_COMPLETE or not _is_ready():
		return
	if used_categories.has(category):
		return
	var points := ScoreManager.category_score(category, current_words)
	total_score += points
	total_score_changed.emit(total_score)
	used_categories.append(category)
	round_history.append({
		"round": current_round,
		"category": category,
		"category_points": points,
		"bonus_points": _round_bonus_points,
	})
	category_chosen.emit(category, points)

	if current_round >= ScoreManager.TOTAL_ROUNDS:
		_set_state(GameState.GAME_COMPLETE)
		game_complete.emit(total_score)
	else:
		current_round += 1
		_begin_round()


## Categories still available to bank (all six minus the used ones).
func available_categories() -> Array:
	var available: Array = []
	for category in ScoreManager.category_ids():
		if not used_categories.has(category):
			available.append(category)
	return available


## Best single-category value over the current round's words.
func best_category_value() -> int:
	return ScoreManager.best_category_value(current_words)


## Sum of all six category values over the current round's words.
func category_potential() -> int:
	return ScoreManager.category_potential(current_words)


func _begin_round() -> void:
	if letter_gen == null:
		push_error("GameManager: letter generator not set up; cannot start round")
		return
	letters = letter_gen.generate()
	current_words = []
	_round_bonus_points = 0
	_round.setup(current_round, letters)
	_set_state(GameState.ROUND_START)
	_set_state(GameState.PLAYING)
	round_started.emit(current_round, letters)


func _on_round_word_accepted(word: String, bonus: int, letter_points: int) -> void:
	_round_bonus_points += bonus


func _set_state(new_state: int) -> void:
	if state == new_state:
		return
	var old_state := state
	state = new_state
	state_changed.emit(old_state, new_state)


func _is_ready() -> bool:
	if word_db == null or letter_gen == null:
		push_error("GameManager: setup(db, gen) must be called first")
		return false
	return true
