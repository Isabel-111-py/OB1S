class_name Pickup
extends Area2D
## Objeto que el jugador recoge al tocarlo: flechas o una mejora.
## Una vez recogido no vuelve a aparecer aunque salgas y vuelvas al nivel.
##
## Colócalo en el nivel con la escena `pickup.tscn`. Si le agregas un Sprite2D hijo se usa ese
## dibujo; si no, se dibuja un símbolo de prueba.

enum Kind { ARROWS, UPGRADE }


@export var kind: Kind = Kind.ARROWS
@export_group("Flechas")
## A qué espacio de munición suma (0, 1 o 2).
@export_range(0, 2) var ammo_slot: int = 0
## Cuántas flechas da. Si ya llevas el máximo de ese tipo, el objeto se queda donde está.
@export var arrow_amount: int = 5
@export_group("Mejora")
## Identificador único de la mejora (por ejemplo "arco_potente").
@export var upgrade_id: StringName = &""
@export var upgrade_name: String = ""
@export_multiline var upgrade_description: String = ""
## Icono que se muestra en el inventario (opcional).
@export var icon: Texture2D
@export_group("Misión (Opcional)")
## Si se especifica, este objeto solo se puede recoger mientras esta misión esté activa.
## Déjalo vacío para que el jugador pueda recogerlo en cualquier momento.
@export var required_quest_id: String = ""
@export_group("Animación")
## Cuánto sube y baja (px) mientras flota.
@export var bob_height: float = 2.0
@export var bob_speed: float = 3.0

var _collected: bool = false
var _base_y: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	if Inventory.is_collected(_key()):
		queue_free()
		return
	_base_y = position.y
	_time = randf() * TAU # que varios pickups no floten sincronizados
	body_entered.connect(_on_body_entered)
	# Los iconos de munición los define el Bow al aparecer el jugador: se vuelve a dibujar entonces.
	Inventory.ammo_types_changed.connect(queue_redraw)


func _process(delta: float) -> void:
	if _collected:
		return
	_time += delta
	position.y = _base_y + sin(_time * bob_speed) * bob_height


func _is_player(body: Node2D) -> bool:
	if body is Player:
		return true
	if body.is_in_group("player") or body.is_in_group("Player"):
		return true
	if body.name == "Player" or body.name.begins_with("Player"):
		return true
	return false


func _on_body_entered(body: Node2D) -> void:
	if _collected or not _is_player(body):
		return
	_try_collect()


func _try_collect() -> void:
	if _collected:
		return
	
	if not required_quest_id.is_empty():
		if Engine.has_singleton("QuestManager") or has_node("/root/QuestManager"):
			var qm = get_node("/root/QuestManager")
			if qm and qm.get_quest_status(required_quest_id) != qm.QuestStatus.ACTIVE:
				return

	var effective_kind := kind
	if kind == Kind.ARROWS and not upgrade_id.is_empty():
		effective_kind = Kind.UPGRADE

	match effective_kind:
		Kind.ARROWS:
			if Inventory.add_ammo(ammo_slot, arrow_amount) <= 0:
				return # ya llevas el máximo de ese tipo: se queda en el mapa
		Kind.UPGRADE:
			var display_name := upgrade_name if upgrade_name != "" else String(upgrade_id)
			Inventory.add_upgrade(upgrade_id, display_name, upgrade_description, icon)

	_collected = true
	Inventory.mark_collected(_key())
	set_deferred("monitoring", false)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE * 1.6, 0.15)
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	tween.chain().tween_callback(queue_free)


## Clave única de este pickup: escena del nivel + ruta del nodo dentro de ella.
func _key() -> String:
	if owner:
		return "%s:%s" % [owner.scene_file_path, owner.get_path_to(self)]
	return str(get_path())


## Dibujo de prueba: solo si no hay un Sprite2D / AnimatedSprite2D propio.
## Las flechas usan el icono de su tipo de munición; las mejoras, su icono o un rombo dorado.
func _draw() -> void:
	for child in get_children():
		if child is Sprite2D or child is AnimatedSprite2D:
			return
	if kind == Kind.ARROWS:
		draw_texture_rect(Inventory.get_slot_icon(ammo_slot), Rect2(-8, -8, 16, 16), false, Inventory.get_slot_tint(ammo_slot))
	elif icon:
		draw_texture_rect(icon, Rect2(-8, -8, 16, 16), false)
	else:
		var gold := Color(1.0, 0.82, 0.25)
		draw_colored_polygon(PackedVector2Array([Vector2(0, -8), Vector2(7, 0), Vector2(0, 8), Vector2(-7, 0)]), gold)
		draw_polyline(PackedVector2Array([Vector2(0, -8), Vector2(7, 0), Vector2(0, 8), Vector2(-7, 0), Vector2(0, -8)]), Color(0.3, 0.2, 0.0), 1.0)
