# ThrowingKnifeAttack.gd
# Nico's secondary attack: a small, fast, low-damage knife thrown toward the mouse.
# Holding the button keeps throwing as fast as the cooldown allows, but it can't be thrown
# while the primary attack is mid-slash. Each knife hits the first mob it touches and is
# used up. Settings live on the root node of the attack scene (see cat_knife_attack.tscn).
# Uses the shared upgrades: damage (knife damage), attack_range (how far it flies) and
# attack_speed (throw rate).
class_name ThrowingKnifeAttack
extends Attack

@export var attack_cooldown := 1.05          # Seconds between throws (level 0; Attack Speed divides it)
@export var knife_speed := 1400.0            # Pixels per second
@export var base_knife_range := 750.0        # Pixels a knife flies before it vanishes (the range upgrade scales it)
@export_range(0.1, 2.0) var damage_fraction := 0.5  # Knife damage as a share of the character's attack damage (rounded, never below 1)
@export var knife_length := 34.0             # Size of the placeholder knife art
@export var knife_body_radius := 10.0        # How "fat" the knife is when checking for hits
@export var knife_color := Color(0.85, 0.9, 1.0)
@export var muzzle_distance := 30.0          # How far from the player a knife starts

# Current-run stats (recalculated in configure)
var knife_range := 750.0
var knife_damage := 1
var current_cooldown := 1.05

var _cooldown_left := 0.0


func configure(new_damage: int, new_range_mult: float, new_speed_mult: float, new_bonuses: Dictionary) -> void:
	super.configure(new_damage, new_range_mult, new_speed_mult, new_bonuses)
	knife_range = base_knife_range * range_mult
	knife_damage = maxi(1, roundi(damage * damage_fraction))
	current_cooldown = attack_cooldown / speed_mult


func start_run() -> void:
	_cooldown_left = 0.0
	cancel()


# Removes any knives still flying (they live in the scene, not under the player)
func cancel() -> void:
	get_tree().call_group("knives", "queue_free")


func tick(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)


# Nico can't throw while his slash is in progress
func can_start_while(primary: Attack) -> bool:
	return primary == null or not primary.is_busy()


func try_attack(target: Vector2) -> bool:
	if _cooldown_left > 0.0:
		return false
	_cooldown_left = current_cooldown

	var aim := target - global_position
	if aim.length_squared() < 1.0:
		aim = Vector2.RIGHT  # Mouse is exactly on the player; pick any direction
	var direction := aim.normalized()

	var knife := KnifeProjectile.new()
	knife.setup(direction * knife_speed, knife_damage, knife_range, knife_body_radius, knife_length, knife_color)
	# Added to the main scene, not to the player, so it doesn't move with the player
	get_tree().current_scene.add_child(knife)
	knife.global_position = global_position + direction * muzzle_distance
	return true
