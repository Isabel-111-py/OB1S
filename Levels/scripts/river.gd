@tool
class_name River
extends Area2D
## Río: una zona rectangular de agua que colocas en el mapa. Se dibuja con corriente y, si quieres,
## hace algo al jugador cuando se mete en él (daño, caída al vacío, arrastre).
##
## Uso: instancia `river.tscn` y estira el rectángulo azul del nodo CollisionShape2D con los
## tiradores del editor. El agua se dibuja sola para llenar ese rectángulo (también en el editor).
## No lo rotes ni lo escales: cambia el tamaño del rectángulo.
##
## La lluvia y las cascadas se detienen en la superficie del río, con salpicaduras.

enum Effect {
	NONE, ## Solo se ve (el jugador puede atravesarlo).
	DAMAGE, ## Quita vida cada cierto tiempo mientras está hundido.
	RESPAWN, ## Agua mortal: quita vida y reaparece en el último checkpoint (como caer al vacío).
}

@export_group("Textura propia")
## Imagen del agua (pixel art, que se pueda repetir). Se desplaza con la corriente.
## Vacío = agua dibujada por código (colores de abajo).
@export var texture: Texture2D
## Si la imagen es una tira horizontal de varios cuadros de animación, cuántos cuadros tiene.
@export var texture_frames: int = 1
@export var frames_per_second: float = 6.0

@export_group("Aspecto")
@export var water_color: Color = Color(0.25, 0.55, 0.85, 0.6)
## Color con el que se oscurece el agua hacia el fondo.
@export var deep_color: Color = Color(0.08, 0.25, 0.55, 0.75)
@export var streak_color: Color = Color(0.8, 0.92, 1.0, 0.5)
## Línea ondulada de la superficie.
@export var show_surface_line: bool = true
@export var surface_color: Color = Color(0.92, 0.98, 1.0, 0.95)
@export var wave_height: float = 1.0
## Orden de dibujo. Más alto que el jugador = el jugador se ve "dentro" del agua.
@export var draw_z_index: int = 3

@export_group("Corriente")
## Velocidad (px/s) del agua: positivo a la derecha, negativo a la izquierda, 0 = aguas quietas.
@export var flow_speed: float = 40.0
## Si la corriente arrastra al jugador mientras está hundido.
@export var pushes_player: bool = true

@export_group("Efecto en el jugador")
@export var effect: Effect = Effect.DAMAGE
## Daño cada vez que pasa `tick_interval` (con el efecto DAMAGE). El primero es al hundirse.
@export var damage_per_tick: int = 1
@export var tick_interval: float = 1.0
## Cuántos píxeles debe hundirse el jugador (desde la superficie hasta sus pies) para que cuente.
@export var trigger_depth: float = 4.0

var _player: Player
var _shape_node: CollisionShape2D
var _time: float = 0.0
var _submerged: bool = false
var _tick_timer: float = 0.0


func _ready() -> void:
	z_index = draw_z_index
	_shape_node = _find_shape_node()
	if _shape_node and _shape_node.shape:
		_shape_node.shape.changed.connect(queue_redraw)
	if Engine.is_editor_hint():
		return

	add_to_group("rivers") # la lluvia y las cascadas lo buscan por este grupo
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _player == null or _player.is_dead or _player.process_mode == Node.PROCESS_MODE_DISABLED:
		_set_submerged(false)
		return

	var is_deep_enough := _player.global_position.y >= _surface_global_y() + trigger_depth
	_set_submerged(is_deep_enough)
	if not _submerged:
		return

	if pushes_player and not is_zero_approx(flow_speed):
		_player.move_and_collide(Vector2(flow_speed * delta, 0.0))

	match effect:
		Effect.DAMAGE:
			if damage_per_tick > 0:
				_tick_timer += delta
				if _tick_timer >= tick_interval:
					_tick_timer = 0.0
					_player.take_damage(damage_per_tick)
		Effect.RESPAWN:
			SceneManager.void_fall()


## Altura (Y global) de la superficie del río sobre `global_x`, o INF si ese x queda fuera del río.
func surface_y_at(global_x: float) -> float:
	var rect := _water_rect()
	if rect.size.x <= 0.0:
		return INF
	var left := to_global(rect.position).x
	var right := to_global(rect.end).x
	if global_x < left or global_x > right:
		return INF
	return to_global(rect.position).y


# ---------------------------------------------------------------------------
# Jugador dentro del río
# ---------------------------------------------------------------------------

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_player = body


func _on_body_exited(body: Node2D) -> void:
	if body == _player:
		_player = null
		_set_submerged(false)


func _set_submerged(value: bool) -> void:
	if value == _submerged:
		return
	_submerged = value
	# Al hundirse, el primer daño es inmediato.
	_tick_timer = tick_interval if value else 0.0


func _surface_global_y() -> float:
	return to_global(_water_rect().position).y


# ---------------------------------------------------------------------------
# Dibujo
# ---------------------------------------------------------------------------

func _find_shape_node() -> CollisionShape2D:
	for child in get_children():
		if child is CollisionShape2D:
			return child
	return null


## Rectángulo de agua (coordenadas locales): el del CollisionShape2D, que estiras con los tiradores.
func _water_rect() -> Rect2:
	if _shape_node == null:
		_shape_node = _find_shape_node()
	if _shape_node == null or not (_shape_node.shape is RectangleShape2D):
		return Rect2()
	var size: Vector2 = (_shape_node.shape as RectangleShape2D).size
	return Rect2((_shape_node.position - size / 2.0).round(), size.round())


func _draw() -> void:
	var rect := _water_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	if texture:
		_draw_textured(rect)
	else:
		_draw_procedural(rect)
	if show_surface_line:
		_draw_surface(rect)
	if Engine.is_editor_hint():
		draw_rect(rect, Color(1, 1, 1, 0.25), false, 1.0) # contorno solo en el editor


## Tu imagen: se repite en ambos sentidos, se desplaza con la corriente y se recorta al río.
func _draw_textured(rect: Rect2) -> void:
	var tex_size := texture.get_size()
	var frames := maxi(texture_frames, 1)
	var frame_width := tex_size.x / frames
	var tile_height := tex_size.y
	var frame := int(_time * frames_per_second) % frames if frames > 1 else 0
	var offset := floorf(fposmod(_time * flow_speed, frame_width))

	var y := rect.position.y
	while y < rect.end.y:
		var x := rect.position.x - frame_width + offset
		while x < rect.end.x:
			var dst := Rect2(x, y, frame_width, tile_height).intersection(rect)
			if dst.size.x > 0.0 and dst.size.y > 0.0:
				draw_texture_rect_region(texture, dst,
					Rect2(frame * frame_width + (dst.position.x - x), dst.position.y - y, dst.size.x, dst.size.y))
			x += frame_width
		y += tile_height


## Agua de prueba dibujada por código (cuando no hay textura).
func _draw_procedural(rect: Rect2) -> void:
	draw_rect(rect, water_color)

	# Más oscuro hacia el fondo.
	var layer_color := Color(deep_color.r, deep_color.g, deep_color.b, deep_color.a / 3.0)
	for i in 3:
		var top := rect.position.y + rect.size.y * float(i + 1) / 4.0
		draw_rect(Rect2(rect.position.x, top, rect.size.x, rect.end.y - top), layer_color)

	# Rayas claras que se mueven con la corriente (cada fila a una velocidad un poco distinta).
	var period := 28.0
	var row := 0
	var y := rect.position.y + 5.0
	while y < rect.end.y - 1.0:
		var speed := flow_speed * (0.7 + 0.3 * float(row % 3))
		var dash := 6.0 + float(row % 3) * 3.0
		var offset := fposmod(_time * speed + float(row * 11), period)
		var x := rect.position.x - period + offset
		while x < rect.end.x:
			var x0 := maxf(x, rect.position.x)
			var x1 := minf(x + dash, rect.end.x)
			if x1 > x0:
				draw_rect(Rect2(x0, floorf(y), x1 - x0, 1.0), streak_color)
			x += period
		y += 6.0
		row += 1


func _draw_surface(rect: Rect2) -> void:
	var points := PackedVector2Array()
	var x := rect.position.x
	while x < rect.end.x:
		points.append(Vector2(x, rect.position.y + roundf(sin(x * 0.35 - _time * 3.0) * wave_height)))
		x += 4.0
	points.append(Vector2(rect.end.x, rect.position.y))
	draw_polyline(points, surface_color, 1.0)
