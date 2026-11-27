@tool
class_name NPCQuestGiver
extends Area2D

## Componente para otorgar o recibir misiones con cualquier NPC del juego.
## 100% Personalizable: No contiene diálogos forzados ni fijos. Todos los textos,
## saludos de proximidad, diálogos completos y botones se configuran en el Inspector.

@export_group("Rol e Identidad del NPC")
## Define si este NPC asigna misiones (Giver) o solo recibe objetos (Receiver).
## Los Receivers solo esperan entregas y nunca sobreescriben misiones.
@export_enum("Giver (Asigna misión)", "Receiver (Solo recibe ítem / entrega)") var npc_role: String = "Giver (Asigna misión)":
	set(val):
		npc_role = val
		_register_or_update_quest()

## Nombre visible del NPC en diálogos y bocadillos (ej. "DrErgot", "Funry", "Guardia").
@export var npc_name: String = "NPC":
	set(val):
		npc_name = val

## Identificador único del NPC para enlazar objetivos de misiones (ej. "dr_ergot", "funry").
@export var npc_id: String = "npc_1":
	set(val):
		npc_id = val
		_register_or_update_quest()


@export_group("Misión Asignada (Solo para rol Giver)")
## Si prefieres crear un archivo .tres de QuestData en tu carpeta de recursos, asígnalo aquí.
@export var custom_quest_resource: QuestData = null:
	set(val):
		custom_quest_resource = val
		_register_or_update_quest()

## Configuración rápida si defines la misión directamente en este NPC:
@export var quest_id: String = ""
@export var quest_title: String = ""
@export_multiline var quest_description: String = ""
@export var quest_objective: String = ""

## ID del NPC destino que debe recibir el ítem (vacío si este mismo NPC recibe la misión)
@export var target_npc_id: String = ""
## Si es verdadero, el jugador debe volver con este NPC tras entregar el objeto al target_npc
@export var return_to_giver: bool = false
## Texto del objetivo cuando el jugador debe regresar con este NPC
@export var return_objective: String = ""

## Ítem que este NPC le entrega al jugador al aceptar la misión (opcional)
@export var grant_item_on_accept: StringName = &""
@export var grant_item_name: String = ""
@export_multiline var grant_item_desc: String = ""
@export var grant_item_icon: Texture2D

@export var prerequisite_quest_id: String = ""
@export var required_event_flag: String = ""

@export_enum("Entregar Ítem / Mejora", "Hablar con NPC", "Evento / Flag", "Manual / Código") var completion_type: String = "Entregar Ítem / Mejora"
@export var required_item_id: String = ""
@export var consume_item_on_complete: bool = true

@export_range(-1, 2) var reward_ammo_slot: int = -1
@export var reward_ammo_amount: int = 0
@export var reward_upgrade_id: String = ""
@export var reward_upgrade_name: String = ""
@export_multiline var reward_upgrade_desc: String = ""
@export var reward_upgrade_icon: Texture2D
@export var event_flag_to_set: String = ""


@export_group("Saludos de Proximidad (Bocadillo Flotante)")
## Deja vacío cualquier saludo que no desees que aparezca en el bocadillo.
## Mensaje cuando este NPC ofrece una nueva misión ('?')
@export var greeting_available: String = ""
## Mensaje del Giver mientras el jugador realiza la misión ('...')
@export var greeting_in_progress: String = ""
## Mensaje del Giver cuando el jugador completó la tarea y regresa a informar ('!')
@export var greeting_ready: String = ""
## Mensaje cuando la misión ya fue completamente finalizada
@export var greeting_completed: String = ""
## Mensaje si la misión aún está bloqueada por prerrequisitos
@export var greeting_locked: String = ""
## Mensaje del Receptor mientras espera que el jugador le traiga el objeto ('...')
@export var greeting_waiting_delivery: String = ""
## Mensaje del Receptor cuando el jugador llega con el objeto en mano ('!')
@export var greeting_can_deliver: String = ""
## Mensaje del Receptor tras haber recibido el objeto
@export var greeting_after_delivered: String = ""


@export_group("Diálogos Completos de Interacción (Ventana Emergente)")
## Escribe tus propios diálogos para cada situación. Si dejas uno vacío, se oculta el texto.
## 1. Diálogo cuando este NPC ofrece la misión por primera vez (Giver)
@export_multiline var dialogue_offer: String = ""
## 2. Diálogo del Giver mientras la misión sigue en curso
@export_multiline var dialogue_in_progress: String = ""
## 3. Diálogo del Giver cuando el jugador regresa tras cumplir el objetivo
@export_multiline var dialogue_ready: String = ""
## 4. Diálogo del Giver después de que la misión ha sido cobrada y finalizada
@export_multiline var dialogue_completed: String = ""
## 5. Diálogo cuando la misión aún no está desbloqueada
@export_multiline var dialogue_locked: String = ""
## 6. Diálogo del Receptor si el jugador habla con él sin tener el objeto requerido
@export_multiline var dialogue_waiting_delivery: String = ""
## 7. Diálogo del Receptor cuando el jugador le entrega el objeto requerido
@export_multiline var dialogue_can_deliver: String = ""
## 8. Diálogo del Receptor tras haber recibido el objeto
@export_multiline var dialogue_after_delivered: String = ""


@export_group("Botones de Acción Personalizados (Opcional)")
## Si los dejas vacíos, usan los textos estándar ("Aceptar Misión", "Entregar", "Completar Misión", "Cerrar")
@export var btn_accept_text: String = ""
@export var btn_deliver_text: String = ""
@export var btn_complete_text: String = ""
@export var btn_close_text: String = ""


@export_group("Posición y Ajustes")
## Altura relativa del indicador '?'/'!' y del bocadillo respecto al centro del NPC.
@export var indicator_height: float = 38.0


# --- Nodos Hijos ---
@onready var indicator_node: Node2D = $Indicator
@onready var speech_bubble: Node2D = $SpeechBubble
@onready var speech_label: Label = $SpeechBubble/BubblePanel/Label
@onready var proximity_area: Area2D = $ProximityArea
@onready var click_area: Area2D = self

# --- Variables de Estado Interno ---
var player_in_proximity: bool = false
var player_in_click_range: bool = false
var anim_time: float = 0.0
var _internal_quest_data: QuestData = null
var _dialogue_box: QuestDialogueBox = null


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	
	# Sincronizar automáticamente npc_name y npc_id con los hermanos bajo el mismo padre si no se definieron
	for sibling in _get_sibling_givers():
		if sibling != self:
			if (npc_id == "npc_1" or npc_id.is_empty()) and not sibling.npc_id.is_empty() and sibling.npc_id != "npc_1":
				npc_id = sibling.npc_id
			if (npc_name == "NPC" or npc_name.is_empty()) and not sibling.npc_name.is_empty() and sibling.npc_name != "NPC":
				npc_name = sibling.npc_name
	
	_register_or_update_quest()
	
	proximity_area.body_entered.connect(_on_proximity_entered)
	proximity_area.body_exited.connect(_on_proximity_exited)
	
	body_entered.connect(_on_interaction_entered)
	body_exited.connect(_on_interaction_exited)
	
	QuestManager.quest_registered.connect(_on_quest_state_changed.unbind(1))
	QuestManager.quest_unlocked.connect(_on_quest_state_changed.unbind(1))
	QuestManager.quest_accepted.connect(_on_quest_state_changed.unbind(1))
	QuestManager.quest_updated.connect(_on_quest_state_changed.unbind(1))
	QuestManager.quest_step_delivered.connect(_on_quest_state_changed.unbind(2))
	QuestManager.quest_ready_to_turn_in.connect(_on_quest_state_changed.unbind(1))
	QuestManager.quest_completed.connect(_on_quest_state_changed.unbind(1))
	
	if speech_bubble:
		speech_bubble.visible = false
	
	_update_indicator()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	anim_time += delta
	
	if indicator_node and indicator_node.visible:
		var bob := sin(anim_time * 4.0) * 2.5
		indicator_node.position.y = -indicator_height + bob
	
	if speech_bubble and speech_bubble.visible:
		var bob_b := sin(anim_time * 3.0) * 1.5
		speech_bubble.position.y = -indicator_height - 24.0 + bob_b


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	
	if not (player_in_proximity or player_in_click_range):
		return
	
	if event is InputEventMouseButton and event.pressed and not event.is_echo():
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if _is_mouse_over_npc(event.position) or player_in_click_range:
				get_viewport().set_input_as_handled()
				interact_with_npc()
				return
	
	if _is_interact_action(event) and player_in_click_range:
		get_viewport().set_input_as_handled()
		interact_with_npc()


func _is_mouse_over_npc(screen_pos: Vector2) -> bool:
	var global_mouse := get_global_mouse_position()
	return global_position.distance_to(global_mouse) <= 28.0


func _is_interact_action(event: InputEvent) -> bool:
	if not event.is_pressed() or event.is_echo():
		return false
	if InputMap.has_action("interact") and event.is_action_pressed("interact"):
		return true
	if event.is_action_pressed("ui_accept"):
		return true
	if event is InputEventKey and event.physical_keycode in [KEY_E, KEY_W]:
		return true
	return false


# ==============================================================================
# INTERACCIÓN Y DIÁLOGOS
# ==============================================================================

## Obtiene todos los componentes NPCQuestGiver que pertenecen al mismo NPC (hermanos en el mismo padre)
func _get_sibling_givers() -> Array[NPCQuestGiver]:
	var result: Array[NPCQuestGiver] = []
	var p = get_parent()
	if not p:
		result.append(self)
		return result
	for child in p.get_children():
		if child is NPCQuestGiver:
			result.append(child)
	if result.is_empty():
		result.append(self)
	return result


## Determina cuál de los componentes hermanos es el responsable de manejar la interacción actual
func _get_active_handler(info: Dictionary) -> NPCQuestGiver:
	var siblings := _get_sibling_givers()
	if siblings.size() <= 1:
		return self
	
	if info.quest != null:
		var q_id: String = info.quest.id
		
		# 1. Si la acción es TURN_IN, OFFER, o IN_PROGRESS: buscar el Giver de esa misión específica
		if info.action_type in ["TURN_IN", "OFFER", "IN_PROGRESS"]:
			for s in siblings:
				if not s.npc_role.begins_with("Receiver") and s.quest_id == q_id:
					return s
		
		# 2. Si la acción es entrega hacia este NPC (DELIVER, WAITING_DELIVERY, DELIVERY_DONE):
		if info.action_type in ["DELIVER", "WAITING_DELIVERY", "DELIVERY_DONE"]:
			# Buscar primero coincidencia exacta por quest_id
			for s in siblings:
				if s.quest_id == q_id:
					return s
			# Buscar un nodo con diálogo de entrega configurado
			for s in siblings:
				if not s.dialogue_can_deliver.is_empty():
					return s
			for s in siblings:
				if s.npc_role.begins_with("Receiver"):
					return s
		
		# 3. Coincidencia directa por quest_id en cualquier caso
		for s in siblings:
			if s.quest_id == q_id:
				return s
		
		# 4. Si la misión fue completada recientemente
		if info.action_type == "COMPLETED":
			for s in siblings:
				if s.quest_id == q_id:
					return s
	
	# Si no hay misión activa, buscar el nodo que tenga nombre personalizado (no el genérico "NPC")
	for s in siblings:
		if not s.quest_id.is_empty() and s.npc_name != "NPC" and not s.npc_name.is_empty():
			return s
	
	# Fallback: el primer hermano en la jerarquía
	return siblings[0]


## Se llama cuando el jugador hace clic derecho o presiona [E]
func interact_with_npc() -> void:
	# Asegurarse de tener el npc_id y npc_name sincronizados
	if npc_id == "npc_1" or npc_id.is_empty():
		for s in _get_sibling_givers():
			if s.npc_id != "npc_1" and not s.npc_id.is_empty():
				npc_id = s.npc_id
				npc_name = s.npc_name
				break
	
	var info := QuestManager.get_npc_interaction_info(npc_id)
	var active := _get_active_handler(info)
	if active != self:
		active.interact_with_npc()
		return
	
	_pause_npc_patrol()
	
	if speech_bubble:
		speech_bubble.visible = false
	
	var dlg_text := ""
	var action_mode := "INFO"
	
	match info.action_type:
		"OFFER":
			dlg_text = dialogue_offer
			action_mode = "OFFER"
		"DELIVER":
			dlg_text = dialogue_can_deliver
			action_mode = "DELIVER"
		"TURN_IN":
			dlg_text = dialogue_ready
			action_mode = "TURN_IN"
		"WAITING_DELIVERY":
			dlg_text = dialogue_waiting_delivery
			action_mode = "INFO"
		"IN_PROGRESS":
			dlg_text = dialogue_in_progress
			action_mode = "INFO"
		"DELIVERY_DONE":
			dlg_text = dialogue_after_delivered
			action_mode = "INFO"
		"COMPLETED":
			dlg_text = dialogue_completed
			action_mode = "INFO"
		_:
			dlg_text = dialogue_locked
			action_mode = "INFO"
	
	var box := _get_or_create_dialogue_box()
	box.show_dialogue(npc_name, dlg_text, info.quest, action_mode, self)
	if not box.is_connected("dialogue_closed", _resume_npc_patrol):
		box.dialogue_closed.connect(_resume_npc_patrol, CONNECT_ONE_SHOT)


func _pause_npc_patrol() -> void:
	var parent = get_parent()
	if parent:
		if parent.get("speed") != null:
			parent.set_meta("_prev_speed", parent.get("speed"))
			parent.set("speed", 0.0)
		if parent.get("velocity") != null:
			parent.set("velocity", Vector2.ZERO)
		var player = get_tree().get_first_node_in_group("player")
		if player and parent.get("anim") != null:
			var anim = parent.get("anim") as AnimatedSprite2D
			if anim:
				anim.flip_h = (player.global_position.x < parent.global_position.x)


func _resume_npc_patrol() -> void:
	var parent = get_parent()
	if parent and parent.has_meta("_prev_speed"):
		parent.set("speed", parent.get_meta("_prev_speed"))
		parent.remove_meta("_prev_speed")
	_update_indicator()


func _get_or_create_dialogue_box() -> QuestDialogueBox:
	if _dialogue_box != null and is_instance_valid(_dialogue_box):
		return _dialogue_box
	
	var existing = get_tree().root.get_node_or_null("QuestDialogueBox")
	if existing is QuestDialogueBox:
		_dialogue_box = existing
		return _dialogue_box
	
	var scene = load("res://missions/QuestDialogueBox.tscn") as PackedScene
	if scene:
		_dialogue_box = scene.instantiate() as QuestDialogueBox
		get_tree().root.add_child(_dialogue_box)
		return _dialogue_box
	
	return null


# ==============================================================================
# DETECCIÓN DE PROXIMIDAD Y BOCADILLO DE DIÁLOGO
# ==============================================================================

func _on_proximity_entered(body: Node2D) -> void:
	if not _is_player(body):
		return
	player_in_proximity = true
	_show_speech_bubble()


func _on_proximity_exited(body: Node2D) -> void:
	if not _is_player(body):
		return
	player_in_proximity = false
	if speech_bubble:
		speech_bubble.visible = false


func _on_interaction_entered(body: Node2D) -> void:
	if _is_player(body):
		player_in_click_range = true


func _on_interaction_exited(body: Node2D) -> void:
	if _is_player(body):
		player_in_click_range = false


func _show_speech_bubble() -> void:
	if not speech_bubble or not speech_label:
		return
	
	var info := QuestManager.get_npc_interaction_info(npc_id)
	var active := _get_active_handler(info)
	if active != self:
		speech_bubble.visible = false
		return
	
	var text := ""
	
	match info.action_type:
		"OFFER":
			text = greeting_available
		"DELIVER":
			text = greeting_can_deliver
		"TURN_IN":
			text = greeting_ready
		"WAITING_DELIVERY":
			text = greeting_waiting_delivery
		"IN_PROGRESS":
			text = greeting_in_progress
		"DELIVERY_DONE":
			text = greeting_after_delivered
		"COMPLETED":
			text = greeting_completed
		_:
			text = greeting_locked
	
	speech_label.text = text
	# Si el texto está vacío, el bocadillo no se muestra
	speech_bubble.visible = not text.is_empty()


# ==============================================================================
# INDICADOR VISUAL SOBRE LA CABEZA ('?' / '!' / '...')
# ==============================================================================

func _update_indicator() -> void:
	if not indicator_node:
		return
	
	var info := QuestManager.get_npc_interaction_info(npc_id)
	var active := _get_active_handler(info)
	if active != self:
		indicator_node.visible = false
		return
	
	if info.indicator_symbol != "":
		indicator_node.visible = true
		_draw_indicator_symbol(info.indicator_symbol, info.indicator_color)
	else:
		indicator_node.visible = false


func _draw_indicator_symbol(symbol: String, color: Color) -> void:
	var label = indicator_node.get_node_or_null("Label") as Label
	if label:
		label.text = symbol
		label.modulate = color


func _on_quest_state_changed() -> void:
	_update_indicator()
	if player_in_proximity and speech_bubble and speech_bubble.visible:
		_show_speech_bubble()


func _register_or_update_quest() -> void:
	# Si este NPC es Receptor, nunca registra ni sobrescribe misiones
	if npc_role == "Receiver (Solo recibe ítem / entrega)":
		_internal_quest_data = null
		return
	
	if custom_quest_resource != null:
		_internal_quest_data = custom_quest_resource
	elif not quest_id.is_empty():
		var q := QuestData.new()
		q.id = quest_id
		q.title = quest_title
		q.description = quest_description
		q.objective_text = quest_objective
		q.giver_npc_id = npc_id if not npc_id.is_empty() else "npc_1"
		q.target_npc_id = target_npc_id if not target_npc_id.is_empty() else npc_id
		q.return_to_giver = return_to_giver
		q.return_objective_text = return_objective
		q.grant_item_on_accept = grant_item_on_accept
		q.grant_item_name = grant_item_name
		q.grant_item_desc = grant_item_desc
		q.grant_item_icon = grant_item_icon
		q.prerequisite_quest_id = prerequisite_quest_id
		q.required_event_flag = required_event_flag
		q.completion_type = completion_type
		q.required_item_id = required_item_id
		q.consume_item_on_complete = consume_item_on_complete
		q.reward_ammo_slot = reward_ammo_slot
		q.reward_ammo_amount = reward_ammo_amount
		q.reward_upgrade_id = reward_upgrade_id
		q.reward_upgrade_name = reward_upgrade_name
		q.reward_upgrade_desc = reward_upgrade_desc
		q.reward_upgrade_icon = reward_upgrade_icon
		q.event_flag_to_set = event_flag_to_set
		_internal_quest_data = q
	
	if _internal_quest_data and is_inside_tree() and not Engine.is_editor_hint():
		QuestManager.register_quest(_internal_quest_data)


func _is_player(body: Node2D) -> bool:
	if body is CharacterBody2D:
		if body.is_in_group("player") or body.is_in_group("Player"):
			return true
		if body.name == "Player" or body.name.begins_with("Player"):
			return true
	return false
