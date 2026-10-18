class_name StateMachine
extends Node
## Administra los estados hijos. Para agregar un estado nuevo basta con añadir
## un nodo hijo cuyo script extienda de State: no hay que registrar nada.

## Se emite en cada cambio de estado (también al entrar al estado inicial, con old_state = null).
signal state_changed(old_state: State, new_state: State)

## Estado con el que arranca el personaje (asígnalo en el Inspector).
@export var initial_state: State

var current_state: State
var states: Dictionary = {}


func _ready() -> void:
	# Esperamos a que el dueño (Player) termine su _ready para que sus @onready estén listos.
	await owner.ready

	for child in get_children():
		if child is State:
			states[child.name.to_lower()] = child
			child.player = owner as Player
			child.state_machine = self

	if initial_state == null:
		push_error("StateMachine: asigna un 'initial_state' en el Inspector.")
		return

	current_state = initial_state
	current_state.enter()
	state_changed.emit(null, current_state)


func _unhandled_input(event: InputEvent) -> void:
	if current_state:
		current_state.handle_input(event)


func _process(delta: float) -> void:
	if current_state:
		current_state.update(delta)


func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_update(delta)


## Cambia de estado usando el nombre del nodo (no distingue mayúsculas).
## Ejemplo: state_machine.transition_to("Jump")
func transition_to(state_name: String, msg: Dictionary = {}) -> void:
	var key := state_name.to_lower()
	if not states.has(key):
		push_warning("StateMachine: el estado '%s' no existe." % state_name)
		return

	var new_state: State = states[key]
	if new_state == current_state:
		return

	var old_state := current_state
	if old_state:
		old_state.exit()

	current_state = new_state
	current_state.enter(msg)
	state_changed.emit(old_state, current_state)
