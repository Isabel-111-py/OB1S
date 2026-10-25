extends State
## Dash (turbo): impulso horizontal rápido y recto, incluso en el aire.
## Lo activa el Player al presionar la acción "turbo". Animación por defecto: "dash".

var _timer: float = 0.0
var _direction: float = 1.0


func enter(_msg: Dictionary = {}) -> void:
	_timer = player.dash_time
	# Va hacia donde presionas; si no presionas nada, hacia donde mira el personaje.
	var input_direction := player.get_input_direction()
	_direction = signf(input_direction) if not is_zero_approx(input_direction) else player.facing
	player.face(_direction)


func exit() -> void:
	# El cooldown empieza cuando termina el dash (o cuando algo lo interrumpe, como un golpe).
	player.dash_cooldown_timer = player.dash_cooldown


func physics_update(delta: float) -> void:
	_timer -= delta

	# Velocidad horizontal constante y sin gravedad: el dash es recto.
	player.velocity.x = _direction * player.dash_speed
	player.velocity.y = 0.0
	player.move_and_slide()

	if _timer <= 0.0 or player.is_on_wall():
		_end_dash()


func _end_dash() -> void:
	# Vuelve a la velocidad máxima actual (normal, o turbo si sigues manteniendo el botón).
	player.velocity.x = _direction * player.get_max_speed()

	if player.is_on_floor():
		if is_zero_approx(player.get_input_direction()):
			state_machine.transition_to("Idle")
		else:
			state_machine.transition_to("Run")
	else:
		state_machine.transition_to("Fall")
