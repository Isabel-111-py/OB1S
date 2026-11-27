@tool
class_name LightReceiver
extends Area2D

## Sensor o receptor de luz (Ojo rúnico / Flor solar mecánica).
## Cuando el haz de luz de una fisura o de un cristal impacta sobre este receptor,
## se activa e ilumina su entorno, pudiendo abrir compuertas o poner en marcha elevadores.

signal activated(state: bool)

@export_group("Conexiones de Mecanismos")
## Compuerta que se abrirá al recibir luz
@export var target_gate: Gate = null
## Elevador que se activará al recibir luz
@export var target_elevator: Elevator = null
## Si es verdadero, permanece activado permanentemente una vez que recibió luz por primera vez
@export var stay_active_once_powered: bool = false

@export_group("Aspecto")
@export var receiver_color: Color = Color(1.0, 0.85, 0.25, 0.95)

var is_powered: bool = false
var _active_sources: Array = []
var _anim_time: float = 0.0
var _bloom_progress: float = 0.0 # 0.0 cerrado, 1.0 abierto
var _ambient_light: PointLight2D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	_setup_light()


func _setup_light() -> void:
	_ambient_light = get_node_or_null("AmbientLight") as PointLight2D
	if not _ambient_light:
		_ambient_light = PointLight2D.new()
		_ambient_light.name = "AmbientLight"
		_ambient_light.texture = _get_or_create_light_texture()
		_ambient_light.texture_scale = 1.6
		_ambient_light.energy = 1.6
		_ambient_light.color = receiver_color
		_ambient_light.visible = false
		add_child(_ambient_light)


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


func _physics_process(delta: float) -> void:
	_anim_time += delta
	
	var target_bloom := 1.0 if is_powered else 0.0
	_bloom_progress = move_toward(_bloom_progress, target_bloom, 4.0 * delta)
	
	if _ambient_light:
		_ambient_light.visible = _bloom_progress > 0.05
		_ambient_light.energy = 1.6 * _bloom_progress
	
	queue_redraw()


## Invocado cuando un haz de luz impacta sobre este receptor
func receive_light(source: Object, _hit_point: Vector2, _in_dir: Vector2 = Vector2.ZERO, in_color: Color = Color.WHITE, _chain: Array = []) -> void:
	if not _active_sources.has(source):
		_active_sources.append(source)
	
	if not is_powered:
		is_powered = true
		receiver_color = in_color
		if _ambient_light:
			_ambient_light.color = in_color
		
		_trigger_mechanisms(true)
		activated.emit(true)
		queue_redraw()


## Invocado cuando el haz de luz deja de impactar
func release_light(source: Object) -> void:
	_active_sources.erase(source)
	
	if _active_sources.is_empty():
		if not stay_active_once_powered:
			is_powered = false
			_trigger_mechanisms(false)
			activated.emit(false)
			queue_redraw()


func _trigger_mechanisms(active: bool) -> void:
	if target_gate != null and is_instance_valid(target_gate):
		if active:
			target_gate.open()
		else:
			target_gate.close()
	
	if target_elevator != null and is_instance_valid(target_elevator):
		if active:
			target_elevator.start()


func _draw() -> void:
	# Soporte de piedra o metal
	var base_col := Color(0.24, 0.22, 0.28)
	var bronze := Color(0.55, 0.45, 0.3)
	
	draw_colored_polygon(PackedVector2Array([
		Vector2(-8, 12), Vector2(8, 12), Vector2(5, 2), Vector2(-5, 2)
	]), base_col)
	
	# Pedestal
	draw_rect(Rect2(-3, -2, 6, 6), bronze)
	
	# Núcleo / Flor solar
	var center := Vector2(0, -6)
	var num_petals := 6
	var petal_dist := 6.0 + _bloom_progress * 5.0
	
	var petal_col := Color(0.35, 0.38, 0.45)
	if is_powered:
		petal_col = Color(receiver_color.r * 1.2, receiver_color.g * 1.2, receiver_color.b * 1.2)
	
	# Pétalos que se abren con la luz
	for i in range(num_petals):
		var angle := (float(i) / float(num_petals)) * TAU + _anim_time * 0.5 * _bloom_progress
		var offset := Vector2.from_angle(angle) * petal_dist
		draw_circle(center + offset, 3.0 + _bloom_progress * 1.5, petal_col)
	
	# Ojo / Gema central
	if is_powered:
		var pulse := (sin(_anim_time * 6.0) * 0.15) + 0.85
		draw_circle(center, 9.0, Color(receiver_color.r, receiver_color.g, receiver_color.b, 0.35 * pulse))
		draw_circle(center, 5.0, Color.WHITE)
	else:
		draw_circle(center, 4.0, Color(0.18, 0.2, 0.26))
		draw_circle(center, 2.0, Color(0.35, 0.38, 0.45))
