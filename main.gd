extends Node

# --- Tuning knobs ---
const SCORE_PER_COIN := 5           # Score needed per coin when a run ends
const KILL_SCORE := 3               # Bonus score for each mob killed
const BASE_MOB_HEALTH := 2
const SCORE_PER_EXTRA_MOB_HP := 30  # Mobs gain +1 HP for every N points of score
const EXIT_AWARDS_COINS := true     # Leaving a run from the pause menu still converts its score to coins (false = the run is just thrown away)

@export var mob_scene: PackedScene
var score := 0
var kills := 0
var game_running = false
var _pause_menu: PauseMenu


func _ready():
	$MobTimer.stop()
	$ScoreTimer.stop()
	$Player.health_changed.connect($HUD.update_health)
	_pause_menu = PauseMenu.new()  # Escape pauses during a run (built in code, see pause_menu.gd)
	add_child(_pause_menu)
	_pause_menu.exit_requested.connect(exit_to_menu)


func game_over():
	# The player died: always convert this run's score into permanent coins
	var earned := _end_run(true)
	$HUD.show_game_over(score, earned, SaveData.get_coins())


# Called from the pause menu's Exit button: abandons the run and returns to the title screen.
func exit_to_menu() -> void:
	var earned := _end_run(EXIT_AWARDS_COINS)
	$HUD.show_title(score, earned, SaveData.get_coins())


# Everything the two ways of ending a run have in common: stops the run's timers, clears the
# mobs, and (if award_coins) converts the score into coins. Returns the coins earned.
func _end_run(award_coins: bool) -> int:
	get_tree().paused = false  # Exit can be pressed while paused
	game_running = false
	_pause_menu.run_active = false
	$StartTimer.stop()  # In case the run ends during "Get Ready!"
	$ScoreTimer.stop()
	$MobTimer.stop()
	get_tree().call_group(Groups.MOBS, "queue_free")
	$Player.stop_run()  # Harmless if the player already died: it only stops attacks and hides

	var earned := 0
	if award_coins:
		earned = floori(score / float(SCORE_PER_COIN))
		SaveData.add_coins(earned)
	return earned


func new_game(character: CharacterData = null):
	# The HUD's character screen passes the chosen character
	if character != null:
		$Player.set_character(character)
	game_running = true
	_pause_menu.run_active = true
	score = 0
	kills = 0
	$MobTimer.stop()
	$ScoreTimer.stop()
	get_tree().call_group(Groups.MOBS, "queue_free")
	$Player.start($StartPosition.position)
	$StartTimer.start()
	$HUD.update_score(score)
	$HUD.show_message("Get Ready!")


func _on_mob_timer_timeout():
	if not game_running:
		return
	var mob = mob_scene.instantiate()
	var mob_spawn_location = $MobPath/MobSpawnLocation
	mob_spawn_location.progress_ratio = randf()
	var direction = mob_spawn_location.rotation + PI / 2
	mob.position = mob_spawn_location.position
	direction += randf_range(-PI / 4, PI / 4)
	mob.rotation = direction
	var velocity = Vector2(randf_range(150.0, 250.0), 0.0)
	mob.linear_velocity = velocity.rotated(direction)

	# Mobs get tougher as the score climbs, so damage upgrades stay useful
	mob.max_health = BASE_MOB_HEALTH + floori(score / float(SCORE_PER_EXTRA_MOB_HP))
	mob.died.connect(_on_mob_died)
	add_child(mob)


func _on_mob_died():
	if not game_running:
		return
	kills += 1
	score += KILL_SCORE
	$HUD.update_score(score)


func _on_score_timer_timeout():
	if game_running:
		score += 1
		$HUD.update_score(score)


func _on_start_timer_timeout():
	$MobTimer.start()
	$ScoreTimer.start()
