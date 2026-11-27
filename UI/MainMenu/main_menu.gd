class_name MainMenu
extends Control

## Ruta de la escena del primer nivel que se cargará al pulsar "Nueva partida".
@export_file("*.tscn") var first_level_path: String = "res://Levels/Forest/lvl1_forest.tscn"

## Velocidad de desplazamiento horizontal para cada capa de fondo parallax (px/segundo)
@export var parallax_speed_layer1: float = 6.0
@export var parallax_speed_layer2: float = 14.0
@export var parallax_speed_layer3: float = 24.0
@export var parallax_speed_layer4: float = 40.0
@export var parallax_speed_layer5: float = 60.0

# Capas Parallax
@onready var bg_layer1: Parallax2D = %BgLayer1
@onready var bg_layer2: Parallax2D = %BgLayer2
@onready var bg_layer3: Parallax2D = %BgLayer3
@onready var bg_layer4: Parallax2D = %BgLayer4
@onready var bg_layer5: Parallax2D = %BgLayer5

# Botones principales
@onready var play_button: Button = %PlayButton
@onready var load_button: Button = %LoadButton
@onready var controls_button: Button = %ControlsButton
@onready var options_button: Button = %OptionsButton
@onready var credits_button: Button = %CreditsButton
@onready var quit_button: Button = %QuitButton

# Paneles Modales
@onready var controls_modal: Control = %ControlsModal
@onready var options_modal: Control = %OptionsModal
@onready var credits_modal: Control = %CreditsModal
@onready var quit_modal: Control = %QuitModal

# Botones dentro de los modales
@onready var close_controls_button: Button = %CloseControlsButton
@onready var close_options_button: Button = %CloseOptionsButton
@onready var close_credits_button: Button = %CloseCreditsButton
@onready var confirm_quit_button: Button = %ConfirmQuitButton
@onready var cancel_quit_button: Button = %CancelQuitButton

# Configuración (Opciones)
@onready var fullscreen_checkbox: CheckBox = %FullscreenCheckBox
@onready var volume_slider: HSlider = %VolumeSlider
@onready var volume_value_label: Label = %VolumeValueLabel

# Elementos visuales dinámicos
@onready var title_label: Label = %TitleLabel
@onready var cursor_indicator: Label = %CursorIndicator

var _time: float = 0.0
var _title_base_y: float = 0.0
var _cursor_base_x: float = 0.0
var _target_cursor_y: float = 0.0
var _active_modal: Control = null
var _last_focused_button: Button = null
var _main_buttons: Array[Button] = []
var _starting_game: bool = false
var _cursor_tween: Tween
var _slots_menu: SaveSlotsMenu


func _ready() -> void:
	# Aseguramos que el cursor y ratón funcionen correctamente
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Guardar posición base del título para la animación flotante
	if is_instance_valid(title_label):
		_title_base_y = title_label.position.y

	# Lista de botones principales
	_main_buttons = [play_button, load_button, controls_button, options_button, credits_button, quit_button]
	
	# Ocultar botón Salir en la web (los navegadores no admiten quit())
	if OS.has_feature("web") and is_instance_valid(quit_button):
		quit_button.visible = false

	# Conectar eventos de botones principales
	play_button.pressed.connect(_on_play_pressed)
	load_button.pressed.connect(_on_load_pressed)
	controls_button.pressed.connect(_on_controls_pressed)
	options_button.pressed.connect(_on_options_pressed)
	credits_button.pressed.connect(_on_credits_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	# Conectar botones de cierre de modales
	close_controls_button.pressed.connect(_close_current_modal)
	close_options_button.pressed.connect(_close_current_modal)
	close_credits_button.pressed.connect(_close_current_modal)
	confirm_quit_button.pressed.connect(_on_confirm_quit_pressed)
	cancel_quit_button.pressed.connect(_close_current_modal)

	# Configurar eventos de hover y foco para mover el cursor
	for btn in _main_buttons:
		if is_instance_valid(btn):
			btn.mouse_entered.connect(_on_button_hover.bind(btn))
			btn.focus_entered.connect(_on_button_focus.bind(btn))

	# Ocultar todos los modales al inicio
	for modal in [controls_modal, options_modal, credits_modal, quit_modal]:
		if is_instance_valid(modal):
			modal.visible = false

	# Inicializar controles de opciones (Pantalla completa y Volumen)
	_setup_options()

	# Esperar un frame para que los contenedores calculen sus posiciones reales
	await get_tree().process_frame
	if is_instance_valid(play_button):
		play_button.grab_focus()
		_update_cursor_to_button(play_button, true)


func _process(delta: float) -> void:
	_time += delta

	# Animación suave del fondo Parallax
	if bg_layer1:
		bg_layer1.scroll_offset.x = wrapf(bg_layer1.scroll_offset.x - parallax_speed_layer1 * delta, 0.0, 640.0)
	if bg_layer2:
		bg_layer2.scroll_offset.x = wrapf(bg_layer2.scroll_offset.x - parallax_speed_layer2 * delta, 0.0, 640.0)
	if bg_layer3:
		bg_layer3.scroll_offset.x = wrapf(bg_layer3.scroll_offset.x - parallax_speed_layer3 * delta, 0.0, 640.0)
	if bg_layer4:
		bg_layer4.scroll_offset.x = wrapf(bg_layer4.scroll_offset.x - parallax_speed_layer4 * delta, 0.0, 640.0)
	if bg_layer5:
		bg_layer5.scroll_offset.x = wrapf(bg_layer5.scroll_offset.x - parallax_speed_layer5 * delta, 0.0, 640.0)

	# Animación de respiración/flotación en el título
	if is_instance_valid(title_label):
		title_label.position.y = _title_base_y + sin(_time * 2.2) * 2.5

	# Animación de oscilación horizontal del cursor cuando está visible
	if is_instance_valid(cursor_indicator) and cursor_indicator.visible:
		cursor_indicator.global_position.x = _cursor_base_x + sin(_time * 6.5) * 2.0


func _unhandled_input(event: InputEvent) -> void:
	# Soporte para la tecla Escape / botón B del gamepad
	if event.is_action_pressed("ui_cancel"):
		if _active_modal != null:
			_close_current_modal()
			get_viewport().set_input_as_handled()
		elif not _starting_game:
			_open_modal(quit_modal, cancel_quit_button)
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Lógica de Botones Principales
# ---------------------------------------------------------------------------

func _on_play_pressed() -> void:
	if _starting_game:
		return
	_starting_game = true

	# Deshabilitar botones para evitar pulsaciones múltiples
	for btn in _main_buttons:
		if is_instance_valid(btn):
			btn.disabled = true

	# Partida nueva: inventario y misiones desde cero (SaveManager también los reinicia).
	SaveManager.start_new_game(first_level_path)


func _on_load_pressed() -> void:
	if _starting_game or is_instance_valid(_slots_menu):
		return
	if is_instance_valid(cursor_indicator):
		cursor_indicator.visible = false
	_slots_menu = SaveSlotsMenu.open_load(self)
	_slots_menu.closed.connect(_on_slots_menu_closed)


func _on_slots_menu_closed() -> void:
	_slots_menu = null
	if is_instance_valid(load_button):
		load_button.grab_focus()
		_update_cursor_to_button(load_button)


func _on_controls_pressed() -> void:
	_open_modal(controls_modal, close_controls_button)


func _on_options_pressed() -> void:
	_open_modal(options_modal, close_options_button)


func _on_credits_pressed() -> void:
	_open_modal(credits_modal, close_credits_button)


func _on_quit_pressed() -> void:
	_open_modal(quit_modal, cancel_quit_button)


func _on_confirm_quit_pressed() -> void:
	get_tree().quit()


# ---------------------------------------------------------------------------
# Gestión de Modales
# ---------------------------------------------------------------------------

func _open_modal(modal: Control, default_button: Button = null) -> void:
	if modal == null:
		return

	# Si ya hay un modal abierto, cerrarlo primero
	if _active_modal != null and _active_modal != modal:
		_active_modal.visible = false

	# Guardar botón con foco previo para restaurarlo al cerrar
	var current_focus = get_viewport().gui_get_focus_owner()
	if current_focus is Button and current_focus in _main_buttons:
		_last_focused_button = current_focus

	_active_modal = modal
	modal.visible = true
	modal.modulate.a = 0.0

	if is_instance_valid(cursor_indicator):
		cursor_indicator.visible = false

	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(modal, "modulate:a", 1.0, 0.15)

	if is_instance_valid(default_button):
		default_button.grab_focus()


func _close_current_modal() -> void:
	if _active_modal == null:
		return

	var modal_to_close := _active_modal
	_active_modal = null

	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(modal_to_close, "modulate:a", 0.0, 0.12)
	tween.tween_callback(func(): modal_to_close.visible = false)

	# Restaurar el foco en el botón del menú principal
	if is_instance_valid(_last_focused_button):
		_last_focused_button.grab_focus()
		_update_cursor_to_button(_last_focused_button)
	else:
		play_button.grab_focus()
		_update_cursor_to_button(play_button)


# ---------------------------------------------------------------------------
# Cursor y Selección
# ---------------------------------------------------------------------------

func _on_button_hover(btn: Button) -> void:
	if _active_modal == null and not _starting_game and not btn.disabled:
		btn.grab_focus()
		_update_cursor_to_button(btn)


func _on_button_focus(btn: Button) -> void:
	if _active_modal == null and not _starting_game and not btn.disabled:
		_update_cursor_to_button(btn)


func _update_cursor_to_button(btn: Button, immediate: bool = false) -> void:
	if not is_instance_valid(cursor_indicator) or not is_instance_valid(btn):
		return

	cursor_indicator.visible = true
	_cursor_base_x = btn.global_position.x - cursor_indicator.size.x - 4.0
	_target_cursor_y = btn.global_position.y + (btn.size.y - cursor_indicator.size.y) / 2.0

	if immediate:
		cursor_indicator.global_position.x = _cursor_base_x
		cursor_indicator.global_position.y = _target_cursor_y
	else:
		if _cursor_tween and _cursor_tween.is_valid():
			_cursor_tween.kill()
		_cursor_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_cursor_tween.tween_property(cursor_indicator, "global_position:y", _target_cursor_y, 0.12)


# ---------------------------------------------------------------------------
# Opciones (Pantalla Completa y Audio)
# ---------------------------------------------------------------------------

func _setup_options() -> void:
	# Pantalla completa
	if is_instance_valid(fullscreen_checkbox):
		var is_fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		fullscreen_checkbox.set_pressed_no_signal(is_fullscreen)
		fullscreen_checkbox.toggled.connect(_on_fullscreen_toggled)

	# Control de volumen
	if is_instance_valid(volume_slider):
		var bus_idx := AudioServer.get_bus_index("Master")
		var initial_volume: float = 1.0
		if bus_idx >= 0:
			if AudioServer.is_bus_mute(bus_idx):
				initial_volume = 0.0
			else:
				initial_volume = db_to_linear(AudioServer.get_bus_volume_db(bus_idx))
		volume_slider.set_value_no_signal(initial_volume)
		_update_volume_label(initial_volume)
		volume_slider.value_changed.connect(_on_volume_changed)


func _on_fullscreen_toggled(toggled_on: bool) -> void:
	if toggled_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _on_volume_changed(value: float) -> void:
	var bus_idx := AudioServer.get_bus_index("Master")
	if bus_idx >= 0:
		if value <= 0.01:
			AudioServer.set_bus_mute(bus_idx, true)
		else:
			AudioServer.set_bus_mute(bus_idx, false)
			AudioServer.set_bus_volume_db(bus_idx, linear_to_db(value))
	_update_volume_label(value)


func _update_volume_label(value: float) -> void:
	if is_instance_valid(volume_value_label):
		volume_value_label.text = "%d%%" % int(round(value * 100.0))
