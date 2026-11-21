# quest.gd
extends Resource
class_name Quest

enum Status { NOT_STARTED, ACTIVE, COMPLETED, FAILED }

@export var id: String = "mission_01"
@export var title: String = "Nueva Misión"
@export_multiline var description: String = "Descripción de lo que debes hacer."
@export var current_amount: int = 0
@export var target_amount: int = 1 # Útil para misiones de recolectar o matar X cosas

var status: Status = Status.NOT_STARTED
