extends RigidBody2D

signal died

@export var max_health := 2
@export var contact_damage := 1  # Damage dealt to the player on touch
@export var hit_radius := 45.0   # Roughly the mob's body radius; added to the player's sweep reach

var health := 0
var _dead := false


func _ready():
	health = max_health
	var mob_types = $AnimatedSprite2D.sprite_frames.get_animation_names()
	$AnimatedSprite2D.play(mob_types[randi() % mob_types.size()])


func take_damage(amount: int = 1) -> void:
	if _dead:
		return
	health -= amount
	queue_redraw()
	if health <= 0:
		_die()
	else:
		_flash()


func _flash() -> void:
	var sprite = $AnimatedSprite2D
	sprite.modulate = Color(1.0, 0.4, 0.4)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.2)


func _die() -> void:
	_dead = true
	remove_from_group("mobs")  # Can't be hit again or hurt the player while fading out
	$CollisionShape2D.set_deferred("disabled", true)
	died.emit()
	var tween := create_tween().set_parallel(true)
	tween.tween_property($AnimatedSprite2D, "scale", Vector2.ZERO, 0.15)
	tween.tween_property($AnimatedSprite2D, "modulate:a", 0.0, 0.15)
	tween.chain().tween_callback(queue_free)


# Small health bar, only shown once the mob has taken damage
func _draw():
	if _dead or health >= max_health:
		return
	# Cancel the mob's rotation so the bar always stays horizontal
	draw_set_transform(Vector2.ZERO, -global_rotation, Vector2.ONE)
	var bar_size := Vector2(50, 6)
	var origin := Vector2(-25, -85)
	var fill := clampf(float(health) / float(max_health), 0.0, 1.0)
	draw_rect(Rect2(origin, bar_size), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(origin, Vector2(bar_size.x * fill, bar_size.y)), Color(0.9, 0.2, 0.2))


func _on_visible_on_screen_notifier_2d_screen_exited():
	queue_free()
