extends RefCounted
## Buduje pokój testowy z brył zastępczych: sala główna, ciemna komórka
## za ścianką, stół, regał i zestaw brył fizycznych o różnej masie.
## Zwraca listę brył fizycznych (do zapisu i ekranu deweloperskiego).

const Tex := preload("res://scripts/textures.gd")

const ROOM_W := 9.0    # oś X
const ROOM_D := 7.0    # oś Z
const ROOM_H := 3.0
const WALL := 0.2


static func build(world: Node3D) -> Array:
	var bodies: Array = []
	_environment(world)
	_shell(world)
	_furniture(world)
	_lights(world)
	_physics_props(world, bodies)
	return bodies


static func _environment(world: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.40, 0.46)
	env.ambient_light_energy = 0.22
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.10, 0.11, 0.12)
	env.fog_density = 0.035
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)


static func _shell(world: Node3D) -> void:
	var floor_m := Tex.material("floor", true, 0.5)
	var wall_m := Tex.material("wall", true, 0.4)
	var ceil_m := Tex.material("ceiling", true, 0.4)
	var hw := ROOM_W / 2.0
	var hd := ROOM_D / 2.0
	# podłoga obejmuje salę i komórkę (komórka: 3 m dalej w +X)
	_static_box(world, "Podloga", Vector3(1.5, -0.1, 0), Vector3(ROOM_W + 3.0 + WALL * 2, 0.2, ROOM_D + WALL * 2), floor_m)
	_static_box(world, "Sufit", Vector3(1.5, ROOM_H + 0.1, 0), Vector3(ROOM_W + 3.0 + WALL * 2, 0.2, ROOM_D + WALL * 2), ceil_m)
	_static_box(world, "ScianaN", Vector3(1.5, ROOM_H / 2, -hd - WALL / 2), Vector3(ROOM_W + 3.0 + WALL * 2, ROOM_H, WALL), wall_m)
	_static_box(world, "ScianaS", Vector3(1.5, ROOM_H / 2, hd + WALL / 2), Vector3(ROOM_W + 3.0 + WALL * 2, ROOM_H, WALL), wall_m)
	_static_box(world, "ScianaW", Vector3(-hw - WALL / 2, ROOM_H / 2, 0), Vector3(WALL, ROOM_H, ROOM_D), wall_m)
	_static_box(world, "ScianaE", Vector3(hw + 3.0 + WALL / 2, ROOM_H / 2, 0), Vector3(WALL, ROOM_H, ROOM_D), wall_m)
	# ścianka działowa z otworem drzwiowym (1 m szerokości, 2.1 m wysokości)
	var door_z := 1.2
	var door_w := 1.0
	var door_h := 2.1
	var north_len := (door_z - door_w / 2.0) + hd
	var south_len := hd - (door_z + door_w / 2.0)
	_static_box(world, "DzialowaN", Vector3(hw, ROOM_H / 2, -hd + north_len / 2.0), Vector3(WALL, ROOM_H, north_len), wall_m)
	_static_box(world, "DzialowaS", Vector3(hw, ROOM_H / 2, hd - south_len / 2.0), Vector3(WALL, ROOM_H, south_len), wall_m)
	_static_box(world, "Nadproze", Vector3(hw, door_h + (ROOM_H - door_h) / 2.0, door_z), Vector3(WALL, ROOM_H - door_h, door_w), wall_m)


static func _furniture(world: Node3D) -> void:
	var wood := Tex.material("wood", false, 1.0)
	# stół
	var t := Vector3(-2.6, 0, -2.2)
	_static_box(world, "StolBlat", t + Vector3(0, 0.76, 0), Vector3(1.6, 0.06, 0.8), wood)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_static_box(world, "StolNoga", t + Vector3(0.72 * sx, 0.365, 0.32 * sz), Vector3(0.07, 0.73, 0.07), wood)
	# regał przy ścianie zachodniej
	var r := Vector3(-ROOM_W / 2.0 + 0.22, 0, 1.6)
	_static_box(world, "RegalBokA", r + Vector3(0, 0.9, -0.6), Vector3(0.4, 1.8, 0.04), wood)
	_static_box(world, "RegalBokB", r + Vector3(0, 0.9, 0.6), Vector3(0.4, 1.8, 0.04), wood)
	for h in [0.1, 0.65, 1.2, 1.78]:
		_static_box(world, "RegalPolka", r + Vector3(0, h, 0), Vector3(0.4, 0.04, 1.2), wood)


static func _lights(world: Node3D) -> void:
	var lamp := OmniLight3D.new()
	lamp.name = "LampaSufitowa"
	lamp.position = Vector3(-0.5, ROOM_H - 0.35, 0)
	lamp.light_color = Color(1.0, 0.86, 0.66)
	lamp.light_energy = 2.2
	lamp.omni_range = 9.5
	lamp.omni_attenuation = 1.4
	lamp.shadow_enabled = true
	world.add_child(lamp)
	# klosz lampy, żeby było widać, skąd świeci
	var bulb := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	mesh.radial_segments = 8
	mesh.rings = 4
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.9, 0.7)
	mesh.material = glow
	bulb.mesh = mesh
	bulb.position = lamp.position + Vector3(0, 0.12, 0)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(bulb)


static func _physics_props(world: Node3D, bodies: Array) -> void:
	var crate := Tex.material("crate", false, 1.0)
	var metal := Tex.material("metal", false, 1.0)
	var can := Tex.material("can", false, 2.0)
	var wood := Tex.material("wood", false, 1.0)
	# skrzynki: rozmiar w metrach, masa w kilogramach
	bodies.append(_rigid_box(world, "skrzynka_duza", Vector3(1.2, 0.4, -1.5), Vector3(0.8, 0.8, 0.8), 45.0, crate))
	bodies.append(_rigid_box(world, "skrzynka_srednia_a", Vector3(2.4, 0.3, -1.2), Vector3(0.6, 0.6, 0.6), 18.0, crate))
	bodies.append(_rigid_box(world, "skrzynka_srednia_b", Vector3(1.3, 1.1, -1.5), Vector3(0.6, 0.6, 0.6), 18.0, crate))
	bodies.append(_rigid_box(world, "skrzynka_mala_a", Vector3(0.2, 0.2, 0.6), Vector3(0.4, 0.4, 0.4), 6.0, crate))
	bodies.append(_rigid_box(world, "skrzynka_mala_b", Vector3(1.3, 1.6, -1.5), Vector3(0.4, 0.4, 0.4), 6.0, crate))
	bodies.append(_rigid_box(world, "deska", Vector3(1.4, 0.05, 3.0), Vector3(1.8, 0.04, 0.16), 3.0, wood))
	# ciężka skrzynia w ciemnej komórce
	bodies.append(_rigid_box(world, "skrzynia_komorka", Vector3(6.2, 0.45, -1.8), Vector3(1.0, 0.9, 0.7), 70.0, crate))
	# beczka
	bodies.append(_rigid_cylinder(world, "beczka", Vector3(3.2, 0.45, 2.3), 0.29, 0.9, 25.0, metal, false))
	# puszki na stole: małe, lekkie bryły
	for i in 5:
		var pos := Vector3(-3.1 + 0.22 * i, 0.85, -2.2 + 0.05 * (i % 2))
		bodies.append(_rigid_cylinder(world, "puszka_%d" % i, pos, 0.037, 0.11, 0.42, can, true))
	# puszki na regale
	for i in 3:
		var pos := Vector3(-ROOM_W / 2.0 + 0.22, 1.28, 1.25 + 0.3 * i)
		bodies.append(_rigid_cylinder(world, "puszka_regal_%d" % i, pos, 0.037, 0.11, 0.42, can, true))


# --- pomocnicze -------------------------------------------------------------

static func _static_box(world: Node3D, node_name: String, pos: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	_add_box(body, size, mat)
	world.add_child(body, true)
	return body


static func _rigid_box(world: Node3D, id: String, pos: Vector3, size: Vector3, mass: float, mat: Material) -> RigidBody3D:
	var body := _rigid(id, pos, mass)
	_add_box(body, size, mat)
	world.add_child(body)
	return body


static func _rigid_cylinder(world: Node3D, id: String, pos: Vector3, radius: float, height: float, mass: float, mat: Material, small: bool) -> RigidBody3D:
	var body := _rigid(id, pos, mass)
	body.continuous_cd = small
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	world.add_child(body)
	return body


static func _rigid(id: String, pos: Vector3, mass: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = id
	body.set_meta("save_id", id)
	body.position = pos
	body.mass = mass
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	pm.bounce = 0.05
	body.physics_material_override = pm
	return body


static func _add_box(body: Node3D, size: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
