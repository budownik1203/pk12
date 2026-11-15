extends Node
## Praca narzędziem na dwie ręce. Lewy przycisk myszy to lewa ręka, prawy to
## prawa; każdy przycisk działa tym, co trzyma jego ręka:
##   dźwignia (łom): przytrzymaj przycisk ręki z łomem i ruszaj myszą w dół,
##   kręcenie (śrubokręt): przytrzymaj przycisk i kręć myszą albo kółkiem,
##   wbijanie: przytrzymaj przycisk ręki z gwoździami (gwóźdź przyłożony),
##     a przyciskiem ręki z młotkiem klikaj; między uderzeniami jest przerwa,
##   przyłożenie części: przycisk ręki, która trzyma deskę, nakładkę czy zamek.
## Dopóki trzymasz przycisk pracy, mysz nie obraca kamery, także gdy praca
## już się skończyła (deska puściła), więc widok nie ucieka w dół.
## Zdolności narzędzi pochodzą z danych: items.json, pole "abilities".

const PointScript := preload("res://scripts/work/work_point.gd")
const Psx := preload("res://scripts/psx.gd")

## Kolory znaczników: czerwony demontaż (podważanie, wyciąganie, wykręcanie),
## żółty dołożenie części, niebieski montaż (wbijanie, wkręcanie).
const MARK_COLORS := {"remove": Color(0.95, 0.22, 0.18), "place": Color(0.98, 0.82, 0.25), "mount": Color(0.25, 0.55, 1.0)}

const REACH := 1.7                 # zasięg pracy w metrach (przykładanie części)
## zasięg wg rodzaju pracy: ręka musi sięgnąć narzędziem do punktu
const KIND_REACH := {"strike": 0.95, "rotate": 1.0, "lever": 1.3, "attach": 1.7}
const RAY_TOLERANCE := 0.09        # jak daleko od promienia wzroku może być punkt
const MARKER_RANGE := 3.0
const LEVER_RATE := 0.005          # postęp na piksel w dół (narzędzie poziomu 3, ramię 0,6 m)
const WHEEL_TURN := 1.0 / 12.0     # obrót na jeden ząbek kółka
const STRIKE_COOLDOWN := 0.45      # sekundy między uderzeniami młotka
const TWO_HAND_LEVER := 1.3        # chwyt oburącz przy dźwigni
const SWING_HIT := 0.09            # od kliknięcia do trafienia obuchem w gwóźdź
const SWING_HOLD := 0.16           # do tej chwili młotek leży na gwoździu
const SWING_END := 0.42            # do tej chwili wraca do tyłu
const NAILS := "gwozdzie"

var main
var points: Array = []
var candidate = null
var active = null                  # punkt dźwigni albo kręcenia
var active_side := ""
var nail_point = null              # gwóźdź przytrzymywany jedną ręką
var nail_side := ""
var holds := {"l": false, "r": false}
var highlights := true
var hand_work = null               # hand_work.gd: praca na przedmiocie w lewej ręce
var show_bars := false             # paski i liczby postępu (numpad 0); docelowo postęp widać na przedmiocie

var _virtual := Vector2.ZERO
var _phase := 0.0
var _cooldown := 0.0
var _impact := 0.0                 # 0 młotek z tyłu, 1 obuch na gwoździu
var _swing := -1.0                 # czas od kliknięcia (ujemny: brak zamachu)
var _pending = null                # uderzenie czekające na trafienie obuchem
var _markers := {}
var _mark_mats := {}


func setup(main_node) -> void:
	main = main_node


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


static func other(side: String) -> String:
	return "l" if side == "r" else "r"


static func _is_nails(item) -> bool:
	return item != null and item.def_id == NAILS


static func _mounts(item, p) -> bool:
	return item != null and str(item.get_def().get("mount", "")) == p.accepts


func hand(side: String):
	if main == null or main.inventory == null:
		return null
	return main.inventory.hand(side)


## Która ręka pracuje w tym punkcie ("l", "r" albo ""). Przy wbijaniu: ręka z młotkiem.
func side_for(p) -> String:
	var l = hand("l")
	var r = hand("r")
	match p.kind:
		"attach":
			return "r" if _mounts(r, p) else ("l" if _mounts(l, p) else "")
		"strike":
			if _is_nails(l) and tool_level(r, p.ability) >= p.min_level:
				return "r"
			if _is_nails(r) and tool_level(l, p.ability) >= p.min_level:
				return "l"
			return ""
	if tool_level(r, p.ability) >= p.min_level:
		return "r"
	if tool_level(l, p.ability) >= p.min_level:
		return "l"
	return ""


## Rodzaj pracy w punkcie: "remove", "place" albo "mount" (kolor znacznika).
func category(p) -> String:
	if p.owner != null and p.owner.has_method("work_category"):
		var c: String = p.owner.work_category(p)
		if c != "":
			return c
	match p.kind:
		"attach":
			return "place"
		"strike", "rotate":
			return "mount"
	return "remove"


func usable(p) -> bool:
	return p.enabled and side_for(p) != ""


func is_active() -> bool:
	return active != null


## Czy mysz jest teraz przy narzędziu (trzymany przycisk pracy).
func is_locked() -> bool:
	return holds["l"] or holds["r"]


func _physics_process(delta: float) -> void:
	if main == null or main.player == null:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	if _swing >= 0.0:
		_swing += delta
		if _swing < SWING_HIT:
			_impact = _swing / SWING_HIT
		elif _swing < SWING_HOLD:
			_impact = 1.0
		elif _swing < SWING_END:
			_impact = 1.0 - (_swing - SWING_HOLD) / (SWING_END - SWING_HOLD)
		else:
			_impact = 0.0
			_swing = -1.0
		if _pending != null and (_swing >= SWING_HIT or _swing < 0.0):
			var pd: Dictionary = _pending
			_pending = null
			if pd["point"].enabled:
				pd["point"].owner.work_apply(pd["point"], pd["ev"])
	var cam_pos: Vector3 = main.player.camera.global_position
	if active != null:
		var lost: bool = not active.enabled or tool_level(hand(active_side), active.ability) < active.min_level
		if lost or cam_pos.distance_to(active.world_pos()) > REACH + 0.3:
			active = null  # przycisk dalej trzymany: kamera stoi do puszczenia
	if nail_point != null:
		if not nail_point.enabled or not _is_nails(hand(nail_side)) or cam_pos.distance_to(nail_point.world_pos()) > REACH + 0.3:
			nail_point = null
	if active == null and nail_point == null:
		var busy: bool = (main.interaction != null and main.interaction.grab_mode) or (main.combat != null and main.combat.active)
		candidate = null if busy else find_candidate()
		if candidate == null and not busy and hand_work != null:
			var hp = hand_work.candidate()
			if hp != null and usable(hp):
				candidate = hp
	_update_markers()
	_update_hud()
	_update_pose()


## Punkt pracy najbliżej linii wzroku (ten, w który celujesz), niezasłonięty.
func find_candidate():
	var cam: Camera3D = main.player.camera
	var o := cam.global_position
	var dir := -cam.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(o, o + dir * REACH)
	q.exclude = [main.player.get_rid()]
	var hit: Dictionary = main.player.get_world_3d().direct_space_state.intersect_ray(q)
	var block: float = REACH if hit.is_empty() else o.distance_to(hit["position"])
	var best = null
	var best_off := INF
	for p in points:
		if not usable(p):
			continue
		var wp: Vector3 = p.world_pos()
		var t := (wp - o).dot(dir)
		if t < 0.1 or t > float(KIND_REACH.get(p.kind, REACH)) or t > block + 0.12:
			continue
		var off := (wp - (o + dir * t)).length()
		if off > RAY_TOLERANCE:
			continue
		if off < best_off:
			best = p
			best_off = off
	return best


## Naciśnięcie przycisku ręki ("l" lewy, "r" prawy). Zwraca, czy była to praca.
func press(side: String) -> bool:
	var it = hand(side)
	# druga ręka trzyma gwóźdź: ta ręka uderza młotkiem
	if nail_point != null and side != nail_side:
		if tool_level(it, nail_point.ability) >= nail_point.min_level:
			holds[side] = true
			_strike(nail_point, side)
			return true
		return false
	var p = candidate
	if p == null or active != null:
		return false
	match p.kind:
		"attach":
			if _mounts(it, p):
				p.owner.work_apply(p, {"type": "attach", "item": it, "side": side})
				return true
		"strike":
			if _is_nails(it) and side_for(p) != "":
				nail_point = p
				nail_side = side
				holds[side] = true
				return true
		_:
			if tool_level(it, p.ability) >= p.min_level:
				active = p
				active_side = side
				holds[side] = true
				_virtual = Vector2(60, 0)
				return true
	return false


func release(side: String) -> void:
	holds[side] = false
	if active_side == side:
		active = null
		active_side = ""
	if nail_side == side:
		nail_point = null
		nail_side = ""


## Praca prawą ręką (zgodność ze starszym kodem i testami).
func begin() -> bool:
	return press("r")


func end() -> void:
	release("l")
	release("r")
	active = null
	active_side = ""
	nail_point = null
	nail_side = ""


## Przyłożenie części ręką, która ją trzyma.
func attach() -> bool:
	if candidate == null or candidate.kind != "attach":
		return false
	var side := side_for(candidate)
	return side != "" and press(side)


## Ruch myszy przy trzymanym przycisku: prowadzi narzędzie zamiast kamery.
func mouse(rel: Vector2) -> void:
	if active == null:
		return
	var it = hand(active_side if active_side != "" else "r")
	var lvl := tool_level(it, active.ability)
	match active.kind:
		"lever":
			if rel.y > 0.0:
				var amount := rel.y * LEVER_RATE * (lvl / 3.0) * arm_factor(it)
				if main.inventory.hands_two():
					amount *= TWO_HAND_LEVER  # oburącz łom podważa mocniej
				amount *= main.health.arm_factor(active_side if active_side != "" else "r")
				_phase = fmod(_phase + rel.y * 0.006, 1.0)
				active.owner.work_apply(active, {"type": "lever", "amount": amount, "tool": it})
		"rotate":
			var prev := _virtual
			_virtual += rel
			if _virtual.length() > 200.0:
				_virtual = _virtual.normalized() * 200.0
			if prev.length() > 15.0 and _virtual.length() > 15.0:
				rotate_by(wrapf(_virtual.angle() - prev.angle(), -PI, PI) / TAU)


func wheel(steps: float) -> void:
	if active != null and active.kind == "rotate":
		rotate_by(steps * WHEEL_TURN)


## Obrót wkrętaka o podaną liczbę obrotów (dodatnie: wkręcanie).
func rotate_by(turns: float) -> void:
	if active == null:
		return
	var side := active_side if active_side != "" else "r"
	var it = hand(side)
	var lvl := tool_level(it, active.ability)
	_phase += turns
	active.owner.work_apply(active, {"type": "rotate", "turns": turns * (lvl / 3.0), "raw": turns, "tool": it})


func cooldown_left() -> float:
	return _cooldown


func _strike(p, side: String) -> void:
	if _cooldown > 0.0:
		return
	_cooldown = STRIKE_COOLDOWN / maxf(0.4, main.health.arm_factor(side))  # ranna ręka bije wolniej
	_swing = 0.0
	var it = hand(side)
	var amount := tool_level(it, p.ability) / 3.0
	# uderzenie liczy się w chwili, gdy obuch dochodzi do gwoździa (dźwięk w tym samym momencie)
	_pending = {"point": p, "ev": {"type": "strike", "amount": amount, "tool": it, "nail_side": nail_side}}


# --- podpowiedzi, znaczniki, poza dłoni -----------------------------------------

func _btn(side: String) -> String:
	return tr("BTN_L") if side == "l" else tr("BTN_R")


func _update_hud() -> void:
	var hud = main.hud
	var shown = active if active != null else nail_point
	if shown != null:
		var st: Dictionary = shown.owner.work_status(shown)
		var text := str(st.get("text", "")) if show_bars else tr(shown.label_key)
		if shown == nail_point:
			text += " · " + tr("WORK_KEY_HIT") % _btn(other(nail_side))
		hud.set_work(text, float(st.get("ratio", -1.0)) if show_bars else -1.0)
	elif candidate != null:
		var side := side_for(candidate)
		var key := ""
		match candidate.kind:
			"attach":
				key = tr("WORK_KEY_ATTACH") % _btn(side)
			"strike":
				key = tr("WORK_KEY_NAIL") % [_btn(other(side)), _btn(side)]
			_:
				key = tr("WORK_KEY_TOOL") % _btn(side)
		hud.set_work("%s · %s" % [tr(candidate.label_key), key], -1.0)
	else:
		hud.set_work("", -1.0)


func _update_markers() -> void:
	var cam_pos: Vector3 = main.player.camera.global_position
	for p in points:
		var show: bool = highlights and usable(p) and cam_pos.distance_to(p.world_pos()) <= MARKER_RANGE
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
		var cat := category(p)
		if m.get_meta("cat", "") != cat:
			m.set_meta("cat", cat)
			m.material_override = _mark_mat(cat)
		var big: bool = p == candidate or p == active or p == nail_point
		m.scale = Vector3.ONE * (1.6 if big else 1.0)


func _mark_mat(cat: String) -> Material:
	if not _mark_mats.has(cat):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = MARK_COLORS[cat]
		_mark_mats[cat] = Psx.material(mat)
	return _mark_mats[cat]


func _make_marker() -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3(0.022, 0.022, 0.022)
	var m := MeshInstance3D.new()
	m.mesh = box
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.top_level = true
	main.world.add_child(m)
	return m


## Dłonie idą do punktu pracy: ręka z narzędziem na punkt; przy wbijaniu jedna
## przytrzymuje gwóźdź, a druga z młotkiem wisi nad nim i opada przy uderzeniu.
func _update_pose() -> void:
	if main.combat != null and main.combat.active:
		return  # w walce dłonie ustawia system walki
	var player = main.player
	var targets := {"l": null, "r": null}
	var rots := {"l": null, "r": null}
	var roll := 0.0
	if active != null:
		var lift := 0.0
		if active.kind == "lever":
			lift = -0.05 * sin(_phase * TAU)
		elif active.kind == "rotate":
			roll = _phase * TAU
		targets[active_side] = active.world_pos() + Vector3.UP * lift
	if nail_point != null:
		var np: Vector3 = nail_point.world_pos()
		var cam_pos: Vector3 = player.camera.global_position
		var toward: Vector3 = Vector3(cam_pos.x - np.x, 0.0, cam_pos.z - np.z).normalized()
		var side_ax := Vector3.UP.cross(toward).normalized()  # w prawo patrząc na gwóźdź
		var face_basis := Basis(side_ax, Vector3.UP, toward)  # przód dłoni (-Z) w stronę ściany
		var hit_basis := Basis(side_ax, deg_to_rad(-18.0)) * face_basis  # obuch lekko wychylony do ściany
		# ręka z gwoździami: palce przy gwoździu, trochę pod nim i z boku
		var hold_sign := -1.0 if nail_side == "l" else 1.0
		targets[nail_side] = np + toward * 0.035 - Vector3.UP * 0.035 + side_ax * 0.035 * hold_sign
		rots[nail_side] = face_basis.get_rotation_quaternion()
		# ręka z młotkiem: zamach przód-tył. Trzonek pionowo, obuch w stronę ściany;
		# przy uderzeniu powierzchnia obucha trafia w łepek, potem młotek wraca
		# do tyłu (przechylony ku graczowi) i czeka na następne kliknięcie.
		var hs := other(nail_side)
		var it = hand(hs)
		var length := 0.32
		if it != null:
			length = float(it.get_def().get("model", {}).get("size", [0.32])[0])
		var face_local := Vector3(0, length * 0.12 + length * 0.42, -0.06)  # powierzchnia obucha w układzie dłoni
		var swing := _impact * _impact
		var back_basis := Basis(side_ax, deg_to_rad(65.0)) * hit_basis
		var hb: Basis = back_basis.slerp(hit_basis, swing)
		var hit_palm := np + toward * 0.004 - hit_basis * face_local
		var back_palm := hit_palm + toward * 0.1 - Vector3.UP * 0.04
		targets[hs] = back_palm.lerp(hit_palm, swing)
		rots[hs] = hb.get_rotation_quaternion()
	player.work_targets = targets
	player.work_rots = rots
	player.work_roll = roll
	player.work_side = active_side
