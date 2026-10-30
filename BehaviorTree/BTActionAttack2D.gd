# BTActionAttack2D.gd
class_name BTActionAttack2D
extends BTNode

@export var attack_range: float = 40.0

func tick(actor: Node2D, blackboard: Dictionary) -> Status:
	var player = blackboard.get("player") as Node2D
	if player == null or not is_instance_valid(player):
		return Status.FAILURE
	
	var distance = actor.global_position.distance_to(player.global_position)
	
	# ¡MUY IMPORTANTE!: Si el jugador se aleja durante el ataque, 
	# devolvemos FAILURE para romper la secuencia y que vuelva a perseguir.
	if distance > attack_range:
		return Status.FAILURE 
	
	# Lógica de ataque...
	if actor is CharacterBody2D:
		actor.velocity.x = 0.0
		
	var sprite = actor.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite:
		sprite.play("attack")
		
	return Status.RUNNING
