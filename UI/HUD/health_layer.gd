class_name HealthLayer
extends CanvasLayer
## Layer de vida: muestra un corazón por punto de vida del jugador y se actualiza sola.
##
## Uso: instancia `health_layer.tscn` como hijo del nodo Player (o ponla en un nivel).
## Se conecta a la señal `health_changed(current, maximum)` del Player, así que no hace falta
## llamar a nada: cuando `take_damage()`, `heal()` o `respawn_at(..., true)` cambian la vida,
## los corazones se actualizan con una pequeña animación.
##
## Debajo de los corazones dibuja la barra de energía (turbo y gancho), conectada a `energy_changed`.
## Debajo de la barra muestra la munición seleccionada: su imagen y cuántas flechas quedan.
## Además, tiñe de rojo los bordes de la pantalla: cuanta menos vida, más rojo y más hacia el centro.
##
## Si no asignas texturas, dibuja unos corazones pixel-art por código.
## Para usar los tuyos, arrastra tus imágenes a `full_texture` y `empty_texture`.

## Jugador a vigilar. Si lo dejas vacío usa el padre (si es un Player) o el nodo del grupo "player".
@export var player: Player
@export_group("Texturas")
## Corazón lleno. Vacío = corazón pixel-art generado por código.
@export var full_texture: Texture2D
## Corazón vacío (vida perdida). Vacío = corazón oscuro generado por código.
@export var empty_texture: Texture2D
@export_group("Diseño")
## Separación (px) entre la esquina superior izquierda de la pantalla y los corazones.
@export var margin: Vector2i = Vector2i(8, 8)
## Separación (px) entre corazones.
@export var spacing: int = 2
## Escala máxima del "latido" al ganar o perder un corazón.
@export var pop_scale: float = 1.5
## Duración (s) de la animación de cada corazón.
@export var pop_time: float = 0.25

@export_group("Barra de energía")
## Muestra la barra de energía debajo de los corazones.
@export var energy_bar_enabled: bool = true
## Tamaño (px) del interior de la barra.
@export var energy_bar_size: Vector2i = Vector2i(64, 6)
@export var energy_color: Color = Color(0.25, 0.8, 1.0)
## Color cuando queda poca energía.
@export var energy_low_color: Color = Color(1.0, 0.65, 0.2)
## Fracción (0-1) por debajo de la cual se usa energy_low_color.
@export_range(0.0, 1.0) var energy_low_fraction: float = 0.25
## Color mientras estás agotado (energía a 0 y sin recuperar lo suficiente).
@export var energy_exhausted_color: Color = Color(0.85, 0.15, 0.2)
@export var energy_back_color: Color = Color(0.12, 0.14, 0.22)
@export var energy_frame_color: Color = Color(0.03, 0.04, 0.08)

@export_group("Munición")
## Muestra la imagen de la munición seleccionada y su cantidad debajo de la barra de energía.
@export var ammo_hud_enabled: bool = true
## Tamaño (px) de la imagen de la munición.
@export var ammo_icon_size: Vector2i = Vector2i(16, 16)
@export var ammo_font_size: int = 12
@export var ammo_color: Color = Color.WHITE
## Color del número cuando no quedan flechas de ese tipo.
@export var ammo_empty_color: Color = Color(0.9, 0.2, 0.2)

@export_group("Viñeta de daño")
## Activa/desactiva el rojo en los bordes de la pantalla.
@export var vignette_enabled: bool = true
@export var vignette_color: Color = Color(0.85, 0.02, 0.08)
## Opacidad máxima del rojo (cuando la vida llega a 0).
@export_range(0.0, 1.0) var max_intensity: float = 0.8
## Qué tan adentro empieza el rojo con poco daño (1 = solo en las esquinas)...
@export_range(0.0, 1.5) var inner_radius_full: float = 0.95
## ...y con la vida casi a 0 (más bajo = el rojo llega más hacia el centro).
@export_range(0.0, 1.5) var inner_radius_low: float = 0.3
## Segundos que tarda el rojo en subir o bajar al cambiar la vida.
@export var vignette_fade_time: float = 0.4
## Hace "latir" el rojo cuando solo queda 1 corazón.
@export var pulse_at_last_heart: bool = true

const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.85, 0.02, 0.08, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float inner_radius : hint_range(0.0, 1.5) = 0.9;
void fragment() {
	float d = length(UV - vec2(0.5)) * 1.41421356;
	float edge = smoothstep(inner_radius, 1.0, d);
	COLOR = vec4(tint.rgb, edge * intensity);
}
"""

const HEART_MAP: Array[String] = [
	".OOO...OOO.",
	"OHHROOORRRO",
	"OHRRRRRRRRO",
	"ORRRRRRRRRO",
	"ORRRRRRRRRO",
	".ORRRRRRRO.",
	"..ORRRRRO..",
	"...ORRRO...",
	"....ORO....",
	".....O.....",
]
const FULL_COLORS := {"O": Color("3b0a1a"), "R": Color("e6263a"), "H": Color("ff9aa8")}
const EMPTY_COLORS := {"O": Color("3b0a1a"), "R": Color("4a2a33"), "H": Color("4a2a33")}

var _container: HBoxContainer
var _hearts: Array[TextureRect] = []
var _current: int = -1
var _max: int = 0
var _start_frame: int = 0
var _stack: VBoxContainer
var _energy_fill: ColorRect
var _ammo_icon: TextureRect
var _ammo_label: Label
var _vignette: ColorRect
var _vignette_material: ShaderMaterial
var _vignette_tween: Tween
var _missing: float = 0.0 # fracción de vida perdida (0 = llena, 1 = muerto)
var _pulsing: bool = false


func _ready() -> void:
	# Que las animaciones sigan aunque el Player se desactive durante un fundido/respawn.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start_frame = Engine.get_process_frames()
	if full_texture == null:
		full_texture = _make_heart_texture(FULL_COLORS)
	if empty_texture == null:
		empty_texture = _make_heart_texture(EMPTY_COLORS)
	_build_vignette()
	_build_container()
	_build_energy_bar()
	_build_ammo_hud()
	set_process(false)

	if player == null:
		player = get_parent() as Player
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Player
	if player:
		_bind_player(player)
	else:
		# El jugador aún no existe (lo crea el SceneManager al cargar el nivel).
		SceneManager.level_changed.connect(_on_level_changed, CONNECT_ONE_SHOT)


func _on_level_changed(_level: Level) -> void:
	if SceneManager.player:
		_bind_player(SceneManager.player)


func _bind_player(target: Player) -> void:
	player = target
	if not player.health_changed.is_connected(_on_health_changed):
		player.health_changed.connect(_on_health_changed)
	if not player.energy_changed.is_connected(_on_energy_changed):
		player.energy_changed.connect(_on_energy_changed)
	# Si el Player ya terminó su _ready, sincroniza ya. Si no (somos su hijo), él emitirá
	# `health_changed` al terminar de prepararse y no hace falta leerlo aquí.
	if player.is_node_ready():
		_on_health_changed(player.health, player.max_health)
		_on_energy_changed(player.energy, player.max_energy)


func _on_health_changed(current: int, maximum: int) -> void:
	if maximum != _max:
		_rebuild(maximum)

	var previous := _current
	_current = current
	# Los cambios del mismo frame de arranque (entrar a un nivel con vida guardada) no se animan.
	var animate := previous >= 0 and Engine.get_process_frames() > _start_frame

	_update_vignette(current, maximum, animate)

	for i in _hearts.size():
		var heart := _hearts[i]
		heart.texture = full_texture if i < current else empty_texture
		if not animate:
			continue
		if i >= current and i < previous:
			_pop(heart, false, 0.0) # corazón perdido
		elif i >= previous and i < current:
			_pop(heart, true, float(i - previous) * 0.06) # corazón recuperado


# ---------------------------------------------------------------------------
# Construcción
# ---------------------------------------------------------------------------

func _build_container() -> void:
	var box := MarginContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	box.add_theme_constant_override("margin_left", margin.x)
	box.add_theme_constant_override("margin_top", margin.y)
	add_child(box)

	# Columna: corazones arriba, barra de energía debajo.
	_stack = VBoxContainer.new()
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.add_theme_constant_override("separation", 3)
	box.add_child(_stack)

	_container = HBoxContainer.new()
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_theme_constant_override("separation", spacing)
	_stack.add_child(_container)


func _rebuild(maximum: int) -> void:
	for heart in _hearts:
		heart.queue_free()
	_hearts.clear()
	_max = maximum
	_current = -1 # al cambiar el máximo no se anima

	for i in maximum:
		var heart := TextureRect.new()
		heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
		heart.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		heart.texture = empty_texture
		_container.add_child(heart)
		_hearts.append(heart)


# ---------------------------------------------------------------------------
# Barra de energía
# ---------------------------------------------------------------------------

func _build_energy_bar() -> void:
	if not energy_bar_enabled:
		return
	var frame := ColorRect.new()
	frame.color = energy_frame_color
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.custom_minimum_size = Vector2(energy_bar_size) + Vector2(2, 2) # 1 px de borde
	frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_stack.add_child(frame)

	var back := ColorRect.new()
	back.color = energy_back_color
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.position = Vector2(1, 1)
	back.size = Vector2(energy_bar_size)
	frame.add_child(back)

	_energy_fill = ColorRect.new()
	_energy_fill.color = energy_color
	_energy_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_energy_fill.position = Vector2(1, 1)
	_energy_fill.size = Vector2(energy_bar_size)
	frame.add_child(_energy_fill)


func _on_energy_changed(current: float, maximum: float) -> void:
	if _energy_fill == null:
		return
	var ratio := clampf(current / maxf(maximum, 0.001), 0.0, 1.0)
	_energy_fill.size.x = roundf(float(energy_bar_size.x) * ratio)

	if player and player.energy_exhausted:
		_energy_fill.color = energy_exhausted_color
	elif ratio <= energy_low_fraction:
		_energy_fill.color = energy_low_color
	else:
		_energy_fill.color = energy_color


# ---------------------------------------------------------------------------
# Munición seleccionada
# ---------------------------------------------------------------------------

func _build_ammo_hud() -> void:
	if not ammo_hud_enabled:
		return
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	_stack.add_child(row)

	_ammo_icon = TextureRect.new()
	_ammo_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ammo_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ammo_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ammo_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ammo_icon.custom_minimum_size = Vector2(ammo_icon_size)
	row.add_child(_ammo_icon)

	_ammo_label = Label.new()
	_ammo_label.add_theme_font_size_override("font_size", ammo_font_size)
	_ammo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_ammo_label)

	# La munición vive en el autoload Inventory: se actualiza sola al disparar, recoger o cambiar.
	Inventory.ammo_changed.connect(_refresh_ammo.unbind(2))
	Inventory.ammo_selected.connect(_refresh_ammo.unbind(1))
	Inventory.ammo_types_changed.connect(_refresh_ammo)
	Inventory.umbrella_toggled.connect(_refresh_ammo.unbind(1))
	_refresh_ammo()


func _refresh_ammo() -> void:
	if _ammo_icon == null:
		return
	var slot := Inventory.selected_slot
	var count := Inventory.get_ammo(slot)
	_ammo_icon.texture = Inventory.get_slot_icon(slot)
	_ammo_icon.modulate = Inventory.get_slot_tint(slot)
	_ammo_label.text = "x%d" % count
	_ammo_label.add_theme_color_override("font_color", ammo_color if count > 0 else ammo_empty_color)
	# Con el paraguas equipado no se dispara: la munición se ve apagada y lo avisa.
	if Inventory.umbrella_equipped:
		_ammo_icon.modulate.a = 0.35
		_ammo_label.text = "Paraguas"
		_ammo_label.add_theme_color_override("font_color", ammo_color.darkened(0.2))


# ---------------------------------------------------------------------------
# Viñeta roja en los bordes
# ---------------------------------------------------------------------------

func _build_vignette() -> void:
	if not vignette_enabled:
		return
	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER
	_vignette_material = ShaderMaterial.new()
	_vignette_material.shader = shader
	_vignette_material.set_shader_parameter("tint", vignette_color)

	_vignette = ColorRect.new()
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.material = _vignette_material
	_vignette.visible = false
	add_child(_vignette)


func _update_vignette(current: int, maximum: int, animate: bool) -> void:
	if _vignette == null:
		return
	var target := 0.0
	if maximum > 0:
		target = 1.0 - clampf(float(current) / float(maximum), 0.0, 1.0)
	_pulsing = pulse_at_last_heart and current == 1
	set_process(_pulsing)

	if _vignette_tween:
		_vignette_tween.kill()
	if animate:
		_vignette_tween = create_tween()
		_vignette_tween.tween_method(_apply_vignette, _missing, target, vignette_fade_time)
	else:
		_apply_vignette(target)


func _apply_vignette(missing: float) -> void:
	_missing = missing
	var pulse := 1.0
	if _pulsing:
		pulse += 0.2 * sin(Time.get_ticks_msec() * 0.008)
	_vignette_material.set_shader_parameter("intensity", clampf(missing * max_intensity * pulse, 0.0, 1.0))
	_vignette_material.set_shader_parameter("inner_radius", lerpf(inner_radius_full, inner_radius_low, missing))
	_vignette.visible = missing > 0.001


func _process(_delta: float) -> void:
	# Solo corre mientras queda 1 corazón, para que el rojo lata.
	if _vignette:
		_apply_vignette(_missing)


# ---------------------------------------------------------------------------
# Animación
# ---------------------------------------------------------------------------

func _pop(heart: TextureRect, gained: bool, delay: float) -> void:
	if heart.has_meta(&"tween"):
		var old := heart.get_meta(&"tween") as Tween
		if old:
			old.kill()

	heart.pivot_offset = heart.size / 2.0
	heart.scale = Vector2.ONE * pop_scale
	# Destello: blanco al perder, un poco más brillante al recuperar.
	heart.modulate = Color(3.0, 3.0, 3.0) if not gained else Color(1.6, 1.6, 1.6)

	var tween := create_tween().set_parallel(true)
	heart.set_meta(&"tween", tween)
	tween.tween_property(heart, "scale", Vector2.ONE, pop_time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)
	tween.tween_property(heart, "modulate", Color.WHITE, pop_time).set_delay(delay)


# ---------------------------------------------------------------------------
# Corazón por defecto (pixel-art generado por código)
# ---------------------------------------------------------------------------

static func _make_heart_texture(colors: Dictionary) -> ImageTexture:
	var height := HEART_MAP.size()
	var width := HEART_MAP[0].length()
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			var key := HEART_MAP[y][x]
			if colors.has(key):
				image.set_pixel(x, y, colors[key])
	return ImageTexture.create_from_image(image)
