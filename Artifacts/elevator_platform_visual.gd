@tool
class_name ElevatorPlatformVisual
extends Node2D

## Renderizado de la plataforma de madera rústica y tecnología fúngica prehistórica.
## Creada por una sociedad de hongos evolucionados:
## - Tablones de madera labrada con vetas y textura de corteza.
## - Amarres de lianas y cuerdas vegetales en los extremos con brotes de musgo.
## - Pequeños hongos silvestres decorativos brotando de la madera.
## - Un hongo bioluminiscente interactivo montado en un pedestal de rama que actúa como botón pulsador.

func _draw() -> void:
	var elevator: Elevator = _get_elevator()
	var w: float = 64.0
	var h: float = 12.0
	var is_moving: bool = false
	var pulse: float = 0.0
	
	# Color del hongo botón según el estado
	var mushroom_cap_color := Color(0.24, 0.92, 0.58) # Verde esmeralda bioluminiscente en inicio
	var mushroom_halo_color := Color(0.24, 0.92, 0.58, 0.35)
	
	if elevator:
		w = elevator.platform_width
		h = elevator.platform_height
		
		match elevator.current_state:
			Elevator.ElevatorState.IDLE_AT_START:
				mushroom_cap_color = Color(0.24, 0.94, 0.56) # Esporas listas en base
				mushroom_halo_color = Color(0.24, 0.94, 0.56, 0.35)
			Elevator.ElevatorState.MOVING_TO_END, Elevator.ElevatorState.MOVING_TO_START:
				is_moving = true
				pulse = (sin(Time.get_ticks_msec() * 0.012) + 1.0) * 0.5
				# Esporas mágicas pulsantes durante el viaje (ámbar a magenta místico)
				mushroom_cap_color = Color(0.96, 0.62, 0.20).lerp(Color(0.88, 0.30, 0.75), pulse)
				mushroom_halo_color = Color(mushroom_cap_color.r, mushroom_cap_color.g, mushroom_cap_color.b, 0.25 + 0.30 * pulse)
			Elevator.ElevatorState.IDLE_AT_END:
				mushroom_cap_color = Color(0.26, 0.82, 0.98) # Cian místico en plataforma destino
				mushroom_halo_color = Color(0.26, 0.82, 0.98, 0.38)
	
	var half_w := w * 0.5
	var half_h := h * 0.5
	
	# -------------------------------------------------------------
	# 1. TRONCO / VIGA BASE INFERIOR (Corteza rústica)
	# -------------------------------------------------------------
	var bark_rect := Rect2(-half_w, -half_h, w, h)
	draw_rect(bark_rect, Color(0.26, 0.16, 0.10), true) # Corteza oscura
	# Sombra profunda en la base
	draw_line(Vector2(-half_w, half_h), Vector2(half_w, half_h), Color(0.14, 0.09, 0.06), 1.5)
	
	# Vetas y hendiduras naturales de la corteza
	draw_line(Vector2(-half_w + 6, half_h - 3), Vector2(-half_w + 22, half_h - 3), Color(0.18, 0.11, 0.07), 1.0)
	draw_line(Vector2(-half_w + 28, half_h - 2), Vector2(half_w - 20, half_h - 2), Color(0.18, 0.11, 0.07), 1.0)
	
	# Clavijas de madera prehistóricas (remaches de madera tallada)
	var num_pegs := int(w / 18.0)
	for i in range(num_pegs):
		var px := -half_w + 10.0 + float(i) * 18.0
		if px < half_w - 8.0:
			draw_circle(Vector2(px, half_h - 3.5), 1.5, Color(0.16, 0.10, 0.06)) # Orificio
			draw_circle(Vector2(px, half_h - 3.5), 1.0, Color(0.42, 0.28, 0.18)) # Clavija
	
	# -------------------------------------------------------------
	# 2. TABLONES DEL PISO (Madera labrada prehistórica)
	# -------------------------------------------------------------
	var deck_h := maxf(h * 0.52, 4.0)
	var plank_width := 14.0
	var total_planks := int(ceil(w / plank_width))
	
	for i in range(total_planks):
		var x_start := -half_w + float(i) * plank_width
		var cur_plank_w := minf(plank_width, half_w - x_start)
		if cur_plank_w <= 0:
			continue
		
		# Variación sutil de tono entre tablones tallados a mano
		var plank_color: Color
		match i % 3:
			0: plank_color = Color(0.48, 0.32, 0.20)
			1: plank_color = Color(0.43, 0.28, 0.17)
			_: plank_color = Color(0.52, 0.35, 0.22)
		
		# Cuerpo del tablón
		draw_rect(Rect2(x_start, -half_h, cur_plank_w, deck_h), plank_color, true)
		# Borde de luz superior del tablón (madera pulida)
		draw_line(Vector2(x_start + 1.0, -half_h + 1.0), Vector2(x_start + cur_plank_w - 1.0, -half_h + 1.0), Color(0.66, 0.48, 0.32), 1.0)
		# Veta de madera interna
		if cur_plank_w > 6.0:
			draw_line(Vector2(x_start + 3.0, -half_h + 3.0), Vector2(x_start + cur_plank_w - 3.0, -half_h + 3.0), Color(0.36, 0.23, 0.14), 1.0)
		# Separación oscura entre tablones
		draw_line(Vector2(x_start, -half_h), Vector2(x_start, -half_h + deck_h), Color(0.18, 0.11, 0.07), 1.0)
	
	# -------------------------------------------------------------
	# 3. AMARRES DE CUERDA Y LIANAS EN LOS EXTREMOS
	# -------------------------------------------------------------
	var wrap_w := minf(9.0, w * 0.15)
	_draw_rope_wrap(Vector2(-half_w, -half_h), wrap_w, h)
	_draw_rope_wrap(Vector2(half_w - wrap_w, -half_h), wrap_w, h)
	
	# -------------------------------------------------------------
	# 4. HONGUITOS SILVESTRES DECORATIVOS EN LA ESQUINA DERECHA
	# -------------------------------------------------------------
	if w >= 48.0:
		var shroom_base_x := half_w - wrap_w - 6.0
		# Hongo pequeño 1
		draw_line(Vector2(shroom_base_x, -half_h), Vector2(shroom_base_x - 1, -half_h - 5), Color(0.85, 0.82, 0.72), 1.5)
		draw_circle(Vector2(shroom_base_x - 1, -half_h - 6), 2.5, Color(0.88, 0.28, 0.22)) # Sombrerillo rojo
		draw_circle(Vector2(shroom_base_x - 1.5, -half_h - 6.5), 0.7, Color(1, 1, 1, 0.9)) # Mota blanca
		# Hongo pequeño 2 (compañero)
		draw_line(Vector2(shroom_base_x + 3, -half_h), Vector2(shroom_base_x + 4, -half_h - 3), Color(0.85, 0.82, 0.72), 1.2)
		draw_circle(Vector2(shroom_base_x + 4, -half_h - 4), 1.8, Color(0.78, 0.45, 0.20)) # Sombrerillo café claro
	
	# -------------------------------------------------------------
	# 5. PEDESTAL DE RAMA Y HONGO BIOLUMINISCENTE (EL BOTÓN)
	# -------------------------------------------------------------
	var console_x := -half_w + wrap_w + 5.0
	var stalk_h := 11.0
	var shroom_center := Vector2(console_x + 3.0, -half_h - stalk_h)
	
	# Tallo / rama retorcida de soporte
	draw_line(Vector2(console_x + 2.0, -half_h), Vector2(console_x + 3.0, -half_h - stalk_h * 0.5), Color(0.34, 0.22, 0.14), 2.5)
	draw_line(Vector2(console_x + 3.0, -half_h - stalk_h * 0.5), shroom_center + Vector2(0, 3), Color(0.34, 0.22, 0.14), 2.0)
	# Amarre de liana en la base del pedestal
	draw_line(Vector2(console_x + 0.5, -half_h - 2), Vector2(console_x + 4.5, -half_h - 2), Color(0.42, 0.62, 0.26), 1.5)
	
	# Aura bioluminiscente (brillo místico de las esporas)
	var halo_radius := 7.0 + (pulse * 2.5 if is_moving else 0.0)
	draw_circle(shroom_center, halo_radius, mushroom_halo_color)
	draw_circle(shroom_center, halo_radius * 0.5, Color(mushroom_cap_color.r, mushroom_cap_color.g, mushroom_cap_color.b, 0.6))
	
	# Pie/tallo del hongo botón (blanquecino orgánico)
	draw_line(shroom_center + Vector2(0, 3), shroom_center, Color(0.92, 0.90, 0.82), 2.0)
	
	# Sombrerillo del hongo (forma de cúpula luminosa)
	var cap_pts := PackedVector2Array([
		shroom_center + Vector2(-4.0, 0.0),
		shroom_center + Vector2(-3.0, -3.5),
		shroom_center + Vector2(0.0, -5.0),
		shroom_center + Vector2(3.0, -3.5),
		shroom_center + Vector2(4.0, 0.0),
		shroom_center + Vector2(0.0, 1.0)
	])
	draw_colored_polygon(cap_pts, mushroom_cap_color)
	# Borde inferior del sombrerillo
	draw_line(shroom_center + Vector2(-4.0, 0.0), shroom_center + Vector2(4.0, 0.0), Color(0.18, 0.12, 0.08), 1.0)
	
	# Motas brillantes de esporas en el sombrero
	draw_circle(shroom_center + Vector2(-1.5, -2.5), 0.9, Color.WHITE)
	draw_circle(shroom_center + Vector2(1.5, -2.0), 0.8, Color.WHITE)
	draw_circle(shroom_center + Vector2(0.0, -4.0), 0.7, Color.WHITE)
	
	# Partículas de esporas flotantes si está en movimiento
	if is_moving:
		var spore1_y := -half_h - stalk_h - 7.0 - pulse * 4.0
		var spore2_y := -half_h - stalk_h - 11.0 + pulse * 3.0
		draw_circle(Vector2(console_x + 1.0, spore1_y), 1.0, Color(mushroom_cap_color.r, mushroom_cap_color.g, mushroom_cap_color.b, 0.85))
		draw_circle(Vector2(console_x + 6.0, spore2_y), 0.8, Color(mushroom_cap_color.r, mushroom_cap_color.g, mushroom_cap_color.b, 0.75))


func _draw_rope_wrap(pos: Vector2, width: float, height: float) -> void:
	# Base de cuerda de cáñamo / liana trenzada
	draw_rect(Rect2(pos.x, pos.y, width, height), Color(0.42, 0.32, 0.20), true)
	
	# Hebras diagonales de la cuerda
	var y_step := 3.5
	var y := pos.y + 1.0
	while y < pos.y + height:
		draw_line(Vector2(pos.x, y), Vector2(pos.x + width, y + 2.0), Color(0.60, 0.48, 0.32), 1.2)
		draw_line(Vector2(pos.x, y + 1.5), Vector2(pos.x + width, y + 3.5), Color(0.28, 0.20, 0.12), 1.0)
		y += y_step
	
	# Brote de musgo vegetal verde en el amarre
	draw_circle(Vector2(pos.x + width * 0.5, pos.y - 1.0), 1.8, Color(0.36, 0.60, 0.22))
	draw_circle(Vector2(pos.x + width * 0.2, pos.y), 1.2, Color(0.28, 0.50, 0.18))


func _get_elevator() -> Elevator:
	var p := get_parent()
	if p:
		return p.get_parent() as Elevator
	return null
