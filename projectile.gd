# Projectile.gd
# A fireball made by ProjectileAttack. It flies in a straight line and explodes when it
# touches a mob or when its fuse runs out. The explosion damages every mob in its radius.
# It is drawn in code as a placeholder circle, so no art is needed yet.
class_name Projectile
extends Node2D

const EXPLODE_TIME := 0.3  # How long the explosion visual lasts

var velocity := Vector2.ZERO
var fuse_left := 1.0
var damage := 1
var explosion_radius := 130.0
var body_radius := 14.0
var color := Color(1.0, 0.6, 0.1)

var _exploding := false
var _explode_elapsed := 0.0


func setup(new_velocity: Vector2, new_fuse: float, new_damage: int, new_radius: float, new_body_radius: float, new_color: Color) -> void:
	velocity = new_velocity
	fuse_left = new_fuse
	damage = new_damage
	explosion_radius = new_radius
	body_radius = new_body_radius
	color = new_color


func _ready() -> void:
	add_to_group(Groups.PROJECTILES)  # So the attack can clear them when a run ends


func _process(delta: float) -> void:
	if _exploding:
		_explode_elapsed += delta
		queue_redraw()
		if _explode_elapsed >= EXPLODE_TIME:
			queue_free()
		return

	global_position += velocity * delta
	fuse_left -= delta
	if fuse_left <= 0.0:
		_explode()
		return

	# Explode as soon as we touch a mob
	if not MobHits.mobs_in_circle(get_tree(), global_position, body_radius).is_empty():
		_explode()
		return
	queue_redraw()


func _explode() -> void:
	_exploding = true
	_explode_elapsed = 0.0
	for mob in MobHits.mobs_in_circle(get_tree(), global_position, explosion_radius):
		mob.take_damage(damage)
	queue_redraw()


func _draw() -> void:
	if not _exploding:
		draw_circle(Vector2.ZERO, body_radius, color)
		draw_arc(Vector2.ZERO, body_radius, 0.0, TAU, 24, Color(1, 1, 1, 0.8), 2.0)
		return
	var t := clampf(_explode_elapsed / EXPLODE_TIME, 0.0, 1.0)
	var r := explosion_radius * (0.35 + 0.65 * (1.0 - pow(1.0 - t, 2.0)))  # Grows fast, then settles
	var fade := 1.0 - t
	draw_circle(Vector2.ZERO, r, Color(color.r, color.g, color.b, 0.35 * fade))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(1, 1, 1, 0.9 * fade), 4.0)
