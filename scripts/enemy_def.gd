class_name EnemyDef
extends RefCounted
## Static roster of the 15 campaign enemies: 5 zones x 3 encounters, the 3rd of
## each zone being its boss. Names/zones follow rpg_design.md exactly.

const ZONE_NAMES := {
	1: "Coral Spelling Reef",
	2: "Kelp Forest of Clauses",
	3: "Trench of Lost Vowels",
	4: "Abyssal Grammar Rift",
	5: "The Lexicon Leech's Lair",
}


## All 15 enemies in campaign order (zone 1 encounter 1 -> zone 5 encounter 3).
static func all_enemies() -> Array:
	return [
		{
			"id": "spelling_bee_rogue",
			"display_name": "Spelling Bee Rogue",
			"zone": 1,
			"encounter": 1,
			"is_boss": false,
			"art": "res://assets/generated/rpg/spelling_bee_rogue.png",
			"taunt": "Buzz off, novice!",
		},
		{
			"id": "comma_chameleon",
			"display_name": "Comma Chameleon",
			"zone": 1,
			"encounter": 2,
			"is_boss": false,
			"art": "res://assets/generated/rpg/comma_chameleon.png",
			"taunt": "Comma on, you can do better than that.",
		},
		{
			"id": "alpha_bet_shark",
			"display_name": "Alpha Bet Shark",
			"zone": 1,
			"encounter": 3,
			"is_boss": true,
			"art": "res://assets/generated/rpg/alpha_bet_shark.png",
			"taunt": "You're gonna need a bigger word.",
		},
		{
			"id": "semicolon_serpent",
			"display_name": "Semicolon Serpent",
			"zone": 2,
			"encounter": 1,
			"is_boss": false,
			"art": "res://assets/generated/rpg/semicolon_serpent.png",
			"taunt": "I'm half fangs, half puns;",
		},
		{
			"id": "participle_jelly",
			"display_name": "Dangling Participle Jelly",
			"zone": 2,
			"encounter": 2,
			"is_boss": false,
			"art": "res://assets/generated/rpg/participle_jelly.png",
			"taunt": "Just hanging around, like me.",
		},
		{
			"id": "runon_kraken",
			"display_name": "Run-On Sentence Kraken",
			"zone": 2,
			"encounter": 3,
			"is_boss": true,
			"art": "res://assets/generated/rpg/runon_kraken.png",
			"taunt": "I never stop and neither will I ever and you can't make me",
		},
		{
			"id": "silent_e_eel",
			"display_name": "Silent-E Eel",
			"zone": 3,
			"encounter": 1,
			"is_boss": false,
			"art": "res://assets/generated/rpg/silent_e_eel.png",
			"taunt": "Shhh... I was never even here.",
		},
		{
			"id": "schwa_slime",
			"display_name": "Schwa Slimer",
			"zone": 3,
			"encounter": 2,
			"is_boss": false,
			"art": "res://assets/generated/rpg/schwa_slime.png",
			"taunt": "Meh. It's my favourite sound.",
		},
		{
			"id": "consonant_crab_king",
			"display_name": "Consonant Crab King",
			"zone": 3,
			"encounter": 3,
			"is_boss": true,
			"art": "res://assets/generated/rpg/consonant_crab_king.png",
			"taunt": "No vowels allowed in my kingdom.",
		},
		{
			"id": "apostrophe_anglerfish",
			"display_name": "Apostrophe Anglerfish",
			"zone": 4,
			"encounter": 1,
			"is_boss": false,
			"art": "res://assets/generated/rpg/apostrophe_anglerfish.png",
			"taunt": "That word? It's mine, it's all mine!",
		},
		{
			"id": "hyphen_hydra",
			"display_name": "Hyphen Hydra",
			"zone": 4,
			"encounter": 2,
			"is_boss": false,
			"art": "res://assets/generated/rpg/hyphen_hydra.png",
			"taunt": "Cut off one head, two more pop-up.",
		},
		{
			"id": "split_infinitive_whale",
			"display_name": "Split Infinitive Whale",
			"zone": 4,
			"encounter": 3,
			"is_boss": true,
			"art": "res://assets/generated/rpg/split_infinitive_whale.png",
			"taunt": "I intend to firmly crush you.",
		},
		{
			"id": "erratum_urchin",
			"display_name": "Erratum Urchin",
			"zone": 5,
			"encounter": 1,
			"is_boss": false,
			"art": "res://assets/generated/rpg/erratum_urchin.png",
			"taunt": "Every typo you make, I keep.",
		},
		{
			"id": "malaprop_manta",
			"display_name": "Malaprop Manta",
			"zone": 5,
			"encounter": 2,
			"is_boss": false,
			"art": "res://assets/generated/rpg/malaprop_manta.png",
			"taunt": "Prepare to be flabberghasted. Or is it flabbergasted?",
		},
		{
			"id": "lexicon_leech",
			"display_name": "The Lexicon Leech",
			"zone": 5,
			"encounter": 3,
			"is_boss": true,
			"art": "res://assets/generated/rpg/lexicon_leech.png",
			"taunt": "Your words look delicious. Hand them all over.",
		},
	]


## The enemy for a campaign position, or {} when out of range.
static func enemy_at(zone: int, encounter: int) -> Dictionary:
	if zone < 1 or zone > RpgConfig.TOTAL_ZONES:
		return {}
	if encounter < 1 or encounter > RpgConfig.ENCOUNTERS_PER_ZONE:
		return {}
	return all_enemies()[(zone - 1) * RpgConfig.ENCOUNTERS_PER_ZONE + (encounter - 1)]


## Display name of a zone, or "" when out of range.
static func zone_name(zone: int) -> String:
	return String(ZONE_NAMES.get(zone, ""))
