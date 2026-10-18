extends State
## Muerte: el jugador pierde el control y ya no recibe daño.
## Animación por defecto: "dead". Conecta la señal `died` del Player para
## reiniciar el nivel, mostrar "Game Over", etc.


func enter(msg: Dictionary = {}) -> void:
	player.hurtbox.active = false
	var knockback: Vector2 = msg.get("knockback", Vector2.ZERO)
	player.velocity = knockback


func physics_update(delta: float) -> void:
	player.apply_gravity(delta)
	if player.is_on_floor():
		player.move_ground(0.0, delta)
	else:
		player.move_air(0.0, delta)
	player.move_and_slide()
