class_name NPCBase
extends CharacterBody2D

signal npc_died()

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

enum NPCState { IDLE, WALK, DEAD }
var current_state: NPCState = NPCState.IDLE
var start_position: Vector2
var direction: int = 1 # 1 = derecha, -1 = izquierda
var state_timer: float = 0.0

var is_dead: bool:
	get:
		return _get_is_dead()
	set(value):
		_set_is_dead(value)

var _is_dead_internal: bool = false


func _get_is_dead() -> bool:
	return _is_dead_internal or current_state == NPCState.DEAD


func _set_is_dead(value: bool) -> void:
	_is_dead_internal = value
	if value:
		current_state = NPCState.DEAD


func _ready() -> void:
	add_to_group("npcs")
	start_position = global_position
	if is_dead or current_state == NPCState.DEAD:
		_enter_dead_state()
	else:
		_enter_idle_state()


func _physics_process(delta: float) -> void:
	# Si está muerto, permanece completamente inmóvil en el suelo
	if is_dead or current_state == NPCState.DEAD:
		velocity.x = 0
		if not is_on_floor():
			velocity.y += gravity * delta
		move_and_slide()
		return

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


## Recibir daño: al primer ataque el NPC muere y queda inmóvil
func take_damage(_amount: int, _knockback: Vector2 = Vector2.ZERO) -> void:
	die()


## Ejecuta la muerte del NPC: reproduce la animación 'die' y se queda inmóvil
func die() -> void:
	if is_dead:
		return
	is_dead = true
	current_state = NPCState.DEAD
	velocity.x = 0
	npc_died.emit()
	
	if anim and anim.sprite_frames and anim.sprite_frames.has_animation("die"):
		anim.play("die")
		if not anim.animation_finished.is_connected(_on_die_anim_finished):
			anim.animation_finished.connect(_on_die_anim_finished)
		if not anim.animation_looped.is_connected(_on_die_anim_finished):
			anim.animation_looped.connect(_on_die_anim_finished)
	elif anim and anim.sprite_frames and anim.sprite_frames.has_animation("idle"):
		anim.play("idle")


func _on_die_anim_finished() -> void:
	if anim and anim.animation == "die":
		anim.stop()
		var count := anim.sprite_frames.get_frame_count("die")
		if count > 0:
			anim.set_frame_and_progress(count - 1, 1.0)


func _enter_dead_state() -> void:
	is_dead = true
	current_state = NPCState.DEAD
	velocity.x = 0
	if anim and anim.sprite_frames and anim.sprite_frames.has_animation("die"):
		var count := anim.sprite_frames.get_frame_count("die")
		anim.play("die")
		anim.stop()
		if count > 0:
			anim.set_frame_and_progress(count - 1, 1.0)


func _choose_next_state() -> void:
	if is_dead or current_state == NPCState.DEAD:
		return
	if current_state == NPCState.IDLE:
		_enter_walk_state()
	else:
		_enter_idle_state()


func _enter_idle_state() -> void:
	if is_dead or current_state == NPCState.DEAD:
		return
	current_state = NPCState.IDLE
	state_timer = randf_range(min_idle_time, max_idle_time)
	if anim and anim.sprite_frames and anim.sprite_frames.has_animation("idle"):
		anim.play("idle")


func _enter_walk_state() -> void:
	if is_dead or current_state == NPCState.DEAD:
		return
	current_state = NPCState.WALK
	state_timer = randf_range(min_walk_time, max_walk_time)
	direction = [-1, 1].pick_random()
	if anim and anim.sprite_frames and anim.sprite_frames.has_animation("walk"):
		anim.play("walk")


func _handle_patrol_limits() -> void:
	if is_dead:
		return
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
	if is_dead:
		return
	if anim == null:
		return
	if sprite_faces_right:
		anim.flip_h = (direction < 0)
	else:
		anim.flip_h = (direction > 0)
