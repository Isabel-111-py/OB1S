class_name DrErgot
extends NPCBase

## Controlador para DrErgot:
## 1. Gestiona su ubicación entre la entrada del nivel y su laboratorio según la misión de Munfy.
## 2. Al hablar con él en su laboratorio (entregar la noticia de la cura), inicia una transformación.
## 3. Pasa al estado enemigo mutado y comienza a atacar al jugador.

enum ErgotState {
	NPC,
	TRANSFORMING,
	ENEMY_CHASE,
	ENEMY_ATTACK,
	ENEMY_DEAD
}

@export_group("Ubicaciones de Misión")
## Posición original en la entrada del nivel (cuando la misión de Munfy no ha comenzado)
@export var entrance_position: Vector2 = Vector2(0, 341)

## Posición dentro del laboratorio al sur de la ciudad
@export var lab_position: Vector2 = Vector2(7800, 810)

## Marcador opcional en la escena para posicionar visualmente el laboratorio arrastrándolo en el editor 2D
@export var lab_marker: Node2D

## Radio de patrulla dentro del laboratorio (más contenido para espacios cerrados)
@export var lab_patrol_radius: float = 40.0

## ID de la misión de Munfy que activa el traslado de Ergot al laboratorio
@export var lab_quest_id: String = "Llevarle_a_ergot"

## Si está activo, Ergot solo aparece cuando la misión está en curso o completada
@export var only_appear_during_quest: bool = false


@export_group("Transformación y Combate Enemigo")
## Duración mínima de la transformación si la animación hace loop o tiene pocos frames
@export var transformation_duration: float = 2.0

## Salud máxima del Dr. Ergot en su forma enemiga
@export var enemy_max_health: int = 8

## Velocidad de persecución hacia el jugador
@export var enemy_chase_speed: float = 95.0

## Distancia a la que inicia el ataque cuerpo a cuerpo
@export var enemy_attack_range: float = 45.0

## Daño que inflige al golpear al jugador
@export var enemy_attack_damage: int = 1

## Tiempo de espera entre ataques
@export var enemy_attack_cooldown: float = 1.2

## Si es verdadero, el enemigo inflige daño por mero contacto además de su animación de ataque
@export var contact_damage: bool = true

## Retroceso aplicado al jugador al recibir un golpe
@export var enemy_knockback: Vector2 = Vector2(240.0, -180.0)

## Nombre del flag de evento guardado en QuestManager cuando es derrotado
@export var defeated_flag: String = "dr_ergot_defeated"


# --- Referencias y Nodos Internos ---
@onready var hitbox: Hitbox = get_node_or_null("Hitbox") as Hitbox
@onready var hurtbox: Hurtbox = get_node_or_null("Hurtbox") as Hurtbox

var ergot_state: ErgotState = ErgotState.NPC
var current_health: int = 8
var target_player: Node2D = null
var attack_timer: float = 0.0
var is_attacking: bool = false
var _default_patrol_radius: float = 80.0
var _pending_transformation: bool = false


func _ready() -> void:
	_default_patrol_radius = patrol_radius
	current_health = enemy_max_health
	super._ready()
	
	# Si ya fue derrotado anteriormente en esta partida, eliminarlo
	if QuestManager and QuestManager.has_event_flag(defeated_flag):
		queue_free()
		return
	
	# Configurar componentes de combate iniciales
	if hitbox:
		hitbox.damage = enemy_attack_damage
		hitbox.knockback = enemy_knockback
		hitbox.active = false # Desactivado mientras sea NPC
	
	if hurtbox:
		hurtbox.active = false # Invulnerable mientras sea NPC
		if not hurtbox.hit_received.is_connected(_on_hurtbox_hit_received):
			hurtbox.hit_received.connect(_on_hurtbox_hit_received)
	
	# Buscar marcador de laboratorio si no fue asignado en inspector
	if lab_marker == null and get_parent() != null:
		lab_marker = get_parent().get_node_or_null("Laboratorio_DrErgot") as Node2D
		if lab_marker == null:
			lab_marker = get_parent().get_node_or_null("LabMarker") as Node2D
	
	if lab_marker != null and is_instance_valid(lab_marker):
		lab_position = lab_marker.global_position
	
	_update_ergot_location()
	
	# Conectar con QuestManager para enterarse de misiones y entregas
	if QuestManager:
		if not QuestManager.quest_accepted.is_connected(_on_quest_status_changed):
			QuestManager.quest_accepted.connect(_on_quest_status_changed)
		if not QuestManager.quest_updated.is_connected(_on_quest_status_changed):
			QuestManager.quest_updated.connect(_on_quest_status_changed)
		if not QuestManager.quest_completed.is_connected(_on_quest_status_changed):
			QuestManager.quest_completed.connect(_on_quest_status_changed)
		if not QuestManager.quest_step_delivered.is_connected(_on_quest_step_delivered):
			QuestManager.quest_step_delivered.connect(_on_quest_step_delivered)
		
		# Si la misión ya había sido completada en una sesión previa y aún no fue derrotado,
		# iniciar directamente en forma enemiga dentro del laboratorio
		if QuestManager.is_quest_completed(lab_quest_id):
			_complete_transformation(true)


func _on_quest_status_changed(quest_id: String) -> void:
	if quest_id == lab_quest_id or QuestManager.normalize_id(quest_id) == QuestManager.normalize_id(lab_quest_id):
		_update_ergot_location()
		
		# Si la misión se completó mientras estábamos presentes en el laboratorio
		if QuestManager.is_quest_completed(lab_quest_id) and ergot_state == ErgotState.NPC:
			var in_lab := global_position.distance_to(lab_position) < 300.0
			if in_lab:
				_prepare_transformation()


func _on_quest_step_delivered(quest_id: String, target_npc: String) -> void:
	if quest_id == lab_quest_id or QuestManager.normalize_id(quest_id) == QuestManager.normalize_id(lab_quest_id):
		if target_npc == "dr_ergot" or target_npc.is_empty():
			_prepare_transformation()


func _update_ergot_location() -> void:
	if ergot_state != ErgotState.NPC:
		return
		
	if lab_marker != null and is_instance_valid(lab_marker):
		lab_position = lab_marker.global_position
	
	var in_lab := false
	if QuestManager:
		in_lab = QuestManager.is_quest_active(lab_quest_id) or \
		         QuestManager.is_quest_ready_to_turn_in(lab_quest_id) or \
		         QuestManager.is_quest_completed(lab_quest_id)
	
	if only_appear_during_quest and not in_lab:
		visible = false
		set_physics_process(false)
		collision_layer = 0
		collision_mask = 0
		for child in get_children():
			if child is Area2D:
				child.monitoring = false
				child.monitorable = false
		return
	
	visible = true
	set_physics_process(true)
	collision_layer = 1
	collision_mask = 1
	for child in get_children():
		if child is Area2D:
			child.monitoring = true
			child.monitorable = true
	
	if in_lab:
		global_position = lab_position
		start_position = lab_position
		patrol_radius = lab_patrol_radius
	else:
		global_position = entrance_position
		start_position = entrance_position
		patrol_radius = _default_patrol_radius
	
	velocity = Vector2.ZERO
	_enter_idle_state()
	
	for child in get_children():
		if child is NPCQuestGiver and child.has_method("_update_indicator"):
			child._update_indicator()


# ==============================================================================
# SECUENCIA DE TRANSFORMACIÓN A ENEMIGO
# ==============================================================================

## Espera a que se cierre el cuadro de diálogo de entrega antes de iniciar la transformación
func _prepare_transformation() -> void:
	if ergot_state != ErgotState.NPC or _pending_transformation:
		return
	_pending_transformation = true
	
	# Buscar si la ventana de diálogo está abierta en la escena
	var dlg = get_tree().root.find_child("QuestDialogueBox", true, false)
	if dlg and dlg.visible:
		if not dlg.dialogue_closed.is_connected(start_transformation):
			dlg.dialogue_closed.connect(start_transformation, CONNECT_ONE_SHOT)
	else:
		# Pequeña pausa de suspenso (0.4s) si no hay ventana activa
		get_tree().create_timer(0.4).timeout.connect(start_transformation)


## Inicia la transición y animación de transformación
func start_transformation() -> void:
	if ergot_state != ErgotState.NPC:
		return
	
	_pending_transformation = false
	ergot_state = ErgotState.TRANSFORMING
	velocity = Vector2.ZERO
	
	# Desactivar interacción de NPC (ocultar bocadillos e indicadores '!'/'?')
	for child in get_children():
		if child is NPCQuestGiver:
			child.visible = false
			child.set_process_mode(Node.PROCESS_MODE_DISABLED)
	
	# Mirar al jugador
	target_player = _get_player()
	if target_player:
		_face_target(target_player.global_position)
	
	# Reproducir animación de transformación en AnimatedSprite2D
	if anim and anim.sprite_frames and anim.sprite_frames.has_animation("transform"):
		anim.play("transform")
		var is_looping = anim.sprite_frames.get_animation_loop("transform")
		var count = anim.sprite_frames.get_frame_count("transform")
		if not is_looping and count > 1:
			await anim.animation_finished
		else:
			await get_tree().create_timer(transformation_duration).timeout
	else:
		# Efecto visual de parpadeo y mutación si aún no se han configurado frames
		var tween = create_tween()
		tween.tween_property(anim, "modulate", Color(1.2, 0.4, 0.4), 0.3)
		tween.tween_property(anim, "modulate", Color.WHITE, 0.3)
		tween.tween_property(anim, "modulate", Color(0.8, 0.2, 1.2), 0.5)
		tween.tween_property(anim, "modulate", Color.WHITE, 0.4)
		await tween.finished
	
	_complete_transformation(false)


## Finaliza la transformación y activa la IA ofensiva del enemigo
func _complete_transformation(instant: bool = false) -> void:
	ergot_state = ErgotState.ENEMY_CHASE
	current_health = enemy_max_health
	
	# Ocultar definitivamente componentes de NPC
	for child in get_children():
		if child is NPCQuestGiver:
			child.visible = false
			child.set_process_mode(Node.PROCESS_MODE_DISABLED)
	
	# Activar Hitbox (daño al jugador) y Hurtbox (daño recibido)
	if hitbox:
		hitbox.active = contact_damage
	if hurtbox:
		hurtbox.active = true
	
	target_player = _get_player()
	
	if not instant:
		# Pequeño rugido o efecto visual al transformarse
		_play_anim("enemy_idle", "run")
	else:
		global_position = lab_position
		_play_anim("enemy_idle", "idle")


# ==============================================================================
# BUCLE DE FÍSICAS E IA DE COMBATE
# ==============================================================================

func _physics_process(delta: float) -> void:
	# 1. Si sigue siendo NPC pacífico, ejecutar la patrulla estándar de NPCBase
	if ergot_state == ErgotState.NPC:
		super._physics_process(delta)
		return
	
	# 2. Aplicar gravedad
	if not is_on_floor():
		velocity.y += gravity * delta
	
	# 3. Estados pasivos de combate
	if ergot_state == ErgotState.ENEMY_DEAD:
		velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
		move_and_slide()
		return
	
	if ergot_state == ErgotState.TRANSFORMING:
		velocity.x = 0.0
		move_and_slide()
		return
	
	# 4. IA activa de combate (Persecución y Ataque)
	_run_enemy_ai(delta)
	move_and_slide()


func _run_enemy_ai(delta: float) -> void:
	if attack_timer > 0.0:
		attack_timer -= delta
	
	if target_player == null or not is_instance_valid(target_player):
		target_player = _get_player()
		if target_player == null:
			velocity.x = move_toward(velocity.x, 0.0, 200.0 * delta)
			_play_anim("enemy_idle", "idle")
			return
	
	var dist: float = global_position.distance_to(target_player.global_position)
	var dir_x: float = signf(target_player.global_position.x - global_position.x)
	if is_zero_approx(dir_x):
		dir_x = 1.0
	
	# Orientar el sprite hacia el jugador
	_face_target(target_player.global_position)
	
	# Si está actualmente ejecutando el ataque
	if is_attacking:
		velocity.x = move_toward(velocity.x, 0.0, 350.0 * delta)
		return
	
	# Evaluar si está en rango de ataque
	if dist <= enemy_attack_range:
		if attack_timer <= 0.0:
			_perform_attack()
		else:
			# Esperando enfriamiento del ataque
			velocity.x = move_toward(velocity.x, 0.0, 250.0 * delta)
			_play_anim("enemy_idle", "idle")
	else:
		# Perseguir al jugador
		ergot_state = ErgotState.ENEMY_CHASE
		velocity.x = dir_x * enemy_chase_speed
		_play_anim("run", "walk")


## Ejecuta el ataque cuerpo a cuerpo contra el jugador
func _perform_attack() -> void:
	ergot_state = ErgotState.ENEMY_ATTACK
	is_attacking = true
	attack_timer = enemy_attack_cooldown
	velocity.x = 0.0
	
	if hitbox:
		hitbox.active = true
	
	if anim and anim.sprite_frames and anim.sprite_frames.has_animation("attack"):
		anim.play("attack")
		var is_looping = anim.sprite_frames.get_animation_loop("attack")
		var count = anim.sprite_frames.get_frame_count("attack")
		if not is_looping and count > 1:
			await anim.animation_finished
		else:
			await get_tree().create_timer(0.6).timeout
	else:
		# Fallback visual de embestida si aún no hay frames de ataque configurados
		var orig_scale = anim.scale
		var tween = create_tween()
		tween.tween_property(anim, "scale", orig_scale * 1.25, 0.15)
		tween.tween_property(anim, "scale", orig_scale, 0.15)
		await tween.finished
	
	if hitbox and not contact_damage:
		hitbox.active = false
	
	is_attacking = false
	ergot_state = ErgotState.ENEMY_CHASE


# ==============================================================================
# SALUD, DAÑO Y MUERTE
# ==============================================================================

func _on_hurtbox_hit_received(incoming_hitbox: Hitbox) -> void:
	if ergot_state in [ErgotState.NPC, ErgotState.TRANSFORMING, ErgotState.ENEMY_DEAD]:
		return
	var dmg: int = incoming_hitbox.damage if incoming_hitbox else 1
	take_damage(dmg)


func take_damage(amount: int) -> void:
	if ergot_state in [ErgotState.NPC, ErgotState.TRANSFORMING, ErgotState.ENEMY_DEAD]:
		return
	
	current_health -= amount
	
	# Parpadeo de impacto
	var tween = create_tween()
	tween.tween_property(anim, "modulate", Color.RED, 0.08)
	tween.tween_property(anim, "modulate", Color.WHITE, 0.08)
	
	if current_health <= 0:
		die()
	elif anim and anim.sprite_frames and anim.sprite_frames.has_animation("hurt"):
		anim.play("hurt")


func die() -> void:
	ergot_state = ErgotState.ENEMY_DEAD
	velocity = Vector2.ZERO
	
	if hitbox:
		hitbox.active = false
	if hurtbox:
		hurtbox.active = false
	
	# Guardar evento de derrota para que no vuelva a aparecer
	if QuestManager:
		QuestManager.set_event_flag(defeated_flag, true)
	
	if anim and anim.sprite_frames and anim.sprite_frames.has_animation("die"):
		anim.play("die")
		await anim.animation_finished
		queue_free()
	elif anim and anim.sprite_frames and anim.sprite_frames.has_animation("death"):
		anim.play("death")
		await anim.animation_finished
		queue_free()
	else:
		var tween = create_tween()
		tween.tween_property(anim, "modulate:a", 0.0, 0.8)
		await tween.finished
		queue_free()


# ==============================================================================
# MÉTODOS AUXILIARES
# ==============================================================================

func _face_target(target_pos: Vector2) -> void:
	if anim == null:
		return
	var is_to_right := target_pos.x > global_position.x
	if sprite_faces_right:
		anim.flip_h = not is_to_right
	else:
		anim.flip_h = is_to_right


func _play_anim(anim_name: String, fallback: String = "") -> void:
	if anim == null or anim.sprite_frames == null:
		return
	if anim.sprite_frames.has_animation(anim_name):
		anim.play(anim_name)
	elif not fallback.is_empty() and anim.sprite_frames.has_animation(fallback):
		anim.play(fallback)
	elif anim.sprite_frames.has_animation("idle"):
		anim.play("idle")


func _get_player() -> Node2D:
	var nodes := get_tree().get_nodes_in_group("player")
	if not nodes.is_empty():
		return nodes[0] as Node2D
	return null
