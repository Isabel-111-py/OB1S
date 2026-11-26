@tool
extends Node2D

## Renderizador visual procedimental para la compuerta de madera y hongos prehistóricos.
## Dibuja barrotes de madera nudosa, amarres de lianas con musgo,
## pequeños hongos silvestres y un núcleo fúngico bioluminiscente central.

var gate: Gate = null


func _ready() -> void:
	_resolve_gate()
	queue_redraw()


func _resolve_gate() -> void:
	var p := get_parent()
	if p and p.get_parent() is Gate:
		gate = p.get_parent() as Gate
	elif owner is Gate:
		gate = owner as Gate


func _draw() -> void:
	if not gate:
		_resolve_gate()
	if not gate:
		return
	
	var is_vert := (gate.orientation == "Vertical")
	var length := gate.gate_length
	var thickness := gate.gate_thickness
	var half_len := length * 0.5
	var half_th := thickness * 0.5
	
	# Colores base de madera petrificada y corteza
	var wood_dark := Color(0.24, 0.16, 0.10)
	var wood_mid := Color(0.38, 0.25, 0.15)
	var wood_light := Color(0.50, 0.35, 0.22)
	var vine_color := Color(0.34, 0.52, 0.20)
	var moss_color := Color(0.44, 0.64, 0.26)
	
	# Color del núcleo fúngico central
	var rune_color: Color
	var aura_color: Color
	if gate.is_locked:
		# Rojo / carmesí pulsante de alerta (bloqueado por combate de jefe)
		var pulse := (sin(Time.get_ticks_msec() * 0.008) + 1.0) * 0.5
		rune_color = Color(0.95, 0.22, 0.18).lerp(Color(1.0, 0.55, 0.20), pulse)
		aura_color = Color(rune_color.r, rune_color.g, rune_color.b, 0.45 + pulse * 0.35)
	elif gate.is_open or gate.open_progress > 0.8:
		# Cian / verde esmeralda bioluminiscente de paso libre
		rune_color = Color(0.22, 0.94, 0.72)
		aura_color = Color(0.22, 0.94, 0.72, 0.35)
	else:
		# Ámbar suave fúngico de reposo (cerrada normalmente)
		rune_color = Color(0.96, 0.62, 0.22)
		aura_color = Color(0.96, 0.62, 0.22, 0.25)
	
	if is_vert:
		_draw_vertical_gate(half_len, half_th, length, thickness, wood_dark, wood_mid, wood_light, vine_color, moss_color, rune_color, aura_color)
	else:
		_draw_horizontal_gate(half_len, half_th, length, thickness, wood_dark, wood_mid, wood_light, vine_color, moss_color, rune_color, aura_color)


func _draw_vertical_gate(half_len: float, half_th: float, length: float, thickness: float, wood_dark: Color, wood_mid: Color, wood_light: Color, vine_color: Color, moss_color: Color, rune_color: Color, aura_color: Color) -> void:
	# 1. Barrotes verticales de troncos nudosos
	var num_bars := 2 if thickness < 20.0 else 3
	var bar_spacing := (thickness - 4.0) / float(maxi(num_bars - 1, 1))
	
	for i in range(num_bars):
		var bx := -half_th + 2.0 + float(i) * bar_spacing
		var bar_w := maxf(thickness / float(num_bars) * 0.8, 3.0)
		var bar_rect := Rect2(bx - bar_w * 0.5, -half_len, bar_w, length)
		
		# Sombra y base del barrote
		draw_rect(bar_rect, wood_dark, true)
		# Veta de madera
		draw_rect(Rect2(bx - bar_w * 0.5 + 1.0, -half_len + 1.0, bar_w - 2.0, length - 2.0), wood_mid, true)
		# Línea de brillo en la madera
		draw_line(Vector2(bx, -half_len + 3.0), Vector2(bx, half_len - 3.0), wood_light, 1.0)
		
		# Puntas afiladas o estacas en los extremos
		var top_tip := PackedVector2Array([
			Vector2(bx - bar_w * 0.5, -half_len),
			Vector2(bx, -half_len - 3.0),
			Vector2(bx + bar_w * 0.5, -half_len)
		])
		draw_colored_polygon(top_tip, wood_mid)
		
		var bot_tip := PackedVector2Array([
			Vector2(bx - bar_w * 0.5, half_len),
			Vector2(bx, half_len + 3.0),
			Vector2(bx + bar_w * 0.5, half_len)
		])
		draw_colored_polygon(bot_tip, wood_mid)
	
	# 2. Travesaños y amarres de lianas con musgo
	var step_y := 24.0
	var steps := maxi(int(length / step_y), 2)
	for s in range(steps + 1):
		var y := -half_len + (float(s) / float(steps)) * length
		y = clampf(y, -half_len + 6.0, half_len - 6.0)
		
		# Travesaño de madera
		draw_line(Vector2(-half_th, y), Vector2(half_th, y), wood_dark, 3.0)
		draw_line(Vector2(-half_th, y), Vector2(half_th, y), wood_light, 1.2)
		
		# Amarre helicoidal de liana
		draw_line(Vector2(-half_th - 1.0, y - 1.5), Vector2(half_th + 1.0, y + 1.5), vine_color, 1.5)
		draw_line(Vector2(-half_th - 1.0, y + 1.5), Vector2(half_th + 1.0, y - 1.5), moss_color, 1.0)
		
		# Brote de musgo o pequeña hoja en el amarre
		if s % 2 == 1:
			draw_circle(Vector2(-half_th, y), 1.6, moss_color)
		else:
			draw_circle(Vector2(half_th, y), 1.6, moss_color)
	
	# 3. Honguitos silvestres brotando a los costados
	var shroom_spots := [-half_len * 0.6, half_len * 0.5]
	for sy in shroom_spots:
		var sx := -half_th - 1.0
		draw_circle(Vector2(sx, sy), 1.8, Color(0.9, 0.85, 0.75)) # Tallo
		draw_circle(Vector2(sx - 1.0, sy - 1.5), 2.2, Color(0.3, 0.85, 0.9)) # Sombrero brillante
	
	# 4. Núcleo fúngico de bloqueo central
	_draw_central_rune(Vector2.ZERO, rune_color, aura_color, minf(thickness * 0.5 + 2.0, 10.0))


func _draw_horizontal_gate(half_len: float, half_th: float, length: float, thickness: float, wood_dark: Color, wood_mid: Color, wood_light: Color, vine_color: Color, moss_color: Color, rune_color: Color, aura_color: Color) -> void:
	# 1. Vigas o tablones horizontales
	var num_bars := 2 if thickness < 20.0 else 3
	var bar_spacing := (thickness - 4.0) / float(maxi(num_bars - 1, 1))
	
	for i in range(num_bars):
		var by := -half_th + 2.0 + float(i) * bar_spacing
		var bar_h := maxf(thickness / float(num_bars) * 0.8, 3.0)
		var bar_rect := Rect2(-half_len, by - bar_h * 0.5, length, bar_h)
		
		draw_rect(bar_rect, wood_dark, true)
		draw_rect(Rect2(-half_len + 1.0, by - bar_h * 0.5 + 1.0, length - 2.0, bar_h - 2.0), wood_mid, true)
		draw_line(Vector2(-half_len + 3.0, by), Vector2(half_len - 3.0, by), wood_light, 1.0)
	
	# 2. Travesaños verticales y amarres de liana
	var step_x := 24.0
	var steps := maxi(int(length / step_x), 2)
	for s in range(steps + 1):
		var x := -half_len + (float(s) / float(steps)) * length
		x = clampf(x, -half_len + 6.0, half_len - 6.0)
		
		draw_line(Vector2(x, -half_th), Vector2(x, half_th), wood_dark, 3.0)
		draw_line(Vector2(x, -half_th), Vector2(x, half_th), wood_light, 1.2)
		
		# Amarre de liana
		draw_line(Vector2(x - 1.5, -half_th - 1.0), Vector2(x + 1.5, half_th + 1.0), vine_color, 1.5)
		draw_line(Vector2(x + 1.5, -half_th - 1.0), Vector2(x - 1.5, half_th + 1.0), moss_color, 1.0)
		
		if s % 2 == 0:
			draw_circle(Vector2(x, -half_th), 1.6, moss_color)
		else:
			draw_circle(Vector2(x, half_th), 1.6, moss_color)
	
	# 3. Honguitos silvestres
	var shroom_spots := [-half_len * 0.5, half_len * 0.6]
	for sx in shroom_spots:
		var sy := -half_th - 1.0
		draw_circle(Vector2(sx, sy), 1.8, Color(0.9, 0.85, 0.75))
		draw_circle(Vector2(sx, sy - 1.5), 2.2, Color(0.3, 0.85, 0.9))
	
	# 4. Núcleo fúngico de bloqueo central
	_draw_central_rune(Vector2.ZERO, rune_color, aura_color, minf(thickness * 0.5 + 2.0, 10.0))


func _draw_central_rune(pos: Vector2, rune_color: Color, aura_color: Color, radius: float) -> void:
	# Disco de madera labrada de fondo
	draw_circle(pos, radius + 2.5, Color(0.20, 0.13, 0.08))
	draw_circle(pos, radius + 1.2, Color(0.38, 0.25, 0.16))
	
	# Aura bioluminiscente
	draw_circle(pos, radius + 4.0, aura_color)
	
	# Gema o sombrerillo fúngico central
	draw_circle(pos, radius, rune_color)
	
	# Puntos o esporas brillantes interiores
	draw_circle(pos, radius * 0.45, Color.WHITE)
	draw_circle(pos + Vector2(-radius * 0.35, -radius * 0.35), 0.8, Color.WHITE)
