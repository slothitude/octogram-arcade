class_name SaveData
extends RefCounted
## Local persistence in user:// (ConfigFile). Never crashes: missing or
## corrupt files simply yield defaults.
##
## Schema v2: [game] arena totals + [rpg] campaign progress + [eight] Eight
## Letters bests + [settings]. Files without an [rpg] / [eight] section (v1
## saves) load with defaults for the missing parts.

const SAVE_PATH := "user://save.cfg"
const RPG_VERSION := 2


## rpg is the campaign dict {level, xp, gold, zone, encounter, upgrades, ng_plus}.
## Passing nothing (the old 3-arg call) writes no [rpg] section, so the file
## reads back as a v1 save with rpg defaults.
## eight is {best_score, best_level} — the Eight Letters bests. Omitting it (the
## old 3-arg call) mirrors the two arena totals into [eight], so legacy bare
## call sites still round-trip bests; Main always passes both dicts explicitly.
func save(total_score: int, highest_round: int, settings: Dictionary,
		rpg: Dictionary = {}, eight: Dictionary = {}) -> bool:
	var config := ConfigFile.new()
	config.set_value("game", "total_score", total_score)
	config.set_value("game", "highest_round", highest_round)
	for key in settings:
		config.set_value("settings", String(key), settings[key])
	if not rpg.is_empty():
		for key in rpg:
			if key != "version":
				config.set_value("rpg", String(key), rpg[key])
		config.set_value("rpg", "version", RPG_VERSION)
	var bests := eight
	if bests.is_empty():
		bests = {"best_score": total_score, "best_level": highest_round}
	config.set_value("eight", "best_score", int(bests.get("best_score", 0)))
	config.set_value("eight", "best_level", int(bests.get("best_level", 0)))
	return config.save(SAVE_PATH) == OK


## Always returns {total_score, highest_round, best_score, best_level, settings,
## rpg}, where rpg is {version, level, xp, gold, zone, encounter, upgrades,
## ng_plus}.
func load_data() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return _defaults()
	var settings := {}
	if config.has_section("settings"):
		var keys := config.get_section_keys("settings")
		if keys != null:
			for key in keys:
				settings[key] = config.get_value("settings", key)
	var rpg := default_rpg()
	if config.has_section("rpg"):
		rpg["level"] = int(config.get_value("rpg", "level", 1))
		rpg["xp"] = int(config.get_value("rpg", "xp", 0))
		rpg["gold"] = int(config.get_value("rpg", "gold", 0))
		rpg["zone"] = int(config.get_value("rpg", "zone", 1))
		rpg["encounter"] = int(config.get_value("rpg", "encounter", 1))
		rpg["upgrades"] = Dictionary(config.get_value("rpg", "upgrades", {}))
		rpg["ng_plus"] = bool(config.get_value("rpg", "ng_plus", false))
		rpg["version"] = int(config.get_value("rpg", "version", RPG_VERSION))
	return {
		"total_score": int(config.get_value("game", "total_score", 0)),
		"highest_round": int(config.get_value("game", "highest_round", 0)),
		"best_score": int(config.get_value("eight", "best_score", 0)),
		"best_level": int(config.get_value("eight", "best_level", 0)),
		"settings": settings,
		"rpg": rpg,
	}


## Canonical v2 campaign defaults (fresh save, or a v1 file migrating forward).
static func default_rpg() -> Dictionary:
	return {
		"version": RPG_VERSION,
		"level": 1,
		"xp": 0,
		"gold": 0,
		"zone": 1,
		"encounter": 1,
		"upgrades": {},
		"ng_plus": false,
	}


func _defaults() -> Dictionary:
	return {
		"total_score": 0,
		"highest_round": 0,
		"best_score": 0,
		"best_level": 0,
		"settings": {},
		"rpg": default_rpg(),
	}
