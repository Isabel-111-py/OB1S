class_name Checkpoint
extends Area2D
## Al tocarlo, el jugador reaparecerá aquí si cae al vacío o muere.
## Coloca el origen del nodo a la altura del suelo. Añádele un CollisionShape2D hijo.

@export var facing_right: bool = true
## Recarga por completo la energía del jugador al entrar en el checkpoint.
@export var refills_energy: bool = true
## true: recarga cada vez que entras (aunque el checkpoint ya esté activado).
## false: solo la primera vez que lo activas.
@export var refill_every_time: bool = true

var _activated: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	var player := body as Player
	if player == null:
		return

	if refills_energy and (refill_every_time or not _activated):
		player.refill_energy()

	if _activated:
		return
	_activated = true
	SceneManager.set_checkpoint(global_position, 1.0 if facing_right else -1.0)
