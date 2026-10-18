class_name Hurtbox
extends Area2D
## Zona que RECIBE daño. Detecta los Hitbox que la toquen, avisa con `hit_received`
## y activa un periodo de invulnerabilidad con parpadeo.
## Agrégale un CollisionShape2D hijo (un poco más pequeño que el cuerpo suele sentirse mejor).

## Se emite al recibir un golpe. Quien tenga la vida (el Player) se conecta a esta señal.
signal hit_received(hitbox: Hitbox)

## Segundos de invulnerabilidad después de recibir un golpe.
@export var invincibility_time: float = 1.0
## Nodo que parpadea mientras es invulnerable (el sprite o el nodo que lo contiene).
## Si lo dejas vacío busca un hermano llamado "AnimatedSprite2D" o "Sprite2D".
@export var visual: CanvasItem
## Duración de cada parpadeo (s).
@export var blink_interval: float = 0.08

var _invincible_timer: float = 0.0

## Desactívalo para que no reciba daño (al morir, en cinemáticas, etc.).
var active: bool = true:
	set(value):
		active = value
		if not active:
			_invincible_timer = 0.0
			_set_visual_alpha(1.0)


func _ready() -> void:
	# Un Hurtbox solo detecta Hitbox; nadie necesita detectarlo a él.
	monitorable = false
	if visual == null:
		visual = get_node_or_null("../AnimatedSprite2D") as CanvasItem
	if visual == null:
		visual = get_node_or_null("../Sprite2D") as CanvasItem


func is_invincible() -> bool:
	return _invincible_timer > 0.0


func _physics_process(delta: float) -> void:
	if _invincible_timer > 0.0:
		_invincible_timer -= delta
		_update_blink()
		return

	if not active:
		return

	# Se revisa cada frame de física (y no solo con area_entered) para que, si el jugador sigue
	# tocando unos pinchos cuando termina la invulnerabilidad, reciba daño de nuevo.
	for area in get_overlapping_areas():
		var hitbox := area as Hitbox
		if hitbox and hitbox.active:
			_receive_hit(hitbox)
			break


func _receive_hit(hitbox: Hitbox) -> void:
	_invincible_timer = invincibility_time
	hitbox.hit_landed.emit(self)
	hit_received.emit(hitbox)


func _update_blink() -> void:
	if _invincible_timer <= 0.0:
		_set_visual_alpha(1.0)
		return
	# Alterna entre semitransparente y opaco.
	var phase := int(_invincible_timer / blink_interval) % 2
	_set_visual_alpha(0.3 if phase == 0 else 1.0)


func _set_visual_alpha(alpha: float) -> void:
	if visual:
		visual.modulate.a = alpha
