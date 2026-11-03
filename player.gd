# Player.gd
extends Area2D

signal hit  # Emitted when health reaches 0 (Main listens to this to end the run)
signal health_changed(current: int, maximum: int)

# Base stats. Shop upgrades are added on top of these at the start of each run.
# The attack itself (reach, cooldown, swing time, slash art) lives on the SweepAttack child node.
@export var speed := 400
@export var base_max_health := 3
@export var base_attack_damage := 1
@export var invulnerability_time := 1.0  # Seconds of protection after being hit

var screen_size
var alive := false

# Current-run stats (recalculated in apply_upgrades)
var health := 0
var max_health := 3
var move_speed := 400.0

var _invuln_left := 0.0

# The attack this player uses. For now it is always the SweepAttack child node.
@onready var attack: Attack = $SweepAttack


func _ready():
	screen_size = get_viewport_rect().size
	_register_inputs()
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
	attack.tick(delta)  # Lets the attack advance its swing and cooldown

	if not alive:
		return

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

	# Held, not just pressed: the attack ignores the request while on cooldown, so
	# holding the button swings again as soon as the cooldown ends.
	if Input.is_action_pressed("attack"):
		attack.try_attack(get_global_mouse_position())


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
	attack.start_run()
	$AnimatedSprite2D.modulate.a = 1.0
	show()
	$CollisionShape2D.disabled = false
	health_changed.emit(health, max_health)


# Combines base stats with whatever the player has bought in the shop.
func apply_upgrades() -> void:
	max_health = base_max_health + int(SaveData.bonus("max_health"))
	move_speed = speed + SaveData.bonus("speed")
	# The attack gets its numbers handed over: damage, reach multiplier, speed multiplier
	attack.configure(
		base_attack_damage + int(SaveData.bonus("damage")),
		1.0 + SaveData.bonus("attack_range"),
		1.0 + SaveData.bonus("attack_speed")
	)


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
	attack.cancel()
	hide()
	$CollisionShape2D.set_deferred("disabled", true)
	hit.emit()


func _update_invulnerability(delta: float) -> void:
	if _invuln_left > 0.0:
		_invuln_left = maxf(_invuln_left - delta, 0.0)
	# Blink while protected
	var blink := _invuln_left > 0.0 and int(_invuln_left * 12.0) % 2 == 0
	$AnimatedSprite2D.modulate.a = 0.35 if blink else 1.0


# Still connected to body_entered in player.tscn
func _on_body_entered(body):
	if body.is_in_group("mobs"):
		take_damage(body.contact_damage)
