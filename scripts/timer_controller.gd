class_name TimerController
extends RefCounted
## Countdown logic for a round. Driven manually via tick(delta) so it can be
## tested headless and wired to any node's _process by the UI layer.

signal timeout()

var time_left: float = 0.0
var duration: float = 0.0
var _running: bool = false
var _paused: bool = false


## Reset and start the countdown.
func start(duration_secs: float = ScoreManager.ROUND_TIME) -> void:
	duration = duration_secs
	time_left = duration_secs
	_paused = false
	_running = true


## Advance the countdown by delta seconds. Emits timeout() exactly once when
## time_left reaches zero; the timer stops itself at that point.
func tick(delta: float) -> void:
	if not _running or _paused:
		return
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		stop()
		timeout.emit()


func pause() -> void:
	_paused = true


func resume() -> void:
	_paused = false


func stop() -> void:
	_running = false
	_paused = false


func is_running() -> bool:
	return _running


func is_paused() -> bool:
	return _paused
