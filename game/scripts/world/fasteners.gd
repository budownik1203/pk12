extends RefCounted
## Widoczne gwoździe i wkręty: postęp pracy widać na samym przedmiocie zamiast
## na pasku. Gwóźdź wystaje coraz mniej z każdym uderzeniem, wygięty sterczy
## krzywo; wkręt chowa się z każdym obrotem, a nacięcie łba obraca się razem
## z wkrętakiem. Oś Y węzła wskazuje na zewnątrz powierzchni.

const NAIL_LEN := 0.06
const SCREW_LEN := 0.03

static var _metal: StandardMaterial3D
static var _dark: StandardMaterial3D


static func _mats() -> void:
	if _metal != null:
		return
	_metal = StandardMaterial3D.new()
	_metal.albedo_color = Color(0.55, 0.55, 0.57)
	_metal.metallic = 0.6
	_metal.roughness = 0.45
	_dark = StandardMaterial3D.new()
	_dark.albedo_color = Color(0.12, 0.12, 0.13)


static func _cyl(r: float, h: float, mat: Material) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 6
	c.rings = 1
	c.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Węzeł gwoździa albo wkrętu ("nail" / "screw"), ustawiony osią Y na zewnątrz.
static func make(kind: String, parent: Node3D, local: Vector3, outward: Vector3) -> Node3D:
	_mats()
	var pivot := Node3D.new()
	pivot.name = "Gwozdz" if kind == "nail" else "Wkret"
	var y := outward.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
	pivot.transform = Transform3D(Basis(x, y, x.cross(y)), local)
	var spin := Node3D.new()
	spin.name = "Obrot"
	pivot.add_child(spin)
	var length := NAIL_LEN if kind == "nail" else SCREW_LEN
	var shaft := _cyl(0.0018 if kind == "nail" else 0.0025, length, _metal)
	shaft.name = "Trzon"
	spin.add_child(shaft)
	var head := _cyl(0.0045 if kind == "nail" else 0.0058, 0.0016, _metal)
	head.name = "Leb"
	spin.add_child(head)
	if kind == "screw":
		var slot := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.0095, 0.0006, 0.0012)
		b.material = _dark
		slot.mesh = b
		slot.position = Vector3(0, 0.0009, 0)
		head.add_child(slot)
	pivot.set_meta("length", length)
	parent.add_child(pivot)
	set_state(pivot, 0.0, 0.0, false, false)
	return pivot


## exposed: ile metrów wystaje nad powierzchnię; spin: obrót w obrotach.
static func set_state(pivot: Node3D, exposed: float, spin_turns: float, bent: bool, shown: bool) -> void:
	pivot.visible = shown
	if not shown:
		return
	var length: float = pivot.get_meta("length")
	var spin: Node3D = pivot.get_node("Obrot")
	spin.basis = Basis(Vector3.UP, spin_turns * TAU)
	if bent:
		# wygięty: wystaje do połowy i odgina się w bok
		spin.basis = Basis(Vector3.BACK, deg_to_rad(65.0)) * spin.basis
		exposed = length * 0.4
	(spin.get_node("Trzon") as Node3D).position = Vector3(0, exposed - length / 2.0, 0)
	(spin.get_node("Leb") as Node3D).position = Vector3(0, exposed + 0.0008, 0)
