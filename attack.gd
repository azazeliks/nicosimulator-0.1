# Attack.gd
# The shared interface every attack type follows. The player never knows HOW an
# attack works: it only calls the functions below. To make a new attack type
# (projectile, ground slam, ...), create a script that extends Attack and fill in
# these functions, then point a character at a scene that uses it.
class_name Attack
extends Node2D

# Set by the player at the start of each run (base stats + shop upgrades)
var damage := 1
var range_mult := 1.0  # Multiplies the attack's reach ("attack_range" upgrade)
var speed_mult := 1.0  # Divides the cooldown ("attack_speed" upgrade)
var bonuses := {}      # Every shop upgrade's current bonus, by upgrade id. Read it with bonus(SaveData.SOME_UPGRADE)

# Seconds until the attack can be used again. Subclasses set it when they fire, reset it in
# start_run(), and count it down by calling _tick_cooldown(delta) from tick().
var _cooldown_left := 0.0


# Called at the start of every run, before start_run().
func configure(new_damage: int, new_range_mult: float, new_speed_mult: float, new_bonuses: Dictionary) -> void:
	damage = new_damage
	range_mult = new_range_mult
	speed_mult = new_speed_mult
	bonuses = new_bonuses


# Bonus of a shop upgrade at its current level (0 if the character hasn't bought any).
# This is how an attack reads its own unique upgrades, e.g. bonus(SaveData.PROJECTILE_COUNT).
# The player hands over EVERY upgrade (see Player.apply_upgrades), so an id that is missing
# here can only be a typo, and we say so instead of quietly returning 0.
func bonus(upgrade_id: String) -> float:
	if not bonuses.has(upgrade_id):
		push_warning("Attack.bonus(): unknown upgrade id '%s' (typo? use the names in SaveData)." % upgrade_id)
		return 0.0
	return float(bonuses[upgrade_id])


# Resets per-run state (cooldowns, swing direction, ...).
func start_run() -> void:
	pass


# Stops anything in progress (used when the run ends).
func cancel() -> void:
	pass


# Called by the player every frame so the attack can advance its timers.
func tick(_delta: float) -> void:
	pass


# Return true while the attack is moving the player itself (like a dash). The player then
# skips its normal movement and attack input until this returns false again.
func is_controlling_movement() -> bool:
	return false


# Multiplies the player's walking speed while this attack is active (1.0 = no change).
# An attack returns less than 1.0 to slow the player down, e.g. during a wind-up.
func movement_speed_multiplier() -> float:
	return 1.0


# Return true while the player should take no damage (for example during a dash).
func is_invulnerable() -> bool:
	return false


# Return true while the attack is mid-swing / mid-cast (a slash in progress, a dash charging).
# Other attacks can ask this, e.g. the throwing knife won't fire during a slash.
func is_busy() -> bool:
	return false


# Called by the player before it triggers this attack as the SECONDARY one. Return false to
# refuse while `primary` (the left-click attack) is doing something. Default: always allowed,
# so a secondary can be used on top of the primary.
func can_start_while(_primary: Attack) -> bool:
	return true


# The player asks for an attack aimed at a point in the world.
# Returns true if the attack actually started (false while on cooldown).
func try_attack(_target: Vector2) -> bool:
	return false


# ------------------------------------------------------------ for subclasses

# Counts the cooldown down. Call it from tick().
func _tick_cooldown(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)


# The direction (a unit vector) from this attack to the target. If the target is exactly on
# the player there is no direction, so it picks "right" instead of dividing by zero.
func _aim_direction(target: Vector2) -> Vector2:
	var aim := target - global_position
	if aim.length_squared() < 1.0:
		return Vector2.RIGHT
	return aim.normalized()
