class_name Arrow
extends Hitbox
## Flecha: vuela en parábola, daña a los Hurtbox que toque y se clava en las paredes.
## Como extiende Hitbox, hereda `damage`, `knockback` y `active`.
##
## Escena: Area2D (con este script) + CollisionShape2D pequeña en la PUNTA + Sprite2D.
## La flecha debe estar dibujada apuntando hacia +X (derecha).

## Gravedad de la flecha (px/s²). Menor que la del jugador = trayectoria más recta.
@export var arrow_gravity: float = 400.0
@export var max_fall_speed: float = 700.0
## Segundos máximos de vuelo antes de desaparecer.
@export var lifetime: float = 4.0
## Segundos que permanece clavada en una pared antes de desvanecerse.
@export var stuck_time: float = 2.0

var velocity: Vector2 = Vector2.ZERO
## Quien disparó la flecha; se ignora para que no se clave en él.
var shooter: Node

var _stuck: bool = false
var _launched: bool = false


func _ready() -> void:
	# No llamamos a super(): un Hitbox normal desactiva `monitoring`, pero la flecha
	# SÍ debe detectar cuerpos (paredes) para poder clavarse.
	body_entered.connect(_on_body_entered)
	hit_landed.connect(_on_hit_landed)
	# Hasta que no se llame a launch(), la flecha se queda quieta e inofensiva
	# (por ejemplo, si hay una colocada a mano en una escena).
	active = false


func launch(initial_velocity: Vector2, from: Node) -> void:
	velocity = initial_velocity
	shooter = from
	rotation = velocity.angle()
	_launched = true
	active = true
	get_tree().create_timer(lifetime).timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	if not _launched or _stuck:
		return
	velocity.y = minf(velocity.y + arrow_gravity * delta, max_fall_speed)
	global_position += velocity * delta
	rotation = velocity.angle()


func _on_body_entered(body: Node2D) -> void:
	if not _launched or _stuck or body == shooter:
		return

	_stuck = true
	active = false # ya no hace daño
	velocity = Vector2.ZERO

	var tween := create_tween()
	tween.tween_interval(stuck_time)
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(queue_free)


func _on_hit_landed(_hurtbox: Hurtbox) -> void:
	# Golpeó a un Hurtbox: la flecha desaparece.
	active = false
	queue_free()


## Dibujo de prueba: solo si la escena no tiene un Sprite2D / AnimatedSprite2D propio.
func _draw() -> void:
	for child in get_children():
		if child is Sprite2D or child is AnimatedSprite2D:
			return
	draw_line(Vector2(-14.0, 0.0), Vector2.ZERO, Color.WHITE, 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(0.0, -3.0), Vector2(6.0, 0.0), Vector2(0.0, 3.0)]), Color.WHITE)
