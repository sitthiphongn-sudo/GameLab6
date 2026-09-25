extends Node3D
## Main menu with the character posing on a small temple stage.

var rig: CharacterRig
var camera: Camera3D
var _t: float = 0.0
var _pose_t: float = 0.0
var _poses: Array[String] = ["idle", "cheer", "idle", "attack", "idle", "walk"]
var _pose_i: int = 0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	WorldKit.environment(self, Color(0.3, 0.55, 0.9), Color(0.98, 0.8, 0.6), 1.2, Vector3(-35, 40, 0))
	WorldKit.solid_cyl(self, 2.2, 0.3, Vector3(0, -0.15, 0), WorldKit.mat(Color(0.93, 0.9, 0.84)))
	WorldKit.add_mesh(self, WorldKit.cyl_mesh(2.3, 2.3, 0.06, 48), Vector3(0, -0.01, 0), WorldKit.gold())
	var ground := PlaneMesh.new()
	ground.size = Vector2(120, 120)
	WorldKit.add_mesh(self, ground, Vector3(0, -0.3, 0), WorldKit.mat(Color(0.33, 0.6, 0.28)))
	WorldKit.chedi(self, Vector3(-5.5, -0.3, -8), 1.3)
	WorldKit.sala(self, Vector3(6, -0.3, -9), -0.4, 1.3)
	for p in [Vector3(-9, -0.3, -3), Vector3(9, -0.3, -2), Vector3(-3, -0.3, -12), Vector3(3.5, -0.3, -14)]:
		WorldKit.palm(self, p, randf_range(4.0, 6.0))

	rig = CharacterRig.new()
	rig.position = Vector3(1.3, 0, 0)
	rig.rotation.y = -0.35
	add_child(rig)
	camera = Camera3D.new()
	camera.fov = 50.0
	add_child(camera)
	camera.position = Vector3(0.2, 1.35, 4.6)
	camera.look_at(Vector3(0.2, 1.0, 0))
	camera.current = true
	_build_ui()
	Global.play_music(-10.0)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Global.theme
	layer.add_child(root)

	var vb := VBoxContainer.new()
	vb.anchor_top = 0.5
	vb.anchor_bottom = 0.5
	vb.offset_left = 70
	vb.offset_right = 560
	vb.offset_top = -230
	vb.offset_bottom = 250
	vb.add_theme_constant_override("separation", 14)
	root.add_child(vb)

	var title := Label.new()
	title.text = Global.GAME_TITLE
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Global.GOLD)
	title.add_theme_constant_override("outline_size", 10)
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "Lab 6"
	sub.add_theme_font_size_override("font_size", 30)
	vb.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	vb.add_child(spacer)
	_button(vb, "Play Game", func(): get_tree().change_scene_to_file("res://scenes/game.tscn"))
	if not Global.is_web():
		_button(vb, "Quit", func(): get_tree().quit())

	# credit
	var credit := PanelContainer.new()
	credit.anchor_left = 0.0
	credit.anchor_top = 1.0
	credit.anchor_bottom = 1.0
	credit.offset_left = 20
	credit.offset_top = -130
	credit.offset_bottom = -20
	root.add_child(credit)
	var cl := Label.new()
	cl.text = "รหัส: %s\nชื่อ-สกุล: %s\nกลุ่มเรียน: %s" % [Global.CREDIT_ID, Global.CREDIT_NAME, Global.CREDIT_GROUP]
	cl.add_theme_font_size_override("font_size", 20)
	credit.add_child(cl)
	print("[Character] ", rig.status_text)


func _button(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 54)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(func(): Global.sfx("click", -4.0, 0.0))
	b.pressed.connect(cb)
	parent.add_child(b)
	if parent.get_child_count() == 4:
		b.grab_focus.call_deferred()


func _process(delta: float) -> void:
	_t += delta
	_pose_t -= delta
	if _pose_t <= 0.0:
		var p := _poses[_pose_i % _poses.size()]
		_pose_i += 1
		var length := rig.play_state(p, 0.3, 1.0, true)
		_pose_t = clampf(length if p != "idle" else 3.0, 1.5, 4.0)
		if p == "walk":
			_pose_t = 2.5
	camera.position.x = 0.2 + sin(_t * 0.25) * 0.25
