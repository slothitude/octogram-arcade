class_name ScoreManager
extends RefCounted
## Pure static scoring math. Every tunable value is a constant.

enum Category { THREE_LETTERS, FOUR_LETTERS, FIVE_PLUS, FULL_HOUSE, FLUSH, WILD }

const LETTER_VALUES := {
	"A": 1, "B": 3, "C": 3, "D": 2, "E": 1, "F": 4, "G": 2, "H": 4,
	"I": 1, "J": 8, "K": 5, "L": 1, "M": 3, "N": 1, "O": 1, "P": 3,
	"Q": 10, "R": 1, "S": 1, "T": 1, "U": 1, "V": 4, "W": 4, "X": 8,
	"Y": 4, "Z": 10,
}

const WORD_SCORE_3 := 4
const WORD_SCORE_4 := 6
const WORD_SCORE_5_PLUS := 8

const FULL_HOUSE_TIER1_COUNT := 15
const FULL_HOUSE_TIER1_POINTS := 50
const FULL_HOUSE_TIER2_COUNT := 25
const FULL_HOUSE_TIER2_POINTS := 150

const FLUSH_MULTIPLIER := 10

const WILD_POINTS := {3: 1, 4: 2, 5: 5, 6: 7, 7: 10, 8: 15}

const LONG_WORD_BONUS := 50
const LONG_WORD_MIN_LENGTH := 7
const ALL_LETTERS_BONUS := 25

const ROUND_COMPLETE_BONUS := 10

const MIN_WORD_LENGTH := 3
const LETTER_COUNT := 8
const ROUND_TIME := 90.0
const TOTAL_ROUNDS := 6


## Sum of letter values for a word. Unknown characters count 0.
static func letter_sum(word: String) -> int:
	var total := 0
	var upper := word.to_upper()
	for i in range(upper.length()):
		total += int(LETTER_VALUES.get(upper[i], 0))
	return total


## Immediate bonus for a word of the given length:
## 7 letters -> 50, 8 letters -> 75 (long word + all-letters), else 0.
static func word_bonus(word_length: int) -> int:
	if word_length < LONG_WORD_MIN_LENGTH:
		return 0
	if word_length >= LETTER_COUNT:
		return LONG_WORD_BONUS + ALL_LETTERS_BONUS
	return LONG_WORD_BONUS


## Points a category would score for the given list of words.
static func category_score(category: int, words: Array) -> int:
	match category:
		Category.THREE_LETTERS:
			return _count_length(words, 3) * WORD_SCORE_3
		Category.FOUR_LETTERS:
			return _count_length(words, 4) * WORD_SCORE_4
		Category.FIVE_PLUS:
			return _count_min_length(words, 5) * WORD_SCORE_5_PLUS
		Category.FULL_HOUSE:
			var count := words.size()
			if count >= FULL_HOUSE_TIER2_COUNT:
				return FULL_HOUSE_TIER2_POINTS
			if count >= FULL_HOUSE_TIER1_COUNT:
				return FULL_HOUSE_TIER1_POINTS
			return 0
		Category.FLUSH:
			var first_letter_counts := {}
			for word in words:
				var cleaned := String(word).strip_edges().to_upper()
				if cleaned.is_empty():
					continue
				var first := cleaned[0]
				first_letter_counts[first] = int(first_letter_counts.get(first, 0)) + 1
			var best := 0
			for letter in first_letter_counts:
				best = maxi(best, int(first_letter_counts[letter]))
			return best * FLUSH_MULTIPLIER
		Category.WILD:
			var total := 0
			for word in words:
				total += int(WILD_POINTS.get(String(word).length(), 0))
			return total
	return 0


## All six categories -> score, keyed by Category enum int.
static func all_category_scores(words: Array) -> Dictionary:
	var result := {}
	for category in category_ids():
		result[category] = category_score(category, words)
	return result


## Highest single-category value available for this word list.
static func best_category_value(words: Array) -> int:
	var best := 0
	var scores := all_category_scores(words)
	for category in scores:
		best = maxi(best, int(scores[category]))
	return best


## Sum of all six category values (upper bound if every category were banked).
static func category_potential(words: Array) -> int:
	var total := 0
	var scores := all_category_scores(words)
	for category in scores:
		total += int(scores[category])
	return total


## The six Category enum ids in declaration order.
static func category_ids() -> Array:
	return [
		Category.THREE_LETTERS,
		Category.FOUR_LETTERS,
		Category.FIVE_PLUS,
		Category.FULL_HOUSE,
		Category.FLUSH,
		Category.WILD,
	]


static func _count_length(words: Array, length: int) -> int:
	var count := 0
	for word in words:
		if String(word).length() == length:
			count += 1
	return count


static func _count_min_length(words: Array, min_length: int) -> int:
	var count := 0
	for word in words:
		if String(word).length() >= min_length:
			count += 1
	return count
