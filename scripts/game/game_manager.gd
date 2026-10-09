# Game Manager - Autoload singleton
extends Node

signal run_started()
signal run_ended(victory: bool)
signal score_changed(score: int)

enum GameState {
	MENU,
	PLAYING,
	PAUSED,
	GAME_OVER,
	VICTORY
}

var current_state: GameState = GameState.MENU

# Run statistics
var current_score: int = 0
var enemies_killed: int = 0
var rooms_cleared: int = 0
var run_time: float = 0.0

# Player reference
var player: Node = null
var run_seed: int = 0
var best_score: int = 0
var completed_runs: int = 0
var victories: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var save := ConfigFile.new()
	if save.load("user://progress.cfg") == OK:
		best_score = int(save.get_value("progress", "best_score", 0))
		completed_runs = int(save.get_value("progress", "completed_runs", 0))
		victories = int(save.get_value("progress", "victories", 0))

func _process(delta: float) -> void:
	if current_state == GameState.PLAYING:
		run_time += delta

func start_run() -> void:
	get_tree().paused = false
	current_score = 0
	enemies_killed = 0
	rooms_cleared = 0
	run_time = 0.0
	current_state = GameState.PLAYING
	run_started.emit()
	print("Run started!")

func end_run(victory: bool) -> void:
	if current_state in [GameState.GAME_OVER, GameState.VICTORY, GameState.MENU]:
		return
	if victory:
		current_state = GameState.VICTORY
	else:
		current_state = GameState.GAME_OVER
	
	best_score = maxi(best_score, current_score)
	completed_runs += 1
	if victory:
		victories += 1
	var save := ConfigFile.new()
	save.set_value("progress", "best_score", best_score)
	save.set_value("progress", "completed_runs", completed_runs)
	save.set_value("progress", "victories", victories)
	var save_error := save.save("user://progress.cfg")
	if save_error != OK:
		push_warning("Could not save run records: %s" % error_string(save_error))
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	run_ended.emit(victory)
	print("Run ended! Victory: %s, Score: %d, Time: %.1fs" % [victory, current_score, run_time])

func add_score(amount: int) -> void:
	current_score += amount
	score_changed.emit(current_score)

func enemy_killed() -> void:
	enemies_killed += 1
	add_score(100)

func room_cleared() -> void:
	rooms_cleared += 1
	add_score(500)

func pause_game() -> void:
	if current_state == GameState.PLAYING:
		current_state = GameState.PAUSED
		get_tree().paused = true

func resume_game() -> void:
	if current_state == GameState.PAUSED:
		current_state = GameState.PLAYING
		get_tree().paused = false

func toggle_pause() -> void:
	if current_state == GameState.PLAYING:
		pause_game()
	elif current_state == GameState.PAUSED:
		resume_game()

func get_run_stats() -> Dictionary:
	return {
		"score": current_score,
		"enemies_killed": enemies_killed,
		"rooms_cleared": rooms_cleared,
		"run_time": run_time
	}
