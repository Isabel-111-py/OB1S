
# BTActionWakeUp.gd
class_name BTActionWakeUp
extends BTNode

@export var animation_name: String = "wake_up" 
var waking_up: bool = false

func tick(actor: Node2D, blackboard: Dictionary) -> Status:
	# Si ya está despierto, pasamos directamente al siguiente nodo (persecución/ataque)
	if blackboard.get("is_awake", false):
		return Status.SUCCESS
		
	var sprite = actor.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null:
		return Status.FAILURE
	
	# Detener movimiento mientras se despierta
	if actor is CharacterBody2D:
		actor.velocity.x = 0.0
		
	if not waking_up:
		sprite.play(animation_name)
		waking_up = true
		return Status.RUNNING
		
	# Mientras la animación de despertar siga reproduciéndose, devolvemos RUNNING
	if sprite.is_playing() and sprite.animation == animation_name:
		return Status.RUNNING
	else:
		# ¡Terminó la animación! Marcamos que ya está despierto
		waking_up = false
		blackboard["is_awake"] = true
		return Status.SUCCESS
