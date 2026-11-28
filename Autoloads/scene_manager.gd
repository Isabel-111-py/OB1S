extends Node
## Autoload "SceneManager": cambia de nivel, coloca al jugador y gestiona el respawn con snapshot del mundo.
## Registro: Proyecto > Configuración del proyecto > Globales (Autoload) > nombre "SceneManager".

signal level_changed(level: Level)
signal player_respawned(player: Player)

const PLAYER_SCENE := preload("res://Player/player.tscn")

## Duración del fundido a negro (s).
var fade_time: float = 0.25
## Espera tras morir (vida 0) antes de reaparecer (s).
var respawn_delay: float = 1.0
## Daño al caer al vacío. Con 0 solo reaparece sin quitar vida.
var void_damage: int = 1
## true: la energía se conserva al cambiar de nivel. false: cada nivel empieza con la energía llena.
var keep_energy_between_levels: bool = true
## Pantallas de muerte (DeathScreen) activas. Si hay alguna, ella decide qué pasa al morir
## (reintentar o volver al menú) y el jugador ya no reaparece solo tras `respawn_delay`.
var death_screens: int = 0

var current_level: Level
var player: Player

var _fade_rect: ColorRect
var _fade_tween: Tween
var _transitioning: bool = false

# Datos que viajan de un nivel a otro.
var _pending_spawn: StringName = &""
var _has_pending_spawn: bool = false
var _saved_health: int = -1
var _saved_energy: float = -1.0
var _saved_energy_exhausted: bool = false

var _checkpoint_pos: Vector2 = Vector2.ZERO
var _checkpoint_facing: float = 1.0

# Posición exacta donde aparecer al cargar una partida guardada o al restaurar checkpoint.
var _has_pending_position: bool = false
var _pending_position: Vector2 = Vector2.ZERO
var _pending_facing: float = 1.0

# Estado del mundo para cargar partida desde SaveManager.
var _pending_world_state: Dictionary = {}

# Snapshot del mundo y entidades al momento de activar el último checkpoint.
var _checkpoint_snapshot: Dictionary = {}
var _is_restoring_checkpoint: bool = false
var _initial_level_node_paths: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color.BLACK
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.modulate.a = 0.0
	layer.add_child(_fade_rect)


# ---------------------------------------------------------------------------
# API pública
# ---------------------------------------------------------------------------

## Cambia a otro nivel y deja al jugador en el SpawnPoint con id `spawn_id`.
func change_level(path: String, spawn_id: StringName = &"default") -> void:
	if _transitioning:
		return
	if not ResourceLoader.exists(path):
		push_error("SceneManager: no existe el nivel '%s'." % path)
		return
	_transitioning = true
	if is_instance_valid(player):
		_saved_health = player.health
		_saved_energy = player.energy
		_saved_energy_exhausted = player.energy_exhausted
		player.process_mode = Node.PROCESS_MODE_DISABLED
	await _fade(1.0)

	_checkpoint_snapshot.clear()
	_initial_level_node_paths.clear()
	_is_restoring_checkpoint = false
	_pending_world_state.clear()

	_pending_spawn = spawn_id
	_has_pending_spawn = true
	_has_pending_position = false
	get_tree().change_scene_to_file(path)
	# El resto ocurre en on_level_ready(), que llama el _ready() del nuevo Level.


## Carga una partida guardada: entra al nivel `path` y deja al jugador en `pos` (su checkpoint)
## con la vida y la energía guardadas, restaurando también el estado del mundo guardado.
func load_saved_game(path: String, pos: Vector2, facing: float, health: int, energy: float, exhausted: bool, world_state: Dictionary = {}) -> void:
	if _transitioning:
		return
	if not ResourceLoader.exists(path):
		push_error("SceneManager: no existe el nivel '%s'." % path)
		return
	_transitioning = true
	get_tree().paused = false
	if is_instance_valid(player):
		player.process_mode = Node.PROCESS_MODE_DISABLED
	await _fade(1.0)

	_checkpoint_snapshot.clear()
	_initial_level_node_paths.clear()
	_is_restoring_checkpoint = false

	_pending_spawn = &"default"
	_has_pending_spawn = true
	_has_pending_position = true
	_pending_position = pos
	_pending_facing = facing
	_saved_health = health
	_saved_energy = energy
	_saved_energy_exhausted = exhausted
	_pending_world_state = world_state
	get_tree().change_scene_to_file(path)
	# El resto ocurre en on_level_ready(), que llama el _ready() del nuevo Level.


## Cambia al menú principal u otra escena que no sea un Level (sin requerir SpawnPoint).
func change_to_menu(path: String = "res://UI/MainMenu/main_menu.tscn") -> void:
	if _transitioning:
		return
	if not ResourceLoader.exists(path):
		push_error("SceneManager: no existe la escena de menú '%s'." % path)
		return
	_transitioning = true
	if is_instance_valid(player):
		player.queue_free()
		player = null
	current_level = null
	_checkpoint_snapshot.clear()
	_initial_level_node_paths.clear()
	_is_restoring_checkpoint = false
	_pending_world_state.clear()
	_has_pending_spawn = false
	_has_pending_position = false
	_saved_health = -1
	_saved_energy = -1.0
	await _fade(1.0)
	get_tree().change_scene_to_file(path)
	await _fade(0.0)
	_transitioning = false


## Guarda el punto donde reaparecerá el jugador y captura una instantánea completa del mundo.
func set_checkpoint(pos: Vector2, facing: float = 1.0, update_snapshot: bool = true) -> void:
	_checkpoint_pos = pos
	_checkpoint_facing = facing

	if not update_snapshot:
		return

	if not is_instance_valid(current_level):
		return

	var level_path := current_level.scene_file_path
	if level_path.is_empty():
		return

	var p_health := player.health if is_instance_valid(player) else -1
	var p_max_health := player.max_health if is_instance_valid(player) else -1
	var p_energy := player.energy if is_instance_valid(player) else -1.0
	var p_exhausted := player.energy_exhausted if is_instance_valid(player) else false

	_checkpoint_snapshot = {
		"level_path": level_path,
		"checkpoint_pos": pos,
		"checkpoint_facing": facing,
		"player_health": p_health,
		"player_max_health": p_max_health,
		"player_energy": p_energy,
		"player_energy_exhausted": p_exhausted,
		"inventory": Inventory.get_state() if Inventory else {},
		"quests": QuestManager.get_state() if QuestManager else {},
		"world_state": capture_world_state(current_level)
	}


func get_checkpoint_pos() -> Vector2:
	return _checkpoint_pos


func get_checkpoint_facing() -> float:
	return _checkpoint_facing


func get_checkpoint_snapshot() -> Dictionary:
	return _checkpoint_snapshot


## Caída al vacío: quita vida y reaparece en el último checkpoint.
func void_fall() -> void:
	if _transitioning or not is_instance_valid(player) or player.is_dead:
		return
	if void_damage > 0:
		player.take_damage(void_damage)
		if player.is_dead:
			return # la señal `died` se encarga del respawn fatal
	respawn_player(false)


## Respawn del jugador.
## - Si el jugador murió (full_heal = true o player.is_dead): recarga la escena y restaura exactamente el estado del mundo en el checkpoint.
## - Si fue una caída no fatal: solo recoloca al jugador en el checkpoint sin reiniciar el mundo.
func respawn_player(full_heal: bool = false) -> void:
	if _transitioning:
		return

	var is_death_respawn: bool = full_heal or (is_instance_valid(player) and player.is_dead)

	_transitioning = true
	if is_instance_valid(player):
		player.process_mode = Node.PROCESS_MODE_DISABLED
	await _fade(1.0)

	if not is_death_respawn:
		if is_instance_valid(player):
			player.process_mode = Node.PROCESS_MODE_INHERIT
			player.respawn_at(_checkpoint_pos, _checkpoint_facing, false)
			player_respawned.emit(player)
		await _fade(0.0)
		_transitioning = false
		return

	# --- RESPAWN POR MUERTE: Restauración completa del estado del checkpoint ---
	if _checkpoint_snapshot.is_empty():
		var fallback_path: String = current_level.scene_file_path if is_instance_valid(current_level) else ""
		_checkpoint_snapshot = {
			"level_path": fallback_path,
			"checkpoint_pos": _checkpoint_pos,
			"checkpoint_facing": _checkpoint_facing,
			"player_health": -1,
			"player_max_health": -1,
			"player_energy": -1.0,
			"player_energy_exhausted": false,
			"inventory": Inventory.get_state() if Inventory else {},
			"quests": QuestManager.get_state() if QuestManager else {},
			"world_state": capture_world_state(current_level) if is_instance_valid(current_level) else {}
		}

	# 1. Revertir inventario y misiones al momento exacto del checkpoint
	if Inventory and _checkpoint_snapshot.has("inventory"):
		Inventory.restore_state(_checkpoint_snapshot["inventory"])
	if QuestManager and _checkpoint_snapshot.has("quests"):
		QuestManager.restore_state(_checkpoint_snapshot["quests"])

	# 2. Configurar flags para recargar la escena del nivel
	_is_restoring_checkpoint = true
	_has_pending_position = true
	_pending_position = _checkpoint_snapshot.get("checkpoint_pos", _checkpoint_pos)
	_pending_facing = float(_checkpoint_snapshot.get("checkpoint_facing", _checkpoint_facing))
	_has_pending_spawn = false

	var target_path: String = String(_checkpoint_snapshot.get("level_path", ""))
	if target_path.is_empty() and is_instance_valid(current_level):
		target_path = current_level.scene_file_path

	get_tree().change_scene_to_file(target_path)
	# El resto ocurre en on_level_ready(), que llama el _ready() del nuevo Level.


# ---------------------------------------------------------------------------
# Lo llama Level._ready()
# ---------------------------------------------------------------------------

func on_level_ready(level: Level) -> void:
	current_level = level
	player = get_tree().get_first_node_in_group("player") as Player
	var created := false
	if player == null:
		player = PLAYER_SCENE.instantiate() as Player
		level.add_child(player)
		created = true

	# Indexar nodos de la escena recién instanciada
	_index_initial_level_nodes(level)

	if _is_restoring_checkpoint:
		var pos := _pending_position
		var facing := _pending_facing
		set_checkpoint(pos, facing, false)

		player.respawn_at(pos, facing, true)
		level.apply_camera_limits(player.get_node_or_null("Camera2D") as Camera2D)

		if not player.died.is_connected(_on_player_died):
			player.died.connect(_on_player_died)

		# Esperar al siguiente frame para que corran los call_deferred de _ready() en los nodos hijos
		await get_tree().process_frame

		# Restaurar el estado del mundo capturado en el checkpoint
		var world_st: Dictionary = _checkpoint_snapshot.get("world_state", {})
		restore_world_state(level, world_st)

		_is_restoring_checkpoint = false
		_has_pending_position = false
		_saved_health = -1
		_saved_energy = -1.0
		level_changed.emit(level)
		player_respawned.emit(player)

		await _fade(0.0)
		_transitioning = false
		return

	# --- Carga normal o nueva entrada a un nivel ---
	var pos := player.global_position
	var facing := 1.0

	if _has_pending_position:
		pos = _pending_position
		facing = _pending_facing
	elif _has_pending_spawn or created:
		var id := _pending_spawn if _has_pending_spawn else level.default_spawn
		var spawn := _find_spawn(level, id)
		if spawn:
			pos = spawn.global_position
			facing = spawn.get_facing()
		else:
			push_warning("SceneManager: no hay SpawnPoint con id '%s' en %s." % [id, level.name])

	if _has_pending_spawn and _saved_health > 0:
		player.health = clampi(_saved_health, 1, player.max_health)
		player.health_changed.emit(player.health, player.max_health)

	if (keep_energy_between_levels or _has_pending_position) and _has_pending_spawn and _saved_energy >= 0.0:
		player.restore_energy(_saved_energy, _saved_energy_exhausted)

	player.respawn_at(pos, facing)
	level.apply_camera_limits(player.get_node_or_null("Camera2D") as Camera2D)

	if not player.died.is_connected(_on_player_died):
		player.died.connect(_on_player_died)

	if not _pending_world_state.is_empty():
		await get_tree().process_frame
		restore_world_state(level, _pending_world_state)
		_pending_world_state.clear()
	else:
		await get_tree().process_frame

	set_checkpoint(pos, facing, true)

	_has_pending_spawn = false
	_has_pending_position = false
	_saved_health = -1
	_saved_energy = -1.0
	level_changed.emit(level)

	await _fade(0.0)
	_transitioning = false


# ---------------------------------------------------------------------------
# Captura y Restauración del Estado del Mundo (Checkpoint Snapshot)
# ---------------------------------------------------------------------------

func _index_initial_level_nodes(level: Level) -> void:
	_initial_level_node_paths = {
		"enemies": [],
		"npcs": [],
		"gates": [],
		"elevators": [],
		"levers": [],
		"boss_detectors": [],
		"crystals": []
	}
	if not is_instance_valid(level):
		return
	_scan_node_recursive(level, level)


func _scan_node_recursive(node: Node, level: Level) -> void:
	for child in node.get_children():
		if child is Player or child.is_in_group("player") or child.name.to_lower().begins_with("player"):
			continue

		var path_str := String(level.get_path_to(child))

		if child is DrErgot:
			_initial_level_node_paths["npcs"].append(path_str)
		elif child is EnemyBase or child is EnemyBaseBoss or child.is_in_group("enemies") or child.is_in_group("boss"):
			_initial_level_node_paths["enemies"].append(path_str)
		elif child is NPCBase or child.is_in_group("npcs"):
			_initial_level_node_paths["npcs"].append(path_str)
		elif child is Gate or child.is_in_group("gates"):
			_initial_level_node_paths["gates"].append(path_str)
		elif child is Elevator or child.is_in_group("elevators"):
			_initial_level_node_paths["elevators"].append(path_str)
		elif child is GateLever or child.is_in_group("levers"):
			_initial_level_node_paths["levers"].append(path_str)
		elif child is BossRoomDetector:
			_initial_level_node_paths["boss_detectors"].append(path_str)
		elif child is LightCrystal or child.is_in_group("light_crystals"):
			_initial_level_node_paths["crystals"].append(path_str)

		if child.get_child_count() > 0:
			_scan_node_recursive(child, level)


func capture_world_state(level: Level = null) -> Dictionary:
	var target_level := level if level else current_level
	if not is_instance_valid(target_level):
		return {}

	if _initial_level_node_paths.is_empty():
		_index_initial_level_nodes(target_level)

	var enemies_data: Dictionary = {}
	for path_str in _initial_level_node_paths.get("enemies", []):
		var enemy := target_level.get_node_or_null(path_str)
		if enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or (enemy.get("is_dead") == true and not (enemy is DrErgot)):
			enemies_data[path_str] = {"alive": false}
		else:
			var hp: int = int(enemy.get("current_health")) if "current_health" in enemy else 1
			var awake: bool = bool(enemy.get("is_awake")) if "is_awake" in enemy else false
			var flip: bool = false
			var sprite = enemy.get_node_or_null("AnimatedSprite2D")
			if sprite and "flip_h" in sprite:
				flip = bool(sprite.flip_h)
			enemies_data[path_str] = {
				"alive": true,
				"health": hp,
				"pos_x": enemy.global_position.x,
				"pos_y": enemy.global_position.y,
				"vel_x": enemy.velocity.x,
				"vel_y": enemy.velocity.y,
				"is_awake": awake,
				"flip_h": flip
			}

	var npcs_data: Dictionary = {}
	for path_str in _initial_level_node_paths.get("npcs", []):
		var npc := target_level.get_node_or_null(path_str)
		if npc == null or not is_instance_valid(npc) or npc.is_queued_for_deletion():
			npcs_data[path_str] = {"exists": false}
		else:
			if npc is DrErgot:
				npcs_data[path_str] = {
					"exists": true,
					"is_dr_ergot": true,
					"pos_x": npc.global_position.x,
					"pos_y": npc.global_position.y,
					"ergot_state": int(npc.ergot_state),
					"current_health": int(npc.current_health),
					"is_dead": bool(npc.is_dead),
					"pending_trans": bool(npc.get("_pending_transformation")),
					"direction": int(npc.direction),
					"current_state": int(npc.current_state)
				}
			else:
				npcs_data[path_str] = {
					"exists": true,
					"is_dr_ergot": false,
					"pos_x": npc.global_position.x,
					"pos_y": npc.global_position.y,
					"is_dead": bool(npc.get("is_dead")),
					"current_state": int(npc.get("current_state")) if "current_state" in npc else 0,
					"direction": int(npc.get("direction")) if "direction" in npc else 1
				}

	var gates_data: Dictionary = {}
	for path_str in _initial_level_node_paths.get("gates", []):
		var g := target_level.get_node_or_null(path_str)
		if g and is_instance_valid(g) and g is Gate:
			gates_data[path_str] = {
				"is_open": g.is_open,
				"is_locked": g.is_locked,
				"open_progress": g.open_progress
			}

	var elevators_data: Dictionary = {}
	for path_str in _initial_level_node_paths.get("elevators", []):
		var el := target_level.get_node_or_null(path_str)
		if el and is_instance_valid(el) and el is Elevator:
			elevators_data[path_str] = {
				"progress": el.progress,
				"current_state": int(el.current_state)
			}

	var levers_data: Dictionary = {}
	for path_str in _initial_level_node_paths.get("levers", []):
		var lev := target_level.get_node_or_null(path_str)
		if lev and is_instance_valid(lev) and lev is GateLever:
			levers_data[path_str] = {
				"lever_angle": lev.lever_angle
			}

	var detectors_data: Dictionary = {}
	for path_str in _initial_level_node_paths.get("boss_detectors", []):
		var det := target_level.get_node_or_null(path_str)
		if det and is_instance_valid(det) and det is BossRoomDetector:
			detectors_data[path_str] = {
				"gate_locked": det.get("_gate_locked_by_detector"),
				"monitoring": det.get("_is_monitoring"),
				"player_inside": det.get("_player_inside")
			}

	var crystals_data: Dictionary = {}
	for path_str in _initial_level_node_paths.get("crystals", []):
		var cry := target_level.get_node_or_null(path_str)
		if cry and is_instance_valid(cry) and cry is LightCrystal:
			crystals_data[path_str] = {
				"pos_x": cry.global_position.x,
				"pos_y": cry.global_position.y,
				"current_angle": cry.current_angle if "current_angle" in cry else 0.0,
				"angle_index": cry.current_angle_index if "current_angle_index" in cry else 0,
				"is_energized": cry.is_energized if "is_energized" in cry else false
			}

	return {
		"enemies": enemies_data,
		"npcs": npcs_data,
		"gates": gates_data,
		"elevators": elevators_data,
		"levers": levers_data,
		"boss_detectors": detectors_data,
		"crystals": crystals_data
	}


func restore_world_state(level: Level, world_state: Dictionary) -> void:
	if not is_instance_valid(level) or world_state.is_empty():
		return

	# 1. Enemigos
	var enemies_dict: Dictionary = world_state.get("enemies", {})
	for path_str in enemies_dict:
		var enemy_data: Dictionary = enemies_dict[path_str]
		var enemy := level.get_node_or_null(path_str)
		if enemy and is_instance_valid(enemy):
			if not bool(enemy_data.get("alive", true)):
				enemy.visible = false
				enemy.process_mode = Node.PROCESS_MODE_DISABLED
				if "is_dead" in enemy:
					enemy.is_dead = true
				var col = enemy.get_node_or_null("CollisionShape2D")
				if col and col is CollisionShape2D:
					col.set_deferred("disabled", true)
				var hb = enemy.get_node_or_null("Hitbox")
				if hb and "active" in hb:
					hb.active = false
				enemy.queue_free()
			else:
				if "health" in enemy_data and "current_health" in enemy:
					enemy.current_health = int(enemy_data.health)
				if "pos_x" in enemy_data and "pos_y" in enemy_data:
					enemy.global_position = Vector2(float(enemy_data.pos_x), float(enemy_data.pos_y))
				if "vel_x" in enemy_data and "vel_y" in enemy_data:
					enemy.velocity = Vector2(float(enemy_data.vel_x), float(enemy_data.vel_y))
				if "is_awake" in enemy_data and "is_awake" in enemy:
					enemy.is_awake = bool(enemy_data.is_awake)
				if "is_dead" in enemy:
					enemy.is_dead = false
				if "target_player" in enemy:
					enemy.target_player = null
				var sprite = enemy.get_node_or_null("AnimatedSprite2D")
				if sprite and "flip_h" in sprite and "flip_h" in enemy_data:
					sprite.flip_h = bool(enemy_data.flip_h)

	# 2. NPCs (incluyendo DrErgot)
	var npcs_dict: Dictionary = world_state.get("npcs", {})
	for path_str in npcs_dict:
		var npc_data: Dictionary = npcs_dict[path_str]
		var npc := level.get_node_or_null(path_str)
		if npc == null or not is_instance_valid(npc):
			continue
		if not bool(npc_data.get("exists", true)):
			npc.queue_free()
			continue

		if npc is DrErgot:
			if "pos_x" in npc_data and "pos_y" in npc_data:
				npc.global_position = Vector2(float(npc_data.pos_x), float(npc_data.pos_y))
			if "current_health" in npc_data:
				npc.current_health = int(npc_data.current_health)
			if "direction" in npc_data:
				npc.direction = int(npc_data.direction)
			var st: int = int(npc_data.get("ergot_state", DrErgot.ErgotState.NPC))
			npc.ergot_state = st as DrErgot.ErgotState
			if st == DrErgot.ErgotState.NPC:
				npc.set("_pending_transformation", false)
				npc.set("is_attacking", false)
				npc.set("target_player", null)
				if npc.hitbox:
					npc.hitbox.active = false
				if npc.hurtbox:
					npc.hurtbox.active = false
				if npc.anim:
					npc.anim.play("idle")
			elif st == DrErgot.ErgotState.ENEMY_DEAD:
				npc.die()
			else:
				npc._complete_transformation(true)
		elif npc is NPCBase:
			if "pos_x" in npc_data and "pos_y" in npc_data:
				npc.global_position = Vector2(float(npc_data.pos_x), float(npc_data.pos_y))
			if "direction" in npc_data:
				npc.direction = int(npc_data.direction)
			if bool(npc_data.get("is_dead", false)):
				npc.die()
			elif "current_state" in npc_data:
				npc.current_state = int(npc_data.current_state) as NPCBase.NPCState

	# 3. Compuertas (Gates)
	var gates_dict: Dictionary = world_state.get("gates", {})
	for path_str in gates_dict:
		var g_data: Dictionary = gates_dict[path_str]
		var g := level.get_node_or_null(path_str)
		if g and is_instance_valid(g) and g is Gate:
			g.is_locked = bool(g_data.get("is_locked", false))
			g.is_open = bool(g_data.get("is_open", false))
			g._apply_current_state_instant()

	# 4. Elevadores
	var elevators_dict: Dictionary = world_state.get("elevators", {})
	for path_str in elevators_dict:
		var el_data: Dictionary = elevators_dict[path_str]
		var el := level.get_node_or_null(path_str)
		if el and is_instance_valid(el) and el is Elevator:
			el.progress = float(el_data.get("progress", 0.0))
			el.current_state = int(el_data.get("current_state", 0)) as Elevator.ElevatorState
			el._apply_platform_position()

	# 5. Palancas (Levers)
	var levers_dict: Dictionary = world_state.get("levers", {})
	for path_str in levers_dict:
		var lev_data: Dictionary = levers_dict[path_str]
		var lev := level.get_node_or_null(path_str)
		if lev and is_instance_valid(lev) and lev is GateLever:
			lev.lever_angle = float(lev_data.get("lever_angle", -28.0))
			lev.queue_redraw()

	# 6. Detectores de Sala de Jefe
	var detectors_dict: Dictionary = world_state.get("boss_detectors", {})
	for path_str in detectors_dict:
		var det_data: Dictionary = detectors_dict[path_str]
		var det := level.get_node_or_null(path_str)
		if det and is_instance_valid(det) and det is BossRoomDetector:
			det.set("_is_monitoring", bool(det_data.get("monitoring", false)))
			det.set("_player_inside", false)
			var locked: bool = bool(det_data.get("gate_locked", false))
			det.set("_gate_locked_by_detector", locked)
			if not locked and is_instance_valid(det.get("target_gate")):
				var tg: Gate = det.target_gate
				tg.unlock_gate()
				tg.open(true)

	# 7. Cristales de Luz
	var crystals_dict: Dictionary = world_state.get("crystals", {})
	for path_str in crystals_dict:
		var cry_data: Dictionary = crystals_dict[path_str]
		var cry := level.get_node_or_null(path_str)
		if cry and is_instance_valid(cry) and cry is LightCrystal:
			if "pos_x" in cry_data and "pos_y" in cry_data:
				cry.global_position = Vector2(float(cry_data.pos_x), float(cry_data.pos_y))
			if "current_angle" in cry_data and "current_angle" in cry:
				cry.current_angle = float(cry_data.current_angle)
				cry.rotation_degrees = cry.current_angle
			if "angle_index" in cry_data and "current_angle_index" in cry:
				cry.current_angle_index = int(cry_data.angle_index)
			if "is_energized" in cry_data and "is_energized" in cry:
				cry.is_energized = bool(cry_data.is_energized)
			cry.queue_redraw()


# ---------------------------------------------------------------------------
# Internos
# ---------------------------------------------------------------------------

func _find_spawn(level: Level, id: StringName) -> SpawnPoint:
	for node in get_tree().get_nodes_in_group("spawn_points"):
		var spawn := node as SpawnPoint
		if spawn and spawn.id == id and level.is_ancestor_of(spawn):
			return spawn
	return null


func _on_player_died() -> void:
	if death_screens > 0:
		return # la pantalla de muerte llama a respawn_player(true) cuando el jugador elige reintentar
	var dead_player := player
	await get_tree().create_timer(respawn_delay).timeout
	# Si mientras tanto cambió el nivel, este jugador ya no existe: no hacer nada.
	if dead_player != player or not is_instance_valid(player):
		return
	respawn_player(true)


func _fade(target_alpha: float) -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade_rect, "modulate:a", target_alpha, fade_time)
	await _fade_tween.finished
