extends Node
## Przedmioty leżące w świecie: każdy to bryła fizyczna niosąca egzemplarz
## przedmiotu (meta "item"). Wyjęty z ekwipunku przedmiot staje się bryłą,
## podniesiony wraca do siatki z tym samym stanem.

const ItemScript := preload("res://scripts/inventory/item.gd")

var world: Node3D
var bodies: Array = []
var on_removed: Callable          # wywoływane przed usunięciem bryły (np. puszczenie chwytu)


func setup(world_node: Node3D) -> void:
	world = world_node


static func make_visual(item) -> MeshInstance3D:
	var model: Dictionary = item.get_def().get("model", {})
	var c: Array = model.get("color", [0.5, 0.5, 0.5])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(float(c[0]), float(c[1]), float(c[2]))
	mat.roughness = 0.85
	if item.material() == "metal":
		mat.metallic = 0.35
		mat.roughness = 0.6
	var mi := MeshInstance3D.new()
	if model.get("type", "box") == "cylinder":
		var cyl := CylinderMesh.new()
		cyl.top_radius = float(model.get("radius", 0.04))
		cyl.bottom_radius = cyl.top_radius
		cyl.height = float(model.get("height", 0.1))
		cyl.radial_segments = 8
		cyl.rings = 1
		cyl.material = mat
		mi.mesh = cyl
	else:
		var s: Array = model.get("size", [0.1, 0.1, 0.1])
		var box := BoxMesh.new()
		box.size = Vector3(float(s[0]), float(s[1]), float(s[2]))
		box.material = mat
		mi.mesh = box
	return mi


static func _shape_for(item) -> Shape3D:
	var model: Dictionary = item.get_def().get("model", {})
	if model.get("type", "box") == "cylinder":
		var cyl := CylinderShape3D.new()
		cyl.radius = float(model.get("radius", 0.04))
		cyl.height = float(model.get("height", 0.1))
		return cyl
	var s: Array = model.get("size", [0.1, 0.1, 0.1])
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(0.02, float(s[0])), maxf(0.02, float(s[1])), maxf(0.02, float(s[2])))
	return box


func spawn(item, xf: Transform3D) -> RigidBody3D:
	item.parent_grid = null
	item.slot = ""
	item.pending = false
	var body := RigidBody3D.new()
	body.name = "przedmiot_%d" % item.uid
	body.set_meta("item", item)
	body.mass = maxf(0.05, item.total_mass())
	body.continuous_cd = body.mass < 1.5
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	pm.bounce = 0.05
	body.physics_material_override = pm
	body.add_child(make_visual(item))
	var col := CollisionShape3D.new()
	col.shape = _shape_for(item)
	body.add_child(col)
	world.add_child(body)
	body.global_transform = xf
	bodies.append(body)
	return body


func remove(body: RigidBody3D) -> void:
	if on_removed.is_valid():
		on_removed.call(body)
	bodies.erase(body)
	body.queue_free()


func clear() -> void:
	for b in bodies.duplicate():
		remove(b)


func to_save() -> Array:
	var out: Array = []
	for b in bodies:
		var q: Quaternion = b.global_transform.basis.get_rotation_quaternion()
		var p: Vector3 = b.global_position
		out.append({
			"item": b.get_meta("item").to_dict(),
			"position": [p.x, p.y, p.z],
			"rotation": [q.x, q.y, q.z, q.w],
		})
	return out


func from_save(list: Array) -> void:
	clear()
	for e in list:
		var item = ItemScript.from_dict(e.get("item", {}), ItemScript)
		var p: Array = e.get("position", [0, 1, 0])
		var r: Array = e.get("rotation", [0, 0, 0, 1])
		var q := Quaternion(float(r[0]), float(r[1]), float(r[2]), float(r[3])).normalized()
		spawn(item, Transform3D(Basis(q), Vector3(float(p[0]), float(p[1]), float(p[2]))))
