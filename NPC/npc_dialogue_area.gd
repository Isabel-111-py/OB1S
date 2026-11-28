class_name NPCDialogueArea
extends Area2D

## NPCDialogueArea:
## Dispara diálogos configurables (1 a 3 frases) cuando el jugador entra al área.
## Los diálogos pueden alternarse secuencialmente, al azar o en ping-pong.
## Muestra un bocadillo / globo de texto flotante sobre el NPC objetivo.

signal dialogue_started(phrase: String, phrase_index: int)
signal dialogue_finished(phrase: String, phrase_index: int)

enum ModoAlternancia {
	SECUENCIAL,   ## 1 -> 2 -> 3 -> 1 -> 2...
	ALEATORIO,    ## Elige al azar sin repetir la misma inmediatamente
	PING_PONG,    ## 1 -> 2 -> 3 -> 2 -> 1...
	UNA_SOLA_VEZ  ## Muestra solo la primera frase y se desactiva
}

# ==============================================================================
# CONFIGURACIÓN DE FRASES
# ==============================================================================
@export_group("Frases de Diálogo (1 a 3 frases)")
@export_multiline var frase_1: String = ""
@export_multiline var frase_2: String = ""
@export_multiline var frase_3: String = ""
## Si deseas más frases opcionales además de las 3 principales:
@export var frases_adicionales: Array[String] = []

# ==============================================================================
# MODO DE ALTERNANCIA Y ACTIVACIÓN
# ==============================================================================
@export_group("Alternancia y Comportamiento")
## Cómo alternan las frases cada vez que el jugador entra al área
@export var modo_alternancia: ModoAlternancia = ModoAlternancia.SECUENCIAL

## Tiempo mínimo de enfriamiento (cooldown) en segundos para evitar activaciones seguidas
@export var cooldown_activacion: float = 1.0

## Duración en segundos que permanece visible la frase en pantalla
@export var duracion_frase: float = 3.5

## Si es verdadero, el bocadillo se oculta tan pronto como el jugador abandona el área
@export var ocultar_al_salir_del_area: bool = false

## Si el NPC objetivo muere (is_dead), no se reproducirá el diálogo
@export var solo_si_npc_vivo: bool = true

# ==============================================================================
# OBJETIVO (NPC) Y POSICIONAMIENTO
# ==============================================================================
@export_group("Objetivo (NPC)")
## Nodo del NPC que pronuncia el diálogo. Si se deja vacío:
## 1. Intenta usar el nodo padre si es un NPC o CharacterBody2D.
## 2. Si no, muestra el globo sobre el centro de esta misma área.
@export var target_npc: Node2D = null

## Nombre opcional que aparecerá como título en el globo de texto
@export var nombre_npc: String = ""

## Desplazamiento del globo de texto respecto a la posición del NPC
@export var offset_globo: Vector2 = Vector2(0, -55)

## Si es verdadero, el globo sigue al NPC en tiempo real si este camina
@export var seguir_al_npc: bool = true

# ==============================================================================
# ESTILO VISUAL Y ANIMACIÓN
# ==============================================================================
@export_group("Visual y Efectos")
## Si es verdadero, el texto aparece letra por letra con efecto de máquina de escribir
@export var efecto_escritura: bool = true

## Velocidad de escritura en segundos por caracter
@export var velocidad_escritura: float = 0.025

## Ancho máximo del globo antes de saltar de línea
@export var ancho_maximo: float = 240.0

## Sonido opcional al empezar a hablar
@export var sonido_hablar: AudioStream = null


# ==============================================================================
# REFERENCIAS INTERNAS
# ==============================================================================
@onready var bubble_root: Node2D = $BubbleAnchor
@onready var bubble_panel: PanelContainer = $BubbleAnchor/BubbleControl/PanelContainer
@onready var name_label: Label = $BubbleAnchor/BubbleControl/PanelContainer/Margin/VBox/NameLabel
@onready var dialogue_label: Label = $BubbleAnchor/BubbleControl/PanelContainer/Margin/VBox/DialogueLabel
@onready var tail_polygon: Polygon2D = $BubbleAnchor/BubbleControl/Tail
@onready var audio_player: AudioStreamPlayer2D = get_node_or_null("AudioStreamPlayer2D")

var _indice_actual: int = 0
var _ultimo_indice: int = -1
var _direccion_ping_pong: int = 1
var _ya_usado_una_vez: bool = false
var _cooldown_activo: bool = false
var _player_dentro: bool = false
var _active_tween: Tween = null
var _hide_timer: SceneTreeTimer = null


func _ready() -> void:
	# Configurar capas de colisión: escucha al jugador (capas 1 y 2)
	collision_layer = 0
	collision_mask |= 1 | 2
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	_resolve_target_npc()
	
	# Ocultar globo al inicio y desacoplar escala/giro del padre
	if bubble_root:
		bubble_root.top_level = true
		bubble_root.visible = false
		bubble_root.modulate.a = 0.0
	
	if dialogue_label:
		dialogue_label.custom_minimum_size.x = min(ancho_maximo, 180.0)
		dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	# Escuchar respawn de SceneManager si existe
	var sm = get_node_or_null("/root/SceneManager")
	if sm and sm.has_signal("player_respawned"):
		sm.player_respawned.connect(_on_player_respawned)


func _process(_delta: float) -> void:
	# Seguir la posición del NPC en tiempo real si el globo está visible
	if seguir_al_npc and bubble_root and bubble_root.visible:
		var target_pos := _get_target_position()
		bubble_root.global_position = target_pos + offset_globo


# ==============================================================================
# RESOLUCIÓN DE OBJETIVO Y POSICIÓN
# ==============================================================================

func _resolve_target_npc() -> void:
	if target_npc != null and is_instance_valid(target_npc):
		return
	
	# Si no se asignó en el inspector, revisar si el padre es un NPC
	var parent_node := get_parent()
	if parent_node is CharacterBody2D or (parent_node and parent_node.is_in_group("npcs")):
		target_npc = parent_node as Node2D


func _get_target_position() -> Vector2:
	if target_npc and is_instance_valid(target_npc):
		return target_npc.global_position
	return global_position


func _is_npc_alive() -> bool:
	if not solo_si_npc_vivo:
		return true
	if target_npc and is_instance_valid(target_npc):
		if target_npc.get("is_dead") == true:
			return false
	return true


# ==============================================================================
# DETECCIÓN DEL JUGADOR
# ==============================================================================

func _is_player(body: Node2D) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	if body.is_in_group("player") or body.is_in_group("Player"):
		return true
	if body.name.to_lower().begins_with("player"):
		return true
	return false


func _on_body_entered(body: Node2D) -> void:
	if not _is_player(body):
		return
	
	_player_dentro = true
	
	if _cooldown_activo:
		return
	
	if not _is_npc_alive():
		return
	
	_mostrar_siguiente_dialogo()


func _on_body_exited(body: Node2D) -> void:
	if not _is_player(body):
		return
	
	_player_dentro = false
	
	if ocultar_al_salir_del_area:
		_ocultar_globo(0.2)


func _on_player_respawned() -> void:
	_cooldown_activo = false
	_player_dentro = false
	_indice_actual = 0
	_ultimo_indice = -1
	_direccion_ping_pong = 1
	_ya_usado_una_vez = false
	if bubble_root:
		bubble_root.visible = false
		bubble_root.modulate.a = 0.0


# ==============================================================================
# GESTIÓN Y ALTERNANCIA DE FRASES
# ==============================================================================

func _get_frases_validas() -> Array[String]:
	var lista: Array[String] = []
	if not frase_1.strip_edges().is_empty():
		lista.append(frase_1.strip_edges())
	if not frase_2.strip_edges().is_empty():
		lista.append(frase_2.strip_edges())
	if not frase_3.strip_edges().is_empty():
		lista.append(frase_3.strip_edges())
	for f in frases_adicionales:
		if not f.strip_edges().is_empty():
			lista.append(f.strip_edges())
	return lista


func _obtener_siguiente_frase() -> Dictionary:
	var frases := _get_frases_validas()
	if frases.is_empty():
		return {"text": "", "index": -1}
	
	if frases.size() == 1:
		if modo_alternancia == ModoAlternancia.UNA_SOLA_VEZ and _ya_usado_una_vez:
			return {"text": "", "index": -1}
		_ya_usado_una_vez = true
		return {"text": frases[0], "index": 0}
	
	var idx := 0
	match modo_alternancia:
		ModoAlternancia.SECUENCIAL:
			idx = _indice_actual % frases.size()
			_indice_actual = (_indice_actual + 1) % frases.size()
			
		ModoAlternancia.ALEATORIO:
			var candidatos: Array[int] = []
			for i in range(frases.size()):
				if i != _ultimo_indice or frases.size() == 1:
					candidatos.append(i)
			idx = candidatos.pick_random()
			_ultimo_indice = idx
			
		ModoAlternancia.PING_PONG:
			idx = _indice_actual
			_indice_actual += _direccion_ping_pong
			if _indice_actual >= frases.size():
				_indice_actual = max(0, frases.size() - 2)
				_direccion_ping_pong = -1
			elif _indice_actual < 0:
				_indice_actual = min(1, frases.size() - 1)
				_direccion_ping_pong = 1
				
		ModoAlternancia.UNA_SOLA_VEZ:
			if _ya_usado_una_vez:
				return {"text": "", "index": -1}
			_ya_usado_una_vez = true
			idx = 0
	
	return {"text": frases[idx], "index": idx}


# ==============================================================================
# PRESENTACIÓN DEL GLOBO DE DIÁLOGO
# ==============================================================================

func _mostrar_siguiente_dialogo() -> void:
	var resultado := _obtener_siguiente_frase()
	var texto: String = resultado.text
	var idx: int = resultado.index
	
	if texto.is_empty():
		return
	
	_iniciar_cooldown()
	_mostrar_globo(texto, idx)


func _mostrar_globo(texto: String, idx: int) -> void:
	_resolve_target_npc()
	
	# Cancelar tweens y timers previos
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()
	
	# Posicionar globo
	bubble_root.global_position = _get_target_position() + offset_globo
	bubble_root.visible = true
	
	# Configurar textos
	if name_label:
		if not nombre_npc.strip_edges().is_empty():
			name_label.text = nombre_npc.strip_edges()
			name_label.visible = true
		else:
			name_label.visible = false
	
	if dialogue_label:
		dialogue_label.text = texto
		if efecto_escritura:
			dialogue_label.visible_ratio = 0.0
		else:
			dialogue_label.visible_ratio = 1.0
	
	# Sonido si está configurado
	if sonido_hablar and audio_player:
		audio_player.stream = sonido_hablar
		audio_player.play()
	
	dialogue_started.emit(texto, idx)
	
	# Animación de aparición (Pop-in con escala y fade)
	bubble_root.scale = Vector2(0.6, 0.6)
	bubble_root.modulate.a = 0.0
	
	_active_tween = create_tween().set_parallel(true)
	_active_tween.tween_property(bubble_root, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(bubble_root, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# Efecto máquina de escribir
	var write_time: float = 0.0
	if efecto_escritura and dialogue_label:
		write_time = clampf(texto.length() * velocidad_escritura, 0.2, 1.8)
		var text_tween = create_tween()
		text_tween.tween_property(dialogue_label, "visible_ratio", 1.0, write_time).set_trans(Tween.TRANS_LINEAR)
	
	# Programar desaparición tras la duración
	var total_display_time := write_time + duracion_frase
	_programar_ocultamiento(total_display_time, texto, idx)


func _programar_ocultamiento(delay: float, texto: String, idx: int) -> void:
	var my_tree := get_tree()
	if my_tree == null:
		return
	
	_hide_timer = my_tree.create_timer(delay)
	await _hide_timer.timeout
	
	# Verificar si no fue interrumpido por otro diálogo más reciente
	if bubble_root and bubble_root.visible and dialogue_label and dialogue_label.text == texto:
		dialogue_finished.emit(texto, idx)
		_ocultar_globo(0.3)


func _ocultar_globo(tiempo: float = 0.25) -> void:
	if not bubble_root or not bubble_root.visible:
		return
	
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()
	
	_active_tween = create_tween().set_parallel(true)
	_active_tween.tween_property(bubble_root, "scale", Vector2(0.7, 0.7), tiempo).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_active_tween.tween_property(bubble_root, "modulate:a", 0.0, tiempo).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	await _active_tween.finished
	if bubble_root and bubble_root.modulate.a <= 0.05:
		bubble_root.visible = false


func _iniciar_cooldown() -> void:
	_cooldown_activo = true
	var tree := get_tree()
	if tree:
		await tree.create_timer(cooldown_activacion).timeout
		_cooldown_activo = false
