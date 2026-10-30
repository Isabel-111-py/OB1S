class_name Checkpoint
extends Area2D
## Al tocarlo, el jugador reaparecerá aquí si cae al vacío o muere.
## Coloca el origen del nodo a la altura del suelo. Añádele un CollisionShape2D hijo.

@export var facing_right: bool = true

var _activated: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if _activated or not (body is Player):
		return
	_activated = true
	SceneManager.set_checkpoint(global_position, 1.0 if facing_right else -1.0)
