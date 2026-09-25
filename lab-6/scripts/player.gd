class_name Player
extends CharacterBody3D
## Third-person player using CharacterRig (Mixamo character + animation library).

signal attacked(hit_position: Vector3)
signal fell

@export var walk_speed: float = 3.4
@export var run_speed: float = 6.8
@export var jump_velocity: float = 8.6
@export var gravity: float = 22.0
@export var mouse_sensitivity: float = 0.0028
@export var dodge_speed: float = 9.5

var rig: CharacterRig
var cam_pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var control_enabled: bool = true
var spawn_point: Vector3 = Vector3.ZERO

var _yaw: float = 0.0
var _pitch: float = -0.32
var _action: String = ""
var _action_t: float = 0.0
var _hit_t: float = -1.0
var _combo: int = 0
var _combo_reset: float = 0.0
var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _dodge_dir: Vector3 = Vector3.FORWARD
var _was_on_floor: bool = true
var _fall_speed: float = 0.0
var _skip_attack: bool = false
var _step_t: float = 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50)

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)

	rig = CharacterRig.new()
	rig.name = "Rig"
	add_child(rig)

	cam_pivot = Node3D.new()
	cam_pivot.position.y = 1.45
	add_child(cam_pivot)
	spring = SpringArm3D.new()
	spring.spring_length = 4.6
	spring.margin = 0.2
	spring.collision_mask = 1
	spring.add_excluded_object(get_rid())
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	spring.shape = sphere
	cam_pivot.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 68.0
	camera.current = true
	spring.add_child(camera)
	spawn_point = global_position
	_yaw = rotation.y
	rotation.y = 0.0
	rig.rotation.y = _yaw + PI


func _unhandled_input(event: InputEvent) -> void:
	if not control_enabled:
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_skip_attack = true   # first click only grabs the mouse
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.25, 0.45)


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	if not on_floor:
		velocity.y -= gravity * delta
		_fall_speed = maxf(_fall_speed, -velocity.y)

	# gamepad right stick camera
	var look := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if look.length() > 0.2:
		_yaw -= look.x * 2.6 * delta
		_pitch = clampf(_pitch - look.y * 1.8 * delta, -1.25, 0.45)
	cam_pivot.rotation = Vector3(_pitch, _yaw, 0.0)

	_coyote = 0.12 if on_floor else _coyote - delta
	_jump_buffer -= delta
	_combo_reset -= delta
	if _combo_reset <= 0.0:
		_combo = 0

	var input := Vector2.ZERO
	if control_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if Input.is_action_just_pressed("jump"):
			_jump_buffer = 0.15
	var dir := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, _yaw)
	if dir.length() > 1.0:
		dir = dir.normalized()

	# ---- actions (attack / dodge / cheer)
	if _action_t > 0.0:
		_action_t -= delta
		if _hit_t >= 0.0:
			_hit_t -= delta
			if _hit_t < 0.0:
				attacked.emit(global_position + _facing() * 1.0 + Vector3.UP * 0.9)
		if _action_t <= 0.0:
			_action = ""
	if control_enabled and _action == "":
		if Input.is_action_just_pressed("attack") and not _skip_attack:
			_start_attack(dir)
		elif Input.is_action_just_pressed("dodge") and on_floor:
			_start_dodge(dir)
		elif Input.is_action_just_pressed("cheer") and on_floor:
			_action = "cheer"
			_action_t = minf(rig.play_state("cheer", 0.2, 1.0, true), 2.5)

	# ---- horizontal movement
	var h := Vector3(velocity.x, 0.0, velocity.z)
	match _action:
		"dodge":
			h = _dodge_dir * dodge_speed * clampf(_action_t / 0.3, 0.35, 1.0)
		"attack", "cheer":
			h = h.lerp(Vector3.ZERO, 1.0 - exp(-10.0 * delta))
		_:
			var speed := run_speed if Input.is_action_pressed("sprint") else walk_speed
			var accel := 14.0 if on_floor else 5.0
			h = h.lerp(dir * speed, 1.0 - exp(-accel * delta))
	velocity.x = h.x
	velocity.z = h.z

	# ---- jump
	if _jump_buffer > 0.0 and _coyote > 0.0 and _action != "dodge":
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0
		if _action == "attack" or _action == "cheer":
			_action = ""
			_action_t = 0.0
			_hit_t = -1.0
		rig.play_state("jump", 0.08, 1.2, true)
		Global.sfx("jump", -5.0)

	# ---- facing
	if _action == "" and dir.length() > 0.1:
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-12.0 * delta))

	move_and_slide()

	# ---- landing
	var now_floor := is_on_floor()
	if now_floor and not _was_on_floor:
		if _fall_speed > 4.0:
			Global.sfx("land", -4.0)
		if _fall_speed > 11.0 and _action == "" and rig.has_state("land"):
			_action = "land"
			_action_t = minf(rig.play_state("land", 0.05, 1.3, true), 0.35)
		_fall_speed = 0.0
	_was_on_floor = now_floor

	_update_animation(now_floor)
	_footsteps(now_floor, delta)
	_skip_attack = false

	if global_position.y < -3.0:
		fell.emit()


func _footsteps(on_floor: bool, delta: float) -> void:
	var hs := Vector2(velocity.x, velocity.z).length()
	if not on_floor or hs < 0.5 or _action != "":
		_step_t = 0.0
		return
	_step_t -= delta * hs / walk_speed
	if _step_t <= 0.0:
		Global.sfx("step", -9.0, 0.15)
		_step_t = 0.45


func _facing() -> Vector3:
	return Vector3(sin(rig.rotation.y), 0.0, cos(rig.rotation.y))


func _start_attack(dir: Vector3) -> void:
	if dir.length() > 0.1:
		rig.rotation.y = atan2(dir.x, dir.z)
	var anim_name := rig.attack_anim(_combo)
	var length := 0.5
	if rig.is_fallback or anim_name == "":
		length = rig.play_state("attack", 0.08, 1.0, true)
	else:
		length = rig.play_anim(anim_name, 0.08, 1.35, true)
	_combo += 1
	_combo_reset = 1.3
	Global.sfx("swoosh", -3.0, 0.12)
	_action = "attack"
	_action_t = clampf(length * 0.85, 0.35, 1.1)
	_hit_t = _action_t * 0.4


func _start_dodge(dir: Vector3) -> void:
	_dodge_dir = dir.normalized() if dir.length() > 0.1 else _facing()
	rig.rotation.y = atan2(_dodge_dir.x, _dodge_dir.z)
	_action = "dodge"
	Global.sfx("dodge", -3.0)
	var length := rig.play_state("dodge", 0.08, 1.4, true)
	_action_t = clampf(length, 0.4, 0.7)


func _update_animation(on_floor: bool) -> void:
	if _action != "":
		return
	if not on_floor:
		if velocity.y > 1.0:
			rig.play_state("jump", 0.12, 1.2)
		else:
			rig.play_state("fall", 0.2)
		return
	var hs := Vector2(velocity.x, velocity.z).length()
	if hs < 0.35:
		rig.play_state("idle", 0.2)
	elif hs < walk_speed + 0.8:
		rig.play_state("walk", 0.2, clampf(hs / walk_speed, 0.6, 1.5))
	else:
		rig.play_state("run", 0.2, clampf(hs / run_speed, 0.8, 1.4))


func respawn() -> void:
	global_position = spawn_point
	velocity = Vector3.ZERO
	_action = ""
	_action_t = 0.0
	_fall_speed = 0.0
	rig.play_state("idle", 0.0, 1.0, true)


func celebrate() -> void:
	control_enabled = false
	velocity = Vector3(0, velocity.y, 0)
	_action = "cheer"
	_action_t = 999.0
	rig.rotation.y = _yaw   # face the camera
	rig.play_state("cheer", 0.2, 1.0, true)
	rig.set_loop(rig.resolve("cheer"), true)
