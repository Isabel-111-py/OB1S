class_name Grapple
extends Node2D
## Gancho con cuerda. El clic izquierdo (acción "grapple") dispara el gancho desde este nodo
## hacia el mouse: viaja por el aire (se ve salir del lanzador) y, si toca una superficie,
## la cuerda se engancha y el Player pasa al estado "Swing". Si no toca nada, regresa.
##
## La cuerda NO es una recta rígida: guarda una lista de puntos de apoyo. Cuando una esquina
## del escenario se interpone, se agrega un punto ahí y la cuerda se dobla; cuando la esquina
## deja de estorbar, el punto se quita y la cuerda se vuelve a estirar.
##
## Colócalo como hijo directo del Player. Su posición es el punto del que sale el gancho
## (tu lanzador); si lo dejas en (0, 0) se sube solo a la altura del pecho.

signal hook_fired(direction: Vector2)
signal rope_attached(anchor: Vector2)
signal rope_detached
signal rope_missed

enum HookState { IDLE, FLYING, ATTACHED, RETURNING }

const MAX_WRAPS_PER_STEP: int = 6
const BISECT_STEPS: int = 16
## Cada cuántos px se revisa el movimiento de la mano entre dos frames.
const SWEEP_STEP: float = 5.0
const MAX_SWEEP_STEPS: int = 12
const MIN_SEGMENT_LENGTH: float = 0.5
const UNWRAP_EPSILON: float = 0.5
## Sondeos alrededor de una esquina para saber hacia qué lado está libre.
const CORNER_PROBES: int = 16
## Rayos a cada lado de la dirección exacta para la asistencia de puntería.
const AIM_ASSIST_RAYS: int = 12
const CORNER_PROBE_RADIUS: float = 2.0

@export_group("Controles")
@export var grapple_action: StringName = &"grapple"
@export var retract_action: StringName = &"rope_retract"
@export var extend_action: StringName = &"rope_extend"
## false: mantén el botón (hasta que el gancho se clave y mientras quieras seguir colgado).
## true: un clic dispara y otro clic suelta o cancela.
@export var toggle_mode: bool = false
## Input buffer: tiempo (s) que se recuerda un clic del gancho que no se pudo usar en ese momento
## (por la espera tras soltarte, o porque aún estabas saliendo del balanceo). El gancho se lanza
## en cuanto es posible. Conviene que sea un poco mayor que fire_cooldown. 0 = sin buffer.
@export var input_buffer_time: float = 0.25

@export_group("Cuerda")
## Alcance máximo del gancho y largo máximo de la cuerda (px).
@export var max_rope_length: float = 260.0
## Tramo libre mínimo (px) de la cuerda al retraer.
@export var min_length: float = 16.0
## Distancia mínima (px) entre la mano y la superficie para poder engancharse. Es muy pequeña a
## propósito: así también se puede enganchar una pared pegada al personaje.
@export var min_attach_distance: float = 1.0
## Velocidad (px/s) al retraer o soltar cuerda.
@export var reel_speed: float = 140.0
## Velocidad (px/s) a la que viaja el gancho hasta el objetivo.
@export var hook_speed: float = 1400.0
## Velocidad (px/s) a la que el gancho regresa cuando falla o te sueltas.
@export var hook_return_speed: float = 2000.0
## Capas contra las que choca la cuerda (el escenario).
@export_flags_2d_physics var rope_collision_mask: int = 1
## Separación (px) entre los puntos de apoyo y la esquina, para que la cuerda no quede incrustada.
## Con bordes muy finos (escalones de píxel) conviene un valor pequeño.
@export var wrap_offset: float = 1.0
## Si la cuerda no logra resolverse sin atravesar el escenario durante este tiempo (s), se corta
## como último recurso. 0 = nunca se corta: sigue reintentando hasta resolverse.
@export var max_unresolved_time: float = 1.5
## Espera (s) antes de poder lanzar el gancho otra vez.
@export var fire_cooldown: float = 0.2
## Si el nodo está en (0, 0), se sube esta cantidad de px (altura del pecho).
@export var default_height: float = 16.0
## Estados desde los que se puede lanzar el gancho (nombres de los nodos).
@export var grapple_allowed_from: Array[StringName] = [&"Idle", &"Run", &"Jump", &"Fall"]

@export_group("Asistencia de puntería")
## Si donde apuntas no hay una superficie para enganchar, el gancho se dirige a la más cercana
## al cursor, siempre que esté a menos de esta distancia (px) de él. 0 = sin asistencia.
@export var aim_assist_radius: float = 24.0
## Desvío máximo (grados) que la asistencia puede aplicar a la dirección del disparo.
@export_range(0.0, 45.0) var aim_assist_max_angle: float = 20.0

@export_group("Salto desde la cuerda")
## Cuántas veces puedes saltar desde la cuerda estando en el aire, hasta volver a tocar el suelo.
## 0 = en el aire la tecla de salto solo te suelta de la cuerda, sin saltar.
@export var max_rope_jumps: int = 1

@export_group("Dibujo")
@export var rope_color: Color = Color(0.85, 0.85, 0.85)
@export var rope_width: float = 1.5

@export_group("Depuración")
## Dibuja en amarillo los puntos donde la cuerda se dobla, y en rojo el último tramo
## cuando no logra resolverse.
@export var debug_draw: bool = false
## Escribe en la consola por qué la cuerda no pudo doblarse en una esquina.
@export var debug_log: bool = false

var is_attached: bool = false
## Saltos desde la cuerda que quedan en el aire (se recargan al tocar el suelo).
var rope_jumps_left: int = 0
## Largo total de la cuerda (suma de todos sus tramos).
var rope_length: float = 0.0
## Puntos de la cuerda: el [0] es el gancho; los demás son esquinas donde se dobla.
## El último tramo va desde el último punto hasta la mano del Player.
var points: Array[Vector2] = []

var _hook_state: HookState = HookState.IDLE
var _hook_pos: Vector2 = Vector2.ZERO
var _hook_dir: Vector2 = Vector2.RIGHT
var _wrap_signs: Array[float] = []
var _prev_hand: Vector2 = Vector2.ZERO
var _cooldown_timer: float = 0.0
var _buffer_timer: float = 0.0
var _unresolved_time: float = 0.0
var _failure: String = ""
var _player: Player


func _ready() -> void:
	_player = get_parent() as Player
	if _player == null:
		push_error("Grapple: debe ser hijo directo del Player.")
		set_physics_process(false)
		return

	if position.is_zero_approx():
		position.y = -default_height

	rope_jumps_left = max_rope_jumps

	for action in [grapple_action, retract_action, extend_action]:
		if not InputMap.has_action(action):
			push_warning("Grapple: falta la acción '%s' en el Input Map." % action)


func _process(_delta: float) -> void:
	if _hook_state != HookState.IDLE:
		queue_redraw()


func _physics_process(delta: float) -> void:
	_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)

	# Input buffer: se recuerda el último clic durante un instante, por si aún no se puede usar.
	if Input.is_action_just_pressed(grapple_action):
		_buffer_timer = input_buffer_time
	else:
		_buffer_timer = maxf(_buffer_timer - delta, 0.0)

	# Los saltos desde la cuerda en el aire se recargan al tocar el suelo.
	if _player.is_on_floor():
		rope_jumps_left = max_rope_jumps

	match _hook_state:
		HookState.IDLE:
			_check_fire_input()
		HookState.FLYING:
			_process_flying(delta)
		HookState.ATTACHED:
			if _release_requested():
				detach()
		HookState.RETURNING:
			_process_returning(delta)
			_check_fire_input()


# ---------------------------------------------------------------------------
# API para el estado Swing
# ---------------------------------------------------------------------------

func detach() -> void:
	if not is_attached:
		return
	is_attached = false
	# El gancho regresa al lanzador desde el punto donde estaba clavado.
	_hook_pos = points[0]
	_hook_state = HookState.RETURNING
	points.clear()
	_wrap_signs.clear()
	_cooldown_timer = fire_cooldown
	queue_redraw()
	rope_detached.emit()


## Pide un salto desde la cuerda. Devuelve true si se puede: en el suelo siempre;
## en el aire solo mientras queden saltos (y entonces gasta uno).
func consume_rope_jump() -> bool:
	if _player.is_on_floor():
		return true
	if rope_jumps_left <= 0:
		return false
	rope_jumps_left -= 1
	return true


## Punto de apoyo actual: el centro del péndulo (el gancho o la última esquina).
func get_pivot() -> Vector2:
	return points[points.size() - 1]


## Largo de los tramos ya "fijos" (del gancho hasta la última esquina).
func get_fixed_length() -> float:
	var total := 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	return total


## Largo disponible para el último tramo, el que cuelga hasta el Player (radio del péndulo).
func get_free_length() -> float:
	return maxf(rope_length - get_fixed_length(), min_length)


## Cambia el largo de la cuerda: valores negativos la retraen, positivos la sueltan.
func reel(amount: float) -> void:
	var lower := get_fixed_length() + min_length
	rope_length = clampf(rope_length + amount, lower, maxf(max_rope_length, lower))


## Dobla o estira la cuerda según el escenario. Se llama una vez por frame desde Swing.
## Si un frame no se puede resolver, la cuerda se mantiene y se reintenta en el siguiente
## (desde la última posición donde estaba bien). Solo se corta si pasa más de max_unresolved_time.
func update_rope() -> void:
	if not is_attached:
		return

	var hand := global_position
	var resolved := true

	if _unwrap(hand):
		# Si se desenrolló alguna esquina, el extremo ya está verificado y no hace falta barrer.
		_prev_hand = hand
	else:
		resolved = _wrap_sweep(hand)

	if resolved:
		_unresolved_time = 0.0
		return

	if debug_log and is_zero_approx(_unresolved_time):
		print("Grapple: no se pudo doblar la cuerda (%s). pivote=%s mano=%s" % [_failure, get_pivot(), hand])
	_unresolved_time += get_physics_process_delta_time()
	if max_unresolved_time > 0.0 and _unresolved_time >= max_unresolved_time:
		detach() # último recurso


# ---------------------------------------------------------------------------
# Disparo: el gancho viaja desde el lanzador
# ---------------------------------------------------------------------------

func _check_fire_input() -> void:
	var requested := Input.is_action_just_pressed(grapple_action) or _buffer_timer > 0.0
	if not requested:
		return

	# En modo mantener, si ya soltaste el botón el disparo se cancelaría al instante: se descarta.
	if not toggle_mode and not Input.is_action_pressed(grapple_action):
		_buffer_timer = 0.0
		return

	if _try_fire():
		_buffer_timer = 0.0


## Soltar el botón (o volver a hacer clic en modo toggle).
func _release_requested() -> bool:
	if toggle_mode:
		var clicked := Input.is_action_just_pressed(grapple_action)
		if clicked:
			_buffer_timer = 0.0 # ese clic se usa para soltar o cancelar, no para disparar de nuevo
		return clicked
	return not Input.is_action_pressed(grapple_action)


func _can_use_hook() -> bool:
	if _player.is_dead:
		return false
	var current := _player.state_machine.current_state
	return current != null and grapple_allowed_from.has(current.name)


func _try_fire() -> bool:
	if _cooldown_timer > 0.0 or not _can_use_hook():
		return false

	var origin := global_position
	var mouse := get_global_mouse_position()
	var direction := (mouse - origin).normalized()
	if direction.is_zero_approx():
		return false
	direction = _assisted_direction(origin, mouse, direction)

	# La dirección se fija al disparar; el gancho viaja en línea recta desde el lanzador.
	_hook_pos = origin
	_hook_dir = direction
	_hook_state = HookState.FLYING
	hook_fired.emit(direction)
	return true


## Asistencia de puntería: si donde apuntas no hay una superficie que enganchar, busca con un
## abanico de rayos la más cercana al cursor (dentro de aim_assist_radius) y dirige el gancho hacia
## ella. Si el rayo exacto ya toca algo cerca de donde apuntas, se respeta tal cual.
func _assisted_direction(origin: Vector2, mouse: Vector2, direction: Vector2) -> Vector2:
	if aim_assist_radius <= 0.0:
		return direction

	var mouse_distance := maxf(origin.distance_to(mouse), 1.0)

	# El rayo exacto ya toca algo (como mucho 2 radios más allá del cursor): se respeta.
	var exact := _raycast(origin, origin + direction * max_rope_length)
	if not exact.is_empty():
		var exact_position: Vector2 = exact.position
		if origin.distance_to(exact_position) <= mouse_distance + 2.0 * aim_assist_radius:
			return direction

	# Si no, se busca la superficie más cercana al cursor. El abanico es más ancho cuanto más
	# cerca esté el cursor, para que la tolerancia sea parecida (en px) a cualquier distancia.
	var spread := minf(atan(aim_assist_radius / mouse_distance), deg_to_rad(aim_assist_max_angle))
	var best_direction := direction
	var best_distance := aim_assist_radius

	for i in range(-AIM_ASSIST_RAYS, AIM_ASSIST_RAYS + 1):
		var candidate := direction.rotated(spread * float(i) / float(AIM_ASSIST_RAYS))
		var hit := _raycast(origin, origin + candidate * max_rope_length)
		if hit.is_empty():
			continue
		var hit_position: Vector2 = hit.position
		if origin.distance_to(hit_position) < min_attach_distance:
			continue
		var distance_to_cursor := mouse.distance_to(hit_position)
		if distance_to_cursor <= best_distance:
			best_distance = distance_to_cursor
			best_direction = (hit_position - origin).normalized()

	return best_direction


func _process_flying(delta: float) -> void:
	# Cancelar: soltar el botón, o un estado que no permite el gancho (golpe, dash, muerte...).
	if _release_requested() or not _can_use_hook():
		_start_returning()
		return

	# Cada frame se revisa el tramo recorrido con un raycast: así nunca atraviesa paredes finas.
	var next_pos := _hook_pos + _hook_dir * hook_speed * delta
	var hit := _raycast(_hook_pos, next_pos)
	if not hit.is_empty():
		if global_position.distance_to(hit.position) < min_attach_distance:
			_start_returning()
			rope_missed.emit()
		else:
			_attach(hit.position + hit.normal * wrap_offset)
		return

	_hook_pos = next_pos
	if global_position.distance_to(_hook_pos) >= max_rope_length:
		_start_returning()
		rope_missed.emit()


func _process_returning(delta: float) -> void:
	var hand := global_position
	var step := hook_return_speed * delta
	if _hook_pos.distance_to(hand) <= step:
		_hook_state = HookState.IDLE
		queue_redraw()
		return
	_hook_pos += (hand - _hook_pos).normalized() * step


func _start_returning() -> void:
	_hook_state = HookState.RETURNING
	_cooldown_timer = fire_cooldown


## El gancho llegó a una superficie: la cuerda queda tensa y empieza el balanceo.
func _attach(anchor: Vector2) -> void:
	var hand := global_position

	# Si desde la mano actual no se ve el anclaje (te moviste mientras el gancho volaba), se descarta.
	if not _raycast(anchor, hand).is_empty():
		_start_returning()
		rope_missed.emit()
		return

	points.clear()
	points.append(anchor)
	_wrap_signs.clear()
	_wrap_signs.append(0.0)
	rope_length = minf(hand.distance_to(anchor), max_rope_length)
	_prev_hand = hand
	_unresolved_time = 0.0
	is_attached = true
	_hook_state = HookState.ATTACHED
	rope_attached.emit(anchor)
	_player.state_machine.transition_to("Swing")


# ---------------------------------------------------------------------------
# Cuerda que se dobla
# ---------------------------------------------------------------------------

## Revisa el movimiento de la mano en pasos pequeños (y no solo su posición final) para no
## "saltarse" esquinas cuando el personaje se mueve rápido. Si el tramo libre choca con el
## escenario, agrega esquinas. Devuelve false si no pudo resolverlo del todo; en ese caso
## recuerda hasta dónde la cuerda quedó bien, para reintentarlo en el siguiente frame.
func _wrap_sweep(hand: Vector2) -> bool:
	var steps := clampi(ceili(_prev_hand.distance_to(hand) / SWEEP_STEP), 1, MAX_SWEEP_STEPS)
	var start := _prev_hand
	var clear := start

	for step in range(1, steps + 1):
		var target := start.lerp(hand, float(step) / float(steps))
		var wraps := 0

		while not _raycast(get_pivot(), target).is_empty():
			var corner := {}
			if wraps < MAX_WRAPS_PER_STEP:
				corner = _find_corner(get_pivot(), clear, target)
			else:
				_failure = "demasiadas esquinas en un solo paso"
			if corner.is_empty():
				_prev_hand = clear
				return false
			_add_corner(corner.position, target, hand)
			clear = corner.clear
			wraps += 1

		clear = target

	_prev_hand = hand
	return true


func _add_corner(corner: Vector2, target: Vector2, hand: Vector2) -> void:
	var pivot := get_pivot()
	# Hacia qué lado gira la cuerda en esta esquina (se usa para saber cuándo se desenrolla).
	var side := signf((corner - pivot).cross(target - corner))
	if is_zero_approx(side):
		side = signf((corner - pivot).cross(hand - corner))
	points.append(corner)
	_wrap_signs.append(side if not is_zero_approx(side) else 1.0)


## Quita las esquinas cuando el Player vuelve al otro lado de ellas y el camino directo desde
## el punto anterior está libre. Devuelve true si quitó alguna.
func _unwrap(hand: Vector2) -> bool:
	var removed := false
	while points.size() > 1:
		var last := points.size() - 1
		var previous := points[last - 1]
		var corner := points[last]
		var side := signf((corner - previous).cross(hand - corner))

		if side * _wrap_signs[last] < -UNWRAP_EPSILON and _raycast(previous, hand).is_empty():
			points.remove_at(last)
			_wrap_signs.remove_at(last)
			removed = true
		else:
			break
	return removed


## Localiza con precisión la esquina que tocó la cuerda: entre una posición de la mano donde el
## tramo estaba libre y otra donde está bloqueado, hace una búsqueda binaria del punto exacto en
## que el rayo empieza a chocar. Ese impacto cae justo sobre la esquina.
## Devuelve {} si no es posible (la referencia no estaba libre o no hay avance real).
func _find_corner(pivot: Vector2, clear_pos: Vector2, blocked_pos: Vector2) -> Dictionary:
	if not _raycast(pivot, clear_pos).is_empty():
		_failure = "la posición de referencia no estaba libre"
		return {}

	var low := clear_pos
	var high := blocked_pos
	for _i in BISECT_STEPS:
		var middle := low.lerp(high, 0.5)
		if _raycast(pivot, middle).is_empty():
			low = middle
		else:
			high = middle

	var hit := _raycast(pivot, high)
	if hit.is_empty():
		_failure = "no se encontró el punto de impacto"
		return {}

	var vertex: Vector2 = hit.position
	var corner := _corner_point(vertex, hit.normal, pivot, high)
	# Si el punto quedó fuera de la vista del pivote, se acerca al pivote.
	if not _raycast(pivot, corner).is_empty():
		corner = vertex + (pivot - vertex).normalized() * wrap_offset
	# Sin avance real (la "esquina" es el propio pivote): no se puede resolver este frame.
	if corner.distance_to(pivot) < MIN_SEGMENT_LENGTH:
		_failure = "la esquina coincide con el pivote (sin avance)"
		return {}

	return {"position": corner, "clear": low}


## Punto de apoyo junto a la esquina, separado de ella hacia el lado libre (fuera de las dos caras).
## Así la cuerda puede recorrer una cara y luego la siguiente girando alrededor del punto, sin
## volver a tocar el mismo vértice, por ejemplo al bajar por el borde de una plataforma.
func _corner_point(vertex: Vector2, normal: Vector2, pivot: Vector2, target: Vector2) -> Vector2:
	# Lo ideal: la dirección exterior real de la esquina (la diagonal en una esquina de 90°).
	var outward := _corner_normal(vertex)

	# Si no se pudo determinar, se usa la bisectriz del ángulo de la cuerda o la normal de la pared.
	if outward.is_zero_approx():
		outward = -((pivot - vertex).normalized() + (target - vertex).normalized())
		if outward.length() < 0.2 or (not normal.is_zero_approx() and outward.dot(normal) <= 0.0):
			outward = normal

	if outward.is_zero_approx():
		return vertex
	return vertex + outward.normalized() * wrap_offset


## Dirección que sale de la esquina hacia el lado libre. Se sondean puntos en círculo alrededor
## del vértice y se promedian las direcciones de los que NO están dentro de un sólido: en una
## esquina de 90° apunta a la diagonal exterior; en una pared recta, a su normal.
## Devuelve Vector2.ZERO si no hay una dirección clara (todo aire, todo sólido o simétrico).
func _corner_normal(vertex: Vector2) -> Vector2:
	var query := PhysicsPointQueryParameters2D.new()
	query.collision_mask = rope_collision_mask
	query.exclude = [_player.get_rid()]
	var space := get_world_2d().direct_space_state

	var sum := Vector2.ZERO
	var free := 0
	for i in CORNER_PROBES:
		var direction := Vector2.from_angle(TAU * float(i) / float(CORNER_PROBES))
		query.position = vertex + direction * CORNER_PROBE_RADIUS
		if space.intersect_point(query, 1).is_empty():
			sum += direction
			free += 1

	if free == 0 or free == CORNER_PROBES or sum.length() < 0.1 * float(CORNER_PROBES):
		return Vector2.ZERO
	return sum.normalized()


func _raycast(origin: Vector2, target: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(origin, target, rope_collision_mask)
	query.exclude = [_player.get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(query)


# ---------------------------------------------------------------------------
# Dibujo (provisional: puedes reemplazarlo por un Line2D o sprites)
# ---------------------------------------------------------------------------

func _draw() -> void:
	match _hook_state:
		HookState.ATTACHED:
			if points.is_empty():
				return
			var line := PackedVector2Array()
			for point in points:
				line.append(to_local(point))
			line.append(Vector2.ZERO) # la mano (origen de este nodo)
			draw_polyline(line, rope_color, rope_width)
			draw_circle(to_local(points[0]), 2.0, rope_color)
			if debug_draw:
				for i in range(1, points.size()):
					draw_circle(to_local(points[i]), 3.0, Color.YELLOW)
				if _unresolved_time > 0.0:
					draw_line(to_local(get_pivot()), Vector2.ZERO, Color.RED, 2.0)
		HookState.FLYING, HookState.RETURNING:
			# Mientras viaja, la cuerda va del lanzador a la punta del gancho.
			var tip := to_local(_hook_pos)
			draw_line(Vector2.ZERO, tip, rope_color, rope_width)
			draw_circle(tip, 2.0, rope_color)
