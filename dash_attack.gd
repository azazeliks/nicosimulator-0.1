# DashAttack.gd
# A dash toward the mouse that ends in a shockwave (called the "slam" in this file).
# Used by two characters, each configured on its own attack scene:
#   - Alistar (bruiser_dash_attack.tscn): a short WIND-UP (the direction is locked toward the
#     mouse at the moment of the press, the player is slowed, and a line shows the path), then
#     the DASH, then an instant slam that damages every mob in range and knocks them back.
#   - Seven's secondary (android_dash_attack.tscn): windup_time is 0, so the dash starts on the
#     same frame as the press. The slam lands slam_delay seconds AFTER the dash ends, at the
#     spot where it ended (shown as a danger zone), and does damage only (knockback_enabled is
#     off). The path the dash crossed also becomes a danger zone that damages mobs after
#     path_delay. The player stays rooted until the slam lands (lock_until_slam).
# While dashing, this attack moves the player itself (the player's own movement is paused)
# and can make the player invulnerable.
# Optional art for the path and the slam: see the "Art" exports below. With no art, simple
# shapes are drawn in code.
# Uses the shared upgrades: damage (slam damage), attack_range (slam size) and attack_speed
# (cooldown), plus the unique "knockback" and "dash_distance" upgrades.
# (Planned: split into one script per character, see HANDOFF_NOTES.txt, Step C.)
class_name DashAttack
extends Attack

@export var attack_cooldown := 1.4          # Seconds between dashes (level 0; Attack Speed divides it)
@export var base_dash_distance := 220.0     # Pixels travelled by the dash (the Dash Distance upgrade adds to it)
@export var windup_time := 0.3              # Seconds of wind-up before the dash starts (direction is locked in during this)
@export_range(0.0, 1.0) var windup_move_multiplier := 0.35  # Walking speed during the wind-up (1 = normal, 0 = rooted to the spot)
@export var dash_time := 0.18               # Seconds the dash takes
@export var base_slam_radius := 170.0       # Shockwave reach in pixels (the range upgrade scales it)
@export var base_knockback_speed := 900.0   # Starting speed given to knocked-back mobs (pixels per second)
@export var knockback_time := 0.5           # Seconds for a knocked-back mob to get back to its normal speed
@export var slam_delay := 0.0               # Seconds between the dash ending and the shockwave landing (0 = instant). The danger zone is shown on the ground and stays where the dash ended, so you can walk away from it
@export var knockback_enabled := true       # Off = the shockwave only damages
@export var lock_until_slam := true         # While the shockwave is charging (slam_delay), the player stays rooted to the spot until it lands, however long slam_delay is. Does nothing when slam_delay is 0
@export var invulnerable_while_dashing := true
@export var post_slam_invulnerability := 0.3  # Extra protection after the slam, so mobs next to you can't hit you right away
@export var slam_color := Color(0.8, 0.8, 0.85)
@export var effect_time := 0.3              # How long the hit effects (shockwave, path strike) stay on screen after they land

@export_group("Path damage")
@export var path_delay := 0.0               # Seconds after the dash ends before the path it crossed deals damage (0 = the path does no damage)
@export var path_width := 90.0              # Width of the danger zone in pixels (the range upgrade scales it)
@export_range(0.0, 2.0) var path_damage_fraction := 1.0  # Path damage as a fraction of the attack's damage (minimum 1)

@export_group("Art")
# PATH art: draw it as a horizontal strip pointing RIGHT, start of the dash on the left. It is
# stretched to fit the path's length and width, then rotated to the dash direction.
# SHOCKWAVE art: draw it centred; its width is stretched to the shockwave's diameter.
# Frames win over the texture. The animation named "default" is used (or the first one) and
# plays once across effect_time when the hit lands; before that, the first frame shows faintly
# as the warning. With no art, the placeholder shapes are drawn.
@export var path_texture: Texture2D
@export var path_frames: SpriteFrames
@export var slam_texture: Texture2D
@export var slam_frames: SpriteFrames
@export var slam_art_scale := 1.0           # Nudges the shockwave art size (1 = exactly the shockwave's diameter)

# Current-run stats (recalculated in configure)
var slam_radius := 170.0
var dash_distance := 220.0
var knockback_speed := 900.0
var current_cooldown := 1.4

var _cooldown_left := 0.0
var _winding_up := false
var _windup_left := 0.0
var _dashing := false
var _dash_dir := Vector2.RIGHT
var _dash_elapsed := 0.0
var _dash_start := Vector2.ZERO  # Where the dash began (world position), for the streak visual
var _grace_left := 0.0
var _effect_left := 0.0
var _slam_pending := false       # Dash is over, shockwave is still charging (slam_delay)
var _slam_delay_left := 0.0
var _slam_pos := Vector2.ZERO    # Where the shockwave happened (world position)
var _path_pending := false       # Path damage is charging (path_delay)
var _path_delay_left := 0.0
var _path_from := Vector2.ZERO   # The path the dash covered (world positions)
var _path_to := Vector2.ZERO
var _path_effect_left := 0.0


func configure(new_damage: int, new_range_mult: float, new_speed_mult: float, new_bonuses: Dictionary) -> void:
	super.configure(new_damage, new_range_mult, new_speed_mult, new_bonuses)
	slam_radius = base_slam_radius * range_mult
	dash_distance = base_dash_distance * (1.0 + bonus("dash_distance"))
	knockback_speed = base_knockback_speed * (1.0 + bonus("knockback"))
	# The delay never drops below wind-up + dash, so one dash finishes before the next starts
	current_cooldown = maxf(attack_cooldown / speed_mult, windup_time + dash_time + maxf(slam_delay, path_delay))


func start_run() -> void:
	_cooldown_left = 0.0
	cancel()


func cancel() -> void:
	_winding_up = false
	_dashing = false
	_grace_left = 0.0
	_effect_left = 0.0
	_slam_pending = false
	_path_pending = false
	_path_effect_left = 0.0
	queue_redraw()


# True during the wind-up, the dash itself and the wait for a delayed shockwave
func is_busy() -> bool:
	return _winding_up or _dashing or _slam_pending


# While true, the player's own movement and attack input are paused: during the dash, and
# (if lock_until_slam) until a delayed shockwave has landed. This follows the shockwave
# itself, not a fixed time, so changing slam_delay or anything else never leaves a gap.
func is_controlling_movement() -> bool:
	return _dashing or (lock_until_slam and _slam_pending)


# Slowed while winding up, normal otherwise (during the dash the player isn't walking anyway)
func movement_speed_multiplier() -> float:
	return windup_move_multiplier if _winding_up else 1.0


func is_invulnerable() -> bool:
	return (_dashing and invulnerable_while_dashing) or _grace_left > 0.0


func tick(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_grace_left = maxf(_grace_left - delta, 0.0)
	if _effect_left > 0.0:
		_effect_left = maxf(_effect_left - delta, 0.0)
		queue_redraw()

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

	# Phase 1: wind-up. The direction stays locked; when the time is up the dash begins
	if _winding_up:
		_windup_left -= delta
		queue_redraw()
		if _windup_left > 0.0:
			return
		_winding_up = false
		_begin_dash()

	# Phase 3 (only when slam_delay > 0): the shockwave charges where the dash ended.
	# The player is free to move during this, the slam stays put.
	if _slam_pending:
		_slam_delay_left -= delta
		queue_redraw()
		if _slam_delay_left <= 0.0:
			_slam_pending = false
			_slam()

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
		_slam_pos = global_position  # The shockwave happens here, even if the player walks off during slam_delay
		_grace_left = post_slam_invulnerability  # Protection on landing, so mobs next to you can't hit you right away
		if path_delay > 0.0:
			_path_from = _dash_start
			_path_to = global_position
			_path_pending = true
			_path_delay_left = path_delay
		if slam_delay > 0.0:
			_slam_pending = true
			_slam_delay_left = slam_delay
		else:
			_slam()


# Starts the wind-up toward the target and locks the dash direction right now.
# The dash length is fixed, it doesn't depend on how far the mouse is.
func try_attack(target: Vector2) -> bool:
	if _cooldown_left > 0.0:
		return false
	_cooldown_left = current_cooldown

	var aim := target - global_position
	if aim.length_squared() < 1.0:
		aim = Vector2.RIGHT  # Mouse is exactly on the player; pick any direction
	_dash_dir = aim.normalized()  # Committed: moving the mouse afterwards changes nothing
	_effect_left = 0.0
	_windup_left = windup_time
	_winding_up = windup_time > 0.0
	if not _winding_up:
		_begin_dash()  # windup_time of 0 = dash right away
	return true


# Phase 2: the player charges forward from wherever they are standing now
func _begin_dash() -> void:
	_dash_elapsed = 0.0
	_dash_start = global_position
	_dashing = true


# The shockwave at the end of the dash: damages and knocks back every mob in range
func _slam() -> void:
	_effect_left = effect_time
	for mob in get_tree().get_nodes_in_group("mobs"):
		if not is_instance_valid(mob) or not mob.has_method("take_damage"):
			continue
		var to_mob: Vector2 = mob.global_position - _slam_pos
		var reach: float = slam_radius + float(mob.hit_radius)
		if to_mob.length() > reach:
			continue
		var away := to_mob.normalized() if to_mob.length_squared() > 1.0 else _dash_dir
		mob.take_damage(damage)
		if knockback_enabled and mob.has_method("knockback"):
			mob.knockback(away, knockback_speed, knockback_time)
	queue_redraw()


# The path strike: damages every mob standing on the ground the dash crossed
func _path_strike() -> void:
	_path_effect_left = effect_time
	var path_damage := maxi(1, roundi(damage * path_damage_fraction))
	var half_width := path_width * range_mult * 0.5
	for mob in get_tree().get_nodes_in_group("mobs"):
		if not is_instance_valid(mob) or not mob.has_method("take_damage"):
			continue
		var mob_pos: Vector2 = mob.global_position
		var closest := Geometry2D.get_closest_point_to_segment(mob_pos, _path_from, _path_to)
		if mob_pos.distance_to(closest) <= half_width + float(mob.hit_radius):
			mob.take_damage(path_damage)
	queue_redraw()


# The texture to draw for an effect: a frame picked by how far through the effect we are
# (0 to 1) if frames were given, otherwise the single texture, otherwise null (placeholder)
func _pick_art(tex: Texture2D, frames: SpriteFrames, progress: float) -> Texture2D:
	if frames != null:
		var names := frames.get_animation_names()
		if names.size() > 0:
			var anim: StringName = &"default" if frames.has_animation(&"default") else StringName(names[0])
			var count := frames.get_frame_count(anim)
			if count > 0:
				return frames.get_frame_texture(anim, mini(int(progress * count), count - 1))
	return tex


func _draw_slam_art(art: Texture2D, center: Vector2, alpha: float) -> void:
	var r := slam_radius * slam_art_scale
	draw_texture_rect(art, Rect2(center - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(1, 1, 1, alpha))


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
			draw_rect(rect, Color(slam_color, 0.06 + 0.10 * charge))
			draw_rect(Rect2(0.0, -width * charge * 0.5, length, width * charge), Color(slam_color, 0.20 + 0.25 * charge))
		draw_rect(rect, Color(slam_color, 0.4 + 0.5 * charge), false, 3.0)
	else:
		var t := 1.0 - _path_effect_left / maxf(effect_time, 0.01)
		var art := _pick_art(path_texture, path_frames, t)
		if art != null:
			draw_texture_rect(art, rect, false, Color(1, 1, 1, clampf((1.0 - t) * 2.0, 0.0, 1.0)))
		else:
			draw_rect(rect, Color(slam_color, 0.3 * (1.0 - t)))
			draw_rect(rect, Color(1, 1, 1, 0.9 * (1.0 - t)), false, 5.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Placeholder visuals: a warning line while winding up, a streak while dashing, then an
# expanding ring at the slam spot
func _draw() -> void:
	if _winding_up:
		# The line grows and brightens as the dash gets closer, and follows the player
		var charge := 1.0 - clampf(_windup_left / maxf(windup_time, 0.01), 0.0, 1.0)
		var tip := to_local(global_position + _dash_dir * dash_distance)  # to_local keeps it correct if the player is scaled
		draw_line(Vector2.ZERO, tip, Color(slam_color, 0.15 + 0.5 * charge), 6.0)
		draw_circle(tip, 10.0 + 14.0 * charge, Color(slam_color, 0.2 + 0.4 * charge))
	if _dashing:
		draw_line(to_local(_dash_start), Vector2.ZERO, Color(slam_color, 0.5), 10.0)
	if _path_pending or _path_effect_left > 0.0:
		_draw_path()
	if _slam_pending:
		# Danger zone: the ring is fixed on the ground, the fill grows outward until it goes off
		var charge := 1.0 - clampf(_slam_delay_left / maxf(slam_delay, 0.01), 0.0, 1.0)
		var zone := to_local(_slam_pos)
		var warn_art := _pick_art(slam_texture, slam_frames, 0.0)
		if warn_art != null:
			_draw_slam_art(warn_art, zone, 0.15 + 0.35 * charge)
		else:
			draw_circle(zone, slam_radius, Color(slam_color, 0.06 + 0.10 * charge))
			draw_circle(zone, slam_radius * charge, Color(slam_color, 0.20 + 0.25 * charge))
		draw_arc(zone, slam_radius, 0.0, TAU, 64, Color(slam_color, 0.4 + 0.5 * charge), 3.0)
	if _effect_left > 0.0:
		var t := 1.0 - _effect_left / maxf(effect_time, 0.01)
		var center := to_local(_slam_pos)
		var strike_art := _pick_art(slam_texture, slam_frames, t)
		if strike_art != null:
			_draw_slam_art(strike_art, center, clampf((1.0 - t) * 2.0, 0.0, 1.0))
		else:
			var r := slam_radius * (0.3 + 0.7 * (1.0 - pow(1.0 - t, 2.0)))  # Grows fast, then settles
			draw_circle(center, r, Color(slam_color, 0.3 * (1.0 - t)))
			draw_arc(center, r, 0.0, TAU, 48, Color(1, 1, 1, 0.9 * (1.0 - t)), 5.0)
