@tool
class_name LightFissure
extends Node2D

## Grieta en el techo de la caverna por donde penetra un haz de luz solar o exterior.
## Proyecta un rayo continuo que ilumina el entorno y activa los cristales reflectores.

@export_group("Haz de Luz")
## Ángulo de proyección en grados (90 = Hacia abajo vertical, 45 = Diagonal derecha, 135 = Diagonal izquierda)
@export_range(0.0, 360.0, 5.0) var beam_angle: float = 90.0:
	set(val):
		beam_angle = val
		queue_redraw()

## Distancia máxima del haz de luz
@export var max_beam_distance: float = 1200.0:
	set(val):
		max_beam_distance = val
		queue_redraw()

## Color del haz de luz (luz cálida y natural de grieta solar)
@export var beam_color: Color = Color(1.0, 0.88, 0.65, 0.85):
	set(val):
		beam_color = val
		_apply_beam_visuals()
		queue_redraw()

## Ancho visual del haz de luz
@export var beam_width: float = 8.0:
	set(val):
		beam_width = val
		_apply_beam_visuals()
		queue_redraw()

## Activa o apaga la emisión de luz
@export var is_active: bool = true:
	set(val):
		is_active = val
		if not val and _current_target != null and is_instance_valid(_current_target):
			if _current_target.has_method("release_light"):
				_current_target.release_light(self)
			_current_target = null
		_apply_beam_visuals()
		queue_redraw()

@export_group("Aspecto de la Grieta")
## Ancho de la abertura de roca en el techo
@export var fissure_width: float = 44.0:
	set(val):
		fissure_width = val
		queue_redraw()

# --- Nodos Hijos ---
var _glow_line: Line2D
var _core_line: Line2D
var _origin_light: PointLight2D
var _impact_light: PointLight2D
var _path_lights: Array[PointLight2D] = []

var _current_target: Object = null
var _current_hit_pos: Vector2 = Vector2.ZERO
var _dust_anim_time: float = 0.0


func _ready() -> void:
	_setup_internal_nodes()
	_apply_beam_visuals()


func _setup_internal_nodes() -> void:
	# Línea de resplandor exterior
	_glow_line = get_node_or_null("GlowLine") as Line2D
	if not _glow_line:
		_glow_line = Line2D.new()
		_glow_line.name = "GlowLine"
		_glow_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		_glow_line.end_cap_mode = Line2D.LINE_CAP_ROUND
		add_child(_glow_line)
	
	# Línea brillante central
	_core_line = get_node_or_null("CoreLine") as Line2D
	if not _core_line:
		_core_line = Line2D.new()
		_core_line.name = "CoreLine"
		_core_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		_core_line.end_cap_mode = Line2D.LINE_CAP_ROUND
		add_child(_core_line)
	
	# Luz en el origen de la grieta
	_origin_light = get_node_or_null("OriginLight") as PointLight2D
	if not _origin_light:
		_origin_light = PointLight2D.new()
		_origin_light.name = "OriginLight"
		_origin_light.texture = _get_or_create_light_texture()
		_origin_light.texture_scale = 1.2
		add_child(_origin_light)
	
	# Luz en el punto de impacto
	_impact_light = get_node_or_null("ImpactLight") as PointLight2D
	if not _impact_light:
		_impact_light = PointLight2D.new()
		_impact_light.name = "ImpactLight"
		_impact_light.texture = _get_or_create_light_texture()
		_impact_light.texture_scale = 1.4
		add_child(_impact_light)
	
	# Pool de luces a lo largo del camino para iluminar el suelo y plataformas intermedias
	_ensure_path_lights()


func _ensure_path_lights() -> void:
	var tex := _get_or_create_light_texture()
	while _path_lights.size() < 12:
		var l := PointLight2D.new()
		l.name = "PathLight_%d" % _path_lights.size()
		l.texture = tex
		l.texture_scale = 1.2
		l.energy = 0.5
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


func _apply_beam_visuals() -> void:
	if not _glow_line or not _core_line:
		return
	
	var active_visible := is_active and is_inside_tree()
	_glow_line.visible = active_visible
	_core_line.visible = active_visible
	if _origin_light:
		_origin_light.visible = active_visible
		_origin_light.color = beam_color
		_origin_light.energy = 0.8
	if _impact_light:
		_impact_light.visible = active_visible
		_impact_light.color = beam_color
		_impact_light.energy = 0.75
	
	_glow_line.width = beam_width * 2.4
	_glow_line.default_color = Color(beam_color.r, beam_color.g * 0.95, beam_color.b * 0.8, 0.22)
	
	_core_line.width = beam_width * 0.6
	_core_line.default_color = Color(1.0, 0.95, 0.85, 0.85)


func _physics_process(delta: float) -> void:
	_dust_anim_time += delta
	
	if not is_active:
		if _current_target != null and is_instance_valid(_current_target):
			if _current_target.has_method("release_light"):
				_current_target.release_light(self)
			_current_target = null
		if _glow_line: _glow_line.clear_points()
		if _core_line: _core_line.clear_points()
		if _impact_light: _impact_light.visible = false
		for pl in _path_lights:
			pl.visible = false
		return
	
	_cast_beam()


func _cast_beam() -> void:
	var ray_dir := Vector2.from_angle(deg_to_rad(beam_angle)).normalized()
	var start_pos := global_position + ray_dir * 10.0
	var end_pos := start_pos + ray_dir * max_beam_distance
	
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(start_pos, end_pos)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.hit_from_inside = false
	
	var result := space.intersect_ray(query)
	var hit_pos := end_pos
	var new_target: Object = null
	
	if not result.is_empty():
		hit_pos = result.position
		var collider = result.collider
		new_target = _find_light_receiver(collider)
	
	# Actualizar destino de luz si cambió
	if new_target != _current_target:
		if _current_target != null and is_instance_valid(_current_target):
			if _current_target.has_method("release_light"):
				_current_target.release_light(self)
		_current_target = new_target
	
	# Alimentar al objetivo actual
	if _current_target != null and is_instance_valid(_current_target):
		if _current_target.has_method("receive_light"):
			_current_target.receive_light(self, hit_pos, ray_dir, beam_color, [self])
	
	_current_hit_pos = hit_pos
	
	# Actualizar representación gráfica del haz
	var local_start := Vector2.ZERO
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
	if _origin_light:
		_origin_light.visible = true
		_origin_light.position = local_start
	
	# Iluminar el camino a lo largo del haz para que el jugador vea plataformas intermedias
	var beam_dist := start_pos.distance_to(hit_pos)
	var step := 75.0
	var count := clampi(int(beam_dist / step), 0, _path_lights.size())
	for i in range(_path_lights.size()):
		if i < count and i > 0:
			var light_pos := local_start + (local_end - local_start) * (float(i) / float(count + 1))
			_path_lights[i].position = light_pos
			_path_lights[i].color = beam_color
			_path_lights[i].visible = true
		else:
			_path_lights[i].visible = false


func _find_light_receiver(collider: Object) -> Object:
	if collider == null:
		return null
	if collider.has_method("receive_light"):
		return collider
	var parent = collider.get_parent()
	if parent != null and parent.has_method("receive_light"):
		return parent
	return null


func _exit_tree() -> void:
	if _current_target != null and is_instance_valid(_current_target):
		if _current_target.has_method("release_light"):
			_current_target.release_light(self)
		_current_target = null


func _draw() -> void:
	# Dibujar la fisura de piedra en el techo
	var w := fissure_width * 0.5
	
	# Borde de roca oscura
	var rock_col := Color(0.18, 0.16, 0.22)
	var rock_pts := PackedVector2Array([
		Vector2(-w - 6, -10),
		Vector2(-w + 4, 4),
		Vector2(-8, 8),
		Vector2(6, 4),
		Vector2(w - 4, 6),
		Vector2(w + 8, -10)
	])
	draw_colored_polygon(rock_pts, rock_col)
	
	# Grieta luminosa interior
	if is_active:
		var inner_col := Color(beam_color.r, beam_color.g, beam_color.b, 0.9)
		var inner_pts := PackedVector2Array([
			Vector2(-w + 6, -4),
			Vector2(-4, 3),
			Vector2(4, 2),
			Vector2(w - 6, -4)
		])
		draw_polyline(inner_pts, inner_col, 5.0)
		# Halo resplandeciente
		draw_circle(Vector2(0, 0), 10.0, Color(beam_color.r, beam_color.g, beam_color.b, 0.35))
	else:
		var dark_pts := PackedVector2Array([
			Vector2(-w + 6, -4),
			Vector2(-4, 1),
			Vector2(4, 0),
			Vector2(w - 6, -4)
		])
		draw_polyline(dark_pts, Color(0.08, 0.07, 0.1), 3.0)
