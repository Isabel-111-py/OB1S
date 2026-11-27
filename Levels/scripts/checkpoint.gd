class_name Checkpoint
extends Area2D
## Al tocarlo, el jugador reaparecerá aquí si cae al vacío o muere.
## Coloca el origen del nodo a la altura del suelo. Añádele un CollisionShape2D hijo.
##
## Guardado MANUAL: mientras el jugador esté dentro, aparece el aviso "[E] Guardar partida".
## Al pulsar E se abre el menú de ranuras (SaveSlotsMenu) y el jugador elige dónde guardar.
## Nunca se guarda automáticamente.

@export var facing_right: bool = true
## Recarga por completo la energía del jugador al entrar en el checkpoint.
@export var refills_energy: bool = true
## true: recarga cada vez que entras (aunque el checkpoint ya esté activado).
## false: solo la primera vez que lo activas.
@export var refill_every_time: bool = true

@export_group("Guardado")
## Texto del aviso que aparece sobre el checkpoint.
@export var save_prompt_text: String = "[E] Guardar partida"
## Altura (px) del aviso sobre el origen del checkpoint.
@export var prompt_height: float = 52.0

var _activated: bool = false
var _player_inside: bool = false
var _prompt: Label
var _save_menu: SaveSlotsMenu


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_prompt()


func _on_body_entered(body: Node2D) -> void:
	var player := body as Player
	if player == null:
		return

	_player_inside = true
	_prompt.visible = true

	if refills_energy and (refill_every_time or not _activated):
		player.refill_energy()

	_activated = true
	SceneManager.set_checkpoint(global_position, _facing_value())


func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		_player_inside = false
		_prompt.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not _player_inside or is_instance_valid(_save_menu):
		return
	if not event.is_action_pressed(&"interact") or event.is_echo():
		return

	# No abrir si el juego está en pausa (inventario) o el jugador no está en condiciones.
	var player: Player = SceneManager.player
	if get_tree().paused or not is_instance_valid(player) or player.is_dead:
		return
	if player.process_mode == Node.PROCESS_MODE_DISABLED:
		return

	get_viewport().set_input_as_handled()
	_open_save_menu()


func _open_save_menu() -> void:
	_prompt.visible = false
	_save_menu = SaveSlotsMenu.open_save(self, global_position, _facing_value())
	_save_menu.closed.connect(_on_save_menu_closed)


func _on_save_menu_closed() -> void:
	_save_menu = null
	_prompt.visible = _player_inside


func _facing_value() -> float:
	return 1.0 if facing_right else -1.0


func _build_prompt() -> void:
	_prompt = Label.new()
	_prompt.text = save_prompt_text
	_prompt.visible = false
	_prompt.z_index = 100
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.custom_minimum_size = Vector2(140, 0)
	_prompt.position = Vector2(-70.0, -prompt_height)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var settings := LabelSettings.new()
	settings.font_size = 10
	settings.font_color = Color(0.98, 0.933, 0.824)
	settings.outline_size = 4
	settings.outline_color = Color(0.059, 0.09, 0.122)
	_prompt.label_settings = settings
	add_child(_prompt)
