class_name RpgConfig
extends RefCounted
## Every tunable RPG number, straight from rpg_design.md ("Math" section).
## Pure data: no logic, no state.

## Player level damage multiplier: 1 + LEVEL_MULT_PER_LEVEL * (level - 1)
const LEVEL_MULT_PER_LEVEL := 0.15

## Crit multipliers: 7-letter words xCRIT_7, 8-letter words xCRIT_8.
const CRIT_7 := 2.0
const CRIT_8 := 3.0

## Combo: each word within COMBO_WINDOW seconds of the last adds COMBO_STEP,
## capped at COMBO_CAP.
const COMBO_STEP := 0.15
const COMBO_CAP := 2.0
const COMBO_WINDOW := 5.0

## Any accepted word pushes the enemy's next attack back by this many seconds.
const WORD_JAM_SECONDS := 1.5

## Enemy max HP = (ENEMY_HP_BASE + ENEMY_HP_ZONE * zone_idx + ENEMY_HP_ENCOUNTER
## * encounter_idx) * (BOSS_HP_MULT if boss), indices 0-based.
const ENEMY_HP_BASE := 40
const ENEMY_HP_ZONE := 30
const ENEMY_HP_ENCOUNTER := 20
const BOSS_HP_MULT := 2.5
const NG_PLUS_HP_MULT := 1.5

## Time-eat: interval = max(EAT_INTERVAL_MIN, EAT_INTERVAL_BASE
## - EAT_INTERVAL_ZONE_STEP * zone_idx); amount = 2 + 0.5 * zone_idx seconds,
## reduced 0.5 per Ink Armor stack.
const EAT_INTERVAL_BASE := 5.0
const EAT_INTERVAL_ZONE_STEP := 0.3
const EAT_INTERVAL_MIN := 2.5
const EAT_AMOUNT_BASE := 2.0
const EAT_AMOUNT_ZONE_STEP := 0.5
const INK_ARMOR_REDUCTION := 0.5

## Upgrades.
const SHARP_QUILL_MULT := 0.15
const HOURGLASS_SECONDS := 5.0
const INK_ARMOR_MAX_STACKS := 3
const LUCKY_KELP_VOWELS := 2
const STARFISH_CRIT_BONUS := 0.5

## Battle timer.
const BASE_TIMER := 90.0

## XP = XP_PER_WORD * words + total letter_sum / XP_LETTER_SUM_DIV
## + XP_WIN_ZONE_MULT * zone_number (on win). Level curve: 50 * level^1.4.
const XP_PER_WORD := 3
const XP_LETTER_SUM_DIV := 2
const XP_WIN_ZONE_MULT := 25
const LEVEL_CURVE_BASE := 50.0
const LEVEL_CURVE_EXP := 1.4

## Gold = GOLD_ZONE_MULT * zone_number + crits * GOLD_CRIT
## + remaining_seconds * GOLD_TIME_MULT + best_category / GOLD_CATEGORY_DIV.
const GOLD_ZONE_MULT := 5
const GOLD_CRIT := 3
const GOLD_TIME_MULT := 2
const GOLD_CATEGORY_DIV := 2

## Shop: base costs escalate by COST_ESCALATION per stack already owned.
const SHOP_ITEMS := {
	"sharp_quill": {
		"name": "Sharp Quill",
		"desc": "+15% word damage per stack.",
		"base_cost": 30,
		"max_stacks": 5,
	},
	"hourglass_pearl": {
		"name": "Hourglass Pearl",
		"desc": "+5s start time per stack.",
		"base_cost": 30,
		"max_stacks": 5,
	},
	"ink_armor": {
		"name": "Ink Armor",
		"desc": "Enemy eats 0.5s less per stack.",
		"base_cost": 45,
		"max_stacks": 3,
	},
	"lucky_kelp": {
		"name": "Lucky Kelp",
		"desc": "Guarantees 2 extra vowels in the draw per stack.",
		"base_cost": 60,
		"max_stacks": 2,
	},
	"golden_starfish": {
		"name": "Golden Starfish",
		"desc": "+0.5 to both crit multipliers per stack.",
		"base_cost": 80,
		"max_stacks": 3,
	},
}
const COST_ESCALATION := 1.6

## Campaign shape.
const TOTAL_ZONES := 5
const ENCOUNTERS_PER_ZONE := 3
