# BTConditionTargetInRange.gd
class_name BTConditionTargetInRange
extends BTNode

@export var attack_range: float = 40.0 # Distancia corta para golpear

func tick(actor: Node2D, blackboard: Dictionary) -> Status:
	var player = blackboard.get("player") as Node2D
	if player == null or not is_instance_valid(player):
		return Status.FAILURE
	
	var distance = actor.global_position.distance_to(player.global_position)
	
	# Si está dentro del rango de ataque, da SUCCESS (ataca)
	if distance <= attack_range:
		return Status.SUCCESS
		
	# Si está lejos, da FAILURE para que el árbol baje a la persecución
	return Status.FAILURE
