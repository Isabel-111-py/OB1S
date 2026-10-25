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
signal charge_cancelled

## Escena de la flecha (debe tener el script arrow.gd en su nodo raíz).
@export var arrow_scene: PackedScene
## Acción del Input Map que carga y dispara el arco.
@export var shoot_action: StringName = &"shoot"

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


func _physics_process(delta: float) -> void:
	_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)
	var pressed := Input.is_action_pressed(shoot_action)

	if _player.is_dead:
		if is_charging:
			_cancel_charge()
		return

	if not is_charging:
		if pressed and _cooldown_timer <= 0.0:
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
	arrow_fired.emit(ratio)


func _spawn_arrow(direction: Vector2, ratio: float) -> void:
	if arrow_scene == null:
		push_error("Bow: asigna 'arrow_scene' en el Inspector.")
		return

	var arrow := arrow_scene.instantiate() as Arrow
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
