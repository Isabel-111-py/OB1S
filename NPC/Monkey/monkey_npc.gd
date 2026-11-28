class_name MonkeyNPC
extends Area2D
## El mono, antes de unirse al robot. Es un NPC suelto en el mapa:
##   1. Si te acercas, te llama la atención (brazo en alto) y aparece "E: Hablar".
##   2. Sin ninguna flecha (la "fruta"): dice que tiene hambre.
##   3. Con una flecha: la recibe (se te descuenta 1), da las gracias, decide ayudarte, salta sobre
##      el robot y desaparece del mapa.
## Al subirse activa la bandera `joined_flag` (QuestManager): desde entonces el mono aparece sobre
## el robot (nodo "Mono" del Player) y la bandera se guarda con la partida.
##
## Uso: pon `monkey_npc.tscn` en el primer nivel, con el origen (el punto del nodo) en el suelo.

## Se emite cuando el mono ya está sobre el robot.
signal joined
@export var bubble_width: float = 100.0
@export var npc_name: String = "Mono"
## Bandera de eventos (QuestManager) que se activa al unirse. Debe ser la misma que `required_flag`
## del script del Mono en el Player. Úsala también para arrancar el tutorial.
@export var joined_flag: String = "monkey_joined"
## Cuántas flechas pide como fruta.
@export var fruit_amount: int = 1
## Acción del Input Map para interactuar. Si no existe, se usa `interact_key`.
@export var interact_action: StringName = &"interact"
@export var interact_key: Key = KEY_E

@export_group("Textos")
@export var prompt_talk: String = "E: Hablar"
@export var prompt_give: String = "E: Darle una fruta"
@export_multiline var hungry_text: String = "Uuuh... ¡tengo hambre! ¿No tendrás alguna fruta?"
## Segundos que se muestra cada mensaje.
@export var hungry_time: float = 3.0
@export var thanks_time: float = 2.6

@export_group("Animación (frames del spritesheet)")
## Quieto, sin nadie cerca.
@export var idle_frames: PackedInt32Array = PackedInt32Array([11])
## Cuando te acercas: llama tu atención con el brazo en alto.
@export var attention_frames: PackedInt32Array = PackedInt32Array([13, 11])
@export var attention_fps: float = 2.5
## Al recibir la fruta: celebra.
@export var happy_frames: PackedInt32Array = PackedInt32Array([12, 13])
@export var happy_fps: float = 6.0
## Mientras salta hacia el robot.
@export var jump_frames: PackedInt32Array = PackedInt32Array([12])

@export_group("Salto al robot")
## Segundos que dura el salto.
@export var jump_time: float = 0.7
## Altura (px) del arco del salto.
@export var jump_height: float = 40.0
## Segundos que tarda la flecha en volar del robot al mono.
@export var fruit_fly_time: float = 0.35

enum Phase { IDLE, BUSY }

var _phase: Phase = Phase.IDLE
var _player: Player
var _sprite: Sprite2D
var _prompt: Label
var _bubble: PanelContainer
var _bubble_label: Label
var _bubble_timer: float = 0.0
var _frames: PackedInt32Array = PackedInt32Array([11])
var _fps: float = 6.0
var _anim_time: float = 0.0


func _ready() -> void:
	_sprite = get_node_or_null("Sprite2D") as Sprite2D
	_frames = idle_frames

	# Si el mono ya se unió (partida cargada o ya hecho antes), este NPC no debe existir.
	if joined_flag != "" and QuestManager.has_event_flag(joined_flag):
		queue_free()
		return

	_build_ui()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	_anim_time += delta
	if _sprite and not _frames.is_empty():
		_sprite.frame = _frames[int(_anim_time * _fps) % _frames.size()]

	# Mira hacia el robot cuando está cerca.
	if _sprite and is_instance_valid(_player) and _phase == Phase.IDLE:
		_sprite.flip_h = _player.global_position.x < global_position.x

	if _bubble_timer > 0.0:
		_bubble_timer -= delta
		if _bubble_timer <= 0.0:
			_bubble.visible = false
			_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if _phase != Phase.IDLE or not is_instance_valid(_player) or _player.is_dead:
		return
	if get_tree().paused or not _is_interact(event):
		return
	get_viewport().set_input_as_handled()
	_interact()


# ---------------------------------------------------------------------------
# Interacción
# ---------------------------------------------------------------------------

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_player = body
		if _phase == Phase.IDLE:
			_set_animation(attention_frames, attention_fps)
		_update_prompt()


func _on_body_exited(body: Node2D) -> void:
	if body == _player:
		_player = null
		if _phase == Phase.IDLE:
			_set_animation(idle_frames, 6.0)
		_update_prompt()


func _interact() -> void:
	var slot := _find_fruit_slot()
	if slot < 0:
		_say(hungry_text, hungry_time)
		return
	_receive_fruit(slot)


## Espacio de munición del que se puede sacar la fruta: el seleccionado y, si no, el primero con flechas.
func _find_fruit_slot() -> int:
	if Inventory.get_ammo(Inventory.selected_slot) >= fruit_amount:
		return Inventory.selected_slot
	for slot in Inventory.SLOT_COUNT:
		if Inventory.get_ammo(slot) >= fruit_amount:
			return slot
	return -1


func _receive_fruit(slot: int) -> void:
	_phase = Phase.BUSY
	var giver := _player
	_update_prompt()

	# 1. La flecha (la fruta) vuela del robot al mono y se descuenta del inventario.
	_consume_fruit(slot)
	await _fly_fruit(slot, giver)
	if not is_inside_tree():
		return

	# 2. Da las gracias y celebra.
	_set_animation(happy_frames, happy_fps)
	
	await get_tree().create_timer(thanks_time).timeout
	if not is_inside_tree():
		return


	# 3. Salta sobre el robot y se queda ahí (el Mono del Player pasa a verse).
	_bubble.visible = false
	await _jump_to_robot(giver)
	if not is_inside_tree():
		return
	if joined_flag != "":
		QuestManager.set_event_flag(joined_flag, true)
	joined.emit()
	queue_free()


## Gasta la fruta sin cambiar la munición que el jugador tiene seleccionada.
func _consume_fruit(slot: int) -> void:
	var previous: int = Inventory.selected_slot
	Inventory.select_ammo(slot)
	for i in fruit_amount:
		Inventory.use_arrow()
	Inventory.select_ammo(previous)


func _fly_fruit(slot: int, giver: Player) -> void:
	if not is_instance_valid(giver):
		return
	var fruit := Sprite2D.new()
	fruit.texture = Inventory.get_slot_icon(slot)
	fruit.modulate = Inventory.get_slot_tint(slot)
	fruit.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fruit.top_level = true
	fruit.z_index = 20
	add_child(fruit)
	fruit.global_position = giver.global_position + Vector2(0, -20)

	var tween := create_tween()
	tween.tween_property(fruit, "global_position", global_position + Vector2(0, -16), fruit_fly_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tween.finished
	fruit.queue_free()


## Arco hasta donde va el mono sobre el robot (se actualiza cada frame por si el robot se mueve).
func _jump_to_robot(giver: Player) -> void:
	if not is_instance_valid(giver):
		return
	_set_animation(jump_frames, 6.0)
	var tween := create_tween()
	tween.tween_method(_jump_step.bind(global_position, giver), 0.0, 1.0, jump_time)
	await tween.finished


func _jump_step(t: float, start: Vector2, giver: Player) -> void:
	if not is_instance_valid(giver):
		return
	var target := _robot_mono_position(giver)
	global_position = start.lerp(target, t) + Vector2(0.0, -sin(t * PI) * jump_height)
	if _sprite:
		_sprite.flip_h = target.x < start.x


## Dónde queda el mono sobre el robot: la posición del nodo "Mono" del Player (aunque esté oculto).
func _robot_mono_position(giver: Player) -> Vector2:
	var mono := giver.get_node_or_null("Mono") as Node2D
	if mono:
		return mono.global_position
	return giver.global_position + Vector2(0, -36)


func _is_interact(event: InputEvent) -> bool:
	if InputMap.has_action(interact_action):
		return event.is_action_pressed(interact_action)
	var key_event := event as InputEventKey
	return key_event != null and key_event.pressed and not key_event.echo \
		and key_event.physical_keycode == interact_key


func _set_animation(frames: PackedInt32Array, fps: float) -> void:
	_frames = frames
	_fps = fps
	_anim_time = 0.0


# ---------------------------------------------------------------------------
# Texto flotante
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_prompt = Label.new()
	_prompt.size = Vector2(160, 14)
	_prompt.position = Vector2(-80, -52)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 10)
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 3)
	_prompt.z_index = 20
	_prompt.visible = false
	add_child(_prompt)

	_bubble = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.97, 0.94, 0.83)
	style.border_color = Color(0.35, 0.22, 0.12)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(5)
	_bubble.add_theme_stylebox_override("panel", style)
	
	_bubble.custom_minimum_size = Vector2(bubble_width, 0)
	_bubble.z_index = 21
	_bubble.visible = false
	add_child(_bubble)

	_bubble_label = Label.new()
	_bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_label.add_theme_font_size_override("font_size", 9)
	_bubble_label.add_theme_color_override("font_color", Color(0.2, 0.12, 0.07))
	_bubble.add_child(_bubble_label)


func _say(text: String, seconds: float) -> void:
	_bubble_label.text = "%s: %s" % [npc_name, text] if npc_name != "" else text
	_bubble.visible = true
	_bubble_timer = seconds
	_bubble.reset_size()
	_update_prompt()
	# El tamaño real del globo se conoce un frame después: se coloca sobre la cabeza del mono.
	await get_tree().process_frame
	if is_inside_tree():
		_bubble.position = Vector2(-_bubble.size.x / 2.0, -42.0 - _bubble.size.y)


func _update_prompt() -> void:
	if _prompt == null:
		return
	var near := is_instance_valid(_player) and _phase == Phase.IDLE
	_prompt.visible = near and not _bubble.visible
	if near:
		_prompt.text = prompt_give if _find_fruit_slot() >= 0 else prompt_talk
