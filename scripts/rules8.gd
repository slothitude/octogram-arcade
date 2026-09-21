class_name Rules8
extends RefCounted
## Pure rules math for Eight Letters: scoring table, adaptive target and the
## possible-words enumeration that sizes the target. No state, no UI.

## Points per accepted word, by length (design8.md scoring table).
const WORD_POINTS := {3: 4, 4: 6, 5: 8, 6: 12, 7: 18, 8: 30}

const MIN_WORD_LENGTH := 3
const LETTER_COUNT := 8

const LEVEL_TIME := 120.0
const BONUS_TIME := 60.0
const BONUS_EVERY := 5
const BONUS_BASE_POINTS := 100

const TARGET_RATIO := 0.16
const TARGET_LEVEL_STEP := 4
const TARGET_MIN := 30
const TARGET_MAX := 160


## Points for a word of `length` letters. Lengths outside the table clamp to
## the nearest end (so a 9+ letter word pays the 8-letter value, shorter than
## MIN_WORD_LENGTH pays nothing).
static func word_score(length: int) -> int:
	if length < MIN_WORD_LENGTH:
		return 0
	var capped: int = mini(length, LETTER_COUNT)
	return int(WORD_POINTS[capped])


## Adaptive target for a level (design8.md):
## clamp(int(possible_points * TARGET_RATIO) + level * TARGET_LEVEL_STEP,
##       TARGET_MIN, TARGET_MAX)
static func compute_target(possible_points: int, level: int) -> int:
	var raw := int(float(possible_points) * TARGET_RATIO) + level * TARGET_LEVEL_STEP
	return clampi(raw, TARGET_MIN, TARGET_MAX)


## All dictionary words that can be built from `letters` (multiset check:
## each letter usable only as often as it appears), sorted by length then
## alphabetically. Includes words of every length from MIN_WORD_LENGTH up to
## letters.size() - the source 8-letter word itself stays in the list so the
## game-over reveal can show it.
static func enumerate_possible_words(letters: Array, word_db) -> Array:
	if word_db == null:
		return []
	var dictionary_words: Array = word_db.words()
	if dictionary_words.is_empty() or letters.is_empty():
		return []

	# 26-slot availability count, indexed by letter code - 'A'. Plain int
	# slots keep the per-word check allocation free.
	var available := PackedInt32Array()
	available.resize(26)
	for letter in letters:
		var code := _letter_code(letter)
		if code >= 0:
			available[code] += 1
	var max_length: int = letters.size()

	var out: Array = []
	var used := PackedInt32Array()
	for entry in dictionary_words:
		var word := String(entry)
		var length := word.length()
		if length < MIN_WORD_LENGTH or length > max_length:
			continue
		var ok := true
		for i in range(length):
			var code := word.unicode_at(i) - 65
			if code < 0 or code > 25 or available[code] <= 0:
				ok = false
				break
			available[code] -= 1
			used.append(code)
		if ok:
			out.append(word)
		for i in range(used.size()):
			available[used[i]] += 1
		used.clear()

	out.sort_custom(_by_length_then_alpha)
	return out


## Milliseconds one enumerate_possible_words() call took (Time.get_ticks_usec
## based), so the level-start budget can be asserted in tests.
static func benchmark_enumeration(letters: Array, word_db) -> float:
	var start := Time.get_ticks_usec()
	enumerate_possible_words(letters, word_db)
	return float(Time.get_ticks_usec() - start) / 1000.0


## True when `word` can be built from `letters` (same multiset rule).
static func can_build(word: String, letters: Array) -> bool:
	var available := {}
	for letter in letters:
		var key := String(letter).to_upper()
		available[key] = int(available.get(key, 0)) + 1
	var candidate := word.to_upper()
	for i in range(candidate.length()):
		var key := candidate[i]
		if int(available.get(key, 0)) <= 0:
			return false
		available[key] = int(available[key]) - 1
	return true


static func _by_length_then_alpha(a: String, b: String) -> bool:
	var la := a.length()
	var lb := b.length()
	if la != lb:
		return la < lb
	return a < b


## Index of a single letter into the 0..25 count array, or -1 when the value
## is not an A-Z letter.
static func _letter_code(letter) -> int:
	var text := String(letter).to_upper()
	if text.length() != 1:
		return -1
	var code := text.unicode_at(0)
	if code < 65 or code > 90:
		return -1
	return code - 65
