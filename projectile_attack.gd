# ProjectileAttack.gd
# Fires one or more exploding projectiles toward the mouse. Settings are set on the root
# node of the character's attack scene (see dragon_projectile_attack.tscn).
# Uses the shared upgrades: damage (explosion damage), attack_range (explosion size) and
# attack_speed (fire rate), plus the unique "projectile_count" upgrade.
class_name ProjectileAttack
extends Attack

@export var attack_cooldown := 0.9        # Seconds between shots (level 0; Attack Speed divides it)
@export var projectile_speed := 650.0     # Pixels per second
@export var fuse_time := 1.0              # Seconds before a projectile explodes on its own
@export var base_explosion_radius := 130.0  # Explosion reach in pixels (level 0; the range upgrade scales it)
@export var base_projectile_count := 1    # Projectiles per shot (the unique upgrade adds more)
@export_range(0.0, 90.0) var spread_degrees := 14.0  # Angle between neighbouring projectiles in a shot
@export var projectile_size := 14.0       # Radius of the fireball itself (placeholder circle)
@export var projectile_color := Color(1.0, 0.6, 0.1)
@export var muzzle_distance := 40.0       # How far from the player a projectile starts

# Current-run stats (recalculated in configure)
var explosion_radius := 130.0
var current_cooldown := 0.9
var projectile_count := 1


func configure(new_damage: int, new_range_mult: float, new_speed_mult: float, new_bonuses: Dictionary) -> void:
	super.configure(new_damage, new_range_mult, new_speed_mult, new_bonuses)
	explosion_radius = base_explosion_radius * range_mult
	current_cooldown = attack_cooldown / speed_mult
	projectile_count = base_projectile_count + int(bonus(SaveData.PROJECTILE_COUNT))


func start_run() -> void:
	_cooldown_left = 0.0
	cancel()


# Removes any projectiles still flying (they live in the scene, not under the player)
func cancel() -> void:
	get_tree().call_group(Groups.PROJECTILES, "queue_free")


func tick(delta: float) -> void:
	_tick_cooldown(delta)


func try_attack(target: Vector2) -> bool:
	if _cooldown_left > 0.0:
		return false
	_cooldown_left = current_cooldown

	var base_angle := _aim_direction(target).angle()
	var spread := deg_to_rad(spread_degrees)

	# Fan the projectiles out around the aim direction
	for i in projectile_count:
		var offset := (float(i) - (projectile_count - 1) * 0.5) * spread
		_spawn(Vector2.from_angle(base_angle + offset))
	return true


func _spawn(direction: Vector2) -> void:
	var p := Projectile.new()
	p.setup(direction * projectile_speed, fuse_time, damage, explosion_radius, projectile_size, projectile_color)
	# Added to the main scene, not to the player, so it doesn't move with the player
	get_tree().current_scene.add_child(p)
	p.global_position = global_position + direction * muzzle_distance
