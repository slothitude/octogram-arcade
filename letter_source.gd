class_name LetterSource
extends RefCounted
## Deals levels: knows every 8-letter word in the dictionary, picks one at
## random and hands it out scrambled. The scramble always uses every letter
## of the source word exactly once, and (unless the word is a single repeated
## letter) is guaranteed to differ from the source spelling.

## Fallback RNG for make_letters_from(); pick_random_8() uses its own injected
## RNG so seeded draws stay reproducible.
var _fallback_rng: RandomNumberGenerator

var _eight_words: PackedStringArray = PackedStringArray()


## Loads the 8-letter word list once from `word_db` (anything exposing
## words()). A null or empty database yields an empty source.
func _init(word_db = null) -> void:
	_fallback_rng = RandomNumberGenerator.new()
	_fallback_rng.randomize()
	if word_db == null:
		return
	for entry in word_db.words():
		var word := String(entry)
		if word.length() == Rules8.LETTER_COUNT:
			_eight_words.append(word)
	if _eight_words.is_empty():
		push_warning("LetterSource: dictionary has no 8-letter words")


## True when the source has at least one 8-letter word to deal.
func has_words() -> bool:
	return not _eight_words.is_empty()


## Number of 8-letter words available.
func word_count() -> int:
	return _eight_words.size()


## Pick a random 8-letter dictionary word with the injected RNG.
## Returns {word: String, letters: Array} - letters is the scrambled 8-letter
## array, guaranteed to be in a different order than `word` unless every
## letter is the same character. Returns {} when there is nothing to deal.
func pick_random_8(rng: RandomNumberGenerator) -> Dictionary:
	if _eight_words.is_empty() or rng == null:
		return {}
	var word: String = _eight_words[rng.randi_range(0, _eight_words.size() - 1)]
	return {"word": word, "letters": _scramble(word, rng)}


## The letters of `word` as an 8-entry array of single-character strings,
## scrambled (uses the internal RNG).
func make_letters_from(word: String) -> Array:
	return _scramble(String(word).to_upper(), _fallback_rng)


func _scramble(word: String, rng: RandomNumberGenerator) -> Array:
	var letters: Array = []
	for i in range(word.length()):
		letters.append(word[i])

	var all_same := true
	for i in range(1, letters.size()):
		if letters[i] != letters[0]:
			all_same = false
			break

	# A Fisher-Yates pass can land on the identity permutation; retry a few
	# times so the dealt order differs from the source spelling.
	for attempt in range(16):
		_fisher_yates(letters, rng)
		if all_same:
			break
		var identical := true
		for i in range(letters.size()):
			if letters[i] != word[i]:
				identical = false
				break
		if not identical:
			break
	return letters


func _fisher_yates(letters: Array, rng: RandomNumberGenerator) -> void:
	for i in range(letters.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap = letters[i]
		letters[i] = letters[j]
		letters[j] = swap
