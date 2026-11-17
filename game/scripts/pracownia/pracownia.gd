extends Node3D
## PRACOWNIA: narzędzie do składania modeli broni i narzędzi z modułów, do ich teksturowania
## (zużycie, brud, rdza) i animowania (kroki przeładowania z kluczami).
## Scena: scenes/pracownia.tscn (w edytorze Godota: otwórz i F6).
##
## Cztery zakładki:
##   1 Składanie     szablony, zestawy, szybkie suwaki całości, dane przedmiotu, test w grze
##   2 Modelowanie   drzewo modułów, parametry, położenie, modyfikatory (lustro, powtórzenie),
##                   hierarchia, edytor profilu rysowanego punktami
##   3 Teksturowanie materiały z biblioteki i zużycie (kolor, przetarcia, brud, rdza, rysy)
##   4 Animacja      kotwice (wylot, lewa dłoń, zawias…), kroki szablonu, ścieżki z kluczami,
##                   oś czasu, podgląd z oczu postaci
## Plik projektu: data/warsztat/<id>.json (gra wczytuje go sama, patrz core.gd).

const Core := preload("res://scripts/pracownia/core.gd")
const Mats := preload("res://scripts/pracownia/materials.gd")
const Anim := preload("res://scripts/pracownia/anim.gd")
const Templates := preload("res://scripts/pracownia/templates.gd")
const UI := preload("res://scripts/pracownia/ui_kit.gd")
const ProfileEditor := preload("res://scripts/pracownia/profile_editor.gd")
const Timeline := preload("res://scripts/pracownia/timeline.gd")
const ItemDB := preload("res://scripts/inventory/item_db.gd")
const Psx := preload("res://scripts/psx.gd")

const TABS := [["skladanie", "1  Składanie"], ["modelowanie", "2  Modelowanie"], ["tekstury", "3  Teksturowanie"], ["animacja", "4  Animacja"]]
const AUTOSAVE := "user://pracownia_autozapis.json"
const SHOTS_DIR := "user://pracownia"
const HIP_PISTOL := Vector3(0.11, -0.2, -0.34)
const HIP_LONG := Vector3(0.15, -0.2, -0.3)
const ANCHOR_COLORS := {"wylot": Color(1.0, 0.85, 0.2), "lewa": Color(0.3, 0.9, 0.5), "gniazdo": Color(0.8, 0.5, 1.0),
		"wyrzutnik": Color(1.0, 0.5, 0.2), "zawias": Color(0.3, 0.6, 1.0), "os_bebna": Color(0.4, 0.9, 0.9), "os_kurka": Color(0.9, 0.4, 0.6)}
const WEAR_PRESETS := {
	"Fabrycznie nowa": {"zuzycie": 0.05, "brud": 0.05, "rdza": 0.0, "rysy": 0.05, "polysk": 0.4},
	"Używana": {"zuzycie": 0.35, "brud": 0.35, "rdza": 0.0, "rysy": 0.3, "polysk": 0.1},
	"Zaniedbana": {"zuzycie": 0.6, "brud": 0.65, "rdza": 0.15, "rysy": 0.55, "polysk": 0.0},
	"Z piwnicy": {"zuzycie": 0.5, "brud": 0.7, "rdza": 0.6, "rysy": 0.4, "polysk": 0.0},
	"Wojenna": {"zuzycie": 0.85, "brud": 0.5, "rdza": 0.25, "rysy": 0.9, "polysk": 0.0},
}
const LIGHTS := ["Pracownia", "Dzień", "Zmierzch", "Noc z latarką", "Żarówka"]

var data := {}
var sel: Array = []                  # zaznaczone moduły (indeksy), ostatni = główny
var tab := "skladanie"
var snap_on := true
var dirty := false

# animacja
var anim_step := ""
var anim_t := 0.0
var playing := false
var loop := true
var play_speed := 1.0
var fpp := false
var ads := false
var anchor_sel := "wylot"
var _pick_anchor := false

var _history: Array = []
var _hist_i := -1
var _commit_timer := -1.0
var _rebuild_due := false
var _rebuild_timer := 0.0
var _autosave_timer := 0.0
var _wear_clip := {}
var _ruler_on := false
var _ruler_pts: Array = []

# transformacja myszą (G / R / S jak w Blenderze)
var _xform_mode := ""
var _xform_axis := ""
var _xform_start := Vector2.ZERO
var _xform_orig: Array = []

# scena 3D
var _cam: Camera3D
var _yaw := 0.75
var _pitch := -0.32
var _dist := 1.1
var _target := Vector3(0.12, 0.0, 0.0)
var _drag := 0
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _rim: DirectionalLight3D
var _bulb: OmniLight3D
var _torch: SpotLight3D
var _model: Node3D
var _gun_holder: Node3D
var _gizmo: MeshInstance3D
var _grid: MeshInstance3D
var _ground: MeshInstance3D
var _anchor_nodes := {}
var _hand_l: MeshInstance3D
var _hand_r: MeshInstance3D
var _ruler: MeshInstance3D
var _ruler_label: Label3D
var _ref_quad: MeshInstance3D
var _light_preset := 0
var _psx := false
var _show_grid := true
var _show_anchors := true

# interfejs
var _root: Control
var _tab_buttons := {}
var _left: VBoxContainer
var _right: VBoxContainer
var _bottom: PanelContainer
var _bottom_box: VBoxContainer
var _status: Label
var _stats: Label
var _title_edit: LineEdit
var _files_opt: OptionButton
var _tree: Tree
var _timeline   # timeline.gd
var _profile    # profile_editor.gd
var _help: PanelContainer
var _view_bar: HBoxContainer
var _restore_btn: Button
var _left_panel: PanelContainer
var _right_panel: PanelContainer


func _ready() -> void:
	Psx.init()
	if get_tree().current_scene == self:
		Psx.set_style(0.0, 0.0)  # w Pracowni bez drgań (włącza je „Pokaż ▸ Wygląd PSX”)
	_build_scene()
	_build_ui()
	get_viewport().size_changed.connect(_update_camera)
	var back := str(Engine.get_meta("pracownia_back", "")) if Engine.has_meta("pracownia_back") else ""
	if back != "" and not Core.load_project(back).is_empty():
		open_project(back)
	elif "dwururka" in Core.list_files():
		open_project("dwururka")
	else:
		new_project("pistolet")
	if FileAccess.file_exists(AUTOSAVE):
		_restore_btn.visible = true
	set_tab("skladanie")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--zrzut-pracowni="):
			_doc_screenshots(a.trim_prefix("--zrzut-pracowni="))


# =====================================================================================
# scena 3D
# =====================================================================================

func _build_scene() -> void:
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.ssao_enabled = true
	_env.ssao_radius = 0.08
	_env.ssao_intensity = 1.2
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 6.0
	add_child(_sun)
	_fill = DirectionalLight3D.new()
	add_child(_fill)
	_rim = DirectionalLight3D.new()
	add_child(_rim)
	_bulb = OmniLight3D.new()
	_bulb.omni_range = 3.0
	_bulb.shadow_enabled = true
	_bulb.position = Vector3(0.3, 0.7, 0.4)
	add_child(_bulb)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.near = 0.005
	add_child(_cam)
	_cam.current = true
	_torch = SpotLight3D.new()
	_torch.spot_range = 4.0
	_torch.spot_angle = 24.0
	_torch.shadow_enabled = true
	_torch.position = Vector3(0.12, -0.05, 0.0)
	_cam.add_child(_torch)

	_gun_holder = Node3D.new()
	add_child(_gun_holder)
	_model = Node3D.new()
	_gun_holder.add_child(_model)

	_ground = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	_ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.075, 0.072, 0.07)
	gmat.roughness = 0.95
	_ground.material_override = gmat
	_ground.position.y = -0.21
	_ground.set_meta("psx_skip", true)
	add_child(_ground)
	_grid = MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-10, 21):
		var major := i % 5 == 0
		var y := -0.2095 if major else -0.2098
		im.surface_set_color(Color(1, 1, 1, 0.22 if major else 0.08))
		im.surface_add_vertex(Vector3(i * 0.05, y, -0.5))
		im.surface_add_vertex(Vector3(i * 0.05, y, 0.5))
	for j in range(-10, 11):
		var major := j % 5 == 0
		im.surface_set_color(Color(1, 1, 1, 0.22 if major else 0.08))
		im.surface_add_vertex(Vector3(-0.5, -0.2095, j * 0.05))
		im.surface_add_vertex(Vector3(1.0, -0.2095, j * 0.05))
	im.surface_end()
	_grid.mesh = im
	_grid.material_override = _line_mat(Color.WHITE, false, true)
	add_child(_grid)

	_gizmo = MeshInstance3D.new()
	_gizmo.material_override = _line_mat(Color.WHITE, true, true)
	add_child(_gizmo)
	for k in Core.ANCHORS:
		var mk := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.005
		sp.height = 0.01
		sp.radial_segments = 12
		sp.rings = 6
		mk.mesh = sp
		mk.material_override = _line_mat(ANCHOR_COLORS.get(k, Color.WHITE), true, false)
		var lb := Label3D.new()
		lb.text = str(Core.ANCHORS[k])
		lb.font_size = 22
		lb.pixel_size = 0.0015
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.no_depth_test = true
		lb.position = Vector3(0, 0.012, 0)
		lb.modulate = ANCHOR_COLORS.get(k, Color.WHITE)
		lb.outline_size = 6
		mk.add_child(lb)
		_gun_holder.add_child(mk)
		_anchor_nodes[k] = mk
	var grip := MeshInstance3D.new()
	var gs := SphereMesh.new()
	gs.radius = 0.005
	gs.height = 0.01
	grip.mesh = gs
	grip.material_override = _line_mat(UI.RED, true, false)
	var gl := Label3D.new()
	gl.text = "Chwyt"
	gl.font_size = 22
	gl.pixel_size = 0.0015
	gl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	gl.no_depth_test = true
	gl.position = Vector3(0, -0.012, 0)
	gl.modulate = UI.RED
	gl.outline_size = 6
	grip.add_child(gl)
	_gun_holder.add_child(grip)
	_anchor_nodes["_chwyt"] = grip
	for side in ["l", "r"]:
		var h := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.085, 0.095)
		h.mesh = bm
		var hm := StandardMaterial3D.new()
		hm.albedo_color = Color(0.55, 0.42, 0.33, 0.55) if side == "l" else Color(0.45, 0.35, 0.3, 0.35)
		hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		h.material_override = hm
		h.visible = false
		h.set_meta("psx_skip", true)
		add_child(h)
		if side == "l":
			_hand_l = h
		else:
			_hand_r = h
	_ruler = MeshInstance3D.new()
	_ruler.material_override = _line_mat(UI.ACCENT, true, false)
	add_child(_ruler)
	_ruler_label = Label3D.new()
	_ruler_label.font_size = 26
	_ruler_label.pixel_size = 0.0012
	_ruler_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_ruler_label.no_depth_test = true
	_ruler_label.modulate = UI.ACCENT
	_ruler_label.outline_size = 8
	add_child(_ruler_label)
	_ref_quad = MeshInstance3D.new()
	_ref_quad.visible = false
	add_child(_ref_quad)
	apply_light(0)
	_update_camera()


func _line_mat(c: Color, top: bool, vcolor: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.vertex_color_use_as_albedo = vcolor
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = top
	m.render_priority = 10 if top else 0
	return m


func apply_light(i: int) -> void:
	_light_preset = i
	_bulb.visible = false
	_torch.visible = false
	_rim.visible = true
	match i:
		0:  # pracownia: neutralne, czytelne
			_env.background_color = Color(0.035, 0.035, 0.04)
			_env.ambient_light_color = Color(0.6, 0.6, 0.63)
			_env.ambient_light_energy = 0.55
			_sun.light_color = Color(1.0, 0.97, 0.92)
			_sun.light_energy = 1.25
			_sun.rotation_degrees = Vector3(-48, 32, 0)
			_fill.light_color = Color(0.75, 0.82, 1.0)
			_fill.light_energy = 0.45
			_fill.rotation_degrees = Vector3(-15, -140, 0)
			_rim.light_energy = 0.7
			_rim.rotation_degrees = Vector3(-10, 170, 0)
		1:  # dzień: jasno jak w Project Zomboid
			_env.background_color = Color(0.55, 0.66, 0.78)
			_env.ambient_light_color = Color(0.7, 0.75, 0.82)
			_env.ambient_light_energy = 0.7
			_sun.light_color = Color(1.0, 0.95, 0.85)
			_sun.light_energy = 1.6
			_sun.rotation_degrees = Vector3(-60, 20, 0)
			_fill.light_energy = 0.25
			_rim.light_energy = 0.2
		2:  # zmierzch: ciepłe nisko
			_env.background_color = Color(0.32, 0.22, 0.2)
			_env.ambient_light_color = Color(0.45, 0.4, 0.5)
			_env.ambient_light_energy = 0.4
			_sun.light_color = Color(1.0, 0.62, 0.35)
			_sun.light_energy = 1.4
			_sun.rotation_degrees = Vector3(-12, 70, 0)
			_fill.light_color = Color(0.4, 0.45, 0.8)
			_fill.light_energy = 0.35
			_rim.light_energy = 0.3
		3:  # noc: granat i latarka (Lethal Company)
			_env.background_color = Color(0.02, 0.025, 0.05)
			_env.ambient_light_color = Color(0.12, 0.15, 0.3)
			_env.ambient_light_energy = 0.35
			_sun.light_energy = 0.0
			_fill.light_energy = 0.08
			_fill.light_color = Color(0.3, 0.4, 0.9)
			_rim.visible = false
			_torch.visible = true
			_torch.light_color = Color(1.0, 0.93, 0.8)
			_torch.light_energy = 3.0
		4:  # żarówka: ciepła lampa w ciemnym pokoju (Darkwood)
			_env.background_color = Color(0.04, 0.035, 0.03)
			_env.ambient_light_color = Color(0.2, 0.17, 0.15)
			_env.ambient_light_energy = 0.3
			_sun.light_energy = 0.0
			_fill.light_energy = 0.05
			_rim.visible = false
			_bulb.visible = true
			_bulb.light_color = Color(1.0, 0.72, 0.42)
			_bulb.light_energy = 2.2


func _update_camera() -> void:
	if fpp:
		_cam.transform = Transform3D.IDENTITY
		_apply_frustum(70.0)
		return
	_apply_frustum(38.0)
	var dir := Vector3(cos(_pitch) * sin(_yaw), -sin(_pitch), cos(_pitch) * cos(_yaw))
	_cam.global_position = _target + dir * _dist
	_cam.look_at(_target, Vector3.UP)


## Obszar podglądu bez paneli (piksele okna).
func free_rect() -> Rect2:
	var vs := get_viewport().get_visible_rect().size
	if _root == null or not _root.visible:
		return Rect2(Vector2.ZERO, vs)
	var top := 92.0
	var bottom := vs.y - (262.0 if tab == "animacja" else 30.0)
	return Rect2(326.0, top, maxf(100.0, vs.x - 376.0 - 326.0), maxf(100.0, bottom - top))


## Kamera patrzy w środek wolnego obszaru: ostrosłup przesunięty tak, żeby kąt widzenia
## liczył się na wysokość tego obszaru (model nie chowa się za panelami).
func _apply_frustum(fov_deg: float) -> void:
	var vs := get_viewport().get_visible_rect().size
	var r := free_rect()
	var k := 2.0 * _cam.near * tan(deg_to_rad(fov_deg) * 0.5) / r.size.y
	var off := vs * 0.5 - r.get_center()
	_cam.projection = Camera3D.PROJECTION_FRUSTUM
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.size = k * vs.y
	_cam.frustum_offset = Vector2(off.x * k, -off.y * k)
	_cam.fov = fov_deg


func view_preset(which: String) -> void:
	fpp = false
	match which:
		"bok": _yaw = 0.0; _pitch = 0.0
		"przod": _yaw = PI * 0.5; _pitch = 0.0
		"gora": _yaw = 0.0; _pitch = -1.5
		"tyl": _yaw = PI; _pitch = 0.0
		"3/4": _yaw = 0.75; _pitch = -0.32
	_update_camera()


## Kadruje kamerę na zaznaczonym module albo całości.
func frame_selection() -> void:
	var box := AABB()
	var first := true
	for mi in _module_nodes():
		var idx := int(mi.get_meta("module"))
		if not sel.is_empty() and not sel.has(idx):
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	_target = box.get_center()
	_dist = clampf(box.size.length() * 1.25, 0.08, 4.0)
	fpp = false
	_update_camera()


func _module_nodes() -> Array:
	var out: Array = []
	_collect_modules(_model, out)
	return out


func _collect_modules(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and c.has_meta("module"):
			out.append(c)
		_collect_modules(c, out)


# =====================================================================================
# budowa modelu w podglądzie
# =====================================================================================

func _rebuild_now() -> void:
	_rebuild_due = false
	for c in _model.get_children():
		_model.remove_child(c)
		c.queue_free()
	var vis := Core.make_visual(data, true)
	_model.add_child(vis)
	for mi in _module_nodes():
		var idx := int(mi.get_meta("module"))
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = (mi as MeshInstance3D).mesh.create_trimesh_shape()
		body.add_child(cs)
		body.set_meta("module", idx)
		mi.add_child(body)
		if sel.has(idx):
			((mi as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("highlight", 1.0 if idx == _primary() else 0.6)
	_update_markers()
	_update_gizmo()
	_update_stats()
	if tab == "animacja":
		_apply_anim_pose()


func _touch(rebuild: bool = true) -> void:
	dirty = true
	if rebuild:
		_rebuild_due = true
	_commit_timer = 0.45


func _update_markers() -> void:
	var anchors: Dictionary = data.get("anchors", {})
	var dv := Core.derived(data)
	for k in _anchor_nodes:
		var node: MeshInstance3D = _anchor_nodes[k]
		if k == "_chwyt":
			node.visible = _show_anchors
			continue
		var has: bool = anchors.has(k)
		var pos := Vector3.ZERO
		if has:
			var a: Array = anchors[k]
			pos = Vector3(float(a[0]), float(a[1]), float(a[2]) if a.size() > 2 else 0.0)
		elif k == "wylot" and str(data.get("kind", "")) == "gun":
			var mz: Array = dv["muzzle"]
			pos = Vector3(float(mz[0]), float(mz[1]), float(mz[2]))
			has = true
		node.position = pos
		node.visible = _show_anchors and has
		var lb: Label3D = node.get_child(0)
		lb.text = str(Core.ANCHORS[k]) + ("" if anchors.has(k) else " (auto)")


func _update_gizmo() -> void:
	var im := ImmediateMesh.new()
	_gizmo.mesh = im
	var p := _primary()
	if p < 0 or fpp:
		return
	var m: Dictionary = data["modules"][p]
	var xf := _gun_holder.global_transform * Core.module_xform(data, m)
	var o := xf.origin
	var L := clampf(_dist * 0.12, 0.02, 0.3)
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var axes := [[Vector3.RIGHT, UI.RED, "x"], [Vector3.UP, UI.GREEN, "y"], [Vector3.BACK, UI.BLUE, "z"]]
	for ax in axes:
		var c: Color = ax[1]
		if _xform_axis != "" and _xform_axis != ax[2]:
			c.a = 0.25
		im.surface_set_color(c)
		im.surface_add_vertex(o)
		im.surface_add_vertex(o + (ax[0] as Vector3) * L)
	# obrys zaznaczenia: oś lokalna modułu (cienka)
	for ax in axes:
		im.surface_set_color(Color((ax[1] as Color), 0.45))
		im.surface_add_vertex(o)
		im.surface_add_vertex(o + xf.basis * (ax[0] as Vector3) * L * 0.6)
	if _xform_axis != "":
		var axv: Vector3 = {"x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK}[_xform_axis]
		im.surface_set_color(Color(1, 1, 1, 0.5))
		im.surface_add_vertex(o - axv * 2.0)
		im.surface_add_vertex(o + axv * 2.0)
	im.surface_end()


func _update_stats() -> void:
	if _stats == null:
		return
	var tris := 0
	var box := AABB()
	var first := true
	for mi in _module_nodes():
		var mesh: ArrayMesh = (mi as MeshInstance3D).mesh
		tris += mesh.surface_get_array_len(0) / 3
		var b: AABB = mi.global_transform * mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var shape := Core.inventory_shape(data)
	_stats.text = "%d modułów · %d trójkątów\n%.0f × %.0f × %.0f mm · ok. %.2f kg\nekwipunek: %d×%d pól" % [
		(data.get("modules", []) as Array).size(), tris, box.size.x * 1000.0, box.size.y * 1000.0, box.size.z * 1000.0,
		Core.estimate_mass(data), str(shape[0]).length(), shape.size()]


# =====================================================================================
# dane: projekt, zaznaczenie, historia
# =====================================================================================

func new_project(template_key: String) -> void:
	data = Templates.make(template_key)
	sel = []
	anim_step = ""
	_history = []
	_hist_i = -1
	_commit()
	dirty = false
	_after_load()
	_status_msg("Nowy projekt z szablonu: " + str(Templates.LIST.get(template_key, {}).get("label", template_key)))


func open_project(id: String) -> void:
	Core.forget(id)
	var d := Core.load_project(id)
	if d.is_empty():
		_status_msg("Nie ma projektu " + id)
		return
	data = d.duplicate(true)
	sel = []
	anim_step = ""
	_history = []
	_hist_i = -1
	_commit()
	dirty = false
	_after_load()
	_status_msg("Otwarto: data/warsztat/%s.json" % id)


func _after_load() -> void:
	if _title_edit != null:
		_title_edit.text = str(data.get("pl", ""))
	_fill_files()
	_rebuild_now()
	frame_selection()
	_refresh_panels()


func save_project(path: String = "") -> bool:
	data["version"] = 2
	var id := str(data.get("id", "")).strip_edges().to_lower().replace(" ", "_")
	if id == "":
		id = "projekt"
	data["id"] = id
	if str(data.get("en", "")) == "":
		data["en"] = data.get("pl", id)
	var item: Dictionary = data.get("item", {})
	if str(data.get("replace", "")) == "":
		item["short_pl"] = data.get("pl", id)
		item["short_en"] = data.get("en", id)
		if not item.has("shape"):
			item["shape"] = Core.inventory_shape(data)
		if not item.has("weight"):
			item["weight"] = Core.estimate_mass(data)
		if str(data.get("kind", "")) == "gun":
			item["grip"] = "gun"
	data["item"] = item
	var ok := Core.save_project(data, path)
	if ok:
		dirty = false
		ItemDB.defs = {}  # gra wczyta przedmioty od nowa (z tym projektem)
		_status_msg(("Zapisano %s. W grze: %s." % [path if path != "" else "data/warsztat/%s.json" % id,
				("podmieniony model przedmiotu „%s”" % data["replace"]) if str(data.get("replace", "")) != "" else "przedmiot o id „%s”" % id]))
		_fill_files()
	else:
		_status_msg("Nie udało się zapisać pliku.")
	return ok


func _commit() -> void:
	_commit_timer = -1.0
	var snap := JSON.stringify(data)
	if _hist_i >= 0 and _hist_i < _history.size() and _history[_hist_i] == snap:
		return
	_history.resize(_hist_i + 1)
	_history.append(snap)
	if _history.size() > 200:
		_history.pop_front()
	_hist_i = _history.size() - 1


func undo() -> void:
	if _commit_timer >= 0.0:
		_commit()
	if _hist_i <= 0:
		_status_msg("Nie ma czego cofnąć")
		return
	_hist_i -= 1
	_restore_history()
	_status_msg("Cofnięto (%d/%d)" % [_hist_i + 1, _history.size()])


func redo() -> void:
	if _hist_i >= _history.size() - 1:
		_status_msg("Nie ma czego powtórzyć")
		return
	_hist_i += 1
	_restore_history()
	_status_msg("Powtórzono (%d/%d)" % [_hist_i + 1, _history.size()])


func _restore_history() -> void:
	var d = JSON.parse_string(_history[_hist_i])
	if typeof(d) != TYPE_DICTIONARY:
		return
	data = d
	sel = sel.filter(func(i): return i < (data["modules"] as Array).size())
	dirty = true
	_rebuild_now()
	_refresh_panels()


func _primary() -> int:
	if sel.is_empty():
		return -1
	var p := int(sel[sel.size() - 1])
	return p if p < (data.get("modules", []) as Array).size() else -1


func select(i: int, additive: bool = false) -> void:
	if i < 0:
		sel = []
	elif additive:
		if sel.has(i):
			sel.erase(i)
		else:
			sel.append(i)
	else:
		sel = [i]
	_rebuild_now()
	_refresh_panels()


func add_module(type: String) -> int:
	var m := Core.default_module(type)
	var p := _primary()
	if p >= 0:
		# nowy moduł obok zaznaczonego: łatwiej go znaleźć
		var base: Array = data["modules"][p]["pos"]
		m["pos"] = [float(base[0]) + 0.03, float(base[1]), float(base[2])]
		m["parent"] = data["modules"][p].get("parent", "")
	data["modules"].append(m)
	var idx: int = data["modules"].size() - 1
	sel = [idx]
	_touch()
	_commit()
	_rebuild_now()
	_refresh_panels()
	_status_msg("Dodano moduł: " + str(m["name"]))
	return idx


func delete_selected() -> void:
	if sel.is_empty():
		return
	var uids: Array = []
	var order := sel.duplicate()
	order.sort()
	order.reverse()
	for i in order:
		uids.append(str(data["modules"][i].get("uid", "")))
		data["modules"].remove_at(i)
	# dzieci usuniętych przypinamy do korzenia (zachowując położenie)
	for m in data["modules"]:
		if uids.has(str(m.get("parent", ""))):
			m["parent"] = ""
	sel = []
	_touch()
	_commit()
	_rebuild_now()
	_refresh_panels()
	_status_msg("Usunięto %d moduł(y)" % order.size())


func duplicate_selected(offset: Vector3 = Vector3(0.02, 0, 0)) -> void:
	if sel.is_empty():
		return
	var new_sel: Array = []
	var remap := {}
	var copies: Array = []
	for i in sel:
		var m: Dictionary = (data["modules"][i] as Dictionary).duplicate(true)
		var old := str(m.get("uid", ""))
		m["uid"] = Core.new_uid()
		remap[old] = m["uid"]
		m["name"] = str(m.get("name", "")) + " (kopia)"
		copies.append(m)
	for m in copies:
		if remap.has(str(m.get("parent", ""))):
			m["parent"] = remap[str(m["parent"])]
		else:
			var p: Array = m["pos"]
			m["pos"] = [float(p[0]) + offset.x, float(p[1]) + offset.y, float(p[2]) + offset.z]
		data["modules"].append(m)
		new_sel.append(data["modules"].size() - 1)
	sel = new_sel
	_touch()
	_commit()
	_rebuild_now()
	_refresh_panels()


func copy_selected() -> void:
	if sel.is_empty():
		return
	var mods: Array = []
	for i in sel:
		mods.append(data["modules"][i])
	DisplayServer.clipboard_set(JSON.stringify({"pracownia_moduly": mods}))
	_status_msg("Skopiowano %d moduł(y) do schowka (można wkleić w innym projekcie)" % mods.size())


func paste() -> void:
	var d = JSON.parse_string(DisplayServer.clipboard_get())
	if typeof(d) != TYPE_DICTIONARY or not d.has("pracownia_moduly"):
		_status_msg("W schowku nie ma modułów")
		return
	insert_modules(d["pracownia_moduly"])


func insert_modules(mods: Array) -> void:
	var remap := {}
	var start: int = data["modules"].size()
	var added: Array = []
	for src in mods:
		var m: Dictionary = (src as Dictionary).duplicate(true)
		var old := str(m.get("uid", ""))
		m["uid"] = Core.new_uid()
		remap[old] = m["uid"]
		added.append(m)
	for m in added:
		var pu := str(m.get("parent", ""))
		m["parent"] = remap.get(pu, "") if pu != "" else ""
		data["modules"].append(m)
	sel = range(start, data["modules"].size())
	_touch()
	_commit()
	_rebuild_now()
	_refresh_panels()
	_status_msg("Wstawiono %d moduł(y)" % added.size())


func move_selected(dir: int) -> void:
	var p := _primary()
	if p < 0:
		return
	var q := p + dir
	if q < 0 or q >= data["modules"].size():
		return
	var tmp = data["modules"][p]
	data["modules"][p] = data["modules"][q]
	data["modules"][q] = tmp
	sel = [q]
	_touch()
	_commit()
	_rebuild_now()
	_refresh_panels()


## Przypina zaznaczone moduły do modułu klikniętego jako ostatni (zachowuje położenie w świecie).
func parent_selected() -> void:
	if sel.size() < 2:
		_status_msg("Zaznacz moduły do przypięcia, a na końcu (Ctrl+klik) moduł-rodzica")
		return
	var parent_i := _primary()
	var parent_uid := str(data["modules"][parent_i].get("uid", ""))
	for i in sel:
		if i == parent_i:
			continue
		if _is_descendant(parent_i, str(data["modules"][i].get("uid", ""))):
			continue
		_set_parent_keep(i, parent_uid)
	_touch()
	_commit()
	_rebuild_now()
	_refresh_panels()
	_status_msg("Przypięto do: " + str(data["modules"][parent_i].get("name", "")))


func unparent_selected() -> void:
	for i in sel:
		_set_parent_keep(i, "")
	_touch()
	_commit()
	_rebuild_now()
	_refresh_panels()


func _is_descendant(i: int, ancestor_uid: String) -> bool:
	var m: Dictionary = data["modules"][i]
	var guard := 0
	while str(m.get("parent", "")) != "" and guard < 32:
		if str(m["parent"]) == ancestor_uid:
			return true
		var pi := Core.find_uid(data, str(m["parent"]))
		if pi < 0:
			return false
		m = data["modules"][pi]
		guard += 1
	return str(m.get("uid", "")) == ancestor_uid


func _set_parent_keep(i: int, parent_uid: String) -> void:
	var m: Dictionary = data["modules"][i]
	var world := Core.module_xform(data, m)
	m["parent"] = parent_uid
	var pxf := Transform3D.IDENTITY
	if parent_uid != "":
		var pi := Core.find_uid(data, parent_uid)
		if pi >= 0:
			pxf = Core.module_xform(data, data["modules"][pi])
	_set_local_xform(m, pxf.affine_inverse() * world)


func _set_local_xform(m: Dictionary, xf: Transform3D) -> void:
	var sc := xf.basis.get_scale()
	var e := xf.basis.orthonormalized().get_euler(EULER_ORDER_YXZ)
	m["pos"] = [snappedf(xf.origin.x, 0.0001), snappedf(xf.origin.y, 0.0001), snappedf(xf.origin.z, 0.0001)]
	m["rot"] = [snappedf(rad_to_deg(e.x), 0.01), snappedf(rad_to_deg(e.y), 0.01), snappedf(rad_to_deg(e.z), 0.01)]
	m["scale"] = [snappedf(sc.x, 0.001), snappedf(sc.y, 0.001), snappedf(sc.z, 0.001)]


func toggle_hidden(i: int) -> void:
	data["modules"][i]["hidden"] = not bool(data["modules"][i].get("hidden", false))
	_touch()
	_commit()
	_rebuild_now()
	_refresh_tree()


func set_param(i: int, key: String, v: float) -> void:
	data["modules"][i]["params"][key] = v
	_touch()


# =====================================================================================
# animacja: podgląd
# =====================================================================================

func _anim_all() -> Dictionary:
	return Anim.resolve(data.get("anim", {}), str(data.get("template", "item")))


func _anim_step_data(name: String) -> Dictionary:
	return _anim_all().get(name, {})


## Krok do edycji: przy pierwszej zmianie kopiujemy domyślny krok do pliku projektu.
func _anim_step_edit(name: String) -> Dictionary:
	if not data.has("anim"):
		data["anim"] = {}
	if not data["anim"].has(name):
		data["anim"][name] = (Anim.default_anim(str(data.get("template", "item"))).get(name, {"time": 0.5, "tracks": {}}) as Dictionary).duplicate(true)
	return data["anim"][name]


func _is_long() -> bool:
	if bool(data.get("item", {}).get("two_handed", false)):
		return true
	for m in data.get("modules", []):
		if str(m.get("type", "")) == "kolba":
			return true
	return false


func _apply_anim_pose() -> void:
	var step: Dictionary = _anim_step_data(anim_step) if anim_step != "" else {}
	var pose := Anim.pose(step, anim_t) if not step.is_empty() else {}
	# części ruchome
	var vis: Node = _model.get_child(0) if _model.get_child_count() > 0 else null
	if vis != null:
		for part in ["zamek", "czolenko", "magazynek", "lufy", "kurek", "beben"]:
			var n: Node3D = vis.get_node_or_null(part)
			if n == null:
				continue
			var rest: Transform3D = n.get_meta("rest")
			var v := float(pose.get(part, 0.0))
			match part:
				"zamek", "czolenko": n.transform = rest.translated(Vector3(-v, 0, 0))
				"magazynek": n.transform = rest.translated(Vector3(0, -v, 0))
				"lufy", "kurek": n.transform = rest * Transform3D(Basis(Vector3.BACK, -deg_to_rad(v)), Vector3.ZERO)
				"beben": n.transform = rest * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(v)), Vector3.ZERO)
	if not fpp:
		_gun_holder.transform = Transform3D.IDENTITY
		_hand_l.visible = false
		_hand_r.visible = false
		return
	var dv := Core.derived(data)
	var hip := HIP_LONG if _is_long() else HIP_PISTOL
	var p := hip
	if ads:
		var ad := float(data.get("item", {}).get("gun", {}).get("ads_dist", 0.34))
		p = Vector3(0.0, -float(dv["sight_y"]), -ad)
	p += Vector3(float(pose.get("x", 0.0)), float(pose.get("y", 0.0)), float(pose.get("z", 0.0)))
	var pitch := deg_to_rad(float(pose.get("pochyl", 0.0)))
	var yaw := deg_to_rad(float(pose.get("odchyl", 0.0))) + (-0.06 if _is_long() and not ads else 0.0)
	var roll := deg_to_rad(float(pose.get("przechyl", 0.0)))
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)).normalized()
	var hb := Basis.looking_at(dir, Vector3.UP)
	if absf(roll) > 0.0001:
		hb = Basis(dir, roll) * hb
	_gun_holder.transform = Transform3D(hb * Basis(Vector3.UP, PI / 2.0), p)
	_hand_r.visible = true
	_hand_r.transform = Transform3D(hb, p + hb * Vector3(0, -0.03, 0.02))
	var sup: Array = data.get("item", {}).get("gun", {}).get("support", [0.0, -0.03, 0.0])
	if dv.has("support"):
		sup = dv["support"]
	var left := Vector3(float(pose.get("lewa_x", sup[0])), float(pose.get("lewa_y", sup[1])), float(pose.get("lewa_z", sup[2])))
	_hand_l.visible = str(data.get("kind", "")) == "gun"
	_hand_l.transform = Transform3D(hb, p + hb * left)


func set_fpp(on: bool, aim: bool = false) -> void:
	fpp = on
	ads = aim
	_update_camera()
	_apply_anim_pose()
	_update_gizmo()


# =====================================================================================
# wejście: mysz i klawisze
# =====================================================================================

func _process(delta: float) -> void:
	if _rebuild_due:
		_rebuild_timer -= delta
		if _rebuild_timer <= 0.0:
			_rebuild_now()
			_rebuild_timer = 0.06
	if _commit_timer >= 0.0:
		_commit_timer -= delta
		if _commit_timer < 0.0:
			_commit()
	_autosave_timer += delta
	if _autosave_timer > 45.0:
		_autosave_timer = 0.0
		if dirty:
			var f := FileAccess.open(AUTOSAVE, FileAccess.WRITE)
			if f != null:
				f.store_string(JSON.stringify(data))
	for k in _anchor_nodes:
		var mk: Node3D = _anchor_nodes[k]
		if mk.visible:
			var d := _cam.global_position.distance_to(mk.global_position)
			mk.scale = Vector3.ONE * clampf(d * 0.55, 0.05, 6.0) * (1.6 if (tab == "animacja" and k == anchor_sel) else 1.0)
	if _ruler_label.visible:
		_ruler_label.pixel_size = 0.0012 * clampf(_cam.global_position.distance_to(_ruler_label.global_position), 0.05, 5.0)
	if playing and anim_step != "":
		var step := _anim_step_data(anim_step)
		var dur := maxf(0.05, float(step.get("time", 0.5)))
		anim_t += delta * play_speed / dur
		if anim_t > 1.0:
			if loop:
				anim_t = fmod(anim_t, 1.0)
			else:
				anim_t = 1.0
				playing = false
		if _timeline != null:
			_timeline.t = anim_t
			_timeline.queue_redraw()
		_apply_anim_pose()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if _handle_key(event as InputEventKey):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if _xform_mode != "":
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_xform_end(true)
			elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
				_xform_end(false)
			return
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_click(mb.position, mb.ctrl_pressed or mb.shift_pressed)
			MOUSE_BUTTON_RIGHT:
				_drag = 1 if mb.pressed else 0
			MOUSE_BUTTON_MIDDLE:
				_drag = (3 if mb.shift_pressed else 2) if mb.pressed else 0
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed and not fpp:
					_dist = maxf(0.04, _dist * 0.88)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed and not fpp:
					_dist = minf(6.0, _dist * 1.12)
		_update_camera()
		_update_gizmo()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _xform_mode != "":
			_xform_update(mm.position)
			return
		if _drag > 0 and not fpp:
			if _drag == 1 or _drag == 3:
				_yaw -= mm.relative.x * 0.008
				_pitch = clampf(_pitch + mm.relative.y * 0.008, -1.55, 1.55)
			else:
				var b := _cam.global_transform.basis
				_target += (-b.x * mm.relative.x + b.y * mm.relative.y) * _dist * 0.0011
			_update_camera()
			_update_gizmo()


func _handle_key(k: InputEventKey) -> bool:
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return false
	var ctrl := k.ctrl_pressed or k.meta_pressed
	if _xform_mode != "":
		match k.keycode:
			KEY_X, KEY_Y, KEY_Z:
				var ax := OS.get_keycode_string(k.keycode).to_lower()
				_xform_axis = "" if _xform_axis == ax else ax
				_xform_update(get_viewport().get_mouse_position())
				return true
			KEY_ENTER, KEY_KP_ENTER:
				_xform_end(true)
				return true
			KEY_ESCAPE:
				_xform_end(false)
				return true
		return true
	match k.keycode:
		KEY_Z:
			if ctrl:
				if k.shift_pressed:
					redo()
				else:
					undo()
				return true
		KEY_Y:
			if ctrl:
				redo()
				return true
		KEY_S:
			if ctrl:
				save_project()
				return true
			_xform_begin("scale")
			return true
		KEY_C:
			if ctrl:
				copy_selected()
				return true
		KEY_V:
			if ctrl:
				paste()
			else:
				set_fpp(not fpp, ads)
			return true
		KEY_D:
			if ctrl or k.shift_pressed:
				duplicate_selected()
				return true
		KEY_A:
			if ctrl:
				sel = range((data["modules"] as Array).size())
				_rebuild_now()
				_refresh_panels()
				return true
		KEY_G:
			_xform_begin("move")
			return true
		KEY_R:
			_xform_begin("rotate")
			return true
		KEY_DELETE, KEY_X:
			if k.keycode == KEY_X and not k.shift_pressed:
				return false
			if tab != "animacja":
				delete_selected()
				return true
		KEY_H:
			if k.alt_pressed:
				for m in data["modules"]:
					m["hidden"] = false
				_touch()
				_commit()
				_rebuild_now()
				_refresh_tree()
			else:
				for i in sel:
					toggle_hidden(int(i))
			return true
		KEY_F, KEY_KP_PERIOD:
			frame_selection()
			return true
		KEY_KP_1:
			view_preset("bok")
			return true
		KEY_KP_3:
			view_preset("przod")
			return true
		KEY_KP_7:
			view_preset("gora")
			return true
		KEY_KP_5, KEY_KP_0:
			view_preset("3/4")
			return true
		KEY_1, KEY_2, KEY_3, KEY_4:
			if not ctrl:
				set_tab(TABS[int(k.keycode - KEY_1)][0])
				return true
		KEY_SPACE:
			if tab == "animacja":
				playing = not playing
				return true
		KEY_F1, KEY_QUESTION, KEY_SLASH:
			_help.visible = not _help.visible
			return true
		KEY_ESCAPE:
			if _help.visible:
				_help.visible = false
			else:
				select(-1)
			return true
		KEY_PAGEUP:
			move_selected(-1)
			return true
		KEY_PAGEDOWN:
			move_selected(1)
			return true
		KEY_F12:
			screenshot()
			return true
	return false


func _ray(screen: Vector2) -> Dictionary:
	var from := _cam.project_ray_origin(screen)
	var to := from + _cam.project_ray_normal(screen) * 20.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	return get_world_3d().direct_space_state.intersect_ray(q)


func _click(pos: Vector2, additive: bool) -> void:
	var hit := _ray(pos)
	if _pick_anchor:
		_pick_anchor = false
		if not hit.is_empty():
			var local: Vector3 = _gun_holder.global_transform.affine_inverse() * (hit["position"] as Vector3)
			if not data.has("anchors"):
				data["anchors"] = {}
			data["anchors"][anchor_sel] = [snappedf(local.x, 0.0005), snappedf(local.y, 0.0005), snappedf(local.z, 0.0005)]
			_touch()
			_commit()
			_status_msg("Kotwica „%s” postawiona w %.1f, %.1f, %.1f mm" % [Core.ANCHORS[anchor_sel], local.x * 1000, local.y * 1000, local.z * 1000])
			_refresh_panels()
		return
	if _ruler_on:
		if hit.is_empty():
			return
		_ruler_pts.append(hit["position"])
		if _ruler_pts.size() > 2:
			_ruler_pts = [_ruler_pts[2]]
		_draw_ruler()
		return
	if hit.is_empty():
		if not additive:
			select(-1)
		return
	var col: Object = hit["collider"]
	if col != null and col.has_meta("module"):
		select(int(col.get_meta("module")), additive)


func _draw_ruler() -> void:
	var im := ImmediateMesh.new()
	_ruler.mesh = im
	_ruler_label.visible = false
	if _ruler_pts.is_empty():
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var a: Vector3 = _ruler_pts[0]
	var b: Vector3 = _ruler_pts[1] if _ruler_pts.size() > 1 else a
	for p in [a, b]:
		for ax in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			im.surface_add_vertex(p - ax * 0.004)
			im.surface_add_vertex(p + ax * 0.004)
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
	im.surface_end()
	if _ruler_pts.size() > 1:
		_ruler_label.visible = true
		_ruler_label.position = (a + b) * 0.5 + Vector3(0, 0.01, 0)
		var d := b - a
		_ruler_label.text = "%.1f mm\n(x %.1f  y %.1f  z %.1f)" % [d.length() * 1000.0, d.x * 1000.0, d.y * 1000.0, d.z * 1000.0]
		_status_msg("Linijka: %.1f mm" % (d.length() * 1000.0))


func _xform_begin(mode: String) -> void:
	if sel.is_empty() or fpp:
		return
	_xform_mode = mode
	_xform_axis = ""
	_xform_start = get_viewport().get_mouse_position()
	_xform_orig = []
	for i in sel:
		_xform_orig.append((data["modules"][i] as Dictionary).duplicate(true))
	_status_msg({"move": "Przesuwanie", "rotate": "Obrót", "scale": "Skala"}[mode] + ": rusz myszą · X/Y/Z: oś · LPM/Enter: zatwierdź · PPM/Esc: anuluj" + (" · Ctrl: bez przyciągania" if snap_on else ""))


func _xform_update(mouse: Vector2) -> void:
	var d := mouse - _xform_start
	var free := Input.is_key_pressed(KEY_CTRL) or not snap_on
	var vh := get_viewport().get_visible_rect().size.y
	var world_per_px := 2.0 * _dist * tan(deg_to_rad(_cam.fov * 0.5)) / maxf(1.0, vh)
	var b := _cam.global_transform.basis
	for k in sel.size():
		var i: int = sel[k]
		var orig: Dictionary = _xform_orig[k]
		var m: Dictionary = data["modules"][i]
		match _xform_mode:
			"move":
				var delta := (b.x * d.x - b.y * d.y) * world_per_px
				if _xform_axis != "":
					var axv: Vector3 = {"x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK}[_xform_axis]
					var sdir := _cam.unproject_position(Core.module_xform(data, orig).origin + axv * 0.1) - _cam.unproject_position(Core.module_xform(data, orig).origin)
					var along := d.dot(sdir.normalized()) * world_per_px if sdir.length() > 0.5 else 0.0
					delta = axv * along
				var pu := str(m.get("parent", ""))
				if pu != "":
					var pi := Core.find_uid(data, pu)
					if pi >= 0:
						delta = Core.module_xform(data, data["modules"][pi]).basis.inverse() * delta
				var op: Array = orig["pos"]
				var np := Vector3(float(op[0]), float(op[1]), float(op[2])) + delta
				if not free:
					np = np.snapped(Vector3.ONE * 0.001)
				m["pos"] = [np.x, np.y, np.z]
			"rotate":
				var ang := d.x * 0.4
				if not free:
					ang = snappedf(ang, 5.0)
				var axis := _xform_axis if _xform_axis != "" else "z"
				var r: Array = (orig["rot"] as Array).duplicate()
				var ci: int = {"x": 0, "y": 1, "z": 2}[axis]
				r[ci] = wrapf(float(r[ci]) + ang, -180.0, 180.0)
				m["rot"] = r
			"scale":
				var f := maxf(0.05, 1.0 + d.x * 0.005)
				if not free:
					f = snappedf(f, 0.05)
				var s: Array = (orig["scale"] as Array).duplicate()
				for c in 3:
					if _xform_axis == "" or {"x": 0, "y": 1, "z": 2}[_xform_axis] == c:
						s[c] = float(s[c]) * f
				m["scale"] = s
	_rebuild_now()


func _xform_end(accept: bool) -> void:
	if not accept:
		for k in sel.size():
			data["modules"][sel[k]] = _xform_orig[k]
	_xform_mode = ""
	_xform_axis = ""
	_rebuild_now()
	if accept:
		_touch(false)
		_commit()
		_refresh_panels()
	_status_msg("Zatwierdzono" if accept else "Anulowano")


# =====================================================================================
# zrzuty
# =====================================================================================

func screenshot(name: String = "") -> String:
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s_%s.png" % [SHOTS_DIR, str(data.get("id", "projekt")), name if name != "" else str(Time.get_unix_time_from_system()).replace(".", "")]
	img.save_png(path)
	_status_msg("Zrzut: " + ProjectSettings.globalize_path(path))
	return path


## Arkusz 8 ujęć dookoła modelu (bez interfejsu).
func turntable() -> void:
	var keep := [_yaw, _pitch, fpp]
	fpp = false
	_root.visible = false
	_frame_all()
	var tiles: Array = []
	for k in 8:
		_yaw = TAU * float(k) / 8.0
		_pitch = -0.25
		_update_camera()
		_update_gizmo()
		for f in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(480, int(480.0 * img.get_height() / img.get_width()))
		tiles.append(img)
	_root.visible = true
	var tw: int = tiles[0].get_width()
	var th: int = tiles[0].get_height()
	var sheet := Image.create(tw * 4, th * 2, false, tiles[0].get_format())
	for k in 8:
		sheet.blit_rect(tiles[k], Rect2i(0, 0, tw, th), Vector2i((k % 4) * tw, (k / 4) * th))
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	var path := "%s/%s_obrot.png" % [SHOTS_DIR, str(data.get("id", "projekt"))]
	sheet.save_png(path)
	_yaw = keep[0]
	_pitch = keep[1]
	fpp = keep[2]
	_update_camera()
	_update_gizmo()
	_status_msg("Arkusz obrotu: " + ProjectSettings.globalize_path(path))


## Zrzuty do dokumentacji (argument --zrzut-pracowni=folder).
func _doc_screenshots(dir: String) -> void:
	for f in 8:
		await get_tree().process_frame
	var shots := [["skladanie", "pistolet", -1, false], ["modelowanie", "siekiera", 1, false], ["tekstury", "dwururka", 1, false], ["animacja", "dwururka", -1, true]]
	for s in shots:
		if s[1] == "dwururka":
			open_project("dwururka")
		else:
			new_project(str(s[1]))
		if int(s[2]) >= 0:
			select(int(s[2]))
		set_tab(str(s[0]))
		view_preset("3/4")
		if int(s[2]) < 0:
			_frame_all()
		else:
			frame_selection()
		if s[3]:
			_select_step("open")
			anim_t = 0.75
			_timeline.t = anim_t
			set_fpp(true)
		apply_light(0)
		for f in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/pracownia_%s.png" % [dir, s[0]])
	# modele z szablonów w świetle nocy i żarówki
	set_tab("skladanie")
	var gallery := ["mlotek", "noz", "lom", "karabinek", "obrzyn", "strzelba"]
	_set_toggle(1, false)
	for g in gallery:
		new_project(g)
		select(-1)
		view_preset("3/4")
		_root.visible = false
		_frame_all()
		for f in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/pracownia_model_%s.png" % [dir, g])
		_root.visible = true
	_set_toggle(1, true)
	_update_camera()
	open_project("dwururka")
	set_tab("tekstury")
	_frame_all()
	for li in [3, 4]:
		apply_light(li)
		for f in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/pracownia_swiatlo_%d.png" % [dir, li])
	get_tree().quit()


func _frame_all() -> void:
	var keep := sel.duplicate()
	sel = []
	frame_selection()
	sel = keep


# =====================================================================================
# interfejs: szkielet
# =====================================================================================

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UI.theme()
	layer.add_child(_root)

	# --- górny pasek
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", UI.box(Color(0.07, 0.07, 0.075, 0.98), UI.LINE, 0, 10))
	top.anchor_right = 1.0
	top.offset_bottom = 46
	_root.add_child(top)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 8)
	top.add_child(th)
	var logo := Label.new()
	logo.text = "PRACOWNIA"
	logo.add_theme_font_size_override("font_size", 20)
	logo.add_theme_color_override("font_color", UI.ACCENT)
	th.add_child(logo)
	var sub := Label.new()
	sub.text = "PSK-12"
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", UI.DIM)
	th.add_child(sub)
	th.add_child(VSeparator.new())
	for t in TABS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		var key: String = t[0]
		b.pressed.connect(func(): set_tab(key))
		th.add_child(b)
		_tab_buttons[key] = b
	var spacer := Control.new()
	UI.grow(spacer)
	th.add_child(spacer)
	_title_edit = LineEdit.new()
	_title_edit.custom_minimum_size = Vector2(180, 0)
	_title_edit.placeholder_text = "Nazwa w grze"
	_title_edit.text_changed.connect(func(t): data["pl"] = t; _touch(false))
	th.add_child(_title_edit)
	_files_opt = OptionButton.new()
	_files_opt.focus_mode = Control.FOCUS_NONE
	_files_opt.custom_minimum_size = Vector2(150, 0)
	_files_opt.tooltip_text = "Projekty w data/warsztat"
	th.add_child(_files_opt)
	UI.button(th, "Otwórz", func(): if _files_opt.selected >= 0: open_project(_files_opt.get_item_text(_files_opt.selected)), "Otwórz wybrany projekt")
	UI.button(th, "↶", func(): undo(), "Cofnij (Ctrl+Z)")
	UI.button(th, "↷", func(): redo(), "Powtórz (Ctrl+Y)")
	var save_b := UI.button(th, "Zapisz", func(): save_project(), "Zapisz do data/warsztat (Ctrl+S)")
	save_b.add_theme_color_override("font_color", UI.ACCENT)
	UI.button(th, "▶ Testuj w grze", func(): test_in_game(), "Zapisz i uruchom grę z tym przedmiotem w ręku (F10 w grze wraca tutaj)")
	UI.button(th, "?", func(): _help.visible = not _help.visible, "Skróty klawiszowe (F1)")

	# --- lewy i prawy panel
	_left_panel = PanelContainer.new()
	_left_panel.anchor_bottom = 1.0
	_left_panel.offset_left = 8
	_left_panel.offset_top = 54
	_left_panel.offset_right = 318
	_left_panel.offset_bottom = -34
	_root.add_child(_left_panel)
	var lsc := ScrollContainer.new()
	lsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_left_panel.add_child(lsc)
	_left = VBoxContainer.new()
	UI.grow(_left)
	_left.custom_minimum_size.x = 286
	lsc.add_child(_left)
	_right_panel = PanelContainer.new()
	_right_panel.anchor_left = 1.0
	_right_panel.anchor_right = 1.0
	_right_panel.anchor_bottom = 1.0
	_right_panel.offset_left = -368
	_right_panel.offset_right = -8
	_right_panel.offset_top = 54
	_right_panel.offset_bottom = -34
	_root.add_child(_right_panel)
	var rsc := ScrollContainer.new()
	rsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_right_panel.add_child(rsc)
	_right = VBoxContainer.new()
	UI.grow(_right)
	_right.custom_minimum_size.x = 334
	rsc.add_child(_right)

	# --- dolny panel (oś czasu w animacji)
	_bottom = PanelContainer.new()
	_bottom.anchor_top = 1.0
	_bottom.anchor_bottom = 1.0
	_bottom.anchor_right = 1.0
	_bottom.offset_left = 326
	_bottom.offset_right = -376
	_bottom.offset_top = -260
	_bottom.offset_bottom = -34
	_bottom.visible = false
	_root.add_child(_bottom)
	_bottom_box = VBoxContainer.new()
	_bottom.add_child(_bottom_box)

	# --- pasek widoku nad podglądem
	var vb := PanelContainer.new()
	vb.add_theme_stylebox_override("panel", UI.box(Color(0.07, 0.07, 0.075, 0.85), UI.LINE, 6, 6))
	vb.position = Vector2(326, 54)
	_root.add_child(vb)
	_view_bar = HBoxContainer.new()
	vb.add_child(_view_bar)
	var lo := UI.option(_view_bar, range(LIGHTS.size()), "0", func(i): apply_light(int(i)), {})
	for i in LIGHTS.size():
		lo.set_item_text(i, "☀ " + LIGHTS[i])
	lo.tooltip_text = "Oświetlenie podglądu: sprawdź model w dzień, w nocy z latarką i przy żarówce"
	var views := [["Z boku   (Num 1)", "bok"], ["Z przodu   (Num 3)", "przod"], ["Z góry   (Num 7)", "gora"], ["Z tyłu", "tyl"], ["3/4   (Num 5)", "3/4"],
			["Z oczu: z biodra   (V)", "fpp"], ["Z oczu: celowanie", "ads"], ["Kadruj zaznaczenie   (F)", "frame"]]
	var vm := MenuButton.new()
	vm.text = "Widok ▾"
	vm.flat = false
	vm.focus_mode = Control.FOCUS_NONE
	for v in views:
		vm.get_popup().add_item(v[0])
	vm.get_popup().id_pressed.connect(func(id):
		var key: String = views[id][1]
		if key == "fpp":
			set_fpp(true, false)
		elif key == "ads":
			set_fpp(true, true)
		elif key == "frame":
			frame_selection()
		else:
			view_preset(key))
	_view_bar.add_child(vm)
	var sm := MenuButton.new()
	sm.text = "Pokaż ▾"
	sm.flat = false
	sm.focus_mode = Control.FOCUS_NONE
	var sp := sm.get_popup()
	sp.hide_on_checkable_item_selection = false
	var toggles := [["Siatka i podłoże", true], ["Kotwice i chwyt", true], ["Przyciąganie (1 mm, 5°)", true], ["Linijka (kliknij 2 punkty)", false], ["Wygląd PSX (drgania)", false]]
	for t in toggles:
		sp.add_check_item(t[0])
		sp.set_item_checked(sp.item_count - 1, t[1])
	sp.id_pressed.connect(func(id):
		var on := not sp.is_item_checked(id)
		sp.set_item_checked(id, on)
		_set_toggle(id, on))
	_view_bar.add_child(sm)
	var shm := MenuButton.new()
	shm.text = "Zrzut ▾"
	shm.flat = false
	shm.focus_mode = Control.FOCUS_NONE
	shm.get_popup().add_item("Zrzut podglądu   (F12)")
	shm.get_popup().add_item("Arkusz obrotu 360° (8 ujęć)")
	shm.get_popup().id_pressed.connect(func(id):
		if id == 0:
			screenshot()
		else:
			turntable())
	_view_bar.add_child(shm)
	var fl := UI.button(_view_bar, "Z oczu", func(): set_fpp(not fpp, false), "Podgląd tak, jak w grze (V)")
	fl.toggle_mode = false

	# --- statystyki
	_stats = Label.new()
	_stats.anchor_left = 1.0
	_stats.anchor_right = 1.0
	_stats.anchor_top = 1.0
	_stats.anchor_bottom = 1.0
	_stats.offset_left = -600
	_stats.offset_right = -384
	_stats.offset_top = -100
	_stats.offset_bottom = -40
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stats.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_stats.add_theme_font_size_override("font_size", 12)
	_stats.add_theme_color_override("font_color", UI.DIM)
	_root.add_child(_stats)

	# --- pasek stanu
	var sb := PanelContainer.new()
	sb.add_theme_stylebox_override("panel", UI.box(Color(0.06, 0.06, 0.065, 0.98), UI.LINE, 0, 8))
	sb.anchor_top = 1.0
	sb.anchor_bottom = 1.0
	sb.anchor_right = 1.0
	sb.offset_top = -28
	_root.add_child(sb)
	var sbh := HBoxContainer.new()
	sb.add_child(sbh)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.clip_text = true
	UI.grow(_status)
	sbh.add_child(_status)
	_restore_btn = UI.button(sbh, "Przywróć autozapis", func(): _restore_autosave(), "Ostatni autozapis (co 45 s, gdy są niezapisane zmiany)")
	_restore_btn.visible = false
	var keys := Label.new()
	keys.text = "PPM obrót · środkowy przesuw · kółko zoom · LPM zaznacz (Ctrl: kilka) · G/R/S przesuń/obróć/skaluj · F kadruj · F1 skróty"
	keys.add_theme_font_size_override("font_size", 11)
	keys.add_theme_color_override("font_color", UI.DIM)
	sbh.add_child(keys)

	_build_help()


func _set_toggle(id: int, on: bool) -> void:
	match id:
		0:
			_show_grid = on
			_grid.visible = on
			_ground.visible = on
		1:
			_show_anchors = on
			_update_markers()
		2:
			snap_on = on
		3:
			_ruler_on = on
			_ruler_pts = []
			_draw_ruler()
		4:
			_psx = on
			Psx.set_style(3.0 if on else 0.0, 0.0)


func _build_help() -> void:
	_help = PanelContainer.new()
	_help.set_anchors_preset(Control.PRESET_CENTER)
	_help.offset_left = -330
	_help.offset_right = 330
	_help.offset_top = -270
	_help.offset_bottom = 270
	_help.visible = false
	_root.add_child(_help)
	var v := VBoxContainer.new()
	_help.add_child(v)
	UI.header(v, "Skróty Pracowni", true)
	var rows := [
		["1 2 3 4", "zakładki: Składanie, Modelowanie, Teksturowanie, Animacja"],
		["LPM / Ctrl+LPM", "zaznacz moduł / dodaj do zaznaczenia"],
		["PPM, środkowy, kółko", "obrót, przesuwanie i przybliżanie widoku"],
		["G · R · S", "przesuń · obróć · skaluj myszą; X/Y/Z wybiera oś, LPM zatwierdza, PPM anuluje"],
		["Ctrl (w trakcie G/R/S)", "chwilowo bez przyciągania do 1 mm / 5°"],
		["Ctrl+D / Shift+D", "duplikuj zaznaczone"],
		["Ctrl+C / Ctrl+V", "kopiuj / wklej moduły (także między projektami)"],
		["Delete", "usuń zaznaczone"],
		["H / Alt+H", "ukryj zaznaczone / pokaż wszystko"],
		["F", "kadruj zaznaczenie (bez zaznaczenia: całość)"],
		["Num 1 / 3 / 7 / 5", "widok z boku / z przodu / z góry / 3/4"],
		["V", "podgląd z oczu postaci (jak w grze)"],
		["PageUp / PageDown", "przesuń moduł w kolejności"],
		["Ctrl+Z / Ctrl+Y", "cofnij / powtórz (200 kroków)"],
		["Ctrl+S", "zapisz projekt (gra wczyta go sama)"],
		["Spacja", "odtwórz krok animacji"],
		["F12", "zrzut podglądu do user://pracownia"],
	]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	v.add_child(grid)
	for r in rows:
		var a := Label.new()
		a.text = r[0]
		a.add_theme_color_override("font_color", UI.ACCENT)
		grid.add_child(a)
		var b := Label.new()
		b.text = r[1]
		grid.add_child(b)
	UI.hint(v, "Układ modelu: X do przodu (lufa), Y w górę, Z w prawo. Czerwony punkt „Chwyt” to miejsce prawej dłoni. Narzędzia: oś X wzdłuż trzonka, chwyt w początku układu.")
	UI.button(v, "Zamknij", func(): _help.visible = false)


func _status_msg(t: String) -> void:
	if _status != null:
		_status.text = t


func _fill_files() -> void:
	if _files_opt == null:
		return
	_files_opt.clear()
	var files := Core.list_files()
	for f in files:
		_files_opt.add_item(f)
		if f == str(data.get("id", "")):
			_files_opt.select(_files_opt.item_count - 1)


func _restore_autosave() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(AUTOSAVE))
	if typeof(d) == TYPE_DICTIONARY:
		data = Core.upgrade(d)
		sel = []
		_commit()
		_after_load()
		_status_msg("Przywrócono autozapis")
	_restore_btn.visible = false


func set_tab(t: String) -> void:
	tab = t
	for k in _tab_buttons:
		(_tab_buttons[k] as Button).button_pressed = k == t
	_bottom.visible = t == "animacja"
	if t != "animacja":
		playing = false
		anim_t = 0.0
		if fpp:
			set_fpp(false)
	elif anim_step == "":
		var steps: Array = Anim.STEPS.get(str(data.get("template", "item")), [])
		if not steps.is_empty():
			anim_step = steps[0]
	_update_camera()
	_rebuild_now()
	_refresh_panels()


func _refresh_panels() -> void:
	if _left == null:
		return
	UI.clear(_left)
	UI.clear(_right)
	_tree = null
	_profile = null
	match tab:
		"skladanie": _panel_compose()
		"modelowanie": _panel_model()
		"tekstury": _panel_texture()
		"animacja": _panel_anim()
	_update_markers()


# =====================================================================================
# zakładka 1: składanie
# =====================================================================================

func _panel_compose() -> void:
	UI.header(_left, "Zacznij od szablonu")
	for cat in ["Broń", "Narzędzia", "Ogólne"]:
		var lab := Label.new()
		lab.text = cat
		lab.add_theme_color_override("font_color", UI.DIM)
		lab.add_theme_font_size_override("font_size", 12)
		_left.add_child(lab)
		var grid := GridContainer.new()
		grid.columns = 2
		_left.add_child(grid)
		for key in Templates.LIST:
			var spec: Dictionary = Templates.LIST[key]
			if str(spec["cat"]) != cat:
				continue
			var b := Button.new()
			b.text = str(spec["label"])
			b.tooltip_text = str(spec["desc"]) + "\n(niezapisane zmiany obecnego projektu przepadną — najpierw Ctrl+S)"
			b.custom_minimum_size = Vector2(136, 34)
			b.focus_mode = Control.FOCUS_NONE
			var k2: String = key
			b.pressed.connect(func(): new_project(k2))
			grid.add_child(b)
	UI.header(_left, "Zestawy modułów")
	UI.hint(_left, "Zapisz zaznaczone moduły (np. komplet przyrządów celowniczych) i wstawiaj je w innych projektach.")
	var presets := Templates.list_presets()
	if presets.is_empty():
		UI.hint(_left, "Brak zapisanych zestawów.")
	for p in presets:
		var r := UI.row(_left)
		var l := Label.new()
		l.text = p
		UI.grow(l)
		r.add_child(l)
		var pn: String = p
		UI.button(r, "Wstaw", func(): insert_modules(Templates.load_preset(pn)))
	var pr := UI.row(_left)
	var pname := LineEdit.new()
	pname.placeholder_text = "nazwa zestawu"
	UI.grow(pname)
	pr.add_child(pname)
	UI.button(pr, "Zapisz zaznaczone", func():
		if sel.is_empty() or pname.text.strip_edges() == "":
			_status_msg("Zaznacz moduły i wpisz nazwę zestawu")
			return
		var mods: Array = []
		for i in sel:
			mods.append(data["modules"][i])
		if Templates.save_preset(pname.text.strip_edges().replace(" ", "_"), mods):
			_status_msg("Zapisano zestaw " + pname.text)
		_refresh_panels())

	# --- prawa: projekt i szybkie suwaki
	UI.header(_right, "Projekt")
	var idr := UI.row(_right)
	var idl := Label.new()
	idl.text = "Id pliku"
	idl.custom_minimum_size.x = 90
	idr.add_child(idl)
	var ide := LineEdit.new()
	ide.text = str(data.get("id", ""))
	UI.grow(ide)
	ide.text_changed.connect(func(t): data["id"] = t.strip_edges().to_lower().replace(" ", "_"); _touch(false))
	idr.add_child(ide)
	var enr := UI.row(_right)
	var enl := Label.new()
	enl.text = "Nazwa (EN)"
	enl.custom_minimum_size.x = 90
	enr.add_child(enl)
	var ene := LineEdit.new()
	ene.text = str(data.get("en", ""))
	UI.grow(ene)
	ene.text_changed.connect(func(t): data["en"] = t; _touch(false))
	enr.add_child(ene)
	var kr := UI.row(_right)
	UI.option(kr, ["gun", "item"], str(data.get("kind", "item")), func(v): data["kind"] = v; _touch(); _refresh_panels(),
			{"gun": "Broń palna", "item": "Przedmiot / narzędzie"})
	UI.option(kr, ["semi", "pump", "break", "item"], str(data.get("template", "item")), func(v):
		data["template"] = v
		anim_step = ""
		_touch(false)
		_commit()
		_refresh_panels(), {"semi": "Półautomat", "pump": "Pompka", "break": "Łamana", "item": "Bez animacji"}).tooltip_text = "Szablon działania: kroki animacji i zachowanie w grze"
	UI.hint(_right, "Podmiana modelu: projekt nie tworzy nowego przedmiotu, tylko zmienia wygląd istniejącego (dane, waga i działanie zostają).")
	ItemDB.ensure_loaded()
	var ids: Array = ItemDB.defs.keys()
	ids.sort()
	var opts: Array = [""]
	opts.append_array(ids)
	var labels := {"": "— nowy przedmiot —"}
	for i in ids:
		labels[i] = "%s (%s)" % [ItemDB.name_of(str(i)), i]
	UI.option(_right, opts, str(data.get("replace", "")), func(v): data["replace"] = str(v); _touch(false); _commit(), labels)

	UI.header(_right, "Szybkie zmiany całości")
	var base := data.duplicate(true)
	UI.slider(_right, "Skala całości", 0.5, 1.6, 1.0, func(v): _scale_all(base, v); _touch(), "x", 0.01,
			"Mnoży wymiary i położenia wszystkich modułów względem stanu z chwili otwarcia zakładki")
	var barrel := -1
	for i in (data["modules"] as Array).size():
		if str(data["modules"][i]["type"]) == "lufy":
			barrel = i
			break
	if barrel >= 0:
		var L0 := Core.param(base["modules"][barrel], "dlugosc")
		UI.slider(_right, "Długość lufy", 0.08, 0.9, L0, func(v): _barrel_length(base, barrel, v); _touch(), "m", 0.001,
				"Wydłuża lufę i przesuwa wszystko, co leży przy jej końcu (muszka, czoło, obejmy)")
	var avg := _avg_wear()
	UI.slider(_right, "Zużycie (przetarcia krawędzi)", 0.0, 1.0, float(avg["zuzycie"]), func(v): _wear_all("zuzycie", v), "%")
	UI.slider(_right, "Brud we wgłębieniach", 0.0, 1.0, float(avg["brud"]), func(v): _wear_all("brud", v), "%")
	UI.slider(_right, "Rdza", 0.0, 1.0, float(avg["rdza"]), func(v): _wear_all("rdza", v), "%")
	var fr := UI.row(_right)
	var woods := ["drewno", "drewno_jasne", "drewno_ciemne", "bakelit", "polimer"]
	var wlab := {}
	for w in woods:
		wlab[w] = Mats.label(w)
	UI.option(fr, woods, "", func(v): _swap_mats(["drewno", "drewno_jasne", "drewno_ciemne", "bakelit", "polimer"], str(v)), wlab).tooltip_text = "Okładziny i kolby: zamień materiał wszystkich naraz"
	var metals := ["stal", "parkeryzowana", "chrom", "stal_grawer", "rdza"]
	var mlab := {}
	for w in metals:
		mlab[w] = Mats.label(w)
	UI.option(fr, metals, "", func(v): _swap_mats(["stal", "parkeryzowana", "chrom", "stal_grawer", "rdza"], str(v)), mlab).tooltip_text = "Wykończenie metalu wszystkich części stalowych"
	UI.header(_right, "Przedmiot w grze")
	var shape := Core.inventory_shape(data)
	UI.hint(_right, "Masa z objętości: ok. %.2f kg · ekwipunek z wymiarów: %d×%d" % [Core.estimate_mass(data), str(shape[0]).length(), shape.size()])
	var ar := UI.row(_right)
	UI.button(ar, "Ustaw masę", func(): data["item"]["weight"] = Core.estimate_mass(data); _touch(false); _commit(); _status_msg("Masa: %.2f kg" % data["item"]["weight"]))
	UI.button(ar, "Ustaw kształt", func(): data["item"]["shape"] = Core.inventory_shape(data); _touch(false); _commit(); _status_msg("Kształt w ekwipunku: " + str(data["item"]["shape"])))
	if str(data.get("kind", "")) == "gun":
		var g: Dictionary = data["item"].get("gun", {})
		if not data["item"].has("gun"):
			data["item"]["gun"] = g
		UI.slider(_right, "Obrażenia", 5.0, 150.0, float(g.get("damage", 40.0)), func(v): g["damage"] = v; _touch(false), "n")
		UI.slider(_right, "Rozrzut z biodra", 0.0, 0.2, float(g.get("spread_hip", 0.04)), func(v): g["spread_hip"] = v; _touch(false), "", 0.001)
		UI.slider(_right, "Rozrzut przy celowaniu", 0.0, 0.1, float(g.get("spread_ads", 0.01)), func(v): g["spread_ads"] = v; _touch(false), "", 0.001)
		UI.slider(_right, "Odległość celowania (oko-przyrządy)", 0.15, 0.6, float(g.get("ads_dist", 0.34)), func(v): g["ads_dist"] = v; _touch(false), "m", 0.005)
		UI.slider(_right, "Obniżenie przy celowaniu", -0.02, 0.04, float(g.get("ads_drop", 0.0)), func(v): g["ads_drop"] = v; _touch(false), "m", 0.0005,
				"Przesuwa broń niżej przy oku, żeby kolba mniej zasłaniała")
	var big := UI.button(_right, "Zapisz i testuj w grze  ▶", func(): test_in_game())
	big.custom_minimum_size.y = 40
	big.add_theme_color_override("font_color", UI.ACCENT)


func _scale_all(base: Dictionary, f: float) -> void:
	for i in mini((base["modules"] as Array).size(), (data["modules"] as Array).size()):
		var bm: Dictionary = base["modules"][i]
		var m: Dictionary = data["modules"][i]
		var spec: Dictionary = Core.MODULES.get(str(m["type"]), {}).get("params", {})
		for k in spec:
			if str(spec[k][4]) == "m":
				m["params"][k] = Core.param(bm, k) * f
		var bp: Array = bm["pos"]
		m["pos"] = [float(bp[0]) * f, float(bp[1]) * f, float(bp[2]) * f]
		if m.has("profile"):
			var pts: Array = []
			for p in bm.get("profile", []):
				pts.append([float(p[0]) * f, float(p[1]) * f])
			m["profile"] = pts
	for k in base.get("anchors", {}):
		var a: Array = base["anchors"][k]
		data["anchors"][k] = [float(a[0]) * f, float(a[1]) * f, (float(a[2]) if a.size() > 2 else 0.0) * f]


func _barrel_length(base: Dictionary, bi: int, L: float) -> void:
	var bm: Dictionary = base["modules"][bi]
	var L0 := Core.param(bm, "dlugosc")
	var d := L - L0
	var bx := float(bm["pos"][0])
	data["modules"][bi]["params"]["dlugosc"] = L
	for i in (base["modules"] as Array).size():
		if i == bi or i >= (data["modules"] as Array).size():
			continue
		var m0: Dictionary = base["modules"][i]
		if str(m0.get("parent", "")) != "":
			continue
		var x0 := float(m0["pos"][0])
		var t := str(m0["type"])
		if t in ["rura", "czolenko"] and absf(x0 - bx) < 0.12:
			if t == "rura":
				data["modules"][i]["params"]["dlugosc"] = maxf(0.05, Core.param(m0, "dlugosc") + d)
			continue
		if x0 > bx + L0 * 0.6:
			data["modules"][i]["pos"][0] = x0 + d
	var a: Dictionary = base.get("anchors", {})
	if a.has("wylot"):
		data["anchors"]["wylot"][0] = float(a["wylot"][0]) + d


func _avg_wear() -> Dictionary:
	var out := {"zuzycie": 0.0, "brud": 0.0, "rdza": 0.0}
	var n := 0
	for m in data.get("modules", []):
		for k in out:
			out[k] += float(m.get("wear", {}).get(k, Mats.DEFAULT_WEAR[k]))
		n += 1
	if n > 0:
		for k in out:
			out[k] /= float(n)
	return out


func _wear_all(key: String, v: float) -> void:
	for m in data["modules"]:
		if typeof(m.get("wear")) != TYPE_DICTIONARY:
			m["wear"] = {}
		m["wear"][key] = v
	_touch()


func _swap_mats(group: Array, to: String) -> void:
	var n := 0
	for m in data["modules"]:
		if group.has(str(m.get("mat", ""))):
			m["mat"] = to
			n += 1
	_touch()
	_commit()
	_status_msg("Zmieniono materiał %d modułów na: %s" % [n, Mats.label(to)])


func test_in_game() -> void:
	if not save_project():
		return
	var id := str(data["replace"]) if str(data.get("replace", "")) != "" else str(data["id"])
	Engine.set_meta("pracownia_test", id)
	Engine.set_meta("pracownia_back", str(data["id"]))
	ItemDB.defs = {}
	Core.forget(str(data["id"]))
	Psx.set_style(0.0, 0.0)
	get_tree().change_scene_to_file("res://scenes/main.tscn")


# =====================================================================================
# drzewo modułów (wspólne dla modelowania i teksturowania)
# =====================================================================================

func _build_tree(parent: Control) -> void:
	_tree = Tree.new()
	_tree.custom_minimum_size = Vector2(0, 300)
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_MULTI
	_tree.focus_mode = Control.FOCUS_NONE
	_tree.item_mouse_selected.connect(func(_pos, btn):
		var it := _tree.get_selected()
		if it == null:
			return
		var idx := int(it.get_metadata(0))
		if btn == MOUSE_BUTTON_LEFT:
			select(idx, Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_SHIFT)))
	_tree.button_clicked.connect(func(it, _c, _id, _b): toggle_hidden(int(it.get_metadata(0))))
	_tree.item_activated.connect(func(): frame_selection())
	parent.add_child(_tree)
	_refresh_tree()


func _refresh_tree() -> void:
	if _tree == null:
		return
	_tree.clear()
	var root := _tree.create_item()
	var items := {}
	var mods: Array = data.get("modules", [])
	var eye := _eye_icon()
	# najpierw korzenie, potem dzieci (rodzic może stać dalej na liście)
	var pending := range(mods.size())
	var guard := 0
	while not pending.is_empty() and guard < 64:
		guard += 1
		var rest: Array = []
		for i in pending:
			var m: Dictionary = mods[i]
			var pu := str(m.get("parent", ""))
			var parent_item: TreeItem = root
			if pu != "":
				var pi := Core.find_uid(data, pu)
				if pi >= 0 and not items.has(pi):
					rest.append(i)
					continue
				if pi >= 0:
					parent_item = items[pi]
			var it := _tree.create_item(parent_item)
			var label := str(m.get("name", m.get("type", "")))
			var tags: Array = []
			if str(m.get("part", "")) != "":
				tags.append(str(m["part"]))
			var mod: Dictionary = m.get("mod", {})
			if int(mod.get("lustro", 0)) > 0:
				tags.append("lustro")
			if int(mod.get("powtorz", 1)) > 1:
				tags.append("×%d" % int(mod["powtorz"]))
			it.set_text(0, label + ("   [" + ", ".join(tags) + "]" if not tags.is_empty() else ""))
			it.set_tooltip_text(0, "%s · %s" % [Core.MODULES.get(str(m["type"]), {}).get("label", m["type"]), Mats.label(str(m.get("mat", "")))])
			it.set_icon(0, Mats.swatch(str(m.get("mat", "stal"))))
			it.set_icon_max_width(0, 16)
			it.set_metadata(0, i)
			it.add_button(0, eye, 0, false, "Ukryj / pokaż (H)")
			if bool(m.get("hidden", false)):
				it.set_custom_color(0, UI.DIM.darkened(0.3))
			if sel.has(i):
				it.select(0)
				if i == _primary():
					it.set_custom_color(0, UI.ACCENT)
			items[i] = it
		pending = rest


static var _eye: Texture2D
func _eye_icon() -> Texture2D:
	if _eye == null:
		var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
		for y in 14:
			for x in 14:
				var d := Vector2((x - 6.5) / 6.5, (y - 6.5) / 3.6)
				var r := d.length()
				var c := Color(0, 0, 0, 0)
				if r < 1.0:
					c = Color(0.8, 0.78, 0.72, 1.0 if r > 0.75 or r < 0.4 else 0.0)
				img.set_pixel(x, y, c)
		_eye = ImageTexture.create_from_image(img)
	return _eye


# =====================================================================================
# zakładka 2: modelowanie
# =====================================================================================

func _panel_model() -> void:
	UI.header(_left, "Moduły")
	_build_tree(_left)
	var r1 := UI.row(_left)
	for cat in Core.CATEGORIES:
		var mb := MenuButton.new()
		mb.text = "+ " + cat
		mb.flat = false
		mb.focus_mode = Control.FOCUS_NONE
		var pop := mb.get_popup()
		var keys: Array = []
		for k in Core.MODULES:
			if str(Core.MODULES[k]["cat"]) == cat:
				pop.add_icon_item(Mats.swatch(str(Core.MODULES[k]["mat"])), str(Core.MODULES[k]["label"]))
				pop.set_item_icon_max_width(pop.item_count - 1, 14)
				keys.append(k)
		pop.id_pressed.connect(func(id): add_module(str(keys[id])))
		UI.grow(mb)
		r1.add_child(mb)
	var r2 := UI.row(_left)
	UI.grow(UI.button(r2, "Duplikuj", func(): duplicate_selected(), "Ctrl+D"))
	UI.grow(UI.button(r2, "Usuń", func(): delete_selected(), "Delete"))
	UI.grow(UI.button(r2, "▲", func(): move_selected(-1), "Wyżej (PageUp)"))
	UI.grow(UI.button(r2, "▼", func(): move_selected(1), "Niżej (PageDown)"))
	var r3 := UI.row(_left)
	UI.grow(UI.button(r3, "Przypnij", func(): parent_selected(), "Zaznacz moduły, Ctrl+klik na rodzicu na końcu: dzieci poruszają się z rodzicem"))
	UI.grow(UI.button(r3, "Odepnij", func(): unparent_selected()))
	UI.grow(UI.button(r3, "Kopiuj", func(): copy_selected(), "Ctrl+C"))
	UI.grow(UI.button(r3, "Wklej", func(): paste(), "Ctrl+V"))
	UI.hint(_left, "Klik: zaznacz · Ctrl+klik: kilka · 2×klik: kadruj · oko: ukryj. Moduł przypięty do części ruchomej (np. zamek) porusza się razem z nią.")
	_ref_panel(_left)

	var p := _primary()
	if p < 0:
		UI.header(_right, "Wybierz moduł", true)
		UI.hint(_right, "Kliknij moduł w podglądzie albo na liście. Nowe moduły dodasz przyciskami „+ Broń / Narzędzia / Ogólne”.\n\nWskazówki:\n• G, R, S w podglądzie przesuwa, obraca i skaluje myszą, X/Y/Z zawęża do osi.\n• Lustro odbija moduł na drugą stronę (np. okładziny chwytu).\n• Powtórzenie tworzy rząd kopii (rowki, nity, mostki).\n• Profil to dowolny kształt narysowany punktami i wyciągnięty na grubość: ostrza, kolby, dźwignie.")
		return
	var m: Dictionary = data["modules"][p]
	var spec: Dictionary = Core.MODULES.get(str(m["type"]), {})
	var nr := UI.row(_right)
	var ne := LineEdit.new()
	ne.text = str(m.get("name", ""))
	UI.grow(ne)
	ne.add_theme_font_size_override("font_size", 17)
	ne.text_changed.connect(func(t): m["name"] = t; _touch(false))
	ne.text_submitted.connect(func(_t): _refresh_tree(); ne.release_focus())
	nr.add_child(ne)
	var tl := Label.new()
	tl.text = str(spec.get("label", m["type"]))
	tl.add_theme_color_override("font_color", UI.DIM)
	nr.add_child(tl)
	if sel.size() > 1:
		UI.hint(_right, "Zaznaczono %d moduły. Suwaki zmieniają moduł główny (ostatnio kliknięty); G/R/S działa na wszystkie." % sel.size())

	UI.header(_right, "Kształt")
	for k in spec.get("params", {}):
		var ps: Array = spec["params"][k]
		var key := str(k)
		UI.slider(_right, str(ps[3]), float(ps[0]), float(ps[1]), Core.param(m, key), func(v): set_param(p, key, v), str(ps[4]))
	if str(m["type"]) == "profil":
		UI.header(_right, "Profil (widok z boku)")
		_profile = ProfileEditor.new()
		_profile.custom_minimum_size = Vector2(0, 280)
		_right.add_child(_profile)
		if not m.has("profile"):
			m["profile"] = (Core.PROFILE_PRESETS["prostokat"] as Array).duplicate(true)
		_profile.set_points(m["profile"])
		_profile.changed.connect(func(): _touch())
		_profile.committed.connect(func(): _commit())
		_profile.resized.connect(func(): _profile.fit(), CONNECT_ONE_SHOT)
		var pr := UI.row(_right)
		var pk: Array = Core.PROFILE_PRESETS.keys()
		var plab := {"prostokat": "Prostokąt", "ostrze_siekiery": "Ostrze siekiery", "ostrze_noza": "Ostrze noża", "kolba_wojskowa": "Kolba",
				"chwyt_rewolweru": "Chwyt rewolweru", "glowica_mlotka": "Głowica młotka"}
		var po := UI.option(pr, pk, "", func(v):
			m["profile"] = (Core.PROFILE_PRESETS[v] as Array).duplicate(true)
			_profile.set_points(m["profile"])
			_touch()
			_commit(), plab)
		po.tooltip_text = "Wczytaj gotowy kształt"
		UI.grow(po)
		UI.button(pr, "↕", func(): _profile.mirror_vertical(), "Odbij: dorysuj lustrzaną dolną/górną połowę")
		UI.button(pr, "↔", func(): _profile.flip_horizontal(), "Odwróć przód-tył")
		UI.button(pr, "⤢", func(): _profile.fit(), "Dopasuj widok")

	UI.header(_right, "Położenie" + ("  (względem rodzica)" if str(m.get("parent", "")) != "" else ""))
	var pos: Array = m["pos"]
	var names := ["X  przód / tył", "Y  góra / dół", "Z  prawo / lewo"]
	for c in 3:
		var ci := c
		UI.slider(_right, names[c], -0.6 if c == 0 else -0.25, 1.0 if c == 0 else 0.25, float(pos[c]), func(v): m["pos"][ci] = v; _touch(), "m", 0.0005)
	var rot: Array = m["rot"]
	var rn := ["Obrót X  (przechył)", "Obrót Y  (odchylenie)", "Obrót Z  (pochylenie)"]
	for c in 3:
		var ci := c
		UI.slider(_right, rn[c], -180.0, 180.0, float(rot[c]), func(v): m["rot"][ci] = v; _touch(), "deg", 0.5)
	var sc: Array = m.get("scale", [1, 1, 1])
	m["scale"] = sc
	var sn := ["Skala X", "Skala Y", "Skala Z"]
	for c in 3:
		var ci := c
		UI.slider(_right, sn[c], 0.1, 3.0, float(sc[c]), func(v): m["scale"][ci] = v; _touch(), "x", 0.01)
	var tr := UI.row(_right)
	UI.grow(UI.button(tr, "Środek Z = 0", func(): m["pos"][2] = 0.0; _touch(); _commit(); _refresh_panels(), "Na osi broni"))
	UI.grow(UI.button(tr, "Zeruj obrót", func(): m["rot"] = [0.0, 0.0, 0.0]; _touch(); _commit(); _refresh_panels()))
	UI.grow(UI.button(tr, "Skala 1", func(): m["scale"] = [1.0, 1.0, 1.0]; _touch(); _commit(); _refresh_panels()))

	UI.header(_right, "Modyfikatory")
	var mod: Dictionary = m.get("mod", {"lustro": 0, "powtorz": 1, "krok": [0.01, 0.0, 0.0]})
	m["mod"] = mod
	UI.check(_right, "Lustro: kopia odbita na drugą stronę (oś Z)", int(mod.get("lustro", 0)) > 0, func(on): mod["lustro"] = 1 if on else 0; _touch(); _commit(); _refresh_tree())
	UI.slider(_right, "Powtórzenie: liczba kopii", 1.0, 24.0, float(mod.get("powtorz", 1)), func(v): mod["powtorz"] = int(v); _touch(), "n")
	var krok: Array = mod.get("krok", [0.01, 0.0, 0.0])
	mod["krok"] = krok
	for c in 3:
		var ci := c
		UI.slider(_right, "Krok powtórzenia " + ["X", "Y", "Z"][c], -0.1, 0.1, float(krok[c]), func(v): krok[ci] = v; _touch(), "m", 0.0005)

	UI.header(_right, "Rola i hierarchia")
	var part_keys: Array = Core.PARTS
	UI.option(_right, part_keys, str(m.get("part", "")), func(v): m["part"] = str(v); _touch(); _commit(); _refresh_tree(), Core.PART_LABELS).tooltip_text = "Część ruchoma animowana w grze. Dzieci dziedziczą rolę rodzica."
	var parents: Array = [""]
	var plabels := {"": "— bez rodzica —"}
	for i in (data["modules"] as Array).size():
		if i == p:
			continue
		var uid := str(data["modules"][i].get("uid", ""))
		if _is_descendant(i, str(m.get("uid", ""))):
			continue
		parents.append(uid)
		plabels[uid] = str(data["modules"][i].get("name", uid))
	UI.option(_right, parents, str(m.get("parent", "")), func(v): _set_parent_keep(p, str(v)); _touch(); _commit(); _refresh_panels(), plabels).tooltip_text = "Rodzic: moduł porusza się razem z nim; położenie liczone od rodzica"
	UI.check(_right, "Ukryty", bool(m.get("hidden", false)), func(on): m["hidden"] = on; _touch(); _commit(); _refresh_tree())


## Obraz referencyjny za modelem (zdjęcie broni do odrysowania).
func _ref_panel(parent: Control) -> void:
	UI.header(parent, "Obraz referencyjny")
	UI.hint(parent, "Zdjęcie z boku za modelem: wrzuć PNG/JPG do data/warsztat/referencje albo wybierz plik.")
	var files: Array = [""]
	var dir := DirAccess.open("res://data/warsztat/referencje")
	if dir != null:
		for f in dir.get_files():
			if f.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
				files.append("res://data/warsztat/referencje/" + f)
	var labels := {"": "— brak —"}
	for f in files:
		if f != "":
			labels[f] = str(f).get_file()
	var cur := str(data.get("ref", {}).get("path", ""))
	if cur != "" and not files.has(cur):
		files.append(cur)
		labels[cur] = cur.get_file()
	var r := UI.row(parent)
	UI.grow(UI.option(r, files, cur, func(v): _set_ref("path", str(v)), labels))
	UI.button(r, "Plik…", func(): _ref_dialog())
	var ref: Dictionary = data.get("ref", {})
	UI.slider(parent, "Szerokość obrazu", 0.05, 2.0, float(ref.get("w", 0.5)), func(v): _set_ref("w", v), "m", 0.001)
	UI.slider(parent, "Przesunięcie X", -0.8, 0.8, float(ref.get("x", 0.2)), func(v): _set_ref("x", v), "m", 0.001)
	UI.slider(parent, "Przesunięcie Y", -0.4, 0.4, float(ref.get("y", 0.0)), func(v): _set_ref("y", v), "m", 0.001)
	UI.slider(parent, "Krycie", 0.05, 1.0, float(ref.get("a", 0.5)), func(v): _set_ref("a", v), "%")
	_update_ref()


func _set_ref(k: String, v) -> void:
	if not data.has("ref"):
		data["ref"] = {}
	data["ref"][k] = v
	_touch(false)
	_update_ref()


func _ref_dialog() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Obrazy"])
	fd.size = Vector2i(900, 600)
	fd.file_selected.connect(func(path): _set_ref("path", path); _refresh_panels())
	_root.add_child(fd)
	fd.popup_centered()


func _update_ref() -> void:
	var ref: Dictionary = data.get("ref", {})
	var path := str(ref.get("path", ""))
	if path == "":
		_ref_quad.visible = false
		return
	var img := Image.new()
	var err := img.load(path) if not path.begins_with("res://") else OK
	var tex: Texture2D
	if path.begins_with("res://"):
		tex = load(path) if ResourceLoader.exists(path) else null
		if tex == null:
			err = img.load(ProjectSettings.globalize_path(path))
			if err == OK:
				tex = ImageTexture.create_from_image(img)
	elif err == OK:
		tex = ImageTexture.create_from_image(img)
	if tex == null:
		_ref_quad.visible = false
		_status_msg("Nie udało się wczytać obrazu " + path)
		return
	var w := float(ref.get("w", 0.5))
	var q := QuadMesh.new()
	q.size = Vector2(w, w * float(tex.get_height()) / float(tex.get_width()))
	_ref_quad.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, float(ref.get("a", 0.5)))
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ref_quad.material_override = mat
	_ref_quad.position = Vector3(float(ref.get("x", 0.2)), float(ref.get("y", 0.0)), -0.12)
	_ref_quad.visible = true


# =====================================================================================
# zakładka 3: teksturowanie
# =====================================================================================

func _panel_texture() -> void:
	UI.header(_left, "Moduły")
	_build_tree(_left)
	var r := UI.row(_left)
	UI.grow(UI.button(r, "Ten sam materiał", func(): _select_same_material(), "Zaznacz wszystkie moduły z materiałem głównego zaznaczenia"))
	UI.grow(UI.button(r, "Wszystko", func(): sel = range((data["modules"] as Array).size()); _rebuild_now(); _refresh_panels(), "Ctrl+A"))
	UI.header(_left, "Gotowe stany")
	UI.hint(_left, "Na zaznaczone moduły (bez zaznaczenia: na całość).")
	var grid := GridContainer.new()
	grid.columns = 2
	_left.add_child(grid)
	for k in WEAR_PRESETS:
		var key: String = k
		var b := UI.button(grid, key, func(): _apply_wear_preset(key))
		b.custom_minimum_size = Vector2(136, 30)
	UI.header(_left, "Światło")
	UI.hint(_left, "Sprawdź materiały w różnych warunkach (pasek nad podglądem):")
	var lg := GridContainer.new()
	lg.columns = 2
	_left.add_child(lg)
	for i in LIGHTS.size():
		var li := i
		var lb := UI.button(lg, LIGHTS[i], func(): apply_light(li))
		lb.custom_minimum_size.x = 136

	var p := _primary()
	if p < 0:
		UI.header(_right, "Wybierz moduł", true)
		UI.hint(_right, "Zaznacz moduł (lub kilka z Ctrl), potem kliknij materiał i ustaw zużycie.\n\nZużycie działa samo z kształtu: przetarcia pojawiają się na wypukłych krawędziach, brud w zagłębieniach, rdza w plamach. Nie trzeba malować.")
		return
	var m: Dictionary = data["modules"][p]
	UI.header(_right, "Materiał  ·  " + str(m.get("name", "")))
	var mg := GridContainer.new()
	mg.columns = 4
	mg.add_theme_constant_override("h_separation", 4)
	mg.add_theme_constant_override("v_separation", 4)
	_right.add_child(mg)
	for k in Mats.names():
		var mk: String = k
		var b := Button.new()
		b.icon = Mats.swatch(mk)
		b.expand_icon = true
		b.custom_minimum_size = Vector2(78, 62)
		b.tooltip_text = Mats.label(mk)
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_pressed = str(m.get("mat", "")) == mk
		b.add_theme_constant_override("icon_max_width", 70)
		b.pressed.connect(func(): _set_mat_sel(mk))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.add_child(b)
		var l := Label.new()
		l.text = Mats.label(mk)
		l.add_theme_font_size_override("font_size", 10)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size.x = 78
		l.clip_text = true
		l.add_theme_color_override("font_color", UI.ACCENT if b.button_pressed else UI.DIM)
		v.add_child(l)
		mg.add_child(v)
	UI.header(_right, "Wygląd i zużycie")
	if typeof(m.get("wear")) != TYPE_DICTIONARY:
		m["wear"] = {}
	var w: Dictionary = m["wear"]
	var tr := UI.row(_right)
	var tlab := Label.new()
	tlab.text = "Odcień"
	UI.grow(tlab)
	tr.add_child(tlab)
	var cp := ColorPickerButton.new()
	var tint: Array = w.get("tint", [1.0, 1.0, 1.0])
	cp.color = Color(float(tint[0]), float(tint[1]), float(tint[2]))
	cp.custom_minimum_size = Vector2(120, 26)
	cp.edit_alpha = false
	cp.color_changed.connect(func(c): _set_wear_sel("tint", [c.r, c.g, c.b]))
	tr.add_child(cp)
	UI.button(tr, "×", func(): _set_wear_sel("tint", [1.0, 1.0, 1.0]); _refresh_panels(), "Bez odcienia")
	var rows := [["zuzycie", "Przetarcia krawędzi", 0.0, 1.0, "%"], ["brud", "Brud we wgłębieniach", 0.0, 1.0, "%"], ["rdza", "Rdza", 0.0, 1.0, "%"],
			["rysy", "Rysy", 0.0, 1.0, "%"], ["polysk", "Połysk / olej", 0.0, 1.0, "%"], ["skala", "Skala wzoru", 0.3, 3.0, "x"]]
	for rw in rows:
		var key: String = rw[0]
		UI.slider(_right, rw[1], float(rw[2]), float(rw[3]), float(w.get(key, Mats.DEFAULT_WEAR[key])), func(v): _set_wear_sel(key, v), rw[4])
	var cr := UI.row(_right)
	UI.grow(UI.button(cr, "Kopiuj", func(): _wear_clip = {"mat": m.get("mat", ""), "wear": (m["wear"] as Dictionary).duplicate(true)}; _status_msg("Skopiowano wygląd")))
	UI.grow(UI.button(cr, "Wklej", func():
		if _wear_clip.is_empty():
			return
		for i in sel:
			data["modules"][i]["mat"] = _wear_clip["mat"]
			data["modules"][i]["wear"] = (_wear_clip["wear"] as Dictionary).duplicate(true)
		_touch()
		_commit()
		_refresh_panels(), "Wklej materiał i zużycie na zaznaczone"))
	UI.grow(UI.button(cr, "Na ten sam materiał", func():
		var n := 0
		for mm in data["modules"]:
			if str(mm.get("mat", "")) == str(m.get("mat", "")):
				mm["wear"] = (m["wear"] as Dictionary).duplicate(true)
				n += 1
		_touch()
		_commit()
		_status_msg("Wygląd przeniesiony na %d moduły" % n), "Wszystkie moduły z tym materiałem dostają ten sam wygląd"))


func _select_same_material() -> void:
	var p := _primary()
	if p < 0:
		return
	var mat := str(data["modules"][p].get("mat", ""))
	sel = []
	for i in (data["modules"] as Array).size():
		if str(data["modules"][i].get("mat", "")) == mat:
			sel.append(i)
	sel.erase(p)
	sel.append(p)
	_rebuild_now()
	_refresh_panels()


func _set_mat_sel(mat: String) -> void:
	for i in sel:
		data["modules"][i]["mat"] = mat
	_touch()
	_commit()
	_refresh_panels()


func _set_wear_sel(key: String, v) -> void:
	for i in sel:
		if typeof(data["modules"][i].get("wear")) != TYPE_DICTIONARY:
			data["modules"][i]["wear"] = {}
		data["modules"][i]["wear"][key] = v
	_touch()


func _apply_wear_preset(name: String) -> void:
	var targets: Array = sel if not sel.is_empty() else range((data["modules"] as Array).size())
	for i in targets:
		var w: Dictionary = data["modules"][i].get("wear", {}) if typeof(data["modules"][i].get("wear")) == TYPE_DICTIONARY else {}
		for k in WEAR_PRESETS[name]:
			w[k] = WEAR_PRESETS[name][k]
		data["modules"][i]["wear"] = w
	_touch()
	_commit()
	_refresh_panels()
	_status_msg("Stan „%s” na %d moduły" % [name, targets.size()])


# =====================================================================================
# zakładka 4: animacja
# =====================================================================================

func _select_step(s: String) -> void:
	anim_step = s
	anim_t = 0.0
	playing = false
	_refresh_panels()
	_apply_anim_pose()


func _panel_anim() -> void:
	var template := str(data.get("template", "item"))
	var steps: Array = Anim.STEPS.get(template, [])
	UI.header(_left, "Kroki szablonu")
	if steps.is_empty():
		UI.hint(_left, "Szablon „bez animacji”: wybierz w zakładce Składanie szablon działania (półautomat, pompka, łamana), żeby animować kroki. Kotwice działają zawsze.")
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0, 150)
	list.focus_mode = Control.FOCUS_NONE
	for s in steps:
		var edited: bool = data.get("anim", {}).has(s)
		list.add_item(str(Anim.STEP_LABELS.get(s, s)) + ("   ●" if edited else ""))
		list.set_item_tooltip(list.item_count - 1, "● = zmieniony w tym projekcie (gra użyje tej wersji)" if edited else "domyślny ruch szablonu")
		if s == anim_step:
			list.select(list.item_count - 1)
	list.item_selected.connect(func(i): _select_step(str(steps[i])))
	_left.add_child(list)
	if anim_step != "":
		var step := _anim_step_data(anim_step)
		UI.slider(_left, "Czas kroku", 0.05, 2.0, float(step.get("time", 0.5)), func(v): _anim_step_edit(anim_step)["time"] = v; _touch(false), "", 0.01, "Sekundy (w grze skracane przez umiejętność)")
		var r := UI.row(_left)
		UI.grow(UI.button(r, "Przywróć domyślny", func():
			data.get("anim", {}).erase(anim_step)
			_touch(false)
			_commit()
			_refresh_panels()
			_apply_anim_pose(), "Usuń zmiany tego kroku"))
		UI.grow(UI.button(r, "Odbij czas", func():
			var st := _anim_step_edit(anim_step)
			for tk in st.get("tracks", {}):
				for key in st["tracks"][tk]:
					key[0] = snappedf(1.0 - float(key[0]), 0.01)
				(st["tracks"][tk] as Array).sort_custom(func(a, b): return float(a[0]) < float(b[0]))
			_touch(false)
			_commit()
			_refresh_panels(), "Ruch od końca do początku (np. z otwierania zrób zamykanie)"))

	UI.header(_left, "Kotwice")
	UI.hint(_left, "Punkty, z których korzysta gra: wylot (strzał, błysk), lewa dłoń, zawias luf, wyrzutnik łusek…")
	var anchors: Dictionary = data.get("anchors", {})
	var ak: Array = Core.ANCHORS.keys()
	var alabels := {}
	for k in ak:
		alabels[k] = str(Core.ANCHORS[k]) + ("  ✓" if anchors.has(k) else "")
	UI.option(_left, ak, anchor_sel, func(v): anchor_sel = str(v); _refresh_panels(), alabels)
	var ar := UI.row(_left)
	UI.grow(UI.button(ar, "Postaw kliknięciem", func(): _pick_anchor = true; _status_msg("Kliknij punkt na modelu, żeby postawić kotwicę „%s”" % Core.ANCHORS[anchor_sel])))
	UI.grow(UI.button(ar, "Usuń", func(): data.get("anchors", {}).erase(anchor_sel); _touch(false); _commit(); _refresh_panels(), "Bez kotwicy gra liczy punkt sama z modułów"))
	if anchors.has(anchor_sel):
		var a: Array = anchors[anchor_sel]
		while a.size() < 3:
			a.append(0.0)
		for c in 3:
			var ci := c
			UI.slider(_left, ["X", "Y", "Z"][c], -0.6 if c == 0 else -0.2, 1.0 if c == 0 else 0.2, float(a[c]), func(v): a[ci] = v; _touch(false); _update_markers(); _apply_anim_pose(), "m", 0.0005)

	# --- prawa: ścieżki
	if anim_step == "":
		UI.header(_right, "Animacja", true)
		UI.hint(_right, "Wybierz krok po lewej.")
		_build_timeline()
		return
	var step2 := _anim_step_data(anim_step)
	UI.header(_right, str(Anim.STEP_LABELS.get(anim_step, anim_step)), true)
	UI.hint(_right, "Suwak ścieżki ustawia klucz w bieżącej chwili (czerwona linia na osi czasu). Między kluczami ruch płynie łagodnie.")
	var vr := UI.row(_right)
	UI.grow(UI.button(vr, "Z oczu (biodro)", func(): set_fpp(true, false)))
	UI.grow(UI.button(vr, "Celowanie", func(): set_fpp(true, true)))
	UI.grow(UI.button(vr, "Orbita", func(): set_fpp(false)))
	var groups := [["Broń w dłoni", ["x", "y", "z", "pochyl", "odchyl", "przechyl"]], ["Lewa dłoń", ["lewa_x", "lewa_y", "lewa_z"]],
			["Części ruchome", ["zamek", "czolenko", "magazynek", "lufy", "kurek", "beben"]]]
	var pose := Anim.pose(step2, anim_t)
	for g in groups:
		UI.header(_right, g[0])
		for tk in g[1]:
			var track: String = tk
			var rng := _track_range(track)
			var has: bool = step2.get("tracks", {}).has(track)
			var cur: float = float(pose.get(track, 0.0))
			var lab := str(Anim.TRACK_LABELS.get(track, track)).split(": ")[-1] + ("  ◆" if has else "")
			UI.slider(_right, lab, rng[0], rng[1], cur, func(v):
				Anim.set_key(_anim_step_edit(anim_step), track, anim_t, v)
				_touch(false)
				if _timeline != null:
					_timeline.set_step(_anim_step_edit(anim_step), track)
					_timeline.t = anim_t
				_apply_anim_pose(), "deg" if Anim.ANGLE_TRACKS.has(track) else "m", rng[2])
	UI.header(_right, "Zdarzenia (dźwięki)")
	var evs: Array = step2.get("events", [])
	for e in evs:
		UI.hint(_right, "%.0f%%  ·  %s" % [float(e[0]) * 100.0, str(e[1])])
	var er := UI.row(_right)
	var ee := LineEdit.new()
	ee.placeholder_text = "dzwiek:gun_rack"
	UI.grow(ee)
	er.add_child(ee)
	UI.button(er, "Dodaj w tej chwili", func():
		if ee.text.strip_edges() == "":
			return
		var st := _anim_step_edit(anim_step)
		if not st.has("events"):
			st["events"] = []
		st["events"].append([snappedf(anim_t, 0.01), ee.text.strip_edges()])
		_touch(false)
		_commit()
		_refresh_panels())
	_build_timeline()


func _track_range(track: String) -> Array:
	match track:
		"x", "y", "z": return [-0.25, 0.25, 0.001]
		"lewa_x", "lewa_y", "lewa_z": return [-0.35, 0.35, 0.001]
		"pochyl", "odchyl", "przechyl": return [-120.0, 120.0, 0.5]
		"zamek", "czolenko": return [0.0, 0.12, 0.0005]
		"magazynek": return [0.0, 0.35, 0.001]
		"lufy": return [0.0, 60.0, 0.5]
		"kurek": return [0.0, 90.0, 0.5]
		"beben": return [0.0, 360.0, 1.0]
	return [-1.0, 1.0, 0.01]


func _build_timeline() -> void:
	UI.clear(_bottom_box)
	var bar := UI.row(_bottom_box)
	UI.button(bar, "⏮", func(): anim_t = 0.0; _timeline.t = 0.0; _timeline.queue_redraw(); _apply_anim_pose(), "Na początek")
	UI.button(bar, "▶ / ❚❚", func(): playing = not playing, "Odtwórz (Spacja)")
	UI.check(bar, "Pętla", loop, func(on): loop = on)
	UI.option(bar, [0.1, 0.25, 0.5, 1.0], str(play_speed), func(v): play_speed = float(v), {0.1: "×0,1", 0.25: "×0,25", 0.5: "×0,5", 1.0: "×1"})
	UI.button(bar, "◆ Klucz wszystkich", func():
		if anim_step == "":
			return
		var st := _anim_step_edit(anim_step)
		var pose := Anim.pose(_anim_step_data(anim_step), anim_t)
		for tk in pose:
			Anim.set_key(st, str(tk), anim_t, float(pose[tk]))
		_touch(false)
		_commit()
		_timeline.set_step(st)
		_status_msg("Klucz wszystkich ścieżek w %.0f%%" % (anim_t * 100.0)), "Wstaw klucze wszystkich ścieżek w bieżącej chwili (zatrzymanie pozy)")
	var tip := Label.new()
	tip.text = "2×klik w wierszu: klucz · przeciągnij romb · Delete: usuń klucz"
	tip.add_theme_font_size_override("font_size", 11)
	tip.add_theme_color_override("font_color", UI.DIM)
	bar.add_child(tip)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_bottom_box.add_child(sc)
	_timeline = Timeline.new()
	UI.grow(_timeline)
	sc.add_child(_timeline)
	_timeline.set_step(_anim_step_data(anim_step) if not data.get("anim", {}).has(anim_step) else data["anim"][anim_step])
	_timeline.t = anim_t
	_timeline.scrubbed.connect(func(tt): anim_t = tt; playing = false; _apply_anim_pose())
	_timeline.edited.connect(func():
		_touch(false)
		_commit()
		_apply_anim_pose())
	_timeline.key_added.connect(func(track, tt):
		var st := _anim_step_edit(anim_step)
		var v = Anim.sample(_anim_step_data(anim_step), track, tt)
		Anim.set_key(st, track, tt, float(v) if v != null else 0.0)
		_timeline.set_step(st, track)
		anim_t = tt
		_timeline.t = tt
		_touch(false)
		_commit()
		_apply_anim_pose())
	# edycja klucza przez przeciąganie zmienia kopię domyślną: najpierw robimy kopię w projekcie
	_timeline.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and anim_step != "" and not data.get("anim", {}).has(anim_step):
			_timeline.step = _anim_step_edit(anim_step))
