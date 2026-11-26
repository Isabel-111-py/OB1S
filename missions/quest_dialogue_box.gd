class_name QuestDialogueBox
extends CanvasLayer

## Ventana de diálogo e interacción de misiones con NPCs.
## Totalmente configurable: muestra los textos, diálogos, objetivos y botones
## exactamente como los haya definido el usuario en el Inspector, sin textos fijos obligatorios.

signal quest_accepted(quest_id: String)
signal quest_step_delivered(quest_id: String)
signal quest_turned_in(quest_id: String)
signal dialogue_closed()

@onready var panel_container: PanelContainer = $Root/Center/PanelContainer
@onready var npc_name_label: Label = $Root/Center/PanelContainer/Box/Header/NPCNameLabel
@onready var dialogue_label: Label = $Root/Center/PanelContainer/Box/DialogueLabel
@onready var quest_card: PanelContainer = $Root/Center/PanelContainer/Box/QuestCard
@onready var quest_title_label: Label = $Root/Center/PanelContainer/Box/QuestCard/VBox/QuestTitleLabel
@onready var quest_desc_label: Label = $Root/Center/PanelContainer/Box/QuestCard/VBox/QuestDescLabel
@onready var quest_obj_label: Label = $Root/Center/PanelContainer/Box/QuestCard/VBox/QuestObjLabel
@onready var quest_reward_label: Label = $Root/Center/PanelContainer/Box/QuestCard/VBox/QuestRewardLabel
@onready var btn_accept: Button = $Root/Center/PanelContainer/Box/Buttons/BtnAccept
@onready var btn_complete: Button = $Root/Center/PanelContainer/Box/Buttons/BtnComplete
@onready var btn_close: Button = $Root/Center/PanelContainer/Box/Buttons/BtnClose

var current_quest_id: String = ""
var current_action_mode: String = "INFO" # "OFFER", "DELIVER", "TURN_IN", "INFO"
var current_npc = null


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	
	btn_accept.pressed.connect(_on_accept_pressed)
	btn_complete.pressed.connect(_on_complete_pressed)
	btn_close.pressed.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


## Muestra un diálogo y adapta los textos y botones según la configuración del usuario
func show_dialogue(npc_name: String, text: String, quest_data: QuestData = null, action_mode: String = "INFO", npc_ref = null) -> void:
	current_npc = npc_ref
	current_action_mode = action_mode
	
	# 1. Nombre del NPC
	if not npc_name.is_empty():
		npc_name_label.text = npc_name
		npc_name_label.visible = true
	else:
		npc_name_label.visible = false
	
	# 2. Diálogo principal del NPC (personalizado por el usuario)
	if not text.is_empty():
		dialogue_label.text = text
		dialogue_label.visible = true
	else:
		dialogue_label.visible = false
	
	btn_accept.visible = false
	btn_complete.visible = false
	btn_close.visible = true
	
	# 3. Tarjeta de misión (solo si hay datos de misión)
	if quest_data != null:
		current_quest_id = quest_data.id
		quest_card.visible = true
		
		# Título de la misión
		if not quest_data.title.is_empty():
			quest_title_label.text = "📜 " + quest_data.title
			quest_title_label.visible = true
		else:
			quest_title_label.visible = false
		
		# Descripción
		if not quest_data.description.is_empty():
			quest_desc_label.text = quest_data.description
			quest_desc_label.visible = true
		else:
			quest_desc_label.visible = false
		
		# Estado y Objetivo
		var status := QuestManager.get_quest_status(quest_data.id)
		var is_delivered := QuestManager.is_delivery_done(quest_data.id)
		var obj_str := ""
		
		if status == QuestManager.QuestStatus.COMPLETED:
			obj_str = "🎯 " + (quest_data.status_completed_text if not quest_data.status_completed_text.is_empty() else "Misión Completada ✓")
		elif action_mode == "TURN_IN" or (quest_data.return_to_giver and is_delivered):
			if not quest_data.return_objective_text.is_empty():
				obj_str = "🎯 " + quest_data.return_objective_text + " [Listo para completar ✓]"
			else:
				obj_str = "🎯 Habla con %s para completar [Listo ✓]" % npc_name
		elif action_mode == "DELIVER":
			if not quest_data.objective_text.is_empty():
				obj_str = "🎯 " + quest_data.objective_text + " [Listo para entregar ✓]"
			else:
				obj_str = "🎯 Entrega a %s [Listo ✓]" % npc_name
		else:
			if not quest_data.objective_text.is_empty():
				obj_str = "🎯 " + quest_data.objective_text
				if quest_data.completion_type == "Entregar Ítem / Mejora":
					var has_item: bool = false
					if has_node("/root/Inventory"):
						has_item = get_node("/root/Inventory").has_upgrade(quest_data.required_item_id)
					obj_str += " [%s]" % ("Listo para entregar ✓" if has_item else "En curso...")
		
		if not obj_str.is_empty():
			quest_obj_label.text = obj_str
			quest_obj_label.visible = true
		else:
			quest_obj_label.visible = false
		
		# Recompensas
		if status == QuestManager.QuestStatus.COMPLETED:
			quest_reward_label.text = "🎁 Recompensas: ¡Reclamadas! ✓"
			quest_reward_label.visible = true
		else:
			var rew_parts := []
			if not quest_data.reward_upgrade_id.is_empty():
				var r_name := quest_data.reward_upgrade_name if not quest_data.reward_upgrade_name.is_empty() else quest_data.reward_upgrade_id
				rew_parts.append(r_name)
			if quest_data.reward_ammo_slot >= 0 and quest_data.reward_ammo_amount > 0:
				rew_parts.append("+%d Flechas" % quest_data.reward_ammo_amount)
			
			if not rew_parts.is_empty():
				quest_reward_label.text = "🎁 Recompensa: " + ", ".join(rew_parts)
				quest_reward_label.visible = true
			else:
				quest_reward_label.visible = false
		
		# 4. Textos de los botones personalizables por el usuario
		var custom_accept := _get_custom_button_text("btn_accept_text", quest_data, npc_ref)
		var custom_deliver := _get_custom_button_text("btn_deliver_text", quest_data, npc_ref)
		var custom_complete := _get_custom_button_text("btn_complete_text", quest_data, npc_ref)
		var custom_close := _get_custom_button_text("btn_close_text", quest_data, npc_ref)
		
		match action_mode:
			"OFFER":
				btn_accept.visible = true
				btn_accept.text = custom_accept if not custom_accept.is_empty() else "Aceptar Misión"
				btn_close.text = custom_close if not custom_close.is_empty() else "Rechazar"
			"DELIVER":
				btn_complete.visible = true
				if not custom_deliver.is_empty():
					btn_complete.text = custom_deliver
				elif quest_data.completion_type == "Hablar con NPC":
					btn_complete.text = "Hablar con %s" % (npc_name if not npc_name.is_empty() else "personaje")
				else:
					var item_label := quest_data.grant_item_name if not quest_data.grant_item_name.is_empty() else (quest_data.required_item_id if not quest_data.required_item_id.is_empty() else "Objeto")
					btn_complete.text = "Entregar %s" % item_label
				btn_close.text = custom_close if not custom_close.is_empty() else "Cerrar"
			"TURN_IN":
				btn_complete.visible = true
				btn_complete.text = custom_complete if not custom_complete.is_empty() else "Completar Misión"
				btn_close.text = custom_close if not custom_close.is_empty() else "Cerrar"
			_:
				btn_close.text = custom_close if not custom_close.is_empty() else "Cerrar"
	else:
		current_quest_id = ""
		quest_card.visible = false
		var custom_close := _get_custom_button_text("btn_close_text", null, npc_ref)
		btn_close.text = custom_close if not custom_close.is_empty() else "Cerrar"
	
	visible = true
	if btn_accept.visible:
		btn_accept.grab_focus()
	elif btn_complete.visible:
		btn_complete.grab_focus()
	else:
		btn_close.grab_focus()


func _get_custom_button_text(prop_name: String, q_data: QuestData, npc_ref) -> String:
	# 1. Prioridad: Lo que el usuario haya escrito en el NPC (NPCQuestGiver)
	if npc_ref != null and npc_ref.get(prop_name) != null:
		var val: String = str(npc_ref.get(prop_name))
		if not val.is_empty():
			return val
	# 2. Segunda prioridad: Lo que el usuario haya escrito en QuestData
	if q_data != null:
		var mapped_prop := ""
		match prop_name:
			"btn_accept_text": mapped_prop = "button_accept_text"
			"btn_deliver_text": mapped_prop = "button_deliver_text"
			"btn_complete_text": mapped_prop = "button_complete_text"
		if not mapped_prop.is_empty() and q_data.get(mapped_prop) != null:
			var q_val: String = str(q_data.get(mapped_prop))
			if not q_val.is_empty():
				return q_val
	return ""


func close() -> void:
	visible = false
	dialogue_closed.emit()


func _on_accept_pressed() -> void:
	if not current_quest_id.is_empty():
		QuestManager.accept_quest(current_quest_id)
		quest_accepted.emit(current_quest_id)
	close()


func _on_complete_pressed() -> void:
	if not current_quest_id.is_empty():
		if current_action_mode == "DELIVER":
			QuestManager.deliver_quest_step(current_quest_id)
			quest_step_delivered.emit(current_quest_id)
		else:
			QuestManager.complete_quest(current_quest_id)
			quest_turned_in.emit(current_quest_id)
	close()
