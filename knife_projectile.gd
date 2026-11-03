# KnifeProjectile.gd
# A thrown knife made by ThrowingKnifeAttack. Flies in a straight line, damages the first
# mob in its path and disappears. It also disappears after its maximum range or when it
# leaves the screen. Drawn in code as a placeholder, so no art is needed yet.
class_name KnifeProjectile
extends Node2D

const OFFSCREEN_MARGIN := 120.0  # Knives are removed once this far outside the screen

var velocity := Vector2.ZERO
var damage := 1
var max_distance := 750.0
var body_radius := 10.0
var length := 34.0
var color := Color(0.85, 0.9, 1.0)

var _travelled := 0.0


func setup(new_velocity: Vector2, new_damage: int, new_max_distance: float, new_body_radius: float, new_length: float, new_color: Color) -> void:
	velocity = new_velocity
	damage = new_damage
	max_distance = new_max_distance
	body_radius = new_body_radius
	length = new_length
	color = new_color


func _ready() -> void:
	add_to_group("knives")  # So the attack can clear them when a run ends
	rotation = velocity.angle()


func _process(delta: float) -> void:
	var from := global_position
	var to := from + velocity * delta

	# Check the whole path travelled this frame (not just the end point), so a fast knife
	# can't skip over a mob. The mob closest along the path is the one that gets hit.
	var hit_mob: Node2D = null
	var hit_dist := INF
	for mob in get_tree().get_nodes_in_group("mobs"):
		if not is_instance_valid(mob) or not mob.has_method("take_damage"):
			continue
		var closest := Geometry2D.get_closest_point_to_segment(mob.global_position, from, to)
		var reach: float = body_radius + float(mob.hit_radius)
		if closest.distance_to(mob.global_position) <= reach:
			var along := from.distance_to(closest)
			if along < hit_dist:
				hit_dist = along
				hit_mob = mob
	if hit_mob != null:
		hit_mob.take_damage(damage)
		queue_free()
		return

	global_position = to
	_travelled += from.distance_to(to)
	if _travelled >= max_distance or not get_viewport_rect().grow(OFFSCREEN_MARGIN).has_point(global_position):
		queue_free()


# A simple dagger pointing along +X (the node is rotated to face its direction of travel)
func _draw() -> void:
	var half := length * 0.5
	var blade := PackedVector2Array([
		Vector2(half, 0.0),
		Vector2(-half * 0.2, -4.0),
		Vector2(-half * 0.2, 4.0),
	])
	draw_colored_polygon(blade, color)
	draw_line(Vector2(-half * 0.2, 0.0), Vector2(-half, 0.0), Color(0.45, 0.3, 0.2), 4.0)  # Handle
	draw_line(Vector2(-half * 0.2, -6.0), Vector2(-half * 0.2, 6.0), Color(0.6, 0.6, 0.65), 3.0)  # Guard
