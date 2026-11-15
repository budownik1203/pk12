extends Node3D
## Ciało zombie z tych samych segmentów co postać gracza (cialo_segmenty.glb),
## z widoczną głową. Pozy liczone w kodzie: powłóczysty chód z pochylonym
## tułowiem, ręce wyciągnięte przed siebie w pościgu, zamach przy ataku,
## zatoczenie po ciosie, leżenie po przewróceniu i śmierci.

const SEGMENTS := preload("res://models/cialo_segmenty.glb")
const Body := preload("res://scripts/body.gd")

const HIP := 0.9
const THIGH := 0.44
const SHIN := 0.44
const UPPER := 0.31
const FORE := 0.29

var parts := {}
var phase := 0.0
var gait := 0.0                     # 0 stoi, 1 pełny krok
var reach := 0.0                    # 0 ręce zwisają, 1 wyciągnięte
var lunge := 0.0                    # 0..1 zamach ataku
var stagger := 0.0                  # 0..1 odrzut po ciosie
var down := 0.0                     # 0 stoi, 1 leży
var lean_seed := 0.0
var _rng := RandomNumberGenerator.new()


func build(seed_value: int) -> void:
	_rng.seed = seed_value
	lean_seed = _rng.randf_range(-0.15, 0.15)
	var scene: Node = SEGMENTS.instantiate()
	var meshes := {}
	for child in scene.find_children("*", "MeshInstance3D", true, false):
		meshes[child.name] = (child as MeshInstance3D).mesh
	scene.free()
	var skin := _mat(Color(0.28, 0.31, 0.23).lerp(Color(0.34, 0.28, 0.25), _rng.randf()))
	var shirts := [Color(0.35, 0.3, 0.25), Color(0.25, 0.28, 0.33), Color(0.4, 0.15, 0.12), Color(0.5, 0.48, 0.42)]
	var pants := [Color(0.18, 0.2, 0.27), Color(0.22, 0.2, 0.17), Color(0.15, 0.15, 0.15)]
	var shirt := _mat((shirts[_rng.randi() % shirts.size()] as Color).lerp(Color(0.3, 0.05, 0.03), _rng.randf_range(0.1, 0.4)))
	var pant := _mat(pants[_rng.randi() % pants.size()])
	var shoe := _mat(Color(0.1, 0.08, 0.07))
	_part("tors", meshes["tors"], shirt)
	_part("miednica", meshes["miednica"], pant)
	for s in ["l", "r"]:
		_part("udo_" + s, meshes["udo"], pant)
		_part("lydka_" + s, meshes["lydka"], pant)
		_part("stopa_" + s, meshes["stopa"], shoe)
		_part("ramie_" + s, meshes["ramie"], shirt)
		_part("przedramie_" + s, meshes["przedramie"], skin)
		_part("dlon_" + s, meshes["dlon"], skin)
	# głowa: pudełko z ciemnymi oczodołami
	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.16, 0.22, 0.19)
	hm.material = skin
	head.mesh = hm
	head.top_level = true
	add_child(head)
	parts["glowa"] = head
	var eyes := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = Vector3(0.12, 0.03, 0.01)
	em.material = _mat(Color(0.05, 0.04, 0.03))
	eyes.mesh = em
	eyes.position = Vector3(0, 0.03, -0.096)
	head.add_child(eyes)
	# rozdziawiona szczęka i krew na brodzie
	var jaw := MeshInstance3D.new()
	var jm := BoxMesh.new()
	jm.size = Vector3(0.09, 0.05, 0.01)
	jm.material = _mat(Color(0.18, 0.03, 0.02))
	jaw.mesh = jm
	jaw.position = Vector3(0, -0.06, -0.096)
	head.add_child(jaw)
	var neck := MeshInstance3D.new()
	var nk := BoxMesh.new()
	nk.size = Vector3(0.09, 0.1, 0.09)
	nk.material = skin
	neck.mesh = nk
	neck.position = Vector3(0, -0.14, 0.02)
	head.add_child(neck)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m


func _part(id: String, mesh: Mesh, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.top_level = true
	add_child(mi)
	parts[id] = mi


func _limb(id: String, p0: Vector3, p1: Vector3, side: Vector3) -> void:
	var y := p1 - p0
	var length := y.length()
	if length < 0.0001:
		return
	var yn := y / length
	var x := side - yn * side.dot(yn)
	x = x.normalized() if x.length() > 0.0001 else yn.cross(Vector3.FORWARD).normalized()
	parts[id].global_transform = Transform3D(Basis(x, yn * length, x.cross(yn)), p0)


## Ustawia całe ciało. origin: stopy na ziemi, fwd: kierunek patrzenia (poziomy).
func pose(origin: Vector3, fwd: Vector3, delta: float, speed: float) -> void:
	phase += delta * (2.2 + speed * 3.0)
	var up := Vector3.UP
	var right := fwd.cross(up).normalized()
	if down > 0.0:
		_pose_down(origin, fwd, right)
		if down >= 0.999:
			return
	# tułów pochylony do przodu, chwiejący się na boki
	var sway := sin(phase * 0.5) * 0.04 * (0.3 + gait)
	var lean := 0.25 + lunge * 0.35 - stagger * 0.5 + lean_seed
	var pelvis := origin + up * (HIP - lunge * 0.06) + right * sway - fwd * stagger * 0.15
	var spine_dir := (up * cos(lean) + fwd * sin(lean) + right * sway * 0.8).normalized()
	var neck := pelvis + spine_dir * 0.58
	_limb("tors", pelvis, neck, right)
	parts["miednica"].global_transform = Transform3D(Basis(right, up, -fwd), pelvis)
	var head_dir := (spine_dir + fwd * 0.35 + right * lean_seed).normalized()
	parts["glowa"].global_transform = Transform3D(Basis.looking_at(fwd, head_dir), neck + head_dir * 0.14)
	# nogi: powłóczyste kroki, jedna noga ciągnięta
	for s in ["l", "r"]:
		var sign := -1.0 if s == "l" else 1.0
		var ph := phase + (0.0 if s == "l" else PI)
		var hip := pelvis + right * 0.1 * sign
		var swing := sin(ph) * 0.24 * gait
		var lift := maxf(0.0, cos(ph)) * (0.05 if s == "l" else 0.09) * gait
		var foot := Vector3(hip.x, origin.y, hip.z) + fwd * swing + up * (0.075 + lift) + right * 0.03 * sign
		var leg: Array = Body.solve_two_bone(hip, foot, hip + fwd * 0.6, THIGH, SHIN)
		_limb("udo_" + s, hip, leg[0], right)
		_limb("lydka_" + s, leg[0], leg[1], right)
		parts["stopa_" + s].global_transform = Transform3D(Basis(right, up, -fwd), leg[1])
	# ręce: zwisają albo wyciągnięte do ofiary; przy ataku zamach z góry
	var torso_right := right
	for s in ["l", "r"]:
		var sign := -1.0 if s == "l" else 1.0
		var shoulder := neck - spine_dir * 0.05 + torso_right * 0.2 * sign
		var ph := phase + (PI if s == "r" else 0.0)
		var hang := shoulder - up * 0.56 + fwd * (0.05 + sin(ph) * 0.08 * gait) + right * 0.05 * sign
		var reach_pt := shoulder + fwd * 0.55 - up * 0.05 + right * 0.04 * sign + up * sin(ph * 1.3) * 0.04
		var hand := hang.lerp(reach_pt, reach)
		if lunge > 0.0:
			var raise := shoulder + up * 0.2 + fwd * 0.15
			var strike := shoulder + fwd * 0.62 - up * 0.2
			hand = hand.lerp(raise, clampf(lunge * 2.0, 0.0, 1.0)).lerp(strike, clampf(lunge * 2.0 - 1.0, 0.0, 1.0))
		var arm: Array = Body.solve_two_bone(shoulder, hand, shoulder - up * 0.3 - fwd * 0.3 + right * sign * 0.3, UPPER, FORE)
		_limb("ramie_" + s, shoulder, arm[0], right)
		_limb("przedramie_" + s, arm[0], arm[1], right)
		var along := (arm[1] - arm[0] as Vector3).normalized()
		_limb("dlon_" + s, arm[1], arm[1] + along, right)


## Leżące ciało: wszystkie segmenty płasko na ziemi, wzdłuż kierunku upadku.
func _pose_down(origin: Vector3, fwd: Vector3, right: Vector3) -> void:
	var up := Vector3.UP
	var base := origin + up * 0.12
	var head_end := base + fwd * 0.9
	_limb("tors", base + fwd * 0.05, base + fwd * 0.62, up)
	parts["miednica"].global_transform = Transform3D(Basis(right, fwd, up), base)
	parts["glowa"].global_transform = Transform3D(Basis.looking_at(-up, fwd), head_end)
	for s in ["l", "r"]:
		var sign := -1.0 if s == "l" else 1.0
		var hip := base + right * 0.1 * sign
		var knee := hip - fwd * 0.44 + right * 0.05 * sign
		var ankle := knee - fwd * 0.44 + right * 0.03 * sign
		_limb("udo_" + s, hip, knee, up)
		_limb("lydka_" + s, knee, ankle, up)
		parts["stopa_" + s].global_transform = Transform3D(Basis(right, -fwd, up), ankle)
		var shoulder := base + fwd * 0.55 + right * 0.2 * sign
		var elbow := shoulder + right * 0.2 * sign + fwd * 0.2
		var wrist := elbow + fwd * 0.28
		_limb("ramie_" + s, shoulder, elbow, up)
		_limb("przedramie_" + s, elbow, wrist, up)
		_limb("dlon_" + s, wrist, wrist + fwd, up)
