extends Node
## Autoload "Inventory": munición (3 espacios) y mejoras que el jugador recoge.
## Como es un autoload, se conserva al cambiar de nivel.
## Registro: Proyecto > Configuración del proyecto > Globales (Autoload) > nombre "Inventory".

const SLOT_COUNT: int = 3
## Colores de prueba de la flecha dibujada por código (cuando un tipo no tiene icono).
const DEFAULT_TINTS: Array[Color] = [Color(1.0, 1.0, 1.0), Color(1.0, 0.65, 0.25), Color(0.45, 0.85, 1.0)]
## Valores de prueba si no defines tipos de munición en el Bow.
const DEFAULT_STARTING: Array[int] = [10, 5, 5]

signal ammo_changed(slot: int, count: int)
signal ammo_selected(slot: int)
## Se emite cuando cambian las definiciones (nombres, iconos) de los tipos de munición.
signal ammo_types_changed
signal upgrade_added(id: StringName)

var ammo_types: Array[AmmoType] = []
## Flechas que tienes de cada tipo.
var ammo: Array[int] = []
var selected_slot: int = 0

## id -> {"name": String, "description": String, "icon": Texture2D}
var upgrades: Dictionary = {}

# Claves de los pickups ya recogidos, para que no reaparezcan al volver a un nivel.
var _collected: Dictionary = {}
# true cuando el Bow ya definió los tipos (las cantidades iniciales se toman de ellos).
var _defined_by_bow: bool = false
var _default_icon: Texture2D


func _ready() -> void:
	_apply_types([])
	_reset_ammo_counts()


# ---------------------------------------------------------------------------
# Tipos de munición
# ---------------------------------------------------------------------------

## Lo llama el Bow con su lista `ammo_types`. Si faltan tipos, usa los de prueba.
## La primera vez que se llama, las cantidades iniciales salen de `starting_amount`.
func setup_ammo(types: Array) -> void:
	_apply_types(types)
	if not _defined_by_bow:
		_defined_by_bow = true
		_reset_ammo_counts()
	ammo_types_changed.emit()


func get_type(slot: int) -> AmmoType:
	if slot < 0 or slot >= ammo_types.size():
		return null
	return ammo_types[slot]


func get_selected_type() -> AmmoType:
	return get_type(selected_slot)


## Escena de flecha del tipo seleccionado; si no tiene, la `fallback` (la del Bow).
func get_selected_arrow_scene(fallback: PackedScene) -> PackedScene:
	var type := get_selected_type()
	if type and type.arrow_scene:
		return type.arrow_scene
	return fallback


## Icono del espacio: el del tipo o, si no tiene, una flecha dibujada por código.
func get_slot_icon(slot: int) -> Texture2D:
	var type := get_type(slot)
	if type and type.icon:
		return type.icon
	if _default_icon == null:
		_default_icon = _make_default_icon()
	return _default_icon


## Color para teñir el icono: blanco si es una imagen propia, o el color de prueba del espacio.
func get_slot_tint(slot: int) -> Color:
	var type := get_type(slot)
	if type and type.icon:
		return Color.WHITE
	return DEFAULT_TINTS[clampi(slot, 0, DEFAULT_TINTS.size() - 1)]


# ---------------------------------------------------------------------------
# Munición
# ---------------------------------------------------------------------------

func get_ammo(slot: int) -> int:
	if slot < 0 or slot >= ammo.size():
		return 0
	return ammo[slot]


## Suma flechas a un espacio (sin pasar de su máximo). Devuelve cuántas se agregaron de verdad.
func add_ammo(slot: int, amount: int) -> int:
	if slot < 0 or slot >= ammo.size():
		return 0
	var maximum := _max_for(slot)
	var added := mini(amount, maximum - ammo[slot])
	if added <= 0:
		return 0
	ammo[slot] += added
	ammo_changed.emit(slot, ammo[slot])
	return added


## true si queda al menos una flecha del tipo seleccionado.
func has_arrows() -> bool:
	return get_ammo(selected_slot) > 0


## Gasta una flecha del tipo seleccionado. Devuelve false si no queda ninguna.
func use_arrow() -> bool:
	if not has_arrows():
		return false
	ammo[selected_slot] -= 1
	ammo_changed.emit(selected_slot, ammo[selected_slot])
	return true


func select_ammo(slot: int) -> void:
	slot = clampi(slot, 0, SLOT_COUNT - 1)
	if slot == selected_slot:
		return
	selected_slot = slot
	ammo_selected.emit(slot)


## Pasa al siguiente (+1) o anterior (-1) tipo de munición, dando la vuelta.
func cycle_ammo(direction: int) -> void:
	select_ammo(posmod(selected_slot + direction, SLOT_COUNT))


# ---------------------------------------------------------------------------
# Mejoras
# ---------------------------------------------------------------------------

## Agrega una mejora. Devuelve false si ya la tenías.
func add_upgrade(id: StringName, display_name: String, description: String = "", icon: Texture2D = null) -> bool:
	if upgrades.has(id):
		return false
	upgrades[id] = {"name": display_name, "description": description, "icon": icon}
	upgrade_added.emit(id)
	return true


func has_upgrade(id: StringName) -> bool:
	return upgrades.has(id)


# ---------------------------------------------------------------------------
# Pickups recogidos / reinicio
# ---------------------------------------------------------------------------

func mark_collected(key: String) -> void:
	_collected[key] = true


func is_collected(key: String) -> bool:
	return _collected.has(key)


## Deja el inventario como en una partida nueva.
func reset() -> void:
	upgrades.clear()
	_collected.clear()
	_reset_ammo_counts()
	selected_slot = 0
	ammo_selected.emit(selected_slot)


# ---------------------------------------------------------------------------
# Internos
# ---------------------------------------------------------------------------

func _apply_types(types: Array) -> void:
	var result: Array[AmmoType] = []
	for i in SLOT_COUNT:
		var type: AmmoType = null
		if i < types.size():
			type = types[i] as AmmoType
		if type == null:
			type = _make_default_type(i)
		result.append(type)
	ammo_types = result


func _make_default_type(slot: int) -> AmmoType:
	var type := AmmoType.new()
	type.display_name = "Munición %d" % (slot + 1)
	type.starting_amount = DEFAULT_STARTING[slot]
	return type


func _reset_ammo_counts() -> void:
	ammo.clear()
	for i in SLOT_COUNT:
		ammo.append(mini(ammo_types[i].starting_amount, ammo_types[i].max_amount))
		ammo_changed.emit(i, ammo[i])


func _max_for(slot: int) -> int:
	var type := get_type(slot)
	return type.max_amount if type else 99


## Flecha diagonal de 16x16 (apunta arriba a la derecha), en blanco para poder teñirla.
func _make_default_icon() -> Texture2D:
	var image := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	for i in 11: # asta
		image.set_pixel(2 + i, 13 - i, Color.WHITE)
		image.set_pixel(3 + i, 13 - i, Color.WHITE)
	for i in 7: # punta: borde superior y derecho
		image.set_pixel(13 - i, 2, Color.WHITE)
		image.set_pixel(13, 2 + i, Color.WHITE)
	for i in 4: # plumas
		image.set_pixel(2, 13 - i, Color.WHITE)
		image.set_pixel(2 + i, 13, Color.WHITE)
	return ImageTexture.create_from_image(image)
