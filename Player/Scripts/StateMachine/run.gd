extends State
## Corriendo en el suelo. La velocidad sube de forma progresiva (ver time_to_max_speed en Player).
##
## Mientras mantengas presionado "turbo" (por ejemplo, justo después de un dash) el personaje corre
## más rápido (ver turbo_speed_multiplier en Player) y usa otra animación.

## Animación que se reproduce al correr con turbo mantenido (créala en el AnimationPlayer).
@export var turbo_animation: StringName = &"turbo"
## Si la animación de turbo no existe todavía, se usa "run" acelerada por este factor.
@export var turbo_fallback_speed_scale: float = 1.6


func enter(_msg: Dictionary = {}) -> void:
	_refresh_animation()


func exit() -> void:
	# Devuelve la velocidad normal de las animaciones para el siguiente estado.
	_set_speed_scale(1.0)


## El AnimationManager llama a esto al entrar al estado (por ejemplo, al terminar el dash).
func get_animation_name() -> StringName:
	if player and player.turbo_held and _has_turbo_animation():
		return turbo_animation
	return super.get_animation_name()


func physics_update(delta: float) -> void:
	var direction := player.get_input_direction()

	_refresh_animation()

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


## Cambia entre "run" y la animación de turbo según el botón esté presionado o no.
func _refresh_animation() -> void:
	var animator := player.animator
	if animator == null:
		return

	if player.turbo_held:
		if _has_turbo_animation():
			animator.play(turbo_animation)
			_set_speed_scale(1.0)
		else:
			animator.play(super.get_animation_name())
			_set_speed_scale(turbo_fallback_speed_scale)
	else:
		animator.play(super.get_animation_name())
		_set_speed_scale(1.0)


func _has_turbo_animation() -> bool:
	var animation_player: AnimationPlayer = player.animator.animation_player if player.animator else null
	return animation_player != null and animation_player.has_animation(turbo_animation)


func _set_speed_scale(value: float) -> void:
	var animation_player: AnimationPlayer = player.animator.animation_player if player.animator else null
	if animation_player:
		animation_player.speed_scale = value
