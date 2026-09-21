class_name LetterGenerator
extends RefCounted
## Draws letter sets weighted by natural English frequency (Scrabble tile
## counts) and guarantees at least one vowel per set of LETTER_COUNT letters.

const LETTER_COUNT := 8
const VOWELS := ["A", "E", "I", "O", "U"]

## Scrabble tile distribution (letter -> tile count).
const LETTER_WEIGHTS := {
	"A": 9, "B": 2, "C": 2, "D": 4, "E": 12, "F": 2, "G": 3, "H": 2,
	"I": 9, "J": 1, "K": 1, "L": 4, "M": 2, "N": 6, "O": 8, "P": 2,
	"Q": 1, "R": 6, "S": 4, "T": 6, "U": 4, "V": 2, "W": 2, "X": 1,
	"Y": 2, "Z": 1,
}

## Max resample attempts before forcing a vowel into the set. The natural
## chance of a vowel-less 8-letter draw is ~1.1%, so this is never hit in
## practice; it only exists to make the vowel guarantee unconditional.
const MAX_ATTEMPTS := 1000

var _rng: RandomNumberGenerator
var _pool: PackedStringArray = PackedStringArray()


func _init(rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	else:
		_rng = rng
	for letter in LETTER_WEIGHTS:
		for i in range(int(LETTER_WEIGHTS[letter])):
			_pool.append(letter)


## Returns LETTER_COUNT uppercase letters with at least one vowel,
## drawn from the injected RNG.
func generate() -> Array:
	return _generate_with(_rng)


## Deterministic variant for tests: fresh RNG seeded by seed_value,
## never randomized.
func generate_seeded(seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return _generate_with(rng)


func _generate_with(rng: RandomNumberGenerator) -> Array:
	var letters: Array = []
	for attempt in range(MAX_ATTEMPTS):
		letters = _draw_set(rng)
		if _has_vowel(letters):
			return letters
	# Unreachable fallback: force a vowel so the invariant always holds.
	letters[0] = VOWELS[rng.randi_range(0, VOWELS.size() - 1)]
	return letters


func _draw_set(rng: RandomNumberGenerator) -> Array:
	var letters: Array = []
	for i in range(LETTER_COUNT):
		letters.append(_pool[rng.randi_range(0, _pool.size() - 1)])
	return letters


func _has_vowel(letters: Array) -> bool:
	for letter in letters:
		if VOWELS.has(String(letter)):
			return true
	return false
