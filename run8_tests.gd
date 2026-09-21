extends SceneTree
## Eight Letters logic suite. Run:
##   godot --headless --script res://tests/run8_tests.gd


var checks: int = 0
var failures: int = 0


func _init() -> void:
	_summary.call_deferred()


func _summary() -> void:
	await _run_tests()
	print("Ran %d Eight Letters checks: %d passed, %d failed" % [
		checks, checks - failures, failures])
	quit(1 if failures > 0 else 0)


func expect(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _fixture_db() -> WordDatabase:
	return WordDatabase.new("res://data/test8_word_list.txt")


func _run_tests() -> void:
	_test_scoring()
	_test_target()
	_test_letter_source()
	_test_enumeration()
	await _test_real_db_benchmark()
	_test_game_flow()
	_test_save()
	_test_sfx()
	_test_word_set()


func _test_scoring() -> void:
	print("--- scoring table ---")
	for pair in [[3, 4], [4, 6], [5, 8], [6, 12], [7, 18], [8, 30]]:
		expect(Rules8.word_score(pair[0]) == pair[1],
			"word_score(%d) == %d" % [pair[0], pair[1]])
	expect(Rules8.word_score(2) == 0, "word_score(2) == 0")
	expect(Rules8.word_score(9) == 30, "word_score(9) clamps to 8-letter value")


func _test_target() -> void:
	print("--- adaptive target ---")
	expect(Rules8.compute_target(0, 1) == 30, "tiny possible points clamps to TARGET_MIN")
	expect(Rules8.compute_target(100000, 50) == 160, "huge possible points clamps to TARGET_MAX")
	var low: int = Rules8.compute_target(200, 3)
	var high: int = Rules8.compute_target(400, 3)
	expect(high >= low, "target monotonic in possible_points (%d -> %d)" % [low, high])
	var lvl_low: int = Rules8.compute_target(200, 2)
	var lvl_high: int = Rules8.compute_target(200, 9)
	expect(lvl_high > lvl_low, "target monotonic in level (%d -> %d)" % [lvl_low, lvl_high])


func _test_letter_source() -> void:
	print("--- letter source ---")
	var db := _fixture_db()
	var source := LetterSource.new(db)
	expect(source.has_words(), "fixture source has 8-letter words")
	expect(source.word_count() == 1, "fixture source holds exactly LABELING (%d)" % source.word_count())
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var pick := source.pick_random_8(rng)
	expect(String(pick.get("word", "")) == "LABELING", "seeded pick returns LABELING")
	var letters: Array = pick.get("letters", [])
	expect(letters.size() == 8, "8 letters dealt")
	var joined := "".join(letters)
	expect(joined != "LABELING", "scramble differs from source (%s)" % joined)
	var sorted_letters := letters.duplicate()
	sorted_letters.sort()
	var sorted_word := "LABELING".split()
	sorted_word.sort()
	expect("".join(sorted_letters) == "".join(sorted_word), "same multiset as source word")


func _test_enumeration() -> void:
	print("--- enumeration ---")
	var db := _fixture_db()
	var letters: Array = LetterSource.new(db).pick_random_8(_seeded(7)).get("letters")
	var possible: Array = Rules8.enumerate_possible_words(letters, db)
	var expected := ["BAG", "BIG", "BIN", "GIN", "LAB", "LEG", "NAB", "NAG",
		"ABLE", "BAIL", "BALE", "BALL", "BEAN", "GAIN", "GALL",
		"GABLE", "BANGLE", "LABELING"]
	expect(possible.size() == expected.size(),
		"fixture enumeration size %d == %d" % [possible.size(), expected.size()])
	var all_match := true
	for i in range(mini(possible.size(), expected.size())):
		if String(possible[i]) != expected[i]:
			all_match = false
			print("  mismatch at %d: %s vs %s" % [i, possible[i], expected[i]])
			break
	expect(all_match, "enumeration sorted by length then alpha, exact fixture set")
	expect(not possible.has("ZEBRA"), "ZEBRA (unbuildable R) excluded")
	expect(not possible.has("BELONG"), "BELONG (unbuildable O) excluded")


func _test_real_db_benchmark() -> void:
	print("--- real dictionary + benchmark ---")
	var db := WordDatabase.new()
	var source := LetterSource.new(db)
	expect(source.word_count() > 1000, "real db has 8-letter words (%d)" % source.word_count())
	for draw in range(5):
		var pick := source.pick_random_8(_seeded(100 + draw))
		var ms: float = Rules8.benchmark_enumeration(pick.get("letters", []), db)
		expect(ms < 150.0, "enumeration draw %d under 150ms (%.1fms)" % [draw, ms])


func _test_game_flow() -> void:
	print("--- game flow (fixture dictionary) ---")
	var db := _fixture_db()
	var source := LetterSource.new(db)
	var game := GameEight.new(db, source, _seeded(1))
	game.debug_target_override = 40

	game.start_run()
	expect(game.state == GameEight.State.PLAYING, "run starts PLAYING")
	expect(game.letters.size() == 8, "level deals 8 letters")
	expect(game.target == 40, "debug target override honored")

	# Rejection pipeline in order.
	expect(game.submit_word("").reason == "empty", "empty rejected")
	expect(game.submit_word("BA G").reason == "invalid_characters", "space rejected as invalid_characters")
	expect(game.submit_word("CA").reason == "too_short", "too_short rejected")
	expect(game.submit_word("ZEBRA").reason == "letters_unavailable", "unbuildable rejected letters_unavailable")
	expect(game.submit_word("GABN").reason == "not_in_dictionary", "buildable non-word rejected not_in_dictionary")

	var r := game.submit_word("bag")
	expect(bool(r.accepted) and int(r.points) == 4, "BAG accepted for 4")
	expect(game.submit_word("BAG").reason == "duplicate", "duplicate rejected same level")

	# Grind to the target: 4+4+4+4+4+4+4+4+6+6 = 44 >= 40.
	for word in ["BIG", "BIN", "GIN", "LAB", "LEG", "NAB", "NAG", "GALL"]:
		game.submit_word(word)
	game.submit_word("BALL")
	expect(game.level == 2, "target reached -> level 2 (score %d)" % game.round_score)
	expect(game.state == GameEight.State.PLAYING, "level 2 playing")

	# Duplicates clear between levels; 8-letter word completes instantly.
	r = game.submit_word("BAG")
	expect(bool(r.accepted), "BAG allowed again on a fresh level")
	r = game.submit_word("LABELING")
	expect(bool(r.accepted) and int(r.points) == 30, "8-letter word accepted for 30")
	expect(game.level == 3, "8-letter word completes the level instantly")

	# Levels 3 and 4 (44 points clears the 40 target), then level 5 is a bonus round.
	for word in ["BANGLE", "GABLE", "ABLE", "BEAN", "BALE", "BAIL"]:
		game.submit_word(word)
	expect(game.level == 4, "level 3 cleared via target")
	for word in ["BANGLE", "GABLE", "ABLE", "BEAN", "BALE", "BAIL"]:
		game.submit_word(word)
	expect(game.level == 5, "level 4 cleared via target")
	expect(game.state == GameEight.State.BONUS, "level 5 is a BONUS round")
	expect(game.bonus_number == 1, "first bonus round")
	expect(game.submit_word("BANGLE").reason == "bonus_round", "non-anagram rejected during bonus")
	r = game.submit_word("LABELING")
	expect(bool(r.accepted) and int(r.points) == 100, "anagram solved for 100")
	expect(game.level == 6 and game.state == GameEight.State.PLAYING,
		"bonus solved -> level 6 PLAYING")

	# Game over path with a fresh game (bonus failure is penalty-free).
	var game2 := GameEight.new(db, source, _seeded(2))
	game2.debug_target_override = 30
	game2.start_run()
	for level_i in range(4):
		for word in ["BANGLE", "GABLE", "ABLE", "BEAN"]:
			game2.submit_word(word)
	expect(game2.state == GameEight.State.BONUS, "second game reaches bonus at level 5")
	game2.timer.set("time_left", 0.01)
	game2.timer.tick(0.02)
	expect(game2.level == 6 and game2.state == GameEight.State.PLAYING,
		"bonus timeout is penalty-free -> level 6")
	game2.timer.set("time_left", 0.01)
	game2.timer.tick(0.02)
	expect(game2.state == GameEight.State.GAME_OVER, "playing timeout -> GAME_OVER")
	expect(game2.total_score > 0, "score accumulated (%d)" % game2.total_score)


func _test_save() -> void:
	print("--- save data ---")
	var sd := SaveData.new()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveData.SAVE_PATH))
	var fresh: Dictionary = sd.load_data()
	expect(int(fresh.get("best_score", -1)) == 0 and int(fresh.get("best_level", -1)) == 0,
		"missing file yields defaults")
	expect(bool(sd.save(4321, 12, {"sound": true})), "save writes cleanly")
	var loaded: Dictionary = sd.load_data()
	expect(int(loaded.get("best_score", 0)) == 4321, "best_score round trips")
	expect(int(loaded.get("best_level", 0)) == 12, "best_level round trips")
	expect(bool(loaded.get("settings", {}).get("sound", false)), "settings round trip")
	var f := FileAccess.open(ProjectSettings.globalize_path(SaveData.SAVE_PATH), FileAccess.WRITE)
	f.store_string("not a config file {{{")
	f.close()
	expect(int(sd.load_data().get("best_score", -1)) == 0, "corrupt file yields defaults")


func _test_sfx() -> void:
	print("--- sfx manager ---")
	var sfx := SfxManager.new()
	root.add_child(sfx)
	var all_played := true
	for sound_name in ["accept", "bonus", "click", "coin", "crit", "eat",
			"gameover", "levelup", "reject", "victory"]:
		all_played = all_played and sfx.play(sound_name)
	expect(all_played, "all 10 sfx names play headless")
	expect(sfx.play("mystery") == false, "unknown sfx name is a no-op")
	sfx.set_muted(true)
	expect(sfx.play("click") == false, "muted play is a no-op")
	sfx.set_muted(false)
	expect(sfx.play("click") == true, "set_muted(false) restores playback")
	sfx.queue_free()


func _test_word_set() -> void:
	print("--- word tiers ---")
	var db := WordDatabase.new()
	expect(db.tier() == "" and not db.is_common(),
		"default db has no tier until set_tier (%s)" % db.tier())

	db.set_tier("common")
	expect(db.tier() == "common" and db.is_common(), "set_tier(common) -> tier/is_common")
	expect(db.is_valid_word("HOUSE"), "HOUSE valid in COMMON")
	expect(not db.is_valid_word("AAHED"), "AAHED invalid in COMMON")
	expect(db.is_valid_word("THEATRES"), "THEATRES valid in COMMON")

	db.set_tier("standard")
	expect(db.tier() == "standard" and not db.is_common(), "set_tier(standard) active")
	expect(db.word_count() == 41092, "STANDARD holds 41092 words (%d)" % db.word_count())

	db.set_tier("expert")
	expect(db.tier() == "expert" and not db.is_common(), "set_tier(expert) active")
	expect(db.is_valid_word("AAHED"), "AAHED valid in EXPERT")
	expect(db.word_count() == 104251, "EXPERT holds 104251 words (%d)" % db.word_count())

	# Same-tier set_tier is a no-op; a bogus tier warns and changes nothing.
	db.set_tier("expert")
	expect(db.tier() == "expert" and db.word_count() == 104251,
		"set_tier on the active tier is a no-op")
	db.set_tier("gibberish")
	expect(db.tier() == "expert" and db.word_count() == 104251,
		"bogus tier keeps the active EXPERT list")

	# Legacy two-set alias still drives COMMON <-> EXPERT.
	db.use_common(true)
	expect(db.tier() == "common" and db.is_common(), "use_common(true) -> COMMON tier")
	db.use_common(false)
	expect(db.tier() == "expert" and not db.is_common(), "use_common(false) -> EXPERT tier")

	var common_db := WordDatabase.new()
	common_db.set_tier("common")
	var common_source := LetterSource.new(common_db)
	expect(common_source.word_count() == 7458,
		"COMMON letter source deals 7458 8-letter words (%d)" % common_source.word_count())

	# Fixture-based suites keep their custom list: tiers never touch it.
	var fixture := _fixture_db()
	expect(fixture.tier() == "" and fixture.is_valid_word("LABELING"),
		"fixture db keeps its custom list, no tier")

	var letters: Array = LetterSource.new(_fixture_db()).pick_random_8(_seeded(7)).get("letters")
	var possible: Array = Rules8.enumerate_possible_words(letters, common_db)
	var all_buildable := true
	for word in possible:
		if not Rules8.can_build(String(word), letters) or not common_db.is_valid_word(String(word)):
			all_buildable = false
			break
	expect(possible.size() > 0 and all_buildable,
		"COMMON enumeration of fixture letters is a buildable subset (%d words)" % possible.size())


func _seeded(value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = value
	return rng
