class_name InventoryMenu
extends CanvasLayer
## Inventario: 3 espacios de munición (selecciónalos con clic), la lista de mejoras y un botón
## para volver al menú. Pausa el juego mientras está abierto.
##
## Uso: instancia `inventory_menu.tscn` como hijo del nodo Player (igual que HealthLayer).
## Se abre/cierra con la tecla I (o con la acción "inventory" del Input Map, si la creas) y con Esc.
## Requiere el autoload "Inventory" (ver inventory.gd).

## Jugador al que pertenece. Si lo dejas vacío usa el padre.
@export var player: Player
## Acción del Input Map para abrir/cerrar. Si no existe, se usa `fallback_key`.
@export var toggle_action: StringName = &"inventory"
@export var fallback_key: Key = KEY_I
## Escena a la que lleva el botón "Volver al menú".
@export_file("*.tscn") var menu_scene_path: String = "res://UI/MainMenu/main_menu.tscn"
## Al volver al menú, el inventario se vacía (como una partida nueva).
@export var reset_inventory_on_exit: bool = true
## Mejora que hay que tener para poder equipar el paraguas (el `upgrade_id` de un Pickup tipo Mejora).
## Vacío = el paraguas siempre está disponible.
@export var umbrella_upgrade_id: StringName = &""

@export_group("Texturas")
## Imagen del cuadro del menú. Se estira como un 9-patch: los bordes no se deforman.
## Vacío = cuadro liso de color.
@export var panel_texture: Texture2D
## Píxeles de la imagen (desde cada borde) que NO se estiran: el marco y las esquinas.
@export var panel_texture_margin: int = 8
## Espacio (px) entre el borde del cuadro y el contenido.
@export var panel_padding: int = 12
## Imagen de cada espacio de munición (9-patch). Vacío = cuadro liso.
@export var slot_texture: Texture2D
## Imagen del espacio de munición seleccionado. Vacío = se usa `slot_texture` más brillante.
@export var slot_selected_texture: Texture2D
@export var slot_texture_margin: int = 4

@export_group("Diseño")
@export var panel_width: int = 300
## Lado (px) de cada espacio de munición.
@export var slot_size: int = 64
## Alto (px) de la lista de mejoras; si hay más, se desplaza.
@export var upgrades_area_height: int = 64
@export var title_font_size: int = 16
@export var body_font_size: int = 12
@export var panel_color: Color = Color(0.098, 0.157, 0.204, 0.96)
@export var border_color: Color = Color(0.235, 0.38, 0.439)
@export var selected_border_color: Color = Color(0.306, 0.886, 0.659)
## Color del número de flechas cuando no queda ninguna.
@export var empty_count_color: Color = Color(0.9, 0.25, 0.25)

var _root: Control
var _upgrades_box: VBoxContainer
var _upgrades_scroll: ScrollContainer
var _umbrella_button: Button
var _empty_label: Label
var _continue_button: Button
var _menu_button: Button
var _slot_buttons: Array[Button] = []
var _slot_icons: Array[TextureRect] = []
var _slot_counts: Array[Label] = []
var _slot_names: Array[Label] = []
var _is_open: bool = false


func _ready() -> void:
	layer = 20 # por encima del HUD (10) y por debajo del fundido a negro (100)
	process_mode = Node.PROCESS_MODE_ALWAYS # sigue recibiendo input con el juego en pausa
	if player == null:
		player = get_parent() as Player

	_build()
	_root.visible = false
	Inventory.ammo_changed.connect(_refresh.unbind(2))
	Inventory.ammo_selected.connect(_refresh.unbind(1))
	Inventory.ammo_types_changed.connect(_refresh)
	Inventory.upgrade_added.connect(_refresh.unbind(1))
	Inventory.umbrella_toggled.connect(_refresh.unbind(1))
	_refresh()


func _exit_tree() -> void:
	# Si el jugador desaparece con el menú abierto, no dejar el juego en pausa.
	if _is_open:
		get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if not _is_toggle(event):
		return
	get_viewport().set_input_as_handled()
	if _is_open:
		close()
	elif _can_open():
		open()


func open() -> void:
	_is_open = true
	_refresh()
	_root.visible = true
	get_tree().paused = true
	_continue_button.grab_focus()


func close() -> void:
	_is_open = false
	_root.visible = false
	get_tree().paused = false


func _is_toggle(event: InputEvent) -> bool:
	if event.is_action_pressed(&"ui_cancel"):
		return true
	if InputMap.has_action(toggle_action):
		return event.is_action_pressed(toggle_action)
	var key_event := event as InputEventKey
	return key_event != null and key_event.pressed and not key_event.echo \
		and key_event.physical_keycode == fallback_key


func _can_open() -> bool:
	return player != null and not player.is_dead \
		and player.process_mode != Node.PROCESS_MODE_DISABLED \
		and not get_tree().paused


func _return_to_menu() -> void:
	_menu_button.disabled = true
	_is_open = false
	get_tree().paused = false
	if reset_inventory_on_exit:
		Inventory.reset()
	SceneManager.change_to_menu(menu_scene_path)


# ---------------------------------------------------------------------------
# Construcción de la interfaz
# ---------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(panel_width, 0)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)

	var title := _make_label("Inventario", title_font_size)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	box.add_child(_make_label("Munición", body_font_size))
	box.add_child(_build_slots_row())
	var hint := _make_label("En el juego: teclas 1-3 o rueda del ratón", body_font_size - 3)
	hint.modulate = Color(1, 1, 1, 0.5)
	box.add_child(hint)

	# Paraguas: equipado cubre del agua, pero no deja disparar flechas.
	_umbrella_button = _make_button("")
	_umbrella_button.pressed.connect(Inventory.toggle_umbrella)
	box.add_child(_umbrella_button)

	box.add_child(HSeparator.new())
	box.add_child(_make_label("Mejoras", body_font_size))

	_empty_label = _make_label("Aún no tienes mejoras", body_font_size - 2)
	_empty_label.modulate = Color(1, 1, 1, 0.55)
	box.add_child(_empty_label)

	_upgrades_scroll = ScrollContainer.new()
	_upgrades_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_upgrades_scroll.custom_minimum_size = Vector2(0, upgrades_area_height)
	box.add_child(_upgrades_scroll)

	_upgrades_box = VBoxContainer.new()
	_upgrades_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrades_box.add_theme_constant_override("separation", 6)
	_upgrades_scroll.add_child(_upgrades_box)

	box.add_child(HSeparator.new())

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	box.add_child(buttons)

	_continue_button = _make_button("Continuar")
	_continue_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_continue_button.pressed.connect(close)
	buttons.add_child(_continue_button)

	_menu_button = _make_button("Volver al menú")
	_menu_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_button.pressed.connect(_return_to_menu)
	buttons.add_child(_menu_button)


func _build_slots_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)

	for slot in Inventory.SLOT_COUNT:
		var button := Button.new()
		button.custom_minimum_size = Vector2(slot_size, slot_size)
		button.pressed.connect(Inventory.select_ammo.bind(slot))
		button.add_theme_stylebox_override("focus", _make_focus_style())

		# Contenido del espacio: icono arriba, cantidad en medio y nombre abajo.
		var content := VBoxContainer.new()
		content.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.add_theme_constant_override("separation", 1)
		button.add_child(content)

		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(24, 24)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		content.add_child(icon)

		var count := _make_label("", body_font_size)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(count)

		var type_name := _make_label("", maxi(body_font_size - 4, 6))
		type_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		type_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		type_name.clip_text = true
		type_name.modulate = Color(1, 1, 1, 0.7)
		content.add_child(type_name)

		row.add_child(button)
		_slot_buttons.append(button)
		_slot_icons.append(icon)
		_slot_counts.append(count)
		_slot_names.append(type_name)
	return row


func _make_panel_style() -> StyleBox:
	if panel_texture:
		var textured := StyleBoxTexture.new()
		textured.texture = panel_texture
		textured.set_texture_margin_all(panel_texture_margin)
		textured.set_content_margin_all(panel_padding)
		return textured
	var flat := StyleBoxFlat.new()
	flat.bg_color = panel_color
	flat.border_color = border_color
	flat.set_border_width_all(1)
	flat.set_corner_radius_all(4)
	flat.set_content_margin_all(panel_padding)
	return flat


func _make_slot_style(selected: bool) -> StyleBox:
	var texture: Texture2D = slot_texture
	if selected and slot_selected_texture:
		texture = slot_selected_texture
	if texture:
		var textured := StyleBoxTexture.new()
		textured.texture = texture
		textured.set_texture_margin_all(slot_texture_margin)
		if selected and slot_selected_texture == null:
			textured.modulate_color = Color(1.4, 1.4, 0.9)
		return textured
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0.07, 0.11, 0.15, 0.95)
	flat.border_color = selected_border_color if selected else border_color
	flat.set_border_width_all(2 if selected else 1)
	flat.set_corner_radius_all(3)
	return flat


## Contorno del espacio que tiene el foco (teclado / mando).
func _make_focus_style() -> StyleBox:
	var flat := StyleBoxFlat.new()
	flat.draw_center = false
	flat.border_color = Color(1, 1, 1, 0.8)
	flat.set_border_width_all(1)
	flat.set_corner_radius_all(3)
	return flat


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", body_font_size)
	return button


# ---------------------------------------------------------------------------
# Actualización
# ---------------------------------------------------------------------------

## Vuelve a dibujar los espacios de munición y la lista de mejoras.
func _refresh() -> void:
	_refresh_slots()
	_refresh_umbrella()
	_refresh_upgrades()


func _refresh_umbrella() -> void:
	var available := umbrella_upgrade_id == &"" or Inventory.has_upgrade(umbrella_upgrade_id)
	_umbrella_button.disabled = not available
	if not available:
		_umbrella_button.text = "Paraguas (aún no lo tienes)"
	elif Inventory.umbrella_equipped:
		_umbrella_button.text = "Guardar paraguas (sin disparar)"
	else:
		_umbrella_button.text = "Equipar paraguas"


func _refresh_slots() -> void:
	for slot in _slot_buttons.size():
		var selected := slot == Inventory.selected_slot
		var count := Inventory.get_ammo(slot)
		var type := Inventory.get_type(slot)

		var style := _make_slot_style(selected)
		var button := _slot_buttons[slot]
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			button.add_theme_stylebox_override(state, style)
		button.tooltip_text = type.display_name if type else ""

		_slot_icons[slot].texture = Inventory.get_slot_icon(slot)
		_slot_icons[slot].modulate = Inventory.get_slot_tint(slot)
		_slot_counts[slot].text = "x%d" % count
		_slot_counts[slot].add_theme_color_override(
			"font_color", Color.WHITE if count > 0 else empty_count_color)
		_slot_names[slot].text = type.display_name if type else ""


func _refresh_upgrades() -> void:
	for child in _upgrades_box.get_children():
		child.queue_free()
	_empty_label.visible = Inventory.upgrades.is_empty()
	_upgrades_scroll.visible = not Inventory.upgrades.is_empty()

	for id in Inventory.upgrades:
		var data: Dictionary = Inventory.upgrades[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var icon: Texture2D = data.get("icon")
		if icon:
			var rect := TextureRect.new()
			rect.texture = icon
			rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rect.custom_minimum_size = Vector2(16, 16)
			row.add_child(rect)

		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_child(_make_label(str(data.get("name", id)), body_font_size))

		var description: String = data.get("description", "")
		if description != "":
			var desc_label := _make_label(description, body_font_size - 2)
			desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc_label.modulate = Color(1, 1, 1, 0.65)
			text.add_child(desc_label)

		row.add_child(text)
		_upgrades_box.add_child(row)
