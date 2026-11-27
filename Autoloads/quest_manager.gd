extends Node

## Autoload global "QuestManager": Administrador central de misiones y eventos del juego.
## Gestiona el ciclo completo de misiones entre múltiples escenas y NPCs (DrErgot y Funry),
## persistiendo el estado independientemente del cambio de niveles.

enum QuestStatus {
	LOCKED = 0,             # Bloqueada por prerrequisitos
	AVAILABLE = 1,          # Disponible para hablar con el NPC (muestra '?')
	ACTIVE = 2,             # Aceptada y en curso
	READY_TO_TURN_IN = 3,   # Objetivos cumplidos, lista para entregar / informar (muestra '!')
	COMPLETED = 4           # Terminada y recompensada
}

signal quest_registered(quest_id: String)
signal quest_unlocked(quest_id: String)
signal quest_accepted(quest_id: String)
signal quest_updated(quest_id: String)
signal quest_step_delivered(quest_id: String, target_npc_id: String)
signal quest_ready_to_turn_in(quest_id: String)
signal quest_completed(quest_id: String)
signal event_flag_changed(flag_name: String, value: bool)

## quest_id -> QuestData
var _quest_definitions: Dictionary = {}
## quest_id -> QuestStatus (int)
var _quest_statuses: Dictionary = {}
## quest_id -> bool (true si ya se le entregó el ítem al target_npc)
var _quest_delivery_done: Dictionary = {}
## flag_name -> bool
var _event_flags: Dictionary = {}


func _ready() -> void:
	# Conectar con Inventory para detectar automáticamente cuando el jugador recoge o pierde un ítem requerido
	if Engine.has_singleton("Inventory") or has_node("/root/Inventory"):
		var inv = get_node_or_null("/root/Inventory")
		if inv:
			if inv.has_signal("upgrade_added"):
				inv.connect("upgrade_added", _on_inventory_changed.unbind(1))
			if inv.has_signal("upgrade_removed"):
				inv.connect("upgrade_removed", _on_inventory_changed.unbind(1))


# ==============================================================================
# NORMALIZACIÓN Y COMPARACIÓN DE IDENTIFICADORES
# ==============================================================================

## Normaliza identificadores para evitar fallos por mayúsculas, espacios o alias (funry/runry)
func normalize_id(id: String) -> String:
	var s := id.to_lower().strip_edges().replace(" ", "_").replace("-", "_")
	# Unificar alias para tolerar funry/runry, dr_ergot/drergot, y minfy/munfy
	if s == "runry" or s == "funry":
		return "funry"
	if s == "drergot" or s == "dr_ergot" or s == "doctor_ergot" or s == "dr_ergo":
		return "dr_ergot"
	if s == "minfy" or s == "munfy":
		return "munfy"
	return s


func ids_match(id_a: String, id_b: String) -> bool:
	if id_a.is_empty() or id_b.is_empty():
		return false
	return normalize_id(id_a) == normalize_id(id_b)


# ==============================================================================
# REGISTRO Y GESTIÓN DE MISIONES
# ==============================================================================

## Registra una misión en el gestor. Si ya existe y está activa o completada,
## no sobreescribe su progreso ni su configuración para evitar que otros nodos la corrompan.
func register_quest(data: QuestData) -> void:
	if data == null or data.id.is_empty():
		return
	
	if _quest_definitions.has(data.id) and _quest_statuses.has(data.id):
		var current_st = _quest_statuses[data.id]
		# Si ya está en curso, lista para turn-in o completada, mantener la definición original
		if current_st != QuestStatus.AVAILABLE and current_st != QuestStatus.LOCKED:
			return
	
	_quest_definitions[data.id] = data
	
	if not _quest_statuses.has(data.id):
		if _can_unlock_internal(data):
			_quest_statuses[data.id] = QuestStatus.AVAILABLE
		else:
			_quest_statuses[data.id] = QuestStatus.LOCKED
	
	quest_registered.emit(data.id)
	_refresh_all_quest_statuses()


func get_quest_data(quest_id: String) -> QuestData:
	return _quest_definitions.get(quest_id, null)


func get_quest_status(quest_id: String) -> QuestStatus:
	if not _quest_statuses.has(quest_id):
		return QuestStatus.LOCKED
	return _quest_statuses[quest_id] as QuestStatus


func is_quest_available(quest_id: String) -> bool:
	return get_quest_status(quest_id) == QuestStatus.AVAILABLE


func is_quest_active(quest_id: String) -> bool:
	return get_quest_status(quest_id) == QuestStatus.ACTIVE


func is_quest_ready_to_turn_in(quest_id: String) -> bool:
	return get_quest_status(quest_id) == QuestStatus.READY_TO_TURN_IN


func is_quest_completed(quest_id: String) -> bool:
	return get_quest_status(quest_id) == QuestStatus.COMPLETED


func is_delivery_done(quest_id: String) -> bool:
	return _quest_delivery_done.get(quest_id, false)


## El jugador acepta la misión desde el NPC que la ofrece (DrErgot)
func accept_quest(quest_id: String) -> bool:
	var q := get_quest_data(quest_id)
	if q == null:
		return false
	
	var status := get_quest_status(quest_id)
	if status != QuestStatus.AVAILABLE:
		return false
	
	_quest_statuses[quest_id] = QuestStatus.ACTIVE
	_quest_delivery_done[quest_id] = false
	
	# Otorgar ítem automático al jugador si la misión lo especifica (la medicina)
	if not String(q.grant_item_on_accept).is_empty():
		var inv = get_node_or_null("/root/Inventory")
		if inv and inv.has_method("add_upgrade"):
			var item_name := q.grant_item_name if not q.grant_item_name.is_empty() else String(q.grant_item_on_accept)
			inv.add_upgrade(q.grant_item_on_accept, item_name, q.grant_item_desc, q.grant_item_icon)
	
	quest_accepted.emit(quest_id)
	quest_updated.emit(quest_id)
	
	check_quest_progress(quest_id)
	return true


## Entrega el ítem al NPC objetivo (Funry).
## Marca primero la entrega como realizada, luego consume el ítem del inventario
## y transiciona la misión a READY_TO_TURN_IN para que el jugador vuelva con DrErgot.
func deliver_quest_step(quest_id: String) -> bool:
	var q := get_quest_data(quest_id)
	if q == null:
		return false
	
	var status := get_quest_status(quest_id)
	if status != QuestStatus.ACTIVE:
		return false
	
	# 1. Registrar primero que la entrega está hecha
	_quest_delivery_done[quest_id] = true
	
	# 2. Retirar el ítem de la mochila (sin provocar condiciones de carrera)
	if q.completion_type == "Entregar Ítem / Mejora" and q.consume_item_on_complete:
		var inv = get_node_or_null("/root/Inventory")
		if inv and inv.has_method("remove_upgrade"):
			inv.remove_upgrade(q.required_item_id)
	
	quest_step_delivered.emit(quest_id, q.target_npc_id)
	
	# 3. Actualizar estado según corresponda
	if q.return_to_giver:
		_quest_statuses[quest_id] = QuestStatus.READY_TO_TURN_IN
		quest_ready_to_turn_in.emit(quest_id)
		quest_updated.emit(quest_id)
	else:
		complete_quest(quest_id)
	
	return true


## Comprueba si los objetivos de una misión activa están completos
func check_quest_progress(quest_id: String) -> bool:
	var q := get_quest_data(quest_id)
	if q == null:
		return false
	
	var status := get_quest_status(quest_id)
	if status != QuestStatus.ACTIVE and status != QuestStatus.READY_TO_TURN_IN:
		return false
	
	var has_separate_target := not q.target_npc_id.is_empty() and not ids_match(q.target_npc_id, q.giver_npc_id)
	var ready := false
	
	if has_separate_target:
		# Si hay un NPC objetivo distinto del que dio la misión (ej. Funry da misión, Fongo es el objetivo):
		# El giver SOLO puede estar listo para entregar si return_to_giver es true Y el jugador ya interactuó con el objetivo.
		if q.return_to_giver:
			ready = is_delivery_done(quest_id)
		else:
			# Si no requiere volver con el giver, se completa directamente al hablar con el objetivo (Fongo).
			# El giver NUNCA se marca como READY_TO_TURN_IN.
			ready = false
	else:
		# Misión de un solo NPC (el giver y el objetivo son el mismo):
		match q.completion_type:
			"Entregar Ítem / Mejora":
				var inv = get_node_or_null("/root/Inventory")
				if inv and inv.has_method("has_upgrade"):
					ready = inv.has_upgrade(q.required_item_id)
			"Hablar con NPC":
				# No auto-completar solo por aceptar: requiere que el objetivo sea visitado
				ready = is_delivery_done(quest_id)
			"Evento / Flag":
				ready = has_event_flag(q.completion_event_flag)
			"Manual / Código":
				ready = (status == QuestStatus.READY_TO_TURN_IN)
	
	if ready and status != QuestStatus.READY_TO_TURN_IN:
		_quest_statuses[quest_id] = QuestStatus.READY_TO_TURN_IN
		quest_ready_to_turn_in.emit(quest_id)
		quest_updated.emit(quest_id)
		return true
	elif not ready and status == QuestStatus.READY_TO_TURN_IN:
		_quest_statuses[quest_id] = QuestStatus.ACTIVE
		quest_updated.emit(quest_id)
		return false
	
	return ready


## Finaliza y completa la misión con el DrErgot: otorga recompensas y desbloquea siguientes eventos
func complete_quest(quest_id: String) -> bool:
	var q := get_quest_data(quest_id)
	if q == null:
		return false
	
	var status := get_quest_status(quest_id)
	if status != QuestStatus.READY_TO_TURN_IN and status != QuestStatus.ACTIVE:
		if status == QuestStatus.ACTIVE and q.completion_type == "Hablar con NPC" and not q.return_to_giver:
			pass
		else:
			return false
	
	var inv = get_node_or_null("/root/Inventory")
	
	# 1. Consumir ítem si aún quedaba pendiente
	if q.completion_type == "Entregar Ítem / Mejora" and q.consume_item_on_complete and not is_delivery_done(quest_id):
		if inv and inv.has_method("remove_upgrade"):
			inv.remove_upgrade(q.required_item_id)
	
	# 2. Entregar recompensas
	if inv:
		if not q.reward_upgrade_id.is_empty():
			var r_name := q.reward_upgrade_name if not q.reward_upgrade_name.is_empty() else q.reward_upgrade_id
			inv.add_upgrade(q.reward_upgrade_id, r_name, q.reward_upgrade_desc, q.reward_upgrade_icon)
		if q.reward_ammo_slot >= 0 and q.reward_ammo_amount > 0:
			inv.add_ammo(q.reward_ammo_slot, q.reward_ammo_amount)
	
	# 3. Establecer bandera de evento opcional
	if not q.event_flag_to_set.is_empty():
		set_event_flag(q.event_flag_to_set, true)
	
	# 4. Establecer bandera implícita de esta misión completada
	set_event_flag("quest_completed_" + q.id, true)
	
	# 5. Cambiar estado a completado
	_quest_statuses[quest_id] = QuestStatus.COMPLETED
	quest_completed.emit(quest_id)
	quest_updated.emit(quest_id)
	
	# 6. Actualizar y desbloquear automáticamente misiones dependientes
	_refresh_all_quest_statuses()
	return true


# ==============================================================================
# BANDERAS DE EVENTOS (EVENT FLAGS)
# ==============================================================================

func set_event_flag(flag_name: String, value: bool = true) -> void:
	if flag_name.is_empty():
		return
	var prev = _event_flags.get(flag_name, false)
	_event_flags[flag_name] = value
	if prev != value:
		event_flag_changed.emit(flag_name, value)
		_refresh_all_quest_statuses()


func has_event_flag(flag_name: String) -> bool:
	if flag_name.is_empty():
		return true
	return _event_flags.get(flag_name, false) == true


# ==============================================================================
# CONSULTAS Y UTILIDADES PARA LA UI Y NPCS
# ==============================================================================

## Determina con precisión qué interacción le corresponde a un NPC según su rol (Giver o Target) y estado.
func get_npc_interaction_info(npc_id: String) -> Dictionary:
	var default_res := {
		"has_interaction": false,
		"action_type": "NONE",
		"quest": null,
		"indicator_symbol": "",
		"indicator_color": Color.WHITE
	}
	
	if npc_id.is_empty():
		return default_res
	
	var turn_in_q: QuestData = null
	var deliver_q: QuestData = null
	var offer_q: QuestData = null
	var waiting_q: QuestData = null
	var in_progress_q: QuestData = null
	var delivered_q: QuestData = null
	var completed_q: QuestData = null
	
	for q_id in _quest_definitions:
		var q: QuestData = _quest_definitions[q_id]
		var status := get_quest_status(q_id)
		if status == QuestStatus.ACTIVE or status == QuestStatus.READY_TO_TURN_IN:
			check_quest_progress(q_id)
			status = get_quest_status(q_id)
		
		# Comprobación insensible a mayúsculas y tolerante a alias (funry/runry)
		var is_giver := ids_match(q.giver_npc_id, npc_id) or (q.giver_npc_id.is_empty() and ids_match(q.target_npc_id, npc_id))
		var is_target := ids_match(q.target_npc_id, npc_id)
		var has_separate_target := not q.target_npc_id.is_empty() and not ids_match(q.target_npc_id, q.giver_npc_id)
		
		# 1. Turn-in: DrErgot / Munfy listo para recibir informe y entregar recompensa
		if is_giver and status == QuestStatus.READY_TO_TURN_IN:
			turn_in_q = q
			break
		
		# 2. Deliver: Funry con misión activa, entrega no hecha, y player tiene el ítem (solo si es receptor separado)
		if has_separate_target and is_target and status == QuestStatus.ACTIVE and not is_delivery_done(q_id):
			var has_item: bool = true
			if q.completion_type == "Entregar Ítem / Mejora":
				var inv = get_node_or_null("/root/Inventory")
				has_item = inv.has_upgrade(q.required_item_id) if (inv and inv.has_method("has_upgrade")) else false
			if has_item:
				deliver_q = q
			else:
				waiting_q = q
		
		# 3. Offer: DrErgot / Munfy con misión disponible para iniciar
		if is_giver and status == QuestStatus.AVAILABLE and offer_q == null:
			offer_q = q
		
		# 4. In Progress: DrErgot / Munfy esperando que el player haga la entrega o consiga el ítem
		if is_giver and status == QuestStatus.ACTIVE and not is_delivery_done(q_id) and in_progress_q == null:
			in_progress_q = q
		
		# 5. Delivery Done: Receptor tras haber recibido la medicina o entrega
		if has_separate_target and is_target and is_delivery_done(q_id) and delivered_q == null:
			delivered_q = q
		
		# 6. Completed: DrErgot / Munfy tras completar definitivamente la misión
		if is_giver and status == QuestStatus.COMPLETED and completed_q == null:
			completed_q = q
	
	if turn_in_q != null:
		return {
			"has_interaction": true,
			"action_type": "TURN_IN",
			"quest": turn_in_q,
			"indicator_symbol": "!",
			"indicator_color": Color(0.35, 0.95, 0.55) # Verde esmeralda
		}
	if deliver_q != null:
		return {
			"has_interaction": true,
			"action_type": "DELIVER",
			"quest": deliver_q,
			"indicator_symbol": "!",
			"indicator_color": Color(0.35, 0.95, 0.55) # Verde esmeralda
		}
	if offer_q != null:
		return {
			"has_interaction": true,
			"action_type": "OFFER",
			"quest": offer_q,
			"indicator_symbol": "?",
			"indicator_color": Color(0.98, 0.78, 0.25) # Oro / Ámbar
		}
	if waiting_q != null:
		return {
			"has_interaction": true,
			"action_type": "WAITING_DELIVERY",
			"quest": waiting_q,
			"indicator_symbol": "...",
			"indicator_color": Color(0.35, 0.85, 0.95) # Cian
		}
	if in_progress_q != null:
		return {
			"has_interaction": true,
			"action_type": "IN_PROGRESS",
			"quest": in_progress_q,
			"indicator_symbol": "...",
			"indicator_color": Color(0.35, 0.85, 0.95) # Cian
		}
	if delivered_q != null:
		return {
			"has_interaction": true,
			"action_type": "DELIVERY_DONE",
			"quest": delivered_q,
			"indicator_symbol": "",
			"indicator_color": Color.WHITE
		}
	if completed_q != null:
		return {
			"has_interaction": true,
			"action_type": "COMPLETED",
			"quest": completed_q,
			"indicator_symbol": "",
			"indicator_color": Color.WHITE
		}
	
	return default_res


## Devuelve la misión prioritaria para un NPC dado su ID (compatibilidad)
func get_quest_for_npc(npc_id: String) -> QuestData:
	var info := get_npc_interaction_info(npc_id)
	return info.quest


## Devuelve todas las misiones activas (en curso o listas para entregar)
func get_active_quests() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for q_id in _quest_definitions:
		var status := get_quest_status(q_id)
		if status == QuestStatus.ACTIVE or status == QuestStatus.READY_TO_TURN_IN:
			var q: QuestData = _quest_definitions[q_id]
			var delivery_done := is_delivery_done(q_id)
			
			var obj_text := q.objective_text
			if q.return_to_giver and delivery_done:
				obj_text = q.return_objective_text if not q.return_objective_text.is_empty() else ("Regresa con " + q.giver_npc_id)
			
			result.append({
				"id": q.id,
				"title": q.title,
				"description": q.description,
				"objective": obj_text,
				"status": status,
				"status_name": "¡Listo para informar!" if status == QuestStatus.READY_TO_TURN_IN else "En curso",
				"is_ready": (status == QuestStatus.READY_TO_TURN_IN)
			})
	return result


## Devuelve todas las misiones completadas
func get_completed_quests() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for q_id in _quest_definitions:
		var status := get_quest_status(q_id)
		if status == QuestStatus.COMPLETED:
			var q: QuestData = _quest_definitions[q_id]
			result.append({
				"id": q.id,
				"title": q.title,
				"description": q.description,
				"status": status,
				"status_name": "Completada"
			})
	return result


## Cantidad de misiones activas en curso
func get_active_quest_count() -> int:
	var count := 0
	for q_id in _quest_statuses:
		var st = _quest_statuses[q_id]
		if st == QuestStatus.ACTIVE or st == QuestStatus.READY_TO_TURN_IN:
			count += 1
	return count


func _can_unlock_internal(q: QuestData) -> bool:
	if not q.prerequisite_quest_id.is_empty():
		if get_quest_status(q.prerequisite_quest_id) != QuestStatus.COMPLETED:
			return false
	if not q.required_event_flag.is_empty():
		if not has_event_flag(q.required_event_flag):
			return false
	return true


func _refresh_all_quest_statuses() -> void:
	for q_id in _quest_definitions:
		var q: QuestData = _quest_definitions[q_id]
		var current_st := get_quest_status(q_id)
		
		if current_st == QuestStatus.LOCKED:
			if _can_unlock_internal(q):
				_quest_statuses[q_id] = QuestStatus.AVAILABLE
				quest_unlocked.emit(q_id)
				quest_updated.emit(q_id)
		elif current_st == QuestStatus.ACTIVE or current_st == QuestStatus.READY_TO_TURN_IN:
			check_quest_progress(q_id)


func _on_inventory_changed() -> void:
	for q_id in _quest_definitions:
		var st = get_quest_status(q_id)
		if st == QuestStatus.ACTIVE or st == QuestStatus.READY_TO_TURN_IN:
			check_quest_progress(q_id)


## Estado serializable de las misiones (para guardar partida).
func get_state() -> Dictionary:
	return {
		"statuses": _quest_statuses.duplicate(),
		"delivery": _quest_delivery_done.duplicate(),
		"flags": _event_flags.duplicate(),
	}


## Restaura un estado de get_state() (cargar partida). Las definiciones de misión las vuelven
## a registrar los NPC al cargar el nivel; aquí solo se recupera el progreso.
func restore_state(state: Dictionary) -> void:
	_quest_statuses.clear()
	_quest_delivery_done.clear()
	_event_flags.clear()

	var statuses = state.get("statuses", {})
	if statuses is Dictionary:
		for q_id in statuses:
			_quest_statuses[String(q_id)] = int(statuses[q_id])
	var delivery = state.get("delivery", {})
	if delivery is Dictionary:
		for q_id in delivery:
			_quest_delivery_done[String(q_id)] = bool(delivery[q_id])
	var flags = state.get("flags", {})
	if flags is Dictionary:
		for flag_name in flags:
			_event_flags[String(flag_name)] = bool(flags[flag_name])

	_refresh_all_quest_statuses()


## Reinicia el estado de misiones (para nueva partida)
func reset() -> void:
	_quest_statuses.clear()
	_quest_delivery_done.clear()
	_event_flags.clear()
	for q_id in _quest_definitions:
		var q: QuestData = _quest_definitions[q_id]
		if _can_unlock_internal(q):
			_quest_statuses[q_id] = QuestStatus.AVAILABLE
		else:
			_quest_statuses[q_id] = QuestStatus.LOCKED
