class_name MouseCamera
extends Camera2D
## Cámara que sigue al jugador (colócala como hijo del Player) y se desplaza un poco
## hacia donde apunta el mouse: izquierda, derecha, arriba o abajo.
##
## En vertical NO sigue cada salto: el jugador puede subir o bajar hasta una "zona muerta" sin que
## la cámara se mueva, y solo la sigue cuando se aleja mucho de ella. Con el jugador en el suelo,
## la cámara vuelve poco a poco a centrarse en él.

@export_group("Mouse")
## Desplazamiento máximo (px) cuando el mouse está en el borde de la pantalla.
@export var max_look_offset: Vector2 = Vector2(48, 32)
## Zona central de la pantalla (0 a 1) en la que el mouse no mueve la cámara.
@export_range(0.0, 0.9) var dead_zone: float = 0.1
## Qué tan rápido alcanza el desplazamiento objetivo (más alto = más reactiva).
@export var look_smoothing: float = 6.0
## Desactívalo para fijar la cámara sobre el jugador (cinemáticas, menús, etc.).
@export var mouse_look_enabled: bool = true

@export_group("Seguimiento vertical")
## Cuánto (px) puede subir el jugador desde el centro de la cámara antes de que esta empiece a subir.
@export var vertical_dead_zone_up: float = 90.0
## Lo mismo hacia abajo (caídas).
@export var vertical_dead_zone_down: float = 60.0
## Qué tan rápido alcanza la cámara el borde de la zona muerta cuando el jugador se sale de ella
## (más alto = más pegada al jugador; 0 = sin suavizado, la sigue de golpe).
@export var vertical_follow_smoothing: float = 10.0
## Con el jugador en el suelo, la cámara vuelve a centrarse en él a esta velocidad (por ejemplo,
## al aterrizar en una plataforma más alta). 0 = nunca se recentra.
@export var ground_recenter_smoothing: float = 3.0

var _target: CharacterBody2D
var _follow_offset: Vector2 = Vector2.ZERO
var _base: Vector2 = Vector2.ZERO


func _ready() -> void:
	# El jugador se mueve en _physics_process; la cámara se actualiza igual para evitar temblores,
	# y con prioridad alta para que corra DESPUÉS de que el jugador se mueva en ese mismo frame.
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	process_physics_priority = 100

	_target = get_parent() as CharacterBody2D
	if _target == null:
		push_warning("MouseCamera: debe ser hijo del Player (un CharacterBody2D) para seguirlo.")
		return

	# La cámara deja de heredar la posición del jugador para controlar ella misma el seguimiento
	# vertical. Se conserva el punto donde la colocaste respecto al jugador.
	_follow_offset = position
	top_level = true
	_base = _target.global_position + _follow_offset
	global_position = _base
	reset_smoothing()


func _physics_process(delta: float) -> void:
	if _target != null:
		_follow(delta)

	var target_offset := Vector2.ZERO
	if mouse_look_enabled:
		target_offset = _get_mouse_offset()
	# Suavizado exponencial: se comporta igual sin importar los FPS.
	offset = offset.lerp(target_offset, 1.0 - exp(-look_smoothing * delta))


func _follow(delta: float) -> void:
	var goal := _target.global_position + _follow_offset

	# Horizontal: sigue al jugador directamente.
	_base.x = goal.x

	# Vertical: el centro de la cámara debe quedar a menos de `up` px por debajo y de `down` px
	# por encima del jugador (en pantalla: el jugador puede subir `up` o bajar `down` px desde el
	# centro sin que la cámara se mueva).
	var limited := clampf(_base.y, goal.y - vertical_dead_zone_down, goal.y + vertical_dead_zone_up)
	if vertical_follow_smoothing > 0.0:
		_base.y = lerpf(_base.y, limited, 1.0 - exp(-vertical_follow_smoothing * delta))
	else:
		_base.y = limited

	# En el suelo, la cámara vuelve poco a poco a centrarse en el jugador.
	if ground_recenter_smoothing > 0.0 and _target.is_on_floor():
		_base.y = lerpf(_base.y, goal.y, 1.0 - exp(-ground_recenter_smoothing * delta))

	global_position = _base


func _get_mouse_offset() -> Vector2:
	var viewport := get_viewport()
	var half_size := viewport.get_visible_rect().size * 0.5
	# Posición del mouse respecto al centro de la pantalla: de -1 a 1 en cada eje.
	var normalized := (viewport.get_mouse_position() - half_size) / half_size
	normalized = normalized.clamp(Vector2(-1.0, -1.0), Vector2.ONE)
	return Vector2(_apply_dead_zone(normalized.x), _apply_dead_zone(normalized.y)) * max_look_offset


func _apply_dead_zone(value: float) -> float:
	var magnitude := absf(value)
	if magnitude <= dead_zone:
		return 0.0
	return signf(value) * (magnitude - dead_zone) / (1.0 - dead_zone)
