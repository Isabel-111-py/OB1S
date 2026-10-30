class_name Level
extends Node2D
## Script raíz de cada nivel. Avisa al SceneManager y vigila la caída al vacío.

## Punto de aparición si se entra al nivel sin indicar spawn (ver SpawnPoint).
@export var default_spawn: StringName = &"default"
## Si el jugador baja de esta Y (coordenadas globales), cuenta como caída al vacío.
## Ponla unos píxeles por debajo de la parte más baja del nivel.
@export var fall_limit_y: float = 100000000.0

@export_group("Límites de cámara")
@export var use_camera_limits: bool = false
## Área visible del nivel en píxeles: posición (x, y) y tamaño (ancho, alto).
@export var camera_limits: Rect2i = Rect2i(0, 0, 1920, 1080)


func _ready() -> void:
	SceneManager.on_level_ready(self)


func _physics_process(_delta: float) -> void:
	var player := SceneManager.player
	if is_instance_valid(player) and not player.is_dead and player.global_position.y > fall_limit_y:
		SceneManager.void_fall()


func apply_camera_limits(camera: Camera2D) -> void:
	if camera == null or not use_camera_limits:
		return
	camera.limit_left = camera_limits.position.x
	camera.limit_top = camera_limits.position.y
	camera.limit_right = camera_limits.end.x
	camera.limit_bottom = camera_limits.end.y
