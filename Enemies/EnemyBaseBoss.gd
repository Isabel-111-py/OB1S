class_name EnemyBaseBoss
extends CharacterBody2D

enum BTState { SUCCESS, FAILURE, RUNNING }

@export_group("Estadísticas")
@export var max_health: int = 100
@export var attack_range: float = 140.0
@export var chase_speed: float = 200.0

var target_player: Node2D = null
var current_target: Node2D = null
var nearby_npcs: Array[Node2D] = []

var is_awake: bool = false
var current_health: int
var is_dead: bool = false
var _has_dealt_attack_damage: bool = false

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var detection_zone: Area2D = $DetectionZone
@onready var hitbox: Area2D = get_node_or_null("hitbox")

var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("boss")
	current_health = max_health
	if detection_zone:
		detection_zone.collision_mask |= 1 | 2


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	if is_dead:
		move_and_slide()
		return

	_update_nearby_npcs()
	_update_current_target()
	_run_behavior_tree(delta)
	_update_facing()

	move_and_slide()


# ==============================================================================
# Detección y Priorización de Objetivos (NPCs vs Jugador)
# ==============================================================================

func _is_npc_target(node: Node2D) -> bool:
	if node == null or not is_instance_valid(node) or node == self:
		return false
	if node.is_in_group("boss") or node.is_in_group("enemies"):
		return false
	if node.is_in_group("npcs") or node is NPCBase or node.name.to_lower().begins_with("mico"):
		if node.get("is_dead") == true:
			return false
		return true
	return false


func _update_nearby_npcs() -> void:
	# 1. Limpiar NPCs de la lista que hayan muerto o ya no sean válidos
	var cleaned: Array[Node2D] = []
	for npc in nearby_npcs:
		if _is_npc_target(npc):
			cleaned.append(npc)
	nearby_npcs = cleaned

	# 2. Consultar cuerpos en DetectionZone para capturar cualquier NPC presente
	if is_instance_valid(detection_zone):
		for body in detection_zone.get_overlapping_bodies():
			if body is Node2D and _is_npc_target(body):
				if not nearby_npcs.has(body):
					nearby_npcs.append(body)


func _update_current_target() -> void:
	# REGLA FUNDAMENTAL:
	# Cuando el Boss detecta a los NPC, inmediatamente prioriza el ataque hacia ellos
	# y deja de perseguir e intentar atacar al jugador.
	if nearby_npcs.size() > 0:
		var closest: Node2D = null
		var min_dist: float = INF
		for npc in nearby_npcs:
			if _is_npc_target(npc):
				var d := global_position.distance_to(npc.global_position)
				if d < min_dist:
					min_dist = d
					closest = npc
		current_target = closest
	else:
		# Si no hay NPCs detectados o todos han muerto, enfoca al jugador
		if is_instance_valid(target_player):
			current_target = target_player
		else:
			current_target = null


# ==============================================================================
# BTSelector (Raíz)
# ==============================================================================

func _run_behavior_tree(delta: float) -> void:
	# Rama 1: Atacar si el objetivo prioritario está en rango
	if _sequence_attack(delta) != BTState.FAILURE:
		return
		
	# Rama 2: Despertar + Perseguir si ve al objetivo prioritario
	if _sequence_chase(delta) != BTState.FAILURE:
		return
		
	# Rama 3 por defecto: Standby / Quieto si no hay objetivos
	_action_standby(delta)


# ==============================================================================
# Ramas (BTSequence)
# ==============================================================================

func _sequence_attack(delta: float) -> int:
	if not is_instance_valid(current_target):
		return BTState.FAILURE
	if not is_awake:
		return BTState.FAILURE
	if _condition_target_in_range() == BTState.FAILURE:
		return BTState.FAILURE
		
	return _action_attack_2d(delta)


func _sequence_chase(delta: float) -> int:
	if not is_instance_valid(current_target):
		return BTState.FAILURE
		
	# Si está dormido, activamos el despertar primero
	if not is_awake:
		return _action_wake_up(delta)
		
	return _action_chase_2d(delta)


# ==============================================================================
# Condiciones (BTCondition)
# ==============================================================================

func _condition_target_in_range() -> int:
	if is_instance_valid(current_target) and global_position.distance_to(current_target.global_position) <= attack_range:
		return BTState.SUCCESS
	return BTState.FAILURE


func _condition_can_see_player() -> int:
	if is_instance_valid(current_target):
		return BTState.SUCCESS
	return BTState.FAILURE


# ==============================================================================
# Acciones (BTAction)
# ==============================================================================

@warning_ignore("unused_parameter")
func _action_attack_2d(delta: float) -> int:
	velocity.x = 0
	
	if anim_sprite.animation != "attack":
		anim_sprite.play("attack")
		_has_dealt_attack_damage = false
	
	# Ejecutar impacto y muerte de NPCs en los frames de ataque
	if anim_sprite.frame >= 2 and not _has_dealt_attack_damage:
		_has_dealt_attack_damage = true
		_apply_attack_to_targets()
	elif anim_sprite.frame == 0:
		# Se reinicia para el siguiente golpe si continúa atacando
		_has_dealt_attack_damage = false
	
	return BTState.RUNNING


func _apply_attack_to_targets() -> void:
	# 1. Si el objetivo prioritario actual es un NPC, dañarlo inmediatamente
	if is_instance_valid(current_target) and _is_npc_target(current_target):
		var dist := global_position.distance_to(current_target.global_position)
		if dist <= attack_range * 1.5:
			_hit_npc(current_target)

	# 2. Golpear a cualquier otro NPC vivo dentro del área de ataque
	for npc in nearby_npcs:
		if is_instance_valid(npc) and _is_npc_target(npc):
			var dist := global_position.distance_to(npc.global_position)
			if dist <= attack_range * 1.3:
				_hit_npc(npc)


func _hit_npc(npc: Node2D) -> void:
	if npc == null or not is_instance_valid(npc):
		return
	if npc.get("is_dead") == true:
		return
	
	if npc.has_method("die"):
		npc.die()
	elif npc.has_method("take_damage"):
		npc.take_damage(1, Vector2.ZERO)
	else:
		npc.set("is_dead", true)
		var sp = npc.get_node_or_null("AnimatedSprite2D")
		if sp and sp.sprite_frames and sp.sprite_frames.has_animation("die"):
			sp.play("die")


@warning_ignore("unused_parameter")
func _action_wake_up(delta: float) -> int:
	velocity.x = 0
	
	if anim_sprite.animation != "wake_up":
		anim_sprite.play("wake_up")
	
	var total_frames = anim_sprite.sprite_frames.get_frame_count("wake_up")
	if anim_sprite.frame >= total_frames - 1:
		is_awake = true
		return BTState.SUCCESS
		
	return BTState.RUNNING


func _on_wake_up_finished() -> void:
	if anim_sprite.animation == "wake_up":
		is_awake = true
		if anim_sprite.animation_finished.is_connected(_on_wake_up_finished):
			anim_sprite.animation_finished.disconnect(_on_wake_up_finished)


@warning_ignore("unused_parameter")
func _action_chase_2d(delta: float) -> int:
	if not is_instance_valid(current_target):
		return BTState.FAILURE

	_has_dealt_attack_damage = false
	var direction := global_position.direction_to(current_target.global_position)
	velocity.x = signf(direction.x) * chase_speed
	anim_sprite.play("run")
	return BTState.RUNNING


@warning_ignore("unused_parameter")
func _action_standby(delta: float) -> int:
	velocity.x = 0
	is_awake = false
	anim_sprite.play("idle")
	return BTState.RUNNING


# ==============================================================================
# Sensores
# ==============================================================================

func _on_detection_zone_body_entered(body: Node2D) -> void:
	if body == self:
		return
	if _is_npc_target(body):
		if not nearby_npcs.has(body):
			nearby_npcs.append(body)
		_update_current_target()
	elif body.is_in_group("player"):
		target_player = body
		_update_current_target()


func _on_detection_zone_body_exited(body: Node2D) -> void:
	if nearby_npcs.has(body):
		nearby_npcs.erase(body)
		_update_current_target()
	if body == target_player:
		target_player = null
		_update_current_target()


# ==============================================================================
# Utilidades
# ==============================================================================

func _update_facing() -> void:
	# Orientar el sprite hacia el objetivo actual si está quieto atacando o moviéndose
	if is_instance_valid(current_target) and absf(current_target.global_position.x - global_position.x) > 5.0:
		if current_target.global_position.x < global_position.x:
			anim_sprite.flip_h = false
		else:
			anim_sprite.flip_h = true
	elif velocity.x < 0:
		anim_sprite.flip_h = false
	elif velocity.x > 0:
		anim_sprite.flip_h = true


# ==============================================================================
# SALUD Y DAÑO
# ==============================================================================

func take_damage(amount: int, knockback: Vector2 = Vector2.ZERO) -> void:
	if is_dead:
		return
		
	current_health -= amount
	if knockback != Vector2.ZERO:
		velocity += knockback
	
	if current_health <= 0:
		die()


func die() -> void:
	is_dead = true
	velocity.x = 0
	queue_free()


func _on_area_2d_body_entered(_body: Node2D) -> void:
	pass


func _on_area_2d_body_exited(_body: Node2D) -> void:
	pass
