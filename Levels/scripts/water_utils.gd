class_name WaterUtils
extends RefCounted
## Utilidades compartidas por la lluvia y las cascadas.


static func find_umbrella(tree: SceneTree) -> Umbrella:
	return tree.get_first_node_in_group("umbrella") as Umbrella


static func find_player(tree: SceneTree) -> Player:
	return tree.get_first_node_in_group("player") as Player


## Altura (Y global) del primer sólido que hay bajo (x, from_y), o INF si no hay ninguno hasta to_y.
static func solid_y_below(space: PhysicsDirectSpaceState2D, x: float, from_y: float, to_y: float,
		mask: int, exclude: Array[RID]) -> float:
	var query := PhysicsRayQueryParameters2D.create(Vector2(x, from_y), Vector2(x, to_y), mask)
	query.exclude = exclude
	var hit := space.intersect_ray(query)
	return hit.position.y if not hit.is_empty() else INF


## true si hay un sólido (techo, plataforma) encima de `point`, hasta `distance` píxeles.
static func has_roof_above(space: PhysicsDirectSpaceState2D, point: Vector2, distance: float,
		mask: int, exclude: Array[RID]) -> bool:
	var query := PhysicsRayQueryParameters2D.create(point, point + Vector2(0.0, -distance), mask)
	query.exclude = exclude
	return not space.intersect_ray(query).is_empty()


static func exclude_for(player: Player) -> Array[RID]:
	var result: Array[RID] = []
	if player:
		result.append(player.get_rid())
	return result
