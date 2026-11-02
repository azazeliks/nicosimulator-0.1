extends Node

# --- Tuning knobs ---
const SCORE_PER_COIN := 5           # Score needed per coin when a run ends
const KILL_SCORE := 3               # Bonus score for each mob killed
const BASE_MOB_HEALTH := 2
const SCORE_PER_EXTRA_MOB_HP := 30  # Mobs gain +1 HP for every N points of score

@export var mob_scene: PackedScene
var score := 0
var kills := 0
var game_running = false


func _ready():
	$MobTimer.stop()
	$ScoreTimer.stop()
	$Player.health_changed.connect($HUD.update_health)


func game_over():
	game_running = false
	$ScoreTimer.stop()
	$MobTimer.stop()
	get_tree().call_group("mobs", "queue_free")

	# Convert this run's score into permanent coins
	var earned := floori(score / float(SCORE_PER_COIN))
	SaveData.add_coins(earned)
	$HUD.show_game_over(score, earned, SaveData.get_coins())


func new_game():
	game_running = true
	score = 0
	kills = 0
	$MobTimer.stop()
	$ScoreTimer.stop()
	get_tree().call_group("mobs", "queue_free")
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
