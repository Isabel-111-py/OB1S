extends State
## Corriendo en el suelo. La velocidad sube de forma progresiva (ver time_to_max_speed en Player).


func physics_update(delta: float) -> void:
	var direction := player.get_input_direction()

	player.apply_gravity(delta)
	player.move_ground(direction, delta)
	player.face(direction)
	player.move_and_slide()

	if not player.is_on_floor():
		state_machine.transition_to("Fall")
	elif player.jump_requested():
		state_machine.transition_to("Jump")
	elif is_zero_approx(direction):
		state_machine.transition_to("Idle")
