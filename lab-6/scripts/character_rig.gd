class_name CharacterRig
extends Node3D
## Loads the Mixamo character (res://characters/hero.fbx), attaches the
## Godot4-OpenAnimationLibraries (MeleeLib / ShooterLib) at runtime and maps
## them to gameplay states (idle, walk, run, jump, attack ...).
## If the character file is missing it builds a placeholder with the same look
## (photo face texture) and procedural animation, so the game always runs.

signal loaded

@export var target_height: float = 1.75
## remove forward drift (root motion) from the Hips track so animations play in place
@export var in_place: bool = true

var model: Node3D
var anim: AnimationPlayer
var skeleton: Skeleton3D
var is_fallback: bool = false
var character_file: String = ""
var library_names: Array[String] = []
var all_animations: PackedStringArray = PackedStringArray()
var states: Dictionary = {}
var attack_list: Array[String] = []
var status_text: String = ""
var current_state: String = ""
var current_anim: String = ""

const FALLBACK_STATES: Array[String] = ["idle", "walk", "run", "jump", "fall", "attack", "dodge", "hit", "cheer", "death"]
const LOOPING: Array[String] = ["idle", "walk", "run", "fall"]
const IGNORE: Array[String] = ["reset", "mixamo.com", "t-pose", "tpose", "t_pose", "bindpose", "bind_pose"]
const RULES: Dictionary = {
	"idle": [["idle"], ["crouch", "aim", "walk", "run", "turn", "shoot", "attack", "fall", "jump", "block", "injur", "to_", "2"]],
	"walk": [["walk_forward", "walkforward", "walk_fwd", "walk"], ["back", "left", "right", "strafe", "crouch", "aim", "injur", "turn", "shoot", "stop", "start"]],
	"run": [["sprint", "run_forward", "runforward", "run_fwd", "run", "jog"], ["back", "left", "right", "strafe", "crouch", "aim", "jump", "shoot", "turn", "stop", "start"]],
	"jump": [["jump_start", "jumpstart", "jump_up", "jumpup", "jump"], ["land", "fall", "loop", "run", "attack", "down"]],
	"fall": [["fall", "jump_loop", "jumploop", "in_air", "inair", "falling"], ["land", "death", "die", "attack", "back"]],
	"land": [["land"], ["hard"]],
	"attack": [["attack", "slash", "swing", "combo", "punch", "kick", "stab", "shoot", "fire"], ["walk", "run", "crouch", "jump", "idle", "hit_", "react"]],
	"dodge": [["roll", "dodge", "dash", "evade"], ["back", "left", "right"]],
	"hit": [["hit_react", "hitreact", "hit", "hurt", "damage", "impact", "react"], ["death", "die"]],
	"death": [["death", "dying", "die"], []],
	"cheer": [["victory", "cheer", "celebrat", "dance", "taunt", "emote"], []],
}
const FALLBACK_CHAIN: Dictionary = {
	"run": ["walk", "idle"], "walk": ["run", "idle"], "fall": ["jump", "idle"], "jump": ["fall", "idle"],
	"land": ["idle"], "dodge": ["idle"], "hit": ["idle"], "cheer": ["idle"], "attack": ["idle"], "death": ["idle"],
}

# ---- placeholder character parts / state
var _fb: Dictionary = {}
var _t: float = 0.0
var _state_t: float = 0.0
var _speed: float = 1.0
var _libs_found: int = 0


func _ready() -> void:
	_load_character()
	loaded.emit()


# =================================================================== public API
func play_state(state: String, blend: float = 0.15, speed: float = 1.0, force: bool = false) -> float:
	if is_fallback:
		if state != current_state or force:
			_state_t = 0.0
		current_state = state
		_speed = speed
		return _fallback_length(state) / maxf(speed, 0.01)
	current_state = state
	var n := resolve(state)
	if n == "":
		return 0.0
	return play_anim(n, blend, speed, force)


func play_anim(anim_name: String, blend: float = 0.15, speed: float = 1.0, force: bool = false) -> float:
	if is_fallback:
		return play_state(anim_name, blend, speed, force)
	if anim == null or not anim.has_animation(anim_name):
		return 0.0
	if anim_name == current_anim and not force:
		anim.speed_scale = speed
		return anim.get_animation(anim_name).length / maxf(speed, 0.01)
	anim.speed_scale = speed
	anim.play(anim_name, blend)
	if force:
		anim.seek(0.0, true)
	current_anim = anim_name
	return anim.get_animation(anim_name).length / maxf(speed, 0.01)


func set_speed(s: float) -> void:
	_speed = s
	if anim:
		anim.speed_scale = s


func set_loop(anim_name: String, loop: bool) -> void:
	if anim and anim.has_animation(anim_name):
		anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE


func resolve(state: String) -> String:
	if String(states.get(state, "")) != "":
		return states[state]
	for alt in FALLBACK_CHAIN.get(state, []):
		if String(states.get(alt, "")) != "":
			return states[alt]
	return ""


func has_state(state: String) -> bool:
	return is_fallback or String(states.get(state, "")) != ""


func attack_anim(index: int) -> String:
	if attack_list.is_empty():
		return ""
	return attack_list[index % attack_list.size()]


func get_animation_names() -> PackedStringArray:
	if is_fallback:
		return PackedStringArray(FALLBACK_STATES)
	return all_animations


# =================================================================== loading
func _load_character() -> void:
	var scene: PackedScene = null
	for p in Global.CHARACTER_PATHS:
		if ResourceLoader.exists(p):
			var r: Resource = load(p)
			if r is PackedScene:
				scene = r
				character_file = p
				break
	if scene == null:
		_build_fallback()
		status_text = "Placeholder character (put hero.fbx in res://characters/)"
		return

	model = scene.instantiate() as Node3D
	add_child(model)
	_fit_model()

	var players := model.find_children("*", "AnimationPlayer", true, false)
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.size() > 0:
		skeleton = skels[0]
	if players.size() > 0:
		anim = players[0]
	else:
		anim = AnimationPlayer.new()
		model.add_child(anim)
		anim.root_node = anim.get_path_to(model)

	_load_libraries()
	_collect_animations()
	_map_states()

	if library_names.is_empty() and _libs_found == 0:
		status_text = "Character OK - no animation library in res://animations/"
	elif library_names.is_empty():
		status_text = "Library found but bones did not match - redo BoneMap import (README)"
	elif all_animations.size() == 0:
		status_text = "Libraries found but no bones matched - check BoneMap import (README)"
	else:
		status_text = "%s | %d animations (%s)" % [character_file.get_file(), all_animations.size(), ", ".join(library_names)]
	play_state("idle", 0.0)


func _fit_model() -> void:
	var box := _local_aabb()
	if box.size.y < 0.001:
		return
	model.scale *= target_height / box.size.y
	box = _local_aabb()
	model.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)


func _local_aabb() -> AABB:
	var inv := global_transform.affine_inverse()
	var result := AABB()
	var first := true
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = (inv * mi.global_transform) * mi.get_aabb()
		if first:
			result = b
			first = false
		else:
			result = result.merge(b)
	return result


func _load_libraries() -> void:
	var root: Node = anim.get_node_or_null(anim.root_node)
	if root == null:
		root = model
	for lib_name in Global.LIBRARY_FILES:
		var path: String = Global.LIBRARY_FILES[lib_name]
		if not ResourceLoader.exists(path):
			continue
		var lib := load(path) as AnimationLibrary
		if lib == null:
			continue
		_libs_found += 1
		var fixed := _prepare_library(lib, root)
		if fixed.get_animation_list().is_empty():
			continue
		if anim.has_animation_library(lib_name):
			anim.remove_animation_library(lib_name)
		anim.add_animation_library(lib_name, fixed)
		library_names.append(lib_name)


## Duplicate library, point tracks at our skeleton, drop tracks for missing bones,
## and remove forward drift so moves play in place.
func _prepare_library(src: AnimationLibrary, root: Node) -> AnimationLibrary:
	var out := AnimationLibrary.new()
	var skel_path := ""
	if skeleton:
		skel_path = String(root.get_path_to(skeleton))
	for n in src.get_animation_list():
		var a: Animation = src.get_animation(n).duplicate(true)
		var matched := 0
		var t := a.get_track_count() - 1
		while t >= 0:
			var tt := a.track_get_type(t)
			if tt == Animation.TYPE_POSITION_3D or tt == Animation.TYPE_ROTATION_3D or tt == Animation.TYPE_SCALE_3D:
				var p: NodePath = a.track_get_path(t)
				var bone := String(p.get_concatenated_subnames())
				if skeleton == null or bone == "" or skeleton.find_bone(bone) == -1:
					a.remove_track(t)
					t -= 1
					continue
				var target := root.get_node_or_null(NodePath(String(p.get_concatenated_names())))
				if target != skeleton:
					a.track_set_path(t, NodePath(skel_path + ":" + bone))
				matched += 1
				if in_place and tt == Animation.TYPE_POSITION_3D and (bone == "Hips" or bone == "Root"):
					_flatten(a, t, bone == "Root")
			t -= 1
		if matched > 0:
			out.add_animation(n, a)
	return out


func _flatten(a: Animation, t: int, whole: bool) -> void:
	var count := a.track_get_key_count(t)
	if count < 2:
		return
	var first: Vector3 = a.track_get_key_value(t, 0)
	var drift := 0.0
	for k in count:
		var v: Vector3 = a.track_get_key_value(t, k)
		drift = maxf(drift, Vector2(v.x - first.x, v.z - first.z).length())
	# only flatten real travel (> 25% of hip height), keep small sways
	if not whole and drift < absf(first.y) * 0.25:
		return
	for k in count:
		var v: Vector3 = a.track_get_key_value(t, k)
		if whole:
			v = Vector3(first.x, v.y, first.z)
		else:
			v.x = first.x
			v.z = first.z
		a.track_set_key_value(t, k, v)


func _collect_animations() -> void:
	var list := PackedStringArray()
	for n in anim.get_animation_list():
		if not _ignored(_short(n)):
			list.append(n)
	list.sort()
	all_animations = list


func _ignored(n: String) -> bool:
	var low := n.to_lower()
	for ig in IGNORE:
		if low == ig or low.contains("mixamo"):
			return true
	return false


func _short(n: String) -> String:
	return n.get_slice("/", n.get_slice_count("/") - 1)


func _find(inc: Array, exc: Array) -> String:
	for strict in [true, false]:
		for kw in inc:
			var best := ""
			for n in all_animations:
				var low := _short(n).to_lower()
				if not low.contains(kw):
					continue
				if strict:
					var bad := false
					for e in exc:
						if low.contains(e):
							bad = true
							break
					if bad:
						continue
				if best == "" or n.length() < best.length():
					best = n
			if best != "":
				return best
	return ""


func _map_states() -> void:
	for s in RULES:
		var rule: Array = RULES[s]
		states[s] = _find(rule[0], rule[1])
	attack_list.clear()
	var rule_a: Array = RULES["attack"]
	for n in all_animations:
		var low := _short(n).to_lower()
		var ok := false
		for kw in rule_a[0]:
			if low.contains(kw):
				ok = true
		for e in rule_a[1]:
			if low.contains(e):
				ok = false
		if ok:
			attack_list.append(n)
	if attack_list.is_empty() and String(states["attack"]) != "":
		attack_list.append(states["attack"])
	for s in states:
		var n: String = states[s]
		if n != "":
			set_loop(n, LOOPING.has(s))
	for n in attack_list:
		set_loop(n, false)


# =================================================================== placeholder character
func _fallback_length(state: String) -> float:
	match state:
		"attack": return 0.5
		"dodge": return 0.55
		"hit": return 0.35
		"land": return 0.2
		"cheer": return 2.0
		"death": return 1.2
	return 1.0


func _build_fallback() -> void:
	is_fallback = true
	model = Node3D.new()
	model.name = "Placeholder"
	add_child(model)
	var s := target_height / 1.77
	model.scale = Vector3.ONE * s

	var shirt := WorldKit.mat(Color(0.93, 0.93, 0.91), 0.9)
	var pants := WorldKit.mat(Color(0.87, 0.87, 0.85), 0.9)
	var skin := WorldKit.mat(Color(0.925, 0.745, 0.61), 0.7)
	var hair := WorldKit.mat(Color(0.08, 0.07, 0.08), 0.5)
	var shoe := WorldKit.mat(Color(0.97, 0.97, 0.97), 0.6)

	var body := Node3D.new()
	body.position = Vector3(0, 0.92, 0)
	model.add_child(body)
	_fb["body"] = body
	var upper := Node3D.new()
	body.add_child(upper)
	_fb["upper"] = upper

	WorldKit.add_mesh(body, WorldKit.cyl_mesh(0.22, 0.22, 0.2), Vector3(0, 0.02, 0), pants, Vector3.ZERO, Vector3(1.05, 1, 0.78))
	WorldKit.add_mesh(upper, WorldKit.capsule_mesh(0.27, 0.78), Vector3(0, 0.25, 0), shirt, Vector3.ZERO, Vector3(1, 1, 0.74))
	WorldKit.add_mesh(upper, WorldKit.sphere_mesh(0.24, 16), Vector3(0, 0.12, 0.03), shirt, Vector3.ZERO, Vector3(1, 0.85, 0.85))
	WorldKit.add_mesh(upper, WorldKit.cyl_mesh(0.07, 0.07, 0.14, 12), Vector3(0, 0.55, 0), skin)

	var head := Node3D.new()
	head.position = Vector3(0, 0.68, 0)
	upper.add_child(head)
	_fb["head"] = head
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_texture = load("res://assets/face_atlas.png")
	head_mat.roughness = 0.7
	var hm := WorldKit.add_mesh(head, _face_head_mesh(), Vector3.ZERO, head_mat)
	hm.name = "FaceHead"
	WorldKit.add_mesh(head, WorldKit.sphere_mesh(0.172, 24, true), Vector3(0, 0.012, -0.01), hair, Vector3(-0.6, 0, 0), Vector3(1.0, 1.05, 1.0))
	for sx in [-1.0, 1.0]:
		WorldKit.add_mesh(head, WorldKit.sphere_mesh(0.04, 8), Vector3(0.15 * sx, 0, 0), skin, Vector3.ZERO, Vector3(0.6, 1.1, 0.8))

	for side in [1.0, -1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(0.31 * side, 0.46, 0)
		upper.add_child(arm)
		WorldKit.add_mesh(arm, WorldKit.cyl_mesh(0.085, 0.095, 0.22, 12), Vector3(0, -0.08, 0), shirt)
		WorldKit.add_mesh(arm, WorldKit.cyl_mesh(0.058, 0.048, 0.42, 10), Vector3(0, -0.36, 0), skin)
		WorldKit.add_mesh(arm, WorldKit.sphere_mesh(0.065, 10), Vector3(0, -0.6, 0), skin, Vector3.ZERO, Vector3(0.8, 1.2, 0.6))
		_fb["arm_l" if side > 0 else "arm_r"] = arm

		var leg := Node3D.new()
		leg.position = Vector3(0.115 * side, 0.0, 0)
		body.add_child(leg)
		WorldKit.add_mesh(leg, WorldKit.cyl_mesh(0.11, 0.08, 0.84, 12), Vector3(0, -0.42, 0), pants)
		WorldKit.add_mesh(leg, WorldKit.sphere_mesh(0.1, 12), Vector3(0, -0.86, 0.05), shoe, Vector3.ZERO, Vector3(0.7, 0.55, 1.4))
		_fb["leg_l" if side > 0 else "leg_r"] = leg
	current_state = "idle"


## Sphere head whose front half is UV-mapped to the face photo on the atlas.
func _face_head_mesh() -> ArrayMesh:
	var r := 0.16
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.08
	sm.radial_segments = 40
	sm.rings = 20
	var arrays := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs := PackedVector2Array()
	uvs.resize(verts.size())
	var half_w := 0.176
	var top := 0.136
	var bottom := -0.19
	for i in verts.size():
		var v := verts[i]
		if v.z > 0.0:
			var u := clampf((v.x + half_w) / (2.0 * half_w), 0.0, 1.0)
			var w := clampf((top - v.y) / (top - bottom), 0.0, 1.0)
			uvs[i] = Vector2(u * 0.625, w * 0.625)
		else:
			uvs[i] = Vector2(0.8, 0.8)
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _process(delta: float) -> void:
	if not is_fallback:
		return
	_t += delta * _speed
	_state_t += delta * _speed
	var la := 0.0
	var ra := 0.0
	var ll := 0.0
	var rl := 0.0
	var bob := 0.0
	var body_x := 0.0
	var twist := 0.0
	var spread := 0.14
	match current_state:
		"walk":
			var sw := sin(_t * 8.0) * 0.55
			ll = sw
			rl = -sw
			la = -sw * 0.8
			ra = sw * 0.8
			bob = absf(sin(_t * 8.0)) * 0.04
		"run":
			var sw2 := sin(_t * 12.0) * 0.95
			ll = sw2
			rl = -sw2
			la = -sw2
			ra = sw2
			bob = absf(sin(_t * 12.0)) * 0.08
			body_x = 0.18
		"jump":
			la = -2.4
			ra = -2.4
			ll = -0.7
			rl = 0.2
			spread = 0.4
		"fall":
			la = -2.0 + sin(_t * 14.0) * 0.3
			ra = -2.0 - sin(_t * 14.0) * 0.3
			ll = -0.3
			rl = 0.3
			spread = 0.6
		"attack":
			var p := clampf(_state_t / 0.5, 0.0, 1.0)
			ra = -2.7 * (p / 0.3) if p < 0.3 else -2.7 + (p - 0.3) / 0.7 * 3.2
			twist = sin(p * PI) * 0.6
			la = 0.3
			ll = -0.3
			rl = 0.3
		"dodge":
			var q := clampf(_state_t / 0.55, 0.0, 1.0)
			body_x = q * TAU
			la = -1.2
			ra = -1.2
			ll = -1.2
			rl = -1.2
			bob = -sin(q * PI) * 0.35
		"hit":
			body_x = -0.4 * sin(clampf(_state_t / 0.35, 0.0, 1.0) * PI)
			la = -0.5
			ra = -0.5
		"cheer":
			la = -2.9 + sin(_t * 10.0) * 0.25
			ra = -2.9 - sin(_t * 10.0) * 0.25
			spread = 0.5
			bob = absf(sin(_t * 5.0)) * 0.18
		"death":
			body_x = -minf(_state_t / 0.8, 1.0) * 1.45
			la = -0.3
			ra = -0.3
		"land":
			bob = -0.08 * sin(clampf(_state_t / 0.2, 0.0, 1.0) * PI)
		_:
			bob = sin(_t * 2.2) * 0.015
			la = sin(_t * 2.2) * 0.04
			ra = -la
	var k := 1.0 - exp(-18.0 * delta)
	var body: Node3D = _fb["body"]
	var upper: Node3D = _fb["upper"]
	body.position.y = lerpf(body.position.y, 0.92 + bob, k)
	if current_state == "dodge":
		body.rotation.x = body_x
	else:
		body.rotation.x = lerp_angle(body.rotation.x, body_x, k)
	upper.rotation.y = lerpf(upper.rotation.y, twist, k)
	var al: Node3D = _fb["arm_l"]
	var ar: Node3D = _fb["arm_r"]
	var lgl: Node3D = _fb["leg_l"]
	var lgr: Node3D = _fb["leg_r"]
	al.rotation.x = lerpf(al.rotation.x, la, k)
	ar.rotation.x = lerpf(ar.rotation.x, ra, k)
	al.rotation.z = lerpf(al.rotation.z, spread, k)
	ar.rotation.z = lerpf(ar.rotation.z, -spread, k)
	lgl.rotation.x = lerpf(lgl.rotation.x, ll, k)
	lgr.rotation.x = lerpf(lgr.rotation.x, rl, k)
