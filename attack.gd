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
var bonuses := {}      # Every shop upgrade's current bonus, by upgrade id. Read it with bonus("id")


# Called at the start of every run, before start_run().
func configure(new_damage: int, new_range_mult: float, new_speed_mult: float, new_bonuses: Dictionary) -> void:
	damage = new_damage
	range_mult = new_range_mult
	speed_mult = new_speed_mult
	bonuses = new_bonuses


# Bonus of a shop upgrade at its current level (0 if the character doesn't have it).
# This is how an attack reads its own unique upgrades, e.g. bonus("projectile_count").
func bonus(upgrade_id: String) -> float:
	return float(bonuses.get(upgrade_id, 0.0))


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
