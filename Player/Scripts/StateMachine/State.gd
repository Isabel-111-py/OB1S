class_name State
extends Node
## Clase base de todos los estados. Cada estado es un nodo hijo del StateMachine.
## Sobrescribe solo los métodos que necesites.

## Animación que el AnimationManager reproduce al entrar a este estado.
## Si lo dejas vacío se usa el nombre del nodo en minúsculas (nodo "Dash" -> "dash").
@export var animation: StringName = &""

## Referencias asignadas automáticamente por el StateMachine.
var player: Player
var state_machine: StateMachine


func get_animation_name() -> StringName:
	return animation if animation != &"" else StringName(name.to_lower())


## Se llama al entrar al estado. `msg` permite pasar datos desde el estado anterior.
func enter(_msg: Dictionary = {}) -> void:
	pass


## Se llama al salir del estado (limpieza).
func exit() -> void:
	pass


## Eventos de input no consumidos (equivale a _unhandled_input).
func handle_input(_event: InputEvent) -> void:
	pass


## Equivale a _process.
func update(_delta: float) -> void:
	pass


## Equivale a _physics_process.
func physics_update(_delta: float) -> void:
	pass
