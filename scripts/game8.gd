class_name GameEight
extends RefCounted
## Eight Letters game flow: endless levels dealt as scrambled 8-letter words,
## adaptive targets, a bonus round every BONUS_EVERY levels, and the game-over
## handoff for the reveal. Pure logic (RefCounted, no UI); the UI layer drives
## timer.tick(delta) and listens to the signals.

enum State { PLAYING, LEVEL_COMPLETE, BONUS, GAME_OVER }

signal level_started(level: int, letters: Array, target: int)
signal word_accepted(word: String, points: int)
signal word_rejected(word: String, reason: String)
signal target_reached(level: int, round_score: int)
signal level_completed(level: int)
signal bonus_started(bonus_number: int, letters: Array)
signal bonus_solved(points: int)
signal bonus_failed()
signal game_over(total_score: int, level: int, found_words: Array, possible_words: Array)
signal state_changed(new_state: int)

## Idle until start_run(); GAME_OVER is the only "not playing yet" state.
var state: int = State.GAME_OVER
var level: int = 1
var total_score: int = 0
var round_score: int = 0
var target: int = 0
var letters: Array = []
var found_words: Array = []
var possible_words: Array = []
var possible_points: int = 0
var bonus_number: int = 0
var timer: TimerController
var rng: RandomNumberGenerator

## Tests only: when >= 0 every normal level uses this target instead of the
## adaptive one, so a scripted run can force level completions. -1 disables.
var debug_target_override: int = -1

var _word_db
var _letter_source
var _current_word_hint: String = ""
var _found_set: Dictionary = {}
var _started: bool = false


func _init(word_db, letter_source, injected_rng: RandomNumberGenerator = null) -> void:
	_word_db = word_db
	_letter_source = letter_source
	if injected_rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	else:
		rng = injected_rng
	timer = TimerController.new()
	timer.timeout.connect(on_timer_zero)


## PLAY AGAIN: wipe the run and deal level 1.
func start_run() -> void:
	level = 1
	total_score = 0
	bonus_number = 0
	_started = true
	_begin_level()


## Deal the current level. Every BONUS_EVERY-th level is a bonus round (60s,
## find the 8-letter anagram); every other level enumerates the possible
## words and derives the adaptive target from them (120s).
func _begin_level() -> void:
	var pick := {}
	if _letter_source != null:
		pick = _letter_source.pick_random_8(rng)
	if pick.is_empty():
		push_error("GameEight: letter source dealt nothing; level not started")
		return
	_current_word_hint = String(pick["word"])
	letters = pick["letters"]
	round_score = 0
	found_words = []
	_found_set = {}

	if level % Rules8.BONUS_EVERY == 0:
		bonus_number += 1
		possible_words = []
		possible_points = 0
		target = 0
		_set_state(State.BONUS)
		timer.start(Rules8.BONUS_TIME)
		bonus_started.emit(bonus_number, letters.duplicate())
	else:
		possible_words = Rules8.enumerate_possible_words(letters, _word_db)
		possible_points = 0
		for word in possible_words:
			if String(word).length() < Rules8.LETTER_COUNT:
				possible_points += Rules8.word_score(String(word).length())
		if debug_target_override >= 0:
			target = debug_target_override
		else:
			target = Rules8.compute_target(possible_points, level)
		_set_state(State.PLAYING)
		timer.start(Rules8.LEVEL_TIME)
		level_started.emit(level, letters.duplicate(), target)


## Submit a word for the current level. Checks run in a fixed order so the
## rejection reason is predictable:
##   empty -> invalid_characters -> too_short -> letters_unavailable ->
##   not_in_dictionary -> duplicate
## During a bonus round only the 8-letter anagram itself is accepted; any
## other submission is rejected with "bonus_round".
## Returns {accepted: bool, reason: String, word: String, points: int}.
func submit_word(word: String) -> Dictionary:
	var candidate := String(word).strip_edges().to_upper()
	var result := {
		"accepted": false,
		"reason": "",
		"word": candidate,
		"points": 0,
	}

	if not _started or (state != State.PLAYING and state != State.BONUS):
		result["reason"] = "not_playing"
		return result

	if candidate.is_empty():
		return _reject(result, "empty")

	if state == State.BONUS:
		if candidate == _current_word_hint:
			var points: int = Rules8.BONUS_BASE_POINTS * bonus_number
			total_score += points
			result["accepted"] = true
			result["reason"] = "bonus_solved"
			result["points"] = points
			bonus_solved.emit(points)
			level += 1
			_begin_level()
			return result
		return _reject(result, "bonus_round")

	for i in range(candidate.length()):
		if candidate[i] < "A" or candidate[i] > "Z":
			return _reject(result, "invalid_characters")

	if candidate.length() < Rules8.MIN_WORD_LENGTH:
		return _reject(result, "too_short")

	if not Rules8.can_build(candidate, letters):
		return _reject(result, "letters_unavailable")

	if _word_db == null or not _word_db.is_valid_word(candidate):
		return _reject(result, "not_in_dictionary")

	if _found_set.has(candidate):
		return _reject(result, "duplicate")

	var points: int = Rules8.word_score(candidate.length())
	round_score += points
	total_score += points
	found_words.append(candidate)
	_found_set[candidate] = true
	result["accepted"] = true
	result["reason"] = "ok"
	result["points"] = points
	word_accepted.emit(candidate, points)

	if candidate.length() == Rules8.LETTER_COUNT or round_score >= target:
		_complete_level()
	return result


## Called by the UI layer when the countdown hits zero (the internal
## TimerController is wired here too).
func on_timer_zero() -> void:
	if not _started:
		return
	if state == State.BONUS:
		bonus_failed.emit()
		level += 1
		_begin_level()
	elif state == State.PLAYING:
		timer.stop()
		_set_state(State.GAME_OVER)
		game_over.emit(total_score, level, found_words.duplicate(), possible_words.duplicate())


## A fresh shuffled order of the current letters (tile reorder only).
func shuffle_letters() -> Array:
	var shuffled := letters.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = swap
	return shuffled


## Words found this level (for the game-over reveal).
func found_count() -> int:
	return found_words.size()


## All words that were buildable this level (for the game-over reveal).
func possible_count() -> int:
	return possible_words.size()


## The 8-letter word the current level was dealt from (bonus anagram, and the
## instant-win word). Test/debug introspection only.
func hint_word() -> String:
	return _current_word_hint


func _complete_level() -> void:
	_set_state(State.LEVEL_COMPLETE)
	target_reached.emit(level, round_score)
	level_completed.emit(level)
	level += 1
	_begin_level()


func _reject(result: Dictionary, reason: String) -> Dictionary:
	result["reason"] = reason
	word_rejected.emit(String(result["word"]), reason)
	return result


func _set_state(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(new_state)
