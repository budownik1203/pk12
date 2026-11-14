extends RefCounted
## Buduje pokój testowy z brył zastępczych: sala główna, ciemna komórka
## za ścianką, stół, regał i zestaw brył fizycznych o różnej masie.
## Zwraca słownik: "bodies" (bryły fizyczne), "switches" (włączniki światła)
## i "containers" (pojemniki świata: id -> węzeł).

const Tex := preload("res://scripts/textures.gd")

const ROOM_W := 9.0    # oś X
const ROOM_D := 7.0    # oś Z
const ROOM_H := 3.0
const WALL := 0.2
const WINDOW_X0 := -3.0
const WINDOW_X1 := -1.8
const WINDOW_SILL := 0.9
const WINDOW_TOP := 2.1


static func build(world: Node3D) -> Dictionary:
	var bodies: Array = []
	var switches := {}
	_environment(world)
	_shell(world)
	_furniture(world)
	_lights(world, switches)
	_physics_props(world, bodies)
	_door(world, bodies)
	var containers := {"szafka": _cabinet(world)}
	return {"bodies": bodies, "switches": switches, "containers": containers}


static func _cabinet(world: Node3D) -> StaticBody3D:
	# szafka przy północnej ścianie: pojemnik z siatką 6 × 4, otwierany pod F
	var wood := Tex.material("wood", false, 1.0)
	var size := Vector3(0.9, 1.0, 0.45)
	var cab := _static_box(world, "Szafka", Vector3(0.6, size.y / 2.0, -ROOM_D / 2.0 + size.z / 2.0 + 0.01), size, wood)
	cab.set_meta("container_id", "szafka")
	# fronty drzwiczek i uchwyty, żeby było widać, że to szafka
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.2, 0.15, 0.1)
	for sx in [-1, 1]:
		var handle := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(0.02, 0.12, 0.02)
		hm.material = dark
		handle.mesh = hm
		handle.position = Vector3(0.05 * sx, 0.1, size.z / 2.0 + 0.01)
		cab.add_child(handle)
	var seam := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.008, size.y - 0.08, 0.005)
	sm.material = dark
	seam.mesh = sm
	seam.position = Vector3(0, 0, size.z / 2.0 + 0.003)
	cab.add_child(seam)
	return cab


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
	# ściana południowa z otworem okiennym (WINDOW_X0..WINDOW_X1, parapet i nadproże)
	var wz := hd + WALL / 2
	var left_x0 := -hw - WALL
	var right_x1 := hw + 3.0 + WALL
	_static_box(world, "ScianaS_L", Vector3((left_x0 + WINDOW_X0) / 2.0, ROOM_H / 2, wz), Vector3(WINDOW_X0 - left_x0, ROOM_H, WALL), wall_m)
	_static_box(world, "ScianaS_P", Vector3((WINDOW_X1 + right_x1) / 2.0, ROOM_H / 2, wz), Vector3(right_x1 - WINDOW_X1, ROOM_H, WALL), wall_m)
	var ww := WINDOW_X1 - WINDOW_X0
	var wx := (WINDOW_X0 + WINDOW_X1) / 2.0
	_static_box(world, "Parapet", Vector3(wx, WINDOW_SILL / 2.0, wz), Vector3(ww, WINDOW_SILL, WALL), wall_m)
	_static_box(world, "Nadproze_okno", Vector3(wx, (WINDOW_TOP + ROOM_H) / 2.0, wz), Vector3(ww, ROOM_H - WINDOW_TOP, WALL), wall_m)
	_exterior(world)
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


## Środek otworu okiennego po stronie wnętrza (tam przybija się deski).
static func window_center() -> Vector3:
	return Vector3((WINDOW_X0 + WINDOW_X1) / 2.0, (WINDOW_SILL + WINDOW_TOP) / 2.0, ROOM_D / 2.0)


## Ościeżnica drzwi do komórki od strony zamka (tam przykręca się nakładkę).
static func door_jamb() -> Vector3:
	return Vector3(ROOM_W / 2.0 + 0.05, 1.1, 1.7 - 0.003)


static func _exterior(world: Node3D) -> void:
	# za oknem: kawałek gruntu i niewidzialne granice, żeby nic nie wypadło ze świata
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color(0.12, 0.13, 0.11)
	ground.roughness = 1.0
	var z0 := ROOM_D / 2.0 + WALL
	_static_box(world, "Grunt", Vector3(-2.4, -0.15, z0 + 1.5), Vector3(4.0, 0.3, 3.0), ground)
	for b in [[Vector3(-2.4, 1.5, z0 + 3.05), Vector3(4.0, 3.0, 0.1)],
			[Vector3(-4.45, 1.5, z0 + 1.5), Vector3(0.1, 3.0, 3.0)],
			[Vector3(-0.35, 1.5, z0 + 1.5), Vector3(0.1, 3.0, 3.0)]]:
		var wall := StaticBody3D.new()
		wall.name = "GranicaZewn"
		wall.position = b[0]
		var shape := BoxShape3D.new()
		shape.size = b[1]
		var col := CollisionShape3D.new()
		col.shape = shape
		wall.add_child(col)
		world.add_child(wall, true)


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


static func _lights(world: Node3D, switches: Dictionary) -> void:
	var wall_x := ROOM_W / 2.0
	# sala: lampa zapalona, włącznik przy drzwiach do komórki
	_lamp(world, switches, "lampa_sala", Vector3(-0.5, ROOM_H - 0.35, 0), 2.2, 9.5, true,
			Vector3(wall_x - WALL / 2.0 - 0.015, 1.3, 0.35))
	# komórka: lampa zgaszona, włącznik po drugiej stronie tej samej ścianki
	_lamp(world, switches, "lampa_komorka", Vector3(wall_x + 1.5, ROOM_H - 0.35, 0), 1.5, 5.5, false,
			Vector3(wall_x + WALL / 2.0 + 0.015, 1.3, 0.35))


static func _lamp(world: Node3D, switches: Dictionary, id: String, pos: Vector3, energy: float,
		light_range: float, on: bool, switch_pos: Vector3) -> void:
	var lamp := OmniLight3D.new()
	lamp.name = id
	lamp.position = pos
	lamp.light_color = Color(1.0, 0.86, 0.66)
	lamp.light_energy = energy
	lamp.omni_range = light_range
	lamp.omni_attenuation = 1.4
	lamp.shadow_enabled = true
	lamp.visible = on
	world.add_child(lamp)
	# żarówka, żeby było widać, skąd świeci
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	mesh.radial_segments = 8
	mesh.rings = 4
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = glow
	var bulb := MeshInstance3D.new()
	bulb.mesh = mesh
	bulb.position = pos + Vector3(0, 0.12, 0)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(bulb)
	# włącznik: płytka na ścianie, obiekt do użycia pod F
	var plate := StandardMaterial3D.new()
	plate.albedo_color = Color(0.78, 0.76, 0.68)
	plate.roughness = 0.8
	var sw := _static_box(world, "Wlacznik_" + id, switch_pos, Vector3(0.03, 0.12, 0.08), plate)
	sw.set_meta("switch_id", id)
	switches[id] = {"light": lamp, "glow": glow, "on": on}
	apply_switch(switches[id])


static func apply_switch(entry: Dictionary) -> void:
	var on: bool = entry["on"]
	entry["light"].visible = on
	entry["glow"].albedo_color = Color(1.0, 0.9, 0.7) if on else Color(0.16, 0.15, 0.13)


static func _door(world: Node3D, bodies: Array) -> void:
	# drzwi do komórki: bryła na zawiasie; na razie bez klamki i zamka
	var wood := Tex.material("wood", false, 1.0)
	var size := Vector3(0.04, 2.04, 0.94)
	var hinge_z := 0.72
	var center := Vector3(ROOM_W / 2.0, 0.02 + size.y / 2.0, hinge_z + size.z / 2.0 + 0.005)
	var door := _rigid("drzwi_komorka", center, 22.0)
	door.angular_damp = 1.5
	_add_box(door, size, wood)
	world.add_child(door)
	var joint := HingeJoint3D.new()
	joint.name = "ZawiasDrzwi"
	joint.position = Vector3(ROOM_W / 2.0, center.y, hinge_z)
	joint.rotation_degrees = Vector3(90, 0, 0)  # oś zawiasu pionowo
	world.add_child(joint)
	joint.node_a = joint.get_path_to(door)
	joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(-100.0))
	joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(100.0))
	bodies.append(door)


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
