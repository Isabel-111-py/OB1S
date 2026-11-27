class_name Waterfall
extends Node2D
## Cascada. El origen del nodo es el CENTRO DEL BORDE SUPERIOR (de donde sale el agua) y cae hacia
## abajo hasta el suelo, una plataforma o `max_height`. Cada columna de agua se detiene por separado:
##   - al chocar con el paraguas del jugador (el agua NO lo atraviesa: debajo queda seco),
##   - al chocar con un techo, plataforma o el suelo (capas de `block_mask`).
## Si el jugador está en el agua (sin paraguas encima), se moja.
##
## Uso: pon `waterfall.tscn` en el nivel, en el punto donde nace la cascada. No la rotes.

## true si el jugador está bajo el agua de esta cascada.
signal player_wet_changed(wet: bool)
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D

## Ancho total (px).
@export var width: float = 24.0
## Altura máxima (px) si no choca con nada.
@export var max_height: float = 240.0
@export var enabled: bool = true
@export_group("Textura propia")
## Imagen de la cascada (pixel art). Se repite hacia abajo y se desplaza para simular el agua
## cayendo. Vacío = agua dibujada por código (colores de abajo).
@export var texture: Texture2D
## Si la imagen es una tira horizontal de varios cuadros de animación, cuántos cuadros tiene.
@export var texture_frames: int = 1
@export var frames_per_second: float = 8.0

@export_group("Aspecto")
## Ancho (px) de cada columna de agua. Más pequeño = el corte con el paraguas es más fino.
@export var column_width: int = 2
## Línea de espuma donde termina cada columna (suelo, techo o paraguas).
@export var show_foam: bool = true
@export var water_color: Color = Color(0.35, 0.65, 0.95, 0.55)
@export var streak_color: Color = Color(0.85, 0.95, 1.0, 0.85)
@export var foam_color: Color = Color(0.95, 0.98, 1.0, 0.9)
## Velocidad (px/s) a la que corren las rayas del agua.
@export var flow_speed: float = 140.0
@export var draw_z_index: int = 4
@export_group("Colisión")
## Capas físicas que detienen el agua (suelo, plataformas, techos). El jugador siempre se ignora.
@export_flags_2d_physics var block_mask: int = 1
@export var roof_update_interval: float = 0.1
@export_group("Efecto en el jugador")
@export var damage_enabled: bool = true
## Daño cada vez que pasa `tick_interval` estando en el agua. 0 = solo visual.
@export var damage_per_tick: int = 1
@export var tick_interval: float = 1.0

var player_wet: bool = false

var _end_ys := PackedFloat32Array() # Y global donde termina cada columna (suelo/techo)
var _roof_timer: float = 0.0
var _tick_timer: float = 0.0
var _time: float = 0.0
var _umbrella: Umbrella
var _player: Player
var _no_umbrella_time: float = 0.0
var _warned_no_umbrella: bool = false


func _ready() -> void:
	z_index = draw_z_index


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_umbrella = _umbrella if is_instance_valid(_umbrella) else WaterUtils.find_umbrella(get_tree())
	_player = _player if is_instance_valid(_player) else WaterUtils.find_player(get_tree())

	_check_umbrella_found(delta)

	_roof_timer -= delta
	if _roof_timer <= 0.0:
		_roof_timer = roof_update_interval
		_update_columns()

	_update_player(delta)


func _process(delta: float) -> void:
	if not enabled:
		return
	_time += delta
	queue_redraw()


func _draw() -> void:
	if not enabled:
		return
	var count := _column_count()
	if _end_ys.size() != count:
		return
	var top_y := global_position.y
	var left := -width / 2.0

	for i in count:
		var x_global := global_position.x + left + (i + 0.5) * column_width
		var length := _column_end_y(i, x_global) - top_y
		if length <= 0.0:
			continue
		var x := floorf(left + i * column_width)

		if texture:
			_draw_textured_column(i, x, length)
		else:
			_draw_procedural_column(i, x, length)

		# Espuma donde termina (suelo, techo o paraguas).
		if show_foam:
			var wobble := 0.0 if int(_time * 10.0 + i) % 2 == 0 else 1.0
			draw_rect(Rect2(x - 1.0, length - 1.0 + wobble, column_width + 2.0, 1.0), foam_color)


## Tu imagen: se repite hacia abajo, se desplaza y se recorta al final de la columna.
func _draw_textured_column(i: int, x: float, length: float) -> void:
	var tex_size := texture.get_size()
	var frames := maxi(texture_frames, 1)
	var frame_width := tex_size.x / frames
	var frame := int(_time * frames_per_second) % frames if frames > 1 else 0
	var src_x := frame * frame_width + fposmod(float(i * column_width), frame_width)
	var tile_height := tex_size.y
	var scroll := floorf(fposmod(_time * flow_speed, tile_height))

	var y := scroll - tile_height
	while y < length:
		var y0 := maxf(y, 0.0)
		var y1 := minf(y + tile_height, length)
		if y1 > y0:
			draw_texture_rect_region(texture,
				Rect2(x, y0, column_width, y1 - y0),
				Rect2(src_x, y0 - y, column_width, y1 - y0))
		y += tile_height


## Agua de prueba dibujada por código (cuando no hay textura).
func _draw_procedural_column(i: int, x: float, length: float) -> void:
	draw_rect(Rect2(x, 0.0, column_width, length), water_color)

	# Rayas claras que bajan (cada columna con su propio desfase y largo).
	var period := 16.0
	var dash := 5.0 + float(i % 3) * 2.0
	var offset := fmod(_time * flow_speed + float((i * 37) % 11) * 5.0, period)
	var y := offset - period
	while y < length:
		var y0 := maxf(y, 0.0)
		var y1 := minf(y + dash, length)
		if y1 > y0:
			draw_rect(Rect2(x, y0, column_width, y1 - y0), streak_color)
		y += period


## true si `point` (global) está dentro del agua de esta cascada, sin paraguas por encima.
func is_point_wet(point: Vector2) -> bool:
	var half := width / 2.0
	var local_x := point.x - global_position.x
	if local_x < -half or local_x > half or point.y < global_position.y:
		return false
	var i := clampi(int((local_x + half) / column_width), 0, _column_count() - 1)
	return point.y <= _column_end_y(i, point.x)


# ---------------------------------------------------------------------------
# Internos
# ---------------------------------------------------------------------------

func _column_count() -> int:
	return maxi(int(ceil(width / column_width)), 1)


## Busca hasta dónde llega el agua en cada columna (primer sólido hacia abajo).
func _update_columns() -> void:
	var count := _column_count()
	var space := get_world_2d().direct_space_state
	var exclude := WaterUtils.exclude_for(_player)
	var top_y := global_position.y
	var bottom_y := top_y + max_height
	var left := global_position.x - width / 2.0

	_end_ys.resize(count)
	for i in count:
		var x := left + (i + 0.5) * column_width
		_end_ys[i] = minf(WaterUtils.solid_y_below(space, x, top_y, bottom_y, block_mask, exclude), bottom_y)


## Y global donde termina la columna i: el suelo/techo o la copa del paraguas, lo que esté más arriba.
func _column_end_y(i: int, x_global: float) -> float:
	var end_y := _end_ys[i] if i < _end_ys.size() else global_position.y + max_height
	if _umbrella:
		end_y = minf(end_y, _umbrella.top_y_at(x_global))
	return end_y


## Avisa (una vez) si hay jugador pero no se encuentra el paraguas: sin él, no detiene el agua.
func _check_umbrella_found(delta: float) -> void:
	if _umbrella or _player == null or _warned_no_umbrella:
		return
	_no_umbrella_time += delta
	if _no_umbrella_time > 1.5:
		_warned_no_umbrella = true
		push_warning("Waterfall: no encuentro el nodo Umbrella. Instancia umbrella.tscn como hijo del Player y usa el umbrella.gd nuevo; si no, el paraguas no detiene el agua.")


func _update_player(delta: float) -> void:
	if _player == null or _player.is_dead or _end_ys.is_empty():
		return
	var wet := is_point_wet(_player.global_position + Vector2(0.0, -12.0))
	if wet != player_wet:
		player_wet = wet
		player_wet_changed.emit(wet)
		_tick_timer = 0.0

	if wet and damage_enabled and damage_per_tick > 0:
		_tick_timer += delta
		if _tick_timer >= tick_interval:
			_tick_timer = 0.0
			_player.take_damage(damage_per_tick)
