extends Node
## Praca narzędziem prowadzona myszą, bez paneli i bez osobnego kursora.
## Celujesz w punkt pracy, trzymasz prawy przycisk i od tej chwili mysz
## prowadzi narzędzie zamiast kamery:
##   dźwignia: ruch myszy w dół; postęp rośnie z poziomem zdolności i ramieniem,
##   kręcenie: koła myszą zgodnie z ruchem wskazówek (przeciwnie wykręca) albo kółko,
##   uderzenie: zamach w górę i ruch w dół; za mocno = wygięty gwóźdź.
## Część w ręce (deska, nakładka, zamek) przykłada się lewym przyciskiem.
## Zdolności narzędzi pochodzą z danych: items.json, pole "abilities".

const PointScript := preload("res://scripts/work/work_point.gd")

const REACH := 1.7                 # zasięg pracy w metrach
const RAY_TOLERANCE := 0.09        # jak daleko od promienia wzroku może być punkt
const MARKER_RANGE := 3.0
const LEVER_RATE := 0.005          # postęp na piksel w dół (narzędzie poziomu 3, ramię 0,6 m)
const STRIKE_RAISE_MIN := 40.0     # pikseli zamachu, by uderzenie się liczyło
const STRIKE_WEAK := 60.0
const STRIKE_HARD := 230.0         # od tego zamachu gwóźdź może się wygiąć
const STRIKE_TOO_HARD := 280.0     # od tego zamachu gwóźdź wygina się zawsze
const WHEEL_TURN := 1.0 / 12.0     # obrót na jeden ząbek kółka

var main
var points: Array = []
var candidate = null
var active = null
var highlights := true
var rng := RandomNumberGenerator.new()

var _virtual := Vector2.ZERO       # wirtualny kursor do kręcenia
var _raise := 0.0                  # zamach w górę
var _down := 0.0
var _phase := 0.0                  # do ruchu dłoni
var _markers := {}


func setup(main_node) -> void:
	main = main_node
	rng.seed = 12


func add_point(owner, node: Node3D, local: Vector3, kind: String, opts: Dictionary = {}):
	var p = PointScript.new()
	p.owner = owner
	p.node = node
	p.local = local
	p.kind = kind
	p.ability = str(opts.get("ability", ""))
	p.min_level = int(opts.get("min_level", 1))
	p.accepts = str(opts.get("accepts", ""))
	p.label_key = str(opts.get("label", ""))
	p.data = opts.get("data", {})
	p.id = str(opts.get("id", "p%d" % points.size()))
	points.append(p)
	return p


static func tool_level(item, ability: String) -> int:
	if item == null or ability == "":
		return 0
	return int(item.get_def().get("abilities", {}).get(ability, 0))


## Ramię dźwigni: dłuższe narzędzie podważa łatwiej (łom 0,75 m: ×1,25).
static func arm_factor(item) -> float:
	if item == null:
		return 0.0
	return clampf(float(item.get_def().get("length", 0.3)) / 0.6, 0.5, 1.4)


func usable(p, hand) -> bool:
	if not p.enabled:
		return false
	if p.kind == "attach":
		return hand != null and str(hand.get_def().get("mount", "")) == p.accepts
	return tool_level(hand, p.ability) >= p.min_level


func is_active() -> bool:
	return active != null


func _hand():
	return main.inventory.hand_item() if main != null and main.inventory != null else null


func _physics_process(_delta: float) -> void:
	if main == null or main.player == null:
		return
	var hand = _hand()
	if active != null:
		var far: bool = main.player.camera.global_position.distance_to(active.world_pos()) > REACH + 0.3
		if not usable(active, hand) or far:
			end()
	if active == null:
		candidate = find_candidate(hand)
	_update_markers(hand)
	_update_hud()
	_update_pose()


## Punkt pracy najbliżej linii wzroku (ten, w który celujesz), niezasłonięty.
func find_candidate(hand):
	var cam: Camera3D = main.player.camera
	var o := cam.global_position
	var dir := -cam.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(o, o + dir * REACH)
	q.exclude = [main.player.get_rid()]
	var hit: Dictionary = main.player.get_world_3d().direct_space_state.intersect_ray(q)
	var block := REACH if hit.is_empty() else o.distance_to(hit["position"])
	var best = null
	var best_off := INF
	for p in points:
		if not usable(p, hand):
			continue
		var wp: Vector3 = p.world_pos()
		var t := (wp - o).dot(dir)
		if t < 0.1 or t > REACH or t > block + 0.12:
			continue
		var off := (wp - (o + dir * t)).length()
		if off > RAY_TOLERANCE:
			continue
		if off < best_off:
			best = p
			best_off = off
	return best


func begin() -> bool:
	if candidate == null or candidate.kind == "attach":
		return false
	active = candidate
	_virtual = Vector2(60, 0)
	_raise = 0.0
	_down = 0.0
	return true


func end() -> void:
	active = null
	_raise = 0.0


## Przyłożenie części trzymanej w ręce do gniazda (lewy przycisk).
func attach() -> bool:
	if candidate == null or candidate.kind != "attach":
		return false
	candidate.owner.work_apply(candidate, {"type": "attach", "item": _hand()})
	return true


## Ruch myszy podczas pracy: zamiast obracać kamerę prowadzi narzędzie.
func mouse(rel: Vector2) -> void:
	if active == null:
		return
	var hand = _hand()
	var lvl := tool_level(hand, active.ability)
	match active.kind:
		"lever":
			if rel.y > 0.0:
				var amount := rel.y * LEVER_RATE * (lvl / 3.0) * arm_factor(hand)
				_phase = fmod(_phase + rel.y * 0.006, 1.0)
				_apply({"type": "lever", "amount": amount, "tool": hand})
		"rotate":
			var prev := _virtual
			_virtual += rel
			if _virtual.length() > 200.0:
				_virtual = _virtual.normalized() * 200.0
			if prev.length() > 15.0 and _virtual.length() > 15.0:
				rotate_by(wrapf(_virtual.angle() - prev.angle(), -PI, PI) / TAU)
		"strike":
			if rel.y < 0.0:
				_raise = minf(_raise - rel.y, 400.0)
				_down = 0.0
			elif rel.y > 0.0 and _raise >= STRIKE_RAISE_MIN:
				_down += rel.y
				if _down >= minf(_raise * 0.6, 60.0):
					strike(_raise)
					_raise = 0.0
					_down = 0.0


func wheel(steps: float) -> void:
	if active != null and active.kind == "rotate":
		rotate_by(steps * WHEEL_TURN)


## Obrót wkrętaka o podaną liczbę obrotów (dodatnie: wkręcanie).
func rotate_by(turns: float) -> void:
	if active == null:
		return
	var hand = _hand()
	var lvl := tool_level(hand, active.ability)
	_phase += turns
	_apply({"type": "rotate", "turns": turns * (lvl / 3.0), "raw": turns, "tool": hand})


## Uderzenie młotkiem; power to długość zamachu w pikselach.
func strike(power: float) -> void:
	if active == null:
		return
	var hand = _hand()
	var lvl := tool_level(hand, active.ability)
	var bend := power >= STRIKE_TOO_HARD or (power >= STRIKE_HARD and rng.randf() < 0.3)
	var amount := (1.0 if power >= STRIKE_WEAK else 0.5) * (lvl / 3.0)
	_apply({"type": "strike", "power": power, "amount": amount, "bend": bend, "tool": hand})


func _apply(ev: Dictionary) -> void:
	active.owner.work_apply(active, ev)


# --- podpowiedzi, znaczniki, poza dłoni -----------------------------------------

func _update_hud() -> void:
	var hud = main.hud
	if active != null:
		var st: Dictionary = active.owner.work_status(active)
		hud.set_work(str(st.get("text", "")), float(st.get("ratio", -1.0)))
	elif candidate != null:
		var key := tr("WORK_KEY_ATTACH") if candidate.kind == "attach" else tr("WORK_KEY_TOOL")
		hud.set_work("%s · %s" % [tr(candidate.label_key), key], -1.0)
	else:
		hud.set_work("", -1.0)


func _update_markers(hand) -> void:
	var cam_pos: Vector3 = main.player.camera.global_position
	for p in points:
		var show: bool = highlights and usable(p, hand) and cam_pos.distance_to(p.world_pos()) <= MARKER_RANGE
		var m: MeshInstance3D = _markers.get(p)
		if not show:
			if m != null:
				m.visible = false
			continue
		if m == null:
			m = _make_marker()
			_markers[p] = m
		m.visible = true
		m.global_position = p.world_pos()
		var big: bool = p == candidate or p == active
		m.scale = Vector3.ONE * (1.6 if big else 1.0)


func _make_marker() -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.95, 0.8, 0.35)
	mat.no_depth_test = false
	var box := BoxMesh.new()
	box.size = Vector3(0.022, 0.022, 0.022)
	box.material = mat
	var m := MeshInstance3D.new()
	m.mesh = box
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.top_level = true
	main.world.add_child(m)
	return m


## Dłoń z narzędziem idzie do punktu pracy i porusza się zgodnie z rodzajem pracy.
func _update_pose() -> void:
	var player = main.player
	if active == null:
		player.work_target = null
		return
	var lift := 0.0
	var roll := 0.0
	match active.kind:
		"lever":
			lift = -0.05 * sin(_phase * TAU)
		"rotate":
			roll = _phase * TAU
		"strike":
			lift = _raise * 0.0007
	player.work_target = active.world_pos() + Vector3.UP * lift
	player.work_roll = roll
