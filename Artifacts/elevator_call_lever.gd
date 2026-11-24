@tool
class_name ElevatorCallLever
extends Area2D

## Palanca de llamado rústica de madera y tecnología fúngica prehistórica.
## Permite al jugador llamar o accionar el elevador desde cualquier piso.
## Si el elevador está lejos, lo llama. Si ya está en este piso, lo activa hacia el otro lado.
## Si se cayó a medio camino, invierte su marcha de inmediato.

signal lever_pulled()

@export_enum("Piso Inicial (Start)", "Piso Destino (Destination)") var target_floor: String = "Piso Inicial (Start)":
	set(val):
		target_floor = val
		_update_prompt_text()
		queue_redraw()

## Referencia al nodo Elevator. Si se deja vacío, busca automáticamente en el padre o en el nivel.
@export var elevator: Elevator:
	set(val):
		elevator = val
		queue_redraw()

## Ruta al nodo Elevator (opcional, para palancas colocadas libremente en el nivel).
@export_node_path("Elevator") var elevator_path: NodePath:
	set(val):
		elevator_path = val
		if is_inside_tree() and has_node(val):
			elevator = get_node(val) as Elevator
		queue_redraw()

## Orientación del mango de la palanca: "Izquierda" o "Derecha".
@export_enum("Izquierda", "Derecha") var lever_facing: String = "Izquierda":
	set(val):
		lever_facing = val
		queue_redraw()

# --- Nodos Hijos ---
@onready var prompt_container: Node2D = get_node_or_null("PromptContainer")
@onready var prompt_label: Label = get_node_or_null("PromptContainer/PromptPanel/Label")

# --- Variables de Animación y Estado ---
var lever_angle: float = -28.0 # Grados de inclinación del mango
var is_animating_pull: bool = false
var player_inside: bool = false
var prompt_anim_time: float = 0.0


func _ready() -> void:
	set_notify_transform(true)
	_resolve_elevator_reference()
	
	if Engine.is_editor_hint():
		queue_redraw()
		return
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	if prompt_container:
		prompt_container.visible = false
	
	_update_prompt_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint() and is_inside_tree():
		var p := get_parent()
		if p is Elevator and p.has_method("_on_lever_moved_in_editor"):
			p.call("_on_lever_moved_in_editor", self)


func _resolve_elevator_reference() -> void:
	if elevator != null and is_instance_valid(elevator):
		return
	if not elevator_path.is_empty() and has_node(elevator_path):
		elevator = get_node(elevator_path) as Elevator
		return
	var p := get_parent()
	if p is Elevator:
		elevator = p
		return
	elif owner and owner is Elevator:
		elevator = owner as Elevator
		return
	
	# Búsqueda automática por grupo en la escena
	if is_inside_tree():
		var elevators := get_tree().get_nodes_in_group("elevators")
		var nearest: Elevator = null
		var min_d := 999999.0
		for el in elevators:
			if el is Elevator:
				var d := global_position.distance_to(el.global_position)
				if d < min_d:
					min_d = d
					nearest = el
		if nearest:
			elevator = nearest


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	prompt_anim_time += delta
	
	# Detección directa en physics_process para que nunca se pierda la pulsación de la tecla E
	if player_inside and not is_animating_pull:
		if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_accept"):
			pull_lever()
		elif Input.is_physical_key_pressed(KEY_E) and not Input.is_key_pressed(KEY_E):
			pull_lever()
	
	# Actualizar animación de flotación del cartel
	if prompt_container and prompt_container.visible:
		var bob := sin(prompt_anim_time * 4.0) * 2.0
		prompt_container.position.y = -38.0 + bob
		_update_prompt_text()
	
	# Redibujar si el elevador está viajando para animar el parpadeo de esporas
	if elevator and (elevator.current_state == Elevator.ElevatorState.MOVING_TO_END or elevator.current_state == Elevator.ElevatorState.MOVING_TO_START):
		queue_redraw()


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	
	if not player_inside or is_animating_pull:
		return
	
	if _is_interact_action(event):
		get_viewport().set_input_as_handled()
		pull_lever()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	
	if not player_inside or is_animating_pull:
		return
	
	if _is_interact_action(event):
		get_viewport().set_input_as_handled()
		pull_lever()


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


## Acciona la palanca manualmente o por código.
func pull_lever() -> void:
	if is_animating_pull:
		return
	
	_resolve_elevator_reference()
	if elevator == null:
		push_warning("ElevatorCallLever '%s': No se encontró ningún Elevator al que enviar la señal." % name)
		return
	
	is_animating_pull = true
	lever_pulled.emit()
	
	# Animación mecánica de giro de la palanca de madera
	var target_pull_angle := 28.0 if lever_facing == "Izquierda" else -28.0
	var rest_angle := -28.0 if lever_facing == "Izquierda" else 28.0
	
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "lever_angle", target_pull_angle, 0.14)
	tween.tween_interval(0.2)
	tween.tween_property(self, "lever_angle", rest_angle, 0.22)
	tween.finished.connect(func(): is_animating_pull = false)
	
	# Llamar u operar el elevador según el piso
	elevator.operate_from_floor(target_floor)
	
	_update_prompt_text()
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if _is_player(body):
		player_inside = true
		_resolve_elevator_reference()
		_update_prompt_text()
		if prompt_container:
			prompt_container.visible = true


func _on_body_exited(body: Node2D) -> void:
	if _is_player(body):
		player_inside = false
		if prompt_container:
			prompt_container.visible = false


func _is_player(body: Node2D) -> bool:
	if body is Player:
		return true
	if body.is_in_group("player") or body.is_in_group("Player"):
		return true
	if body.name == "Player" or body.name.begins_with("Player"):
		return true
	# Si es CharacterBody2D pero no es enemigo ni NPC
	if body is CharacterBody2D and not body.is_in_group("enemies") and not body.name.to_lower().contains("mushroom") and not body.name.to_lower().contains("zombie"):
		return true
	return false


func _update_prompt_text() -> void:
	if not prompt_label:
		return
	if elevator == null:
		_resolve_elevator_reference()
	if elevator == null:
		prompt_label.text = "Palanca sin elevador conectado"
		return
	
	var is_here := false
	var is_coming := false
	
	if target_floor == "Piso Inicial (Start)":
		is_here = (elevator.current_state == Elevator.ElevatorState.IDLE_AT_START)
		is_coming = (elevator.current_state == Elevator.ElevatorState.MOVING_TO_START)
	else:
		is_here = (elevator.current_state == Elevator.ElevatorState.IDLE_AT_END)
		is_coming = (elevator.current_state == Elevator.ElevatorState.MOVING_TO_END)
	
	if is_coming:
		prompt_label.text = "¡Elevador en camino...!"
	elif is_here:
		prompt_label.text = "Presiona [E] para activar"
	else:
		prompt_label.text = "Presiona [E] para llamar elevador"


# --- Renderizado de la Palanca ---
func _draw() -> void:
	if elevator == null:
		_resolve_elevator_reference()
	
	var is_moving := false
	var pulse := 0.0
	var is_here := false
	
	if elevator:
		if target_floor == "Piso Inicial (Start)":
			is_here = (elevator.current_state == Elevator.ElevatorState.IDLE_AT_START)
			is_moving = (elevator.current_state == Elevator.ElevatorState.MOVING_TO_START)
		else:
			is_here = (elevator.current_state == Elevator.ElevatorState.IDLE_AT_END)
			is_moving = (elevator.current_state == Elevator.ElevatorState.MOVING_TO_END)
		
		if is_moving:
			pulse = (sin(Time.get_ticks_msec() * 0.012) + 1.0) * 0.5
	
	# Color del hongo indicador sobre la palanca
	var shroom_color: Color
	var halo_color: Color
	
	if is_moving:
		# Ámbar/magenta pulsante de llamada en progreso
		shroom_color = Color(0.96, 0.62, 0.20).lerp(Color(0.88, 0.30, 0.75), pulse)
		halo_color = Color(shroom_color.r, shroom_color.g, shroom_color.b, 0.25 + 0.35 * pulse)
	elif is_here:
		# Suave / listo para activar
		shroom_color = Color(0.24, 0.88, 0.95)
		halo_color = Color(0.24, 0.88, 0.95, 0.25)
	else:
		# Verde esmeralda vivo: listo para llamar
		shroom_color = Color(0.24, 0.94, 0.56)
		halo_color = Color(0.24, 0.94, 0.56, 0.35)
	
	# -------------------------------------------------------------
	# 1. BASE DE TRONCO LABRADO
	# -------------------------------------------------------------
	var base_w := 14.0
	var base_h := 10.0
	var base_rect := Rect2(-base_w * 0.5, -base_h, base_w, base_h)
	draw_rect(base_rect, Color(0.32, 0.20, 0.12), true) # Tronco base
	draw_rect(base_rect, Color(0.18, 0.11, 0.07), false, 1.0) # Borde oscuro
	
	# Vetas y textura de madera en la base
	draw_line(Vector2(-base_w * 0.5 + 2, -base_h + 3), Vector2(base_w * 0.5 - 2, -base_h + 3), Color(0.44, 0.30, 0.18), 1.0)
	
	# Amarre de liana alrededor de la base
	draw_line(Vector2(-base_w * 0.5, -2.5), Vector2(base_w * 0.5, -2.5), Color(0.38, 0.58, 0.22), 1.6)
	
	# -------------------------------------------------------------
	# 2. MANGO / BRAZO DE LA PALANCA DE MADERA
	# -------------------------------------------------------------
	var pivot := Vector2(0, -base_h * 0.5)
	var handle_len := 15.0
	
	# Calcular dirección del mango con el ángulo actual
	var angle_rad := deg_to_rad(lever_angle)
	var handle_dir := Vector2(sin(angle_rad), -cos(angle_rad))
	var handle_end := pivot + handle_dir * handle_len
	
	# Brazo de madera tallada
	draw_line(pivot, handle_end, Color(0.50, 0.35, 0.22), 2.5) # Brazo de madera
	draw_line(pivot, handle_end, Color(0.22, 0.14, 0.08), 1.0) # Detalle
	
	# Pomo de hueso / piedra tallada en el extremo del mango
	draw_circle(handle_end, 2.4, Color(0.86, 0.82, 0.72)) # Pomo
	draw_circle(handle_end, 1.2, Color(0.96, 0.94, 0.88)) # Brillo
	
	# Perno / clavija central de giro en el pivote
	draw_circle(pivot, 2.2, Color(0.18, 0.11, 0.07)) # Orificio
	draw_circle(pivot, 1.4, Color(0.68, 0.50, 0.34)) # Clavija
	
	# -------------------------------------------------------------
	# 3. HONGO INDICADOR LUMINOSO SOBRE LA BASE
	# -------------------------------------------------------------
	var shroom_offset_x := 4.0 if lever_facing == "Izquierda" else -4.0
	var shroom_center := Vector2(shroom_offset_x, -base_h - 4.5)
	
	# Aura bioluminiscente
	var halo_r := 6.0 + (pulse * 2.0 if is_moving else 0.0)
	draw_circle(shroom_center, halo_r, halo_color)
	
	# Pie del hongo
	draw_line(Vector2(shroom_offset_x, -base_h), shroom_center, Color(0.90, 0.88, 0.80), 1.5)
	
	# Sombrerillo
	var cap_pts := PackedVector2Array([
		shroom_center + Vector2(-3.0, 0.0),
		shroom_center + Vector2(-2.0, -2.5),
		shroom_center + Vector2(0.0, -3.8),
		shroom_center + Vector2(2.0, -2.5),
		shroom_center + Vector2(3.0, 0.0)
	])
	draw_colored_polygon(cap_pts, shroom_color)
	draw_circle(shroom_center + Vector2(0, -1.8), 0.7, Color.WHITE)
