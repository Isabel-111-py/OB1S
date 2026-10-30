@tool
class_name SpawnPoint
extends Marker2D
## Punto donde aparece el jugador al entrar a un nivel. Colócalo en el suelo.
## El id debe coincidir con el `target_spawn` del LevelExit que lleva hasta aquí.

@export var id: StringName = &"default"
@export var facing_right: bool = true


func _ready() -> void:
	add_to_group("spawn_points")


func get_facing() -> float:
	return 1.0 if facing_right else -1.0
