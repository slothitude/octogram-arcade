class_name Progression
extends RefCounted
## Campaign meta-state: level/xp curve, gold, shop purchase rules, zone/encounter
## gating and New Game+. Pure logic, persists through SaveData's [rpg] section.

var level: int = 1
var xp: int = 0
var gold: int = 0
var upgrades: Dictionary = {}
var zone: int = 1
var encounter: int = 1
var ng_plus: bool = false
var sound: bool = true


## XP needed to go from `level` to level + 1: 50 * level^1.4 (floored).
func xp_for_next_level() -> int:
	return int(RpgConfig.LEVEL_CURVE_BASE * pow(float(level), RpgConfig.LEVEL_CURVE_EXP))


## Bank xp, carrying the remainder across level-ups. Returns true when the
## level increased (possibly more than once).
func add_xp(amount: int) -> bool:
	var leveled_up := false
	xp += amount
	while xp >= xp_for_next_level():
		xp -= xp_for_next_level()
		level += 1
		leveled_up = true
	return leveled_up


func add_gold(amount: int) -> void:
	gold += amount


## Cost of the next stack of an item: base_cost * 1.6^owned (floored).
## Unknown ids cost 0 (and can never be bought).
func item_cost(item_id: String) -> int:
	var item: Dictionary = RpgConfig.SHOP_ITEMS.get(item_id, {})
	if item.is_empty():
		return 0
	var owned := int(upgrades.get(item_id, 0))
	return int(float(int(item["base_cost"])) * pow(RpgConfig.COST_ESCALATION, float(owned)))


func can_buy(item_id: String) -> bool:
	var item: Dictionary = RpgConfig.SHOP_ITEMS.get(item_id, {})
	if item.is_empty():
		return false
	var max_stacks := int(item["max_stacks"])
	return gold >= item_cost(item_id) and int(upgrades.get(item_id, 0)) < max_stacks


## Buy one stack if affordable and under the cap. Returns true on success.
func buy(item_id: String) -> bool:
	if not can_buy(item_id):
		return false
	gold -= item_cost(item_id)
	upgrades[item_id] = int(upgrades.get(item_id, 0)) + 1
	return true


## Word damage multiplier from level and Sharp Quill: (1 + 0.15*(level-1))
## * (1 + 0.15*quill_stacks).
func damage_multiplier() -> float:
	var level_mult := 1.0 + RpgConfig.LEVEL_MULT_PER_LEVEL * float(level - 1)
	var quill_mult := 1.0 + RpgConfig.SHARP_QUILL_MULT * float(int(upgrades.get("sharp_quill", 0)))
	return level_mult * quill_mult


## Round length: 90s + 5s per Hourglass Pearl.
func start_timer_seconds() -> float:
	return RpgConfig.BASE_TIMER + RpgConfig.HOURGLASS_SECONDS * int(upgrades.get("hourglass_pearl", 0))


## Vowels guaranteed in a draw: 1 by default, +2 per Lucky Kelp.
func guaranteed_vowels() -> int:
	return 1 + RpgConfig.LUCKY_KELP_VOWELS * int(upgrades.get("lucky_kelp", 0))


## Added to both crit multipliers: 0.5 per Golden Starfish.
func crit_bonus() -> float:
	return RpgConfig.STARFISH_CRIT_BONUS * float(int(upgrades.get("golden_starfish", 0)))


## Next battle. Past the final boss the campaign loops into New Game+:
## zone 1 encounter 1 with ng_plus set (level/gold/upgrades are kept).
func advance_encounter() -> void:
	encounter += 1
	if encounter > RpgConfig.ENCOUNTERS_PER_ZONE:
		encounter = 1
		zone += 1
		if zone > RpgConfig.TOTAL_ZONES:
			ng_plus = true
			zone = 1
			encounter = 1


## The enemy definition for the current campaign position.
func current_enemy() -> Dictionary:
	return EnemyDef.enemy_at(zone, encounter)


## True while sitting on the final boss before it has been beaten.
func is_final_victory() -> bool:
	return zone == RpgConfig.TOTAL_ZONES and encounter == RpgConfig.ENCOUNTERS_PER_ZONE and not ng_plus
