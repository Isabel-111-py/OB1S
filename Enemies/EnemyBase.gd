class_name EnemyBase
extends CharacterBody2D

enum BTState { SUCCESS, FAILURE, RUNNING }

@export_group("Estadísticas")
@export var max_health: int = 3
@export var attack_range: float = 40.0
@export var chase_speed: float = 120.0

var target_player: Node2D = null
var is_awake: bool = false # Controla si el enemigo ya terminó su animación de despertar
var current_health: int      # <--- NUEVO
var is_dead: bool = false    # <--- NUEVO para saber si debe detenerse
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var detection_zone: Area2D = $DetectionZone

func _ready() -> void:
	current_health = max_health
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
func _physics_process(delta: float) -> void:
		if not is_on_floor():
			velocity.y += gravity * delta
		if is_dead:
			move_and_slide()
			return
		_run_behavior_tree(delta)
		_update_facing()
	
		move_and_slide()
	
	
# ==============================================================================
# BTSelector (Raíz)
# ==============================================================================
func _run_behavior_tree(delta: float) -> void:
	# Rama 1: Atacar si está muy cerca
	if _sequence_attack(delta) != BTState.FAILURE:
		return
		
	# Rama 2: Despertar + Perseguir si ve al jugador
	if _sequence_chase(delta) != BTState.FAILURE:
		return
		
	# Rama 3 por defecto: Durmiendo/Quieto
	_action_standby(delta)


# ==============================================================================
# Ramas (BTSequence)
# ==============================================================================
func _sequence_attack(delta: float) -> int:
	if _condition_target_in_range() == BTState.FAILURE:
		return BTState.FAILURE
		
	return _action_attack_2d(delta)

func _sequence_chase(delta: float) -> int:
	if _condition_can_see_player() == BTState.FAILURE:
		return BTState.FAILURE
		
	# ¡Volvemos a activar el despertar!
	if not is_awake:
		return _action_wake_up(delta)
		
	return _action_chase_2d(delta)


# ==============================================================================
# Condiciones (BTCondition)
# ==============================================================================
func _condition_target_in_range() -> int:
	if is_instance_valid(target_player) and global_position.distance_to(target_player.global_position) <= attack_range:
		return BTState.SUCCESS
	return BTState.FAILURE

func _condition_can_see_player() -> int:
	# AQUÍ ESTÁ LA MAGIA PARA LOS NIVELES: 
	# target_player solo se asigna si un cuerpo con el grupo "player" entra al Area2D.
	if is_instance_valid(target_player):
		return BTState.SUCCESS
	return BTState.FAILURE


# ==============================================================================
# Acciones (BTAction)
# ==============================================================================
@warning_ignore("unused_parameter")
func _action_attack_2d(delta: float) -> int:
	velocity.x = 0
	anim_sprite.play("attack")
	return BTState.RUNNING

func _action_wake_up(delta: float) -> int:
	velocity.x = 0
	
	# Solo le damos play si no estaba ya reproduciéndose
	if anim_sprite.animation != "wake_up":
		anim_sprite.play("wake_up")
	
	# Obtenemos el número total de frames de esta animación
	var total_frames = anim_sprite.sprite_frames.get_frame_count("wake_up")
	
	# Si ya llegó al último frame, terminamos la acción
	if anim_sprite.frame == total_frames - 1:
		is_awake = true
		return BTState.SUCCESS
		
	return BTState.RUNNING

# Añade esta nueva función justo debajo:
func _on_wake_up_finished() -> void:
	if anim_sprite.animation == "wake_up":
		is_awake = true
		# Desconectamos la señal para que no interfiera después
		anim_sprite.animation_finished.disconnect(_on_wake_up_finished)

@warning_ignore("unused_parameter")
func _action_chase_2d(delta: float) -> int:
	var direction := global_position.direction_to(target_player.global_position)
	velocity.x = sign(direction.x) * chase_speed
	anim_sprite.play("run")
	print("Velocidad X: ", velocity.x)
	return BTState.RUNNING

@warning_ignore("unused_parameter")
func _action_standby(delta: float) -> int:
	velocity.x = 0
	is_awake = false # Si el jugador escapa, se vuelve a dormir
	anim_sprite.play("idle") # O "sleep"
	return BTState.RUNNING


# ==============================================================================
# Sensores (Solución para instanciamiento en múltiples niveles/biomas)
# ==============================================================================
func _on_detection_zone_body_entered(body: Node2D) -> void:
	print("Algo entró: ", body.name) # <-- Añade esto
	if body.is_in_group("player"):
		print("¡ES EL JUGADOR! Activando persecución.") # <-- Añade esto
		target_player = body
func _on_detection_zone_body_exited(body: Node2D) -> void:
	if body == target_player:
		target_player = null

# ==============================================================================
# Utilidades
# ==============================================================================
func _update_facing() -> void:
	if velocity.x > 0:
		anim_sprite.flip_h = false
	elif velocity.x < 0:
		anim_sprite.flip_h = true
# ==============================================================================
# SALUD Y DAÑO
# ==============================================================================

func take_damage(amount: int) -> void:
	if is_dead:
		return # Si ya está muerto, ignorar
		
	current_health -= amount
	print("Enemigo recibió daño. Vida restante: ", current_health)
	
	if current_health <= 0:
		die()

func die() -> void:
	is_dead = true
	velocity.x = 0 # Detenemos su movimiento horizontal
	
	# OPCIÓN 1: Si TIENES animación de muerte:
	# anim_sprite.play("die")
	# await anim_sprite.animation_finished # Espera a que termine la animación
	# queue_free() # Destruye el nodo del enemigo
	
	# OPCIÓN 2: Si NO tienes animación de muerte, lo destruimos de inmediato:
	queue_free()
