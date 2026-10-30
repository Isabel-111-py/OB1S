# BTActionStandby.gd
class_name BTActionStandby
extends BTNode

@export var animation_name: String = "standby"

func tick(actor: Node2D, blackboard: Dictionary) -> Status:
	if actor is CharacterBody2D:
		actor.velocity.x = move_toward(actor.velocity.x, 0, 100) # Frenar suavemente
		
		var sprite = actor.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if sprite:
			if sprite.animation != animation_name or not sprite.is_playing():
				sprite.play(animation_name)
				
	return Status.RUNNING # Siempre devuelve RUNNING para mantener este estado activo por defecto
