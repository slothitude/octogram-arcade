extends SceneTree
## Battle-scene smoke test: boots the REAL battle.tscn against a level-3
## Progression and the zone-1 encounter-1 enemy, feeds guaranteed-valid words
## through the internal submit path, and asserts the win path (rewards signal,
## HP drain, progression payout) plus the lose path (timeout -> retry overlay ->
## BACK emits battle_finished(false, {})). Run:
##   godot --headless --path <project> --script res://tests/smoke_battle.gd

var _checks: int = 0
var _failures: int = 0
var _result: Dictionary = {}


func _init() -> void:
	# Start deferred: the coroutine awaits process_frame, so it must begin once
	# the tree is actually ticking (a plain call would let _init race ahead).
	_summary.call_deferred()


func _summary() -> void:
	await _run()
	print("")
	print("Ran %d battle smoke checks: %d passed, %d failed" % [
		_checks, _checks - _failures, _failures])
	Engine.time_scale = 1.0
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, check_name: String, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("PASS: " + check_name)
	else:
		_failures += 1
		print("FAIL: " + check_name + ((" - " + detail) if detail != "" else ""))


func _await_until(predicate: Callable, max_frames: int) -> bool:
	for i in range(max_frames):
		if predicate.call():
			return true
		await process_frame
	return bool(predicate.call())


func _run() -> void:
	# --- Seed save + build the logic layer -----------------------------------
	var save := SaveData.new()
	save.save(0, 0, {"tutorial_seen": true}, {
		"level": 3, "xp": 0, "gold": 100, "zone": 1, "encounter": 1,
		"upgrades": {"sharp_quill": 2, "lucky_kelp": 1, "hourglass_pearl": 1},
		"ng_plus": false,
	})
	var progression := Progression.new()
	progression.level = 3
	progression.gold = 100
	progression.upgrades = {"sharp_quill": 2, "lucky_kelp": 1, "hourglass_pearl": 1}
	var word_db := WordDatabase.new()
	var letter_gen := LetterGenerator.new()
	var enemy := EnemyDef.enemy_at(1, 1)
	_check(not enemy.is_empty(), "enemy_at(1,1) resolves")

	# --- Boot the scene --------------------------------------------------------
	var ui: BattleUi = (load("res://scenes/battle.tscn") as PackedScene).instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	_check(ui != null and ui.get("battle") == null, "scene boots before setup")
	ui.setup(enemy, progression, word_db, letter_gen)
	ui.battle_finished.connect(func(won: bool, rewards: Dictionary) -> void:
		_result["won"] = won
		_result["rewards"] = rewards)
	_check(ui.battle != null, "setup exposes BattleManager as battle var")
	_check(int(ui.battle.enemy_max_hp) == 40, "enemy max hp 40 (got %d)" % int(ui.battle.enemy_max_hp))

	ui.begin()
	await process_frame
	await process_frame

	# --- Board state after begin ------------------------------------------------
	var letters: Array = ui.get("letters")
	_check(letters.size() == 8, "8 letters dealt (%s)" % str(letters))
	var need_vowels := progression.guaranteed_vowels()
	var vowel_count := 0
	for letter in letters:
		if ["A", "E", "I", "O", "U"].has(String(letter)):
			vowel_count += 1
	_check(vowel_count >= need_vowels,
		"vowel guarantee met (%d >= %d)" % [vowel_count, need_vowels])
	var tiles := ui.find_child("LetterArea", true, false)
	_check(tiles != null and tiles.get_child_count() == 8,
		"8 LetterTile instances on the board")
	_check(ui.get("battle_time") > 0.0, "battle timer started")
	var zone_label: Label = ui.find_child("ZoneLabel", true, false)
	_check(zone_label != null and String(zone_label.text).contains("Coral Spelling Reef"),
		"zone strip shows zone 1 name")
	var taunt: Control = ui.find_child("TauntBubble", true, false)
	_check(taunt != null and taunt.visible, "taunt bubble shown on begin")

	# --- Rejection paths (check order) ------------------------------------------
	# A letter outside the pool is ignored; a too-short word is rejected.
	var pool_has_q := false
	for letter in letters:
		if String(letter) == "Q":
			pool_has_q = true
	ui.call("_append_letter", "Q")
	if pool_has_q:
		_check(String(ui.get("current_word")) == "Q", "single letter enters the word")
		ui.call("submit_current_word")
		_check(int(ui.battle.word_count) == 0, "too-short word rejected")
		ui.call("_clear_word")
	else:
		_check(String(ui.get("current_word")) == "", "letter outside the pool ignored")

	var words := _find_words(letters, word_db, 40)
	_check(words.size() >= 5, "brute-forced buildable dictionary words (%d found)" % words.size())
	if words.is_empty():
		return

	# Duplicate rejection: submit word[0] twice, list stays size 1.
	_type_word(ui, String(words[0]))
	ui.call("submit_current_word")
	_check(int(ui.battle.word_count) == 1, "first word accepted into battle")
	_check(float(ui.battle.enemy_hp) < float(ui.battle.enemy_max_hp),
		"enemy hp visibly decreased after first word (%.1f/%d)" % [
			float(ui.battle.enemy_hp), int(ui.battle.enemy_max_hp)])
	_type_word(ui, String(words[0]))
	ui.call("submit_current_word")
	_check(int(ui.battle.word_count) == 1, "duplicate word rejected")
	_check(String(ui.get("current_word")) == String(words[0]),
		"rejected duplicate keeps the word for editing")

	# Non-word rejection (buildable 3-letter combo that is not in the dictionary).
	var nonsense := _find_nonsense(letters, word_db)
	if nonsense != "":
		ui.call("_clear_word")
		_type_word(ui, nonsense)
		ui.call("submit_current_word")
		_check(int(ui.battle.word_count) == 1, "non-word rejected (%s)" % nonsense)

	# --- Feed words until the enemy dies (or the pool runs out) -----------------
	var fed := 1
	for i in range(1, words.size()):
		if ui.get("_finished"):
			break
		_type_word(ui, String(words[i]))
		ui.call("submit_current_word")
		fed += 1
		if i % 5 == 0:
			await process_frame
	_check(fed >= 1, "fed %d valid words through the submit path" % fed)

	var won := await _await_until(func() -> bool: return not _result.is_empty(), 600)
	_check(won and bool(_result.get("won", false)), "battle_finished fired with won=true")
	var rewards: Dictionary = _result.get("rewards", {})
	_check(rewards.has("gold") and rewards.has("xp") and rewards.has("leveled_up"),
		"win rewards carry gold/xp/leveled_up (%s)" % str(rewards))
	_check(int(rewards.get("gold", 0)) > 0 and int(rewards.get("xp", 0)) > 0,
		"win rewards are non-zero")
	_check(progression.gold <= 100, "battle scene does NOT bank gold itself (main is the single applier) (%d)" % progression.gold)
	progression.add_gold(int(rewards.get("gold", 0)))
	progression.add_xp(int(rewards.get("xp", 0)))
	_check(progression.gold > 100, "rewards bank via progression once main applies them (%d)" % progression.gold)

	# --- Lose path: retry, run the clock out, press BACK -------------------------
	_result.clear()
	ui.call("retry_same_battle")
	await process_frame
	await process_frame
	_check(float(ui.battle.enemy_hp) == float(ui.battle.enemy_max_hp),
		"retry restores enemy hp")
	_check(int(ui.battle.word_count) == 0, "retry resets the battle record")
	ui.set("battle_time", 0.5)
	var lost := await _await_until(func() -> bool: return bool(ui.get("_finished")), 600)
	_check(lost, "battle_time running out finishes the battle")
	var overlay: Control = ui.find_child("LoseOverlay", true, false)
	_check(overlay != null and overlay.visible, "defeat overlay shown")
	var retry_btn: Button = ui.find_child("RetryButton", true, false)
	var back_btn: Button = ui.find_child("BackButton", true, false)
	_check(retry_btn != null and retry_btn.visible, "RETRY button shown")
	_check(back_btn != null and back_btn.visible, "BACK button shown")

	# RETRY restarts the same encounter without emitting battle_finished.
	retry_btn.pressed.emit()
	await process_frame
	await process_frame
	_check(not bool(ui.get("_finished")) and _result.is_empty(),
		"RETRY restarts the battle (no signal)")
	_check(float(ui.battle.enemy_hp) == float(ui.battle.enemy_max_hp),
		"RETRY restored enemy hp")

	# BACK emits battle_finished(false, {}).
	ui.set("battle_time", 0.2)
	await _await_until(func() -> bool: return bool(ui.get("_finished")), 600)
	back_btn.pressed.emit()
	var backed := await _await_until(func() -> bool: return not _result.is_empty(), 60)
	_check(backed and not bool(_result.get("won", true)), "BACK emits battle_finished(false)")
	var lose_rewards: Dictionary = _result.get("rewards", {})
	_check(lose_rewards.is_empty(), "lose rewards are an empty dict")

	ui.queue_free()
	await process_frame
	_check(Engine.time_scale == 1.0, "Engine.time_scale restored after battle")


## Type a word through the same path the A-Z keys use.
func _type_word(ui: BattleUi, word: String) -> void:
	ui.call("_clear_word")
	for ch in word:
		ui.call("_append_letter", ch)


## Brute-force buildable dictionary words of length 3 and 4 (distinct letter
## positions, same pattern as run_e2e.gd's _find_word), up to max_count.
func _find_words(letters: Array, db: WordDatabase, max_count: int) -> Array:
	var found: Array = []
	var n := letters.size()
	for length: int in [3, 4]:
		var idx := []
		for i in range(length):
			idx.append(0)
		while true:
			# advance the odometer
			var pos := length - 1
			while pos >= 0:
				idx[pos] += 1
				if idx[pos] < n:
					break
				idx[pos] = 0
				pos -= 1
			if pos < 0:
				break
			# distinct positions only
			var distinct := true
			for a in range(length):
				for b in range(a + 1, length):
					if idx[a] == idx[b]:
						distinct = false
			if not distinct:
				continue
			var w := ""
			for a in range(length):
				w += String(letters[idx[a]])
			if db.is_valid_word(w) and not found.has(w):
				found.append(w)
				if found.size() >= max_count:
					return found
	return found


## A buildable 3-letter combo that is NOT in the dictionary.
func _find_nonsense(letters: Array, db: WordDatabase) -> String:
	var n := letters.size()
	for i in range(n):
		for j in range(n):
			for k in range(n):
				if i == j or j == k or i == k:
					continue
				var w := String(letters[i]) + String(letters[j]) + String(letters[k])
				if not db.is_valid_word(w):
					return w
	return ""
