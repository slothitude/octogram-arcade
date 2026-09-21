class_name WordDatabase
extends RefCounted
## Local dictionary. Loads a plain text word list (one word per line).
## Word validation is deterministic and fully offline.
## Three nested SCOWL tiers: COMMON (everyday words) ⊂ STANDARD (full dictionary
## standard) ⊂ EXPERT (deep dictionary, US & UK spellings).

const DEFAULT_WORD_LIST_PATH := "res://data/word_list.txt"

const TIER_PATHS := {
	"common": "res://data/scowl_common.txt",
	"standard": "res://data/scowl_standard.txt",
	"expert": "res://data/scowl_expert.txt",
}

var current_tier := ""
var using_common := false

var _words: Dictionary = {}


func _init(path: String = DEFAULT_WORD_LIST_PATH) -> void:
	_load_words(path)


## Switch the dictionary tier: "common", "standard" or "expert".
## A bogus tier warns and leaves the dictionary untouched; re-selecting the
## active tier is a no-op (no reload).
func set_tier(tier: String) -> void:
	var key := tier.strip_edges().to_lower()
	if not TIER_PATHS.has(key):
		push_warning("WordDatabase: unknown word tier '%s' (expected common/standard/expert)" % tier)
		return
	if key == current_tier:
		return
	current_tier = key
	using_common = key == "common"
	_load_words(TIER_PATHS[key])


## The active tier name ("" while the constructor's default list is loaded).
func tier() -> String:
	return current_tier


## Legacy alias: true -> COMMON, false -> EXPERT.
func use_common(on: bool) -> void:
	set_tier("common" if on else "expert")


func is_common() -> bool:
	return using_common


func words() -> Array:
	return _words.keys()


func is_valid_word(word: String) -> bool:
	return _words.has(word.strip_edges().to_upper())


func word_count() -> int:
	return _words.size()


## (Re)fill the dictionary from the given path; an unreadable file empties it.
func _load_words(path: String) -> void:
	_words = {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("WordDatabase: could not open word list at %s (error %d) - dictionary is empty" % [
			path, FileAccess.get_open_error()
		])
		return
	while not file.eof_reached():
		var line := file.get_line().strip_edges().to_upper()
		if line.is_empty():
			continue
		_words[line] = true
	file.close()
