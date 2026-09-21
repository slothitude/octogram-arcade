class_name BattleManager
extends RefCounted
## One battle against one enemy: the word->damage pipeline, combo tracking and
## the enemy's time-eat clock. Pure logic, no scene/UI dependencies; the caller
## owns the round (letters, dictionary, player timer) and drives tick().

signal enemy_damaged(amount: float, is_crit: bool, word: String)
signal enemy_eat(amount: int)
signal battle_won(gold: int, xp: int, best_category_gold: int)
signal battle_lost
signal combo_changed(new_combo: float)

var enemy: Dictionary = {}
var enemy_hp: float = 0.0
var enemy_max_hp: float = 0.0
var combo: float = 1.0
var player_level: int = 1
var upgrades: Dictionary = {}
var ng_plus: bool = false
var elapsed: float = 0.0
var is_over: bool = false
var won: bool = false

## Battle record, used by the win rewards.
var word_count: int = 0
var letter_sum_total: int = 0
var crit_count: int = 0

var zone: int = 1
var encounter: int = 1

var _last_word_time: float = -1.0
var _eat_timer: float = 0.0


## enemy_dict is an EnemyDef.all_enemies() entry; upgrades maps item id -> stacks.
func setup(enemy_dict: Dictionary, level: int, upgrade_counts: Dictionary, is_ng_plus: bool) -> void:
	enemy = enemy_dict
	player_level = level
	upgrades = upgrade_counts.duplicate()
	ng_plus = is_ng_plus
	zone = int(enemy.get("zone", 1))
	encounter = int(enemy.get("encounter", 1))

	var boss_mult := RpgConfig.BOSS_HP_MULT if bool(enemy.get("is_boss", false)) else 1.0
	var ng_mult := RpgConfig.NG_PLUS_HP_MULT if ng_plus else 1.0
	enemy_max_hp = (RpgConfig.ENEMY_HP_BASE + RpgConfig.ENEMY_HP_ZONE * (zone - 1) \
			+ RpgConfig.ENEMY_HP_ENCOUNTER * (encounter - 1)) * boss_mult * ng_mult
	enemy_hp = enemy_max_hp

	combo = 1.0
	elapsed = 0.0
	is_over = false
	won = false
	word_count = 0
	letter_sum_total = 0
	crit_count = 0
	_last_word_time = -1.0
	_eat_timer = eat_interval()


## Player round length: 90s + 5s per Hourglass Pearl.
func start_time() -> float:
	return RpgConfig.BASE_TIMER + RpgConfig.HOURGLASS_SECONDS * _stacks("hourglass_pearl")


## Seconds between enemy time-eats: 5.0 shrinking 0.3 per zone index, floor 2.5.
func eat_interval() -> float:
	var raw := RpgConfig.EAT_INTERVAL_BASE - RpgConfig.EAT_INTERVAL_ZONE_STEP * float(zone - 1)
	return maxf(RpgConfig.EAT_INTERVAL_MIN, raw)


## Seconds the enemy eats per attack: 2 + 0.5 per zone index (rounded half),
## minus 0.5 per Ink Armor stack, never below 1.
func eat_amount() -> int:
	var raw := RpgConfig.EAT_AMOUNT_BASE + RpgConfig.EAT_AMOUNT_ZONE_STEP * float(zone - 1) \
			- RpgConfig.INK_ARMOR_REDUCTION * float(_stacks("ink_armor"))
	return maxi(1, int(round(raw)))


## Feed an accepted word at time_now (seconds, same clock as tick). Returns
## {damage, is_crit, combo}. The combo multiplier in effect for THIS word is the
## updated one: a word inside the window ramps it (+0.15, cap x2.0), a word
## after a gap or the first word of the fight uses x1.0.
func on_word_accepted(word: String, time_now: float) -> Dictionary:
	if is_over or enemy_hp <= 0.0:
		return {"damage": 0.0, "is_crit": false, "combo": combo}

	var chained := _last_word_time >= 0.0 and (time_now - _last_word_time) <= RpgConfig.COMBO_WINDOW
	if chained:
		combo = minf(combo + RpgConfig.COMBO_STEP, RpgConfig.COMBO_CAP)
	else:
		combo = 1.0
	_last_word_time = time_now
	combo_changed.emit(combo)

	var letters := ScoreManager.letter_sum(word)
	var crit_mult := _crit_mult(word.length())
	var is_crit := crit_mult > 1.0
	var damage := float(letters) * _level_mult() * _quill_mult() * combo * crit_mult

	word_count += 1
	letter_sum_total += letters
	if is_crit:
		crit_count += 1

	_eat_timer += RpgConfig.WORD_JAM_SECONDS
	enemy_hp = maxf(0.0, enemy_hp - damage)
	enemy_damaged.emit(damage, is_crit, word)

	return {"damage": damage, "is_crit": is_crit, "combo": combo}


## True once the enemy's HP is spent (call after on_word_accepted).
func check_win() -> bool:
	return enemy_hp <= 0.0


## Bank the victory: remaining_seconds is the player timer left, best_category
## is the best Word Poker category value. Returns {gold, xp} and emits
## battle_won(gold, xp, best_category_gold) exactly once.
func finish_win(remaining_seconds: float, best_category: int) -> Dictionary:
	if is_over:
		return {"gold": 0, "xp": 0}
	is_over = true
	won = true

	var best_gold := int(float(best_category) / float(RpgConfig.GOLD_CATEGORY_DIV))
	var gold := RpgConfig.GOLD_ZONE_MULT * zone + crit_count * RpgConfig.GOLD_CRIT \
			+ int(remaining_seconds) * RpgConfig.GOLD_TIME_MULT + best_gold
	var xp := RpgConfig.XP_PER_WORD * word_count \
			+ int(float(letter_sum_total) / float(RpgConfig.XP_LETTER_SUM_DIV)) \
			+ RpgConfig.XP_WIN_ZONE_MULT * zone

	battle_won.emit(gold, xp, best_gold)
	return {"gold": gold, "xp": xp}


## Advance the battle clock by delta; time_left is the player timer. Fires the
## enemy's time-eat when its countdown runs out, and calls the battle lost when
## the player's timer is spent.
func tick(delta: float, time_left: float) -> void:
	if is_over:
		return
	elapsed += delta
	_eat_timer -= delta
	if _eat_timer <= 0.0:
		_eat_timer = eat_interval()
		enemy_eat.emit(eat_amount())
	if time_left <= 0.0:
		is_over = true
		won = false
		battle_lost.emit()


func _stacks(item_id: String) -> int:
	return int(upgrades.get(item_id, 0))


func _level_mult() -> float:
	return 1.0 + RpgConfig.LEVEL_MULT_PER_LEVEL * float(player_level - 1)


func _quill_mult() -> float:
	return 1.0 + RpgConfig.SHARP_QUILL_MULT * float(_stacks("sharp_quill"))


func _crit_mult(word_length: int) -> float:
	if word_length >= ScoreManager.LETTER_COUNT:
		return RpgConfig.CRIT_8 + _starfish_bonus()
	if word_length >= ScoreManager.LONG_WORD_MIN_LENGTH:
		return RpgConfig.CRIT_7 + _starfish_bonus()
	return 1.0


func _starfish_bonus() -> float:
	return RpgConfig.STARFISH_CRIT_BONUS * float(_stacks("golden_starfish"))
