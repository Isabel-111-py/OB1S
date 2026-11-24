@tool
class_name ElevatorCallStation
extends Area2D

## Estación de llamada prehistórica: poste de madera envuelto en lianas con un hongo bioluminiscente de llamada.

func _draw() -> void:
	var elevator: Elevator = get_parent() as Elevator
	var is_moving: bool = false
	var pulse: float = 0.0
	
	# Color del hongo según si el elevador está viajando, ya está aquí, o está disponible para llamar
	var shroom_color := Color(0.24, 0.94, 0.56) # Verde: disponible para llamar
	var halo_color := Color(0.24, 0.94, 0.56, 0.35)
	
	if elevator:
		if elevator.current_state == Elevator.ElevatorState.MOVING_TO_END or elevator.current_state == Elevator.ElevatorState.MOVING_TO_START:
			is_moving = true
			pulse = (sin(Time.get_ticks_msec() * 0.012) + 1.0) * 0.5
			# Parpadeo místico de aviso
			shroom_color = Color(0.96, 0.62, 0.20).lerp(Color(0.88, 0.30, 0.75), pulse)
			halo_color = Color(shroom_color.r, shroom_color.g, shroom_color.b, 0.25 + 0.30 * pulse)
		elif elevator.current_state == Elevator.ElevatorState.IDLE_AT_END:
			# El elevador ya está en este piso
			shroom_color = Color(0.26, 0.82, 0.98) # Cian
			halo_color = Color(0.26, 0.82, 0.98, 0.35)
		else:
			# Está en el origen (listo para ser llamado)
			shroom_color = Color(0.24, 0.94, 0.56)
			halo_color = Color(0.24, 0.94, 0.56, 0.35)
	
	# -------------------------------------------------------------
	# 1. POSTE RÚSTICO DE MADERA (Corteza y vetas)
	# -------------------------------------------------------------
	var post_w := 6.0
	var post_h := 22.0
	var post_rect := Rect2(-post_w * 0.5, -post_h, post_w, post_h)
	draw_rect(post_rect, Color(0.34, 0.22, 0.14), true) # Tronco
	draw_rect(post_rect, Color(0.18, 0.11, 0.07), false, 1.0) # Borde
	# Veta de madera
	draw_line(Vector2(0, -2), Vector2(0, -post_h + 3), Color(0.24, 0.15, 0.09), 1.0)
	
	# -------------------------------------------------------------
	# 2. ENREDADERA / LIANA ESPIRAL ALREDEDOR DEL POSTE
	# -------------------------------------------------------------
	draw_line(Vector2(-post_w * 0.5, -3), Vector2(post_w * 0.5, -7), Color(0.36, 0.58, 0.22), 1.8)
	draw_line(Vector2(-post_w * 0.5, -10), Vector2(post_w * 0.5, -14), Color(0.36, 0.58, 0.22), 1.8)
	# Hoja pequeña de adorno
	draw_circle(Vector2(post_w * 0.5 + 2.0, -14.0), 1.5, Color(0.42, 0.68, 0.26))
	
	# -------------------------------------------------------------
	# 3. MENSULA / SOPORTE TALLADO SUPERIOR
	# -------------------------------------------------------------
	var bracket_w := 12.0
	var bracket_rect := Rect2(-bracket_w * 0.5, -post_h - 2.0, bracket_w, 4.0)
	draw_rect(bracket_rect, Color(0.48, 0.32, 0.20), true)
	draw_line(Vector2(-bracket_w * 0.5, -post_h - 2.0), Vector2(bracket_w * 0.5, -post_h - 2.0), Color(0.66, 0.48, 0.32), 1.0)
	
	# -------------------------------------------------------------
	# 4. HONGO BOTÓN DE LLAMADA BIOLUMINISCENTE
	# -------------------------------------------------------------
	var shroom_center := Vector2(0, -post_h - 7.0)
	
	# Aura luminiscente
	var halo_r := 7.0 + (pulse * 2.5 if is_moving else 0.0)
	draw_circle(shroom_center, halo_r, halo_color)
	draw_circle(shroom_center, halo_r * 0.5, Color(shroom_color.r, shroom_color.g, shroom_color.b, 0.6))
	
	# Tallo del hongo
	draw_line(Vector2(0, -post_h - 2.0), shroom_center, Color(0.92, 0.90, 0.82), 2.0)
	
	# Sombrerillo
	var cap_pts := PackedVector2Array([
		shroom_center + Vector2(-4.0, 0.0),
		shroom_center + Vector2(-3.0, -3.5),
		shroom_center + Vector2(0.0, -5.0),
		shroom_center + Vector2(3.0, -3.5),
		shroom_center + Vector2(4.0, 0.0),
		shroom_center + Vector2(0.0, 1.0)
	])
	draw_colored_polygon(cap_pts, shroom_color)
	draw_line(shroom_center + Vector2(-4.0, 0.0), shroom_center + Vector2(4.0, 0.0), Color(0.18, 0.12, 0.08), 1.0)
	
	# Motas brillantes
	draw_circle(shroom_center + Vector2(-1.5, -2.5), 0.8, Color.WHITE)
	draw_circle(shroom_center + Vector2(1.5, -2.0), 0.8, Color.WHITE)
