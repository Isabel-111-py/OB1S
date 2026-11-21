extends Area2D

@export var quest_to_give: Quest 
var is_rob_near: bool = false
var dialogue_finished: bool = false

# 1. Rastrear si Rob está cerca (Nombres ajustados a tus señales)
func _on_area_2d_body_entered(body: Node2D) -> void:
	if body.name == "rob":
		is_rob_near = true
		print("Rob está cerca del NPC") # Para comprobar en consola

func _on_area_2d_body_exited(body: Node2D) -> void:
	if body.name == "rob":
		is_rob_near = false

# 2. Detectar el clic sobre el NPC
func _on_area_2d_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if is_rob_near and not dialogue_finished:
			iniciar_dialogo()

# 3. Lógica de tu diálogo
func iniciar_dialogo() -> void:
	print("NPC: ¡Hola Rob! Necesito tu ayuda con una misión.")
	entregar_mision()

func entregar_mision() -> void:
	QuestManager.start_quest(quest_to_give)
	dialogue_finished = true
