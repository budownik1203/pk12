extends Node
## Ikony przedmiotów w ekwipunku renderowane z tego samego modelu 3D, który
## leży w świecie i który postać trzyma w ręce (WorldItems.make_visual).
## Każdy rodzaj przedmiotu renderuje się raz, w osobnym świecie 3D, w kadrze
## o proporcjach jego kształtu w siatce (np. deska 1×3 leży wzdłuż kratek).
## Obróconemu w siatce przedmiotowi okno ekwipunku obraca gotową ikonę.

const WorldItems := preload("res://scripts/world_items.gd")
const ItemDB := preload("res://scripts/inventory/item_db.gd")
const ItemScript := preload("res://scripts/inventory/item.gd")

const PX_PER_CELL := 64       # rozdzielczość ikony na kratkę
const ELEVATION := 58.0       # kąt patrzenia z góry (stopnie nad poziomem)

var _cache := {}              # def_id -> ImageTexture (albo null w kolejce)
var _queue: Array = []
var _vp: SubViewport
var _pivot: Node3D
var _cam: Camera3D
var _busy := ""
var _wait := 0
signal icon_ready(def_id)


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.size = Vector2i(PX_PER_CELL, PX_PER_CELL)
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, -35, 0)
	key.light_energy = 1.25
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 140, 0)
	fill.light_energy = 0.35
	_vp.add_child(fill)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_vp.add_child(_cam)


## Ikona dla rodzaju przedmiotu; null, dopóki się nie wyrenderuje (wtedy w kolejce).
func get_icon(def_id: String) -> Texture2D:
	if _cache.has(def_id):
		return _cache[def_id]
	_cache[def_id] = null
	_queue.append(def_id)
	return null


func pending() -> int:
	return _queue.size() + (1 if _busy != "" else 0)


func _process(_delta: float) -> void:
	if _busy != "":
		_wait -= 1
		if _wait > 0:
			return
		var img := _vp.get_texture().get_image()
		if img != null and not img.is_empty():
			_cache[_busy] = ImageTexture.create_from_image(img)
		icon_ready.emit(_busy)
		_busy = ""
		for c in _pivot.get_children():
			c.queue_free()
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _queue.is_empty():
		return
	_busy = _queue.pop_front()
	_stage(_busy)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_wait = 2  # klatka renderu i klatka na odczyt


## Ustawia model w kadrze: płasko (najcieńszy wymiar do góry), najdłuższy wymiar
## wzdłuż dłuższego boku kształtu w siatce; kamera z góry pod kątem.
func _stage(def_id: String) -> void:
	var item = ItemScript.new(def_id, 1)
	var cells: Array = item.cells_for(0)
	var b: Vector2i = ItemDB.bounds(cells)
	_vp.size = Vector2i(b.x * PX_PER_CELL, b.y * PX_PER_CELL)
	var mi: MeshInstance3D = WorldItems.make_visual(item)
	mi.set_meta("psx_skip", true)  # bez drgań wierzchołków PS1 w małym kadrze
	var aabb: AABB = mi.get_aabb()
	mi.position = -aabb.get_center()
	var holder := Node3D.new()
	holder.add_child(mi)
	holder.basis = _lay_flat(aabb.size, b)
	_pivot.add_child(holder)
	# obrys po obróceniu i kadr kamery
	var corners := AABB()
	for k in 8:
		var p: Vector3 = holder.basis * (aabb.get_endpoint(k) - aabb.get_center())
		corners = AABB(p, Vector3.ZERO) if k == 0 else corners.expand(p)
	var elev := deg_to_rad(ELEVATION)
	var dir := Vector3(0, sin(elev), cos(elev))
	var dist := corners.size.length() * 2.0 + 1.0
	_cam.position = dir * dist
	_cam.look_at(Vector3.ZERO, Vector3.UP)
	# rozmiar kadru: rzut obrysu na płaszczyznę kamery
	var right := _cam.global_transform.basis.x
	var upv := _cam.global_transform.basis.y
	var w := 0.0
	var h := 0.0
	for k in 8:
		var p: Vector3 = corners.get_endpoint(k)
		w = maxf(w, absf(p.dot(right)) * 2.0)
		h = maxf(h, absf(p.dot(upv)) * 2.0)
	var aspect := float(b.x) / float(b.y)
	_cam.size = maxf(h, w / aspect) * 1.12
	_cam.near = 0.01
	_cam.far = dist * 2.0 + 2.0


## Obrót modelu do ikony. Kratka kwadratowa (1×1, 2×2): model jak w świecie
## (puszka stoi), lekko obrócony dla bryłowatości. Kształt podłużny: model
## leży, najdłuższy wymiar wzdłuż dłuższego boku kształtu.
static func _lay_flat(size: Vector3, b: Vector2i) -> Basis:
	if b.x == b.y:
		return Basis(Vector3.UP, deg_to_rad(-30.0))
	var dims := [[size.x, Vector3.RIGHT], [size.y, Vector3.UP], [size.z, Vector3.BACK]]
	dims.sort_custom(func(a, c): return a[0] > c[0])
	var longest: Vector3 = dims[0][1]
	var thinnest: Vector3 = dims[2][1]
	var middle: Vector3 = dims[1][1]
	# osie świata ikony: X w prawo (szerokość), Z do widza (wysokość obrazka), Y do góry
	var to_x: Vector3 = longest if b.x > b.y else middle
	var to_z: Vector3 = middle if b.x > b.y else longest
	# basis: kolumny to obrazy osi modelu; składamy odwrotnie (z ikony do modelu) i odwracamy
	var m := Basis(to_x, thinnest, to_z)  # kolumny: która oś modelu idzie na X, Y, Z ikony
	if m.determinant() < 0.0:
		m.z = -m.z
	return m.transposed()
