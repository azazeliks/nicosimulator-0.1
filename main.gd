extends Node

@export var mob_scene: PackedScene
var score
var game_running = false

func _ready():
	$MobTimer.stop()
	$ScoreTimer.stop()

func game_over():
	game_running = false
	$ScoreTimer.stop()
	$MobTimer.stop()
	get_tree().call_group("mobs", "queue_free")
	$HUD.show_game_over()

func new_game():
	game_running = true
	score = 0
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
	add_child(mob)

func _on_score_timer_timeout():
	if game_running:
		score += 1
		$HUD.update_score(score)

func _on_start_timer_timeout():
	$MobTimer.start()
	$ScoreTimer.start()

func _on_hud_start_game() -> void:
	new_game()
