class_name AmmoType extends Resource
## Un tipo de munición. Crea hasta 3 recursos (Clic derecho en FileSystem > Nuevo recurso > AmmoType)
## y arrástralos a `ammo_types` del nodo Bow.

## Nombre que se muestra en el inventario.
@export var display_name: String = "Flechas"
## Imagen del HUD y del inventario. Vacío = una flecha dibujada por código.
@export var icon: Texture2D
## Escena de flecha que se dispara con este tipo. Vacío = usa `arrow_scene` del Bow.
## (Sirve para que cada munición tenga otro daño, dibujo, etc.)
@export var arrow_scene: PackedScene
## Flechas con las que empiezas una partida nueva.
@export var starting_amount: int = 0
## Máximo de flechas de este tipo que puedes llevar.
@export var max_amount: int = 99
