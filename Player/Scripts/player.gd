class_name Player
extends CharacterBody2D
## El jugador solo guarda parámetros y utilidades compartidas.
## La lógica de cada acción vive en los estados (nodos hijos de StateMachine)
## y las animaciones las gestiona el nodo AnimationManager.

## Se emite cada vez que cambia la vida (útil para la barra de vida de la UI).
signal health_changed(current: int, maximum: int)
## Se emite una sola vez cuando la vida llega a 0.
signal died
## Se emite cada vez que cambia la energía (la usa la barra de energía del HUD).
signal energy_changed(current: float, maximum: float)

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

@export_group("Inercia")
## Frenado (px/s²) de la velocidad que SOBREPASA la máxima en el aire (por ejemplo, al soltarte de
## la cuerda). Más bajo = el impulso se conserva más tiempo. Cerca de la velocidad máxima el frenado
## se acerca poco a poco al normal, para que no haya un cambio brusco.
@export var air_momentum_decel: float = 120.0
## Lo mismo en el suelo (al aterrizar manteniendo la dirección).
@export var ground_momentum_decel: float = 350.0

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
@export var dash_speed: float = 400.0
## Duración del impulso en segundos.
@export var dash_time: float = 0.2
## Espera (s) tras terminar un dash antes de poder usar otro.
@export var dash_cooldown: float = 0.35
## Dashes permitidos en el aire antes de volver a tocar el suelo.
@export var max_air_dashes: int = 1
## Mientras mantengas presionado el botón turbo, la velocidad máxima se multiplica por esto.
@export var turbo_speed_multiplier: float = 2
## Estados desde los que se puede iniciar un dash (nombres de los nodos).
@export var dash_allowed_from: Array[StringName] = [&"Idle", &"Run", &"Jump", &"Fall"]

@export_group("Salud")
@export var max_health: int = 5

@export_group("Energía")
## Energía máxima. La gastan el turbo y el gancho, y se recupera sola cuando no los usas.
@export var max_energy: float = 100.0
## Energía que cuesta cada dash.
@export var dash_energy_cost: float = 20.0
## Energía por segundo que gasta correr con el turbo mantenido (no cuenta durante el dash).
@export var turbo_drain_per_second: float = 12.0
## Energía que cuesta lanzar el gancho.
@export var grapple_energy_cost: float = 10.0
## Energía por segundo que gasta el gancho mientras estás colgado de la cuerda.
@export var grapple_drain_per_second: float = 8.0
## Si está activado, la energía se recupera sola cuando no usas turbo ni gancho.
## Desactívalo para que solo se recargue al tocar un checkpoint (o donde llames a refill_energy()).
@export var energy_regen_enabled: bool = true
## Energía por segundo que se recupera sola (solo si energy_regen_enabled está activado).
@export var energy_regen_per_second: float = 30.0
## Segundos de espera, después de gastar energía, antes de que empiece a recuperarse.
@export var energy_regen_delay: float = 0.6
## Al llegar a 0 te "agotas": no puedes usar turbo ni gancho hasta recuperar esta fracción (0-1).
@export_range(0.0, 1.0) var energy_recover_fraction: float = 0.25

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
var energy: float = 0.0
## true cuando la energía llegó a 0 y aún no se recupera lo suficiente.
var energy_exhausted: bool = false
var _energy_regen_timer: float = 0.0

@onready var animator: AnimationManager = $AnimationManager
@onready var state_machine: StateMachine = $StateMachine
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var grapple: Grapple = get_node_or_null("Grapple") as Grapple


func _ready() -> void:
	add_to_group("player")
	health = max_health
	energy = max_energy
	air_dashes_left = max_air_dashes
	hurtbox.hit_received.connect(_on_hit_received)
	health_changed.emit(health, max_health)
	energy_changed.emit(energy, max_energy)


func _physics_process(delta: float) -> void:
	# El padre se procesa ANTES que sus hijos, así que los timers
	# ya están actualizados cuando corre el estado actual.
	_update_timers(delta)
	_update_energy(delta)
	_try_dash()


func _update_timers(delta: float) -> void:
	# Agotado = sin energía: el turbo mantenido no da velocidad extra hasta recuperarte.
	turbo_held = Input.is_action_pressed("turbo") and not energy_exhausted
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
##  - Input en el mismo sentido: aceleración progresiva hasta `speed`. Si ya ibas más rápido
##    (por ejemplo, al aterrizar tras soltarte de la cuerda), el exceso se frena suavemente.
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
		# Si ya vas más rápido que el máximo en esa dirección, el exceso se frena suavemente.
		if absf(velocity.x) > get_max_speed() and signf(direction) == signf(velocity.x):
			accel = _overspeed_decel(accel, ground_momentum_decel)
		velocity.x = move_toward(velocity.x, direction * get_max_speed(), accel * delta)


## Aire: control reducido, sin rueda libre. La velocidad que sobrepasa la máxima (impulso de la
## cuerda, dash...) se conserva: solo se frena el exceso, y suavemente (air_momentum_decel).
## Presionar la dirección contraria sí frena con normalidad.
func move_air(direction: float, delta: float) -> void:
	var max_speed := get_max_speed()
	var has_momentum := absf(velocity.x) > max_speed

	if is_zero_approx(direction):
		var decel := speed / maxf(air_time_to_stop, 0.001)
		if has_momentum:
			decel = _overspeed_decel(decel, air_momentum_decel)
		velocity.x = move_toward(velocity.x, 0.0, decel * delta)
	else:
		var accel := max_speed / maxf(air_time_to_max_speed, 0.001)
		if has_momentum and signf(direction) == signf(velocity.x):
			accel = _overspeed_decel(accel, air_momentum_decel)
		velocity.x = move_toward(velocity.x, direction * max_speed, accel * delta)


## Frenado a aplicar cuando se va más rápido que la velocidad máxima: con mucho exceso es
## `momentum_decel` (suave) y, a medida que la velocidad baja hacia el máximo, se acerca a
## `normal_decel`. Así no hay un cambio brusco al "nivelarse" con la velocidad máxima.
func _overspeed_decel(normal_decel: float, momentum_decel: float) -> float:
	var max_speed := get_max_speed()
	var excess_ratio := clampf((absf(velocity.x) - max_speed) / maxf(max_speed, 0.001), 0.0, 1.0)
	return lerpf(normal_decel, momentum_decel, excess_ratio)


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
# Respawn / cambio de nivel
# ---------------------------------------------------------------------------

## Recoloca al jugador y lo devuelve a un estado limpio (respawn o entrada a un nivel).
func respawn_at(pos: Vector2, dir: float = 1.0, full_heal: bool = false) -> void:
	global_position = pos
	velocity = Vector2.ZERO

	if full_heal:
		health = max_health
		health_changed.emit(health, max_health)
		energy_exhausted = false
		_set_energy(max_energy)
	is_dead = false

	facing_lock = 0.0
	coyote_timer = 0.0
	jump_buffer_timer = 0.0
	dash_cooldown_timer = 0.0
	air_dashes_left = max_air_dashes
	hurtbox.active = true

	if grapple:
		grapple.detach()

	face(dir)
	state_machine.transition_to("Idle")

	# Evita que la cámara "viaje" desde la posición anterior.
	var camera := get_node_or_null("Camera2D") as Camera2D
	if camera:
		camera.reset_smoothing()
		camera.force_update_scroll()


# ---------------------------------------------------------------------------
# Energía
# ---------------------------------------------------------------------------

## true si hay energía suficiente para pagar `cost` (y no estás agotado).
func can_spend_energy(cost: float) -> bool:
	return not energy_exhausted and energy >= cost


## Gasta energía de golpe (por ejemplo, un dash o lanzar el gancho) y retrasa la recuperación.
func spend_energy(cost: float) -> void:
	_energy_regen_timer = energy_regen_delay
	_set_energy(energy - cost)


## Llena la energía por completo y quita el agotamiento (lo usa el Checkpoint).
func refill_energy() -> void:
	energy_exhausted = false
	_set_energy(max_energy)


## Restaura la energía (y el agotamiento) al cambiar de nivel; lo llama el SceneManager.
func restore_energy(value: float, exhausted: bool) -> void:
	energy_exhausted = exhausted
	_set_energy(value)


## Gasto continuo del turbo y del gancho, y recuperación cuando no se usan.
func _update_energy(delta: float) -> void:
	var state_name: StringName = &""
	if state_machine.current_state:
		state_name = state_machine.current_state.name

	var drain := 0.0
	if turbo_held and state_name != &"Dash" and not is_zero_approx(get_input_direction()):
		drain += turbo_drain_per_second
	if grapple and grapple.is_attached:
		drain += grapple_drain_per_second

	if drain > 0.0:
		_energy_regen_timer = energy_regen_delay
		_set_energy(energy - drain * delta)
		# Sin energía, el gancho se suelta.
		if energy_exhausted and grapple and grapple.is_attached:
			grapple.detach()
	else:
		_energy_regen_timer -= delta
		if energy_regen_enabled and _energy_regen_timer <= 0.0 and energy < max_energy:
			_set_energy(energy + energy_regen_per_second * delta)


func _set_energy(value: float) -> void:
	var previous := energy
	energy = clampf(value, 0.0, max_energy)
	if energy <= 0.0:
		energy_exhausted = true
	elif energy_exhausted and energy >= max_energy * energy_recover_fraction:
		energy_exhausted = false
	if not is_equal_approx(energy, previous) or energy == 0.0:
		energy_changed.emit(energy, max_energy)


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
	if not can_spend_energy(dash_energy_cost):
		return

	if not is_on_floor():
		if air_dashes_left <= 0:
			return
		air_dashes_left -= 1

	spend_energy(dash_energy_cost)
	state_machine.transition_to("Dash")
