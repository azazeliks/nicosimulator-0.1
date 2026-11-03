# SweepAttack.gd
# The timed cone sweep, moved out of player.gd. It plays exactly as before.
# Add it as a child node of the Player. The sweep and slash-art settings now live
# on this node in the Inspector instead of on the Player node.
class_name SweepAttack
extends Attack

@export var base_attack_radius := 240.0  # How far the sweep reaches from the player (includes the gap before the slash starts)
@export_range(10.0, 180.0) var attack_arc_degrees := 100.0  # Total width of the sweep
@export var attack_cooldown := 0.6       # Seconds between attacks
@export var sweep_time := 0.2            # Seconds the swing takes to cross the arc

# Your own attack art (all optional). The art can be drawn at any angle: tell the
# script where its rotation point is, which way it points, and how long it is.
# The defaults match slash.png.
@export_group("Slash graphics")
@export var slash_texture: Texture2D    # A single image...
@export var slash_frames: SpriteFrames  # ...or an animation (wins over slash_texture)
@export var slash_animation: StringName = &"default"  # Which animation in slash_frames
@export var slash_pivot := Vector2(482, 1064)  # Pixel in the image that sits on the player (the rotation point)
@export var slash_art_angle := -80.0     # Direction the middle of the art points, in degrees: 0 = right, -90 = up, 90 = down, 180 = left
@export var slash_art_length := 850.0    # Pixels from the pivot to the far end of the art (scaled to match the attack range)
@export var slash_lead_degrees := 54.0   # Angle from the art's middle to its leading edge. The leading edge rides the blade and the rest trails behind. 0 centers the art on the blade
@export var slash_scale := 1.0           # Extra size multiplier
@export var slash_distance := 60.0       # How far from the player the slash orbits. The hit area still covers the gap
@export var slash_flip_y := false        # Tick if the art's leading edge is on the other side (swings look backwards)
@export var slash_angle_offset := 0.0    # Visual-only tilt in degrees, mirrored between the two swings. Positive leans the art forward (the way it is swinging), negative leans it back. The hit area never moves
@export var debug_draw_attack := false   # Shows the real hit area in red, for lining up art

const FADE_TIME := 0.12  # How long the placeholder trail lingers after a sweep

# Current-run stats (recalculated in configure)
var attack_radius := 240.0
var current_cooldown := 0.6    # attack_cooldown divided by the attack speed multiplier (never less than the swing time)
var current_sweep_time := 0.2  # How long a swing takes (attack speed doesn't change it)

var _cooldown_left := 0.0

# Sweep state
var _sweeping := false
var _sweep_elapsed := 0.0
var _sweep_aim := 0.0       # Direction (radians) the sweep is centered on, locked when it starts
var _sweep_cur_rel := 0.0   # Where the blade is now, relative to the aim direction
var _sweep_dir := 1         # +1 = left to right (clockwise), -1 = right to left
var _next_dir := 1          # Alternates every attack
var _hit_this_sweep := {}   # Mobs already hit by the current sweep (each is hit once)
var _fade_left := 0.0

# Slash art nodes, built in code if you assigned a texture or frames
var _slash_pivot: Node2D   # Rotates with the blade
var _slash_mirror: Node2D  # Flips the art for the right-to-left swing
var _slash_sprite: AnimatedSprite2D
var _slash_anim: StringName = &"default"
var _slash_tex: Texture2D


func _ready() -> void:
	_setup_slash()


# ------------------------------------------------------- Attack interface

func configure(new_damage: int, new_range_mult: float, new_speed_mult: float) -> void:
	super.configure(new_damage, new_range_mult, new_speed_mult)
	attack_radius = base_attack_radius * range_mult
	# Attack speed only shortens the delay between attacks. The swing itself (and the
	# slash animation) always takes sweep_time.
	current_sweep_time = sweep_time
	# The delay never drops below the swing time, so one swing finishes before the next starts
	current_cooldown = maxf(attack_cooldown / speed_mult, current_sweep_time)


func start_run() -> void:
	_cooldown_left = 0.0
	_next_dir = 1  # First swing of every run goes left to right
	cancel()


func cancel() -> void:
	_sweeping = false
	_fade_left = 0.0
	_hit_this_sweep.clear()
	if _slash_pivot != null:
		_slash_pivot.hide()
		_slash_sprite.stop()
	queue_redraw()


func tick(delta: float) -> void:
	_update_sweep(delta)
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)


# Starts a sweep aimed at the target. Each attack swings the opposite way from the last.
func try_attack(target: Vector2) -> bool:
	if _cooldown_left > 0.0:
		return false
	_cooldown_left = current_cooldown

	var aim := target - global_position
	if aim.length_squared() < 1.0:
		aim = Vector2.RIGHT  # Target is exactly on the player; pick any direction
	_sweep_aim = aim.angle()  # Locked in: the swing doesn't follow the mouse afterwards

	_sweep_dir = _next_dir
	_next_dir = -_next_dir
	_sweep_elapsed = 0.0
	_sweeping = true
	_fade_left = 0.0
	_hit_this_sweep.clear()

	_start_slash_visual()
	_update_sweep(0.0)  # Apply the very first slice right away
	return true


# ------------------------------------------------------------------ sweep

func _update_sweep(delta: float) -> void:
	if _fade_left > 0.0:
		_fade_left = maxf(_fade_left - delta, 0.0)
		queue_redraw()
	if not _sweeping:
		return

	_sweep_elapsed += delta
	var t := clampf(_sweep_elapsed / maxf(current_sweep_time, 0.01), 0.0, 1.0)
	var p := 1.0 - pow(1.0 - t, 2.0)  # Ease-out: fast start, soft finish
	var half_arc := deg_to_rad(attack_arc_degrees) * 0.5
	if _sweep_dir > 0:
		_sweep_cur_rel = lerpf(-half_arc, half_arc, p)
	else:
		_sweep_cur_rel = lerpf(half_arc, -half_arc, p)

	_apply_sweep_hits(half_arc)
	_update_slash_rotation()
	queue_redraw()

	if t >= 1.0:
		_end_sweep()


# Damages each mob (once per sweep) as the blade passes over it.
func _apply_sweep_hits(half_arc: float) -> void:
	var aim_vec := Vector2.from_angle(_sweep_aim)
	for mob in get_tree().get_nodes_in_group("mobs"):
		if not is_instance_valid(mob) or not mob.has_method("take_damage"):
			continue
		var id: int = mob.get_instance_id()
		if _hit_this_sweep.has(id):
			continue

		var hit_r: float = mob.hit_radius
		var to_mob: Vector2 = mob.global_position - global_position
		var dist := to_mob.length()
		if dist > attack_radius + hit_r:
			continue

		# A mob right on top of the player is hit immediately
		if dist <= hit_r:
			_hit_this_sweep[id] = true
			mob.take_damage(damage)
			continue

		# Mobs have size, so widen their angle a little: a mob counts as soon as
		# the blade touches its edge.
		var rel := aim_vec.angle_to(to_mob)  # Mob's angle relative to the aim direction
		var margin := asin(clampf(hit_r / dist, 0.0, 1.0))
		if absf(rel) > half_arc + margin:
			continue  # Outside the cone entirely

		var reached := (rel - margin <= _sweep_cur_rel) if _sweep_dir > 0 else (rel + margin >= _sweep_cur_rel)
		if reached:
			_hit_this_sweep[id] = true
			mob.take_damage(damage)


func _end_sweep() -> void:
	_sweeping = false
	_fade_left = FADE_TIME
	if _slash_pivot != null:
		_slash_pivot.hide()
		_slash_sprite.stop()


# ------------------------------------------------------------ slash graphics

# Builds the nodes for your art. Does nothing if no texture/frames were assigned,
# in which case a plain white placeholder is drawn instead.
func _setup_slash() -> void:
	var frames: SpriteFrames = slash_frames
	if frames == null and slash_texture != null:
		frames = SpriteFrames.new()  # New SpriteFrames already contains a "default" animation
		frames.add_frame(&"default", slash_texture)
		_slash_anim = &"default"
	elif frames != null:
		_slash_anim = slash_animation
		if not frames.has_animation(_slash_anim):
			var names := frames.get_animation_names()
			if names.is_empty():
				return
			_slash_anim = StringName(names[0])
	if frames == null or frames.get_frame_count(_slash_anim) == 0:
		return

	_slash_tex = frames.get_frame_texture(_slash_anim, 0)
	if _slash_tex == null:
		return

	# The pivot sits on the player and rotates; the sprite hangs off it pointing right
	_slash_pivot = Node2D.new()
	_slash_pivot.name = "SlashPivot"
	_slash_pivot.visible = false
	add_child(_slash_pivot)

	_slash_mirror = Node2D.new()
	_slash_mirror.name = "SlashMirror"
	_slash_pivot.add_child(_slash_mirror)

	_slash_sprite = AnimatedSprite2D.new()
	_slash_sprite.name = "SlashSprite"
	_slash_sprite.sprite_frames = frames
	_slash_sprite.centered = false
	_slash_mirror.add_child(_slash_sprite)


func _start_slash_visual() -> void:
	if _slash_sprite == null:
		return
	# The art fills the space from the orbit distance out to the attack range
	var visible_length := maxf(attack_radius - slash_distance, 1.0)
	var s: float = (visible_length / maxf(slash_art_length, 1.0)) * slash_scale
	# The second swing is a mirror image of the first (slash_flip_y swaps which one)
	var mirror := (_sweep_dir < 0) != slash_flip_y
	_slash_mirror.scale = Vector2(1.0, -1.0 if mirror else 1.0)

	_slash_sprite.offset = -slash_pivot  # Puts the pivot pixel at the sprite's origin
	# Turns the art so its middle points along +x, plus the visual-only tilt. The tilt follows the
	# swing: on screen it is +offset (clockwise) for a clockwise swing and -offset for a counterclockwise
	# one, so it leans the same way relative to the swing both times. The mirror node flips rotation
	# direction on mirrored swings, which the last factor cancels out.
	var tilt := deg_to_rad(slash_angle_offset) * float(_sweep_dir) * (-1.0 if mirror else 1.0)
	_slash_sprite.rotation = deg_to_rad(-slash_art_angle) + tilt
	_slash_sprite.scale = Vector2(s, s)
	# Put the art's pivot on a circle around the player, directly along the blade's line.
	# (The pivot node is turned by -dir * lead, so the blade sits at +dir * lead in its frame.)
	var lead := float(_sweep_dir) * deg_to_rad(slash_lead_degrees)
	_slash_mirror.position = Vector2.from_angle(lead) * slash_distance

	# Stretch/squash the animation so it lasts exactly as long as the sweep
	var frames := _slash_sprite.sprite_frames
	var natural_length := float(frames.get_frame_count(_slash_anim)) / maxf(frames.get_animation_speed(_slash_anim), 0.01)
	_slash_sprite.speed_scale = natural_length / maxf(current_sweep_time, 0.01)

	_update_slash_rotation()
	_slash_pivot.show()
	_slash_sprite.stop()
	_slash_sprite.animation = _slash_anim
	_slash_sprite.frame = 0
	_slash_sprite.frame_progress = 0.0
	_slash_sprite.play(_slash_anim)


# Keeps the art's leading edge on the blade, with the rest of the art trailing behind it.
func _update_slash_rotation() -> void:
	if _slash_pivot == null:
		return
	_slash_pivot.rotation = _sweep_aim + _sweep_cur_rel - float(_sweep_dir) * deg_to_rad(slash_lead_degrees)


# Placeholder visuals (and the debug overlay). Hidden once you've assigned your own art.
func _draw() -> void:
	if not _sweeping and _fade_left <= 0.0:
		return
	var half_arc := deg_to_rad(attack_arc_degrees) * 0.5
	var fade := 1.0 if _sweeping else _fade_left / FADE_TIME

	if debug_draw_attack:
		_draw_wedge(_sweep_aim - half_arc, _sweep_aim + half_arc, Color(1, 0, 0, 0.15))
	if _slash_sprite != null:
		return  # Your art is showing; no placeholder needed

	# Trail from where the sweep started to where the blade is now
	var start_rel := -half_arc if _sweep_dir > 0 else half_arc
	_draw_wedge(_sweep_aim + start_rel, _sweep_aim + _sweep_cur_rel, Color(1, 1, 1, 0.25 * fade))
	var tip := Vector2.from_angle(_sweep_aim + _sweep_cur_rel) * attack_radius
	draw_line(Vector2.ZERO, tip, Color(1, 1, 1, 0.9 * fade), 4.0)


func _draw_wedge(from_angle: float, to_angle: float, color: Color) -> void:
	if absf(to_angle - from_angle) < 0.02:
		return  # Too thin to triangulate
	var points := PackedVector2Array([Vector2.ZERO])
	var steps := 24
	for i in range(steps + 1):
		var a := lerpf(from_angle, to_angle, float(i) / float(steps))
		points.append(Vector2.from_angle(a) * attack_radius)
	draw_colored_polygon(points, color)
