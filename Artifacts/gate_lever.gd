@tool
class_name GateLever
extends Area2D

## Palanca fúngica de madera para accionar compuertas (abrir, cerrar o alternar).
## Se conecta directamente a un nodo Gate por referencia o ruta.
## Detecta interacción por tecla [E], botón del gamepad y acción 'interact'.

signal lever_pulled()

@export_group("Conexión con Compuerta")
## Referencia directa al nodo Gate que controlará esta palanca.
@export var target_gate: Gate:
	set(val):
		target_gate = val
		_update_prompt_text()
		queue_redraw()

## Ruta de nodo alternativa para conectar la compuerta.
@export_node_path("Gate") var gate_path: NodePath:
	set(val):
		gate_path = val
		if is_inside_tree() and has_node(val):
			target_gate = get_node(val) as Gate
		_update_prompt_text()
		queue_redraw()

## Acción que ejecutará la palanca sobre la compuerta al ser accionada:
## - Alternar (Toggle): Abre si está cerrada, cierra si está abierta.
## - Solo Abrir: Solo abre la compuerta.
## - Solo Cerrar: Solo cierra la compuerta.
@export_enum("Alternar (Toggle)", "Solo Abrir", "Solo Cerrar") var lever_action: String = "Alternar (Toggle)"

## Orientación del mango de la palanca: "Izquierda" o "Derecha".
@export_enum("Izquierda", "Derecha") var lever_facing: String = "Izquierda":
	set(val):
		lever_facing = val
		queue_redraw()

# --- Nodos Hijos ---
@onready var prompt_container: Node2D = get_node_or_null("PromptContainer")
@onready var prompt_label: Label = get_node_or_null("PromptContainer/PromptPanel/Label")

# --- Variables de Estado Interno ---
var lever_angle: float = -28.0 # Grados de inclinación del mango
var is_animating_pull: bool = false
var player_inside: bool = false
var prompt_anim_time: float = 0.0


func _ready() -> void:
	_resolve_gate_reference()
	
	if Engine.is_editor_hint():
		queue_redraw()
		return
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	if prompt_container:
		prompt_container.visible = false
	
	_update_prompt_text()


func _resolve_gate_reference() -> void:
	if target_gate != null and is_instance_valid(target_gate):
		return
	if not gate_path.is_empty() and has_node(gate_path):
		target_gate = get_node(gate_path) as Gate
		return
	
	# Si no se asignó, buscar automáticamente la compuerta más cercana en la escena
	if is_inside_tree():
		var gates := get_tree().get_nodes_in_group("gates")
		var nearest: Gate = null
		var min_d := 999999.0
		for g in gates:
			if g is Gate:
				var d := global_position.distance_to(g.global_position)
				if d < min_d:
					min_d = d
					nearest = g
		if nearest:
			target_gate = nearest


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	prompt_anim_time += delta
	
	# Detección continua en physics_process para que nunca se pierda la tecla [E]
	if player_inside and not is_animating_pull:
		if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_accept"):
			pull_lever()
		elif Input.is_physical_key_pressed(KEY_E) and not Input.is_key_pressed(KEY_E):
			pull_lever()
	
	# Animación de flotación suave del cartel de interacción
	if prompt_container and prompt_container.visible:
		var bob := sin(prompt_anim_time * 4.0) * 2.0
		prompt_container.position.y = -38.0 + bob
		_update_prompt_text()


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


## Acciona la palanca, ejecutando el movimiento de la compuerta asociada.
func pull_lever() -> void:
	if is_animating_pull:
		return
	
	_resolve_gate_reference()
	if target_gate == null:
		push_warning("GateLever '%s': No se encontró ningún Gate asociado." % name)
		return
	
	# Si la compuerta está trabada (ej. combate de jefe), no se mueve
	if target_gate.is_locked:
		_animate_locked_jiggle()
		return
	
	is_animating_pull = true
	lever_pulled.emit()
	
	# Animación mecánica de giro de la palanca
	var target_pull_angle := 28.0 if lever_facing == "Izquierda" else -28.0
	var rest_angle := -28.0 if lever_facing == "Izquierda" else 28.0
	
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "lever_angle", target_pull_angle, 0.14)
	tween.tween_interval(0.18)
	tween.tween_property(self, "lever_angle", rest_angle, 0.22)
	tween.finished.connect(func(): is_animating_pull = false)
	
	# Operar la compuerta
	match lever_action:
		"Alternar (Toggle)":
			target_gate.toggle()
		"Solo Abrir":
			target_gate.open()
		"Solo Cerrar":
			target_gate.close()
	
	_update_prompt_text()
	queue_redraw()


func _animate_locked_jiggle() -> void:
	is_animating_pull = true
	var base_ang := lever_angle
	var tween := create_tween()
	tween.tween_property(self, "lever_angle", base_ang + 6.0, 0.05)
	tween.tween_property(self, "lever_angle", base_ang - 6.0, 0.05)
	tween.tween_property(self, "lever_angle", base_ang + 4.0, 0.05)
	tween.tween_property(self, "lever_angle", base_ang, 0.05)
	tween.finished.connect(func(): is_animating_pull = false)


func _on_body_entered(body: Node2D) -> void:
	if _is_player(body):
		player_inside = true
		_resolve_gate_reference()
		_update_prompt_text()
		if prompt_container:
			prompt_container.visible = true


func _on_body_exited(body: Node2D) -> void:
	if _is_player(body):
		player_inside = false
		if prompt_container:
			prompt_container.visible = false


func _is_player(body: Node2D) -> bool:
	if body is CharacterBody2D:
		if body.is_in_group("player") or body.is_in_group("Player"):
			return true
		if body.name == "Player" or body.name.begins_with("Player"):
			return true
	return false


func _update_prompt_text() -> void:
	if not prompt_label:
		return
	
	if target_gate == null:
		_resolve_gate_reference()
	
	if target_gate == null:
		prompt_label.text = "Palanca sin compuerta asignada"
		return
	
	if target_gate.is_locked:
		prompt_label.text = "¡Compuerta bloqueada!"
		return
	
	match lever_action:
		"Solo Abrir":
			if target_gate.is_open:
				prompt_label.text = "Compuerta ya abierta"
			else:
				prompt_label.text = "Presiona [E] para abrir compuerta"
		"Solo Cerrar":
			if not target_gate.is_open:
				prompt_label.text = "Compuerta ya cerrada"
			else:
				prompt_label.text = "Presiona [E] para cerrar compuerta"
		"Alternar (Toggle)":
			if target_gate.is_open:
				prompt_label.text = "Presiona [E] para cerrar compuerta"
			else:
				prompt_label.text = "Presiona [E] para abrir compuerta"


# --- Renderizado de la Palanca ---
func _draw() -> void:
	if target_gate == null:
		_resolve_gate_reference()
	
	# Color del hongo indicador
	var shroom_color: Color
	var halo_color: Color
	
	if target_gate and target_gate.is_locked:
		shroom_color = Color(0.95, 0.25, 0.20)
		halo_color = Color(0.95, 0.25, 0.20, 0.4)
	elif target_gate and target_gate.is_open:
		shroom_color = Color(0.24, 0.94, 0.65) # Verde esmeralda (abierta)
		halo_color = Color(0.24, 0.94, 0.65, 0.3)
	else:
		shroom_color = Color(0.96, 0.65, 0.22) # Ámbar (cerrada)
		halo_color = Color(0.96, 0.65, 0.22, 0.25)
	
	# 1. Base de tronco labrado
	var base_w := 14.0
	var base_h := 10.0
	var base_rect := Rect2(-base_w * 0.5, -base_h, base_w, base_h)
	draw_rect(base_rect, Color(0.32, 0.20, 0.12), true)
	draw_rect(base_rect, Color(0.18, 0.11, 0.07), false, 1.0)
	draw_line(Vector2(-base_w * 0.5 + 2, -base_h + 3), Vector2(base_w * 0.5 - 2, -base_h + 3), Color(0.44, 0.30, 0.18), 1.0)
	draw_line(Vector2(-base_w * 0.5, -2.5), Vector2(base_w * 0.5, -2.5), Color(0.38, 0.58, 0.22), 1.6)
	
	# 2. Mango de madera y pomo de hueso
	var pivot := Vector2(0, -base_h * 0.5)
	var handle_len := 15.0
	var angle_rad := deg_to_rad(lever_angle)
	var handle_dir := Vector2(sin(angle_rad), -cos(angle_rad))
	var handle_end := pivot + handle_dir * handle_len
	
	draw_line(pivot, handle_end, Color(0.50, 0.35, 0.22), 2.5)
	draw_line(pivot, handle_end, Color(0.22, 0.14, 0.08), 1.0)
	draw_circle(handle_end, 2.4, Color(0.86, 0.82, 0.72))
	draw_circle(handle_end, 1.2, Color(0.96, 0.94, 0.88))
	draw_circle(pivot, 2.2, Color(0.18, 0.11, 0.07))
	draw_circle(pivot, 1.4, Color(0.68, 0.50, 0.34))
	
	# 3. Honguito indicador bioluminiscente
	var shroom_offset_x := 4.0 if lever_facing == "Izquierda" else -4.0
	var shroom_center := Vector2(shroom_offset_x, -base_h - 4.5)
	draw_circle(shroom_center, 6.0, halo_color)
	draw_line(Vector2(shroom_offset_x, -base_h), shroom_center, Color(0.90, 0.88, 0.80), 1.5)
	
	var cap_pts := PackedVector2Array([
		shroom_center + Vector2(-3.0, 0.0),
		shroom_center + Vector2(-2.0, -2.5),
		shroom_center + Vector2(0.0, -3.8),
		shroom_center + Vector2(2.0, -2.5),
		shroom_center + Vector2(3.0, 0.0)
	])
	draw_colored_polygon(cap_pts, shroom_color)
	draw_circle(shroom_center + Vector2(0, -1.8), 0.7, Color.WHITE)
