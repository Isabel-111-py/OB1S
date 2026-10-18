extends State
## Fase ascendente del salto.
## Mantener el botón presionado (hasta jump_hold_time) sostiene la subida;
## soltarlo antes recorta el salto con jump_cut_multiplier.

var _hold_timer: float = 0.0
var _sustaining: bool = false


func enter(_msg: Dictionary = {}) -> void:
	player.velocity.y = player.jump_velocity
	player.consume_jump()
	_hold_timer = 0.0
	_sustaining = true


func physics_update(delta: float) -> void:
	var direction := player.get_input_direction()

	if _sustaining:
		_hold_timer += delta
		if player.is_on_ceiling():
			# Golpeó el techo: la subida termina.
			_sustaining = false
		elif not Input.is_action_pressed("jump"):
			# Soltó el botón antes de tiempo: recorta el salto.
			_sustaining = false
			player.velocity.y *= player.jump_cut_multiplier
		elif _hold_timer >= player.jump_hold_time:
			# Alcanzó el tiempo máximo: la gravedad toma el control.
			_sustaining = false
		else:
			# Sigue presionado: se mantiene la velocidad de subida.
			player.velocity.y = player.jump_velocity

	if not _sustaining:
		player.apply_gravity(delta)

	player.move_air(direction, delta)
	player.face(direction)
	player.move_and_slide()

	# Al llegar al punto más alto (o golpear el techo) empieza la caída.
	if player.velocity.y >= 0.0:
		state_machine.transition_to("Fall")
