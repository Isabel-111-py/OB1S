class_name Rain
extends Node2D
## Lluvia de todo el nivel. Cae desde arriba de la pantalla y se detiene al chocar con:
##   - el suelo, las plataformas y los techos (física: capas de `block_mask`),
##   - el paraguas del jugador cuando está equipado (el agua NO lo atraviesa).
## Debajo de un techo o del paraguas no llueve, y ahí el jugador no se moja.
##
## Uso: pon `rain.tscn` en el nivel (en cualquier lugar). Es solo visual + una comprobación:
## `is_exposed(punto)` dice si ese punto recibe lluvia, y `exposure_changed` avisa al cambiar.
## La lluvia es vertical a propósito, para que lo que ves coincida con lo que moja.

## true si el jugador está bajo la lluvia (sin techo ni paraguas encima).
signal exposure_changed(exposed: bool)

@export var enabled: bool = true
@export_group("Lluvia")
## Gotas a la vez (se reparten por toda la pantalla).
@export var drop_count: int = 160
@export var fall_speed: float = 260.0
## Variación aleatoria de la velocidad (0.25 = ±25 %).
@export_range(0.0, 0.9) var speed_variation: float = 0.25
@export var drop_length: int = 3
@export var drop_color: Color = Color(0.7, 0.85, 1.0, 0.75)
@export var splash_color: Color = Color(0.85, 0.93, 1.0, 0.8)
@export var splash_time: float = 0.15
## Para que la lluvia se dibuje encima del mapa y de los personajes.
@export var draw_z_index: int = 5
@export_group("Colisión")
## Capas físicas que detienen la lluvia (suelo, plataformas, techos). El jugador siempre se ignora.
@export_flags_2d_physics var block_mask: int = 1
## Ancho (px) de cada columna de comprobación de techos.
@export var column_width: int = 4
## Cuántos píxeles por encima de la pantalla se buscan techos.
@export var roof_lookahead: float = 400.0
## Cada cuántos segundos se vuelven a buscar los techos.
@export var roof_update_interval: float = 0.1
@export_group("Efecto en el jugador")
@export var damage_enabled: bool = true
## Daño cada vez que pasa `tick_interval` estando mojado. 0 = solo visual.
@export var damage_per_tick: int = 1
@export var tick_interval: float = 3.0
## Altura (px) sobre el origen del jugador desde donde se comprueba si hay techo.
@export var head_offset: float = 24.0
## Distancia (px) hacia arriba en la que se busca un techo sobre el jugador.
@export var roof_check_distance: float = 800.0

var exposed: bool = false

var _x := PackedFloat32Array()
var _y := PackedFloat32Array()
var _speed := PackedFloat32Array() # 0 = gota inactiva (se vuelve a lanzar en el siguiente frame)
var _roof_y := PackedFloat32Array()
var _first_col: int = 0
var _roof_timer: float = 0.0
var _tick_timer: float = 0.0
var _initial_fill: bool = true
var _umbrella: Umbrella
var _player: Player
var _no_umbrella_time: float = 0.0
var _warned_no_umbrella: bool = false
var _splashes: Array[Vector3] = [] # x, y, edad


func _ready() -> void:
	top_level = true # dibuja en coordenadas globales, aunque el padre se mueva
	global_position = Vector2.ZERO
	z_index = draw_z_index
	_x.resize(drop_count)
	_y.resize(drop_count)
	_speed.resize(drop_count)


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_umbrella = _umbrella if is_instance_valid(_umbrella) else WaterUtils.find_umbrella(get_tree())
	_player = _player if is_instance_valid(_player) else WaterUtils.find_player(get_tree())

	_check_umbrella_found(delta)

	_roof_timer -= delta
	if _roof_timer <= 0.0:
		_roof_timer = roof_update_interval
		_update_roofs(_view_rect())

	_update_player_exposure(delta)


func _process(delta: float) -> void:
	if not enabled:
		return
	var view := _view_rect()

	for i in drop_count:
		if _speed[i] == 0.0:
			_spawn(i, view)
			continue
		_y[i] += _speed[i] * delta
		var end_y := _end_y_at(_x[i])
		if _y[i] >= end_y:
			_add_splash(_x[i], end_y)
			_speed[i] = 0.0
		elif _y[i] > view.end.y + 8.0 or _x[i] < view.position.x or _x[i] > view.end.x:
			_speed[i] = 0.0
	_initial_fill = false

	for i in range(_splashes.size() - 1, -1, -1):
		var splash := _splashes[i]
		splash.z += delta
		if splash.z >= splash_time:
			_splashes.remove_at(i)
		else:
			_splashes[i] = splash
	queue_redraw()


func _draw() -> void:
	if not enabled:
		return
	for i in drop_count:
		if _speed[i] > 0.0:
			draw_rect(Rect2(floorf(_x[i]), floorf(_y[i]) - drop_length, 1.0, float(drop_length)), drop_color)
	for splash in _splashes:
		var spread := 1.0 + floorf(splash.z / splash_time * 3.0)
		draw_rect(Rect2(floorf(splash.x) - spread, floorf(splash.y) - 2.0, 1.0, 1.0), splash_color)
		draw_rect(Rect2(floorf(splash.x) + spread, floorf(splash.y) - 2.0, 1.0, 1.0), splash_color)


## true si `point` (coordenadas globales) recibe lluvia: sin paraguas ni techo encima.
func is_exposed(point: Vector2) -> bool:
	if _umbrella and _umbrella.top_y_at(point.x) < point.y:
		return false
	var exclude := WaterUtils.exclude_for(_player)
	return not WaterUtils.has_roof_above(get_world_2d().direct_space_state, point, roof_check_distance, block_mask, exclude)


# ---------------------------------------------------------------------------
# Internos
# ---------------------------------------------------------------------------

func _view_rect() -> Rect2:
	var to_world := get_viewport().get_canvas_transform().affine_inverse()
	return to_world * get_viewport_rect()


## Busca el primer sólido sobre cada columna de la pantalla (techos, plataformas, suelo).
func _update_roofs(view: Rect2) -> void:
	var first := floori(view.position.x / column_width)
	var last := floori(view.end.x / column_width)
	var count := last - first + 1
	var space := get_world_2d().direct_space_state
	var exclude := WaterUtils.exclude_for(_player)
	var from_y := view.position.y - roof_lookahead
	var to_y := view.end.y + 32.0

	_roof_y.resize(count)
	for i in count:
		var x := (first + i + 0.5) * column_width
		_roof_y[i] = WaterUtils.solid_y_below(space, x, from_y, to_y, block_mask, exclude)
	_first_col = first


## Altura a la que se detiene el agua en la posición x: techo/suelo o copa del paraguas.
func _end_y_at(x: float) -> float:
	var end_y := INF
	var idx := floori(x / column_width) - _first_col
	if idx >= 0 and idx < _roof_y.size():
		end_y = _roof_y[idx]
	if _umbrella:
		end_y = minf(end_y, _umbrella.top_y_at(x))
	return end_y


func _spawn(i: int, view: Rect2) -> void:
	var x := randf_range(view.position.x, view.end.x)
	var y := randf_range(view.position.y, view.end.y) if _initial_fill \
		else view.position.y - randf() * 24.0
	if _end_y_at(x) <= y:
		return # hay un techo por encima de este punto: ahí no llueve
	_x[i] = x
	_y[i] = y
	_speed[i] = fall_speed * (1.0 + randf_range(-speed_variation, speed_variation))


## Avisa (una vez) si hay jugador pero no se encuentra el paraguas: sin él, no detiene el agua.
func _check_umbrella_found(delta: float) -> void:
	if _umbrella or _player == null or _warned_no_umbrella:
		return
	_no_umbrella_time += delta
	if _no_umbrella_time > 1.5:
		_warned_no_umbrella = true
		push_warning("Rain: no encuentro el nodo Umbrella. Instancia umbrella.tscn como hijo del Player y usa el umbrella.gd nuevo; si no, el paraguas no detiene el agua.")


func _add_splash(x: float, y: float) -> void:
	if is_inf(y) or _splashes.size() >= 60:
		return
	_splashes.append(Vector3(x, y, 0.0))


func _update_player_exposure(delta: float) -> void:
	if _player == null or _player.is_dead:
		return
	var now_exposed := is_exposed(_player.global_position + Vector2(0.0, -head_offset))
	if now_exposed != exposed:
		exposed = now_exposed
		exposure_changed.emit(exposed)
		_tick_timer = 0.0

	if exposed and damage_enabled and damage_per_tick > 0:
		_tick_timer += delta
		if _tick_timer >= tick_interval:
			_tick_timer = 0.0
			_player.take_damage(damage_per_tick)
