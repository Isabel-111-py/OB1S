extends Node
## Autoload "SceneManager": cambia de nivel, coloca al jugador y gestiona el respawn.
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

var current_level: Level
var player: Player

var _fade_rect: ColorRect
var _fade_tween: Tween
var _transitioning: bool = false

# Datos que viajan de un nivel a otro.
var _pending_spawn: StringName = &""
var _has_pending_spawn: bool = false
var _saved_health: int = -1

var _checkpoint_pos: Vector2 = Vector2.ZERO
var _checkpoint_facing: float = 1.0


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
		player.process_mode = Node.PROCESS_MODE_DISABLED
	await _fade(1.0)

	_pending_spawn = spawn_id
	_has_pending_spawn = true
	get_tree().change_scene_to_file(path)
	# El resto ocurre en on_level_ready(), que llama el _ready() del nuevo Level.


## Guarda el punto donde reaparecerá el jugador.
func set_checkpoint(pos: Vector2, facing: float = 1.0) -> void:
	_checkpoint_pos = pos
	_checkpoint_facing = facing


## Caída al vacío: quita vida y reaparece en el último checkpoint.
func void_fall() -> void:
	if _transitioning or not is_instance_valid(player) or player.is_dead:
		return
	if void_damage > 0:
		player.take_damage(void_damage)
		if player.is_dead:
			return # la señal `died` se encarga del respawn
	respawn_player()


## Fundido a negro, recoloca al jugador en el checkpoint y vuelve a mostrar la escena.
func respawn_player(full_heal: bool = false) -> void:
	if _transitioning or not is_instance_valid(player):
		return
	_transitioning = true
	player.process_mode = Node.PROCESS_MODE_DISABLED
	await _fade(1.0)

	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.respawn_at(_checkpoint_pos, _checkpoint_facing, full_heal)
	player_respawned.emit(player)

	await _fade(0.0)
	_transitioning = false


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

	var pos := player.global_position
	var facing := 1.0
	# Si se llegó desde otro nivel (o el nivel no traía Player) se usa un SpawnPoint.
	# Si abres el nivel con F6 y el Player ya estaba colocado, se respeta su posición.
	if _has_pending_spawn or created:
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

	set_checkpoint(pos, facing)
	player.respawn_at(pos, facing)
	level.apply_camera_limits(player.get_node_or_null("Camera2D") as Camera2D)

	if not player.died.is_connected(_on_player_died):
		player.died.connect(_on_player_died)

	_has_pending_spawn = false
	_saved_health = -1
	level_changed.emit(level)

	await _fade(0.0)
	_transitioning = false


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
