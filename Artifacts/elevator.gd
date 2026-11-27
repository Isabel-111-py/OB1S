@tool
class_name Elevator
extends Node2D

## Elevador personalizable para mundos y niveles 2D en Godot 4.
## Permite ajustar distancia (longitud), dirección, velocidad y comportamiento con interacción por botón.

signal movement_started(to_destination: bool)
signal movement_finished(at_destination: bool)
signal button_pressed()

enum ElevatorState {
	IDLE_AT_START,
	MOVING_TO_END,
	IDLE_AT_END,
	MOVING_TO_START
}

@export_group("Recorrido y Distancia")
## Longitud total del recorrido del elevador en píxeles.
@export_range(16.0, 2000.0, 8.0) var travel_distance: float = 160.0:
	set(val):
		travel_distance = val
		_update_offsets()
		if is_inside_tree():
			queue_redraw()

## Dirección hacia la que viajará el elevador desde su posición inicial.
@export_enum("Arriba", "Abajo", "Izquierda", "Derecha", "Personalizado") var move_direction: String = "Arriba":
	set(val):
		move_direction = val
		_update_offsets()
		if is_inside_tree():
			queue_redraw()

## Vector de dirección utilizado cuando move_direction es 'Personalizado'.
@export var custom_direction: Vector2 = Vector2.UP:
	set(val):
		custom_direction = val
		_update_offsets()
		if is_inside_tree():
			queue_redraw()

## Velocidad de movimiento en píxeles por segundo.
@export_range(10.0, 800.0, 5.0) var speed: float = 80.0

## Si está activado, la aceleración y frenado serán suaves (curva sinusoidal).
@export var ease_movement: bool = true

## Tiempo de espera (en segundos) tras llegar a un extremo antes de poder reactivarse.
@export_range(0.0, 10.0, 0.1) var wait_time_at_ends: float = 0.5


@export_group("Interacción y Activación")
## Si es verdadero, el jugador debe presionar el botón interactuar (E / W / Aceptar).
## Si es falso, el elevador arranca automáticamente al subirse a él.
@export var require_button_press: bool = true

## Si es verdadero, tras llegar al destino esperará 'auto_return_delay' y volverá solo.
@export var auto_return: bool = false
@export_range(0.5, 30.0, 0.5) var auto_return_delay: float = 3.0

## Si es verdadero, el elevador iniciará en el extremo final en lugar del origen.
@export var start_at_destination: bool = false


@export_group("Palancas de Llamado")
## Si es verdadero, incluye una palanca de llamado en el piso inicial (abajo).
@export var include_start_lever: bool = true:
	set(val):
		include_start_lever = (val == true)
		_update_lever_positions()
		if is_inside_tree():
			queue_redraw()

## Si es verdadero, incluye una palanca de llamado en el piso destino (arriba).
@export var include_end_lever: bool = true:
	set(val):
		include_end_lever = (val == true)
		_update_lever_positions()
		if is_inside_tree():
			queue_redraw()

## Posición relativa de la palanca de llamado inicial (Start).
@export var start_lever_offset: Vector2 = Vector2(-46.0, 0.0):
	set(val):
		start_lever_offset = val if val != null else Vector2(-46.0, 0.0)
		_update_lever_positions()
		if is_inside_tree():
			queue_redraw()

## Posición relativa de la palanca de llamado de destino (End) respecto al punto final.
@export var end_lever_offset: Vector2 = Vector2(-46.0, 0.0):
	set(val):
		end_lever_offset = val if val != null else Vector2(-46.0, 0.0)
		_update_lever_positions()
		if is_inside_tree():
			queue_redraw()

## Compatibilidad: añade estación de llamada en destino.
@export var include_call_button: bool = true:
	set(val):
		include_call_button = val
		include_end_lever = val


@export_group("Dimensiones y Aspecto")
## Ancho de la plataforma en píxeles.
@export_range(24.0, 256.0, 4.0) var platform_width: float = 64.0:
	set(val):
		platform_width = val
		_update_dimensions()
		if is_inside_tree():
			queue_redraw()

## Grosor / altura de la plataforma en píxeles.
@export_range(6.0, 48.0, 2.0) var platform_height: float = 12.0:
	set(val):
		platform_height = val
		_update_dimensions()
		if is_inside_tree():
			queue_redraw()

## Mostrar riel / cable guía visual entre el punto de origen y el destino.
@export var show_track: bool = true:
	set(val):
		show_track = val
		if is_inside_tree():
			queue_redraw()

## Color de la liana o cuerda guía de cáñamo.
@export var track_color: Color = Color(0.48, 0.38, 0.25, 0.88):
	set(val):
		track_color = val
		if is_inside_tree():
			queue_redraw()

## Texto personalizado para el cartel de activación (vacío para automático según dirección).
@export var custom_prompt_text: String = ""


# --- Nodos Hijos ---
@onready var platform: AnimatableBody2D = $Platform
@onready var collision_shape: CollisionShape2D = $Platform/CollisionShape2D
@onready var interaction_area: Area2D = $Platform/InteractionArea
@onready var interaction_shape: CollisionShape2D = $Platform/InteractionArea/CollisionShape2D
@onready var visual_platform: Node2D = $Platform/VisualPlatform
@onready var prompt_container: Node2D = $Platform/PromptContainer
@onready var prompt_label: Label = $Platform/PromptContainer/PromptPanel/Label
@onready var crush_area: Area2D = $Platform.get_node_or_null("CrushArea")
@onready var start_call_lever: Area2D = get_node_or_null("StartCallLever")
@onready var end_call_lever: Area2D = get_node_or_null("EndCallLever")
@onready var call_station: Area2D = get_node_or_null("CallStation")
@onready var call_prompt: Node2D = get_node_or_null("CallStation/PromptContainer")
@onready var call_prompt_label: Label = get_node_or_null("CallStation/PromptContainer/PromptPanel/Label")

# --- Variables de Estado Interno ---
var current_state: ElevatorState = ElevatorState.IDLE_AT_START
var progress: float = 0.0 # 0.0 = inicio, 1.0 = destino
var start_offset: Vector2 = Vector2.ZERO
var target_offset: Vector2 = Vector2.ZERO

var _updating_levers_internal: bool = false
var player_on_platform: bool = false
var player_at_call_station: bool = false
var wait_timer: float = 0.0
var auto_return_timer: float = 0.0
var prompt_anim_time: float = 0.0


func _ready() -> void:
	add_to_group("elevators")
	_update_offsets()
	
	if Engine.is_editor_hint():
		_update_dimensions()
		queue_redraw()
		return
	
	# Inicialización en ejecución de juego
	_setup_in_game()


func _setup_in_game() -> void:
	add_to_group("elevators")
	_update_dimensions()
	
	# Configurar offsets y palancas de llamado
	start_offset = Vector2.ZERO
	target_offset = get_travel_offset()
	_update_lever_positions()
	
	if call_station:
		call_station.position = target_offset
		call_station.visible = false
		call_station.monitoring = false
		if call_prompt:
			call_prompt.visible = false
	
	# Estado inicial
	if start_at_destination:
		progress = 1.0
		platform.position = target_offset
		current_state = ElevatorState.IDLE_AT_END
	else:
		progress = 0.0
		platform.position = start_offset
		current_state = ElevatorState.IDLE_AT_START
	
	# Conexión de áreas de interacción
	if interaction_area:
		interaction_area.body_entered.connect(_on_interaction_body_entered)
		interaction_area.body_exited.connect(_on_interaction_body_exited)
	
	# Ocultar cartel de activación al inicio
	if prompt_container:
		prompt_container.visible = false
	
	_update_prompt_text()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	prompt_anim_time += delta
	_animate_prompts()
	
	# Detección directa en physics_process para que nunca se pierda la tecla interactuar sobre la plataforma
	if player_on_platform and (current_state == ElevatorState.IDLE_AT_START or current_state == ElevatorState.IDLE_AT_END):
		if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_accept"):
			_on_platform_button_pressed()
		elif Input.is_physical_key_pressed(KEY_E) and not Input.is_key_pressed(KEY_E):
			_on_platform_button_pressed()
	
	# Verificar si el jugador está siendo aplastado bajo la plataforma en descenso
	_check_crush_hazard()
	
	# Temporizador de espera tras llegar a un piso
	if wait_timer > 0.0:
		wait_timer -= delta
	
	# Temporizador de retorno automático
	if auto_return and current_state == ElevatorState.IDLE_AT_END and wait_timer <= 0.0:
		auto_return_timer -= delta
		if auto_return_timer <= 0.0:
			start_moving_to_start()
			return
	
	# Movimiento de la plataforma
	if current_state == ElevatorState.MOVING_TO_END:
		var travel_time: float = maxf(travel_distance / maxf(speed, 10.0), 0.05)
		progress = minf(progress + delta / travel_time, 1.0)
		_apply_platform_position()
		if progress >= 1.0:
			_arrive_at_destination()
			
	elif current_state == ElevatorState.MOVING_TO_START:
		var travel_time: float = maxf(travel_distance / maxf(speed, 10.0), 0.05)
		progress = maxf(progress - delta / travel_time, 0.0)
		_apply_platform_position()
		if progress <= 0.0:
			_arrive_at_start()


## Detecta si el jugador está debajo de la plataforma mientras desciende o se acerca al suelo
func _check_crush_hazard() -> void:
	if current_state != ElevatorState.MOVING_TO_START and current_state != ElevatorState.MOVING_TO_END:
		return
	
	if crush_area == null:
		return
	
	# Determinar vector de movimiento actual
	var move_vector := (target_offset - start_offset)
	if current_state == ElevatorState.MOVING_TO_START:
		move_vector = -move_vector
	
	# ¿La plataforma se está moviendo hacia abajo?
	var is_moving_down := move_vector.y > 5.0
	
	var bodies := crush_area.get_overlapping_bodies()
	for body in bodies:
		if not _is_player(body):
			continue
		
		var p := body as CharacterBody2D
		if p == null:
			continue
		
		# 1. El elevador desciende y el jugador está apoyado en el suelo (aplastamiento inminente)
		var crushing_on_floor := is_moving_down and p.is_on_floor()
		
		# 2. La plataforma desciende y la distancia restante al piso es menor que la altura del personaje (~32px)
		var current_dest := start_offset if current_state == ElevatorState.MOVING_TO_START else target_offset
		var dist_to_dest := platform.position.distance_to(current_dest)
		var trapped_near_ground := is_moving_down and dist_to_dest < 32.0
		
		# 3. Movimiento lateral aplastando al jugador contra una pared
		var crushing_on_wall := p.is_on_wall() and absf(move_vector.x) > 5.0
		
		if crushing_on_floor or trapped_near_ground or crushing_on_wall:
			_kill_player_by_crush(body)
			break


func _kill_player_by_crush(player_node: Node2D) -> void:
	if player_node == null or not is_instance_valid(player_node):
		return
	if player_node.get("is_dead") == true:
		return
	
	# 1. Aplicar daño letal para que el Player entre en estado Dead y emita 'died'
	if player_node.has_method("take_damage"):
		player_node.call("take_damage", 9999, Vector2.DOWN * 30.0)
	
	# 2. Asegurar que SceneManager gestione el respawn al checkpoint del nivel
	var sm = Engine.get_singleton("SceneManager") if Engine.has_singleton("SceneManager") else null
	if sm == null and has_node("/root/SceneManager"):
		sm = get_node("/root/SceneManager")
	
	if sm:
		if sm.get("player") == null:
			sm.set("player", player_node)
		
		# Asegurar que haya un checkpoint válido guardado
		var chk_pos = sm.get("_checkpoint_pos")
		if chk_pos == null or chk_pos == Vector2.ZERO:
			var spawn = get_tree().get_first_node_in_group("spawn_points")
			if spawn:
				sm.call("set_checkpoint", spawn.global_position, 1.0)
			else:
				sm.call("set_checkpoint", player_node.global_position - Vector2(80, 0), 1.0)
		
		# Conectar la señal de muerte al respawn si no estaba conectada
		if player_node.has_signal("died"):
			if not player_node.is_connected("died", Callable(sm, "_on_player_died")):
				player_node.connect("died", Callable(sm, "_on_player_died"), CONNECT_ONE_SHOT)


func _apply_platform_position() -> void:
	var factor: float = progress
	if ease_movement:
		# Curva suave de aceleración y frenado: 0.5 * (1 - cos(PI * progress))
		factor = 0.5 * (1.0 - cos(PI * progress))
	
	platform.position = start_offset.lerp(target_offset, factor)
	
	if visual_platform:
		visual_platform.queue_redraw()
	if call_station and include_call_button:
		call_station.queue_redraw()


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	
	if not _is_interact_action(event):
		return
	
	if player_on_platform and (current_state == ElevatorState.IDLE_AT_START or current_state == ElevatorState.IDLE_AT_END):
		get_viewport().set_input_as_handled()
		_on_platform_button_pressed()
	elif player_at_call_station and current_state == ElevatorState.IDLE_AT_START:
		get_viewport().set_input_as_handled()
		_on_call_button_pressed()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	
	if not _is_interact_action(event):
		return
	
	if player_on_platform and (current_state == ElevatorState.IDLE_AT_START or current_state == ElevatorState.IDLE_AT_END):
		get_viewport().set_input_as_handled()
		_on_platform_button_pressed()
	elif player_at_call_station and current_state == ElevatorState.IDLE_AT_START:
		get_viewport().set_input_as_handled()
		_on_call_button_pressed()


func _is_interact_action(event: InputEvent) -> bool:
	if not event.is_pressed() or event.is_echo():
		return false
	if InputMap.has_action("interact") and event.is_action_pressed("interact"):
		return true
	if event.is_action_pressed("ui_accept"):
		return true
	if event is InputEventKey:
		if event.physical_keycode in [KEY_E, KEY_W, KEY_UP, KEY_ENTER] or event.keycode in [KEY_E, KEY_W, KEY_UP, KEY_ENTER]:
			return true
	if event is InputEventJoypadButton:
		if event.button_index in [JOY_BUTTON_A, JOY_BUTTON_Y, JOY_BUTTON_X]:
			return true
	return false


func _on_platform_button_pressed() -> void:
	if wait_timer > 0.0:
		return
	
	button_pressed.emit()
	
	if current_state == ElevatorState.IDLE_AT_START:
		start_moving_to_end()
	elif current_state == ElevatorState.IDLE_AT_END:
		start_moving_to_start()


func _on_call_button_pressed() -> void:
	call_to_end()


## Opera el elevador desde una palanca situada en un piso específico.
## Si el elevador está en otro piso o alejándose, lo llama a este piso (ideal si el jugador cayó).
## Si el elevador ya está en este piso, lo activa hacia el piso contrario.
func operate_from_floor(from_floor: String) -> void:
	var is_start_floor := ("Inicial" in from_floor) or ("Start" in from_floor)
	
	if is_start_floor:
		if current_state == ElevatorState.IDLE_AT_START:
			start_moving_to_end()
		else:
			call_to_start()
	else:
		if current_state == ElevatorState.IDLE_AT_END:
			start_moving_to_start()
		else:
			call_to_end()


## Llamar al elevador hacia el piso inicial (Start). Usado por la palanca de abajo.
## Si el elevador estaba arriba o subiendo, invierte la marcha y baja inmediatamente.
func call_to_start() -> bool:
	if current_state == ElevatorState.IDLE_AT_START:
		return false
	
	wait_timer = 0.0
	button_pressed.emit()
	start_moving_to_start()
	return true


## Llamar al elevador hacia el piso destino (End). Usado por la palanca de arriba.
## Si el elevador estaba abajo o bajando, invierte la marcha y sube inmediatamente.
func call_to_end() -> bool:
	if current_state == ElevatorState.IDLE_AT_END:
		return false
	
	wait_timer = 0.0
	button_pressed.emit()
	start_moving_to_end()
	return true


## Inicia el viaje hacia la plataforma de destino.
func start_moving_to_end() -> void:
	current_state = ElevatorState.MOVING_TO_END
	_update_prompts_visibility()
	movement_started.emit(true)
	if visual_platform:
		visual_platform.queue_redraw()
	_redraw_levers()


## Inicia el viaje de vuelta a la plataforma inicial.
func start_moving_to_start() -> void:
	current_state = ElevatorState.MOVING_TO_START
	_update_prompts_visibility()
	movement_started.emit(false)
	if visual_platform:
		visual_platform.queue_redraw()
	_redraw_levers()


func _arrive_at_destination() -> void:
	current_state = ElevatorState.IDLE_AT_END
	wait_timer = wait_time_at_ends
	auto_return_timer = auto_return_delay
	_update_prompt_text()
	_update_prompts_visibility()
	movement_finished.emit(true)
	if visual_platform:
		visual_platform.queue_redraw()
	_redraw_levers()
	if call_station:
		call_station.queue_redraw()


func _arrive_at_start() -> void:
	current_state = ElevatorState.IDLE_AT_START
	wait_timer = wait_time_at_ends
	_update_prompt_text()
	_update_prompts_visibility()
	movement_finished.emit(false)
	if visual_platform:
		visual_platform.queue_redraw()
	_redraw_levers()
	if call_station:
		call_station.queue_redraw()


# --- Detección de Jugador ---
func _on_interaction_body_entered(body: Node2D) -> void:
	if _is_player(body):
		player_on_platform = true
		_update_prompts_visibility()
		if not require_button_press and wait_timer <= 0.0:
			if current_state == ElevatorState.IDLE_AT_START:
				start_moving_to_end()
			elif current_state == ElevatorState.IDLE_AT_END:
				start_moving_to_start()


func _on_interaction_body_exited(body: Node2D) -> void:
	if _is_player(body):
		player_on_platform = false
		_update_prompts_visibility()


func _on_call_body_entered(body: Node2D) -> void:
	if _is_player(body):
		player_at_call_station = true
		_update_prompts_visibility()


func _on_call_body_exited(body: Node2D) -> void:
	if _is_player(body):
		player_at_call_station = false
		_update_prompts_visibility()


func _is_player(body: Node2D) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	if body.is_in_group("player") or body.is_in_group("Player"):
		return true
	if body.name.to_lower().begins_with("player"):
		return true
	return false


# --- Carteles y Animación de Interfaz ---
func _update_prompts_visibility() -> void:
	if prompt_container:
		var can_activate_platform := player_on_platform and (current_state == ElevatorState.IDLE_AT_START or current_state == ElevatorState.IDLE_AT_END)
		prompt_container.visible = can_activate_platform
	
	if call_prompt and include_call_button:
		var can_call := player_at_call_station and current_state == ElevatorState.IDLE_AT_START
		call_prompt.visible = can_call


func _update_prompt_text() -> void:
	if not prompt_label:
		return
	
	if not custom_prompt_text.is_empty():
		prompt_label.text = custom_prompt_text
		return
	
	var is_vertical := move_direction in ["Arriba", "Abajo"]
	if current_state == ElevatorState.IDLE_AT_START:
		if move_direction == "Arriba":
			prompt_label.text = "Presiona [E] para Subir"
		elif move_direction == "Abajo":
			prompt_label.text = "Presiona [E] para Bajar"
		else:
			prompt_label.text = "Presiona [E] para Activar"
	elif current_state == ElevatorState.IDLE_AT_END:
		if move_direction == "Arriba":
			prompt_label.text = "Presiona [E] para Bajar"
		elif move_direction == "Abajo":
			prompt_label.text = "Presiona [E] para Subir"
		else:
			prompt_label.text = "Presiona [E] para Volver"


func _animate_prompts() -> void:
	var bob := sin(prompt_anim_time * 4.0) * 2.0
	if prompt_container and prompt_container.visible:
		prompt_container.position.y = -platform_height * 0.5 - 34.0 + bob
	if call_prompt and call_prompt.visible:
		call_prompt.position.y = -36.0 + bob


# --- Cálculo de Vectores y Dimensiones ---
func get_travel_offset() -> Vector2:
	match move_direction:
		"Arriba":
			return Vector2(0, -travel_distance)
		"Abajo":
			return Vector2(0, travel_distance)
		"Izquierda":
			return Vector2(-travel_distance, 0)
		"Derecha":
			return Vector2(travel_distance, 0)
		"Personalizado":
			var dir := custom_direction.normalized()
			if dir.length_squared() < 0.001:
				dir = Vector2.UP
			return dir * travel_distance
		_:
			return Vector2(0, -travel_distance)


func _update_offsets() -> void:
	target_offset = get_travel_offset()
	_update_lever_positions()
	if Engine.is_editor_hint() and has_node("CallStation"):
		$CallStation.position = target_offset


func _update_lever_positions() -> void:
	if not is_inside_tree():
		return
	_updating_levers_internal = true
	var s_offset: Vector2 = start_lever_offset if start_lever_offset != null else Vector2(-46.0, 0.0)
	var e_offset: Vector2 = end_lever_offset if end_lever_offset != null else Vector2(-46.0, 0.0)
	if has_node("StartCallLever"):
		var sl: Node2D = $StartCallLever
		sl.position = s_offset
		sl.visible = (include_start_lever == true)
		if sl is Area2D:
			(sl as Area2D).monitoring = (include_start_lever == true)
		sl.queue_redraw()
	if has_node("EndCallLever"):
		var el: Node2D = $EndCallLever
		el.position = target_offset + e_offset
		el.visible = (include_end_lever == true)
		if el is Area2D:
			(el as Area2D).monitoring = (include_end_lever == true)
		el.queue_redraw()
	_updating_levers_internal = false


## Sincroniza las coordenadas en el Inspector cuando el usuario arrastra las palancas en el visor 2D
func _on_lever_moved_in_editor(lever: Node2D) -> void:
	if _updating_levers_internal:
		return
	if lever.name == "StartCallLever":
		start_lever_offset = lever.position
	elif lever.name == "EndCallLever":
		end_lever_offset = lever.position - target_offset
	queue_redraw()


func _redraw_levers() -> void:
	if has_node("StartCallLever"):
		$StartCallLever.queue_redraw()
	if has_node("EndCallLever"):
		$EndCallLever.queue_redraw()


func _update_dimensions() -> void:
	if not is_inside_tree():
		return
	
	if has_node("Platform/CollisionShape2D"):
		var col: CollisionShape2D = $Platform/CollisionShape2D
		if col.shape is RectangleShape2D:
			(col.shape as RectangleShape2D).size = Vector2(platform_width, platform_height)
	
	if has_node("Platform/InteractionArea/CollisionShape2D"):
		var area_col: CollisionShape2D = $Platform/InteractionArea/CollisionShape2D
		if area_col.shape is RectangleShape2D:
			(area_col.shape as RectangleShape2D).size = Vector2(platform_width - 2.0, 40.0)
			area_col.position = Vector2(0, -20.0 - platform_height * 0.5)
	
	if has_node("Platform/CrushArea/CollisionShape2D"):
		var crush_col: CollisionShape2D = $Platform/CrushArea/CollisionShape2D
		if crush_col.shape is RectangleShape2D:
			(crush_col.shape as RectangleShape2D).size = Vector2(platform_width - 8.0, 10.0)
			crush_col.position = Vector2(0, platform_height * 0.5 + 4.0)
	
	if has_node("Platform/PromptContainer"):
		$Platform/PromptContainer.position.y = -platform_height * 0.5 - 34.0
	
	if has_node("Platform/VisualPlatform"):
		$Platform/VisualPlatform.queue_redraw()


# --- Renderizado en el Editor y en el Juego ---
func _draw() -> void:
	var target := get_travel_offset()
	
	# 1. Dibujar liana o cuerda trenzada de cáñamo con poleas de madera
	if show_track or Engine.is_editor_hint():
		var dist := target.length()
		var dir_norm := target.normalized()
		var perp := dir_norm.orthogonal() * 2.2
		
		# Cuerda central de fondo
		draw_line(Vector2.ZERO, target, track_color, 3.2, true)
		
		# Textura helicoidal de trenzado de la cuerda
		if dist > 8.0:
			var steps := int(dist / 6.0)
			for i in range(steps):
				var t0 := float(i) * 6.0
				var t1 := minf(t0 + 4.0, dist)
				var p0 := dir_norm * t0 - perp
				var p1 := dir_norm * t1 + perp
				# Vetas claras y oscuras del trenzado
				draw_line(p0, p1, Color(track_color.r * 1.25, track_color.g * 1.25, track_color.b * 1.25, track_color.a), 1.2)
				draw_line(p0 + dir_norm * 1.5, p1 + dir_norm * 1.5, Color(track_color.r * 0.65, track_color.g * 0.65, track_color.b * 0.65, track_color.a), 1.0)
				
				# Brotes de hojitas o musgo cada cierto trecho a lo largo de la liana
				if i % 7 == 3:
					var leaf_pt := dir_norm * t0 + perp * 1.2
					draw_circle(leaf_pt, 1.4, Color(0.38, 0.62, 0.24, 0.9))
		
		# Poleas de madera tallada en los extremos (mecanismo rústico)
		_draw_wooden_pulley(Vector2.ZERO)
		_draw_wooden_pulley(target)
	
	# 2. Elementos exclusivos en el Editor de Godot
	if Engine.is_editor_hint():
		var dir_norm := target.normalized()
		
		# Flecha de dirección a mitad del recorrido
		if dir_norm.length_squared() > 0.01:
			var arrow_center := target * 0.5
			var perp := dir_norm.orthogonal() * 6.0
			draw_line(arrow_center - dir_norm * 8.0 - perp, arrow_center, Color(0.96, 0.72, 0.22, 0.95), 2.0)
			draw_line(arrow_center - dir_norm * 8.0 + perp, arrow_center, Color(0.96, 0.72, 0.22, 0.95), 2.0)
		
		# Silueta verde en la posición inicial (origen)
		var start_rect := Rect2(
			-platform_width * 0.5,
			-platform_height * 0.5,
			platform_width,
			platform_height
		)
		draw_rect(start_rect, Color(0.2, 0.9, 0.4, 0.15), true)
		draw_rect(start_rect, Color(0.2, 0.9, 0.4, 0.8), false, 1.5)
		
		# Silueta cian de previsualización en la plataforma destino
		var dest_rect := Rect2(
			target.x - platform_width * 0.5,
			target.y - platform_height * 0.5,
			platform_width,
			platform_height
		)
		draw_rect(dest_rect, Color(0.2, 0.8, 1.0, 0.2), true)
		draw_rect(dest_rect, Color(0.2, 0.8, 1.0, 0.85), false, 1.5)


func _draw_wooden_pulley(pos: Vector2) -> void:
	# Soporte / soporte de viga de madera
	draw_rect(Rect2(pos.x - 6.0, pos.y - 3.0, 12.0, 6.0), Color(0.34, 0.22, 0.14), true)
	draw_rect(Rect2(pos.x - 6.0, pos.y - 3.0, 12.0, 6.0), Color(0.18, 0.11, 0.07), false, 1.0)
	# Rueda de polea de madera
	draw_circle(pos, 5.0, Color(0.48, 0.32, 0.20))
	draw_circle(pos, 5.0, Color(0.24, 0.15, 0.09), false, 1.0)
	# Clavija o eje central de madera clara
	draw_circle(pos, 1.8, Color(0.68, 0.50, 0.34))
