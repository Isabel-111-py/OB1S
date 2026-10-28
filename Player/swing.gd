extends State
## Balanceo con la cuerda del Grapple. Animación por defecto: "swing".
##  - Izquierda / derecha: impulsan el balanceo.
##  - rope_retract / rope_extend: retraen o sueltan cuerda.
##  - Saltar: te sueltas y saltas con el impulso del balanceo. Una tecla que esté asignada
##    a saltar Y también a retraer/soltar cuerda (p. ej. W) solo maneja la cuerda aquí;
##    para saltar desde la cuerda usa una tecla de salto que no sea compartida (p. ej. Espacio).
##  - Soltar el clic izquierdo (o clic de nuevo en modo toggle): te sueltas.

## Aceleración horizontal (px/s²) al presionar una dirección mientras estás en el aire.
@export var swing_acceleration: float = 800.0
## Fricción del aire (0 = ninguna). Evita que el balanceo sea eterno.
@export var air_drag: float = 0.15
## Límite de velocidad durante el balanceo, para evitar que la física se desborde.
@export var max_swing_speed: float = 1000.0


func enter(_msg: Dictionary = {}) -> void:
	if player.grapple == null:
		push_error("Swing: el Player no tiene un nodo 'Grapple'.")
		state_machine.transition_to("Fall")


func exit() -> void:
	# Si algo interrumpe el balanceo (un golpe, la muerte...), la cuerda se suelta.
	if player.grapple:
		player.grapple.detach()


func physics_update(delta: float) -> void:
	var grapple := player.grapple
	if grapple == null or not grapple.is_attached:
		_leave()
		return

	# La cuerda se dobla o se estira según las esquinas que haya en el escenario.
	grapple.update_rope()
	if not grapple.is_attached:
		_leave() # la cuerda no pudo resolverse sin atravesar el escenario
		return

	var direction := player.get_input_direction()

	# Retraer (+1) o soltar (-1) cuerda.
	var reel_input := Input.get_axis(grapple.extend_action, grapple.retract_action)
	if not is_zero_approx(reel_input):
		grapple.reel(-reel_input * grapple.reel_speed * delta)

	player.apply_gravity(delta)
	if player.is_on_floor():
		# Con los pies en el suelo se mueve como siempre (aceleración, rueda libre...).
		player.move_ground(direction, delta)
	else:
		player.velocity.x += direction * swing_acceleration * delta
		player.velocity *= maxf(1.0 - air_drag * delta, 0.0)

	_apply_rope_constraint(grapple, delta)

	if absf(player.velocity.x) > 20.0:
		player.face(player.velocity.x)
	player.move_and_slide()


## La cuerda limita la distancia entre el punto de apoyo y la mano a su largo libre.
## Si el siguiente paso la sacaría del círculo, se corrige la velocidad para que quede sobre él:
## se elimina el movimiento hacia afuera y se conserva el tangencial, que es el balanceo.
func _apply_rope_constraint(grapple: Grapple, delta: float) -> void:
	var pivot := grapple.get_pivot()
	var radius := grapple.get_free_length()
	var hand := grapple.global_position

	var next_hand := hand + player.velocity * delta
	var offset := next_hand - pivot
	if offset.length() > radius:
		var constrained := pivot + offset.normalized() * radius
		player.velocity = (constrained - hand) / delta

	player.velocity = player.velocity.limit_length(max_swing_speed)


## Se evalúa por evento para saber QUÉ tecla se presionó. Si esa misma tecla también está
## asignada a retraer o soltar cuerda, se ignora aquí y solo maneja la cuerda.
func handle_input(event: InputEvent) -> void:
	var grapple := player.grapple
	if grapple == null or not grapple.is_attached:
		return
	if not event.is_action_pressed("jump"):
		return
	if event.is_action(grapple.retract_action) or event.is_action(grapple.extend_action):
		return
	_jump_off()


## Te sueltas de la cuerda y saltas: entras al estado Jump (salto completo, con altura variable
## según cuánto mantengas el botón), conservando la velocidad horizontal del balanceo.
## En el aire solo se puede saltar mientras queden saltos (max_rope_jumps del Grapple, se recargan
## al tocar el suelo); sin saltos disponibles solo te sueltas y conservas la velocidad.
func _jump_off() -> void:
	var grapple := player.grapple
	var swing_vertical_speed := player.velocity.y
	var can_jump := grapple.consume_rope_jump()
	grapple.detach()

	if not can_jump:
		state_machine.transition_to("Fall")
		return

	state_machine.transition_to("Jump")
	# Si el balanceo ya subía más rápido que un salto normal, no pierdes ese impulso.
	player.velocity.y = minf(player.velocity.y, swing_vertical_speed)


func _leave() -> void:
	if player.grapple:
		player.grapple.detach()
	if player.is_on_floor():
		if is_zero_approx(player.get_input_direction()):
			state_machine.transition_to("Idle")
		else:
			state_machine.transition_to("Run")
	else:
		state_machine.transition_to("Fall")
