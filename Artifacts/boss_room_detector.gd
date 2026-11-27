class_name BossRoomDetector
extends Area2D

## Detector de Sala de Jefe:
## Detecta cuando el jugador ingresa a la sala del jefe (Laboratorio del Dr. Ergot).
## 1. La compuerta 'Puerta_boss' inicia abierta.
## 2. Al entrar el jugador al área que marca la sala del jefe (y estar el jefe con vida),
##    'Puerta_boss' se cierra y se bloquea (es la única compuerta afectada).
## 3. Mientras el jefe permanezca con vida, la compuerta se mantendrá cerrada y trabada.
## 4. Al registrarse la muerte del jefe ('dr_ergot_defeated' / ENEMY_DEAD), 'Puerta_boss' vuelve a abrirse automáticamente.
## 5. Si el jugador muere y reaparece fuera, la compuerta se abre para permitir un nuevo intento.

signal player_entered_boss_room(player: Node2D)
signal boss_room_locked()
signal boss_defeated_gate_opened()

@export_group("Conexiones")
## Referencia al nodo Gate exclusivo que sella la arena ('Puerta_boss').
@export var target_gate: Gate

## Nombre del nodo Gate objetivo si no se asignó referencia directa (por defecto "Puerta_boss").
@export var gate_name: String = "Puerta_boss"

## Referencia al nodo del jefe (Dr. Ergot).
@export var boss_node: Node2D

## Nombre del nodo del jefe si no se asignó referencia directa en el inspector.
@export var boss_name: String = "DrErgot"

## Flag de evento en QuestManager que marca la derrota definitiva del jefe.
@export var defeated_flag: String = "dr_ergot_defeated"

@export_group("Comportamiento")
## Retardo breve en segundos tras entrar el jugador antes de cerrar la compuerta.
@export var close_delay: float = 0.2

## Si es verdadero, solo bloquea si el Dr. Ergot se encuentra en la sala del laboratorio (no si aún está en la entrada).
@export var require_boss_in_room: bool = true

var _is_monitoring: bool = false
var _player_inside: bool = false
var _gate_locked_by_detector: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	_resolve_references()
	
	# Escuchar eventos de banderas en QuestManager
	if QuestManager:
		if not QuestManager.event_flag_changed.is_connected(_on_event_flag_changed):
			QuestManager.event_flag_changed.connect(_on_event_flag_changed)
	
	# Escuchar respawn del jugador en SceneManager por si reaparece tras morir
	var sm = get_node_or_null("/root/SceneManager")
	if sm and sm.has_signal("player_respawned"):
		sm.player_respawned.connect(_on_player_respawned)
	
	# Asegurar estado inicial: Puerta_boss abierta
	call_deferred("_check_initial_state")


func _physics_process(_delta: float) -> void:
	if not _is_monitoring:
		return
	
	# Monitoreo activo de la muerte del jefe
	if is_boss_defeated():
		_on_boss_defeated()


func _resolve_references() -> void:
	# 1. Resolver Gate (buscar exclusivamente Puerta_boss como prioridad)
	if target_gate == null or not is_instance_valid(target_gate):
		if get_parent():
			var g := get_parent().get_node_or_null(gate_name) as Gate
			if g:
				target_gate = g
		if target_gate == null and get_tree() and get_tree().current_scene:
			var g2 := get_tree().current_scene.find_child(gate_name, true, false) as Gate
			if g2:
				target_gate = g2
		if target_gate == null and is_inside_tree():
			var gates := get_tree().get_nodes_in_group("gates")
			for g in gates:
				if g is Gate and g.name == gate_name:
					target_gate = g
					break
	
	# 2. Resolver Boss
	if boss_node == null or not is_instance_valid(boss_node):
		if get_parent():
			var b := get_parent().get_node_or_null(boss_name) as Node2D
			if b:
				boss_node = b
		if boss_node == null and get_tree() and get_tree().current_scene:
			var found := get_tree().current_scene.find_child(boss_name, true, false) as Node2D
			if found:
				boss_node = found
		if boss_node == null and is_inside_tree():
			var bosses := get_tree().get_nodes_in_group("boss")
			if not bosses.is_empty() and bosses[0] is Node2D:
				boss_node = bosses[0]
	
	# Conectar señal de muerte directa del jefe si la tiene
	if boss_node != null and is_instance_valid(boss_node):
		if boss_node.has_signal("boss_died") and not boss_node.is_connected("boss_died", _on_boss_defeated):
			boss_node.connect("boss_died", _on_boss_defeated)
		if boss_node.has_signal("boss_transformed") and not boss_node.is_connected("boss_transformed", _on_boss_transformed):
			boss_node.connect("boss_transformed", _on_boss_transformed)


func is_boss_defeated() -> bool:
	if QuestManager and QuestManager.has_event_flag(defeated_flag):
		return true
	if boss_node == null or not is_instance_valid(boss_node):
		return QuestManager != null and QuestManager.has_event_flag(defeated_flag)
	if boss_node.is_queued_for_deletion():
		return true
	if boss_node.get("is_dead") == true:
		return true
	if boss_node.get("current_health") != null and boss_node.get("current_health") <= 0:
		return true
	if boss_node.get("ergot_state") != null:
		# 4 = ErgotState.ENEMY_DEAD
		if int(boss_node.get("ergot_state")) == 4:
			return true
	return false


func is_boss_in_room() -> bool:
	_resolve_references()
	if is_boss_defeated():
		return false
	if boss_node == null or not is_instance_valid(boss_node):
		return false
	
	# Comprobar si el script de DrErgot indica que está en la fase de laboratorio
	if boss_node.has_method("_is_in_lab_phase"):
		if not boss_node.call("_is_in_lab_phase"):
			return false
	
	# Comprobar distancia física a la sala del laboratorio
	if global_position.distance_to(boss_node.global_position) > 2500.0:
		return false
	
	return true


func _on_body_entered(body: Node2D) -> void:
	if not _is_player(body):
		return
	
	_player_inside = true
	_resolve_references()
	
	# Si el jefe ya fue derrotado, asegurarse de que Puerta_boss permanezca abierta
	if is_boss_defeated():
		if target_gate and is_instance_valid(target_gate):
			target_gate.unlock_gate()
			target_gate.open(true)
		return
	
	# Si se requiere que el jefe esté presente y aún no está en la sala, no bloquear
	if require_boss_in_room and not is_boss_in_room():
		return
	
	player_entered_boss_room.emit(body)
	_lock_gate_for_boss_fight()


func _on_body_exited(body: Node2D) -> void:
	if _is_player(body):
		_player_inside = false


func _lock_gate_for_boss_fight() -> void:
	if _gate_locked_by_detector:
		return
	_gate_locked_by_detector = true
	_is_monitoring = true
	
	_resolve_references()
	if target_gate and is_instance_valid(target_gate):
		if close_delay > 0.0:
			await get_tree().create_timer(close_delay).timeout
		if is_instance_valid(target_gate) and not is_boss_defeated():
			target_gate.close(true)
			target_gate.lock_gate()
			boss_room_locked.emit()


func _on_boss_transformed() -> void:
	# Si el jugador ya estaba adentro al transformarse, asegurar el bloqueo de la sala
	if _player_inside and not is_boss_defeated():
		_lock_gate_for_boss_fight()


func _on_boss_defeated() -> void:
	_is_monitoring = false
	_gate_locked_by_detector = false
	boss_defeated_gate_opened.emit()
	
	_resolve_references()
	if target_gate and is_instance_valid(target_gate):
		target_gate.unlock_gate()
		target_gate.open(true)


func _on_event_flag_changed(flag_name: String, value: bool) -> void:
	if flag_name == defeated_flag and value:
		_on_boss_defeated()


func _on_player_respawned(_player: Node2D) -> void:
	# Si el jugador murió y reapareció fuera de la sala, reabrir Puerta_boss para permitir reintentos
	if not _player_inside and _gate_locked_by_detector:
		_gate_locked_by_detector = false
		_is_monitoring = false
		_resolve_references()
		if target_gate and is_instance_valid(target_gate):
			target_gate.unlock_gate()
			target_gate.open(true)


func _check_initial_state() -> void:
	_resolve_references()
	if target_gate and is_instance_valid(target_gate):
		# Puerta_boss debe iniciar abierta a menos que ya se esté en combate activo
		if is_boss_defeated() or not _gate_locked_by_detector:
			target_gate.unlock_gate()
			if not target_gate.is_open:
				target_gate.open(true)


func _is_player(body: Node2D) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	if body.is_in_group("player") or body.is_in_group("Player"):
		return true
	if body.name.to_lower().begins_with("player"):
		return true
	return false
