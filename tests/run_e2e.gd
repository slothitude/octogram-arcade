extends SceneTree
## End-to-end milestone test: boots the REAL main.tscn (full UI tree), feeds real
## InputEventKey events through _unhandled_input, and asserts the complete game loop:
## tutorial skip -> round started with 8 letters -> typed word accepted -> scores live
## -> timer ends round -> category chosen & banked & locked -> next round -> 6 rounds
## -> GAME_COMPLETE. Run: godot --headless --script res://tests/run_e2e.gd


var failures: int = 0
var checks: int = 0


func _init() -> void:
	# Start deferred: the coroutine awaits process_frame, so it must begin once
	# the tree is actually ticking (a plain call would let _init race ahead to quit).
	_test_summary.call_deferred()


func _test_summary() -> void:
	await _test_full_game()
	print("Ran %d E2E checks: %d passed, %d failed" % [checks, checks - failures, failures])
	quit(1 if failures > 0 else 0)


func expect(cond: bool, label: String) -> void:
	checks += 1
	if cond:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _key_press(unicode: int, keycode: int = 0) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.echo = false
	ev.unicode = unicode
	if keycode != 0:
		ev.keycode = keycode as Key
	return ev


func _find_word(letters: Array, db) -> String:
	## Brute-force a 3-letter word that (a) is in the dictionary and (b) can be
	## built from the round's letters. Returns "" if none found.
	for i in letters.size():
		for j in letters.size():
			for k in letters.size():
				if i == j or j == k or i == k:
					continue
				var w := String(letters[i]) + String(letters[j]) + String(letters[k])
				if db.is_valid_word(w):
					return w
	return ""


func _test_full_game() -> void:
	# Pre-seed save so _ready skips the tutorial (its visible state was already
	# verified visually on desktop; here we test the game loop).
	var sd := SaveData.new()
	sd.save(0, 0, {"tutorial_seen": true, "e2e": true})

	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)

	# Let _ready and a couple of process frames run before reading anything.
	await process_frame
	await process_frame

	# Boot now lands on the ModeMenu; drive it into the arena like a tap would.
	var menu: Node = null
	for child in main.get_children():
		if child.has_method("select_arena"):
			menu = child
			break
	if menu != null:
		menu.call("select_arena")
	await process_frame
	await process_frame

	var game: Object = main.get("game")
	var ui: Object = main.get("ui")
	var db: Object = main.get("word_db")
	var timer: Object = main.get("timer")
	expect(game != null and ui != null and db != null and timer != null, "main exposes game/ui/word_db/timer")

	expect(int(game.get("state")) == 1 or int(game.get("state")) == 2,
		"game started (ROUND_START/PLAYING), state=%d" % int(game.get("state")))
	var letters: Array = game.get("letters")
	expect(letters.size() == 8, "8 letters generated (%s)" % str(letters).substr(0, 24))
	var has_vowel := false
	for l in letters:
		if ["A", "E", "I", "O", "U"].has(l):
			has_vowel = true
	expect(has_vowel, "at least one vowel in letters")

	# --- Type a valid word through real key events ------------------------------
	var word := _find_word(letters, db)
	expect(word.length() == 3, "found a buildable dictionary word from letters: %s" % word)
	if word.is_empty():
		return
	for ch in word.to_upper():
		main.call("_unhandled_input", _key_press(ch.unicode_at(0)))
	expect(String(main.get("current_word")) == word, "typed word assembled: %s" % main.get("current_word"))

	# Submit with a real Enter event.
	main.call("_unhandled_input", _key_press(0, KEY_ENTER))
	var words: Array = game.get("current_words")
	expect(words.has(word), "word accepted into round word list")
	expect(String(main.get("current_word")) == "", "current word cleared after accepted submit")
	var pot_before: int = game.call("category_potential")
	var best_before: int = game.call("best_category_value")
	expect(pot_before > 0 and best_before > 0,
		"live category values moved (best=%d, potential=%d)" % [best_before, pot_before])

	# Duplicate rejected.
	for ch in word:
		main.call("_unhandled_input", _key_press(ch.unicode_at(0)))
	main.call("_unhandled_input", _key_press(0, KEY_ENTER))
	expect(game.get("current_words").size() == 1, "duplicate word rejected (list still size 1)")
	expect(String(main.get("current_word")) == word, "rejected duplicate keeps the word for editing")

	# Non-word rejected.
	main.call("_unhandled_input", _key_press(81))  # Q
	main.call("_unhandled_input", _key_press(88))  # X
	main.call("_unhandled_input", _key_press(74))  # J
	main.call("_unhandled_input", _key_press(0, KEY_ENTER))
	expect(game.get("current_words").size() == 1, "non-word/letters-unavailable rejected")

	# --- Timer ends the round ---------------------------------------------------
	var total_before: int = game.get("total_score")  # before end_round adds its bonus
	timer.set("time_left", 0.01)
	await process_frame
	await process_frame
	expect(int(game.get("state")) == 4, "timer zero -> ROUND_COMPLETE (state=%d)" % int(game.get("state")))

	# --- Choose a category: banks points, locks, advances ------------------------
	var scores: Dictionary = ScoreManager.all_category_scores(game.get("current_words"))
	var cat := ScoreManager.Category.FLUSH
	var expected_flush: int = scores.get(cat, 0)
	game.call("choose_category", cat)
	var banked: int = int(game.get("total_score")) - total_before
	expect(banked == expected_flush + 10,
		"FLUSH banked + round bonus (banked %d = %d + 10)" % [banked, expected_flush])
	expect(game.get("used_categories").has(cat), "category locked after choosing")

	# --- Play the remaining rounds to GAME_COMPLETE ------------------------------
	for round_i in range(2, 7):
		expect(int(game.get("current_round")) == round_i, "advanced to round %d" % round_i)
		expect(int(game.get("state")) == 2, "playing in round %d" % round_i)
		# submit one word if possible, then end round and take first available cat
		var l2: Array = game.get("letters")
		var w2 := _find_word(l2, db)
		if not w2.is_empty():
			for ch in w2:
				main.call("_unhandled_input", _key_press(ch.unicode_at(0)))
			main.call("_unhandled_input", _key_press(0, KEY_ENTER))
		timer.set("time_left", 0.01)
		await process_frame
		await process_frame
		var avail: Array = game.call("available_categories")
		expect(avail.size() > 0, "categories available in round %d (%d)" % [round_i, avail.size()])
		game.call("choose_category", avail[0])

	expect(int(game.get("state")) == 5, "GAME_COMPLETE after round 6 (state=%d)" % int(game.get("state")))
	expect(game.get("round_history").size() == 6, "6 rounds recorded in history")
	expect(game.get("used_categories").size() == 6, "all 6 categories used exactly once")

	# --- PLAY AGAIN resets --------------------------------------------------------
	game.call("reset_game")
	expect(int(game.get("current_round")) == 1, "PLAY AGAIN -> round 1")
	expect(game.get("used_categories").is_empty(), "categories cleared on reset")
	expect(int(game.get("total_score")) == 0, "total reset to 0")

	# --- Save persistence ----------------------------------------------------------
	var sd2 := SaveData.new()
	var loaded: Dictionary = sd2.load_data()
	expect(int(loaded.get("highest_round", 0)) >= 6, "highest_round persisted (got %d)" % int(loaded.get("highest_round", 0)))
