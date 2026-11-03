# DashAttack.gd
# The bruiser's attack: a short dash toward the mouse that ends in a shockwave. The
# shockwave damages every mob in its radius and knocks them back.
# While dashing, this attack moves the player itself (the player's normal movement is
# paused) and can make the player invulnerable.
# Uses the shared upgrades: damage (slam damage), attack_range (slam size) and
# attack_speed (cooldown), plus the unique "knockback" and "dash_distance" upgrades.
class_name DashAttack
extends Attack

@export var attack_cooldown := 1.4          # Seconds between dashes (level 0; Attack Speed divides it)
@export var base_dash_distance := 220.0     # Pixels travelled by the dash (the Dash Distance upgrade adds to it)
@export var dash_time := 0.18               # Seconds the dash takes
@export var base_slam_radius := 170.0       # Shockwave reach in pixels (the range upgrade scales it)
@export var base_knockback_speed := 900.0   # Starting speed given to knocked-back mobs (pixels per second)
@export var knockback_time := 0.5           # Seconds for a knocked-back mob to get back to its normal speed
@export var invulnerable_while_dashing := true
@export var post_slam_invulnerability := 0.3  # Extra protection after the slam, so mobs next to you can't hit you right away
@export var slam_color := Color(0.8, 0.8, 0.85)

const EFFECT_TIME := 0.3  # How long the shockwave visual lasts

# Current-run stats (recalculated in configure)
var slam_radius := 170.0
var dash_distance := 220.0
var knockback_speed := 900.0
var current_cooldown := 1.4

var _cooldown_left := 0.0
var _dashing := false
var _dash_dir := Vector2.RIGHT
var _dash_elapsed := 0.0
var _dash_start := Vector2.ZERO  # Where the dash began (world position), for the streak visual
var _grace_left := 0.0
var _effect_left := 0.0
var _slam_pos := Vector2.ZERO    # Where the shockwave happened (world position)


func configure(new_damage: int, new_range_mult: float, new_speed_mult: float, new_bonuses: Dictionary) -> void:
	super.configure(new_damage, new_range_mult, new_speed_mult, new_bonuses)
	slam_radius = base_slam_radius * range_mult
	dash_distance = base_dash_distance * (1.0 + bonus("dash_distance"))
	knockback_speed = base_knockback_speed * (1.0 + bonus("knockback"))
	# The delay never drops below the dash time, so one dash finishes before the next starts
	current_cooldown = maxf(attack_cooldown / speed_mult, dash_time)


func start_run() -> void:
	_cooldown_left = 0.0
	cancel()


func cancel() -> void:
	_dashing = false
	_grace_left = 0.0
	_effect_left = 0.0
	queue_redraw()


# While true, the player's own movement and attack input are paused
func is_controlling_movement() -> bool:
	return _dashing


func is_invulnerable() -> bool:
	return (_dashing and invulnerable_while_dashing) or _grace_left > 0.0


func tick(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_grace_left = maxf(_grace_left - delta, 0.0)
	if _effect_left > 0.0:
		_effect_left = maxf(_effect_left - delta, 0.0)
		queue_redraw()
	if not _dashing:
		return

	# Move the player along the dash direction at a constant speed
	var step := minf(delta, dash_time - _dash_elapsed)  # Never overshoot the end of the dash
	_dash_elapsed += step
	var dash_speed := dash_distance / maxf(dash_time, 0.01)
	var player := get_parent() as Node2D
	var new_pos := player.global_position + _dash_dir * dash_speed * step
	player.global_position = new_pos.clamp(Vector2.ZERO, get_viewport_rect().size)
	queue_redraw()

	if _dash_elapsed >= dash_time - 0.0001:
		_dashing = false
		_slam()


# Starts a dash toward the target. The dash length is fixed, it doesn't depend on how far the mouse is.
func try_attack(target: Vector2) -> bool:
	if _cooldown_left > 0.0:
		return false
	_cooldown_left = current_cooldown

	var aim := target - global_position
	if aim.length_squared() < 1.0:
		aim = Vector2.RIGHT  # Mouse is exactly on the player; pick any direction
	_dash_dir = aim.normalized()
	_dash_elapsed = 0.0
	_dash_start = global_position
	_effect_left = 0.0
	_dashing = true
	return true


# The shockwave at the end of the dash: damages and knocks back every mob in range
func _slam() -> void:
	_slam_pos = global_position
	_effect_left = EFFECT_TIME
	_grace_left = post_slam_invulnerability
	for mob in get_tree().get_nodes_in_group("mobs"):
		if not is_instance_valid(mob) or not mob.has_method("take_damage"):
			continue
		var to_mob: Vector2 = mob.global_position - _slam_pos
		var reach: float = slam_radius + float(mob.hit_radius)
		if to_mob.length() > reach:
			continue
		var away := to_mob.normalized() if to_mob.length_squared() > 1.0 else _dash_dir
		mob.take_damage(damage)
		if mob.has_method("knockback"):
			mob.knockback(away, knockback_speed, knockback_time)
	queue_redraw()


# Placeholder visuals: a streak while dashing, then an expanding ring at the slam spot
func _draw() -> void:
	if _dashing:
		draw_line(to_local(_dash_start), Vector2.ZERO, Color(slam_color, 0.5), 10.0)
	if _effect_left > 0.0:
		var t := 1.0 - _effect_left / EFFECT_TIME
		var r := slam_radius * (0.3 + 0.7 * (1.0 - pow(1.0 - t, 2.0)))  # Grows fast, then settles
		var center := to_local(_slam_pos)
		draw_circle(center, r, Color(slam_color, 0.3 * (1.0 - t)))
		draw_arc(center, r, 0.0, TAU, 48, Color(1, 1, 1, 0.9 * (1.0 - t)), 5.0)
