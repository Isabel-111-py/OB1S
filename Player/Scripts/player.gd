class_name Player
extends CharacterBody2D
## El jugador solo guarda parámetros y utilidades compartidas.
## La lógica de cada acción vive en los estados (nodos hijos de StateMachine)
## y las animaciones las gestiona el nodo AnimationManager.

## Se emite cada vez que cambia la vida (útil para la barra de vida de la UI).
signal health_changed(current: int, maximum: int)
## Se emite una sola vez cuando la vida llega a 0.
signal died

@export_group("Movimiento")
@export var speed: float = 220.0
## Segundos que tarda en llegar a la velocidad máxima desde parado (en suelo).
@export var time_to_max_speed: float = 0.25
## Distancia aproximada (px) que avanza por inercia al soltar la dirección yendo a velocidad máxima.
## Es proporcional a la velocidad: a la mitad de velocidad desliza la mitad.
@export var coast_distance: float = 40.0
## Por debajo de esta velocidad (px/s) la rueda libre se corta y el robot se detiene por completo.
@export var coast_stop_speed: float = 10.0
## Segundos que tarda en frenar desde velocidad máxima al presionar la dirección contraria.
@export var time_to_brake: float = 0.08
## En el aire: segundos para llegar a velocidad máxima y para detenerse sin input.
@export var air_time_to_max_speed: float = 0.35
@export var air_time_to_stop: float = 0.6

@export_group("Salto")
## Velocidad inicial del salto (negativa = hacia arriba).
@export var jump_velocity: float = -380.0
## Tiempo máximo (s) que mantener el botón presionado sostiene la subida.
## Un toque rápido da un saltito; mantener hasta este tiempo da el salto completo.
@export var jump_hold_time: float = 0.22
## Si sueltas el botón antes de tiempo, la velocidad de subida se multiplica por esto
## (0 = corte seco, 1 = no recorta).
@export_range(0.0, 1.0) var jump_cut_multiplier: float = 0.4
## Tiempo coyote: margen (s) para saltar justo después de salir de una plataforma.
@export var coyote_time: float = 0.12
## Jump buffer: margen (s) para registrar un salto presionado justo antes de aterrizar.
@export var jump_buffer_time: float = 0.1

@export_group("Gravedad")
@export var fall_gravity_multiplier: float = 1.4
@export var max_fall_speed: float = 700.0

@export_group("Turbo")
## Velocidad del impulso (dash) en px/s.
@export var dash_speed: float = 520.0
## Duración del impulso en segundos.
@export var dash_time: float = 0.16
## Espera (s) tras terminar un dash antes de poder usar otro.
@export var dash_cooldown: float = 0.35
## Dashes permitidos en el aire antes de volver a tocar el suelo.
@export var max_air_dashes: int = 1
## Mientras mantengas presionado el botón turbo, la velocidad máxima se multiplica por esto.
@export var turbo_speed_multiplier: float = 1.3
## Estados desde los que se puede iniciar un dash (nombres de los nodos).
@export var dash_allowed_from: Array[StringName] = [&"Idle", &"Run", &"Jump", &"Fall"]

@export_group("Salud")
@export var max_health: int = 5

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
## Hacia dónde mira el personaje: 1.0 derecha, -1.0 izquierda (útil para dash, ataques, etc.).
var facing: float = 1.0
## Si no es 0, fuerza hacia dónde mira el personaje (lo usa el arco mientras apunta).
var facing_lock: float = 0.0
var health: int = 0
var is_dead: bool = false
var turbo_held: bool = false
var dash_cooldown_timer: float = 0.0
var air_dashes_left: int = 0

@onready var animator: AnimationManager = $AnimationManager
@onready var state_machine: StateMachine = $StateMachine
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var grapple: Grapple = get_node_or_null("Grapple") as Grapple


func _ready() -> void:
	health = max_health
	air_dashes_left = max_air_dashes
	hurtbox.hit_received.connect(_on_hit_received)
	health_changed.emit(health, max_health)


func _physics_process(delta: float) -> void:
	# El padre se procesa ANTES que sus hijos, así que los timers
	# ya están actualizados cuando corre el estado actual.
	_update_timers(delta)
	_try_dash()


func _update_timers(delta: float) -> void:
	turbo_held = Input.is_action_pressed("turbo")
	dash_cooldown_timer = maxf(dash_cooldown_timer - delta, 0.0)

	# `velocity.y >= 0` evita que el coyote time se reinicie justo al saltar (doble salto accidental).
	if is_on_floor() and velocity.y >= 0.0:
		coyote_timer = coyote_time
		air_dashes_left = max_air_dashes
	else:
		coyote_timer = maxf(coyote_timer - delta, 0.0)

	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time
	else:
		jump_buffer_timer = maxf(jump_buffer_timer - delta, 0.0)


# ---------------------------------------------------------------------------
# Utilidades para los estados
# ---------------------------------------------------------------------------

func get_input_direction() -> float:
	return Input.get_axis("move_left", "move_right")


## true si hay un salto pedido (buffer) y se permite saltar (suelo o coyote time).
func jump_requested() -> bool:
	return jump_buffer_timer > 0.0 and coyote_timer > 0.0


func consume_jump() -> void:
	jump_buffer_timer = 0.0
	coyote_timer = 0.0


func apply_gravity(delta: float, multiplier: float = 1.0) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * multiplier * delta, max_fall_speed)


## Suelo (robot con ruedas):
##  - Sin input: rueda libre, avanza por inercia (la distancia depende de la velocidad que llevaba).
##  - Input contrario al movimiento: frenado fuerte, sin deslizar, y luego arranca al otro lado.
##  - Input en el mismo sentido: aceleración progresiva hasta `speed`.
func move_ground(direction: float, delta: float) -> void:
	if is_zero_approx(direction):
		# Rueda libre: la velocidad decae de forma exponencial (como una rueda con poca fricción).
		# Distancia recorrida ≈ velocidad / drag  ->  proporcional a la velocidad que llevaba.
		var drag := speed / maxf(coast_distance, 0.001)
		velocity.x *= exp(-drag * delta)
		if absf(velocity.x) < coast_stop_speed:
			velocity.x = 0.0
	elif not is_zero_approx(velocity.x) and signf(direction) != signf(velocity.x):
		var brake_decel := get_max_speed() / maxf(time_to_brake, 0.001)
		velocity.x = move_toward(velocity.x, 0.0, brake_decel * delta)
	else:
		var accel := get_max_speed() / maxf(time_to_max_speed, 0.001)
		velocity.x = move_toward(velocity.x, direction * get_max_speed(), accel * delta)


## Aire: control reducido, sin rueda libre ni frenado especial.
func move_air(direction: float, delta: float) -> void:
	if is_zero_approx(direction):
		var decel := speed / maxf(air_time_to_stop, 0.001)
		velocity.x = move_toward(velocity.x, 0.0, decel * delta)
	else:
		var accel := get_max_speed() / maxf(air_time_to_max_speed, 0.001)
		velocity.x = move_toward(velocity.x, direction * get_max_speed(), accel * delta)


func face(direction: float) -> void:
	if not is_zero_approx(facing_lock):
		direction = facing_lock
	if is_zero_approx(direction):
		return
	facing = signf(direction)
	animator.set_facing(facing)


# ---------------------------------------------------------------------------
# Salud y daño
# ---------------------------------------------------------------------------

## Resta vida y pasa al estado Hurt (o Dead si la vida llega a 0).
## Puedes llamarla desde cualquier lugar (caída al vacío, scripts, etc.).
func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO) -> void:
	if is_dead:
		return

	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)

	var msg := {"knockback": knockback}
	if health == 0:
		is_dead = true
		died.emit()
		state_machine.transition_to("Dead", msg)
	else:
		state_machine.transition_to("Hurt", msg)


func heal(amount: int) -> void:
	if is_dead:
		return
	health = mini(health + amount, max_health)
	health_changed.emit(health, max_health)


func _on_hit_received(hitbox: Hitbox) -> void:
	# El retroceso empuja al jugador en dirección contraria al atacante.
	var direction := signf(global_position.x - hitbox.global_position.x)
	if is_zero_approx(direction):
		direction = -facing
	take_damage(hitbox.damage, Vector2(direction * hitbox.knockback.x, hitbox.knockback.y))


# ---------------------------------------------------------------------------
# Turbo
# ---------------------------------------------------------------------------

## Velocidad horizontal máxima actual: aumenta mientras mantienes el botón turbo.
func get_max_speed() -> float:
	return speed * (turbo_speed_multiplier if turbo_held else 1.0)


## Al presionar "turbo" inicia el dash si el estado actual lo permite.
## Se hace aquí (y no en cada estado) para poder agregar el dash sin modificar Idle/Run/Jump/Fall.
func _try_dash() -> void:
	if not Input.is_action_just_pressed("turbo"):
		return
	if is_dead or dash_cooldown_timer > 0.0 or state_machine.current_state == null:
		return
	if not dash_allowed_from.has(state_machine.current_state.name):
		return

	if not is_on_floor():
		if air_dashes_left <= 0:
			return
		air_dashes_left -= 1

	state_machine.transition_to("Dash")
