class_name LevelExit
extends Area2D
## Zona que lleva al jugador a otro nivel. Añádele un CollisionShape2D hijo.

@export_file("*.tscn") var target_level: String
## id del SpawnPoint del nivel de destino donde aparecerá el jugador.
@export var target_spawn: StringName = &"default"


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not (body is Player) or (body as Player).is_dead:
		return
	if target_level.is_empty():
		push_warning("LevelExit '%s': falta asignar target_level." % name)
		return
	SceneManager.change_level(target_level, target_spawn)
