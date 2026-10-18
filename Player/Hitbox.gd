class_name Hitbox
extends Area2D
## Zona que HACE daño (enemigos, trampas, proyectiles...).
## Agrégale un CollisionShape2D hijo. Quien RECIBE el daño usa un Hurtbox.

## Se emite cuando este hitbox golpea a un Hurtbox (útil para destruir proyectiles al impactar).
signal hit_landed(hurtbox: Hurtbox)

@export var damage: int = 1
## Retroceso aplicado a quien reciba el golpe.
## x: se aplica alejándolo del hitbox. y: vertical (negativo = hacia arriba).
@export var knockback: Vector2 = Vector2(220.0, -180.0)
## Activa/desactiva el daño (p. ej. solo durante los frames de ataque de una animación).
@export var active: bool = true


func _ready() -> void:
	# Un Hitbox solo necesita ser detectado; no detecta nada por sí mismo.
	monitoring = false
