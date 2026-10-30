# BTActionChase2D.gd
class_name BTActionChase2D
extends BTNode

@export var speed: float = 100.0
@export var animation_name: String = "walk"

@export_group("Configuración Visual")
## Marca esta casilla si el sprite original del enemigo mira hacia la DERECHA por defecto.
## Desmárcala si el sprite original mira hacia la IZQUIERDA por defecto.
@export var sprite_faces_right: bool = false

func tick(actor: Node2D, blackboard: Dictionary) -> Status:
	var player = blackboard.get("player") as Node2D
	if player == null or not is_instance_valid(player):
		return Status.FAILURE
	
	var direction = (player.global_position - actor.global_position).normalized()
	
	if actor is CharacterBody2D:
		actor.velocity.x = direction.x * speed
		
		var sprite = actor.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if sprite:
			if sprite.animation != animation_name or not sprite.is_playing():
				sprite.play(animation_name)
			
			if direction.x != 0:
				if sprite_faces_right:
					# Si el sprite original mira a la DERECHA:
					# Se voltea (flip_h = true) cuando se mueve a la IZQUIERDA (< 0)
					sprite.flip_h = direction.x < 0
				else:
					# Si el sprite original mira a la IZQUIERDA:
					# Se voltea (flip_h = true) cuando se mueve a la DERECHA (> 0)
					sprite.flip_h = direction.x > 0
				
		return Status.RUNNING
	
	return Status.FAILURE
