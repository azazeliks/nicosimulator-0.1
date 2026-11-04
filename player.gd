# Player.gd
extends Area2D

signal hit  # Emitted when health reaches 0 (Main listens to this to end the run)
signal health_changed(current: int, maximum: int)

# Which character this player is. This is only the default; at runtime Main calls
# set_character() with the character picked on the selection screen.
@export var character: CharacterData
@export var invulnerability_time := 1.0  # Seconds of protection after being hit

# Base stats, copied from the character in set_character(). Shop upgrades are added on top
# of these at the start of each run.
var speed := 400
var base_max_health := 3
var base_attack_damage := 1
var base_regen_interval := 0.0  # Seconds to regenerate 1 HP (0 = no regeneration)

var screen_size
var alive := false

# Current-run stats (recalculated in apply_upgrades)
var health := 0
var max_health := 3
var move_speed := 400.0
var regen_interval := 0.0  # base_regen_interval sped up by the Regeneration upgrade

var _invuln_left := 0.0
var _regen_left := 0.0

# The attack node of the current character (created from character.attack_scene)
var attack: Attack
# The optional right-click attack (created from character.secondary_attack_scene)
var secondary_attack: Attack


func _ready():
	add_to_group(Groups.PLAYER)  # Mobs look the player up by this group to chase it
	screen_size = get_viewport_rect().size
	_register_inputs()
	if character != null:
		set_character(character)
	else:
		push_error("Player has no character assigned. Set 'Character' on the Player node in player.tscn.")
	hide()


# Turns this player into the given character: stats, sprites and attack.
func set_character(data: CharacterData) -> void:
	character = data
	speed = data.speed
	base_max_health = data.base_max_health
	base_attack_damage = data.base_attack_damage
	base_regen_interval = data.regen_interval
	# self_modulate tints the sprite without touching modulate.a, which the hit-blink uses
	$AnimatedSprite2D.self_modulate = data.sprite_tint

	if data.sprite_frames != null:
		$AnimatedSprite2D.sprite_frames = data.sprite_frames
		$AnimatedSprite2D.animation = &"walk"

	# Swap in this character's attack
	if attack != null:
		remove_child(attack)
		attack.queue_free()
		attack = null
	if data.attack_scene != null:
		attack = data.attack_scene.instantiate() as Attack
		if attack == null:
			push_error("Character '%s': attack_scene's root script must extend Attack." % data.id)
		else:
			add_child(attack)

	# Same for the secondary (right-click) attack, which may not exist
	if secondary_attack != null:
		remove_child(secondary_attack)
		secondary_attack.queue_free()
		secondary_attack = null
	if data.secondary_attack_scene != null:
		secondary_attack = data.secondary_attack_scene.instantiate() as Attack
		if secondary_attack == null:
			push_error("Character '%s': secondary_attack_scene's root script must extend Attack." % data.id)
		else:
			add_child(secondary_attack)


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
	# Secondary attack: right mouse button
	if not InputMap.has_action("attack_secondary"):
		InputMap.add_action("attack_secondary")
		var right_click := InputEventMouseButton.new()
		right_click.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("attack_secondary", right_click)


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
	if attack != null:
		attack.tick(delta)  # Lets the attack advance its swing and cooldown
	if secondary_attack != null:
		secondary_attack.tick(delta)

	if not alive:
		return

	_update_invulnerability(delta)
	_update_regen(delta)

	# Some attacks (the bruiser's dash) move the player themselves, so skip normal movement
	# and attack input
	if _attack_controls_movement():
		_update_animation(Vector2.ZERO, true)
		return

	_handle_attack_input()

	var velocity = Vector2.ZERO
	if Input.is_action_pressed("move_right"): velocity.x += 1
	if Input.is_action_pressed("move_left"):  velocity.x -= 1
	if Input.is_action_pressed("move_down"):  velocity.y += 1
	if Input.is_action_pressed("move_up"):    velocity.y -= 1

	if velocity.length() > 0:
		var slow := 1.0  # e.g. the bruiser's wind-up; both attacks can slow the player
		if attack != null:
			slow *= attack.movement_speed_multiplier()
		if secondary_attack != null:
			slow *= secondary_attack.movement_speed_multiplier()
		velocity = velocity.normalized() * move_speed * slow
	position += velocity * delta
	position = position.clamp(Vector2.ZERO, screen_size)

	_update_animation(velocity, false)


# The one place that decides which sprite animation plays. `velocity` is where the player is
# moving this frame; `rooted` is true while an attack (a dash) is moving or holding the player.
#   rooted           -> "idle" if the character has it, otherwise the sprite carries on as it was
#   moving sideways  -> "walk", flipped to face the way you go
#   moving up/down   -> "up" (or "walk" if the character has no "up")
#   standing still   -> "idle" if the character has it, otherwise the sprite freezes
func _update_animation(velocity: Vector2, rooted: bool) -> void:
	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	var frames := sprite.sprite_frames
	if frames == null:
		return
	if rooted:
		if frames.has_animation(&"idle"):
			_play_animation(&"idle")
		return
	if velocity.length() > 0:
		sprite.flip_v = false
		if velocity.x != 0:
			_play_animation(&"walk")
			sprite.flip_h = velocity.x > 0  # Art faces left by default, so flip when moving right
		elif frames.has_animation(&"up"):
			_play_animation(&"up")
		else:
			_play_animation(&"walk")
	elif frames.has_animation(&"idle"):
		_play_animation(&"idle")  # Keeps the last facing direction
	else:
		sprite.stop()


# Plays an animation without restarting it every frame
func _play_animation(anim: StringName) -> void:
	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	if sprite.animation != anim or not sprite.is_playing():
		sprite.play(anim)


# Held, not just pressed: an attack ignores the request while on cooldown, so holding the
# button fires again as soon as the cooldown ends.
# The secondary is checked FIRST and on its own, so right click fires whether or not left
# click is being held or the primary is mid-swing. (A secondary can still refuse by
# overriding can_start_while, e.g. Nico's knife won't throw during a slash.)
func _handle_attack_input() -> void:
	var mouse := get_global_mouse_position()
	if secondary_attack != null and Input.is_action_pressed("attack_secondary"):
		if secondary_attack.can_start_while(attack):
			secondary_attack.try_attack(mouse)
	if attack != null and Input.is_action_pressed("attack"):
		attack.try_attack(mouse)


func _physics_process(_delta):
	# body_entered only fires when a mob first touches us. If a mob is still
	# overlapping when invulnerability ends, this makes it hurt us again.
	if not alive or _invuln_left > 0.0:
		return
	for body in get_overlapping_bodies():
		if _can_hurt_us(body):
			take_damage(body.contact_damage)
			break


# Does touching this body hurt us? Mobs do, unless they are paralysed.
func _can_hurt_us(body: Node) -> bool:
	return body.is_in_group(Groups.MOBS) and not body.is_paralyzed()


func start(pos):
	if character == null or attack == null:
		push_error("Player can't start: no character or attack set up.")
		return
	position = pos
	apply_upgrades()
	health = max_health
	alive = true
	_invuln_left = 0.0
	_regen_left = regen_interval
	attack.start_run()
	if secondary_attack != null:
		secondary_attack.start_run()
	$AnimatedSprite2D.modulate.a = 1.0
	show()
	$CollisionShape2D.disabled = false
	health_changed.emit(health, max_health)


# Combines base stats with whatever the player has bought in the shop (for this character).
func apply_upgrades() -> void:
	max_health = base_max_health + int(SaveData.bonus(character, SaveData.MAX_HEALTH))
	move_speed = speed + SaveData.bonus(character, SaveData.SPEED)
	# Regeneration: the bonus is a fraction (0.2 = 20% faster), so the wait between heals shrinks
	regen_interval = base_regen_interval / (1.0 + SaveData.bonus(character, SaveData.REGEN)) if base_regen_interval > 0.0 else 0.0
	# The attacks get their numbers handed over: damage, reach multiplier, speed multiplier, and
	# every upgrade's bonus so they can read their own unique ones (e.g. projectile_count)
	var bonuses := {}
	for id in SaveData.UPGRADES:
		bonuses[id] = SaveData.bonus(character, id)
	var attack_damage := base_attack_damage + int(SaveData.bonus(character, SaveData.DAMAGE))
	var range_mult := 1.0 + SaveData.bonus(character, SaveData.ATTACK_RANGE)
	var speed_mult := 1.0 + SaveData.bonus(character, SaveData.ATTACK_SPEED)
	# The secondary gets the same numbers as the primary; it decides which of them it uses
	for each_attack in [attack, secondary_attack]:
		if each_attack != null:
			each_attack.configure(attack_damage, range_mult, speed_mult, bonuses)


func take_damage(amount: int = 1) -> void:
	if not alive or _invuln_left > 0.0:
		return
	if (attack != null and attack.is_invulnerable()) or (secondary_attack != null and secondary_attack.is_invulnerable()):
		return  # e.g. mid-dash
	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)
	if health <= 0:
		_die()
	else:
		_invuln_left = invulnerability_time


# True while either attack is moving the player itself (a dash)
func _attack_controls_movement() -> bool:
	return (attack != null and attack.is_controlling_movement()) \
		or (secondary_attack != null and secondary_attack.is_controlling_movement())


func _die() -> void:
	stop_run()
	hit.emit()


# Ends the run without the "hit" signal: stops both attacks, hides the player and turns off
# its collision. Used when the player dies and when the run is abandoned from the pause menu.
func stop_run() -> void:
	alive = false
	if attack != null:
		attack.cancel()
	if secondary_attack != null:
		secondary_attack.cancel()
	hide()
	$CollisionShape2D.set_deferred("disabled", true)


# Heals 1 HP every regen_interval seconds while hurt. The wait starts over once at full health.
func _update_regen(delta: float) -> void:
	if regen_interval <= 0.0 or health >= max_health:
		_regen_left = regen_interval
		return
	_regen_left -= delta
	if _regen_left <= 0.0:
		health += 1
		_regen_left = regen_interval
		health_changed.emit(health, max_health)


func _update_invulnerability(delta: float) -> void:
	if _invuln_left > 0.0:
		_invuln_left = maxf(_invuln_left - delta, 0.0)
	# Blink while protected
	var blink := _invuln_left > 0.0 and int(_invuln_left * 12.0) % 2 == 0
	$AnimatedSprite2D.modulate.a = 0.35 if blink else 1.0


# Still connected to body_entered in player.tscn
func _on_body_entered(body):
	if _can_hurt_us(body):
		take_damage(body.contact_damage)
