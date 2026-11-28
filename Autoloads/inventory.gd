extends Node
## Autoload "Inventory": munición (3 espacios) y mejoras que el jugador recoge.
## Como es un autoload, se conserva al cambiar de nivel.
## Registro: Proyecto > Configuración del proyecto > Globales (Autoload) > nombre "Inventory".

const SLOT_COUNT: int = 3
## Colores de prueba de la flecha dibujada por código (cuando un tipo no tiene icono).
const DEFAULT_TINTS: Array[Color] = [Color(1.0, 1.0, 1.0), Color(1.0, 0.65, 0.25), Color(0.45, 0.85, 1.0)]
## Valores de prueba si no defines tipos de munición en el Bow.
const DEFAULT_STARTING: Array[int] = [10, 5, 5]
## Id de la mejora que desbloquea el paraguas. Sin ella el paraguas no se puede equipar.
## El Pickup tipo Mejora que lo entrega debe usar este mismo id (ver Levels/umbrella_pickup.tscn).
const UMBRELLA_UPGRADE_ID: StringName = &"paraguas"

signal ammo_changed(slot: int, count: int)
signal ammo_selected(slot: int)
## Se emite cuando cambian las definiciones (nombres, iconos) de los tipos de munición.
signal ammo_types_changed
signal upgrade_added(id: StringName)
signal upgrade_removed(id: StringName)
## Se emite al equipar o guardar el paraguas.
signal umbrella_toggled(equipped: bool)

var ammo_types: Array[AmmoType] = []
## Flechas que tienes de cada tipo.
var ammo: Array[int] = []
var selected_slot: int = 0
## true mientras el paraguas está equipado: cubre del agua que cae y no deja disparar flechas.
## Para el agua (lluvia, cascadas) basta con preguntar `Inventory.umbrella_equipped`.
## Solo puede ser true si el jugador ya recogió el paraguas (ver `has_umbrella`).
var umbrella_equipped: bool = false

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
# Paraguas
# ---------------------------------------------------------------------------

## true si el jugador ya recogió el paraguas (aunque no lo tenga equipado).
func has_umbrella() -> bool:
	return has_upgrade(UMBRELLA_UPGRADE_ID)


## Equipa o guarda el paraguas. Equiparlo solo funciona si ya lo recogiste.
func set_umbrella_equipped(value: bool) -> void:
	if value and not has_umbrella():
		return
	if value == umbrella_equipped:
		return
	umbrella_equipped = value
	umbrella_toggled.emit(value)


func toggle_umbrella() -> void:
	set_umbrella_equipped(not umbrella_equipped)


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


func has_upgrade(id: Variant) -> bool:
	if upgrades.has(StringName(id)) or upgrades.has(str(id)):
		return true
	var target_str := str(id).strip_edges().to_lower()
	for k in upgrades.keys():
		if str(k).strip_edges().to_lower() == target_str:
			return true
	return false


## Elimina una mejora / ítem del inventario (útil para misiones de entrega).
func remove_upgrade(id: Variant) -> bool:
	var key_sn := StringName(id)
	var key_str := str(id)
	if upgrades.has(key_sn):
		upgrades.erase(key_sn)
		upgrade_removed.emit(key_sn)
		_unequip_umbrella_if_lost()
		return true
	elif upgrades.has(key_str):
		upgrades.erase(key_str)
		upgrade_removed.emit(key_sn)
		_unequip_umbrella_if_lost()
		return true
	var target_str := str(id).strip_edges().to_lower()
	for k in upgrades.keys():
		if str(k).strip_edges().to_lower() == target_str:
			upgrades.erase(k)
			upgrade_removed.emit(StringName(k))
			_unequip_umbrella_if_lost()
			return true
	return false


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
	set_umbrella_equipped(false)


## Estado serializable (para guardar partida). Los iconos se guardan como ruta de recurso.
func get_state() -> Dictionary:
	var saved_upgrades: Array = []
	for id in upgrades:
		var entry: Dictionary = upgrades[id]
		var icon := entry.get("icon") as Texture2D
		saved_upgrades.append({
			"id": String(id),
			"name": String(entry.get("name", "")),
			"description": String(entry.get("description", "")),
			"icon": icon.resource_path if icon else "",
		})
	return {
		"ammo": ammo.duplicate(),
		"selected_slot": selected_slot,
		"umbrella_equipped": umbrella_equipped,
		"upgrades": saved_upgrades,
		"collected": _collected.keys(),
	}


## Restaura un estado de get_state() (cargar partida). Debe llamarse antes de crear al jugador.
func restore_state(state: Dictionary) -> void:
	upgrades.clear()
	for entry in state.get("upgrades", []):
		if not entry is Dictionary:
			continue
		var icon: Texture2D = null
		var icon_path := String(entry.get("icon", ""))
		if icon_path != "" and ResourceLoader.exists(icon_path):
			icon = load(icon_path) as Texture2D
		upgrades[StringName(String(entry.get("id", "")))] = {
			"name": String(entry.get("name", "")),
			"description": String(entry.get("description", "")),
			"icon": icon,
		}

	_collected.clear()
	for key in state.get("collected", []):
		_collected[String(key)] = true

	# El Bow llama a setup_ammo() al aparecer el jugador y, la primera vez, reinicia las
	# cantidades. Se marca como ya definido para que no pise las flechas cargadas.
	_defined_by_bow = true
	var saved_ammo: Array = state.get("ammo", [])
	for i in SLOT_COUNT:
		if i < saved_ammo.size():
			ammo[i] = maxi(int(saved_ammo[i]), 0)
		ammo_changed.emit(i, ammo[i])

	selected_slot = clampi(int(state.get("selected_slot", 0)), 0, SLOT_COUNT - 1)
	ammo_selected.emit(selected_slot)

	umbrella_equipped = bool(state.get("umbrella_equipped", false)) and has_umbrella()
	umbrella_toggled.emit(umbrella_equipped)


# ---------------------------------------------------------------------------
# Internos
# ---------------------------------------------------------------------------

## Si el paraguas estaba equipado y ya no está en el inventario, se guarda.
func _unequip_umbrella_if_lost() -> void:
	if umbrella_equipped and not has_umbrella():
		set_umbrella_equipped(false)


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
