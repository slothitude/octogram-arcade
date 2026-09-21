extends SceneTree
## Eight Letters end-to-end: boots the REAL main.tscn (full UI tree), drives the
## ModeMenu into EIGHT LETTERS like a tap would, feeds real InputEventKey events
## through _unhandled_input, and asserts the whole loop: into level 1 -> typed
## word accepted -> live scores + pills -> duplicate/unavailable rejects ->
## target reached -> next level -> 8-letter instant win -> bonus-mode + how-to
## UI states -> game over reveal -> best saved -> PLAY AGAIN.
## Run: godot --headless --script res://tests/run8_e2e.gd


var checks: int = 0
var failures: int = 0


func _init() -> void:
	# Start deferred: the coroutine awaits process_frame, so it must begin once
	# the tree is actually ticking (a plain call would let _init race ahead to quit).
	_test_summary.call_deferred()


func _test_summary() -> void:
	await _run_all()
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


## Types `word` through main's real input handler, then presses ENTER.
func _type_word(main: Node, word: String, submit: bool = true) -> void:
	for ch in String(word).to_upper():
		main.call("_unhandled_input", _key_press(ch.unicode_at(0)))
	if submit:
		main.call("_unhandled_input", _key_press(0, KEY_ENTER))


func _find_word(letters: Array, db) -> String:
	## Brute-force a 3-letter word that (a) is in the dictionary and (b) can be
	## built from the level's letters. Returns "" if none found.
	for i in letters.size():
		for j in letters.size():
			for k in letters.size():
				if i == j or j == k or i == k:
					continue
				var w := String(letters[i]) + String(letters[j]) + String(letters[k])
				if db.is_valid_word(w):
					return w
	return ""


func _run_all() -> void:
	# Pre-seed the save so bests start from zero (fresh-run assertions below).
	var sd := SaveData.new()
	sd.save(0, 0, {"e2e": true})

	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)

	# Let _ready and a couple of process frames run before reading anything.
	await process_frame
	await process_frame

	# Boot lands on the ModeMenu: drive it into EIGHT LETTERS like a tap would.
	var menu: Node = null
	for child in main.get_children():
		if child.has_method("select_eight"):
			menu = child
	if menu == null:
		expect(false, "ModeMenu with select_eight() found on boot")
		return
	menu.call("select_eight")
	await process_frame
	await process_frame

	var game8: Object = main.get("game8")
	var board: Object = main.get("board")
	var db: Object = main.get("word_db")
	expect(game8 != null and board != null and db != null, "main exposes game8/board/word_db")
	if game8 == null or board == null or db == null:
		return

	expect(int(game8.get("state")) == GameEight.State.PLAYING and int(game8.get("level")) == 1,
		"first launch goes straight to level 1 PLAYING (state=%d)" % int(game8.get("state")))
	var letters: Array = game8.get("letters")
	var level_label := board.find_child("LevelLabel", true, false) as Label
	expect(letters.size() == 8 and level_label != null and level_label.text == "LEVEL 1",
		"8 letters dealt and board header shows LEVEL 1")
	var timer_label := board.find_child("TimerLabel", true, false) as Label
	expect(timer_label != null and timer_label.text == "2:00",
		"board timer shows 2:00 (%s)" % (timer_label.text if timer_label != null else "?"))

	# --- Type a valid word through real key events ------------------------------
	var word := _find_word(letters, db)
	expect(word.length() == 3, "buildable dictionary word from letters: %s" % word)
	if word.is_empty():
		return
	_type_word(main, word)
	var found: Array = game8.get("found_words")
	expect(found.has(word) and String(main.get("current_word")).is_empty()
		and int(game8.get("round_score")) == 4,
		"typed word accepted (found_words + empty word + round score 4)")
	var score_label := board.find_child("ScoreLabel", true, false) as Label
	var words_list := board.find_child("WordsList", true, false) as VBoxContainer
	var counter := board.find_child("WordsCounter", true, false) as Label
	expect(score_label != null and score_label.text == "SCORE 4"
		and words_list.get_child_count() == 1
		and counter != null and counter.text == "WORDS: 1",
		"board shows score, pill and WORDS: 1 (%s / %s)" % [
			score_label.text if score_label != null else "?",
			counter.text if counter != null else "?"])

	# --- Duplicate rejected -------------------------------------------------------
	_type_word(main, word)
	expect(found.size() == 1, "duplicate rejected (found_words still 1)")
	var toast := board.find_child("Toast", true, false) as Control
	var toast_label := board.find_child("ToastLabel", true, false) as Label
	expect(toast != null and toast.visible and toast_label != null
		and toast_label.text == "Already found",
		"duplicate reject toast: %s" % (toast_label.text if toast_label != null else "?"))

	# --- Unavailable letter feedback ---------------------------------------------
	# Deterministic: pick a letter that is guaranteed absent from the draw (a
	# spare copy of a used letter depends on the random pool and would flake).
	var absent := "Q"
	for code in range(65, 91):
		var probe := String.chr(code)
		var in_pool := false
		for l in game8.get("letters"):
			if String(l) == probe:
				in_pool = true
				break
		if not in_pool:
			absent = probe
			break
	main.call("_unhandled_input", _key_press(absent.unicode_at(0)))
	expect(String(main.get("current_word")) == word and toast_label.text == "Letters not available",
		"unavailable letter (%s) blocked with toast" % absent)
	main.call("_unhandled_input", _key_press(0, KEY_ESCAPE))
	expect(String(main.get("current_word")).is_empty(), "ESC clears the current word")

	# --- Grind to the target: submit the level's possible words (cap 200) --------
	var submissions := 0
	var possible: Array = game8.get("possible_words")
	for candidate in possible:
		if int(game8.get("level")) != 1 or submissions >= 200:
			break
		var candidate_word := String(candidate)
		if found.has(candidate_word):
			continue
		_type_word(main, candidate_word)
		submissions += 1
	expect(int(game8.get("level")) == 2, "target reached -> level 2 (%d submissions)" % submissions)
	await process_frame
	var words_list2 := board.find_child("WordsList", true, false) as VBoxContainer
	expect(words_list2 != null and words_list2.get_child_count() == 0,
		"found-words list cleared for the new level")

	# --- 8-letter instant win ------------------------------------------------------
	var hint: String = game8.call("hint_word")
	_type_word(main, hint)
	expect(int(game8.get("level")) == 3, "8-letter word completes the level instantly (level=%d)"
		% int(game8.get("level")))

	# --- Bonus-mode board states (bonus flow itself covered by run8_tests) --------
	board.call("set_bonus_mode", true)
	var title := board.find_child("TitleLabel", true, false) as Label
	var score_panel := board.find_child("ScorePanel", true, false) as Control
	var bonus_on := title != null and String(title.text).contains("BONUS ROUND") \
		and score_panel != null and not score_panel.visible
	board.call("set_bonus_mode", false)
	var bonus_off := title != null and not String(title.text).contains("BONUS ROUND") \
		and score_panel != null and score_panel.visible
	expect(bonus_on and bonus_off, "bonus mode swaps header, hides bar, then restores")

	# --- How-to pauses the level timer and resumes on close -----------------------
	var timer: Object = game8.get("timer")
	board.emit_signal("how_to_requested")
	var how_to: Object = main.get("how_to")
	expect(how_to != null and bool(how_to.get("visible")) and bool(timer.call("is_paused")),
		"how-to opens and pauses the timer")
	timer.set("time_left", 10.0)
	timer.call("tick", 0.5)
	var held := absf(float(timer.get("time_left")) - 10.0) < 0.001
	how_to.call("close")
	var closed_ok := how_to != null and not bool(how_to.get("visible")) \
		and not bool(timer.call("is_paused"))
	timer.call("tick", 0.5)
	var resumed := absf(float(timer.get("time_left")) - 9.5) < 0.001
	expect(held and closed_ok and resumed, "paused timer holds, close resumes it (%.2f -> %.2f)"
		% [10.0, float(timer.get("time_left"))])

	# --- Force game over -> reveal --------------------------------------------------
	var total_before: int = game8.get("total_score")
	timer.set("time_left", 0.01)
	timer.call("tick", 0.02)
	await process_frame
	expect(int(game8.get("state")) == GameEight.State.GAME_OVER,
		"timer zero -> GAME_OVER (state=%d)" % int(game8.get("state")))
	var reveal := board.find_child("RevealOverlay", true, false) as Control
	expect(reveal != null and reveal.visible, "reveal overlay visible after game over")
	var total_label := reveal.find_child("TotalLabel", true, false) as Label
	var found_label := reveal.find_child("FoundLabel", true, false) as Label
	expect(total_label != null and total_label.text == "TOTAL SCORE %d" % total_before
		and found_label != null and found_label.text == "You found %d of %d words"
			% [int(game8.call("found_count")), int(game8.call("possible_count"))],
		"reveal shows total + found count (%s / %s)" % [
			total_label.text if total_label != null else "?",
			found_label.text if found_label != null else "?"])
	var words_box := reveal.find_child("WordsBox", true, false) as VBoxContainer
	var best_label := reveal.find_child("BestLabel", true, false) as Label
	expect(words_box != null and words_box.get_child_count() > 0
		and best_label != null and best_label.text == "NEW BEST!",
		"reveal lists word groups and flags the new best (%s)" % best_label.text)
	var loaded: Dictionary = SaveData.new().load_data()
	expect(int(loaded.get("best_score", 0)) >= total_before,
		"best score persisted (%d)" % int(loaded.get("best_score", 0)))

	# --- PLAY AGAIN ---------------------------------------------------------------
	board.emit_signal("play_again_requested")
	await process_frame
	await process_frame
	expect(int(game8.get("level")) == 1 and int(game8.get("state")) == GameEight.State.PLAYING
		and reveal != null and not reveal.visible,
		"play again -> level 1 PLAYING with reveal hidden")
