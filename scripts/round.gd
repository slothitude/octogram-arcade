class_name RoundManager
extends RefCounted
## One round of word building: validates submissions against the round's
## letters and the dictionary, tracks this round's accepted words.

signal word_accepted(word: String, bonus: int, letter_points: int)
signal word_rejected(word: String, reason: String)

var round_number: int = 0
var letters: Array = []
var submitted_words: Array = []
var last_word: String = ""
var _word_set: Dictionary = {}


## (Re)initialise the round. Clears the word list and last word.
func setup(round_number: int, letters: Array) -> void:
	self.round_number = round_number
	self.letters = letters.duplicate()
	submitted_words = []
	last_word = ""
	_word_set = {}


## True when `word` can be built from the round's letters (multiset check:
## each letter tile may be used once per word, but tiles refresh between
## words, so the pool itself is never consumed).
func can_build(word: String) -> bool:
	var available := {}
	for letter in letters:
		var letter_key := String(letter).to_upper()
		available[letter_key] = int(available.get(letter_key, 0)) + 1
	var candidate := word.strip_edges().to_upper()
	for i in range(candidate.length()):
		var letter_key := candidate[i]
		if int(available.get(letter_key, 0)) <= 0:
			return false
		available[letter_key] = int(available[letter_key]) - 1
	return true


## Validate and (maybe) record a submission. Checks run in a fixed order so
## the rejection reason is predictable:
##   empty -> invalid_characters -> too_short -> letters_unavailable ->
##   not_in_dictionary -> duplicate
## Returns {accepted: bool, reason: String, word: String, bonus: int,
##          letter_points: int}.
func submit_word(word: String, word_db: WordDatabase) -> Dictionary:
	var candidate := word.strip_edges().to_upper()
	var result := {
		"accepted": false,
		"reason": "",
		"word": candidate,
		"bonus": 0,
		"letter_points": 0,
	}

	if candidate.is_empty():
		return _reject(result, "empty")

	for i in range(candidate.length()):
		if candidate[i] < "A" or candidate[i] > "Z":
			return _reject(result, "invalid_characters")

	if candidate.length() < ScoreManager.MIN_WORD_LENGTH:
		return _reject(result, "too_short")

	if not can_build(candidate):
		return _reject(result, "letters_unavailable")

	if not word_db.is_valid_word(candidate):
		return _reject(result, "not_in_dictionary")

	if _word_set.has(candidate):
		return _reject(result, "duplicate")

	var bonus := ScoreManager.word_bonus(candidate.length())
	var letter_points := ScoreManager.letter_sum(candidate)
	submitted_words.append(candidate)
	_word_set[candidate] = true
	last_word = candidate

	result["accepted"] = true
	result["bonus"] = bonus
	result["letter_points"] = letter_points
	word_accepted.emit(candidate, bonus, letter_points)
	return result


func _reject(result: Dictionary, reason: String) -> Dictionary:
	result["reason"] = reason
	word_rejected.emit(String(result["word"]), reason)
	return result
