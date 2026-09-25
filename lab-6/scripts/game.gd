extends Node3D
## "Temple Quest" - small 3D platformer level (Thai temple / tropical theme)
## Collect coins, smash clay pots with attacks, reach the golden chedi.

const START := Vector3(0, 0.2, 5.0)

var player: Player
var coins: Array[Node3D] = []
var pots: Array[Node3D] = []
var movers: Array[Dictionary] = []
var coin_total: int = 0
var coin_count: int = 0
var pot_total: int = 0
var pot_count: int = 0
var time: float = 0.0
var running: bool = true
var finished: bool = false
var _t: float = 0.0
var _mouse_was_captured: bool = false

# UI
var hud: CanvasLayer
var lbl_coins: Label
var lbl_pots: Label
var lbl_time: Label
var lbl_msg: Label
var lbl_hint: Label
var lbl_click: Label
var pause_panel: Control
var win_panel: Control
var win_text: Label
var fade: ColorRect


func _ready() -> void:
	randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS   # so Esc can un-pause; gameplay nodes stay pausable
	WorldKit.environment(self, Color(0.28, 0.52, 0.86), Color(0.92, 0.82, 0.66))
	_build_level()
	_spawn_player()
	_build_hud()
	Global.play_music(-12.0)
	_show_message("Reach the golden chedi!  Collect coins and smash pots", 4.0)


# =================================================================== level
func _build_level() -> void:
	var level := Node3D.new()
	level.name = "Level"
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(level)

	# water
	var water_mat := WorldKit.mat(Color(0.12, 0.45, 0.62, 0.9), 0.15, 0.1)
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	WorldKit.add_mesh(level, plane, Vector3(0, -4.0, -25), water_mat)
	# far hills
	for i in 10:
		var a := TAU * i / 10.0
		WorldKit.add_mesh(level, WorldKit.sphere_mesh(18, 16), Vector3(cos(a) * 110, -10, sin(a) * 110 - 25),
			WorldKit.mat(Color(0.2, 0.42, 0.25)), Vector3.ZERO, Vector3(1.4, 0.8, 1))

	# start island (top y = 0)
	WorldKit.solid_box(level, Vector3(18, 4, 16), Vector3(0, -2, 0), WorldKit.mat(Color(0.55, 0.42, 0.3)))
	WorldKit.add_mesh(level, WorldKit.box_mesh(Vector3(18.1, 0.2, 16.1)), Vector3(0, -0.05, 0), WorldKit.mat(Color(0.33, 0.62, 0.27)))
	WorldKit.sala(level, Vector3(-4.5, 0, -1.5), 0.3)
	for p in [Vector3(-7.5, 0, 6.5), Vector3(7.3, 0, 6.0), Vector3(7.5, 0, -6.5), Vector3(-7.8, 0, -6.8), Vector3(6.0, 0, 1.0)]:
		WorldKit.palm(level, p, randf_range(3.5, 5.0))
	for p in [Vector3(-8, 0, 2), Vector3(3.5, 0, 7), Vector3(8, 0, -3)]:
		WorldKit.bush(level, p)
	WorldKit.lantern(level, Vector3(-1.4, 0, -7.2))
	WorldKit.lantern(level, Vector3(1.4, 0, -7.2))

	# path of platforms: [center xz, top, size, move]
	var path := [
		[Vector2(0, -11), 1.0, Vector3(3, 1, 3), null],
		[Vector2(3, -15), 2.0, Vector3(3, 1, 3), null],
		[Vector2(0, -19.5), 3.0, Vector3(2.5, 1, 2.5), null],
		[Vector2(0, -24), 3.0, Vector3(3, 0.6, 3), Vector3(3.5, 0, 0)],
		[Vector2(0, -29), 4.0, Vector3(3.5, 1, 3.5), null],
		[Vector2(-4, -32.5), 5.0, Vector3(3, 1, 3), null],
		[Vector2(-4, -37), 5.0, Vector3(3, 0.6, 3), Vector3(0, 1.5, 0)],
		[Vector2(0, -41), 6.5, Vector3(3, 1, 3), null],
		[Vector2(4, -45), 7.0, Vector3(3, 1, 3), null],
		[Vector2(2, -50.5), 7.0, Vector3(2, 0.5, 6), null],
	]
	var i := 0
	for entry in path:
		var moving: bool = entry[3] != null
		var body := WorldKit.platform(level, entry[0], entry[1], entry[2], moving)
		if moving:
			movers.append({"node": body, "base": body.position, "offset": entry[3], "speed": 0.9 + i * 0.05})
		# a coin above every platform (moves with moving platforms)
		_add_coin(body, Vector3(0, entry[2].y * 0.5 + 1.1, 0))
		i += 1

	# goal island (top y = 7)
	WorldKit.solid_box(level, Vector3(12, 3, 12), Vector3(0, 5.5, -60), WorldKit.mat(Color(0.55, 0.42, 0.3)))
	WorldKit.add_mesh(level, WorldKit.box_mesh(Vector3(12.1, 0.2, 12.1)), Vector3(0, 6.95, -60), WorldKit.mat(Color(0.33, 0.62, 0.27)))
	WorldKit.chedi(level, Vector3(0, 7, -63))
	for p in [Vector3(-5, 7, -55.5), Vector3(5, 7, -64.5), Vector3(-5, 7, -65)]:
		WorldKit.palm(level, p, 4.0)
	WorldKit.lantern(level, Vector3(-2.5, 7, -56))
	WorldKit.lantern(level, Vector3(2.5, 7, -56))

	# extra coins on the start island
	_add_coin(level, Vector3(-3, 1.1, 4))
	_add_coin(level, Vector3(3.5, 1.1, 2.5))

	# clay pots
	for p in [Vector3(2, 0, 4.2), Vector3(-2.2, 0, 2.5), Vector3(4.5, 0, -3), Vector3(0.9, 4, -29.8), Vector3(-3, 7, -58.5), Vector3(3, 7, -58.5)]:
		_add_pot(level, p)

	# checkpoint on platform 5
	_add_checkpoint(level, Vector3(0.9, 4.0, -28.3))

	# goal trigger in front of the chedi
	var goal := Area3D.new()
	goal.collision_layer = 0
	goal.collision_mask = 2
	goal.position = Vector3(0, 8, -59.5)
	var gs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 3, 2.5)
	gs.shape = box
	goal.add_child(gs)
	level.add_child(goal)
	goal.body_entered.connect(_on_goal)
	var glow := WorldKit.add_mesh(level, WorldKit.cyl_mesh(1.6, 1.6, 0.05, 32), Vector3(0, 7.03, -59.5),
		WorldKit.mat(Color(1.0, 0.85, 0.3, 0.55), 0.3, 0.0, 1.2))
	glow.name = "GoalGlow"


func _add_coin(parent: Node, pos: Vector3) -> void:
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	area.position = pos
	parent.add_child(area)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.55
	cs.shape = sh
	area.add_child(cs)
	var visual := WorldKit.add_mesh(area, WorldKit.cyl_mesh(0.32, 0.32, 0.07, 24), Vector3.ZERO,
		WorldKit.mat(Color(1.0, 0.8, 0.2), 0.25, 0.8, 0.35), Vector3(PI * 0.5, 0, 0))
	visual.name = "Visual"
	WorldKit.add_mesh(visual, WorldKit.cyl_mesh(0.18, 0.18, 0.09, 6), Vector3.ZERO, WorldKit.mat(Color(0.85, 0.55, 0.1), 0.3, 0.8))
	area.body_entered.connect(_on_coin.bind(area))
	coins.append(area)
	coin_total += 1


func _add_pot(parent: Node, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	parent.add_child(body)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.38
	sh.height = 0.9
	cs.shape = sh
	cs.position.y = 0.45
	body.add_child(cs)
	var clay := WorldKit.mat(Color(0.72, 0.36, 0.2), 0.8)
	WorldKit.add_mesh(body, WorldKit.sphere_mesh(0.4, 16), Vector3(0, 0.42, 0), clay, Vector3.ZERO, Vector3(1, 1.05, 1))
	WorldKit.add_mesh(body, WorldKit.cyl_mesh(0.2, 0.26, 0.2, 16), Vector3(0, 0.88, 0), clay)
	WorldKit.add_mesh(body, WorldKit.cyl_mesh(0.41, 0.41, 0.06, 16), Vector3(0, 0.45, 0), WorldKit.gold())
	pots.append(body)
	pot_total += 1


var checkpoint_pos: Vector3
var _flag: MeshInstance3D


func _add_checkpoint(parent: Node, pos: Vector3) -> void:
	checkpoint_pos = pos + Vector3(0, 0.1, 0)
	WorldKit.add_mesh(parent, WorldKit.cyl_mesh(0.05, 0.05, 2.4, 8), pos + Vector3(0, 1.2, 0), WorldKit.mat(Color(0.35, 0.25, 0.15)))
	_flag = WorldKit.add_mesh(parent, WorldKit.box_mesh(Vector3(0.8, 0.5, 0.04)), pos + Vector3(0.42, 2.1, 0), WorldKit.mat(Color(0.8, 0.8, 0.8)))
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	area.position = pos + Vector3(0, 1, 0)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 1.6
	cs.shape = sh
	area.add_child(cs)
	parent.add_child(area)
	area.body_entered.connect(_on_checkpoint)


# =================================================================== player
func _spawn_player() -> void:
	player = Player.new()
	player.name = "Player"
	player.position = START
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.spawn_point = START
	player.attacked.connect(_on_player_attack)
	player.fell.connect(_on_player_fell)


# =================================================================== loop
func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	_t += delta
	for m in movers:
		var node: Node3D = m["node"]
		var base: Vector3 = m["base"]
		var off: Vector3 = m["offset"]
		var spd: float = m["speed"]
		node.position = base + off * sin(_t * spd)


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	for c in coins:
		if is_instance_valid(c):
			var v := c.get_node_or_null("Visual") as Node3D
			if v:
				v.rotation.y += delta * 2.5
				v.position.y = sin(_t * 2.0 + c.position.x) * 0.12
	var glow := get_node_or_null("Level/GoalGlow") as MeshInstance3D
	if glow:
		glow.scale = Vector3.ONE * (1.0 + sin(_t * 3.0) * 0.06)
	if running:
		time += delta
	_update_hud()

	# browsers release the mouse on Esc without sending the key -> auto pause
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if _mouse_was_captured and not captured and not get_tree().paused and not finished:
		_set_paused(true)
	_mouse_was_captured = captured


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not finished:
		_set_paused(not get_tree().paused)
	elif event.is_action_pressed("restart") and not get_tree().paused:
		get_tree().reload_current_scene()


# =================================================================== events
func _on_coin(body: Node3D, area: Area3D) -> void:
	if body != player or not is_instance_valid(area) or area.get_meta("taken", false):
		return
	area.set_meta("taken", true)
	coin_count += 1
	Global.sfx("coin", -3.0, 0.03)
	var tw := create_tween()
	tw.tween_property(area, "scale", Vector3.ONE * 1.8, 0.12)
	tw.tween_property(area, "scale", Vector3.ONE * 0.01, 0.15)
	tw.tween_callback(area.queue_free)
	if coin_count == coin_total:
		_show_message("All coins collected!", 2.5)


func _on_player_attack(hit_pos: Vector3) -> void:
	for pot in pots.duplicate():
		if not is_instance_valid(pot):
			continue
		if pot.global_position.distance_to(hit_pos - Vector3(0, 0.5, 0)) < 1.35:
			_smash_pot(pot)


func _smash_pot(pot: Node3D) -> void:
	pots.erase(pot)
	pot_count += 1
	Global.sfx("smash", -1.0, 0.1)
	var pos := pot.global_position
	var clay := WorldKit.mat(Color(0.72, 0.36, 0.2), 0.8)
	for i in 8:
		var rb := RigidBody3D.new()
		rb.collision_layer = 4
		rb.collision_mask = 1
		rb.mass = 0.2
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(0.18, 0.12, 0.18)
		cs.shape = sh
		rb.add_child(cs)
		WorldKit.add_mesh(rb, WorldKit.box_mesh(sh.size), Vector3.ZERO, clay)
		add_child(rb)
		rb.global_position = pos + Vector3(randf_range(-0.2, 0.2), 0.5 + randf() * 0.3, randf_range(-0.2, 0.2))
		rb.apply_central_impulse(Vector3(randf_range(-1, 1), randf_range(1.2, 2.2), randf_range(-1, 1)) * 0.6)
		var tw := rb.create_tween()
		tw.tween_interval(1.4)
		tw.tween_property(rb, "scale", Vector3.ONE * 0.01, 0.3)
		tw.tween_callback(rb.queue_free)
	pot.queue_free()
	_show_message("Pot smashed! (%d/%d)" % [pot_count, pot_total], 1.2)


func _on_checkpoint(body: Node3D) -> void:
	if body != player or player.spawn_point == checkpoint_pos:
		return
	player.spawn_point = checkpoint_pos
	Global.sfx("checkpoint", -2.0, 0.0)
	_flag.material_override = WorldKit.mat(Global.GOLD, 0.4, 0.5, 0.4)
	_show_message("Checkpoint!", 1.5)


func _on_player_fell() -> void:
	if finished:
		return
	player.respawn()
	Global.sfx("splash", -2.0)
	_show_message("Splash! Back to checkpoint", 1.5)
	fade.color.a = 0.8
	create_tween().tween_property(fade, "color:a", 0.0, 0.5)


func _on_goal(body: Node3D) -> void:
	if body != player or finished:
		return
	finished = true
	running = false
	player.celebrate()
	Global.play_music(-24.0)
	Global.sfx("win", 0.0, 0.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var best_note := ""
	if Global.best_time < 0.0 or time < Global.best_time:
		Global.best_time = time
		best_note = "  NEW BEST!"
	win_text.text = "Time  %s%s\nCoins  %d / %d\nPots  %d / %d\nBest  %s" % [
		Global.format_time(time), best_note, coin_count, coin_total, pot_count, pot_total, Global.format_time(Global.best_time)]
	await get_tree().create_timer(1.2).timeout
	win_panel.visible = true


# =================================================================== UI
func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Global.theme
	hud.add_child(root)

	fade = ColorRect.new()
	fade.color = Color(0.05, 0.15, 0.25, 0.0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)

	var stats := PanelContainer.new()
	stats.position = Vector2(16, 16)
	root.add_child(stats)
	var vb := VBoxContainer.new()
	stats.add_child(vb)
	lbl_coins = _label(vb, "", 24)
	lbl_pots = _label(vb, "", 20)
	lbl_time = _label(vb, "", 20)

	print("[Character] ", player.rig.status_text)

	lbl_hint = _label(root, "WASD move   Shift run   Space jump   Click / J attack   Q dodge   E cheer   R restart   Esc pause   M mute", 15)
	_place(lbl_hint, [0, 1, 1, 1], [0, -34, 0, -8])
	lbl_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_hint.modulate = Color(1, 1, 1, 0.8)

	lbl_click = _label(root, "Click to control the camera with the mouse", 20)
	_place(lbl_click, [0, 1, 1, 1], [0, -84, 0, -52])
	lbl_click.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	lbl_msg = _label(root, "", 34)
	_place(lbl_msg, [0, 0, 1, 0], [0, 90, 0, 140])
	lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_msg.add_theme_color_override("font_color", Color(1, 0.88, 0.45))

	pause_panel = _menu_panel(root, "PAUSED", [
		["Resume", func(): _set_paused(false)],
		["Restart", func(): _goto("res://scenes/game.tscn")],
		["Main Menu", func(): _goto("res://scenes/main_menu.tscn")],
	])
	win_panel = _menu_panel(root, "TEMPLE REACHED!", [
		["Play Again", func(): _goto("res://scenes/game.tscn")],
		["Main Menu", func(): _goto("res://scenes/main_menu.tscn")],
	])
	var win_box: VBoxContainer = win_panel.get_meta("vbox")
	win_text = _label(win_box, "", 22)
	win_box.move_child(win_text, 1)


func _place(c: Control, anchors: Array, offsets: Array) -> void:
	c.anchor_left = anchors[0]
	c.anchor_top = anchors[1]
	c.anchor_right = anchors[2]
	c.anchor_bottom = anchors[3]
	c.offset_left = offsets[0]
	c.offset_top = offsets[1]
	c.offset_right = offsets[2]
	c.offset_bottom = offsets[3]


func _label(parent: Node, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _menu_panel(root: Control, title: String, buttons: Array) -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.visible = false
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var t := _label(vb, title, 36)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Global.GOLD)
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.pressed.connect(func(): Global.sfx("click", -4.0, 0.0))
		btn.pressed.connect(b[1])
		vb.add_child(btn)
	center.set_meta("vbox", vb)
	return center


func _update_hud() -> void:
	lbl_coins.text = "Coins  %d / %d" % [coin_count, coin_total]
	lbl_pots.text = "Pots  %d / %d" % [pot_count, pot_total]
	lbl_time.text = "Time  %s" % Global.format_time(time)
	lbl_click.visible = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not get_tree().paused and not finished


var _msg_tween: Tween


func _show_message(text: String, duration: float) -> void:
	lbl_msg.text = text
	lbl_msg.modulate.a = 1.0
	if _msg_tween:
		_msg_tween.kill()
	_msg_tween = create_tween()
	_msg_tween.tween_interval(duration)
	_msg_tween.tween_property(lbl_msg, "modulate:a", 0.0, 0.5)


func _set_paused(p: bool) -> void:
	get_tree().paused = p
	Global.play_music(-20.0 if p else -12.0)
	pause_panel.visible = p
	if p:
		_mouse_was_captured = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _goto(path: String) -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(path)

