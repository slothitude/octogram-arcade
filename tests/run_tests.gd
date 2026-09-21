extends SceneTree
## Headless test battery for the Octogram logic layer.
## Run with:
##   godot --headless --path <project> --script res://tests/run_tests.gd
## Exits 0 when every check passes, 1 otherwise.

const TEST_WORD_LIST := "res://data/test_word_list.txt"

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	_test_word_database()
	_test_letter_generator()
	_test_score_manager()
	_test_round_manager()
	_test_timer_controller()
	_test_game_manager()
	_test_game_manager_long_word_bonus()
	_test_save_data()
	print("")
	print("Ran %d checks: %d passed, %d failed" % [_checks, _checks - _failures, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, check_name: String, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("PASS: " + check_name)
	else:
		_failures += 1
		print("FAIL: " + check_name + ((" - " + detail) if detail != "" else ""))


func _check_eq(actual, expected, check_name: String) -> void:
	_check(actual == expected, check_name, "expected %s, got %s" % [str(expected), str(actual)])


func _has_vowel(letters: Array) -> bool:
	for letter in letters:
		if LetterGenerator.VOWELS.has(String(letter)):
			return true
	return false


func _load_fixture_words() -> Array:
	var words: Array = []
	var file := FileAccess.open(TEST_WORD_LIST, FileAccess.READ)
	if file == null:
		return words
	while not file.eof_reached():
		var line := file.get_line().strip_edges().to_upper()
		if not line.is_empty():
			words.append(line)
	file.close()
	return words


# ---------------------------------------------------------------- suite 1

func _test_word_database() -> void:
	var db := WordDatabase.new(TEST_WORD_LIST)
	_check(db.word_count() > 0, "word_database loads fixture (%d words)" % db.word_count())
	_check(db.is_valid_word("CAT"), "word_database accepts CAT")
	_check(db.is_valid_word("cat"), "word_database accepts lowercase cat")
	_check(db.is_valid_word("  cat  "), "word_database trims surrounding whitespace")
	_check(not db.is_valid_word("ZZZZZ"), "word_database rejects ZZZZZ")
	_check(not db.is_valid_word(""), "word_database rejects empty string")
	var missing := WordDatabase.new("res://data/definitely_missing_words.txt")
	_check(missing.word_count() == 0, "word_database missing file -> empty dictionary")
	_check(not missing.is_valid_word("CAT"), "word_database missing file -> rejects everything")


# ---------------------------------------------------------------- suite 2

func _test_letter_generator() -> void:
	var gen := LetterGenerator.new()
	var letters: Array = gen.generate_seeded(12345)
	_check_eq(letters.size(), ScoreManager.LETTER_COUNT, "letter_generator seeded draw has 8 letters")
	var all_upper := true
	for letter in letters:
		var s := String(letter)
		if s.length() != 1 or s < "A" or s > "Z":
			all_upper = false
	_check(all_upper, "letter_generator letters all A-Z (%s)" % str(letters))

	var vowel_ok := true
	for i in range(200):
		var draw: Array = gen.generate_seeded(1000 + i)
		if draw.size() != ScoreManager.LETTER_COUNT or not _has_vowel(draw):
			vowel_ok = false
	_check(vowel_ok, "letter_generator 200 seeded sets all have >= 1 vowel")

	var counts := {}
	for i in range(2000):
		var draw: Array = gen.generate_seeded(50000 + i)
		for letter in draw:
			counts[letter] = int(counts.get(letter, 0)) + 1
	var e_count := int(counts.get("E", 0))
	var x_count := int(counts.get("X", 0))
	_check(e_count > x_count, "letter_generator E drawn more often than X (E=%d, X=%d)" % [e_count, x_count])

	_check(gen.generate_seeded(777) == gen.generate_seeded(777),
		"letter_generator same seed reproduces same set (no randomize)")

	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 99
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 99
	var gen_a := LetterGenerator.new(rng_a)
	var gen_b := LetterGenerator.new(rng_b)
	_check_eq(gen_a.generate(), gen_b.generate(),
		"letter_generator injected seeded RNG drives generate() deterministically")


# ---------------------------------------------------------------- suite 3

func _test_score_manager() -> void:
	_check_eq(ScoreManager.letter_sum("QUIZ"), 22, "score letter_sum(QUIZ) == 22")
	_check_eq(ScoreManager.letter_sum("cat"), 5, "score letter_sum(cat) == 5")
	_check_eq(ScoreManager.letter_sum("C4T!"), 4, "score unknown chars count 0")

	_check_eq(ScoreManager.word_bonus(3), 0, "score word_bonus(3) == 0")
	_check_eq(ScoreManager.word_bonus(4), 0, "score word_bonus(4) == 0")
	_check_eq(ScoreManager.word_bonus(5), 0, "score word_bonus(5) == 0")
	_check_eq(ScoreManager.word_bonus(6), 0, "score word_bonus(6) == 0")
	_check_eq(ScoreManager.word_bonus(7), 50, "score word_bonus(7) == 50")
	_check_eq(ScoreManager.word_bonus(8), 75, "score word_bonus(8) == 75")

	var mixed := ["CAT", "DOG", "SUN", "BIRD", "QUIZ", "HORSE", "APPLE"]
	_check_eq(ScoreManager.category_score(ScoreManager.Category.THREE_LETTERS, mixed), 12,
		"score THREE_LETTERS: 3 x 4 == 12")
	_check_eq(ScoreManager.category_score(ScoreManager.Category.FOUR_LETTERS, mixed), 12,
		"score FOUR_LETTERS: 2 x 6 == 12")
	_check_eq(ScoreManager.category_score(ScoreManager.Category.FIVE_PLUS, mixed), 16,
		"score FIVE_PLUS: 2 x 8 == 16")

	var fourteen := []
	for i in range(14):
		fourteen.append("CAT")
	var fifteen := fourteen.duplicate()
	fifteen.append("DOG")
	var twenty_four := fourteen.duplicate()
	for i in range(10):
		twenty_four.append("DOG")
	var twenty_five := twenty_four.duplicate()
	twenty_five.append("CUP")
	_check_eq(ScoreManager.category_score(ScoreManager.Category.FULL_HOUSE, fourteen), 0,
		"score FULL_HOUSE at 14 words == 0")
	_check_eq(ScoreManager.category_score(ScoreManager.Category.FULL_HOUSE, fifteen), 50,
		"score FULL_HOUSE at 15 words == 50")
	_check_eq(ScoreManager.category_score(ScoreManager.Category.FULL_HOUSE, twenty_four), 50,
		"score FULL_HOUSE at 24 words == 50")
	_check_eq(ScoreManager.category_score(ScoreManager.Category.FULL_HOUSE, twenty_five), 150,
		"score FULL_HOUSE at 25 words == 150")

	var flush_list := ["SUN", "SIT", "SET", "SAD", "BAT", "BET", "BIG"]
	_check_eq(ScoreManager.category_score(ScoreManager.Category.FLUSH, flush_list), 40,
		"score FLUSH 4 x S beats 3 x B == 40")
	var tie_list := ["SUN", "SIT", "SET", "BAT", "BET", "BIG"]
	_check_eq(ScoreManager.category_score(ScoreManager.Category.FLUSH, tie_list), 30,
		"score FLUSH tie 3/3 == 3 x 10 == 30")
	_check_eq(ScoreManager.category_score(ScoreManager.Category.FLUSH, []), 0,
		"score FLUSH empty word list == 0")

	var by_length := {"CAT": 1, "BIRD": 2, "HORSE": 5, "ORANGE": 7, "MONKEYS": 10, "BASEBALL": 15}
	var wild_ok := true
	var wild_total := 0
	for word in by_length:
		var value := ScoreManager.category_score(ScoreManager.Category.WILD, [word])
		if value != int(by_length[word]):
			wild_ok = false
		wild_total += value
	_check(wild_ok, "score WILD per-length values 3..8 == 1,2,5,7,10,15")
	_check_eq(wild_total, 40, "score WILD sums across words == 40")

	var all_scores := ScoreManager.all_category_scores(mixed)
	var six_keys := all_scores.size() == 6
	for category in ScoreManager.category_ids():
		if not all_scores.has(category):
			six_keys = false
	_check(six_keys, "score all_category_scores returns all six keys")
	_check_eq(ScoreManager.best_category_value(mixed), 17, "score best_category_value(mixed) == 17 (WILD)")
	_check_eq(ScoreManager.category_potential(mixed), 67, "score category_potential(mixed) == 67")


# ---------------------------------------------------------------- suite 4

func _test_round_manager() -> void:
	var db := WordDatabase.new(TEST_WORD_LIST)
	var round_manager := RoundManager.new()
	var accepted_log: Array = []
	var rejected_log: Array = []
	round_manager.word_accepted.connect(func(word: String, bonus: int, letter_points: int) -> void:
		accepted_log.append([word, bonus, letter_points]))
	round_manager.word_rejected.connect(func(word: String, reason: String) -> void:
		rejected_log.append([word, reason]))

	round_manager.setup(1, ["C", "A", "T", "S", "D", "O", "G", "E"])

	_check_eq(round_manager.submit_word("", db)["reason"], "empty", "round rejects '' with 'empty'")
	_check_eq(round_manager.submit_word("   ", db)["reason"], "empty", "round rejects whitespace with 'empty'")
	_check_eq(round_manager.submit_word("CA T!", db)["reason"], "invalid_characters",
		"round rejects 'CA T!' with 'invalid_characters'")
	_check_eq(round_manager.submit_word("CA", db)["reason"], "too_short", "round rejects 'CA' with 'too_short'")
	_check_eq(round_manager.submit_word("MOON", db)["reason"], "letters_unavailable",
		"round rejects 'MOON' (no M) with 'letters_unavailable'")
	_check_eq(round_manager.submit_word("GAT", db)["reason"], "not_in_dictionary",
		"round rejects 'GAT' with 'not_in_dictionary'")

	var res := round_manager.submit_word("cat", db)
	_check(bool(res["accepted"]), "round accepts lowercase 'cat'")
	_check_eq(res["word"], "CAT", "round result word is uppercased")
	_check_eq(res["letter_points"], 5, "round letter_points(CAT) == 5 (3+1+1)")
	_check_eq(res["bonus"], 0, "round bonus(CAT) == 0")

	_check(bool(round_manager.submit_word("CATS", db)["accepted"]), "round accepts CATS reusing C,A,T")
	_check(bool(round_manager.submit_word("DOGS", db)["accepted"]), "round accepts DOGS")
	_check(bool(round_manager.submit_word("GOAD", db)["accepted"]), "round accepts GOAD reusing G,O,A,D")
	_check(bool(round_manager.submit_word("TOAD", db)["accepted"]), "round accepts TOAD reusing T,O,A,D")
	_check(bool(round_manager.submit_word("COASTED", db)["accepted"]), "round accepts 7-letter COASTED")
	_check_eq(round_manager.submit_word("CAT", db)["reason"], "duplicate", "round rejects repeat of CAT with 'duplicate'")

	_check_eq(round_manager.last_word, "COASTED", "round last_word == COASTED")
	_check_eq(round_manager.submitted_words.size(), 6, "round submitted_words holds 6 words")
	_check_eq(accepted_log.size(), 6, "round word_accepted emitted 6 times")
	_check_eq(rejected_log.size(), 7, "round word_rejected emitted 7 times")
	_check_eq(accepted_log.back()[1], 50, "round COASTED carried bonus 50")
	_check_eq(accepted_log.back()[2], 10, "round COASTED carried letter_points 10")

	round_manager.setup(2, ["B", "I", "R", "D", "S", "O", "N", "G"])
	_check(round_manager.submitted_words.is_empty(), "round setup clears submitted_words")
	_check_eq(round_manager.last_word, "", "round setup clears last_word")
	_check_eq(round_manager.round_number, 2, "round setup sets round_number")
	_check(bool(round_manager.submit_word("BONDS", db)["accepted"]), "round 2 accepts BONDS")
	_check(bool(round_manager.submit_word("ROBIN", db)["accepted"]), "round 2 accepts ROBIN")
	_check(bool(round_manager.submit_word("SONG", db)["accepted"]), "round 2 accepts SONG")
	_check_eq(round_manager.submit_word("BONDS", db)["reason"], "duplicate", "round duplicate tracking is per round")
	_check_eq(round_manager.can_build("BONDS"), true, "round can_build(BONDS) with B,O,N,D,S")
	_check_eq(round_manager.can_build("MOON"), false, "round can_build(MOON) false without M")
	_check_eq(round_manager.can_build("BIRDSS"), false, "round can_build honours letter multiplicity")


# ---------------------------------------------------------------- suite 5

func _test_timer_controller() -> void:
	var timer := TimerController.new()
	var fired := [0]
	timer.timeout.connect(func() -> void: fired[0] += 1)
	timer.start(2.0)
	_check(timer.is_running(), "timer is_running after start")
	_check_eq(timer.time_left, 2.0, "timer time_left equals duration after start")
	timer.tick(1.0)
	_check_eq(timer.time_left, 1.0, "timer 1.0 left after tick(1.0)")
	_check_eq(fired[0], 0, "timer no timeout before zero")
	timer.tick(1.0)
	_check_eq(fired[0], 1, "timer timeout emitted exactly once")
	_check_eq(timer.time_left, 0.0, "timer clamped to 0 at timeout")
	_check(not timer.is_running(), "timer stopped itself at timeout")
	timer.tick(5.0)
	_check_eq(fired[0], 1, "timer tick after stop is inert")
	_check_eq(timer.time_left, 0.0, "timer time_left stays 0 after stop")

	var paused := TimerController.new()
	paused.start(5.0)
	paused.pause()
	paused.tick(1.0)
	_check_eq(paused.time_left, 5.0, "paused timer does not decrement")
	_check(paused.is_running(), "paused timer still counts as running")
	paused.resume()
	paused.tick(1.0)
	_check_eq(paused.time_left, 4.0, "resumed timer decrements again")

	var stopped := TimerController.new()
	stopped.start(3.0)
	stopped.stop()
	stopped.tick(1.0)
	_check_eq(stopped.time_left, 3.0, "stopped timer ignores ticks")

	var default_timer := TimerController.new()
	default_timer.start()
	_check_eq(default_timer.time_left, ScoreManager.ROUND_TIME, "timer default duration == ROUND_TIME")


# ---------------------------------------------------------------- suite 6

func _test_game_manager() -> void:
	var fixture_words := _load_fixture_words()
	_check(fixture_words.size() > 0, "game fixture word list loaded (%d words)" % fixture_words.size())
	var db := WordDatabase.new(TEST_WORD_LIST)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260921
	var game := GameManager.new()
	game.setup(db, LetterGenerator.new(rng))
	_check(game.state == GameManager.GameState.MENU, "game starts in MENU")
	_check_eq(game.submit_word("CAT")["reason"], "not_playing", "game ignores submits before start_game")

	var completed := [0]
	var final_total := [-1]
	game.game_complete.connect(func(total: int) -> void:
		completed[0] += 1
		final_total[0] = total)
	var rounds_ended := [0]
	game.round_ended.connect(func(_round_number: int, scores: Dictionary) -> void:
		rounds_ended[0] += 1
		_check_eq(scores.size(), 6, "game round_ended carries all six categories"))
	var started_rounds := [0]
	game.round_started.connect(func(round_number: int, letters: Array) -> void:
		started_rounds[0] += 1
		_check_eq(letters.size(), ScoreManager.LETTER_COUNT, "game round_started carries 8 letters"))

	game.start_game()

	var expected_total: int = 0
	var history_expect: Array = []
	for r in range(1, ScoreManager.TOTAL_ROUNDS + 1):
		_check_eq(game.current_round, r, "game round %d is active" % r)
		_check(game.state == GameManager.GameState.PLAYING, "game state PLAYING in round %d" % r)
		_check(_has_vowel(game.letters), "game round %d letters contain a vowel (%s)" % [
			r, ",".join(PackedStringArray(game.letters))])

		var round_bonus: int = 0
		var round_words: Array = []
		for word in fixture_words:
			var result := game.submit_word(word)
			if bool(result["accepted"]):
				round_words.append(String(result["word"]))
				round_bonus += int(result["bonus"])
				expected_total += int(result["bonus"])
		_check_eq(game.current_words.size(), round_words.size(),
			"game round %d recorded %d accepted words" % [r, round_words.size()])
		_check_eq(game.total_score, expected_total, "game bonuses banked immediately in round %d" % r)
		_check_eq(game.available_categories().size(), ScoreManager.TOTAL_ROUNDS - (r - 1),
			"game %d categories open during round %d play" % [ScoreManager.TOTAL_ROUNDS - (r - 1), r])

		_check_eq(game.best_category_value(), ScoreManager.best_category_value(round_words),
			"game best_category_value live in round %d" % r)
		_check_eq(game.category_potential(), ScoreManager.category_potential(round_words),
			"game category_potential live in round %d" % r)

		game.end_round()
		expected_total += ScoreManager.ROUND_COMPLETE_BONUS
		_check(game.state == GameManager.GameState.ROUND_COMPLETE,
			"game state ROUND_COMPLETE after round %d" % r)
		_check_eq(game.total_score, expected_total, "game completion bonus applied in round %d" % r)

		_check_eq(game.submit_word("CAT")["reason"], "not_playing",
			"game ignores submits once round %d is complete" % r)

		var available := game.available_categories()
		_check_eq(available.size(), ScoreManager.TOTAL_ROUNDS - r + 1,
			"game %d categories left before round %d choice" % [ScoreManager.TOTAL_ROUNDS - r + 1, r])
		var category := int(available[0])
		var points := ScoreManager.category_score(category, round_words)
		game.choose_category(category)
		expected_total += points
		_check(game.used_categories.has(category), "game category %d locked in round %d" % [category, r])
		_check_eq(game.total_score, expected_total,
			"game category %d banked %d points in round %d" % [category, points, r])

		game.choose_category(category)
		_check_eq(game.total_score, expected_total, "game re-choosing category %d changes nothing" % category)

		history_expect.append({
			"round": r,
			"category": category,
			"category_points": points,
			"bonus_points": round_bonus,
		})

		if r < ScoreManager.TOTAL_ROUNDS:
			_check(game.state == GameManager.GameState.PLAYING,
				"game next round started after round %d choice" % r)
		else:
			_check(game.state == GameManager.GameState.GAME_COMPLETE,
				"game GAME_COMPLETE after round 6 choice")
			_check_eq(completed[0], 1, "game game_complete emitted exactly once")

	_check_eq(game.total_score, expected_total, "game final total matches expected arithmetic (%d)" % expected_total)
	_check_eq(final_total[0], expected_total, "game_complete signal carried the final total")
	_check_eq(rounds_ended[0], ScoreManager.TOTAL_ROUNDS, "game round_ended emitted 6 times")
	_check_eq(started_rounds[0], ScoreManager.TOTAL_ROUNDS, "game round_started emitted 6 times")
	_check_eq(game.round_history.size(), ScoreManager.TOTAL_ROUNDS, "game round_history holds 6 entries")
	_check_eq(game.available_categories().size(), 0, "game no categories left at game end")

	var history_matches := true
	for i in range(game.round_history.size()):
		var recorded: Dictionary = game.round_history[i]
		var expected: Dictionary = history_expect[i]
		if int(recorded["round"]) != int(expected["round"]) \
				or int(recorded["category"]) != int(expected["category"]) \
				or int(recorded["category_points"]) != int(expected["category_points"]) \
				or int(recorded["bonus_points"]) != int(expected["bonus_points"]):
			history_matches = false
	_check(history_matches, "game round_history entries match expected arithmetic")

	_check_eq(game.current_round, ScoreManager.TOTAL_ROUNDS, "game stays on round 6 after completion")

	game.reset_game()
	_check(game.state == GameManager.GameState.PLAYING, "game reset_game starts playing again")
	_check_eq(game.current_round, 1, "game reset_game back to round 1")
	_check(game.used_categories.is_empty(), "game reset_game clears used_categories")
	_check(game.round_history.is_empty(), "game reset_game clears round_history")
	_check_eq(game.total_score, 0, "game reset_game clears total score")
	_check_eq(game.current_words.size(), 0, "game reset_game clears current words")
	_check_eq(game.letters.size(), ScoreManager.LETTER_COUNT, "game reset_game dealt fresh letters")
	_check_eq(game.available_categories().size(), ScoreManager.TOTAL_ROUNDS,
		"game reset_game reopens all categories")


# ---------------------------------------------------------------- suite 7


## Deterministic letter source for scripted rounds (overrides the weighted
## draw so a known long word can be forced through the game flow).
class FixedLetterGenerator extends LetterGenerator:
	var fixed: Array = []

	func generate() -> Array:
		return fixed


func _test_game_manager_long_word_bonus() -> void:
	var db := WordDatabase.new(TEST_WORD_LIST)
	var gen := FixedLetterGenerator.new()
	gen.fixed = ["C", "O", "A", "S", "T", "E", "D", "G"]
	var game := GameManager.new()
	game.setup(db, gen)
	game.start_game()

	var bonus_log := [0]
	game.word_accepted.connect(func(_word: String, bonus: int, _letter_points: int) -> void:
		bonus_log[0] += bonus)

	var res := game.submit_word("coasted")
	_check(bool(res["accepted"]), "game long-word round accepts COASTED")
	_check_eq(int(res["bonus"]), 50, "game COASTED result carries the 50 bonus")
	_check_eq(bonus_log[0], 50, "game word_accepted emitted the 50 bonus")
	_check_eq(game.total_score, 50, "game long-word bonus banked into total immediately")
	_check_eq(game.current_words, ["COASTED"], "game current_words tracks the accepted word")

	game.end_round()
	_check_eq(game.total_score, 50 + ScoreManager.ROUND_COMPLETE_BONUS,
		"game long-word total after round completion bonus")

	game.choose_category(ScoreManager.Category.FIVE_PLUS)
	_check_eq(game.total_score, 50 + ScoreManager.ROUND_COMPLETE_BONUS + ScoreManager.WORD_SCORE_5_PLUS,
		"game FIVE_PLUS banked on a single 7-letter word")
	_check_eq(int(game.round_history[0]["bonus_points"]), 50, "game history records 50 bonus points")

	game.reset_game()
	_check_eq(game.total_score, 0, "game reset clears the long-word total")


# ---------------------------------------------------------------- suite 8

func _test_save_data() -> void:
	var save_data := SaveData.new()
	var path := ProjectSettings.globalize_path(SaveData.SAVE_PATH)
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		print("NOTE: save_data stale file not present (remove err %d)" % err)

	var missing := save_data.load_data()
	_check(missing.is_empty() == false and int(missing.get("total_score", -1)) == 0
			and int(missing.get("highest_round", -1)) == 0
			and Dictionary(missing.get("settings", {"x": 1})).is_empty(),
		"save_data missing file -> defaults 0/0/{}")

	_check(save_data.save(123, 4, {"sound": true}), "save_data save(123, 4, {sound:true}) returns true")
	var loaded := save_data.load_data()
	_check_eq(int(loaded["total_score"]), 123, "save_data round-trips total_score")
	_check_eq(int(loaded["highest_round"]), 4, "save_data round-trips highest_round")
	_check_eq(Dictionary(loaded["settings"]).get("sound"), true, "save_data round-trips settings.sound == true")

	DirAccess.remove_absolute(path)
	var file := FileAccess.open(SaveData.SAVE_PATH, FileAccess.WRITE)
	file.store_string("this is ][ not a valid config {{{")
	file.close()
	var corrupt := save_data.load_data()
	_check(int(corrupt.get("total_score", -1)) == 0 and int(corrupt.get("highest_round", -1)) == 0
			and Dictionary(corrupt.get("settings", {"x": 1})).is_empty(),
		"save_data corrupt file -> defaults, no crash")

	_check(save_data.save(0, 0, {}), "save_data save with empty settings works")
	var empty_settings := save_data.load_data()
	_check(Dictionary(empty_settings["settings"]).is_empty(), "save_data empty settings round-trip")

	DirAccess.remove_absolute(path)
	_check(save_data.load_data()["total_score"] == 0, "save_data file deletion restores defaults")
