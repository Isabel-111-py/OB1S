@tool
class_name CrystalPedestal
extends Area2D

## Zócalo o pedestal receptor en el suelo para cristales empujables.
## Cuando un cristal empujable llega a este zócalo, se acopla en el centro
## y puede accionar compuertas, elevadores o mecanismos.

signal crystal_docked(crystal: LightCrystal)
signal crystal_undocked(crystal: LightCrystal)

@export_group("Comportamiento")
## Si es verdadero, el cristal queda permanentemente fijado al pedestal una vez acoplado
@export var lock_permanently: bool = false
## Si es verdadero, requiere que el cristal esté energizado (con luz) para activar compuertas
@export var require_light_energized: bool = false

@export_group("Conexiones de Mecanismos (Opcional)")
## Compuerta que se abrirá al colocar el cristal en este pedestal
@export var target_gate: Gate = null
## Elevador que se activará
@export var target_elevator: Elevator = null

var docked_crystal: LightCrystal = null
var _anim_glow: float = 0.0


func _ready() -> void:
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	_anim_glow += delta
	
	if Engine.is_editor_hint():
		return
	
	# Si hay un cristal acoplándose, ayudar a centrarlo suavemente
	if docked_crystal != null and is_instance_valid(docked_crystal):
		var target_x := global_position.x
		var diff := target_x - docked_crystal.global_position.x
		if absf(diff) > 0.5 and not lock_permanently:
			docked_crystal.global_position.x = move_toward(docked_crystal.global_position.x, target_x, 60.0 * delta)
		elif lock_permanently:
			docked_crystal.global_position.x = target_x
			docked_crystal.velocity.x = 0.0
	
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if body is LightCrystal:
		var crystal := body as LightCrystal
		if crystal.crystal_type == "Empujable (Pedestal)":
			docked_crystal = crystal
			crystal.is_docked = true
			crystal.current_pedestal = self
			
			if lock_permanently:
				crystal.velocity.x = 0.0
			
			if require_light_energized:
				if not crystal.energized_changed.is_connected(_on_crystal_energized_changed):
					crystal.energized_changed.connect(_on_crystal_energized_changed)
				_check_activation(crystal.is_energized)
			else:
				_check_activation(true)
			
			crystal_docked.emit(crystal)
			queue_redraw()


func _on_body_exited(body: Node2D) -> void:
	if body == docked_crystal:
		var crystal := docked_crystal
		crystal.is_docked = false
		crystal.current_pedestal = null
		if crystal.energized_changed.is_connected(_on_crystal_energized_changed):
			crystal.energized_changed.disconnect(_on_crystal_energized_changed)
		
		docked_crystal = null
		_check_activation(false)
		crystal_undocked.emit(crystal)
		queue_redraw()


func _on_crystal_energized_changed(is_en: bool) -> void:
	if require_light_energized:
		_check_activation(is_en)


func _check_activation(active: bool) -> void:
	if target_gate != null and is_instance_valid(target_gate):
		if active:
			target_gate.open()
		else:
			target_gate.close()
	
	if target_elevator != null and is_instance_valid(target_elevator):
		if active:
			target_elevator.start()


func _draw() -> void:
	# Dibujar el hueco o zócalo de piedra en el suelo
	var stone_dark := Color(0.14, 0.12, 0.18)
	var stone_rim := Color(0.35, 0.32, 0.42)
	var has_crystal := docked_crystal != null
	
	# Rebaje en el suelo
	draw_colored_polygon(PackedVector2Array([
		Vector2(-16, 8), Vector2(16, 8), Vector2(13, 0), Vector2(-13, 0)
	]), stone_dark)
	
	draw_polyline(PackedVector2Array([
		Vector2(-16, 8), Vector2(-13, 0), Vector2(13, 0), Vector2(16, 8)
	]), stone_rim, 2.0)
	
	# Marcas rúnicas en el zócalo
	var rune_col := Color(0.2, 0.85, 1.0, 0.9) if has_crystal else Color(0.3, 0.35, 0.45, 0.5)
	if has_crystal:
		var pulse := (sin(_anim_glow * 5.0) * 0.2) + 0.8
		rune_col.a *= pulse
		draw_circle(Vector2(0, 4), 5.0, Color(rune_col.r, rune_col.g, rune_col.b, 0.25))
	
	draw_line(Vector2(-8, 4), Vector2(8, 4), rune_col, 1.5)
	draw_line(Vector2(0, 1), Vector2(0, 7), rune_col, 1.5)
