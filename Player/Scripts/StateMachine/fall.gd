extends State
## Cayendo (después de saltar o de salir de una plataforma).


func physics_update(delta: float) -> void:
	var direction := player.get_input_direction()

	player.apply_gravity(delta, player.fall_gravity_multiplier)
	player.move_air(direction, delta)
	player.face(direction)
	player.move_and_slide()

	if player.is_on_floor():
		# Idle/Run se encargan de ejecutar el salto si quedó guardado en el buffer.
		if is_zero_approx(direction):
			state_machine.transition_to("Idle")
		else:
			state_machine.transition_to("Run")
	elif player.jump_requested():
		# Tiempo coyote: aún se puede saltar justo después de dejar la plataforma.
		state_machine.transition_to("Jump")
