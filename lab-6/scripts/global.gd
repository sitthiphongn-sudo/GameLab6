extends Node
## Autoload "Global" : input actions, file paths, shared UI theme, session data.

## ตัวละครที่ได้จาก Mixamo (วางไฟล์ไว้ที่ใดที่หนึ่งด้านล่าง ระบบจะหาเอง)
const CHARACTER_PATHS: Array[String] = [
	"res://characters/hero.fbx",
	"res://characters/hero.glb",
	"res://characters/hero.gltf",
	"res://characters/hero.tscn",
]

## Animation libraries จาก Godot4-OpenAnimationLibraries
const LIBRARY_FILES: Dictionary = {
	"Melee": "res://animations/MeleeLib.res",
	"Shooter": "res://animations/ShooterLib.res",
}

const GAME_TITLE := "TEMPLE QUEST"
const CREDIT_ID := "673380350-7"
const CREDIT_NAME := "สิทธิพงษ์ นครขวาง"
const CREDIT_GROUP := "AI 1"

const GOLD := Color(0.93, 0.72, 0.22)
const TEMPLE_RED := Color(0.62, 0.13, 0.09)

var best_time: float = -1.0
var theme: Theme

# ---- audio
const SFX_NAMES: Array[String] = ["coin", "jump", "swoosh", "dodge", "land", "step", "smash", "checkpoint", "splash", "win", "click"]
var music: AudioStreamPlayer
var _sfx: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_i: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_key("move_forward", [KEY_W, KEY_UP])
	_key("move_back", [KEY_S, KEY_DOWN])
	_key("move_left", [KEY_A, KEY_LEFT])
	_key("move_right", [KEY_D, KEY_RIGHT])
	_key("jump", [KEY_SPACE])
	_key("sprint", [KEY_SHIFT])
	_key("attack", [KEY_J, KEY_F])
	_mouse("attack", MOUSE_BUTTON_LEFT)
	_key("dodge", [KEY_Q, KEY_C])
	_key("cheer", [KEY_E])
	_key("pause", [KEY_ESCAPE, KEY_P])
	_key("restart", [KEY_R])
	_key("mute", [KEY_M])
	_pad_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_pad_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_pad_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_pad_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_pad_button("jump", JOY_BUTTON_A)
	_pad_button("attack", JOY_BUTTON_X)
	_pad_button("dodge", JOY_BUTTON_B)
	_pad_button("sprint", JOY_BUTTON_LEFT_SHOULDER)
	_pad_button("pause", JOY_BUTTON_START)
	theme = _make_theme()
	_setup_audio()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mute"):
		AudioServer.set_bus_mute(0, not AudioServer.is_bus_mute(0))


# ------------------------------------------------------------------ audio
func _setup_audio() -> void:
	for n in SFX_NAMES:
		var p := "res://assets/audio/%s.wav" % n
		if ResourceLoader.exists(p):
			_sfx[n] = load(p)
	for i in 12:
		var a := AudioStreamPlayer.new()
		a.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(a)
		_pool.append(a)
	music = AudioStreamPlayer.new()
	music.process_mode = Node.PROCESS_MODE_ALWAYS
	music.volume_db = -10.0
	add_child(music)
	if ResourceLoader.exists("res://assets/audio/music.wav"):
		music.stream = load("res://assets/audio/music.wav")
		music.finished.connect(music.play)   # loop


## Play a sound effect (slight random pitch so repeats don't sound robotic).
func sfx(sound: String, volume_db: float = 0.0, pitch_var: float = 0.06) -> void:
	if not _sfx.has(sound):
		return
	var a := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	a.stream = _sfx[sound]
	a.volume_db = volume_db
	a.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	a.play()


func play_music(volume_db: float = -10.0) -> void:
	if music.stream == null:
		return
	create_tween().tween_property(music, "volume_db", volume_db, 0.6)
	if not music.playing:
		music.play()


func is_web() -> bool:
	return OS.has_feature("web")


func format_time(t: float) -> String:
	var m: int = int(t / 60.0)
	var s: float = t - m * 60.0
	return "%02d:%04.1f" % [m, s]


# ------------------------------------------------------------------ input helpers
func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)


func _key(action: String, keys: Array) -> void:
	_ensure(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)


func _mouse(action: String, button: MouseButton) -> void:
	_ensure(action)
	var e := InputEventMouseButton.new()
	e.button_index = button
	InputMap.action_add_event(action, e)


func _pad_axis(action: String, axis: JoyAxis, dir: float) -> void:
	_ensure(action)
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = dir
	InputMap.action_add_event(action, e)


func _pad_button(action: String, button: JoyButton) -> void:
	_ensure(action)
	var e := InputEventJoypadButton.new()
	e.button_index = button
	InputMap.action_add_event(action, e)


# ------------------------------------------------------------------ theme
func _flat(bg: Color, border: Color, radius: int = 10, border_w: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _make_theme() -> Theme:
	var t := Theme.new()
	# Thai + Latin font (Loma, TLWG) so Thai text also renders on the Web build
	var f: Font = load("res://assets/fonts/Loma-Bold.otf")
	if f:
		t.default_font = f
	t.default_font_size = 20
	t.set_stylebox("normal", "Button", _flat(Color(0.45, 0.1, 0.07, 0.92), GOLD))
	t.set_stylebox("hover", "Button", _flat(Color(0.62, 0.16, 0.1, 0.95), Color(1, 0.85, 0.4)))
	t.set_stylebox("pressed", "Button", _flat(Color(0.3, 0.06, 0.04, 0.95), GOLD))
	t.set_stylebox("focus", "Button", _flat(Color(0, 0, 0, 0), Color(1, 0.9, 0.5), 10, 2))
	t.set_color("font_color", "Button", Color(1, 0.94, 0.8))
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_stylebox("panel", "PanelContainer", _flat(Color(0.08, 0.05, 0.04, 0.82), Color(GOLD, 0.8), 14, 2))
	t.set_stylebox("panel", "Panel", _flat(Color(0.08, 0.05, 0.04, 0.82), Color(GOLD, 0.8), 14, 2))
	t.set_color("font_color", "Label", Color(1, 0.96, 0.88))
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "Label", 4)
	t.set_font_size("font_size", "ItemList", 17)
	t.set_font_size("font_size", "LineEdit", 18)
	t.set_font_size("font_size", "CheckBox", 18)
	return t
