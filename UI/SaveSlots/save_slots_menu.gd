class_name SaveSlotsMenu
extends CanvasLayer
## Menú de ranuras de partida. Se usa en dos modos:
##   - SAVE: lo abre el Checkpoint al pulsar [E]. Pausa el juego y deja elegir dónde guardar.
##   - LOAD: lo abre el menú principal con "Cargar partida". Las ranuras vacías aparecen
##           deshabilitadas.
##
## Uso:
##   SaveSlotsMenu.open_save(self, global_position, 1.0)
##   SaveSlotsMenu.open_load(self)
## Se construye por código (misma paleta que el menú principal) y se elimina solo al cerrar.

## Se emite cuando el menú se cierra (por VOLVER, ESC o tras guardar).
signal closed

enum Mode { SAVE, LOAD }

var mode: Mode = Mode.LOAD

var _save_pos: Vector2 = Vector2.ZERO
var _save_facing: float = 1.0
var _pauses_game: bool = false

var _root: Control
var _slot_buttons: Array[Button] = []
var _status_label: Label
var _close_button: Button
var _confirm_slot: int = -1
var _loading: bool = false
var _closing: bool = false


## Abre el menú para GUARDAR. El jugador reaparecerá en `pos` al cargar esa ranura.
static func open_save(parent: Node, pos: Vector2, facing: float = 1.0) -> SaveSlotsMenu:
	var menu := SaveSlotsMenu.new()
	menu.mode = Mode.SAVE
	menu._save_pos = pos
	menu._save_facing = facing
	menu._pauses_game = true
	parent.add_child(menu)
	return menu


## Abre el menú para CARGAR.
static func open_load(parent: Node) -> SaveSlotsMenu:
	var menu := SaveSlotsMenu.new()
	menu.mode = Mode.LOAD
	parent.add_child(menu)
	return menu


func _ready() -> void:
	layer = 60 # por encima del HUD (10), inventario (20) y pantalla de muerte (30)
	process_mode = Node.PROCESS_MODE_ALWAYS # sigue funcionando con el juego en pausa
	_build()
	_refresh_slots()
	if _pauses_game:
		get_tree().paused = true
	_focus_first()


func _exit_tree() -> void:
	# Si el menú desaparece (cambio de nivel, etc.) nunca debe dejar el juego en pausa.
	if _pauses_game and is_inside_tree():
		get_tree().paused = false


## Se usa _input (no _unhandled_input) para que ESC cierre este menú antes que el
## inventario o el menú principal.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not _loading:
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	if _closing:
		return
	_closing = true
	if _pauses_game:
		get_tree().paused = false
	closed.emit()
	queue_free()


# ---------------------------------------------------------------------------
# Lógica de ranuras
# ---------------------------------------------------------------------------

func _on_slot_pressed(slot: int) -> void:
	if _loading or _closing:
		return
	match mode:
		Mode.SAVE:
			_try_save(slot)
		Mode.LOAD:
			_try_load(slot)


func _try_save(slot: int) -> void:
	# Si la ranura ya tiene una partida, se pide pulsar una segunda vez para sobrescribir.
	if SaveManager.has_save(slot) and _confirm_slot != slot:
		_confirm_slot = slot
		_set_status("La ranura %d ya tiene una partida.\nPulsa de nuevo para sobrescribirla." % slot, Color(0.98, 0.78, 0.25))
		return

	if SaveManager.save_game(slot, _save_pos, _save_facing):
		_confirm_slot = -1
		_refresh_slots()
		for button in _slot_buttons:
			button.disabled = true
		_close_button.disabled = true
		_set_status("¡Partida guardada en la ranura %d!" % slot, Color(0.35, 0.95, 0.55))
		get_tree().create_timer(0.9).timeout.connect(close)
	else:
		_set_status("No se pudo guardar la partida.", Color(0.95, 0.35, 0.35))


func _try_load(slot: int) -> void:
	_loading = true
	for button in _slot_buttons:
		button.disabled = true
	_close_button.disabled = true
	_set_status("Cargando partida...", Color(0.35, 0.85, 0.95))
	if not SaveManager.load_game(slot):
		# Ranura dañada o nivel inexistente: se devuelve el control al jugador.
		_loading = false
		_close_button.disabled = false
		_refresh_slots()
		_set_status("No se pudo cargar la ranura %d." % slot, Color(0.95, 0.35, 0.35))
		_focus_first()


func _refresh_slots() -> void:
	for i in _slot_buttons.size():
		var slot := i + 1
		_slot_buttons[i].text = _slot_text(slot)
		_slot_buttons[i].disabled = (mode == Mode.LOAD and not SaveManager.has_save(slot))

	if mode == Mode.LOAD:
		if SaveManager.has_any_save():
			_set_status("Elige la partida que quieres continuar.")
		else:
			_set_status("Todavía no hay partidas guardadas.\nGuarda en un checkpoint con [E].")
	else:
		_set_status("Elige una ranura para guardar.")


func _slot_text(slot: int) -> String:
	var info: Dictionary = SaveManager.get_slot_info(slot)
	if info.is_empty():
		return "RANURA %d\n— Vacía —" % slot
	var when := String(info["saved_at"]).substr(0, 16) # sin segundos
	return "RANURA %d  —  %s\n%s   ·   Vida %d/%d" % [
		slot, info["level_name"], when, info["health"], info["max_health"]
	]


func _focus_first() -> void:
	for button in _slot_buttons:
		if not button.disabled:
			button.grab_focus.call_deferred()
			return
	_close_button.grab_focus.call_deferred()


func _set_status(text: String, color: Color = Color(0.702, 0.82, 0.882)) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)


# ---------------------------------------------------------------------------
# Construcción de la interfaz
# ---------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP # bloquea clics al juego/menú de fondo
	_root.theme = _make_theme()
	add_child(_root)

	var overlay := ColorRect.new()
	overlay.color = Color(0.02, 0.039, 0.059, 0.82)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(330, 0)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title := Label.new()
	title.text = "GUARDAR PARTIDA" if mode == Mode.SAVE else "CARGAR PARTIDA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.98, 0.933, 0.824))
	box.add_child(title)

	box.add_child(HSeparator.new())

	for slot in range(1, SaveManager.SLOT_COUNT + 1):
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 38)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_slot_pressed.bind(slot))
		box.add_child(button)
		_slot_buttons.append(button)

	_status_label = Label.new()
	_status_label.custom_minimum_size = Vector2(0, 30)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 10)
	box.add_child(_status_label)

	_close_button = Button.new()
	_close_button.text = "CANCELAR" if mode == Mode.SAVE else "VOLVER"
	_close_button.custom_minimum_size = Vector2(110, 0)
	_close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_close_button.pressed.connect(close)
	box.add_child(_close_button)


func _make_theme() -> Theme:
	var theme := Theme.new()
	theme.set_stylebox("normal", "Button", _button_style(Color(0.098, 0.157, 0.204, 0.85), Color(0.235, 0.38, 0.439, 0.85)))
	theme.set_stylebox("hover", "Button", _button_style(Color(0.157, 0.278, 0.322, 0.95), Color(0.306, 0.886, 0.659, 1.0)))
	theme.set_stylebox("pressed", "Button", _button_style(Color(0.078, 0.122, 0.153, 0.95), Color(0.22, 0.718, 0.533, 1.0)))
	theme.set_stylebox("disabled", "Button", _button_style(Color(0.06, 0.09, 0.12, 0.7), Color(0.15, 0.22, 0.27, 0.7)))

	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_border_width_all(1)
	focus.border_color = Color(0.306, 0.886, 0.659, 1.0)
	focus.set_corner_radius_all(4)
	focus.set_expand_margin_all(1.0)
	theme.set_stylebox("focus", "Button", focus)

	theme.set_color("font_color", "Button", Color(0.851, 0.91, 0.941))
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_focus_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color(0.651, 0.784, 0.824))
	theme.set_color("font_disabled_color", "Button", Color(0.45, 0.52, 0.56))
	theme.set_font_size("font_size", "Button", 11)
	theme.set_font_size("font_size", "Label", 11)

	var line := StyleBoxLine.new()
	line.color = Color(0.251, 0.447, 0.518, 0.6)
	theme.set_stylebox("separator", "HSeparator", line)
	return theme


func _button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.059, 0.09, 0.122, 0.96)
	style.border_color = Color(0.306, 0.549, 0.62, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	return style
