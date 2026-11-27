class_name DeathScreen
extends CanvasLayer
## Pantalla de muerte ("Game Over"). Aparece cuando la vida del jugador llega a 0, con dos opciones:
##   - Reintentar: reaparece en el último checkpoint con la vida y la energía llenas.
##   - Volver al menú: regresa al menú principal.
##
## Uso: instancia `death_screen.tscn` como hijo del nodo Player (igual que HealthLayer).
## Mientras exista una pantalla de muerte, el SceneManager ya no reaparece al jugador solo:
## espera a que elijas.
##
## Puedes poner tus propias imágenes (fondo, título, cuadro) en el grupo "Texturas".

## Jugador al que pertenece. Si lo dejas vacío usa el padre.
@export var player: Player
@export var title_text: String = "Has muerto"
@export var retry_text: String = "Reintentar"
@export var menu_text: String = "Volver al menú"
## Escena a la que lleva "Volver al menú".
@export_file("*.tscn") var menu_scene_path: String = "res://UI/MainMenu/main_menu.tscn"
## Al volver al menú, el inventario se vacía (como una partida nueva).
@export var reset_inventory_on_exit: bool = true
## Segundos que se espera tras morir (para que se vea la animación) antes de mostrar la pantalla.
@export var show_delay: float = 1.0
## Segundos que tarda en aparecer la pantalla.
@export var fade_in_time: float = 0.6

@export_group("Texturas")
## Imagen a pantalla completa detrás de todo (se ajusta cubriendo la pantalla). Vacío = solo el color.
@export var background_texture: Texture2D
## Imagen del título. Si la pones, reemplaza al texto `title_text`.
@export var title_texture: Texture2D
## Imagen del cuadro que contiene el título y los botones (9-patch). Vacío = sin cuadro.
@export var panel_texture: Texture2D
## Píxeles de la imagen (desde cada borde) que NO se estiran: el marco y las esquinas.
@export var panel_texture_margin: int = 8
## Espacio (px) entre el borde del cuadro y el contenido.
@export var panel_padding: int = 16

@export_group("Diseño")
## Color que cubre la pantalla (con transparencia, sobre el juego o sobre `background_texture`).
@export var overlay_color: Color = Color(0.25, 0.0, 0.03, 0.8)
@export var title_color: Color = Color(0.95, 0.25, 0.3)
@export var title_font_size: int = 24
@export var body_font_size: int = 12
@export var button_width: int = 160

var _root: Control
var _retry_button: Button
var _menu_button: Button
var _fade_tween: Tween


func _ready() -> void:
	layer = 30 # por encima del HUD (10) y del inventario (20), y por debajo del fundido a negro (100)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if player == null:
		player = get_parent() as Player

	_build()
	_root.visible = false

	# Avisa al SceneManager de que esta pantalla decide qué pasa al morir.
	SceneManager.death_screens += 1
	SceneManager.player_respawned.connect(_on_player_respawned)
	if player:
		player.died.connect(_on_player_died)


func _exit_tree() -> void:
	SceneManager.death_screens = maxi(SceneManager.death_screens - 1, 0)


func _on_player_died() -> void:
	await get_tree().create_timer(show_delay).timeout
	if not is_inside_tree() or player == null or not player.is_dead:
		return
	_show()


func _show() -> void:
	_retry_button.disabled = false
	_menu_button.disabled = false
	_root.visible = true
	_root.modulate.a = 0.0
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_root, "modulate:a", 1.0, fade_in_time)
	_retry_button.grab_focus()


## El SceneManager reaparece al jugador cuando la pantalla ya está en negro: ahí se oculta.
func _on_player_respawned(_respawned: Player) -> void:
	_root.visible = false


func _on_retry_pressed() -> void:
	_retry_button.disabled = true
	_menu_button.disabled = true
	SceneManager.respawn_player(true)


func _on_menu_pressed() -> void:
	_retry_button.disabled = true
	_menu_button.disabled = true
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

	if background_texture:
		var background := TextureRect.new()
		background.texture = background_texture
		background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		background.set_anchors_preset(Control.PRESET_FULL_RECT)
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(background)

	var overlay := ColorRect.new()
	overlay.color = overlay_color
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	box.add_child(_make_title())

	_retry_button = _make_button(retry_text)
	_retry_button.pressed.connect(_on_retry_pressed)
	box.add_child(_retry_button)

	_menu_button = _make_button(menu_text)
	_menu_button.pressed.connect(_on_menu_pressed)
	box.add_child(_menu_button)


func _make_title() -> Control:
	if title_texture:
		var image := TextureRect.new()
		image.texture = title_texture
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		image.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		image.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		return image
	var label := Label.new()
	label.text = title_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", title_font_size)
	label.add_theme_color_override("font_color", title_color)
	return label


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(button_width, 0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", body_font_size)
	return button


func _make_panel_style() -> StyleBox:
	if panel_texture:
		var textured := StyleBoxTexture.new()
		textured.texture = panel_texture
		textured.set_texture_margin_all(panel_texture_margin)
		textured.set_content_margin_all(panel_padding)
		return textured
	var empty := StyleBoxEmpty.new()
	empty.set_content_margin_all(panel_padding)
	return empty
