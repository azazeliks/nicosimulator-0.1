# DelayedDashAttack.gd
# Seven's right-click attack: an instant dash toward the mouse (no wind-up), then a big blast
# (the "slash dash") that lands slash_dash_delay seconds AFTER the dash ends, at the spot where
# it ended. Until it lands it is shown as a danger zone on the ground, and Seven is rooted to
# the spot (lock_until_slash_dash). It damages mobs without knocking them back.
# Optionally (path_delay above 0) the ground the dash crossed is also marked as a danger
# zone and damages every mob on it after that delay.
# Alistar's dash is a different attack: see dash_attack.gd. The shared parts (cooldown, the
# dash itself, invulnerability) live in dash_attack_base.gd.
# Uses the shared upgrades: damage (blast damage), attack_range (blast and path size) and
# attack_speed (cooldown), plus "dash_distance" (not sold to Seven yet).
# Settings live on the root node of the attack scene (see android_dash_attack.tscn).
class_name DelayedDashAttack
extends DashAttackBase

@export var base_slash_dash_radius := 170.0   # Blast reach in pixels (the range upgrade scales it)
@export var slash_dash_delay := 0.0           # Seconds between the dash ending and the blast landing (0 = instant). The danger zone is shown on the ground and stays where the dash ended, so it does not follow you (but see lock_until_slash_dash)
@export var lock_until_slash_dash := true     # While the blast is charging (slash_dash_delay), the player stays rooted to the spot until it lands, however long the delay is. Does nothing when slash_dash_delay is 0
@export var post_slash_dash_invulnerability := 0.3  # Extra protection after the dash, so mobs next to you can't hit you right away
@export var slash_dash_color := Color(0.8, 0.8, 0.85)

@export_group("Path damage")
@export var path_delay := 0.0               # Seconds after the dash ends before the path it crossed deals damage (0 = the path does no damage)
@export var path_width := 90.0              # Width of the danger zone in pixels (the range upgrade scales it)
@export_range(0.0, 2.0) var path_damage_fraction := 1.0  # Path damage as a fraction of the attack's damage (minimum 1)

@export_group("Art")
# PATH art: draw it as a horizontal strip pointing RIGHT, start of the dash on the left. It is
# stretched to fit the path's length and width, then rotated to the dash direction.
# BLAST art: draw it centred; its width is stretched to the blast's diameter.
# Frames win over the texture. The animation named "default" is used (or the first one) and
# plays once across effect_time when the hit lands; before that, the first frame shows faintly
# as the warning. With no art, the placeholder shapes are drawn.
@export var path_texture: Texture2D
@export var path_frames: SpriteFrames
@export var slash_dash_texture: Texture2D
@export var slash_dash_frames: SpriteFrames
@export var slash_dash_art_scale := 1.0     # Nudges the blast art size (1 = exactly the blast's diameter)

# Current-run stats (recalculated in configure)
var slash_dash_radius := 170.0

var _slash_dash_pending := false     # Dash is over, the blast is still charging (slash_dash_delay)
var _slash_dash_delay_left := 0.0
var _slash_dash_pos := Vector2.ZERO  # Where the blast lands (world position)
var _path_pending := false           # Path damage is charging (path_delay)
var _path_delay_left := 0.0
var _path_from := Vector2.ZERO       # The path the dash covered (world positions)
var _path_to := Vector2.ZERO
var _path_effect_left := 0.0


func configure(new_damage: int, new_range_mult: float, new_speed_mult: float, new_bonuses: Dictionary) -> void:
	super.configure(new_damage, new_range_mult, new_speed_mult, new_bonuses)
	slash_dash_radius = base_slash_dash_radius * range_mult
	# The delay never drops below the dash plus the wait for the blast / path, so one attack finishes before the next starts
	current_cooldown = maxf(attack_cooldown / speed_mult, dash_time + maxf(slash_dash_delay, path_delay))


func cancel() -> void:
	super.cancel()
	_slash_dash_pending = false
	_path_pending = false
	_path_effect_left = 0.0


# True during the dash and the wait for the blast
func is_busy() -> bool:
	return _dashing or _slash_dash_pending


# While true, the player's own movement and attack input are paused: during the dash, and
# (if lock_until_slash_dash) until the blast has landed. This follows the blast itself, not a
# fixed time, so changing slash_dash_delay or anything else never leaves a gap.
func is_controlling_movement() -> bool:
	return _dashing or (lock_until_slash_dash and _slash_dash_pending)


func _tick_phases(delta: float) -> void:
	# The path strike: charges where the dash went, then damages everything on it
	if _path_effect_left > 0.0:
		_path_effect_left = maxf(_path_effect_left - delta, 0.0)
		queue_redraw()
	if _path_pending:
		_path_delay_left -= delta
		queue_redraw()
		if _path_delay_left <= 0.0:
			_path_pending = false
			_path_strike()

	# The blast charges where the dash ended
	if _slash_dash_pending:
		_slash_dash_delay_left -= delta
		queue_redraw()
		if _slash_dash_delay_left <= 0.0:
			_slash_dash_pending = false
			_land_slash_dash()


func _on_dash_finished() -> void:
	_slash_dash_pos = global_position  # The blast happens here, even if the player walks off during the delay
	_grace_left = post_slash_dash_invulnerability  # Protection on landing, so mobs next to you can't hit you right away
	if path_delay > 0.0:
		_path_from = _dash_start
		_path_to = global_position
		_path_pending = true
		_path_delay_left = path_delay
	if slash_dash_delay > 0.0:
		_slash_dash_pending = true
		_slash_dash_delay_left = slash_dash_delay
	else:
		_land_slash_dash()


# The blast at the end of the dash: damages every mob in range (no knockback)
func _land_slash_dash() -> void:
	_effect_left = effect_time
	for mob in MobHits.mobs_in_circle(get_tree(), _slash_dash_pos, slash_dash_radius):
		mob.take_damage(damage)
	queue_redraw()


# The path strike: damages every mob standing on the ground the dash crossed
func _path_strike() -> void:
	_path_effect_left = effect_time
	var path_damage := maxi(1, roundi(damage * path_damage_fraction))
	var half_width := path_width * range_mult * 0.5
	for mob in MobHits.mobs_near_segment(get_tree(), _path_from, _path_to, half_width):
		mob.take_damage(path_damage)
	queue_redraw()


# The path danger zone / strike: a rectangle from where the dash began to where it ended
func _draw_path() -> void:
	var a := to_local(_path_from)
	var b := to_local(_path_to)
	var length := a.distance_to(b)
	var width := path_width * range_mult
	draw_set_transform(a, (b - a).angle(), Vector2.ONE)
	var rect := Rect2(0.0, -width * 0.5, length, width)
	if _path_pending:
		var charge := 1.0 - clampf(_path_delay_left / maxf(path_delay, 0.01), 0.0, 1.0)
		var art := _pick_art(path_texture, path_frames, 0.0)
		if art != null:
			draw_texture_rect(art, rect, false, Color(1, 1, 1, 0.15 + 0.35 * charge))
		else:
			draw_rect(rect, Color(slash_dash_color, 0.06 + 0.10 * charge))
			draw_rect(Rect2(0.0, -width * charge * 0.5, length, width * charge), Color(slash_dash_color, 0.20 + 0.25 * charge))
		draw_rect(rect, Color(slash_dash_color, 0.4 + 0.5 * charge), false, 3.0)
	else:
		var t := 1.0 - _path_effect_left / maxf(effect_time, 0.01)
		var art := _pick_art(path_texture, path_frames, t)
		if art != null:
			draw_texture_rect(art, rect, false, Color(1, 1, 1, clampf((1.0 - t) * 2.0, 0.0, 1.0)))
		else:
			draw_rect(rect, Color(slash_dash_color, 0.3 * (1.0 - t)))
			draw_rect(rect, Color(1, 1, 1, 0.9 * (1.0 - t)), false, 5.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Placeholder visuals: a streak while dashing, the path danger zone, the blast's danger zone
# while it charges, then an expanding ring where it lands
func _draw() -> void:
	_draw_dash_streak(slash_dash_color)
	if _path_pending or _path_effect_left > 0.0:
		_draw_path()
	if _slash_dash_pending:
		# Danger zone: the ring is fixed on the ground, the fill grows outward until it goes off
		var charge := 1.0 - clampf(_slash_dash_delay_left / maxf(slash_dash_delay, 0.01), 0.0, 1.0)
		var zone := to_local(_slash_dash_pos)
		var warn_art := _pick_art(slash_dash_texture, slash_dash_frames, 0.0)
		if warn_art != null:
			_draw_circle_art(warn_art, zone, slash_dash_radius * slash_dash_art_scale, 0.15 + 0.35 * charge)
		else:
			draw_circle(zone, slash_dash_radius, Color(slash_dash_color, 0.06 + 0.10 * charge))
			draw_circle(zone, slash_dash_radius * charge, Color(slash_dash_color, 0.20 + 0.25 * charge))
		draw_arc(zone, slash_dash_radius, 0.0, TAU, 64, Color(slash_dash_color, 0.4 + 0.5 * charge), 3.0)
	if _effect_left > 0.0:
		_draw_landing_effect(_slash_dash_pos, slash_dash_radius, slash_dash_color, slash_dash_texture, slash_dash_frames, slash_dash_art_scale)
