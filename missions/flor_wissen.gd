class_name FlorWissen
extends Pickup

## FlorWissen:
## Flor mística y luminosa recolectada en el nivel volcánico (lvl5_volcano).
## Funciona como objeto recogible e ítem de inventario / misión para futuras misiones.

func _init() -> void:
	kind = Kind.UPGRADE
	upgrade_id = &"flor_wissen"
	upgrade_name = "Flor Wissen"
	upgrade_description = "Una extraña y hermosa flor mística hallada en las profundidades volcánicas."


func _ready() -> void:
	kind = Kind.UPGRADE
	if upgrade_id.is_empty():
		upgrade_id = &"flor_wissen"
	if upgrade_name.is_empty():
		upgrade_name = "Flor Wissen"
	if upgrade_description.is_empty():
		upgrade_description = "Una extraña y hermosa flor mística hallada en las profundidades volcánicas."
	if icon == null and ResourceLoader.exists("res://Decoration/flor.png"):
		icon = load("res://Decoration/flor.png")
	
	# Asegurar que el área detecta al jugador (capas 1 y 2)
	collision_layer = 0
	collision_mask |= 1 | 2
	
	super._ready()
