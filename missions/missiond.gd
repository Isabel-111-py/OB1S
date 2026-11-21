extends Area2D

@export var quest_to_give: Quest 
var is_rob_near: bool = false
var dialogue_finished: bool = false # Para evitar dar la misión múltiples veces si ya se completó el diálogo

# 1. Rastrear si Rob está cerca
func _on_body_entered(body: Node2D) -> void:
	if body.name == "rob":
		is_rob_near = true

func _on_body_exited(body: Node2D) -> void:
	if body.name == "rob":
		is_rob_near = false

# 2. Detectar el clic sobre el NPC
func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	# Verificamos si el evento es un clic izquierdo presionado
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if is_rob_near and not dialogue_finished:
			iniciar_dialogo()

# 3. Lógica de tu diálogo
func iniciar_dialogo() -> void:
	# Aquí llamarías a tu sistema de diálogos (ej. Dialogic o un CanvasLayer propio)
	print("NPC: ¡Hola Rob! Las máquinas en las ruinas se han vuelto locas. ¿Puedes ayudarme?")
	
	# Suponiendo que el diálogo termina inmediatamente en este ejemplo:
	entregar_mision()

func entregar_mision() -> void:
	QuestManager.start_quest(quest_to_give)
	dialogue_finished = true # Marcamos que ya hablamos para no repetir
