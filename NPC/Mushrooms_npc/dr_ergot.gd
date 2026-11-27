class_name DrErgot
extends NPCBase

## Controlador para DrErgot:
## Gestiona la ubicación de DrErgot entre la entrada del nivel y su laboratorio
## según el progreso de la misión "Llevarle_a_ergot" de Munfy.

@export_group("Ubicaciones de Misión")
## Posición original en la entrada del nivel (cuando la misión de Munfy no ha comenzado)
@export var entrance_position: Vector2 = Vector2(0, 341)

## Posición dentro del laboratorio al sur de la ciudad
@export var lab_position: Vector2 = Vector2(7800, 810)

## Marcador opcional en la escena para posicionar visualmente el laboratorio arrastrándolo en el editor 2D
@export var lab_marker: Node2D

## Radio de patrulla dentro del laboratorio (más contenido para espacios cerrados)
@export var lab_patrol_radius: float = 40.0

## ID de la misión de Munfy que activa el traslado de Ergot al laboratorio
@export var lab_quest_id: String = "Llevarle_a_ergot"

## Si está activo, Ergot solo aparece cuando la misión está en curso o completada (se oculta en la entrada).
## Si está desactivado (por defecto), Ergot está en la entrada al inicio y se traslada al laboratorio cuando la misión inicia.
@export var only_appear_during_quest: bool = false

var _default_patrol_radius: float = 80.0


func _ready() -> void:
	_default_patrol_radius = patrol_radius
	super._ready()
	
	# Si no se asignó un marcador en el inspector, buscar "Laboratorio_DrErgot" o "LabMarker" en la escena
	if lab_marker == null and get_parent() != null:
		lab_marker = get_parent().get_node_or_null("Laboratorio_DrErgot") as Node2D
		if lab_marker == null:
			lab_marker = get_parent().get_node_or_null("LabMarker") as Node2D
	
	if lab_marker != null and is_instance_valid(lab_marker):
		lab_position = lab_marker.global_position
	
	_update_ergot_location()
	
	# Conectar a señales de QuestManager para reubicarlo automáticamente en tiempo real
	if QuestManager:
		if not QuestManager.quest_accepted.is_connected(_on_quest_status_changed):
			QuestManager.quest_accepted.connect(_on_quest_status_changed)
		if not QuestManager.quest_updated.is_connected(_on_quest_status_changed):
			QuestManager.quest_updated.connect(_on_quest_status_changed)
		if not QuestManager.quest_completed.is_connected(_on_quest_status_changed):
			QuestManager.quest_completed.connect(_on_quest_status_changed)


func _on_quest_status_changed(quest_id: String) -> void:
	if quest_id == lab_quest_id or QuestManager.normalize_id(quest_id) == QuestManager.normalize_id(lab_quest_id):
		_update_ergot_location()


func _update_ergot_location() -> void:
	if lab_marker != null and is_instance_valid(lab_marker):
		lab_position = lab_marker.global_position
	
	var in_lab := false
	if QuestManager:
		in_lab = QuestManager.is_quest_active(lab_quest_id) or \
		         QuestManager.is_quest_ready_to_turn_in(lab_quest_id) or \
		         QuestManager.is_quest_completed(lab_quest_id)
	
	if only_appear_during_quest and not in_lab:
		# Ocultar completamente y desactivar colisiones si no debe verse antes
		visible = false
		set_physics_process(false)
		collision_layer = 0
		collision_mask = 0
		for child in get_children():
			if child is Area2D:
				child.monitoring = false
				child.monitorable = false
		return
	
	visible = true
	set_physics_process(true)
	collision_layer = 1
	collision_mask = 1
	for child in get_children():
		if child is Area2D:
			child.monitoring = true
			child.monitorable = true
	
	if in_lab:
		global_position = lab_position
		start_position = lab_position
		patrol_radius = lab_patrol_radius
	else:
		global_position = entrance_position
		start_position = entrance_position
		patrol_radius = _default_patrol_radius
	
	velocity = Vector2.ZERO
	_enter_idle_state()
	
	# Notificar a los componentes de interacción / bocadillos que la posición cambió
	for child in get_children():
		if child is NPCQuestGiver and child.has_method("_update_indicator"):
			child._update_indicator()
