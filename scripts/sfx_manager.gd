class_name SfxManager
extends Node
## Tiny sound-cue bank: preloads the 10 generated WAVs and plays them through a
## round-robin pool of AudioStreamPlayers so overlapping cues never cut each
## other off. AudioStreamWAV only (the format the web build can load).
## main.gd owns the shared instance; BattleUi receives it via its `sfx` var.

const SOUNDS := {
	"click": preload("res://assets/generated/sfx/click.wav"),
	"accept": preload("res://assets/generated/sfx/accept.wav"),
	"reject": preload("res://assets/generated/sfx/reject.wav"),
	"crit": preload("res://assets/generated/sfx/crit.wav"),
	"levelup": preload("res://assets/generated/sfx/levelup.wav"),
	"victory": preload("res://assets/generated/sfx/victory.wav"),
	"gameover": preload("res://assets/generated/sfx/gameover.wav"),
	"eat": preload("res://assets/generated/sfx/eat.wav"),
	"coin": preload("res://assets/generated/sfx/coin.wav"),
	"bonus": preload("res://assets/generated/sfx/bonus.wav"),
}

const POOL_SIZE := 8

var _muted := false
var _pool: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "SfxPlayer%d" % i
		add_child(player)
		_pool.append(player)


## Play one of the SOUNDS cues. No-op when muted, when the name is unknown, or
## when the manager is not in the tree yet (empty pool).
func play(sfx_name: String) -> bool:
	if _muted or not SOUNDS.has(sfx_name) or _pool.is_empty():
		return false
	var player := _pool[_next]
	_next = (_next + 1) % _pool.size()
	player.stop()
	player.stream = SOUNDS[sfx_name]
	player.play()
	return true


## Mute/unmute; muting also silences anything currently playing.
func set_muted(muted: bool) -> void:
	_muted = muted
	if _muted:
		for player in _pool:
			player.stop()
