# Player.gd
extends Area2D

signal hit  # Emitted when health reaches 0 (Main listens to this to end the run)
signal health_changed(current: int, maximum: int)

# Base stats. Shop upgrades are added on top of these at the start of each run.
@export var speed := 400
@export var base_max_health := 3
@export var base_attack_damage := 1
@export var base_attack_radius := 240.0  # How far the sweep reaches from the player (includes the gap before the slash starts)
@export_range(10.0, 180.0) var attack_arc_degrees := 100.0  # Total width of the sweep
@export var attack_cooldown := 0.6       # Seconds between attacks
@export var sweep_time := 0.2            # Seconds the swing takes to cross the arc
@export var invulnerability_time := 1.0  # Seconds of protection after being hit

# Your own attack art (all optional). Set these in the Inspector on the Player node.
# The art can be drawn at any angle: tell the script where its rotation point is,
# which way it points, and how long it is. The defaults match slash.png.
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
@export var debug_draw_attack := false   # Shows the real hit area in red, for lining up art

const FADE_TIME := 0.12  # How long the placeholder trail lingers after a sweep

var screen_size
var alive := false

# Current-run stats (recalculated in apply_upgrades)
var health := 0
var max_health := 3
var move_speed := 400.0
var attack_damage := 1
var attack_radius := 240.0
var current_cooldown := 0.6    # attack_cooldown divided by the attack speed multiplier
var current_sweep_time := 0.2  # sweep_time divided by the attack speed multiplier

var _invuln_left := 0.0
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


func _ready():
	screen_size = get_viewport_rect().size
	_register_inputs()
	_setup_slash()
	hide()


# Creates WASD movement and attack actions in code, unless you've already made
# actions with these names in Project Settings > Input Map.
func _register_inputs() -> void:
	_ensure_action("move_left", KEY_A)
	_ensure_action("move_right", KEY_D)
	_ensure_action("move_up", KEY_W)
	_ensure_action("move_down", KEY_S)
	# Attack: Space or left mouse button
	if _ensure_action("attack", KEY_SPACE):
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack", click)


# Returns true if the action was newly created.
func _ensure_action(action: String, keycode: Key) -> bool:
	if InputMap.has_action(action):
		return false
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode  # Physical key, so WASD works on any keyboard layout
	InputMap.action_add_event(action, ev)
	return true


func _process(delta):
	_update_sweep(delta)

	if not alive:
		return

	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_update_invulnerability(delta)

	var velocity = Vector2.ZERO
	if Input.is_action_pressed("move_right"): velocity.x += 1
	if Input.is_action_pressed("move_left"):  velocity.x -= 1
	if Input.is_action_pressed("move_down"):  velocity.y += 1
	if Input.is_action_pressed("move_up"):    velocity.y -= 1

	if velocity.length() > 0:
		velocity = velocity.normalized() * move_speed
		$AnimatedSprite2D.play()
	else:
		$AnimatedSprite2D.stop()

	position += velocity * delta
	position = position.clamp(Vector2.ZERO, screen_size)

	if velocity.x != 0:
		$AnimatedSprite2D.animation = "walk"
		$AnimatedSprite2D.flip_v = false
		$AnimatedSprite2D.flip_h = velocity.x > 0  # Art faces left by default, so flip when moving right
	elif velocity.y != 0:
		$AnimatedSprite2D.animation = "up"
		$AnimatedSprite2D.flip_v = false

	# Held, not just pressed: _attack() ignores the call while on cooldown, so
	# holding the button swings again as soon as the cooldown ends.
	if Input.is_action_pressed("attack"):
		_attack()


func _physics_process(_delta):
	# body_entered only fires when a mob first touches us. If a mob is still
	# overlapping when invulnerability ends, this makes it hurt us again.
	if not alive or _invuln_left > 0.0:
		return
	for body in get_overlapping_bodies():
		if body.is_in_group("mobs"):
			take_damage(body.contact_damage)
			break


func start(pos):
	position = pos
	apply_upgrades()
	health = max_health
	alive = true
	_invuln_left = 0.0
	_cooldown_left = 0.0
	_next_dir = 1  # First swing of every run goes left to right
	_cancel_sweep()
	$AnimatedSprite2D.modulate.a = 1.0
	show()
	$CollisionShape2D.disabled = false
	health_changed.emit(health, max_health)


# Combines base stats with whatever the player has bought in the shop.
func apply_upgrades() -> void:
	max_health = base_max_health + int(SaveData.bonus("max_health"))
	attack_damage = base_attack_damage + int(SaveData.bonus("damage"))
	attack_radius = base_attack_radius * (1.0 + SaveData.bonus("attack_range"))
	move_speed = speed + SaveData.bonus("speed")
	# Attack speed: the bonus is a fraction (0.15 = 15% faster). It shortens both the
	# swing itself (which also speeds up the slash animation) and the cooldown.
	var attack_speed_mult := 1.0 + SaveData.bonus("attack_speed")
	current_cooldown = attack_cooldown / attack_speed_mult
	current_sweep_time = sweep_time / attack_speed_mult


func take_damage(amount: int = 1) -> void:
	if not alive or _invuln_left > 0.0:
		return
	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)
	if health <= 0:
		_die()
	else:
		_invuln_left = invulnerability_time


func _die() -> void:
	alive = false
	_cancel_sweep()
	hide()
	$CollisionShape2D.set_deferred("disabled", true)
	hit.emit()


func _update_invulnerability(delta: float) -> void:
	if _invuln_left > 0.0:
		_invuln_left = maxf(_invuln_left - delta, 0.0)
	# Blink while protected
	var blink := _invuln_left > 0.0 and int(_invuln_left * 12.0) % 2 == 0
	$AnimatedSprite2D.modulate.a = 0.35 if blink else 1.0


# ------------------------------------------------------------------ attack

# Starts a sweep aimed at the mouse. Each attack swings the opposite way from the last.
func _attack() -> void:
	if _cooldown_left > 0.0:
		return
	_cooldown_left = current_cooldown

	var aim := get_global_mouse_position() - global_position
	if aim.length_squared() < 1.0:
		aim = Vector2.RIGHT  # Mouse is exactly on the player; pick any direction
	_sweep_aim = aim.angle()  # Locked in: the swing doesn't follow the mouse afterwards

	_sweep_dir = _next_dir
	_next_dir = -_next_dir
	_sweep_elapsed = 0.0
	_sweeping = true
	_fade_left = 0.0
	_hit_this_sweep.clear()

	_start_slash_visual()
	_update_sweep(0.0)  # Apply the very first slice right away


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
			mob.take_damage(attack_damage)
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
			mob.take_damage(attack_damage)


func _end_sweep() -> void:
	_sweeping = false
	_fade_left = FADE_TIME
	if _slash_pivot != null:
		_slash_pivot.hide()
		_slash_sprite.stop()


func _cancel_sweep() -> void:
	_sweeping = false
	_fade_left = 0.0
	_hit_this_sweep.clear()
	if _slash_pivot != null:
		_slash_pivot.hide()
		_slash_sprite.stop()
	queue_redraw()


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
	_slash_sprite.offset = -slash_pivot  # Puts the pivot pixel at the sprite's origin
	_slash_sprite.rotation = deg_to_rad(-slash_art_angle)  # Turns the art so its middle points along +x
	_slash_sprite.scale = Vector2(s, s)

	# The second swing is a mirror image of the first (slash_flip_y swaps which one)
	var mirror := (_sweep_dir < 0) != slash_flip_y
	_slash_mirror.scale = Vector2(1.0, -1.0 if mirror else 1.0)
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
func _draw():
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


# Still connected to body_entered in player.tscn
func _on_body_entered(body):
	if body.is_in_group("mobs"):
		take_damage(body.contact_damage)
