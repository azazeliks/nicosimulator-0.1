# MobHits.gd
# Shared hit tests: "which mobs does this attack touch?" Every attack asks here instead of
# keeping its own copy of the maths. All of them follow the same rule: a mob counts as hit
# as soon as the attack's shape touches the EDGE of the mob, which means distance <= the
# attack's reach + the mob's hit_radius (see mob.gd). They only look at nodes in the "mobs"
# group that are still valid and have take_damage().
# Each function takes the SceneTree first (call it with get_tree()), because static functions
# have no node of their own to ask. They only find mobs; the caller decides what to do
# with them (damage, knockback, exploding...).
class_name MobHits
extends RefCounted


# Every mob touched by a circle (explosion, shockwave, a projectile's body...).
static func mobs_in_circle(tree: SceneTree, center: Vector2, radius: float) -> Array:
	var result: Array = []
	for mob in _damageable_mobs(tree):
		var reach: float = radius + float(mob.hit_radius)
		if center.distance_to(mob.global_position) <= reach:
			result.append(mob)
	return result


# Every mob touched by a thick line from `from` to `to` (a dash path). half_width is half the
# line's thickness.
static func mobs_near_segment(tree: SceneTree, from: Vector2, to: Vector2, half_width: float) -> Array:
	var result: Array = []
	for mob in _damageable_mobs(tree):
		var mob_pos: Vector2 = mob.global_position
		var closest := Geometry2D.get_closest_point_to_segment(mob_pos, from, to)
		if mob_pos.distance_to(closest) <= half_width + float(mob.hit_radius):
			result.append(mob)
	return result


# Like mobs_near_segment, but returns only the mob that the line reaches FIRST (closest to
# `from` along the line), or null if it touches none. Used by the throwing knife.
static func first_mob_on_segment(tree: SceneTree, from: Vector2, to: Vector2, radius: float) -> Node2D:
	var first: Node2D = null
	var first_dist := INF
	for mob in _damageable_mobs(tree):
		var closest := Geometry2D.get_closest_point_to_segment(mob.global_position, from, to)
		var reach: float = radius + float(mob.hit_radius)
		if closest.distance_to(mob.global_position) <= reach:
			var along := from.distance_to(closest)
			if along < first_dist:
				first_dist = along
				first = mob
	return first


# Every mob inside a pie slice (the slash). The slice starts at `origin`, reaches `radius`
# (plus each mob's size), and covers the angles from min_rel to max_rel in radians, measured
# from the direction `aim_angle` (positive = clockwise on screen, like Godot's angles).
# A mob right on top of `origin` always counts. Mobs have size, so each mob's angle range is
# widened a little: it counts as soon as the slice touches its edge.
static func mobs_in_sector(tree: SceneTree, origin: Vector2, radius: float, aim_angle: float, min_rel: float, max_rel: float) -> Array:
	var result: Array = []
	var aim_vec := Vector2.from_angle(aim_angle)
	for mob in _damageable_mobs(tree):
		var hit_r: float = mob.hit_radius
		var to_mob: Vector2 = mob.global_position - origin
		var dist := to_mob.length()
		if dist > radius + hit_r:
			continue
		if dist <= hit_r:
			result.append(mob)
			continue
		var rel := aim_vec.angle_to(to_mob)  # Mob's angle relative to the aim direction
		var margin := asin(clampf(hit_r / dist, 0.0, 1.0))
		if rel < min_rel - margin or rel > max_rel + margin:
			continue
		result.append(mob)
	return result


static func _damageable_mobs(tree: SceneTree) -> Array:
	var result: Array = []
	for mob in tree.get_nodes_in_group(Groups.MOBS):
		if is_instance_valid(mob) and mob.has_method("take_damage"):
			result.append(mob)
	return result
