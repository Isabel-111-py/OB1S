class_name MonkeyCompanion
extends Sprite2D
## El mono que va encima del jugador. Elige su pose según lo que haga el jugador:
##   - Paraguas equipado  -> sostiene el paraguas (brazos arriba).
##   - Cargando el arco   -> apunta con el arco.
##   - Acaba de disparar  -> pose de disparo durante un instante.
##   - Cualquier otra cosa -> idle.
## También se voltea hacia donde mira el jugador. El balanceo (posición) lo siguen haciendo las
## animaciones del AnimationPlayer; este script solo cambia el frame y la orientación.
##
## Uso: selecciona el nodo "Mono" en player.tscn y adjúntale este script (Adjuntar script > Cargar).
## Los números de frame cuentan desde 0 de izquierda a derecha y de arriba a abajo en el spritesheet.

## Jugador al que acompaña. Si lo dejas vacío usa el padre.
@export var player: Player
## Arco del jugador. Si lo dejas vacío busca el nodo hijo "Bow" del jugador.
@export var bow: Bow

@export_group("Idle")
@export var idle_frames: PackedInt32Array = PackedInt32Array([11])
@export var idle_fps: float = 6.0

@export_group("Apuntando (cargando el arco)")
@export var aim_frames: PackedInt32Array = PackedInt32Array([9])
@export var aim_fps: float = 6.0

@export_group("Disparo")
## Pose justo después de soltar la flecha.
@export var shoot_frames: PackedInt32Array = PackedInt32Array([10])
@export var shoot_fps: float = 6.0
## Segundos que dura la pose de disparo.
@export var shoot_pose_time: float = 0.25

@export_group("Paraguas")
@export var umbrella_frames: PackedInt32Array = PackedInt32Array([8])
@export var umbrella_fps: float = 3.0

enum Pose { IDLE, AIM, SHOOT, UMBRELLA }

var _pose: Pose = Pose.IDLE
var _pose_time: float = 0.0
var _shoot_timer: float = 0.0


func _ready() -> void:
	if player == null:
		player = get_parent() as Player
	if bow == null and player:
		bow = player.get_node_or_null("Bow") as Bow
	if bow:
		bow.arrow_fired.connect(_on_arrow_fired)
	_apply_frame()


func _process(delta: float) -> void:
	_shoot_timer = maxf(_shoot_timer - delta, 0.0)

	var new_pose := _choose_pose()
	if new_pose != _pose:
		_pose = new_pose
		_pose_time = 0.0
	else:
		_pose_time += delta

	_apply_frame()
	if player:
		flip_h = player.facing < 0.0


func _on_arrow_fired(_ratio: float) -> void:
	_shoot_timer = shoot_pose_time


func _choose_pose() -> Pose:
	if Inventory.umbrella_equipped:
		return Pose.UMBRELLA
	if bow and bow.is_charging:
		return Pose.AIM
	if _shoot_timer > 0.0:
		return Pose.SHOOT
	return Pose.IDLE


func _apply_frame() -> void:
	var frames := idle_frames
	var fps := idle_fps
	match _pose:
		Pose.AIM:
			frames = aim_frames
			fps = aim_fps
		Pose.SHOOT:
			frames = shoot_frames
			fps = shoot_fps
		Pose.UMBRELLA:
			frames = umbrella_frames
			fps = umbrella_fps
	if frames.is_empty():
		return
	frame = frames[int(_pose_time * fps) % frames.size()]
