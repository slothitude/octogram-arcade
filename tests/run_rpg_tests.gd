extends SceneTree
## Headless test battery for the RPG logic layer (battle, progression, roster,
## v2 save). Run with:
##   godot --headless --path <project> --script res://tests/run_rpg_tests.gd
## Exits 0 when every check passes, 1 otherwise.

var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	# Start deferred: the coroutine awaits below, so it must begin once the tree
	# is actually ticking (a plain call would let _init race ahead to quit).
	_summary.call_deferred()


func _summary() -> void:
	await _run()
	print("")
	print("Ran %d RPG checks: %d passed, %d failed" % [_checks, _checks - _failures, _failures])
	quit(1 if _failures > 0 else 0)


func _run() -> void:
	_test_damage_math()
	_test_combo()
	_test_enemy_hp()
	_test_time_eat()
	_test_progression_curve()
	_test_shop()
	_test_campaign_flow()
	_test_save_v2()
	_test_battle_win_flow()
	_test_word_set()
	_test_sfx()


func _check(condition: bool, check_name: String, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("PASS: " + check_name)
	else:
		_failures += 1
		print("FAIL: " + check_name + ((" - " + detail) if detail != "" else ""))


func _check_eq(actual, expected, check_name: String) -> void:
	_check(actual == expected, check_name, "expected %s, got %s" % [str(expected), str(actual)])


func _feq(actual: float, expected: float, check_name: String) -> void:
	_check(absf(actual - expected) <= 0.0001, check_name,
		"expected %f, got %f" % [expected, actual])


func _battle(zone: int, encounter: int, level: int = 1, upgrades: Dictionary = {},
		ng_plus: bool = false) -> BattleManager:
	var battle := BattleManager.new()
	battle.setup(EnemyDef.enemy_at(zone, encounter), level, upgrades, ng_plus)
	return battle


## Accept a word at the given clock time and return the result dict.
func _hit(battle: BattleManager, word: String, time_now: float) -> Dictionary:
	return battle.on_word_accepted(word, time_now)


# ---------------------------------------------------------------- suite 1

func _test_damage_math() -> void:
	# Hand base: CAT = 3+1+1 = 5 letter sum, level 1, combo x1.0 -> 5 damage.
	var battle := _battle(1, 1)
	var res := _hit(battle, "CAT", 0.0)
	_feq(float(res["damage"]), 5.0, "damage CAT at level 1 combo 1.0 == 5")
	_check(bool(res["is_crit"]) == false, "damage CAT is not a crit")
	_feq(float(res["combo"]), 1.0, "damage CAT leaves combo at 1.0")
	_feq(battle.enemy_hp, 35.0, "damage CAT leaves enemy hp 35/40")

	# Combo ramp applies to the quick second word (within 5s): x1.15.
	res = _hit(battle, "CAT", 1.0)
	_feq(float(res["damage"]), 5.75, "damage second quick CAT == 5 * 1.15")

	# 7-letter word crits x2: COASTED = 3+1+1+1+1+1+2 = 10 -> 20.
	var crit_battle := _battle(1, 1)
	res = _hit(crit_battle, "COASTED", 0.0)
	_feq(float(res["damage"]), 20.0, "damage 7-letter COASTED == 10 * CRIT_7 == 20")
	_check(bool(res["is_crit"]), "damage 7-letter word is a crit")
	_check_eq(crit_battle.crit_count, 1, "crit_count tracks 7-letter word")

	# 8-letter word mega crits x3: BASEBALL = 3+1+1+1+3+1+1+1 = 12 -> 36.
	var mega_battle := _battle(1, 1)
	res = _hit(mega_battle, "BASEBALL", 0.0)
	_feq(float(res["damage"]), 36.0, "damage 8-letter BASEBALL == 12 * CRIT_8 == 36")
	_check(bool(res["is_crit"]), "damage 8-letter word is a crit")
	_check_eq(mega_battle.crit_count, 1, "crit_count tracks 8-letter word")

	# Sharp Quill x2 stacks: 5 * (1 + 0.15*2) = 6.5.
	var quill_battle := _battle(1, 1, 1, {"sharp_quill": 2})
	res = _hit(quill_battle, "CAT", 0.0)
	_feq(float(res["damage"]), 6.5, "damage CAT with 2 Sharp Quill == 5 * 1.3")

	# Golden Starfish x2 adds +1.0 to both crit multipliers.
	var star_battle := _battle(1, 1, 1, {"golden_starfish": 2})
	res = _hit(star_battle, "COASTED", 0.0)
	_feq(float(res["damage"]), 30.0, "damage COASTED with 2 Starfish == 10 * (2.0 + 1.0)")
	res = _hit(_battle(1, 1, 1, {"golden_starfish": 2}), "BASEBALL", 0.0)
	_feq(float(res["damage"]), 48.0, "damage BASEBALL with 2 Starfish == 12 * (3.0 + 1.0)")
	_feq(float(_hit(_battle(1, 1, 1, {"golden_starfish": 2}), "CAT", 0.0)["damage"]), 5.0,
		"Starfish leaves non-crit CAT at 5")

	# Level 5 multiplier: 1 + 0.15*4 = 1.6 -> CAT == 8.
	_feq(float(_hit(_battle(1, 1, 5), "CAT", 0.0)["damage"]), 8.0,
		"damage CAT at level 5 == 5 * 1.6")

	# Level and quill stack multiplicatively: 5 * 1.6 * 1.15 = 9.2.
	_feq(float(_hit(_battle(1, 1, 5, {"sharp_quill": 1}), "CAT", 0.0)["damage"]), 9.2,
		"damage CAT at level 5 + 1 quill == 5 * 1.6 * 1.15")


# ---------------------------------------------------------------- suite 2

func _test_combo() -> void:
	# Boss HP pool so the ramp words cannot kill anything.
	var battle := _battle(5, 3)
	var expected := [1.0, 1.15, 1.3, 1.45, 1.6, 1.75, 1.9, 2.0, 2.0]
	var ramp_ok := true
	for i in range(expected.size()):
		var res := _hit(battle, "CAT", float(i))
		if not _combo_close(float(res["combo"]), float(expected[i])):
			ramp_ok = false
	_check(ramp_ok, "combo ramps +0.15 per quick word and caps at 2.0 (%s)" % str(battle.combo))
	_feq(battle.combo, 2.0, "combo sits at COMBO_CAP after 8 quick words")
	_feq(float(battle.word_count), 9.0, "combo battle accepted 9 words")

	# Window edge: exactly 5.0s after the last word still counts as chained.
	var edge := _battle(5, 3)
	_hit(edge, "CAT", 100.0)
	_feq(float(_hit(edge, "CAT", 105.0)["combo"]), 1.15, "combo chains at exactly 5.0s gap")
	_feq(float(_hit(edge, "CAT", 110.001)["combo"]), 1.0, "combo resets past 5.0s gap")

	# A >5s gap resets to x1.0 and that word deals un-ramped damage.
	var reset := _battle(5, 3)
	_hit(reset, "CAT", 0.0)
	_hit(reset, "CAT", 1.0)
	var after_gap := _hit(reset, "CAT", 10.0)
	_feq(float(after_gap["combo"]), 1.0, "combo resets to 1.0 after >5s gap")
	_feq(float(after_gap["damage"]), 5.0, "gap word deals un-ramped CAT damage")
	_feq(float(_hit(reset, "CAT", 11.0)["combo"]), 1.15, "combo ramps again after reset")

	# combo_changed fires once per accepted word.
	var combo_log: Array = []
	var listener := _battle(1, 1)
	listener.combo_changed.connect(func(new_combo: float) -> void: combo_log.append(new_combo))
	_hit(listener, "CAT", 0.0)
	_hit(listener, "CAT", 1.0)
	_check_eq(combo_log.size(), 2, "combo_changed emitted per accepted word")


func _combo_close(a: float, b: float) -> bool:
	return absf(a - b) <= 0.0001


# ---------------------------------------------------------------- suite 3

func _test_enemy_hp() -> void:
	var z1e1 := _battle(1, 1)
	_feq(z1e1.enemy_max_hp, 40.0, "enemy hp z1e1 non-boss == 40")
	_feq(z1e1.enemy_hp, 40.0, "enemy hp starts full")

	# (40 + 30*0 + 20*2) * 2.5 = 200.
	_feq(_battle(1, 3).enemy_max_hp, 200.0, "enemy hp z1e3 boss == (40+40)*2.5 == 200")

	# (40 + 30*1 + 20*0) = 70.
	_feq(_battle(2, 1).enemy_max_hp, 70.0, "enemy hp z2e1 non-boss == 70")

	# (40 + 30*4 + 20*2) * 2.5 = 500.
	_feq(_battle(5, 3).enemy_max_hp, 500.0, "enemy hp z5e3 final boss == (40+120+40)*2.5 == 500")

	_feq(_battle(1, 1, 1, {}, true).enemy_max_hp, 60.0, "ng_plus z1e1 hp == 40 * 1.5 == 60")
	_feq(_battle(1, 3, 1, {}, true).enemy_max_hp, 300.0, "ng_plus z1e3 boss hp == 200 * 1.5 == 300")
	_feq(_battle(5, 3, 1, {}, true).enemy_max_hp, 750.0, "ng_plus final boss hp == 500 * 1.5 == 750")


# ---------------------------------------------------------------- suite 4

func _test_time_eat() -> void:
	# Interval: 5.0 at zone 1, shrinking 0.3 per zone index, floor 2.5.
	_feq(_battle(1, 1).eat_interval(), 5.0, "eat interval z1 == 5.0")
	_feq(_battle(3, 1).eat_interval(), 4.4, "eat interval z3 == 5.0 - 0.3*2 == 4.4")
	_feq(_battle(5, 1).eat_interval(), 3.8, "eat interval z5 == 5.0 - 0.3*4 == 3.8")
	var deep := BattleManager.new()
	deep.setup({"id": "test_dummy", "zone": 10, "encounter": 1, "is_boss": false}, 1, {}, false)
	_feq(deep.eat_interval(), 2.5, "eat interval clamps at 2.5")

	# Amount: 2 + 0.5 per zone index, minus 0.5 per Ink Armor stack, min 1.
	_check_eq(_battle(1, 1).eat_amount(), 2, "eat amount z1 == 2")
	_check_eq(_battle(3, 1).eat_amount(), 3, "eat amount z3 == 3")
	_check_eq(_battle(5, 1).eat_amount(), 4, "eat amount z5 == 4")
	_check_eq(_battle(2, 1).eat_amount(), 3, "eat amount z2 == 2.5 rounded half == 3")
	_check_eq(_battle(1, 1, 1, {"ink_armor": 3}).eat_amount(), 1,
		"eat amount z1 with 3 Ink Armor == 0.5 rounded then clamped to min 1")
	_check_eq(_battle(5, 1, 1, {"ink_armor": 2}).eat_amount(), 3,
		"eat amount z5 with 2 Ink Armor == 3")

	# Words jam the eat countdown by +1.5s.
	var battle := _battle(1, 1)
	var eats: Array = []
	battle.enemy_eat.connect(func(amount: int) -> void: eats.append(amount))
	battle.tick(4.0, 90.0)
	_check_eq(eats.size(), 0, "no eat fires 4.0s into a 5.0s interval")
	_hit(battle, "CAT", 0.0)
	battle.tick(2.0, 88.0)
	_check_eq(eats.size(), 0, "word jam of +1.5s delays the eat past its deadline")
	battle.tick(0.6, 86.0)
	_check_eq(eats.size(), 1, "eat fires once the jammed countdown expires")
	_check_eq(int(eats[0]), 2, "eat carries amount 2 at zone 1")
	battle.tick(5.0, 80.0)
	_check_eq(eats.size(), 2, "eat interval restarts after firing")

	# Timer hitting zero calls the battle lost, exactly once.
	var loser := _battle(1, 1)
	var lost_log: Array = []
	loser.battle_lost.connect(func() -> void: lost_log.append(true))
	loser.tick(0.1, 0.0)
	_check_eq(lost_log.size(), 1, "battle_lost emitted once when time runs out")
	_check(loser.is_over and not loser.won, "battle is over and not won after timeout")
	loser.tick(1.0, 0.0)
	_check_eq(lost_log.size(), 1, "battle_lost does not re-emit after the battle is over")

	# Start timer: 90s + 5s per Hourglass Pearl.
	_feq(_battle(1, 1).start_time(), 90.0, "start_time == 90 without Hourglass")
	_feq(_battle(1, 1, 1, {"hourglass_pearl": 2}).start_time(), 100.0,
		"start_time == 90 + 2*5 with 2 Hourglass")


# ---------------------------------------------------------------- suite 5

func _test_progression_curve() -> void:
	var prog := Progression.new()
	_check_eq(prog.level, 1, "progression starts at level 1")
	_check_eq(prog.xp_for_next_level(), 50, "level 1 -> 2 curve == 50 * 1^1.4 == 50")

	_check_eq(prog.add_xp(49), false, "add_xp(49) does not level up")
	_check_eq(prog.level, 1, "still level 1 after 49 xp")
	_check_eq(prog.add_xp(1), true, "add_xp crossing 50 levels up")
	_check_eq(prog.level, 2, "level 2 after 50 xp")
	_check_eq(prog.xp, 0, "no xp remainder at exactly 50")
	_check_eq(prog.xp_for_next_level(), 131, "level 2 -> 3 curve == floor(50 * 2^1.4) == 131")

	var carry := Progression.new()
	_check_eq(carry.add_xp(60), true, "add_xp(60) levels up once")
	_check_eq(carry.level, 2, "carry case lands on level 2")
	_check_eq(carry.xp, 10, "xp remainder 10 carried past the 50 threshold")
	_check_eq(carry.add_xp(120), false, "120 more xp stops one short of the 131 curve")
	_check_eq(carry.xp, 130, "xp banked toward level 3")
	_check_eq(carry.add_xp(1), true, "exact curve boundary levels up")
	_check_eq(carry.level, 3, "carry case reaches level 3")
	_check_eq(carry.xp, 0, "no remainder at the exact curve boundary")

	# Gold accrual.
	var rich := Progression.new()
	rich.add_gold(30)
	_check_eq(rich.gold, 30, "add_gold(30) -> 30")
	rich.add_gold(45)
	_check_eq(rich.gold, 75, "add_gold accrues to 75")


# ---------------------------------------------------------------- suite 6

func _test_shop() -> void:
	var prog := Progression.new()
	_check_eq(prog.item_cost("sharp_quill"), 30, "sharp_quill first stack costs base 30")
	_check_eq(prog.item_cost("hourglass_pearl"), 30, "hourglass_pearl first stack costs 30")
	_check_eq(prog.item_cost("ink_armor"), 45, "ink_armor first stack costs 45")
	_check_eq(prog.item_cost("lucky_kelp"), 60, "lucky_kelp first stack costs 60")
	_check_eq(prog.item_cost("golden_starfish"), 80, "golden_starfish first stack costs 80")
	_check_eq(prog.item_cost("not_an_item"), 0, "unknown item costs 0")

	_check_eq(prog.can_buy("sharp_quill"), false, "cannot buy with 0 gold")
	prog.add_gold(1000)
	_check_eq(prog.can_buy("sharp_quill"), true, "can buy with gold in pocket")

	# Escalation 30 -> 48 -> 76 (floor(30 * 1.6^2) == floor(76.8)).
	_check_eq(prog.buy("sharp_quill"), true, "buy sharp_quill #1")
	_check_eq(prog.gold, 970, "gold deducted for stack #1")
	_check_eq(prog.item_cost("sharp_quill"), 48, "sharp_quill stack #2 costs 48")
	_check_eq(prog.buy("sharp_quill"), true, "buy sharp_quill #2")
	_check_eq(prog.item_cost("sharp_quill"), 76, "sharp_quill stack #3 costs floor(76.8) == 76")
	_check_eq(prog.buy("sharp_quill"), true, "buy sharp_quill #3")
	_check_eq(prog.item_cost("sharp_quill"), 122, "sharp_quill stack #4 costs floor(122.88) == 122")
	_check_eq(prog.buy("sharp_quill"), true, "buy sharp_quill #4")
	_check_eq(prog.item_cost("sharp_quill"), 196, "sharp_quill stack #5 costs floor(196.6) == 196")
	_check_eq(prog.buy("sharp_quill"), true, "buy sharp_quill #5")
	_check_eq(prog.upgrades["sharp_quill"], 5, "sharp_quill at 5 stacks")
	_check_eq(prog.gold, 1000 - (30 + 48 + 76 + 122 + 196), "gold spent matches escalated costs")
	_check_eq(prog.can_buy("sharp_quill"), false, "max stacks blocks can_buy")
	_check_eq(prog.buy("sharp_quill"), false, "buy past max stacks fails")
	_check_eq(prog.upgrades["sharp_quill"], 5, "failed buy does not add a stack")
	_check_eq(prog.gold, 528, "failed buy does not charge gold")

	var armor := Progression.new()
	armor.add_gold(1000)
	for i in range(3):
		armor.buy("ink_armor")
	_check_eq(armor.upgrades["ink_armor"], 3, "ink_armor caps at 3 stacks")
	_check_eq(armor.can_buy("ink_armor"), false, "ink_armor max stacks enforced")


# ---------------------------------------------------------------- suite 7

func _test_campaign_flow() -> void:
	var prog := Progression.new()
	_check_eq(String(prog.current_enemy()["id"]), "spelling_bee_rogue",
		"campaign starts on spelling_bee_rogue")
	_check_eq(prog.is_final_victory(), false, "fresh campaign is not final victory")

	# Walk every encounter in order and check the positions along the way.
	var expected: Array = [
		[1, 1], [1, 2], [1, 3], [2, 1], [2, 2], [2, 3],
		[3, 1], [3, 2], [3, 3], [4, 1], [4, 2], [4, 3],
		[5, 1], [5, 2], [5, 3],
	]
	var walker := Progression.new()
	var ids := ["spelling_bee_rogue", "comma_chameleon", "alpha_bet_shark",
		"semicolon_serpent", "participle_jelly", "runon_kraken",
		"silent_e_eel", "schwa_slime", "consonant_crab_king",
		"apostrophe_anglerfish", "hyphen_hydra", "split_infinitive_whale",
		"erratum_urchin", "malaprop_manta", "lexicon_leech"]
	var order_ok := true
	for i in range(expected.size()):
		if int(walker.zone) != int(expected[i][0]) or int(walker.encounter) != int(expected[i][1]):
			order_ok = false
		if String(walker.current_enemy()["id"]) != String(ids[i]):
			order_ok = false
		if bool(walker.current_enemy()["is_boss"]) != (i % 3 == 2):
			order_ok = false
		if String(EnemyDef.enemy_at(walker.zone, walker.encounter)["art"]) \
				!= "res://assets/generated/rpg/%s.png" % ids[i]:
			order_ok = false
		walker.advance_encounter()
	_check(order_ok, "advance_encounter walks all 15 enemies in campaign order")
	_check(walker.ng_plus, "past the final boss ng_plus turns on")
	_check_eq(int(walker.zone), 1, "ng_plus resets zone to 1")
	_check_eq(int(walker.encounter), 1, "ng_plus resets encounter to 1")

	# ng_plus keeps the meta progress.
	var keeper := Progression.new()
	keeper.add_gold(123)
	keeper.add_xp(200)
	keeper.upgrades = {"sharp_quill": 2}
	for i in range(15):
		keeper.advance_encounter()
	_check_eq(keeper.gold, 123, "ng_plus keeps gold")
	_check_eq(keeper.level, 3, "ng_plus keeps level (200 xp -> level 3, 19 xp carried)")
	_check_eq(keeper.xp, 19, "ng_plus keeps the xp remainder")
	_check_eq(int(keeper.upgrades["sharp_quill"]), 2, "ng_plus keeps upgrades")

	# Final victory window: sitting on 5/3 before advancing.
	var finalist := Progression.new()
	finalist.zone = 5
	finalist.encounter = 2
	_check_eq(finalist.is_final_victory(), false, "z5e2 is not the final victory")
	finalist.advance_encounter()
	_check_eq(int(finalist.zone), 5, "advance into z5e3")
	_check_eq(int(finalist.encounter), 3, "advance into z5e3 encounter")
	_check_eq(String(finalist.current_enemy()["id"]), "lexicon_leech", "z5e3 is the Lexicon Leech")
	_check_eq(finalist.is_final_victory(), true, "sitting on the Lexicon Leech is final victory")
	finalist.advance_encounter()
	_check_eq(finalist.is_final_victory(), false, "final victory clears once ng_plus starts")
	_check(finalist.ng_plus, "final advance flags ng_plus")

	# Upgrade-driven multipliers.
	var powered := Progression.new()
	_feq(powered.damage_multiplier(), 1.0, "damage_multiplier level 1 == 1.0")
	powered.level = 5
	powered.upgrades = {"sharp_quill": 2}
	_feq(powered.damage_multiplier(), 1.6 * 1.3, "damage_multiplier level 5 + 2 quill == 2.08")
	_feq(powered.crit_bonus(), 0.0, "crit_bonus without Starfish == 0")
	powered.upgrades = {"golden_starfish": 2}
	_feq(powered.crit_bonus(), 1.0, "crit_bonus 2 Starfish == 1.0")
	_feq(powered.start_timer_seconds(), 90.0, "start_timer_seconds without Hourglass == 90")
	powered.upgrades = {"hourglass_pearl": 2}
	_feq(powered.start_timer_seconds(), 100.0, "start_timer_seconds 2 Hourglass == 100")
	_check_eq(powered.guaranteed_vowels(), 1, "guaranteed_vowels base == 1")
	powered.upgrades = {"lucky_kelp": 1}
	_check_eq(powered.guaranteed_vowels(), 3, "guaranteed_vowels 1 Lucky Kelp == 3")
	powered.upgrades = {"lucky_kelp": 2}
	_check_eq(powered.guaranteed_vowels(), 5, "guaranteed_vowels 2 Lucky Kelp == 5")

	# Roster helpers.
	_check_eq(EnemyDef.all_enemies().size(), 15, "roster holds 15 enemies")
	_check_eq(String(EnemyDef.enemy_at(1, 1)["display_name"]), "Spelling Bee Rogue",
		"enemy_at(1,1) display name")
	_check_eq(String(EnemyDef.enemy_at(5, 3)["display_name"]), "The Lexicon Leech",
		"enemy_at(5,3) display name")
	_check_eq(String(EnemyDef.zone_name(1)), "Coral Spelling Reef", "zone 1 name")
	_check_eq(String(EnemyDef.zone_name(5)), "The Lexicon Leech's Lair", "zone 5 name")
	_check_eq(String(EnemyDef.zone_name(9)), "", "unknown zone name is empty")
	_check(EnemyDef.enemy_at(6, 1).is_empty(), "enemy_at out-of-range zone is empty")
	_check(EnemyDef.enemy_at(1, 4).is_empty(), "enemy_at out-of-range encounter is empty")


# ---------------------------------------------------------------- suite 8

func _test_save_v2() -> void:
	var save_data := SaveData.new()
	var path := ProjectSettings.globalize_path(SaveData.SAVE_PATH)
	DirAccess.remove_absolute(path)

	# Missing file -> arena defaults AND rpg defaults.
	var missing := save_data.load_data()
	var rpg: Dictionary = missing["rpg"]
	_check(int(missing["total_score"]) == 0 and int(missing["highest_round"]) == 0,
		"rpg save missing file -> arena defaults")
	_check(int(rpg["version"]) == 2 and int(rpg["level"]) == 1 and int(rpg["xp"]) == 0
			and int(rpg["gold"]) == 0 and int(rpg["zone"]) == 1 and int(rpg["encounter"]) == 1
			and Dictionary(rpg["upgrades"]).is_empty() and bool(rpg["ng_plus"]) == false,
		"rpg save missing file -> rpg defaults level 1 zone 1")

	# Round trip every rpg field alongside the arena fields.
	var campaign := {
		"level": 3, "xp": 12, "gold": 140, "zone": 2, "encounter": 3,
		"upgrades": {"sharp_quill": 2, "ink_armor": 1}, "ng_plus": false,
	}
	_check(save_data.save(123, 4, {"sound": true, "tutorial_seen": true}, campaign),
		"rpg save round trip writes successfully")
	var loaded := save_data.load_data()
	_check_eq(int(loaded["total_score"]), 123, "rpg save keeps total_score round trip")
	_check_eq(int(loaded["highest_round"]), 4, "rpg save keeps highest_round round trip")
	_check_eq(Dictionary(loaded["settings"]).get("sound"), true, "rpg save keeps settings round trip")
	var loaded_rpg: Dictionary = loaded["rpg"]
	_check(int(loaded_rpg["version"]) == 2 and int(loaded_rpg["level"]) == 3
			and int(loaded_rpg["xp"]) == 12 and int(loaded_rpg["gold"]) == 140
			and int(loaded_rpg["zone"]) == 2 and int(loaded_rpg["encounter"]) == 3
			and bool(loaded_rpg["ng_plus"]) == false,
		"rpg save round trips level/xp/gold/zone/encounter")
	_check_eq(Dictionary(loaded_rpg["upgrades"]).get("sharp_quill"), 2,
		"rpg save round trips upgrades.sharp_quill")
	_check_eq(Dictionary(loaded_rpg["upgrades"]).get("ink_armor"), 1,
		"rpg save round trips upgrades.ink_armor")

	# ng_plus flag round trips too.
	var ng := {
		"level": 2, "xp": 0, "gold": 55, "zone": 1, "encounter": 1,
		"upgrades": {}, "ng_plus": true,
	}
	save_data.save(10, 1, {}, ng)
	var ng_rpg: Dictionary = save_data.load_data()["rpg"]
	_check(bool(ng_rpg["ng_plus"]), "rpg save round trips ng_plus true")
	_check_eq(int(ng_rpg["gold"]), 55, "rpg save round trips gold after ng_plus write")

	# A v1 file (game + settings only, no [rpg]) loads with rpg defaults.
	DirAccess.remove_absolute(path)
	var legacy := ConfigFile.new()
	legacy.set_value("game", "total_score", 77)
	legacy.set_value("game", "highest_round", 2)
	legacy.set_value("settings", "sound", true)
	legacy.save(SaveData.SAVE_PATH)
	var migrated := save_data.load_data()
	_check_eq(int(migrated["total_score"]), 77, "v1 file keeps total_score")
	_check_eq(int(migrated["highest_round"]), 2, "v1 file keeps highest_round")
	_check_eq(Dictionary(migrated["settings"]).get("sound"), true, "v1 file keeps settings")
	var migrated_rpg: Dictionary = migrated["rpg"]
	_check(int(migrated_rpg["level"]) == 1 and int(migrated_rpg["gold"]) == 0
			and int(migrated_rpg["zone"]) == 1 and int(migrated_rpg["encounter"]) == 1
			and Dictionary(migrated_rpg["upgrades"]).is_empty()
			and bool(migrated_rpg["ng_plus"]) == false,
		"v1 file migrates to rpg defaults level 1 zone 1")

	# The old 3-argument save() call still works (arena-only write).
	_check(save_data.save(55, 3, {"sound": false}), "old 3-arg save() call still succeeds")
	var old_style := save_data.load_data()
	_check_eq(int(old_style["total_score"]), 55, "old 3-arg save() round trips arena fields")
	var old_rpg: Dictionary = old_style["rpg"]
	_check(int(old_rpg["level"]) == 1 and Dictionary(old_rpg["upgrades"]).is_empty(),
		"old 3-arg save() yields rpg defaults on load")

	# Corrupt file -> everything defaults, no crash.
	DirAccess.remove_absolute(path)
	var file := FileAccess.open(SaveData.SAVE_PATH, FileAccess.WRITE)
	file.store_string("this is ][ not a valid config {{{")
	file.close()
	var corrupt := save_data.load_data()
	_check(int(corrupt["total_score"]) == 0 and int(Dictionary(corrupt["rpg"])["level"]) == 1,
		"corrupt file -> arena and rpg defaults")

	DirAccess.remove_absolute(path)


# ---------------------------------------------------------------- suite 9

func _test_battle_win_flow() -> void:
	var battle := _battle(1, 1)
	var damaged: Array = []
	var won_log: Array = []
	var lost_log: Array = []
	battle.enemy_damaged.connect(func(amount: float, is_crit: bool, word: String) -> void:
		damaged.append([amount, is_crit, word]))
	battle.battle_won.connect(func(gold: int, xp: int, best_gold: int) -> void:
		won_log.append([gold, xp, best_gold]))
	battle.battle_lost.connect(func() -> void: lost_log.append(true))

	# spelling_bee_rogue has 40 HP; 8 gap-separated CATs deal 5 each.
	for i in range(8):
		var res := _hit(battle, "CAT", float(i) * 10.0)
		_feq(float(res["damage"]), 5.0, "win-flow word %d deals 5 damage" % (i + 1))
	_feq(battle.enemy_hp, 0.0, "enemy hp is 0 after 8 CATs")
	_check(battle.check_win(), "check_win true when enemy hp is spent")
	_check_eq(battle.word_count, 8, "battle recorded 8 words")
	_check_eq(battle.letter_sum_total, 40, "battle recorded letter sum 40")
	_check_eq(battle.crit_count, 0, "no crits in the CAT chain")
	_check_eq(damaged.size(), 8, "enemy_damaged emitted per word")
	_check_eq(lost_log.size(), 0, "no battle_lost while winning")

	# gold = 5*1 + 0 crits*3 + 30s remaining*2 + 60 best category / 2 == 95.
	# xp = 8 words*3 + 40 letter sum/2 + 25*zone 1 == 69.
	var rewards := battle.finish_win(30.0, 60)
	_check_eq(int(rewards["gold"]), 95, "finish_win gold == 95 (5 + 0 + 60 + 30)")
	_check_eq(int(rewards["xp"]), 69, "finish_win xp == 69 (24 + 20 + 25)")
	_check_eq(won_log.size(), 1, "battle_won emitted exactly once")
	_check_eq(int(won_log[0][0]), 95, "battle_won carried gold")
	_check_eq(int(won_log[0][1]), 69, "battle_won carried xp")
	_check_eq(int(won_log[0][2]), 30, "battle_won carried best category gold (60 / 2)")
	_check(battle.is_over and battle.won, "battle flagged over and won")

	# Post-victory words and ticks are inert.
	var late := _hit(battle, "CAT", 999.0)
	_feq(float(late["damage"]), 0.0, "word after victory deals no damage")
	_check_eq(damaged.size(), 8, "no extra enemy_damaged after victory")
	battle.tick(1.0, 20.0)
	_check_eq(lost_log.size(), 0, "no battle_lost after victory")
	var again := battle.finish_win(10.0, 60)
	_check_eq(int(again["gold"]), 0, "second finish_win banks nothing")
	_check_eq(won_log.size(), 1, "battle_won still emitted exactly once")

	# Crit gold: two 7-letter crits kill z1e1 (2 x 20 damage).
	var crit_battle := _battle(1, 1)
	var crit_won: Array = []
	crit_battle.battle_won.connect(func(gold: int, _xp: int, best_gold: int) -> void:
		crit_won.append([gold, best_gold]))
	_hit(crit_battle, "COASTED", 0.0)
	_hit(crit_battle, "COASTED", 10.0)
	_check(crit_battle.check_win(), "two COASTED crits fell the z1e1 enemy")
	_check_eq(crit_battle.crit_count, 2, "crit_count == 2 for the crit battle")
	# gold = 5*1 + 2 crits*3 + 0s*2 + floor(61/2) == 41, xp = 6 + 20/2 + 25 == 41.
	var crit_rewards := crit_battle.finish_win(0.0, 61)
	_check_eq(int(crit_rewards["gold"]), 41, "crit gold == 41 (5 + 6 + 0 + 30)")
	_check_eq(int(crit_rewards["xp"]), 41, "crit xp == 41 (6 + 10 + 25)")
	_check_eq(int(crit_won[0][1]), 30, "odd best category floors to 30 bonus gold")


# ---------------------------------------------------------------- suite 10

func _test_word_set() -> void:
	var db := WordDatabase.new()
	_check(db.tier() == "" and db.words().size() > 0,
		"constructor keeps the default list with no active tier")

	# COMMON: everyday words only.
	db.set_tier("common")
	_check_eq(db.tier(), "common", "set_tier(common) -> tier")
	_check(db.is_common(), "set_tier(common) -> is_common")
	_check(db.is_valid_word("HOUSE"), "COMMON accepts HOUSE")
	_check(db.is_valid_word("THEATRES"), "COMMON accepts THEATRES")
	_check(db.is_valid_word("house"), "COMMON accepts lowercase house")
	_check(not db.is_valid_word("AAHED"), "COMMON rejects AAHED")
	_check_eq(db.words().size(), 26955, "COMMON list holds 26955 words")

	# Re-selecting the active tier is a no-op.
	db.set_tier("common")
	_check_eq(db.tier(), "common", "set_tier to the active tier is a no-op")
	_check_eq(db.words().size(), 26955, "no-op set_tier leaves the dictionary loaded")

	# STANDARD: full dictionary standard, still without the deep-catalog AAHED.
	db.set_tier("standard")
	_check_eq(db.tier(), "standard", "set_tier(standard) -> tier")
	_check(not db.is_common(), "set_tier(standard) -> not is_common")
	_check(db.is_valid_word("HOUSE"), "STANDARD accepts HOUSE")
	_check(db.is_valid_word("THEATRES"), "STANDARD accepts THEATRES")
	_check(not db.is_valid_word("AAHED"), "STANDARD rejects AAHED")
	_check_eq(db.words().size(), 41092, "STANDARD list holds 41092 words")

	# EXPERT: the deep dictionary, US & UK spellings.
	db.set_tier("expert")
	_check_eq(db.tier(), "expert", "set_tier(expert) -> tier")
	_check(not db.is_common(), "set_tier(expert) -> not is_common")
	_check(db.is_valid_word("AAHED"), "EXPERT accepts AAHED")
	_check(db.is_valid_word("HOUSE"), "EXPERT still accepts HOUSE")
	_check(db.is_valid_word("THEATRES"), "EXPERT still accepts THEATRES")
	_check_eq(db.words().size(), 104251, "EXPERT list holds 104251 words")

	# Legacy alias: use_common(true) -> COMMON, use_common(false) -> EXPERT.
	db.use_common(true)
	_check(db.is_common(), "use_common(true) -> is_common")
	_check_eq(db.tier(), "common", "use_common(true) maps to the common tier")
	db.use_common(false)
	_check(db.is_common() == false, "use_common(false) -> not is_common")
	_check_eq(db.tier(), "expert", "use_common(false) maps to the expert tier")
	_check_eq(db.words().size(), 104251, "use_common(false) loads the expert list")

	# Bogus tier: warns but never crashes, and the dictionary is left alone.
	var expert_count: int = db.words().size()
	db.set_tier("klingon")
	_check_eq(db.tier(), "expert", "bogus tier leaves the active tier unchanged")
	_check_eq(db.words().size(), expert_count, "bogus tier leaves the dictionary unchanged")


# ---------------------------------------------------------------- suite 11

func _test_sfx() -> void:
	var sfx := SfxManager.new()
	# Orphan manager (no tree, empty pool): play() must be a safe no-op.
	sfx.play("click")
	sfx.play("not_a_real_cue")
	root.add_child(sfx)
	_check_eq(sfx.get_child_count(), 8, "sfx builds a pool of 8 players")

	# Every known cue name plays through the pool.
	var all_play := true
	for cue in ["click", "accept", "reject", "crit", "levelup",
			"victory", "gameover", "eat", "coin", "bonus"]:
		_sfx_wipe_streams(sfx)
		sfx.play(cue)
		if _sfx_stream_count(sfx) == 0:
			all_play = false
	_check(all_play, "sfx plays all 10 cues (click/accept/reject/crit/levelup/victory/gameover/eat/coin/bonus)")

	# Unknown name: silent no-op, nothing assigned.
	_sfx_wipe_streams(sfx)
	sfx.play("not_a_real_cue")
	_check_eq(_sfx_stream_count(sfx), 0, "unknown cue name is a silent no-op")

	# set_muted(true) stops whatever is playing...
	sfx.play("victory")
	sfx.set_muted(true)
	_check(not _sfx_any_playing(sfx), "set_muted(true) stops a playing cue")

	# ...and muted plays assign nothing.
	_sfx_wipe_streams(sfx)
	sfx.play("click")
	_check_eq(_sfx_stream_count(sfx), 0, "muted play() assigns no stream")

	# Unmute -> plays again.
	sfx.set_muted(false)
	sfx.play("coin")
	_check(_sfx_stream_count(sfx) > 0, "unmuted play() assigns a stream again")


func _sfx_wipe_streams(sfx: SfxManager) -> void:
	for player in sfx.get_children():
		player.set("stream", null)


func _sfx_stream_count(sfx: SfxManager) -> int:
	var count := 0
	for player in sfx.get_children():
		if player.get("stream") != null:
			count += 1
	return count


func _sfx_any_playing(sfx: SfxManager) -> bool:
	for player in sfx.get_children():
		if bool(player.get("playing")):
			return true
	return false
