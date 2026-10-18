extends State
## Quieto en el suelo.


func physics_update(delta: float) -> void:
	player.apply_gravity(delta)
	player.move_ground(0.0, delta) # rueda libre: avanza por inercia hasta frenar
	player.move_and_slide()

	if not player.is_on_floor():
		state_machine.transition_to("Fall")
	elif player.jump_requested():
		state_machine.transition_to("Jump")
	elif not is_zero_approx(player.get_input_direction()):
		state_machine.transition_to("Run")
