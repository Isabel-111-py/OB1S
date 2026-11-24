class_name NPCBase
extends CharacterBody2D

# --- Propiedades personalizables en el Inspector ---
@export_group("Movimiento")
@export var speed: float = 40.0
@export var gravity: float = 980.0
@export var patrol_radius: float = 80.0 # Distancia máxima en píxeles desde donde aparece

@export_group("Tiempos de Comportamiento")
@export var min_idle_time: float = 1.0
@export var max_idle_time: float = 3.0
@export var min_walk_time: float = 1.5
@export var max_walk_time: float = 3.5

@export_group("Visual")
@export var sprite_faces_right: bool = true # Desmarca si tu sprite original mira a la izquierda

# --- Referencias y Estado interno ---
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

enum NPCState { IDLE, WALK }
var current_state: NPCState = NPCState.IDLE
var start_position: Vector2
var direction: int = 1 # 1 = derecha, -1 = izquierda
var state_timer: float = 0.0

func _ready() -> void:
	# Guardamos la coordenada exacta donde pusiste al NPC en el nivel
	start_position = global_position
	_enter_idle_state()

func _physics_process(delta: float) -> void:
	# 1. Aplicar gravedad
	if not is_on_floor():
		velocity.y += gravity * delta

	# 2. Actualizar temporizador del estado actual
	state_timer -= delta
	if state_timer <= 0:
		_choose_next_state()

	# 3. Ejecutar lógica del estado
	match current_state:
		NPCState.IDLE:
			velocity.x = move_toward(velocity.x, 0, speed)
		NPCState.WALK:
			_handle_patrol_limits()
			velocity.x = direction * speed
			_update_sprite_flip()

	move_and_slide()

func _choose_next_state() -> void:
	if current_state == NPCState.IDLE:
		_enter_walk_state()
	else:
		_enter_idle_state()

func _enter_idle_state() -> void:
	current_state = NPCState.IDLE
	state_timer = randf_range(min_idle_time, max_idle_time)
	anim.play("idle")

func _enter_walk_state() -> void:
	current_state = NPCState.WALK
	state_timer = randf_range(min_walk_time, max_walk_time)
	# Elige aleatoriamente caminar a la izquierda (-1) o derecha (1)
	direction = [-1, 1].pick_random()
	anim.play("walk")

func _handle_patrol_limits() -> void:
	# Si choca contra una pared, da la vuelta
	if is_on_wall():
		direction *= -1
		return

	# Si se pasa del radio permitido a la derecha, vuelve a la izquierda
	if global_position.x > start_position.x + patrol_radius:
		direction = -1
	# Si se pasa del radio permitido a la izquierda, vuelve a la derecha
	elif global_position.x < start_position.x - patrol_radius:
		direction = 1

func _update_sprite_flip() -> void:
	if sprite_faces_right:
		anim.flip_h = (direction < 0)
	else:
		anim.flip_h = (direction > 0)
