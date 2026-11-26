class_name Umbrella
extends Node2D
## Paraguas sobre la cabeza del jugador. Solo se ve cuando está equipado (ver Inventory).
## Mientras está equipado el arco no dispara; para el agua (lluvia, cascadas) basta con preguntar
## `Inventory.umbrella_equipped`: si es true, el jugador está cubierto.
##
## Uso: instancia `umbrella.tscn` como hijo del nodo Player. Si el jugador tiene un nodo "Mono",
## el paraguas lo sigue y queda sobre sus manos (el mono lo sostiene); si no, se coloca sobre la
## cabeza del jugador (o donde lo dejes en el editor).

## Nodo que sostiene el paraguas. Vacío = busca un hermano llamado "Mono".
@export var follow_node: Node2D
## Dónde queda el nodo del paraguas respecto a `follow_node` (px). Súbelo o bájalo para que el
## mango coincida con las manos del mono.
@export var follow_offset: Vector2 = Vector2(0, -28)

## Imagen del paraguas (centrada en el nodo). Vacío = un paraguas dibujado por código.
@export var texture: Texture2D
## Altura (px) sobre el origen del jugador si dejas el nodo en (0, 0).
@export var default_height: float = 34.0
@export_group("Escudo (lo que detiene el agua)")
## Mitad del ancho (px) de la zona que detiene el agua. 0 = automático: el radio de la copa o,
## si usas una imagen, la mitad de su ancho.
@export var shield_half_width: float = 0.0
## Altura (px) de la copa por encima del origen del nodo. 0 = automático: el radio de la copa o,
## si usas una imagen, la mitad de su alto.
@export var shield_height: float = 0.0
## Dibuja en rojo la zona que detiene el agua (mientras el paraguas está equipado), para ajustarla
## a tu imagen con los dos valores de arriba.
@export var show_shield: bool = false

@export_group("Paraguas dibujado por código")
@export var canopy_radius: float = 18.0
@export var canopy_color: Color = Color(0.85, 0.2, 0.25)
@export var stripe_color: Color = Color(0.95, 0.95, 0.95)
@export var handle_color: Color = Color(0.25, 0.15, 0.1)
## Segundos de la animación al abrirlo.
@export var open_time: float = 0.15

var _tween: Tween


func _ready() -> void:
	add_to_group("umbrella") # la lluvia y las cascadas lo buscan por este grupo
	z_index = 1 # por encima del dibujo del jugador
	if follow_node == null:
		follow_node = get_node_or_null("../Mono") as Node2D
	if follow_node == null and position.is_zero_approx():
		position.y = -default_height
	visible = Inventory.umbrella_equipped
	Inventory.umbrella_toggled.connect(_on_toggled)


func _process(_delta: float) -> void:
	# Sigue al mono (que se balancea con las animaciones del jugador).
	if follow_node and visible:
		global_position = follow_node.global_position + follow_offset



## Altura (coordenada Y global) de la copa del paraguas justo encima de `global_x`.
## Devuelve INF si el paraguas no está abierto o `global_x` queda fuera de la copa.
## El agua que cae usa esto para detenerse al chocar con el paraguas.
func top_y_at(global_x: float) -> float:
	if not Inventory.umbrella_equipped or not visible:
		return INF
	var half_width := _shield_half_width()
	var dx := absf(global_x - global_position.x)
	if dx >= half_width:
		return INF
	# La copa se aproxima con media elipse.
	var ratio := dx / half_width
	return global_position.y - _shield_height() * sqrt(1.0 - ratio * ratio)


func _shield_half_width() -> float:
	if shield_half_width > 0.0:
		return shield_half_width
	return texture.get_width() / 2.0 if texture else canopy_radius


func _shield_height() -> float:
	if shield_height > 0.0:
		return shield_height
	return texture.get_height() / 2.0 if texture else canopy_radius


func _on_toggled(equipped: bool) -> void:
	if _tween:
		_tween.kill()
	visible = equipped
	if equipped:
		# Se abre "de golpe": parte aplastado y recupera su forma.
		scale = Vector2(1.0, 0.2)
		_tween = create_tween()
		_tween.tween_property(self, "scale", Vector2.ONE, open_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	if texture:
		draw_texture(texture, -texture.get_size() / 2.0)
	else:
		_draw_default_umbrella()
	if show_shield:
		_draw_shield()


## Contorno rojo de la zona que detiene el agua.
func _draw_shield() -> void:
	var hw := _shield_half_width()
	var h := _shield_height()
	var points := PackedVector2Array()
	for i in 25:
		var angle := PI * float(i) / 24.0
		points.append(Vector2(cos(angle) * hw, -sin(angle) * h))
	draw_polyline(points, Color(1.0, 0.1, 0.1, 0.9), 1.0)
	draw_line(Vector2(-hw, 0.0), Vector2(hw, 0.0), Color(1.0, 0.1, 0.1, 0.5), 1.0)


func _draw_default_umbrella() -> void:
	var r := canopy_radius
	# Copa: media circunferencia.
	var arc := PackedVector2Array()
	for i in 17:
		var angle := PI + PI * float(i) / 16.0
		arc.append(Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(arc, canopy_color)
	# Franja central clara.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-r * 0.25, -r * 0.97), Vector2(r * 0.25, -r * 0.97), Vector2(r * 0.12, 0), Vector2(-r * 0.12, 0)
	]), stripe_color)
	draw_line(Vector2(-r, 0), Vector2(r, 0), canopy_color.darkened(0.3), 1.0)
	# Mango con gancho.
	draw_line(Vector2(0, 0), Vector2(0, r * 0.9), handle_color, 1.5)
	draw_arc(Vector2(-2.5, r * 0.9), 2.5, 0.0, PI, 8, handle_color, 1.5)
