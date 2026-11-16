extends Node
## Przedmioty leżące w świecie: każdy to bryła fizyczna niosąca egzemplarz
## przedmiotu (meta "item"). Wyjęty z ekwipunku przedmiot staje się bryłą,
## podniesiony wraca do siatki z tym samym stanem.

const ItemScript := preload("res://scripts/inventory/item.gd")
const GunMats := preload("res://scripts/gun_materials.gd")
const Gunsmith := preload("res://scripts/gunsmith/gunsmith.gd")
const LIBRARIES := ["res://models/przedmioty.glb", "res://models/bron.glb", "res://models/bron_cc0.glb"]  # późniejszy plik nadpisuje wcześniejszy

var world: Node3D
var bodies: Array = []
var on_removed: Callable          # wywoływane przed usunięciem bryły (np. puszczenie chwytu)


func setup(world_node: Node3D) -> void:
	world = world_node


static var _library := {}
static var _library_xf := {}      # nazwa -> położenie obiektu w pliku (części ruchome broni)


## Siatka modelu z game/models/przedmioty.glb (Blender: assets_src/blender/przedmioty.py).
static func library_mesh(mesh_name: String) -> Mesh:
	if _library.is_empty():
		for path in LIBRARIES:
			if not ResourceLoader.exists(path):
				continue
			var scene: Node = load(path).instantiate()
			for child in scene.find_children("*", "MeshInstance3D", true, false):
				_library[str(child.name)] = (child as MeshInstance3D).mesh
				_library_xf[str(child.name)] = (child as Node3D).transform
			scene.free()
		_library["_loaded"] = null
	return _library.get(mesh_name)


static func make_visual(item) -> MeshInstance3D:
	var model: Dictionary = item.get_def().get("model", {})
	if model.has("gunsmith"):
		var g: Dictionary = Gunsmith.load_gun(str(model["gunsmith"]))
		if not g.is_empty():
			return Gunsmith.make_visual(g)
	if model.has("mesh") and library_mesh(str(model["mesh"])) != null:
		var mesh_name := str(model["mesh"])
		var lm := MeshInstance3D.new()
		lm.mesh = library_mesh(mesh_name)
		_swap_gun_materials(lm)
		# części ruchome (zamek, magazynek, lufy, czółenko): osobne węzły pod modelem
		for key in _library.keys():
			var k := str(key)
			if k.begins_with(mesh_name + "__"):
				var part := MeshInstance3D.new()
				part.name = k.substr(mesh_name.length() + 2)
				part.mesh = _library[k]
				part.transform = _library_xf.get(k, Transform3D.IDENTITY)
				part.set_meta("rest", part.transform)
				_swap_gun_materials(part)
				lm.add_child(part)
		return lm
	var c: Array = model.get("color", [0.5, 0.5, 0.5])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(float(c[0]), float(c[1]), float(c[2]))
	mat.roughness = 0.85
	if item.material() == "metal":
		mat.metallic = 0.35
		mat.roughness = 0.6
	var mi := MeshInstance3D.new()
	if model.get("type", "box") == "parts":
		mi.mesh = parts_mesh(model, item.material() == "metal")
		return mi
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


## Materiały broni z Blendera podmieniamy na teksturowane (po nazwie materiału).
static func _swap_gun_materials(mi: MeshInstance3D) -> void:
	for i in mi.mesh.get_surface_count():
		var src: Material = mi.mesh.surface_get_material(i)
		if src == null:
			continue
		var m := GunMats.for_name(src.resource_name)
		if m != null:
			mi.set_surface_override_material(i, m)


## Model złożony z kilku brył (broń): każda część to osobna powierzchnia z własnym
## kolorem. Części: {"type": "box"|"cylinder", "size"|"radius"+"height", "pos",
## "rot" (stopnie), "color"}. Walec domyślnie leży wzdłuż osi X (lufa).
static func parts_mesh(model: Dictionary, metal: bool) -> ArrayMesh:
	var out := ArrayMesh.new()
	for part in model.get("parts", []):
		var src: PrimitiveMesh
		if str(part.get("type", "box")) == "cylinder":
			var c := CylinderMesh.new()
			c.top_radius = float(part.get("radius", 0.01))
			c.bottom_radius = c.top_radius
			c.height = float(part.get("height", 0.1))
			c.radial_segments = 8
			c.rings = 1
			src = c
		else:
			var b := BoxMesh.new()
			var sz: Array = part.get("size", [0.05, 0.05, 0.05])
			b.size = Vector3(float(sz[0]), float(sz[1]), float(sz[2]))
			src = b
		var r: Array = part.get("rot", [0, 0, 0])
		var basis := Basis.from_euler(Vector3(deg_to_rad(float(r[0])), deg_to_rad(float(r[1])), deg_to_rad(float(r[2]))))
		if src is CylinderMesh and not part.has("rot"):
			basis = Basis(Vector3.BACK, PI / 2.0)  # walec wzdłuż X
		var pp: Array = part.get("pos", [0, 0, 0])
		var xf := Transform3D(basis, Vector3(float(pp[0]), float(pp[1]), float(pp[2])))
		var st := SurfaceTool.new()
		st.append_from(src, 0, xf)
		var c: Array = part.get("color", model.get("color", [0.2, 0.2, 0.2]))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(float(c[0]), float(c[1]), float(c[2]))
		mat.roughness = 0.6 if metal else 0.85
		mat.metallic = 0.4 if metal and not part.get("wood", false) else 0.0
		st.set_material(mat)
		st.commit(out)
	return out


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
	var mc: Array = item.get_def().get("model", {}).get("center", [])
	if mc.size() == 3:
		col.position = Vector3(float(mc[0]), float(mc[1]), float(mc[2]))  # model złożony: obrys nie w środku
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
