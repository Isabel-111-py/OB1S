extends State
## Retroceso al recibir daño: el jugador pierde el control unos instantes.
## Animación por defecto: "hurt" (o la que escribas en el campo Animation).

## Segundos sin control tras recibir el golpe.
@export var stun_time: float = 0.3

var _timer: float = 0.0


func enter(msg: Dictionary = {}) -> void:
	_timer = stun_time
	var knockback: Vector2 = msg.get("knockback", Vector2.ZERO)
	player.velocity = knockback
	print("hurt")


func physics_update(delta: float) -> void:
	_timer -= delta

	player.apply_gravity(delta)
	if player.is_on_floor():
		player.move_ground(0.0, delta)
	else:
		player.move_air(0.0, delta)
	player.move_and_slide()

	if _timer <= 0.0:
		if player.is_on_floor():
			state_machine.transition_to("Idle")
		else:
			state_machine.transition_to("Fall")
