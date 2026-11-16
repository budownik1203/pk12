extends Node3D
## Warsztat broni (osobna scena: scenes/warsztat_broni.tscn, w edytorze F6).
## Lewa kolumna: plik broni, szablon działania, lista modułów. Prawa: suwaki wybranego modułu,
## materiał, rola (część ruchoma) i położenie. Środek: podgląd 3D (PPM obrót, kółko
## przybliżenie, środkowy przycisk przesuwanie). „Zapisz” tworzy data/bronie/<id>.json,
## który gra wczytuje sama: broń leży potem w świecie pod tym samym id.

const Gunsmith := preload("res://scripts/gunsmith/gunsmith.gd")
const ItemDB := preload("res://scripts/inventory/item_db.gd")

const TEMPLATES := {
	"semi": {"label": "Półautomat (pistolet)", "item_from": "pistolet"},
	"pump": {"label": "Pompka (strzelba)", "item_from": "strzelba"},
	"break": {"label": "Łamana (dwururka)", "item_from": "dwururka"},
}
const PART_LABELS := {"": "stała część", "zamek": "zamek (odskakuje)", "magazynek": "magazynek (wypada)",
		"lufy": "lufy (łamane)", "czolenko": "czółenko (pompka)"}
const MAT_LABELS := {"stal": "stal oksydowana", "stal_jasna": "stal jasna", "stal_grawer": "stal grawerowana",
		"drewno": "drewno (orzech)", "bakelit": "bakelit", "guma": "guma", "mosiadz": "mosiądz"}

var data := {}
var selected := -1
var template := "break"

var _gun: Node3D
var _overlay: MeshInstance3D
var _markers := {}
var _cam: Camera3D
var _yaw := 0.6
var _pitch := -0.25
var _dist := 1.2
var _target := Vector3(0.15, 0.0, 0.0)
var _drag := 0

var _id_edit: LineEdit
var _name_edit: LineEdit
var _files: OptionButton
var _tmpl: OptionButton
var _list: ItemList
var _add_type: OptionButton
var _right: VBoxContainer
var _status: Label
var _hinge_box: VBoxContainer
var _info: Label


func _ready() -> void:
	_build_scene()
	_build_ui()
	var files := Gunsmith.list_files()
	if "dwururka" in files:
		load_gun("dwururka")
	else:
		new_gun("break")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--zrzut-warsztatu="):
			_screenshot(a.trim_prefix("--zrzut-warsztatu="))


## Zrzuty do dokumentacji: dwururka z zaznaczonymi lufami i pistolet z szablonu.
func _screenshot(dir: String) -> void:
	select(5)
	for k in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "/warsztat_dwururka.png")
	_yaw = 1.2
	_pitch = -0.1
	_dist = 0.45
	_target = Vector3(0.05, 0.0, 0.0)
	_update_camera()
	new_gun("semi")
	select(0)
	for k in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "/warsztat_pistolet.png")
	get_tree().quit()


# --- scena 3D ---------------------------------------------------------------------

func _build_scene() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.135, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.58)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 35, 0)
	key.light_energy = 1.3
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -140, 0)
	fill.light_energy = 0.5
	add_child(fill)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_cam.near = 0.01
	add_child(_cam)
	_cam.current = true
	_gun = Node3D.new()
	add_child(_gun)
	_overlay = MeshInstance3D.new()
	var om := StandardMaterial3D.new()
	om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	om.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	om.no_depth_test = true
	om.albedo_color = Color(1.0, 0.8, 0.2, 0.22)
	_overlay.material_override = om
	add_child(_overlay)
	for k in [["chwyt", Color(0.9, 0.2, 0.15)], ["wylot", Color(1.0, 0.85, 0.2)], ["zawias", Color(0.3, 0.6, 1.0)]]:
		var mk := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.006
		sp.height = 0.012
		var mm := StandardMaterial3D.new()
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mm.no_depth_test = true
		mm.albedo_color = k[1]
		sp.material = mm
		mk.mesh = sp
		add_child(mk)
		_markers[k[0]] = mk
	# siatka podłoża co 10 cm dla skali
	var grid := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-8, 13):
		im.surface_add_vertex(Vector3(i * 0.1, -0.2, -0.4))
		im.surface_add_vertex(Vector3(i * 0.1, -0.2, 0.4))
	for j in range(-4, 5):
		im.surface_add_vertex(Vector3(-0.8, -0.2, j * 0.1))
		im.surface_add_vertex(Vector3(1.2, -0.2, j * 0.1))
	im.surface_end()
	grid.mesh = im
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(0.3, 0.3, 0.32)
	grid.material_override = gm
	add_child(grid)
	_update_camera()


func _update_camera() -> void:
	var dir := Vector3(cos(_pitch) * sin(_yaw), -sin(_pitch), cos(_pitch) * cos(_yaw))
	_cam.global_position = _target + dir * _dist
	_cam.look_at(_target, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_drag = 1 if mb.pressed else 0
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = 2 if mb.pressed else 0
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist = maxf(0.15, _dist * 0.9)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist = minf(4.0, _dist * 1.1)
		_update_camera()
	elif event is InputEventMouseMotion and _drag > 0:
		var mm := event as InputEventMouseMotion
		if _drag == 1:
			_yaw -= mm.relative.x * 0.008
			_pitch = clampf(_pitch + mm.relative.y * 0.008, -1.4, 1.4)
		else:
			var b := _cam.global_transform.basis
			_target += (-b.x * mm.relative.x + b.y * mm.relative.y) * _dist * 0.0012
		_update_camera()


# --- interfejs --------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var left := PanelContainer.new()
	left.position = Vector2(12, 12)
	left.custom_minimum_size = Vector2(340, 0)
	layer.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	left.add_child(lv)
	var title := Label.new()
	title.text = "WARSZTAT BRONI"
	title.add_theme_font_size_override("font_size", 22)
	lv.add_child(title)
	_id_edit = _line(lv, "Id pliku (bez spacji)")
	_name_edit = _line(lv, "Nazwa w grze")
	var fh := HBoxContainer.new()
	lv.add_child(fh)
	_files = OptionButton.new()
	_files.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fh.add_child(_files)
	_button(fh, "Wczytaj", func(): if _files.selected >= 0: load_gun(_files.get_item_text(_files.selected)))
	var bh := HBoxContainer.new()
	lv.add_child(bh)
	_button(bh, "Nowa", func(): new_gun(template))
	_button(bh, "Zapisz", func(): save())
	lv.add_child(_caption("Szablon działania (przedmiot i animacje)"))
	_tmpl = OptionButton.new()
	for k in TEMPLATES:
		_tmpl.add_item(TEMPLATES[k]["label"])
		_tmpl.set_item_metadata(_tmpl.item_count - 1, k)
	_tmpl.item_selected.connect(func(i): template = str(_tmpl.get_item_metadata(i)); _apply_template_item(); _refresh())
	lv.add_child(_tmpl)
	_hinge_box = VBoxContainer.new()
	lv.add_child(_hinge_box)
	lv.add_child(HSeparator.new())
	lv.add_child(_caption("Moduły"))
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 260)
	_list.item_selected.connect(func(i): select(i))
	lv.add_child(_list)
	var ah := HBoxContainer.new()
	lv.add_child(ah)
	_add_type = OptionButton.new()
	_add_type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in Gunsmith.MODULES:
		_add_type.add_item(Gunsmith.MODULES[k]["label"])
		_add_type.set_item_metadata(_add_type.item_count - 1, k)
	ah.add_child(_add_type)
	_button(ah, "Dodaj", func(): add_module(str(_add_type.get_item_metadata(_add_type.selected))))
	var eh := HBoxContainer.new()
	lv.add_child(eh)
	_button(eh, "Usuń", func(): remove_selected())
	_button(eh, "Duplikuj", func(): duplicate_selected())
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.custom_minimum_size = Vector2(320, 0)
	lv.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.anchor_left = 1.0
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = -390
	scroll.offset_right = -12
	scroll.offset_top = 12
	scroll.offset_bottom = -12
	layer.add_child(scroll)
	var rp := PanelContainer.new()
	rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rp)
	_right = VBoxContainer.new()
	_right.custom_minimum_size = Vector2(360, 0)
	_right.add_theme_constant_override("separation", 4)
	rp.add_child(_right)

	_info = Label.new()
	_info.anchor_top = 1.0
	_info.anchor_bottom = 1.0
	_info.offset_left = 370
	_info.offset_top = -64
	_info.text = "PPM: obrót · kółko: przybliżenie · środkowy: przesuwanie · czerwony punkt: chwyt prawej dłoni · żółty: wylot lufy · niebieski: zawias"
	_info.add_theme_color_override("font_color", Color(0.75, 0.75, 0.7))
	layer.add_child(_info)


func _line(parent: Control, placeholder: String) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	parent.add_child(le)
	return le


func _caption(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", Color(0.85, 0.72, 0.4))
	return l


func _button(parent: Control, t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _slider(parent: Control, label: String, mn: float, mx: float, value: float, cb: Callable, step: float = 0.0, unit: String = "mm") -> void:
	var l := Label.new()
	parent.add_child(l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step if step > 0.0 else (mx - mn) / 400.0
	s.value = value
	s.custom_minimum_size = Vector2(330, 0)
	var show := func(v): l.text = "%s: %s" % [label, _fmt(v, unit)]
	show.call(value)
	s.value_changed.connect(func(v): show.call(v); cb.call(v))
	parent.add_child(s)


static func _fmt(v: float, unit: String) -> String:
	match unit:
		"mm": return "%.0f mm" % (v * 1000.0)
		"°": return "%.0f°" % v
		"n": return "%d" % int(round(v))
	return "%.2f" % v


# --- operacje ----------------------------------------------------------------------

func new_gun(tmpl: String) -> void:
	template = tmpl
	data = {"id": "nowa_bron", "pl": "Nowa broń", "en": "New gun", "modules": [], "anchors": {"hinge": [0.08, -0.004]}, "item": {}}
	match tmpl:
		"semi":
			for t in ["zamek", "chwyt", "kablak", "magazynek", "muszka", "szczerbinka", "kurek"]:
				data["modules"].append(Gunsmith.default_module(t))
			data["modules"][0]["pos"] = [-0.045, 0.06, 0.0]
			data["modules"][0]["part"] = "zamek"
			data["modules"][1]["pos"] = [-0.004, 0.03, 0.0]
			data["modules"][2]["pos"] = [0.012, 0.024, 0.0]
			data["modules"][3]["pos"] = [-0.004, 0.026, 0.0]
			data["modules"][3]["part"] = "magazynek"
			data["modules"][4]["pos"] = [0.108, 0.074, 0.0]
			data["modules"][4]["part"] = "zamek"
			data["modules"][5]["pos"] = [-0.038, 0.074, 0.0]
			data["modules"][5]["part"] = "zamek"
			data["modules"][6]["pos"] = [-0.052, 0.045, 0.0]
			var frame := Gunsmith.default_module("komora")
			frame["params"] = {"dlugosc": 0.15, "wysokosc": 0.018, "szerokosc": 0.021, "zaokraglenie": 6.0}
			frame["pos"] = [-0.042, 0.037, 0.0]
			data["modules"].insert(1, frame)
		"pump":
			for t in ["kolba", "komora", "lufy", "rura", "czolenko", "kablak"]:
				data["modules"].append(Gunsmith.default_module(t))
			data["modules"][1]["pos"] = [0.01, 0.017, 0.0]
			data["modules"][1]["params"]["dlugosc"] = 0.18
			data["modules"][2]["pos"] = [0.19, 0.026, 0.0]
			data["modules"][2]["params"]["dlugosc"] = 0.53
			data["modules"][3]["pos"] = [0.19, -0.003, 0.0]
			data["modules"][4]["pos"] = [0.27, -0.004, 0.0]
			data["modules"][4]["part"] = "czolenko"
			data["modules"][4]["params"]["rowki"] = 6.0
			data["modules"][5]["pos"] = [0.02, -0.01, 0.0]
		_:
			var t2 := Gunsmith.load_gun("dwururka")
			if not t2.is_empty():
				data["modules"] = (t2["modules"] as Array).duplicate(true)
	_apply_template_item()
	selected = -1
	_refresh()


func _apply_template_item() -> void:
	var src := str(TEMPLATES[template]["item_from"])
	var base: Dictionary = ItemDB.get_def(src).duplicate(true)
	base.erase("model")
	for k in ["pl", "en", "short_pl", "short_en"]:
		base.erase(k)
	data["item"] = base


func load_gun(id: String) -> void:
	var g := Gunsmith.load_gun(id)
	if g.is_empty():
		_status.text = "Nie ma pliku " + id
		return
	data = g.duplicate(true)
	var action := str(data.get("item", {}).get("gun", {}).get("action", "break"))
	template = "semi" if action == "semi" else ("pump" if action == "pump" else "break")
	selected = -1
	_refresh()
	_status.text = "Wczytano: " + id


func save(path: String = "") -> bool:
	data["id"] = _id_edit.text.strip_edges().to_lower().replace(" ", "_")
	if data["id"] == "":
		data["id"] = "nowa_bron"
	data["pl"] = _name_edit.text if _name_edit.text != "" else data["id"]
	if not data.has("en") or str(data["en"]) == "":
		data["en"] = data["pl"]
	var item: Dictionary = data.get("item", {})
	item["short_pl"] = data["pl"]
	item["short_en"] = data["en"]
	data["item"] = item
	var ok := Gunsmith.save_gun(data, path)
	_status.text = ("Zapisano data/bronie/%s.json: broń jest w grze pod tym id." % data["id"]) if ok else "Nie udało się zapisać."
	_fill_files()
	return ok


func add_module(type: String) -> void:
	var m := Gunsmith.default_module(type)
	data["modules"].append(m)
	select(data["modules"].size() - 1)


func remove_selected() -> void:
	if selected < 0:
		return
	data["modules"].remove_at(selected)
	selected = -1
	_refresh()


func duplicate_selected() -> void:
	if selected < 0:
		return
	var m: Dictionary = (data["modules"][selected] as Dictionary).duplicate(true)
	var p: Array = m["pos"]
	p[0] = float(p[0]) + 0.02
	data["modules"].append(m)
	select(data["modules"].size() - 1)


func select(i: int) -> void:
	selected = i
	_refresh()


func set_param(i: int, key: String, v: float) -> void:
	data["modules"][i]["params"][key] = v
	_rebuild()


func _refresh() -> void:
	_id_edit.text = str(data.get("id", ""))
	_name_edit.text = str(data.get("pl", ""))
	for k in _tmpl.item_count:
		if str(_tmpl.get_item_metadata(k)) == template:
			_tmpl.select(k)
	_fill_files()
	_list.clear()
	for i in data["modules"].size():
		var m: Dictionary = data["modules"][i]
		var lab := str(Gunsmith.MODULES.get(m["type"], {}).get("label", m["type"]))
		if str(m.get("part", "")) != "":
			lab += "  [%s]" % m["part"]
		_list.add_item(lab)
	if selected >= 0 and selected < _list.item_count:
		_list.select(selected)
	_fill_right()
	_fill_hinge()
	_rebuild()


func _fill_files() -> void:
	_files.clear()
	for f in Gunsmith.list_files():
		_files.add_item(f)


func _fill_hinge() -> void:
	for c in _hinge_box.get_children():
		c.queue_free()
	if template != "break":
		return
	var h: Array = data.get("anchors", {}).get("hinge", [0.08, -0.004])
	_slider(_hinge_box, "Zawias X", -0.05, 0.3, float(h[0]), func(v): data["anchors"]["hinge"][0] = v; _rebuild(), 0.001)
	_slider(_hinge_box, "Zawias Y", -0.08, 0.08, float(h[1]), func(v): data["anchors"]["hinge"][1] = v; _rebuild(), 0.001)


func _fill_right() -> void:
	for c in _right.get_children():
		c.queue_free()
	if selected < 0 or selected >= data["modules"].size():
		var l := _caption("Wybierz moduł z listy po lewej")
		_right.add_child(l)
		return
	var m: Dictionary = data["modules"][selected]
	var spec: Dictionary = Gunsmith.MODULES.get(m["type"], {})
	var t := Label.new()
	t.text = str(spec.get("label", m["type"]))
	t.add_theme_font_size_override("font_size", 20)
	_right.add_child(t)
	_right.add_child(_caption("Materiał"))
	var mo := OptionButton.new()
	for k in Gunsmith.MATERIALS:
		mo.add_item(MAT_LABELS.get(k, k))
		mo.set_item_metadata(mo.item_count - 1, k)
		if k == str(m.get("mat", "")):
			mo.select(mo.item_count - 1)
	mo.item_selected.connect(func(i): m["mat"] = str(mo.get_item_metadata(i)); _rebuild())
	_right.add_child(mo)
	_right.add_child(_caption("Rola w animacji"))
	var po := OptionButton.new()
	for k in Gunsmith.PARTS:
		po.add_item(PART_LABELS[k])
		po.set_item_metadata(po.item_count - 1, k)
		if k == str(m.get("part", "")):
			po.select(po.item_count - 1)
	po.item_selected.connect(func(i): m["part"] = str(po.get_item_metadata(i)); _refresh())
	_right.add_child(po)
	_right.add_child(_caption("Kształt"))
	for k in spec.get("params", {}):
		var ps: Array = spec["params"][k]
		var key := str(k)
		var ints: bool = key in ["liczba", "uklad", "rowki", "spusty", "gumowa"]
		var unit := "n" if ints else ("°" if key == "kat" else ("x" if key in ["zwezenie", "zaokraglenie"] else "mm"))
		_slider(_right, str(ps[3]), float(ps[0]), float(ps[1]), Gunsmith.param(m, key), func(v): set_param(selected, key, v), 1.0 if ints else 0.0, unit)
	_right.add_child(_caption("Położenie"))
	var p: Array = m["pos"]
	_slider(_right, "X (przód)", -0.6, 1.0, float(p[0]), func(v): m["pos"][0] = v; _rebuild(), 0.001)
	_slider(_right, "Y (góra)", -0.2, 0.2, float(p[1]), func(v): m["pos"][1] = v; _rebuild(), 0.0005)
	_slider(_right, "Z (bok)", -0.1, 0.1, float(p[2]) if p.size() > 2 else 0.0, func(v): m["pos"][2] = v; _rebuild(), 0.0005)
	_slider(_right, "Obrót", -90.0, 90.0, float(m.get("rot", 0.0)), func(v): m["rot"] = v; _rebuild(), 0.5, "°")


func _rebuild() -> void:
	for c in _gun.get_children():
		c.queue_free()
	var vis := _visual_uncached()
	_gun.add_child(vis)
	if selected >= 0 and selected < data["modules"].size():
		var only := Gunsmith.build_meshes(data, selected)
		var mesh: ArrayMesh = null
		for k in only:
			mesh = only[k]
		_overlay.mesh = mesh
		_overlay.visible = mesh != null
	else:
		_overlay.visible = false
	var dv := Gunsmith.derived(data)
	var mz: Array = dv["muzzle"]
	_markers["chwyt"].position = Vector3.ZERO
	_markers["wylot"].position = Vector3(float(mz[0]), float(mz[1]), float(mz[2]))
	var h: Array = data.get("anchors", {}).get("hinge", [0.08, -0.004])
	_markers["zawias"].position = Vector3(float(h[0]), float(h[1]), 0)
	_markers["zawias"].visible = template == "break"


## Podgląd bez pamięci podręcznej (zmiany w suwakach mają być widoczne od razu).
func _visual_uncached() -> MeshInstance3D:
	var tmp := data.duplicate(false)
	tmp["id"] = ""
	return Gunsmith.make_visual(tmp)
