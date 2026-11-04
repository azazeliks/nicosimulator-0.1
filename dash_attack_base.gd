# DashAttackBase.gd
# What both dash attacks have in common: the cooldown, the dash itself (moving the player in
# a locked direction at a constant speed), invulnerability, and a few drawing helpers.
# Two attacks extend it:
#   - DashAttack (dash_attack.gd): Alistar's wind-up dash that ends in a knockback shockwave
#   - DelayedDashAttack (delayed_dash_attack.gd): Seven's instant dash with a delayed landing
# A subclass fills in three things:
#   _start_sequence()   what happens when the button is pressed (default: dash right away)
#   _tick_phases(delta) its own timers each frame (wind-up, delayed landing, ...)
#   _on_dash_finished() what happens when the dash ends (the landing)
# While dashing, this attack moves the player itself (the player's normal movement is
# paused) and can make the player invulnerable.
# Uses the shared upgrades attack_speed (cooldown) and dash_distance.
class_name DashAttackBase
extends Attack

@export var attack_cooldown := 1.4          # Seconds between dashes (level 0; Attack Speed divides it)
@export var base_dash_distance := 220.0     # Pixels travelled by the dash (the Dash Distance upgrade adds to it)
@export var dash_time := 0.18               # Seconds the dash takes
@export var invulnerable_while_dashing := true
@export var effect_time := 0.3              # How long the landing effect stays on screen after it lands

# Current-run stats (recalculated in configure)
var dash_distance := 220.0
var current_cooldown := 1.4

var _cooldown_left := 0.0
var _dashing := false
var _dash_dir := Vector2.RIGHT
var _dash_elapsed := 0.0
var _dash_start := Vector2.ZERO  # Where the dash began (world position), for the streak visual
var _grace_left := 0.0           # Protection after landing, so mobs next to you can't hit you right away
var _effect_left := 0.0          # Time left on the landing effect


func configure(new_damage: int, new_range_mult: float, new_speed_mult: float, new_bonuses: Dictionary) -> void:
	super.configure(new_damage, new_range_mult, new_speed_mult, new_bonuses)
	dash_distance = base_dash_distance * (1.0 + bonus("dash_distance"))
	# A subclass sets current_cooldown after this call (it never drops below the time one dash takes)


func start_run() -> void:
	_cooldown_left = 0.0
	cancel()


func cancel() -> void:
	_dashing = false
	_grace_left = 0.0
	_effect_left = 0.0
	queue_redraw()


# True while the attack is in progress. Subclasses add their own phases.
func is_busy() -> bool:
	return _dashing


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
	_tick_phases(delta)
	_move_dash(delta)


# Locks the dash direction right now, toward the target. The dash length is fixed, it doesn't
# depend on how far the mouse is.
func try_attack(target: Vector2) -> bool:
	if _cooldown_left > 0.0:
		return false
	_cooldown_left = current_cooldown

	var aim := target - global_position
	if aim.length_squared() < 1.0:
		aim = Vector2.RIGHT  # Mouse is exactly on the player; pick any direction
	_dash_dir = aim.normalized()  # Committed: moving the mouse afterwards changes nothing
	_effect_left = 0.0
	_start_sequence()
	return true


# ------------------------------------------------------------ for subclasses

# What happens when the button is pressed. By default the dash starts on the same frame.
func _start_sequence() -> void:
	_begin_dash()


# A subclass's own timers. Called every frame, just before the dash moves the player.
func _tick_phases(_delta: float) -> void:
	pass


# Called once, on the frame the dash ends. The player is standing where the dash ended.
func _on_dash_finished() -> void:
	pass


# The player charges forward from wherever they are standing now
func _begin_dash() -> void:
	_dash_elapsed = 0.0
	_dash_start = global_position
	_dashing = true


# Moves the player along the dash direction at a constant speed
func _move_dash(delta: float) -> void:
	if not _dashing:
		return
	var step := minf(delta, dash_time - _dash_elapsed)  # Never overshoot the end of the dash
	_dash_elapsed += step
	var dash_speed := dash_distance / maxf(dash_time, 0.01)
	var player := get_parent() as Node2D
	var new_pos := player.global_position + _dash_dir * dash_speed * step
	player.global_position = new_pos.clamp(Vector2.ZERO, get_viewport_rect().size)
	queue_redraw()

	if _dash_elapsed >= dash_time - 0.0001:
		_dashing = false
		_on_dash_finished()


# ------------------------------------------------------------ drawing helpers

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


# Art drawn centred on a point, stretched to a circle of the given radius
func _draw_circle_art(art: Texture2D, center: Vector2, radius: float, alpha: float) -> void:
	draw_texture_rect(art, Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, Color(1, 1, 1, alpha))


# The streak behind the player while dashing
func _draw_dash_streak(color: Color) -> void:
	if _dashing:
		draw_line(to_local(_dash_start), Vector2.ZERO, Color(color, 0.5), 10.0)


# The effect when the landing hits: the art if there is any, otherwise an expanding ring.
# `center_world` is where it landed (a world position).
func _draw_landing_effect(center_world: Vector2, radius: float, color: Color, art_texture: Texture2D, art_frames: SpriteFrames, art_scale: float) -> void:
	var t := 1.0 - _effect_left / maxf(effect_time, 0.01)
	var center := to_local(center_world)
	var strike_art := _pick_art(art_texture, art_frames, t)
	if strike_art != null:
		_draw_circle_art(strike_art, center, radius * art_scale, clampf((1.0 - t) * 2.0, 0.0, 1.0))
	else:
		var r := radius * (0.3 + 0.7 * (1.0 - pow(1.0 - t, 2.0)))  # Grows fast, then settles
		draw_circle(center, r, Color(color, 0.3 * (1.0 - t)))
		draw_arc(center, r, 0.0, TAU, 48, Color(1, 1, 1, 0.9 * (1.0 - t)), 5.0)
