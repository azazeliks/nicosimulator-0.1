# DashAttack.gd
# Alistar's attack, in two phases:
#   1. WIND-UP: the direction is locked in (toward the mouse at the moment of the press) and
#      the player is slowed down for a moment. A line shows where the dash will go.
#   2. DASH: the player charges forward in that direction, then a shockwave (the "slam")
#      damages every mob in its radius and knocks them back.
# Seven's right-click dash is a different attack: see delayed_dash_attack.gd. The shared parts
# (cooldown, the dash itself, invulnerability) live in dash_attack_base.gd.
# Uses the shared upgrades: damage (slam damage), attack_range (slam size) and
# attack_speed (cooldown), plus the unique "knockback" and "dash_distance" upgrades.
# Settings live on the root node of the attack scene (see bruiser_dash_attack.tscn).
class_name DashAttack
extends DashAttackBase

@export var windup_time := 0.3              # Seconds of wind-up before the dash starts (direction is locked in during this)
@export_range(0.0, 1.0) var windup_move_multiplier := 0.35  # Walking speed during the wind-up (1 = normal, 0 = rooted to the spot)
@export var base_slam_radius := 170.0       # Shockwave reach in pixels (the range upgrade scales it)
@export var base_knockback_speed := 900.0   # Starting speed given to knocked-back mobs (pixels per second)
@export var knockback_time := 0.5           # Seconds for a knocked-back mob to get back to its normal speed
@export var post_slam_invulnerability := 0.3  # Extra protection after the slam, so mobs next to you can't hit you right away
@export var slam_color := Color(0.8, 0.8, 0.85)

@export_group("Art")
# SHOCKWAVE art: draw it centred; its width is stretched to the shockwave's diameter.
# Frames win over the texture. The animation named "default" is used (or the first one) and
# plays once across effect_time when the slam lands. With no art, a ring is drawn.
@export var slam_texture: Texture2D
@export var slam_frames: SpriteFrames
@export var slam_art_scale := 1.0           # Nudges the shockwave art size (1 = exactly the shockwave's diameter)

# Current-run stats (recalculated in configure)
var slam_radius := 170.0
var knockback_speed := 900.0

var _winding_up := false
var _windup_left := 0.0
var _slam_pos := Vector2.ZERO    # Where the shockwave happened (world position)


func configure(new_damage: int, new_range_mult: float, new_speed_mult: float, new_bonuses: Dictionary) -> void:
	super.configure(new_damage, new_range_mult, new_speed_mult, new_bonuses)
	slam_radius = base_slam_radius * range_mult
	knockback_speed = base_knockback_speed * (1.0 + bonus("knockback"))
	# The delay never drops below wind-up + dash, so one dash finishes before the next starts
	current_cooldown = maxf(attack_cooldown / speed_mult, windup_time + dash_time)


func cancel() -> void:
	super.cancel()
	_winding_up = false


# True during the wind-up and the dash itself
func is_busy() -> bool:
	return _winding_up or _dashing


# Slowed while winding up, normal otherwise (during the dash the player isn't walking anyway)
func movement_speed_multiplier() -> float:
	return windup_move_multiplier if _winding_up else 1.0


# Starts the wind-up (the direction is already locked). With windup_time 0 the dash starts at once.
func _start_sequence() -> void:
	_windup_left = windup_time
	_winding_up = windup_time > 0.0
	if not _winding_up:
		_begin_dash()


# Phase 1: wind-up. The direction stays locked; when the time is up the dash begins
func _tick_phases(delta: float) -> void:
	if not _winding_up:
		return
	_windup_left -= delta
	queue_redraw()
	if _windup_left <= 0.0:
		_winding_up = false
		_begin_dash()


func _on_dash_finished() -> void:
	_grace_left = post_slam_invulnerability  # Protection on landing, so mobs next to you can't hit you right away
	_slam_pos = global_position
	_slam()


# The shockwave at the end of the dash: damages and knocks back every mob in range
func _slam() -> void:
	_effect_left = effect_time
	for mob in MobHits.mobs_in_circle(get_tree(), _slam_pos, slam_radius):
		var to_mob: Vector2 = mob.global_position - _slam_pos
		var away := to_mob.normalized() if to_mob.length_squared() > 1.0 else _dash_dir
		mob.take_damage(damage)
		if mob.has_method("knockback"):
			mob.knockback(away, knockback_speed, knockback_time)
	queue_redraw()


# Placeholder visuals: a warning line while winding up, a streak while dashing, then an
# expanding ring at the slam spot
func _draw() -> void:
	if _winding_up:
		# The line grows and brightens as the dash gets closer, and follows the player
		var charge := 1.0 - clampf(_windup_left / maxf(windup_time, 0.01), 0.0, 1.0)
		var tip := to_local(global_position + _dash_dir * dash_distance)  # to_local keeps it correct if the player is scaled
		draw_line(Vector2.ZERO, tip, Color(slam_color, 0.15 + 0.5 * charge), 6.0)
		draw_circle(tip, 10.0 + 14.0 * charge, Color(slam_color, 0.2 + 0.4 * charge))
	_draw_dash_streak(slam_color)
	if _effect_left > 0.0:
		_draw_landing_effect(_slam_pos, slam_radius, slam_color, slam_texture, slam_frames, slam_art_scale)
