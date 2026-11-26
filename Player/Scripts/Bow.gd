class_name Bow
extends Node2D
## Arco. Mantén presionada la acción "shoot" (clic derecho) para cargarlo:
##  - La flecha SOLO se lanza cuando sueltas el botón.
##  - Cuanto menos tiempo cargues, menos velocidad y menos alcance tendrá la flecha.
##  - Al llegar a la carga máxima el arco queda cargado a tope hasta que sueltes (potencia máxima).
## La flecha sale siempre hacia el mouse.
##
## Colócalo como hijo directo del Player, a la altura del pecho o del brazo.
## Si le agregas un Sprite2D hijo (arco apuntando hacia +X) se mostrará y rotará mientras cargas.

signal charge_started
## Se emite cada frame mientras cargas. ratio va de 0.0 a 1.0 (útil para una barra de carga).
signal charge_changed(ratio: float)
## Se emite una vez al alcanzar la carga máxima (útil para un destello o un sonido de aviso).
signal fully_charged
signal arrow_fired(ratio: float)
## Se emite al intentar disparar sin flechas del tipo seleccionado (útil para un sonido o un aviso).
signal out_of_ammo
signal charge_cancelled

## Escena de la flecha (debe tener el script arrow.gd en su nodo raíz).
@export var arrow_scene: PackedScene
## Acción del Input Map que carga y dispara el arco.
@export var shoot_action: StringName = &"shoot"
## Si está activado, cada disparo gasta una flecha de la munición seleccionada (ver Inventory) y,
## sin flechas de ese tipo, no se puede cargar el arco hasta cambiar de munición o conseguir más.
## Desactivado = flechas infinitas.
@export var use_ammo: bool = true
## Los 3 tipos de munición (nombre, icono, flecha propia, cantidad inicial). Si no los defines,
## se usan 3 tipos de prueba.
@export var ammo_types: Array[AmmoType] = []

@export_group("Cambio de munición")
## Acciones del Input Map para elegir cada tipo. Si no existen, se usan las teclas 1, 2 y 3.
@export var select_actions: Array[StringName] = [&"ammo_1", &"ammo_2", &"ammo_3"]
## Rueda del ratón: pasa al siguiente / anterior tipo de munición.
@export var cycle_with_mouse_wheel: bool = true

const FALLBACK_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3]

@export_group("Carga")
## Segundos manteniendo el botón hasta alcanzar la carga máxima (potencia máxima).
@export var max_charge_time: float = 0.8
## Segundos de espera tras un disparo antes de poder cargar otra vez.
@export var cooldown: float = 0.25

@export_group("Flecha")
## Velocidad de la flecha con carga mínima (px/s).
@export var min_arrow_speed: float = 180.0
## Velocidad de la flecha con carga máxima (px/s).
@export var max_arrow_speed: float = 520.0
## Distancia desde el arco a la que aparece la flecha, en la dirección de apuntado.
@export var muzzle_distance: float = 10.0
## Si el arco quedó exactamente en el origen del Player (normalmente los pies), se sube
## esta cantidad de px, a la altura del pecho. Si ya lo moviste tú en el editor, no se toca.
@export var default_height: float = 16.0

var is_charging: bool = false
## Carga actual de 0.0 a 1.0.
var charge_ratio: float:
	get:
		return clampf(_charge_time / maxf(max_charge_time, 0.001), 0.0, 1.0)

var _charge_time: float = 0.0
var _cooldown_timer: float = 0.0
var _full_notified: bool = false
var _player: Player


func _ready() -> void:
	_player = get_parent() as Player
	if _player == null:
		push_error("Bow: debe ser hijo directo del Player.")
		set_physics_process(false)
		return

	if position.is_zero_approx():
		position.y = -default_height
	visible = false
	Inventory.setup_ammo(ammo_types)


func _physics_process(delta: float) -> void:
	_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)
	var pressed := Input.is_action_pressed(shoot_action)

	if _player.is_dead:
		if is_charging:
			_cancel_charge()
		return

	# Con el paraguas equipado no se puede disparar (y se cancela cualquier carga en curso).
	if Inventory.umbrella_equipped:
		if is_charging:
			_cancel_charge()
		return

	if not is_charging:
		if Input.is_action_just_pressed(shoot_action) and use_ammo and not Inventory.has_arrows():
			out_of_ammo.emit()
		if pressed and _cooldown_timer <= 0.0 and (not use_ammo or Inventory.has_arrows()):
			_start_charge()
		else:
			return

	# Soltó el botón: dispara con la carga que lleve.
	if not pressed:
		_fire()
		return

	_charge_time = minf(_charge_time + delta, max_charge_time)
	_update_aim()
	charge_changed.emit(charge_ratio)

	# Carga máxima: el arco queda cargado a tope hasta que sueltes el botón.
	if _charge_time >= max_charge_time and not _full_notified:
		_full_notified = true
		fully_charged.emit()


## Elegir munición: teclas 1-3 (o tus acciones) y rueda del ratón. No se puede cambiar mientras cargas.
func _unhandled_input(event: InputEvent) -> void:
	if _player == null or _player.is_dead or is_charging:
		return

	for slot in Inventory.SLOT_COUNT:
		if _is_select_event(event, slot):
			Inventory.select_ammo(slot)
			get_viewport().set_input_as_handled()
			return

	var wheel := event as InputEventMouseButton
	if cycle_with_mouse_wheel and wheel and wheel.pressed:
		if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
			Inventory.cycle_ammo(-1)
			get_viewport().set_input_as_handled()
		elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			Inventory.cycle_ammo(1)
			get_viewport().set_input_as_handled()


func _is_select_event(event: InputEvent, slot: int) -> bool:
	if slot < select_actions.size() and InputMap.has_action(select_actions[slot]):
		return event.is_action_pressed(select_actions[slot])
	var key_event := event as InputEventKey
	return key_event != null and key_event.pressed and not key_event.echo \
		and key_event.physical_keycode == FALLBACK_KEYS[slot]


## Dirección normalizada desde el arco hacia el mouse (en coordenadas del mundo).
func get_aim_direction() -> Vector2:
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length_squared() < 1.0:
		return Vector2(_player.facing, 0.0)
	return to_mouse.normalized()


func _start_charge() -> void:
	is_charging = true
	_charge_time = 0.0
	_full_notified = false
	visible = true
	charge_started.emit()


func _cancel_charge() -> void:
	_end_charge()
	charge_cancelled.emit()


func _end_charge() -> void:
	is_charging = false
	_charge_time = 0.0
	visible = false
	_player.facing_lock = 0.0


func _fire() -> void:
	var ratio := charge_ratio
	var direction := get_aim_direction()
	_end_charge()
	_cooldown_timer = cooldown
	_spawn_arrow(direction, ratio)
	if use_ammo:
		Inventory.use_arrow() # después de elegir la escena: el tipo no cambia durante la carga
	arrow_fired.emit(ratio)


func _spawn_arrow(direction: Vector2, ratio: float) -> void:
	var scene: PackedScene = Inventory.get_selected_arrow_scene(arrow_scene)
	if scene == null:
		push_error("Bow: asigna 'arrow_scene' en el Inspector.")
		return

	var arrow := scene.instantiate() as Arrow
	if arrow == null:
		push_error("Bow: el nodo raíz de 'arrow_scene' debe tener el script arrow.gd.")
		return

	get_tree().current_scene.add_child(arrow)
	arrow.global_position = global_position + direction * muzzle_distance
	arrow.launch(direction * lerpf(min_arrow_speed, max_arrow_speed, ratio), _player)


## Rota el arco hacia el mouse y hace que el personaje mire hacia ese lado.
func _update_aim() -> void:
	var direction := get_aim_direction()
	rotation = direction.angle()
	# Evita que el sprite del arco quede boca abajo al apuntar hacia la izquierda.
	scale.y = -1.0 if direction.x < 0.0 else 1.0

	if not is_zero_approx(direction.x):
		_player.facing_lock = signf(direction.x)
		_player.face(direction.x)
