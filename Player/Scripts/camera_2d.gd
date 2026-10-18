class_name MouseCamera
extends Camera2D
## Cámara que sigue al jugador (colócala como hijo del Player) y se desplaza un poco
## hacia donde apunta el mouse: izquierda, derecha, arriba o abajo.

## Desplazamiento máximo (px) cuando el mouse está en el borde de la pantalla.
@export var max_look_offset: Vector2 = Vector2(48, 32)
## Zona central de la pantalla (0 a 1) en la que el mouse no mueve la cámara.
@export_range(0.0, 0.9) var dead_zone: float = 0.1
## Qué tan rápido alcanza el desplazamiento objetivo (más alto = más reactiva).
@export var look_smoothing: float = 6.0
## Desactívalo para fijar la cámara sobre el jugador (cinemáticas, menús, etc.).
@export var mouse_look_enabled: bool = true


func _ready() -> void:
	# El jugador se mueve en _physics_process; la cámara se actualiza igual para evitar temblores.
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS


func _physics_process(delta: float) -> void:
	var target_offset := Vector2.ZERO
	if mouse_look_enabled:
		target_offset = _get_mouse_offset()
	# Suavizado exponencial: se comporta igual sin importar los FPS.
	offset = offset.lerp(target_offset, 1.0 - exp(-look_smoothing * delta))


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
