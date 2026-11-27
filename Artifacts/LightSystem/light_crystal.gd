@tool
class_name LightCrystal
extends CharacterBody2D

## Cristal reflector y canalizador de luz para puzzles en cavernas.
## Soporta cuatro modalidades configurables desde el Inspector:
##   1. Primer_Iluminado: Recibe la luz directa de las grietas, siempre activo inicialmente.
##      El jugador puede rotarlo [E] entre 3 posiciones para dirigir la luz inicial a otros cristales.
##   2. Rotable por Jugador [E]: Cristal secundario que el jugador rota [E] entre 3 posiciones.
##   3. Empujable (Pedestal): El jugador lo empuja físicamente hacia pedestales o por el suelo.
##   4. Fijo (Techo/Pared): Cristal fijo en techos/paredes como repetidor óptico.

signal energized_changed(is_energized: bool)
signal rotated(new_angle: float, angle_index: int)
signal docked_to_pedestal(pedestal: Node)
signal undocked_from_pedestal(pedestal: Node)

@export_group("Tipo e Identidad del Cristal")
@export_enum(
	"Primer_Iluminado (Entrada de Luz)",
	"Rotable por Jugador [E]",
	"Empujable (Pedestal)",
	"Fijo (Techo/Pared)"
) var crystal_type: String = "Primer_Iluminado (Entrada de Luz)":
	set(val):
		crystal_type = val
		_apply_crystal_type()
		queue_redraw()

@export_group("Rotaciones Permitidas (3 Posiciones)")
## Si está activo, el cristal solo alterna entre 3 ángulos predefinidos
@export var use_three_rotations: bool = true:
	set(val):
		use_three_rotations = val
		_sync_three_angles()
		queue_redraw()

## Ángulo 1 en grados (o calculado automáticamente si asignas target_1)
@export_range(0.0, 360.0, 1.0) var angle_1: float = 0.0:
	set(val):
		angle_1 = val
		_sync_three_angles()
		queue_redraw()

## Ángulo 2 en grados (o calculado automáticamente si asignas target_2)
@export_range(0.0, 360.0, 1.0) var angle_2: float = 330.0:
	set(val):
		angle_2 = val
		_sync_three_angles()
		queue_redraw()

## Ángulo 3 en grados (o calculado automáticamente si asignas target_3)
@export_range(0.0, 360.0, 1.0) var angle_3: float = 30.0:
	set(val):
		angle_3 = val
		_sync_three_angles()
		queue_redraw()

## Posición actual seleccionada entre las 3 rotaciones (0 = Posición 1, 1 = Posición 2, 2 = Posición 3)
@export_range(0, 2) var current_angle_index: int = 0:
	set(val):
		current_angle_index = clampi(val, 0, 2)
		_sync_three_angles()
		queue_redraw()

@export_group("Objetivos Directos (Apuntado Automático)")
## Si asignas nodos objetivo (otros cristales o receptores), el cristal apunta
## automáticamente con precisión matemática hacia ellos para que la conexión nunca falle:
@export var target_1: Node2D:
	set(val):
		target_1 = val
		_sync_three_angles()
		queue_redraw()

@export var target_2: Node2D:
	set(val):
		target_2 = val
		_sync_three_angles()
		queue_redraw()

@export var target_3: Node2D:
	set(val):
		target_3 = val
		_sync_three_angles()
		queue_redraw()

@export_group("Orientación Continua (Solo si use_three_rotations es falso)")
@export_range(0.0, 360.0, 5.0) var custom_rotation_angle: float = 0.0:
	set(val):
		custom_rotation_angle = wrapf(val, 0.0, 360.0)
		if not use_three_rotations:
			rotation_angle = custom_rotation_angle
		queue_redraw()

@export var rotation_step: float = 45.0

## Modo de redirección del haz de luz:
## - Prisma: Canaliza la luz hacia donde apunta el cristal (rotation_angle).
## - Espejo: Refleja la luz por rebote óptico según el ángulo de entrada.
@export_enum("Dirección del Cristal (Prisma)", "Reflejo Óptico (Espejo)") var reflection_mode: String = "Dirección del Cristal (Prisma)"

@export_group("Propiedades de Luz")
## Color del cristal y del haz reflejado
@export var crystal_color: Color = Color(0.25, 0.9, 1.0, 0.95):
	set(val):
		crystal_color = val
		_apply_beam_visuals()
		queue_redraw()

## Distancia máxima del haz reflejado
@export var max_beam_distance: float = 1200.0

@export_group("Física de Empuje (Solo tipo Empujable)")
## Velocidad horizontal al ser empujado por el jugador (px/s)
@export var push_speed: float = 70.0
## Gravedad aplicada al cristal empujable
@export var gravity: float = 980.0

# --- Estado Interno ---
var rotation_angle: float = 0.0
var is_energized: bool = false
var player_in_interaction_range: bool = false
var is_docked: bool = false
var current_pedestal: Node = null

var _active_sources: Dictionary = {} # source_ref -> { "dir": Vector2, "color": Color, "chain": Array }
var _downstream_target: Object = null
var _last_hit_pos: Vector2 = Vector2.ZERO

var _visual_rotation: float = 0.0
var _anim_pulse: float = 0.0
var _prompt_anim: float = 0.0

# --- Nodos Hijos ---
@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D")
var _interaction_area: Area2D
var _push_detect_area: Area2D
var _hitbox_area: Area2D
var _prompt_container: Node2D
var _prompt_label: Label
var _glow_line: Line2D
var _core_line: Line2D
var _ambient_light: PointLight2D
var _impact_light: PointLight2D
var _path_lights: Array[PointLight2D] = []


func _ready() -> void:
	_setup_internal_components()
	_apply_crystal_type()
	_sync_three_angles()
	_apply_beam_visuals()


func _sync_three_angles() -> void:
	if use_three_rotations:
		rotation_angle = _get_effective_angle(current_angle_index)
	else:
		rotation_angle = custom_rotation_angle
	_visual_rotation = deg_to_rad(rotation_angle)
	_update_prompt_text()


## Devuelve el ángulo efectivo para el índice (calculado desde target_node si existe, o ángulo manual)
func _get_effective_angle(index: int) -> float:
	var target_node: Node2D = null
	match index:
		0: target_node = target_1
		1: target_node = target_2
		2: target_node = target_3
	
	if target_node != null and is_instance_valid(target_node):
		var from_pos := global_position + Vector2(0, -10)
		var to_pos := target_node.global_position + Vector2(0, -10)
		return wrapf(rad_to_deg((to_pos - from_pos).angle()), 0.0, 360.0)
	
	match index:
		0: return angle_1
		1: return angle_2
		2: return angle_3
	return 0.0


func _setup_internal_components() -> void:
	# Área receptora de luz (Hitbox para que los rayos la detecten de forma fiable)
	_hitbox_area = get_node_or_null("LightHitbox") as Area2D
	if not _hitbox_area:
		_hitbox_area = Area2D.new()
		_hitbox_area.name = "LightHitbox"
		_hitbox_area.collision_layer = 2 | 4
		_hitbox_area.collision_mask = 0
		var h_shape := CollisionShape2D.new()
		var c_circle := CircleShape2D.new()
		c_circle.radius = 18.0
		h_shape.shape = c_circle
		h_shape.position = Vector2(0, -10)
		_hitbox_area.add_child(h_shape)
		add_child(_hitbox_area)
	
	# Área de interacción para rotar con [E]
	_interaction_area = get_node_or_null("InteractionArea") as Area2D
	if not _interaction_area:
		_interaction_area = Area2D.new()
		_interaction_area.name = "InteractionArea"
		_interaction_area.collision_layer = 0
		_interaction_area.collision_mask = 1 # Jugador
		var col := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 36.0
		col.shape = shape
		_interaction_area.add_child(col)
		add_child(_interaction_area)
	
	if not Engine.is_editor_hint():
		if not _interaction_area.body_entered.is_connected(_on_interaction_entered):
			_interaction_area.body_entered.connect(_on_interaction_entered)
		if not _interaction_area.body_exited.is_connected(_on_interaction_exited):
			_interaction_area.body_exited.connect(_on_interaction_exited)
	
	# Área de detección de empuje
	_push_detect_area = get_node_or_null("PushDetectArea") as Area2D
	if not _push_detect_area:
		_push_detect_area = Area2D.new()
		_push_detect_area.name = "PushDetectArea"
		_push_detect_area.collision_layer = 0
		_push_detect_area.collision_mask = 1
		var col_push := CollisionShape2D.new()
		var p_shape := RectangleShape2D.new()
		p_shape.size = Vector2(30.0, 24.0)
		col_push.shape = p_shape
		col_push.position = Vector2(0, 4)
		_push_detect_area.add_child(col_push)
		add_child(_push_detect_area)
	
	# Cartel de interacción [E]
	_prompt_container = get_node_or_null("PromptContainer") as Node2D
	if not _prompt_container:
		_prompt_container = Node2D.new()
		_prompt_container.name = "PromptContainer"
		_prompt_container.position = Vector2(0, -42)
		_prompt_container.visible = false
		
		var panel := PanelContainer.new()
		panel.name = "Panel"
		panel.position = Vector2(-44, -12)
		panel.custom_minimum_size = Vector2(88, 24)
		
		var s_style := StyleBoxFlat.new()
		s_style.bg_color = Color(0.12, 0.14, 0.22, 0.94)
		s_style.set_corner_radius_all(6)
		s_style.border_width_left = 1
		s_style.border_width_top = 1
		s_style.border_width_right = 1
		s_style.border_width_bottom = 1
		s_style.border_color = Color(0.2, 0.85, 1.0, 0.7)
		panel.add_theme_stylebox_override("panel", s_style)
		
		_prompt_label = Label.new()
		_prompt_label.name = "Label"
		_prompt_label.text = "[E] Girar (1/3)"
		_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_prompt_label.add_theme_font_size_override("font_size", 10)
		_prompt_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
		panel.add_child(_prompt_label)
		
		_prompt_container.add_child(panel)
		add_child(_prompt_container)
	else:
		_prompt_label = _prompt_container.get_node_or_null("Panel/Label") as Label
	
	# Líneas del haz de luz saliente
	_glow_line = get_node_or_null("GlowLine") as Line2D
	if not _glow_line:
		_glow_line = Line2D.new()
		_glow_line.name = "GlowLine"
		_glow_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		_glow_line.end_cap_mode = Line2D.LINE_CAP_ROUND
		add_child(_glow_line)
	
	_core_line = get_node_or_null("CoreLine") as Line2D
	if not _core_line:
		_core_line = Line2D.new()
		_core_line.name = "CoreLine"
		_core_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		_core_line.end_cap_mode = Line2D.LINE_CAP_ROUND
		add_child(_core_line)
	
	# Luz ambiental propia del cristal cuando está encendido
	_ambient_light = get_node_or_null("AmbientLight") as PointLight2D
	if not _ambient_light:
		_ambient_light = PointLight2D.new()
		_ambient_light.name = "AmbientLight"
		_ambient_light.texture = _get_or_create_light_texture()
		_ambient_light.texture_scale = 1.8
		_ambient_light.energy = 1.6
		_ambient_light.position = Vector2(0, -10)
		add_child(_ambient_light)
	
	# Luz en el punto de impacto del haz saliente
	_impact_light = get_node_or_null("ImpactLight") as PointLight2D
	if not _impact_light:
		_impact_light = PointLight2D.new()
		_impact_light.name = "ImpactLight"
		_impact_light.texture = _get_or_create_light_texture()
		_impact_light.texture_scale = 1.4
		_impact_light.energy = 1.5
		add_child(_impact_light)
	
	_ensure_path_lights()


func _ensure_path_lights() -> void:
	var tex := _get_or_create_light_texture()
	while _path_lights.size() < 12:
		var l := PointLight2D.new()
		l.name = "PathLight_%d" % _path_lights.size()
		l.texture = tex
		l.texture_scale = 1.3
		l.energy = 1.1
		l.visible = false
		add_child(l)
		_path_lights.append(l)


func _get_or_create_light_texture() -> Texture2D:
	var path := "res://Artifacts/LightSystem/radial_light_gradient.tres"
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			return res
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 128
	tex.height = 128
	return tex


func _apply_crystal_type() -> void:
	match crystal_type:
		"Primer_Iluminado (Entrada de Luz)":
			# Cristal emisor primario: recibe luz solar directa de forma permanente
			motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
			collision_layer = 2
			collision_mask = 0
			velocity = Vector2.ZERO
			is_energized = true
			if _interaction_area: _interaction_area.monitoring = true
			if _push_detect_area: _push_detect_area.monitoring = false
			_active_sources[self] = {"dir": Vector2.DOWN, "color": crystal_color, "chain": [self]}
		"Empujable (Pedestal)":
			motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
			collision_layer = 1 | 2
			collision_mask = 1
			if _interaction_area: _interaction_area.monitoring = false
			if _push_detect_area: _push_detect_area.monitoring = true
			if _prompt_container: _prompt_container.visible = false
			_active_sources.erase(self)
		"Rotable por Jugador [E]":
			motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
			collision_layer = 2
			collision_mask = 0
			velocity = Vector2.ZERO
			if _interaction_area: _interaction_area.monitoring = true
			if _push_detect_area: _push_detect_area.monitoring = false
			_active_sources.erase(self)
		"Fijo (Techo/Pared)":
			motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
			collision_layer = 2
			collision_mask = 0
			velocity = Vector2.ZERO
			if _interaction_area: _interaction_area.monitoring = false
			if _push_detect_area: _push_detect_area.monitoring = false
			if _prompt_container: _prompt_container.visible = false
			_active_sources.erase(self)


func _update_prompt_text() -> void:
	if not _prompt_label:
		return
	if use_three_rotations:
		_prompt_label.text = "[E] Girar (%d/3)" % (current_angle_index + 1)
	else:
		_prompt_label.text = "[E] Rotar"


func _apply_beam_visuals() -> void:
	if not _glow_line or not _core_line:
		return
	
	var active := is_energized and is_inside_tree()
	_glow_line.visible = active
	_core_line.visible = active
	if _ambient_light:
		_ambient_light.visible = active
		_ambient_light.color = crystal_color
	if _impact_light:
		_impact_light.visible = active
		_impact_light.color = crystal_color
	
	_glow_line.width = 18.0
	_glow_line.default_color = Color(crystal_color.r, crystal_color.g, crystal_color.b, 0.3)
	
	_core_line.width = 6.0
	_core_line.default_color = Color(crystal_color.r, crystal_color.g, crystal_color.b, 0.95)


# ==============================================================================
# FÍSICA Y ENTRADA DEL JUGADOR
# ==============================================================================

func _physics_process(delta: float) -> void:
	_anim_pulse += delta
	
	if Engine.is_editor_hint():
		if is_energized:
			_sync_three_angles()
			_cast_outgoing_beam()
		return
	
	# Animación suave del cartel [E]
	if _prompt_container and _prompt_container.visible:
		_prompt_anim += delta
		_prompt_container.position.y = -42.0 + sin(_prompt_anim * 4.0) * 2.0
	
	# Lógica según el tipo de cristal
	match crystal_type:
		"Primer_Iluminado (Entrada de Luz)", "Rotable por Jugador [E]":
			_process_rotatable(delta)
		"Empujable (Pedestal)":
			_process_pushable(delta)
		"Fijo (Techo/Pared)":
			pass
	
	# Si está energizado, emitir haz saliente
	if is_energized:
		_cast_outgoing_beam()
	else:
		_clear_outgoing_beam()
	
	queue_redraw()


func _process_pushable(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0.0
	
	var push_dir := 0.0
	if _push_detect_area:
		for body in _push_detect_area.get_overlapping_bodies():
			if _is_player(body):
				var p_vel_x: float = body.velocity.x if body.get("velocity") != null else 0.0
				var rel_x := global_position.x - body.global_position.x
				if absf(p_vel_x) > 10.0 and (p_vel_x * rel_x > 0.0):
					push_dir = signf(p_vel_x)
					break
	
	if push_dir != 0.0:
		velocity.x = push_dir * push_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, 450.0 * delta)
	
	move_and_slide()


func _process_rotatable(_delta: float) -> void:
	if player_in_interaction_range:
		if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_accept"):
			rotate_crystal()
		elif Input.is_physical_key_pressed(KEY_E) and not Input.is_key_pressed(KEY_E):
			rotate_crystal()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if crystal_type not in ["Primer_Iluminado (Entrada de Luz)", "Rotable por Jugador [E]"]:
		return
	if not player_in_interaction_range:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		rotate_crystal()
	elif event is InputEventKey and event.is_pressed() and not event.is_echo() and event.physical_keycode == KEY_E:
		get_viewport().set_input_as_handled()
		rotate_crystal()


## Alterna al siguiente ángulo de rotación
func rotate_crystal() -> void:
	if use_three_rotations:
		current_angle_index = (current_angle_index + 1) % 3
		_sync_three_angles()
	else:
		rotation_angle = wrapf(rotation_angle + rotation_step, 0.0, 360.0)
	
	# Animación suave de giro con Tween
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "_visual_rotation", deg_to_rad(rotation_angle), 0.18)
	
	_update_prompt_text()
	rotated.emit(rotation_angle, current_angle_index)
	queue_redraw()


func _on_interaction_entered(body: Node2D) -> void:
	if _is_player(body) and crystal_type in ["Primer_Iluminado (Entrada de Luz)", "Rotable por Jugador [E]"]:
		player_in_interaction_range = true
		_update_prompt_text()
		if _prompt_container:
			_prompt_container.visible = true


func _on_interaction_exited(body: Node2D) -> void:
	if _is_player(body):
		player_in_interaction_range = false
		if _prompt_container:
			_prompt_container.visible = false


func _is_player(body: Node2D) -> bool:
	if body is CharacterBody2D:
		if body.is_in_group("player") or body.is_in_group("Player"):
			return true
		if body.name == "Player" or body.name.begins_with("Player"):
			return true
	return false


# ==============================================================================
# RECEPCIÓN Y EMISIÓN DE LUZ
# ==============================================================================

## Llamado por una fuente (LightFissure u otro LightCrystal) cuando su haz toca este cristal
func receive_light(source: Object, hit_point: Vector2, in_dir: Vector2, in_color: Color, visited_chain: Array = []) -> void:
	if visited_chain.has(self):
		return
	
	var new_chain := visited_chain.duplicate()
	new_chain.append(self)
	
	_active_sources[source] = {
		"hit_point": hit_point,
		"dir": in_dir,
		"color": in_color,
		"chain": new_chain
	}
	
	if not is_energized:
		is_energized = true
		_apply_beam_visuals()
		energized_changed.emit(true)
		queue_redraw()


## Llamado cuando el haz entrante deja de tocar este cristal
func release_light(source: Object) -> void:
	# El Primer_Iluminado no se apaga por fuentes externas
	if crystal_type == "Primer_Iluminado (Entrada de Luz)":
		return
	
	_active_sources.erase(source)
	
	if _active_sources.is_empty():
		is_energized = false
		_clear_outgoing_beam()
		_apply_beam_visuals()
		energized_changed.emit(false)
		queue_redraw()


func _clear_outgoing_beam() -> void:
	if _downstream_target != null and is_instance_valid(_downstream_target):
		if _downstream_target.has_method("release_light"):
			_downstream_target.release_light(self)
		_downstream_target = null
	
	if _glow_line: _glow_line.clear_points()
	if _core_line: _core_line.clear_points()
	if _impact_light: _impact_light.visible = false
	if _ambient_light: _ambient_light.visible = false
	for pl in _path_lights:
		pl.visible = false


func _cast_outgoing_beam() -> void:
	var out_dir := Vector2.ZERO
	var current_chain: Array = []
	
	if reflection_mode == "Dirección del Cristal (Prisma)":
		out_dir = Vector2.from_angle(_visual_rotation).normalized()
	else:
		if not _active_sources.is_empty():
			var first_source_data: Dictionary = _active_sources.values()[0]
			var in_dir: Vector2 = first_source_data["dir"]
			var normal := Vector2.from_angle(_visual_rotation - PI * 0.5)
			out_dir = in_dir.bounce(normal).normalized()
		else:
			out_dir = Vector2.from_angle(_visual_rotation).normalized()
	
	for s in _active_sources:
		var chain_data: Array = _active_sources[s].get("chain", [])
		for node in chain_data:
			if not current_chain.has(node):
				current_chain.append(node)
	if not current_chain.has(self):
		current_chain.append(self)
	
	# Punto de origen: centro de la gema adelantado 8px hacia la dirección de salida para evitar colisionar consigo mismo
	var gem_center := global_position + Vector2(0, -10)
	var start_pos := gem_center + out_dir * 12.0
	var end_pos := gem_center + out_dir * max_beam_distance
	
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(start_pos, end_pos)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.hit_from_inside = false
	
	# Excluir a sí mismo y a todas sus áreas/hijos colisionadores
	var exclude_list := [get_rid()]
	for child in get_children():
		if child is CollisionObject2D:
			exclude_list.append(child.get_rid())
	query.exclude = exclude_list
	
	var result := space.intersect_ray(query)
	var hit_pos := end_pos
	var new_target: Object = null
	
	if not result.is_empty():
		hit_pos = result.position
		var collider = result.collider
		new_target = _find_light_receiver(collider)
	
	# Si el objetivo aguas abajo cambió (ej. se rotó o movió a otro cristal)
	if new_target != _downstream_target:
		if _downstream_target != null and is_instance_valid(_downstream_target):
			if _downstream_target.has_method("release_light"):
				_downstream_target.release_light(self)
		_downstream_target = new_target
	
	# Alimentar al nuevo objetivo
	if _downstream_target != null and is_instance_valid(_downstream_target):
		if _downstream_target.has_method("receive_light"):
			_downstream_target.receive_light(self, hit_pos, out_dir, crystal_color, current_chain)
	
	_last_hit_pos = hit_pos
	
	# Representación visual del haz
	var local_start := to_local(gem_center)
	var local_end := to_local(hit_pos)
	
	if _glow_line:
		_glow_line.visible = true
		_glow_line.points = PackedVector2Array([local_start, local_end])
	if _core_line:
		_core_line.visible = true
		_core_line.points = PackedVector2Array([local_start, local_end])
	if _impact_light:
		_impact_light.visible = true
		_impact_light.position = local_end
	if _ambient_light:
		_ambient_light.visible = true
	
	# Iluminar el camino entre cristales para ver el suelo y plataformas
	var beam_dist := gem_center.distance_to(hit_pos)
	var step := 70.0
	var count := clampi(int(beam_dist / step), 0, _path_lights.size())
	for i in range(_path_lights.size()):
		if i < count and i > 0:
			var light_pos := local_start + (local_end - local_start) * (float(i) / float(count + 1))
			_path_lights[i].position = light_pos
			_path_lights[i].color = crystal_color
			_path_lights[i].visible = true
		else:
			_path_lights[i].visible = false


func _find_light_receiver(collider: Object) -> Object:
	if collider == null or collider == self:
		return null
	if collider.has_method("receive_light"):
		return collider
	var parent = collider.get_parent()
	if parent != null and parent != self and parent.has_method("receive_light"):
		return parent
	var owner_node = collider.owner
	if owner_node != null and owner_node != self and owner_node.has_method("receive_light"):
		return owner_node
	return null


func _exit_tree() -> void:
	_clear_outgoing_beam()


# ==============================================================================
# DIBUJO PROCEDURAL ESTILIZADO
# ==============================================================================

func _draw() -> void:
	# Haz celestial vertical que entra desde el techo si es Primer_Iluminado
	if crystal_type == "Primer_Iluminado (Entrada de Luz)":
		_draw_sunshaft_stream()
	
	# 1. Dibujar el Pedestal / Base según el tipo
	_draw_base()
	
	# 2. Dibujar la Gema de Cristal (Gira según _visual_rotation)
	_draw_gem()


func _draw_sunshaft_stream() -> void:
	# Haz de luz que desciende desde el techo de la cueva sobre el cristal
	var shaft_top := Vector2(0, -90)
	var shaft_bottom := Vector2(0, -14)
	var pulse := (sin(_anim_pulse * 4.0) * 0.1) + 0.9
	
	# Haz amplio suave
	draw_line(shaft_top, shaft_bottom, Color(1.0, 0.95, 0.75, 0.22 * pulse), 22.0)
	# Rayo central dorado
	draw_line(shaft_top, shaft_bottom, Color(1.0, 0.98, 0.85, 0.65 * pulse), 8.0)
	# Núcleo blanco
	draw_line(shaft_top, shaft_bottom, Color.WHITE, 2.5)
	# Halo de impacto sobre la corona del cristal
	draw_circle(shaft_bottom, 12.0, Color(1.0, 0.9, 0.6, 0.35))


func _draw_base() -> void:
	match crystal_type:
		"Primer_Iluminado (Entrada de Luz)":
			# Gran altar de piedra fúngica con adornos dorados de recepción solar
			var stone_col := Color(0.24, 0.22, 0.3)
			var gold := Color(0.9, 0.78, 0.32)
			
			# Base ancha escalonada
			draw_colored_polygon(PackedVector2Array([
				Vector2(-16, 12), Vector2(16, 12), Vector2(12, 3), Vector2(-12, 3)
			]), stone_col)
			draw_line(Vector2(-16, 12), Vector2(16, 12), gold, 1.5)
			
			# Aro selector / dial dorado
			draw_circle(Vector2(0, -8), 8.0, Color(0.16, 0.14, 0.22))
			draw_arc(Vector2(0, -8), 8.0, 0, TAU, 16, gold, 1.8)
			
			# Marcadores de las 3 rotaciones disponibles
			if use_three_rotations:
				for i in range(3):
					var a_deg := _get_effective_angle(i)
					var a_rad := deg_to_rad(a_deg)
					var dot_pos := Vector2(0, -8) + Vector2.from_angle(a_rad) * 6.5
					var is_current := (i == current_angle_index)
					var dot_col := Color(1.0, 0.92, 0.4, 1.0) if is_current else Color(0.5, 0.45, 0.35, 0.7)
					var dot_rad := 2.5 if is_current else 1.2
					draw_circle(dot_pos, dot_rad, dot_col)

		"Empujable (Pedestal)":
			var base_col := Color(0.24, 0.22, 0.28)
			var trim_col := Color(0.42, 0.38, 0.48)
			var wheel_col := Color(0.14, 0.12, 0.18)
			
			draw_circle(Vector2(-9, 10), 3.5, wheel_col)
			draw_circle(Vector2(9, 10), 3.5, wheel_col)
			
			draw_rect(Rect2(-12, -2, 24, 11), base_col)
			draw_rect(Rect2(-12, -2, 24, 11), trim_col, false, 1.5)
			
			draw_line(Vector2(-4, 0), Vector2(-1, 6), Color(0.12, 0.1, 0.15), 1.2)
			draw_line(Vector2(-1, 6), Vector2(3, 8), Color(0.12, 0.1, 0.15), 1.2)
			
			draw_colored_polygon(PackedVector2Array([
				Vector2(-5, -2), Vector2(5, -2), Vector2(3, -7), Vector2(-3, -7)
			]), trim_col)
			
		"Rotable por Jugador [E]":
			var base_col := Color(0.28, 0.25, 0.32)
			var bronze := Color(0.68, 0.52, 0.28)
			
			draw_colored_polygon(PackedVector2Array([
				Vector2(-14, 10), Vector2(14, 10), Vector2(10, 3), Vector2(-10, 3)
			]), base_col)
			draw_line(Vector2(-10, 3), Vector2(10, 3), bronze, 2.0)
			
			draw_rect(Rect2(-4, -6, 8, 9), bronze)
			
			draw_circle(Vector2(0, -8), 7.5, Color(0.16, 0.14, 0.22))
			draw_arc(Vector2(0, -8), 7.5, 0, TAU, 16, bronze, 1.5)
			
			if use_three_rotations:
				for i in range(3):
					var a_deg := _get_effective_angle(i)
					var a_rad := deg_to_rad(a_deg)
					var dot_pos := Vector2(0, -8) + Vector2.from_angle(a_rad) * 6.0
					var is_current := (i == current_angle_index)
					var dot_col := Color(0.2, 0.9, 1.0, 1.0) if is_current else Color(0.45, 0.4, 0.35, 0.7)
					var dot_rad := 2.0 if is_current else 1.2
					draw_circle(dot_pos, dot_rad, dot_col)
			
		"Fijo (Techo/Pared)":
			var iron := Color(0.3, 0.3, 0.36)
			draw_colored_polygon(PackedVector2Array([
				Vector2(-10, -18), Vector2(10, -18), Vector2(4, -8), Vector2(-4, -8)
			]), iron)
			draw_circle(Vector2(-6, -15), 1.5, Color(0.15, 0.15, 0.2))
			draw_circle(Vector2(6, -15), 1.5, Color(0.15, 0.15, 0.2))


func _draw_gem() -> void:
	var gem_center := Vector2(0, -10)
	var rot := _visual_rotation
	
	var dir := Vector2.from_angle(rot)
	var side := Vector2(-dir.y, dir.x)
	
	var tip := gem_center + dir * 14.0
	var back := gem_center - dir * 10.0
	var left := gem_center + side * 9.0
	var right := gem_center - side * 9.0
	
	var col_main: Color
	var col_bright: Color
	var col_dark: Color
	var col_outline: Color
	
	if is_energized:
		var pulse := (sin(_anim_pulse * 6.0) * 0.15) + 0.85
		col_main = Color(crystal_color.r * 1.1, crystal_color.g * 1.1, crystal_color.b * 1.1, 0.95)
		col_bright = Color(1.0, 1.0, 1.0, 0.95 * pulse)
		col_dark = Color(crystal_color.r * 0.7, crystal_color.g * 0.7, crystal_color.b * 0.7, 0.9)
		col_outline = Color(1.0, 1.0, 1.0, 0.85)
		draw_circle(gem_center, 18.0, Color(crystal_color.r, crystal_color.g, crystal_color.b, 0.28 * pulse))
	else:
		col_main = Color(0.18, 0.38, 0.52, 0.85)
		col_bright = Color(0.35, 0.62, 0.78, 0.9)
		col_dark = Color(0.08, 0.2, 0.32, 0.9)
		col_outline = Color(0.45, 0.72, 0.88, 0.75)
	
	draw_colored_polygon(PackedVector2Array([tip, left, gem_center]), col_bright)
	draw_colored_polygon(PackedVector2Array([tip, right, gem_center]), col_main)
	draw_colored_polygon(PackedVector2Array([gem_center, left, back]), col_main)
	draw_colored_polygon(PackedVector2Array([gem_center, right, back]), col_dark)
	
	draw_polyline(PackedVector2Array([tip, left, back, right, tip]), col_outline, 1.5)
	draw_line(left, right, col_outline, 1.0)
	draw_line(back, tip, col_bright, 1.2)
	
	var arrow_tip := tip + dir * 3.5
	draw_line(tip, arrow_tip, col_bright, 2.0)
