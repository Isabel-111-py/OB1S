@tool
class_name Gate
extends Node2D

## Compuerta personalizable fúngica y de madera prehistórica para Godot 4.
## Soporta orientación Horizontal y Vertical, longitud y grosor ajustables,
## activación por palancas, modo Jefe/Evento (se cierra al entrar a la arena y
## se abre automáticamente al derrotar al jefe), y modo Trigger o Temporizado.

signal opened()
signal closed()
signal state_changed(is_open: bool)
signal locked()
signal unlocked()
signal player_triggered(player: Node2D)
signal boss_defeated()

# --- Grupos de exportación en el Inspector ---

@export_group("Dimensiones y Orientación")
## Orientación de la compuerta: Vertical (para pasillos/puertas) u Horizontal (para trampillas/techos).
@export_enum("Vertical", "Horizontal") var orientation: String = "Vertical":
	set(val):
		orientation = val
		_update_dimensions()
		if is_inside_tree():
			queue_redraw()

## Longitud de la compuerta en píxeles (altura si es Vertical, anchura si es Horizontal).
@export_range(16.0, 1024.0, 8.0) var gate_length: float = 96.0:
	set(val):
		gate_length = maxf(val, 16.0)
		_update_dimensions()
		if is_inside_tree():
			queue_redraw()

## Grosor de la compuerta en píxeles (ancho si es Vertical, alto si es Horizontal).
@export_range(8.0, 64.0, 2.0) var gate_thickness: float = 16.0:
	set(val):
		gate_thickness = maxf(val, 8.0)
		_update_dimensions()
		if is_inside_tree():
			queue_redraw()

## Dirección hacia la que se deslizará la compuerta al abrirse.
@export_enum("Hacia Arriba", "Hacia Abajo", "Hacia la Izquierda", "Hacia la Derecha") var open_direction: String = "Hacia Arriba":
	set(val):
		open_direction = val
		_update_dimensions()
		if is_inside_tree():
			queue_redraw()

## Distancia total de desplazamiento al abrirse. Si es 0.0, usa automáticamente la longitud completa (gate_length).
@export_range(0.0, 1024.0, 8.0) var open_distance: float = 0.0:
	set(val):
		open_distance = val
		_update_dimensions()
		if is_inside_tree():
			queue_redraw()

## Duración en segundos de la animación de apertura / cierre.
@export_range(0.1, 5.0, 0.1) var transition_duration: float = 0.7

## Si está activado, el movimiento tendrá aceleración y desaceleración suave.
@export var ease_movement: bool = true


@export_group("Tipo y Comportamiento")
## Modo de funcionamiento de la compuerta:
## - Palanca / Interruptor: Se abre o cierra mediante una o varias palancas.
## - Jefe / Evento: Se cierra al entrar el jugador al área y no se abre hasta que el jefe esté 'dead'.
## - Trigger de Entrada: Se activa automáticamente al cruzar el jugador una zona.
## - Temporizada: Se abre por palanca y se cierra sola tras un tiempo.
## - Manual / Código: Controlada exclusivamente por scripts o señales externas.
@export_enum("Palanca / Interruptor", "Jefe / Evento", "Trigger de Entrada", "Temporizada", "Manual / Código") var gate_type: String = "Palanca / Interruptor":
	set(val):
		gate_type = val
		_update_trigger_visibility()
		if is_inside_tree():
			queue_redraw()

## Si es verdadero, la compuerta inicia abierta. Por defecto inicia cerrada (falso).
@export var start_open: bool = false:
	set(val):
		start_open = val
		if Engine.is_editor_hint():
			is_open = val
			_apply_current_state_instant()

## Si es verdadero, la compuerta está trabada y las palancas normales no pueden abrirla.
@export var is_locked: bool = false:
	set(val):
		is_locked = val
		if is_locked:
			locked.emit()
		else:
			unlocked.emit()
		if is_inside_tree():
			_update_visuals()

## Acción al activar el trigger en modo 'Trigger de Entrada'.
@export_enum("Cerrar", "Abrir", "Alternar") var trigger_action: String = "Cerrar"

## En modo Temporizada, segundos antes de volver a cerrarse sola.
@export_range(0.5, 30.0, 0.5) var auto_close_delay: float = 4.0


@export_group("Configuración de Jefe / Evento")
## Referencia al nodo del Jefe. Se verificará si tiene 'is_dead == true', 'current_health <= 0' o si fue destruido.
@export var boss_target: Node2D

## Lista de múltiples enemigos o jefes. La compuerta se abrirá solo cuando TODOS estén derrotados.
@export var boss_targets: Array[Node2D] = []

## Nombre del grupo de jefes (opcional, ej. "boss" o "enemies"). Se abrirá cuando no quede ninguno vivo.
@export var boss_group: String = ""

## Posición relativa de la zona de activación (trigger) donde entra el jugador para cerrar la compuerta.
@export var trigger_offset: Vector2 = Vector2(0, 0):
	set(val):
		trigger_offset = val
		if has_node("TriggerArea"):
			$TriggerArea.position = val
		if is_inside_tree():
			queue_redraw()

## Tamaño de la zona de activación (trigger).
@export var trigger_size: Vector2 = Vector2(64, 64):
	set(val):
		trigger_size = val
		_update_trigger_shape()
		if is_inside_tree():
			queue_redraw()

## Si es verdadero, la zona de activación solo se dispara una vez.
@export var trigger_once: bool = true


@export_group("Aspecto y Rieles")
## Mostrar marco de piedra y madera en los extremos donde se ancla la compuerta.
@export var show_frame_mounts: bool = true:
	set(val):
		show_frame_mounts = val
		if is_inside_tree():
			queue_redraw()

## Color de los soportes y herrajes de piedra/madera.
@export var frame_color: Color = Color(0.28, 0.22, 0.16, 1.0):
	set(val):
		frame_color = val
		if is_inside_tree():
			queue_redraw()


# --- Nodos Hijos ---
@onready var barrier: AnimatableBody2D = $Barrier
@onready var collision_shape: CollisionShape2D = $Barrier/CollisionShape2D
@onready var visual_barrier: Node2D = $Barrier/VisualBarrier
@onready var trigger_area: Area2D = get_node_or_null("TriggerArea")
@onready var trigger_shape: CollisionShape2D = get_node_or_null("TriggerArea/CollisionShape2D")

# --- Variables de Estado Interno ---
var is_open: bool = false
var open_progress: float = 0.0 # 0.0 = cerrada, 1.0 = abierta
var is_moving: bool = false
var _boss_monitoring_active: bool = false
var _auto_close_timer: float = 0.0
var _trigger_consumed: bool = false
var _tween: Tween = null


func _ready() -> void:
	add_to_group("gates")
	_update_dimensions()
	_update_trigger_visibility()
	_update_trigger_shape()
	
	if Engine.is_editor_hint():
		is_open = start_open
		_apply_current_state_instant()
		queue_redraw()
		return
	
	# Inicialización en ejecución del juego
	is_open = start_open
	open_progress = 1.0 if is_open else 0.0
	_apply_current_state_instant()
	
	# Conectar zona de activación (trigger)
	if trigger_area:
		trigger_area.body_entered.connect(_on_trigger_body_entered)
	
	# Si es de tipo Jefe / Evento y ya inició cerrada, activar monitoreo inmediato
	if gate_type == "Jefe / Evento" and not is_open:
		_boss_monitoring_active = true


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	# 1. Monitoreo de temporizador de cierre automático
	if gate_type == "Temporizada" and is_open and not is_moving:
		if _auto_close_timer > 0.0:
			_auto_close_timer -= delta
			if _auto_close_timer <= 0.0:
				close()
	
	# 2. Monitoreo de estado de muerte del Jefe en modo 'Jefe / Evento'
	if _boss_monitoring_active and gate_type == "Jefe / Evento":
		_check_monitored_bosses()


# ==============================================================================
# CONTROL DE APERTURA Y CIERRE
# ==============================================================================

## Abre la compuerta. Si está bloqueada (is_locked) y force es falso, la acción se rechaza.
func open(force: bool = false) -> bool:
	if is_locked and not force:
		return false
	if is_open and not is_moving:
		return false
	
	is_open = true
	_animate_transition(1.0)
	return true


## Cierra la compuerta.
func close(force: bool = false) -> bool:
	if is_locked and not force:
		return false
	if not is_open and not is_moving:
		return false
	
	is_open = false
	_animate_transition(0.0)
	return true


## Alterna el estado entre abierto y cerrado. Usado por palancas.
func toggle(force: bool = false) -> bool:
	if is_locked and not force:
		return false
	if is_open:
		return close(force)
	else:
		return open(force)


## Bloquea la compuerta (las palancas no podrán abrirla).
func lock_gate() -> void:
	is_locked = true
	locked.emit()
	_update_visuals()


## Desbloquea la compuerta.
func unlock_gate() -> void:
	is_locked = false
	unlocked.emit()
	_update_visuals()


## Dispara el evento de la compuerta (cierra y bloquea para combate de jefe).
func trigger_boss_event() -> void:
	if _trigger_consumed and trigger_once:
		return
	_trigger_consumed = true
	
	# Se cierra de golpe y se bloquea
	is_locked = true
	close(true)
	_boss_monitoring_active = true


func _animate_transition(target_progress: float) -> void:
	is_moving = true
	
	if _tween and _tween.is_valid():
		_tween.kill()
	
	var closed_pos := Vector2.ZERO
	var open_pos := get_open_travel_vector()
	var target_pos := open_pos if target_progress >= 0.5 else closed_pos
	
	_tween = create_tween()
	if ease_movement:
		_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	else:
		_tween.set_trans(Tween.TRANS_LINEAR)
	
	_tween.parallel().tween_property(barrier, "position", target_pos, transition_duration)
	_tween.parallel().tween_property(self, "open_progress", target_progress, transition_duration)
	
	_tween.finished.connect(_on_transition_finished)
	_update_visuals()


func _on_transition_finished() -> void:
	is_moving = false
	_apply_current_state_instant()
	state_changed.emit(is_open)
	
	if is_open:
		opened.emit()
		if gate_type == "Temporizada":
			_auto_close_timer = auto_close_delay
	else:
		closed.emit()
	
	_update_visuals()


func _apply_current_state_instant() -> void:
	if not barrier:
		return
	
	var open_pos := get_open_travel_vector()
	barrier.position = open_pos if is_open else Vector2.ZERO
	open_progress = 1.0 if is_open else 0.0
	_update_visuals()


func get_open_travel_vector() -> Vector2:
	var dist := open_distance if open_distance > 0.0 else gate_length
	match open_direction:
		"Hacia Arriba":
			return Vector2(0, -dist)
		"Hacia Abajo":
			return Vector2(0, dist)
		"Hacia la Izquierda":
			return Vector2(-dist, 0)
		"Hacia la Derecha":
			return Vector2(dist, 0)
		_:
			return Vector2(0, -dist)


# ==============================================================================
# MONITOREO DE JEFE Y TRIGGERS
# ==============================================================================

func _on_trigger_body_entered(body: Node2D) -> void:
	if not _is_player(body):
		return
	if _trigger_consumed and trigger_once:
		return
	
	player_triggered.emit(body)
	
	if gate_type == "Jefe / Evento":
		trigger_boss_event()
	elif gate_type == "Trigger de Entrada":
		if trigger_once:
			_trigger_consumed = true
		match trigger_action:
			"Cerrar":
				close()
			"Abrir":
				open()
			"Alternar":
				toggle()


func _check_monitored_bosses() -> void:
	var has_configured_targets := false
	var any_boss_alive := false
	
	# 1. Objetivo único
	if boss_target != null:
		has_configured_targets = true
		if _is_target_alive(boss_target):
			any_boss_alive = true
	
	# 2. Lista de objetivos
	if not boss_targets.is_empty():
		has_configured_targets = true
		for target in boss_targets:
			if target != null and _is_target_alive(target):
				any_boss_alive = true
				break
	
	# 3. Grupo de jefes
	if not boss_group.is_empty():
		has_configured_targets = true
		var group_nodes := get_tree().get_nodes_in_group(boss_group)
		for node in group_nodes:
			if node is Node2D and _is_target_alive(node):
				any_boss_alive = true
				break
	
	# Si no se configuró ningún objetivo aún, no disparar
	if not has_configured_targets:
		return
	
	# Si todos los jefes monitoreados han muerto, desbloquear y abrir la compuerta
	if not any_boss_alive:
		_on_all_bosses_defeated()


func _is_target_alive(node: Node2D) -> bool:
	if not is_instance_valid(node):
		return false
	if node.is_queued_for_deletion():
		return false
	if node.get("is_dead") == true:
		return false
	if node.get("current_health") != null and node.get("current_health") <= 0:
		return false
	if node.has_method("is_alive") and not node.call("is_alive"):
		return false
	return true


func _on_all_bosses_defeated() -> void:
	_boss_monitoring_active = false
	is_locked = false
	boss_defeated.emit()
	unlocked.emit()
	# Abrir inmediatamente la compuerta al vencer al jefe
	open(true)


func _is_player(body: Node2D) -> bool:
	if body is CharacterBody2D:
		if body.is_in_group("player") or body.is_in_group("Player"):
			return true
		if body.name == "Player" or body.name.begins_with("Player"):
			return true
	return false


# ==============================================================================
# DIMENSIONES Y VISUALES
# ==============================================================================

func _update_dimensions() -> void:
	if not is_inside_tree():
		return
	
	var col_size: Vector2
	if orientation == "Vertical":
		col_size = Vector2(gate_thickness, gate_length)
	else:
		col_size = Vector2(gate_length, gate_thickness)
	
	if has_node("Barrier/CollisionShape2D"):
		var col: CollisionShape2D = $Barrier/CollisionShape2D
		if col.shape is RectangleShape2D:
			(col.shape as RectangleShape2D).size = col_size
		col.position = Vector2.ZERO
	
	_update_visuals()


func _update_trigger_shape() -> void:
	if not is_inside_tree():
		return
	if has_node("TriggerArea/CollisionShape2D"):
		var trig_col: CollisionShape2D = $TriggerArea/CollisionShape2D
		if trig_col.shape is RectangleShape2D:
			(trig_col.shape as RectangleShape2D).size = trigger_size


func _update_trigger_visibility() -> void:
	if not is_inside_tree():
		return
	var should_have_trigger := (gate_type in ["Jefe / Evento", "Trigger de Entrada"])
	if has_node("TriggerArea"):
		var ta: Area2D = $TriggerArea
		ta.monitoring = should_have_trigger
		ta.monitorable = should_have_trigger


func _update_visuals() -> void:
	if has_node("Barrier/VisualBarrier"):
		$Barrier/VisualBarrier.queue_redraw()
	queue_redraw()


# ==============================================================================
# RENDERIZADO EN EDITOR Y SOPORTES DE MARCO
# ==============================================================================

func _draw() -> void:
	# 1. Dibujar soportes fúngicos / marcos de piedra y madera en los extremos
	if show_frame_mounts:
		_draw_frame_brackets()
	
	# 2. Guías exclusivas del Editor de Godot
	if Engine.is_editor_hint():
		_draw_editor_helpers()


func _draw_frame_brackets() -> void:
	var half_len := gate_length * 0.5
	var half_th := gate_thickness * 0.5
	var socket_size := 8.0
	
	if orientation == "Vertical":
		# Soporte superior
		var top_rect := Rect2(-half_th - 3.0, -half_len - socket_size, gate_thickness + 6.0, socket_size)
		draw_rect(top_rect, frame_color, true)
		draw_rect(top_rect, Color(0.12, 0.08, 0.05), false, 1.0)
		# Clavija / gema de resina
		draw_circle(Vector2(0, -half_len - socket_size * 0.5), 2.2, Color(0.48, 0.38, 0.22))
		
		# Soporte inferior
		var bot_rect := Rect2(-half_th - 3.0, half_len, gate_thickness + 6.0, socket_size)
		draw_rect(bot_rect, frame_color, true)
		draw_rect(bot_rect, Color(0.12, 0.08, 0.05), false, 1.0)
		draw_circle(Vector2(0, half_len + socket_size * 0.5), 2.2, Color(0.48, 0.38, 0.22))
	else:
		# Soporte izquierdo
		var left_rect := Rect2(-half_len - socket_size, -half_th - 3.0, socket_size, gate_thickness + 6.0)
		draw_rect(left_rect, frame_color, true)
		draw_rect(left_rect, Color(0.12, 0.08, 0.05), false, 1.0)
		draw_circle(Vector2(-half_len - socket_size * 0.5, 0), 2.2, Color(0.48, 0.38, 0.22))
		
		# Soporte derecho
		var right_rect := Rect2(half_len, -half_th - 3.0, socket_size, gate_thickness + 6.0)
		draw_rect(right_rect, frame_color, true)
		draw_rect(right_rect, Color(0.12, 0.08, 0.05), false, 1.0)
		draw_circle(Vector2(half_len + socket_size * 0.5, 0), 2.2, Color(0.48, 0.38, 0.22))


func _draw_editor_helpers() -> void:
	var open_pos := get_open_travel_vector()
	var half_len := gate_length * 0.5
	var half_th := gate_thickness * 0.5
	
	# Flecha indicadora de apertura
	if open_pos.length_squared() > 1.0:
		var dir := open_pos.normalized()
		var perp := dir.orthogonal() * 5.0
		draw_line(Vector2.ZERO, open_pos, Color(0.3, 0.9, 0.6, 0.75), 1.5, true)
		draw_line(open_pos - dir * 8.0 - perp, open_pos, Color(0.3, 0.9, 0.6, 0.9), 2.0)
		draw_line(open_pos - dir * 8.0 + perp, open_pos, Color(0.3, 0.9, 0.6, 0.9), 2.0)
		
		# Silueta fantasma de posición abierta
		var ghost_rect: Rect2
		if orientation == "Vertical":
			ghost_rect = Rect2(open_pos.x - half_th, open_pos.y - half_len, gate_thickness, gate_length)
		else:
			ghost_rect = Rect2(open_pos.x - half_len, open_pos.y - half_th, gate_length, gate_thickness)
		draw_rect(ghost_rect, Color(0.2, 0.8, 1.0, 0.15), true)
		draw_rect(ghost_rect, Color(0.2, 0.8, 1.0, 0.5), false, 1.0)
	
	# Indicador visual del Trigger si está activo
	if gate_type in ["Jefe / Evento", "Trigger de Entrada"]:
		var trig_rect := Rect2(trigger_offset - trigger_size * 0.5, trigger_size)
		draw_rect(trig_rect, Color(1.0, 0.8, 0.2, 0.12), true)
		draw_rect(trig_rect, Color(1.0, 0.8, 0.2, 0.7), false, 1.5)
