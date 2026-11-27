extends Node
## Autoload "SaveManager": guarda y carga partidas en ranuras (slots).
##
## - El guardado es SIEMPRE manual: solo ocurre cuando el jugador pulsa [E] en un Checkpoint
##   y elige una ranura (ver Checkpoint y SaveSlotsMenu). No hay autoguardado.
## - Cada ranura es un archivo JSON en user://saves/slot_N.json (N = 1..SLOT_COUNT).
## - Se guarda: nivel, posición del checkpoint, vida, energía, inventario (munición, mejoras,
##   objetos ya recogidos), el estado de las misiones y el estado del mundo.
##
## Registro: Proyecto > Configuración del proyecto > Globales (Autoload) > nombre "SaveManager".

signal game_saved(slot: int)
signal game_loaded(slot: int)

## Cantidad de ranuras disponibles (numeradas desde 1).
const SLOT_COUNT: int = 3
const SAVE_DIR: String = "user://saves"
const SAVE_VERSION: int = 1

## Última ranura guardada o cargada en esta sesión (0 = partida nueva sin guardar).
var current_slot: int = 0


# ---------------------------------------------------------------------------
# Consultas
# ---------------------------------------------------------------------------

func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]


func has_save(slot: int) -> bool:
	return not _read_slot(slot).is_empty()


func has_any_save() -> bool:
	for slot in range(1, SLOT_COUNT + 1):
		if has_save(slot):
			return true
	return false


## Resumen de una ranura para mostrar en los menús. Devuelve {} si está vacía o dañada.
func get_slot_info(slot: int) -> Dictionary:
	var data := _read_slot(slot)
	if data.is_empty():
		return {}
	var level_path := String(data.get("level_path", ""))
	var player_data := _as_dict(data.get("player"))
	return {
		"level_path": level_path,
		"level_name": _pretty_level_name(level_path),
		"saved_at": String(data.get("saved_at", "")),
		"health": int(player_data.get("health", 0)),
		"max_health": int(player_data.get("max_health", 0)),
	}


# ---------------------------------------------------------------------------
# Guardar
# ---------------------------------------------------------------------------

## Guarda la partida en `slot` (1..SLOT_COUNT). El jugador reaparecerá en `checkpoint_pos`.
## Devuelve false si no se pudo guardar.
func save_game(slot: int, checkpoint_pos: Vector2, checkpoint_facing: float = 1.0) -> bool:
	if slot < 1 or slot > SLOT_COUNT:
		push_error("SaveManager: ranura inválida (%d)." % slot)
		return false

	var level: Level = SceneManager.current_level
	var player: Player = SceneManager.player
	if not is_instance_valid(level) or not is_instance_valid(player):
		push_error("SaveManager: no hay nivel o jugador activo para guardar.")
		return false

	var level_path := level.scene_file_path
	if level_path.is_empty():
		push_error("SaveManager: el nivel actual no tiene ruta de escena.")
		return false

	var data := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"level_path": level_path,
		"checkpoint": {
			"x": checkpoint_pos.x,
			"y": checkpoint_pos.y,
			"facing": checkpoint_facing,
		},
		"player": {
			"health": player.health,
			"max_health": player.max_health,
			"energy": player.energy,
			"energy_exhausted": player.energy_exhausted,
		},
		"inventory": Inventory.get_state(),
		"quests": QuestManager.get_state(),
		"world_state": SceneManager.capture_world_state(level),
	}

	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var file := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: no se pudo escribir la ranura %d (%s)." % [slot, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	current_slot = slot
	game_saved.emit(slot)
	return true


# ---------------------------------------------------------------------------
# Cargar / partida nueva
# ---------------------------------------------------------------------------

## Carga la partida de `slot`: restaura inventario, misiones y mundo y lleva al jugador a su checkpoint.
## Devuelve false si la ranura está vacía, dañada o el nivel guardado ya no existe.
func load_game(slot: int) -> bool:
	var data := _read_slot(slot)
	if data.is_empty():
		return false

	var level_path := String(data.get("level_path", ""))
	if level_path.is_empty() or not ResourceLoader.exists(level_path):
		push_error("SaveManager: el nivel guardado '%s' no existe." % level_path)
		return false

	var checkpoint := _as_dict(data.get("checkpoint"))
	var player_data := _as_dict(data.get("player"))
	var world_state := _as_dict(data.get("world_state"))

	Inventory.restore_state(_as_dict(data.get("inventory")))
	QuestManager.restore_state(_as_dict(data.get("quests")))

	current_slot = slot
	get_tree().paused = false
	SceneManager.load_saved_game(
		level_path,
		Vector2(float(checkpoint.get("x", 0.0)), float(checkpoint.get("y", 0.0))),
		float(checkpoint.get("facing", 1.0)),
		int(player_data.get("health", 0)),
		float(player_data.get("energy", -1.0)),
		bool(player_data.get("energy_exhausted", false)),
		world_state
	)
	game_loaded.emit(slot)
	return true


## Empieza una partida desde cero: vacía inventario y misiones y entra al primer nivel.
func start_new_game(first_level_path: String) -> void:
	current_slot = 0
	Inventory.reset()
	QuestManager.reset()
	SceneManager.change_level(first_level_path)


# ---------------------------------------------------------------------------
# Internos
# ---------------------------------------------------------------------------

func _read_slot(slot: int) -> Dictionary:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


func _as_dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value as Dictionary
	return {}


func _pretty_level_name(level_path: String) -> String:
	if level_path.is_empty():
		return "?"
	return level_path.get_file().get_basename().replace("_", " ").capitalize()
