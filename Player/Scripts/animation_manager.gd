class_name AnimationManager
extends Node
## Reproduce automáticamente la animación de cada estado.
##
## Funciona con AnimatedSprite2D, con AnimationPlayer, o con ambos.
## Cada estado indica su animación en el campo "Animation" de su nodo
## (si lo dejas vacío se usa el nombre del nodo en minúsculas: "Dash" -> "dash").

@export var state_machine: StateMachine

@export_group("Reproductores (usa uno o ambos)")
@export var sprite: Sprite2D
@export var animation_player: AnimationPlayer

@export_group("Orientación")
## Nodo que se voltea al cambiar de dirección. Si está vacío usa `sprite` o, en su defecto,
## un nodo hermano llamado "Sprite2D".
@export var flip_node: Node2D

@export_group("Depuración")
@export var warn_on_missing_animation: bool = true

var current_animation: StringName = &""
var _warned: Dictionary = {}


func _ready() -> void:
	# Autodetección: si no asignas nada en el Inspector, busca nodos hermanos con nombre estándar.
	if state_machine == null:
		state_machine = get_node_or_null("../StateMachine") as StateMachine
	if sprite == null:
		sprite = get_node_or_null("../Sprite2D") as Sprite2D
	if animation_player == null:
		animation_player = get_node_or_null("../AnimationPlayer") as AnimationPlayer
	if flip_node == null:
		if sprite:
			flip_node = sprite
		else:
			flip_node = get_node_or_null("../Sprite2D") as Node2D

	if state_machine == null:
		push_error("AnimationManager: no se encontró el StateMachine.")
		return

	# Nos conectamos aquí (antes de que el StateMachine entre a su estado inicial).
	state_machine.state_changed.connect(_on_state_changed)


func _on_state_changed(_old_state: State, new_state: State) -> void:
	play(new_state.get_animation_name())


## Reproduce una animación por nombre. También puedes llamarla desde cualquier estado:
##   player.animator.play(&"attack_2")
func play(anim: StringName, restart: bool = false) -> void:
	if anim == &"":
		return

	if animation_player and animation_player.has_animation(anim):
		if restart or animation_player.current_animation != anim:
			animation_player.play(anim)
		current_animation = anim
	#elif sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
		#if restart or sprite.animation != anim or not sprite.is_playing():
			#sprite.play(anim)
		#current_animation = anim
	else:
		_warn_missing(anim)


## Voltea el personaje según la dirección (>0 derecha, <0 izquierda).
func set_facing(direction: float) -> void:
	if is_zero_approx(direction) or flip_node == null:
		return

	var face_left := direction < 0.0
	if flip_node is AnimatedSprite2D:
		(flip_node as AnimatedSprite2D).flip_h = face_left
	elif flip_node is Sprite2D:
		(flip_node as Sprite2D).flip_h = face_left
	else:
		# Cualquier otro Node2D (p. ej. un nodo "Visuals" con varios sprites): se voltea con la escala.
		flip_node.scale.x = absf(flip_node.scale.x) * (-1.0 if face_left else 1.0)


func _warn_missing(anim: StringName) -> void:
	if warn_on_missing_animation and not _warned.has(anim):
		_warned[anim] = true
		push_warning("AnimationManager: no existe la animación '%s'." % anim)
