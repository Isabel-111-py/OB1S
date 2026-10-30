# BTConditionCanSeePlayer.gd
class_name BTConditionCanSeePlayer
extends BTNode

@export var vision_distance: float = 200.0

func tick(actor: Node2D, blackboard: Dictionary) -> Status:
	var player = blackboard.get("player") as Node2D
	
	# Si no está en la memoria, intenta buscarlo por grupo o por clase
	if player == null or not is_instance_valid(player):
		player = actor.get_tree().get_first_node_in_group("Player") as Node2D
		if player == null:
			player = actor.get_tree().get_first_node_in_ref("Player") # fallback alternativo
		if player != null:
			blackboard["player"] = player
			
	if player == null or not is_instance_valid(player):
		return Status.FAILURE
	
	var distance = actor.global_position.distance_to(player.global_position)
	if distance <= vision_distance:
		return Status.SUCCESS
		
	return Status.FAILURE
