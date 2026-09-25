class_name WorldKit
extends RefCounted
## Small helper library to build 3D scenes from code (materials, meshes, bodies, decor).

static var _mats: Dictionary = {}


static func mat(color: Color, rough: float = 0.85, metal: float = 0.0, emissive: float = 0.0) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f_%.2f" % [color.to_html(), rough, metal, emissive]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if color.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emissive
	_mats[key] = m
	return m


static func gold() -> StandardMaterial3D:
	return mat(Color(0.95, 0.74, 0.25), 0.35, 0.75)


# ------------------------------------------------------------------ meshes
static func box_mesh(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func cyl_mesh(top: float, bottom: float, h: float, seg: int = 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func sphere_mesh(r: float, seg: int = 16, hemi: bool = false) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r if hemi else r * 2.0
	s.is_hemisphere = hemi
	s.radial_segments = seg
	s.rings = maxi(4, seg / 2)
	return s


static func prism_mesh(size: Vector3) -> PrismMesh:
	var p := PrismMesh.new()
	p.size = size
	return p


static func capsule_mesh(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 16
	c.rings = 6
	return c


static func add_mesh(parent: Node, m: Mesh, pos: Vector3, material: Material, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


# ------------------------------------------------------------------ physics bodies
static func solid_box(parent: Node, size: Vector3, pos: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	parent.add_child(body)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	add_mesh(body, box_mesh(size), Vector3.ZERO, material)
	return body


static func solid_cyl(parent: Node, r: float, h: float, pos: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	parent.add_child(body)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	body.add_child(cs)
	add_mesh(body, cyl_mesh(r, r, h, 24), Vector3.ZERO, material)
	return body


## Platform whose TOP surface is at `top`. Grass/stone top trim for readability.
static func platform(parent: Node, center_xz: Vector2, top: float, size: Vector3, moving: bool = false) -> Node3D:
	var body: Node3D
	if moving:
		var ab := AnimatableBody3D.new()
		ab.sync_to_physics = true
		body = ab
	else:
		body = StaticBody3D.new()
	body.position = Vector3(center_xz.x, top - size.y * 0.5, center_xz.y)
	parent.add_child(body)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	var stone := mat(Color(0.62, 0.55, 0.47)) if not moving else mat(Color(0.7, 0.2, 0.12), 0.6)
	add_mesh(body, box_mesh(size), Vector3.ZERO, stone)
	var trim := mat(Color(0.3, 0.62, 0.25)) if not moving else gold()
	add_mesh(body, box_mesh(Vector3(size.x + 0.08, 0.12, size.z + 0.08)), Vector3(0, size.y * 0.5 - 0.05, 0), trim)
	return body


# ------------------------------------------------------------------ environment
static func environment(parent: Node, sky_top: Color, horizon: Color, sun_energy: float = 1.25, sun_rot: Vector3 = Vector3(-52, -35, 0), shadows: bool = true) -> DirectionalLight3D:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = sky_top
	psm.sky_horizon_color = horizon
	psm.ground_horizon_color = horizon
	psm.ground_bottom_color = Color(0.12, 0.2, 0.25)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = sun_rot
	sun.light_energy = sun_energy
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.shadow_enabled = shadows
	sun.directional_shadow_max_distance = 45.0
	parent.add_child(sun)
	return sun


# ------------------------------------------------------------------ decor
static func palm(parent: Node, pos: Vector3, height: float = 4.0) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation = Vector3(randf_range(-0.12, 0.12), randf() * TAU, randf_range(-0.12, 0.12))
	parent.add_child(root)
	add_mesh(root, cyl_mesh(0.12, 0.2, height, 8), Vector3(0, height * 0.5, 0), mat(Color(0.48, 0.34, 0.22)))
	var leaf_mat := mat(Color(0.2, 0.58, 0.22))
	var leaf_mesh := sphere_mesh(1.0, 10)
	for i in 7:
		var a := TAU * i / 7.0
		add_mesh(root, leaf_mesh, Vector3(0, height - 0.1, 0) + Basis(Vector3.UP, a) * Vector3(0, -0.15, 0.95),
			leaf_mat, Vector3(0.45, a, 0), Vector3(0.32, 0.06, 1.25))
	add_mesh(root, sphere_mesh(0.28, 10), Vector3(0, height, 0), mat(Color(0.35, 0.25, 0.12)))
	return root


static func bush(parent: Node, pos: Vector3, s: float = 1.0) -> void:
	var m := mat(Color(0.17, 0.48, 0.2))
	for i in 3:
		add_mesh(parent, sphere_mesh(0.55 * s, 10), pos + Vector3(randf_range(-0.4, 0.4) * s, 0.35 * s, randf_range(-0.4, 0.4) * s), m)


## Small Thai-style sala (pavilion) with red layered roof and gold trims.
static func sala(parent: Node, pos: Vector3, rot_y: float = 0.0, s: float = 1.0) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot_y
	root.scale = Vector3.ONE * s
	parent.add_child(root)
	solid_box(root, Vector3(5.0, 0.4, 3.6), Vector3(0, 0.2, 0), mat(Color(0.85, 0.82, 0.76)))
	var white := mat(Color(0.96, 0.94, 0.9))
	for x in [-2.1, 2.1]:
		for z in [-1.5, 1.5]:
			solid_cyl(root, 0.15, 2.6, Vector3(x, 1.7, z), white)
	var red := mat(Global.TEMPLE_RED, 0.6)
	add_mesh(root, box_mesh(Vector3(5.2, 0.2, 3.8)), Vector3(0, 3.05, 0), gold())
	add_mesh(root, prism_mesh(Vector3(3.9, 1.3, 5.6)), Vector3(0, 3.8, 0), red, Vector3(0, PI * 0.5, 0))
	add_mesh(root, prism_mesh(Vector3(2.9, 1.2, 4.6)), Vector3(0, 4.65, 0), red, Vector3(0, PI * 0.5, 0))
	add_mesh(root, box_mesh(Vector3(4.7, 0.08, 0.1)), Vector3(0, 5.25, 0), gold())
	for x in [-2.35, 2.35]:
		add_mesh(root, cyl_mesh(0.02, 0.09, 0.8, 6), Vector3(x, 5.5, 0), gold(), Vector3(0, 0, -0.5 * signf(x)))
	return root


## Golden chedi (stupa) used as the goal.
static func chedi(parent: Node, pos: Vector3, s: float = 1.0) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	root.scale = Vector3.ONE * s
	parent.add_child(root)
	var g := gold()
	solid_box(root, Vector3(4.0, 0.6, 4.0), Vector3(0, 0.3, 0), mat(Color(0.93, 0.9, 0.84)))
	solid_box(root, Vector3(3.0, 0.6, 3.0), Vector3(0, 0.9, 0), mat(Color(0.93, 0.9, 0.84)))
	solid_cyl(root, 1.2, 0.5, Vector3(0, 1.45, 0), g)
	add_mesh(root, sphere_mesh(1.25, 24), Vector3(0, 2.4, 0), g, Vector3.ZERO, Vector3(1, 0.9, 1))
	add_mesh(root, cyl_mesh(0.5, 0.7, 0.4, 16), Vector3(0, 3.4, 0), g)
	for i in 6:
		add_mesh(root, cyl_mesh(0.45 - i * 0.07, 0.5 - i * 0.07, 0.28, 16), Vector3(0, 3.75 + i * 0.3, 0), g)
	add_mesh(root, cyl_mesh(0.0, 0.08, 1.4, 8), Vector3(0, 6.2, 0), g)
	add_mesh(root, sphere_mesh(0.14, 12), Vector3(0, 6.95, 0), mat(Color(1, 0.9, 0.5), 0.2, 0.3, 1.5))
	return root


static func lantern(parent: Node, pos: Vector3) -> void:
	add_mesh(parent, cyl_mesh(0.05, 0.05, 1.6, 6), pos + Vector3(0, 0.8, 0), mat(Color(0.3, 0.2, 0.12)))
	add_mesh(parent, sphere_mesh(0.22, 12), pos + Vector3(0, 1.75, 0), mat(Color(1.0, 0.55, 0.2), 0.5, 0.0, 2.0), Vector3.ZERO, Vector3(1, 1.25, 1))
