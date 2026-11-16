extends Node
## Broń palna. Działa w trybie walki (domyślnym), gdy w prawej ręce jest broń:
##   lewy przycisk: strzał,
##   prawy przytrzymany: przyrządy celownicze (mniejszy rozrzut, przybliżenie),
##   R: przeładowanie (magazynek albo naboje do rury), a przy zacięciu: przeładowanie
##      zamka, które wyrzuca zacięty nabój.
## Wszystko jest fizyczne i ręczne:
##   - naboje ładuje się do magazynka w ekwipunku: przeciągnij naboje na magazynek,
##     prawy przycisk na magazynku (albo broni) rozładowuje do ekwipunku,
##   - magazynek wymienia się R (stary wraca do ekwipunku), po włożeniu trzeba
##     przeładować zamek, żeby nabój wszedł do komory (robi się to samo, gdy komora pusta),
##   - strzelba pompowa: R wkłada naboje do rury po jednym, po strzale postać sama
##     przeładowuje pompką (chwila przerwy),
##   - każdy strzał brudzi broń; brud, zużycie i brak smaru zwiększają szansę zacięcia.
##     Czyszczenie: broń w lewej ręce, szmata / wycior / WD-40 w prawej, ruchy myszą
##     (praca w dłoni). WD-40 smaruje: przez kilkadziesiąt strzałów zacięć prawie nie ma.
## Strzał to bardzo głośny hałas (zombie z daleka), błysk i dym z lufy, łuska.
## Bez celownika na ekranie (jak w Iron Blight): pocisk wylatuje z lufy w kierunku,
## w który lufa faktycznie wskazuje. Z biodra broń buja się w rękach, więc strzał
## idzie mniej więcej tam, gdzie patrzysz; przy celowaniu muszka i szczerbinka są na osi wzroku.
## Odrzut podrzuca dłonie i broń (kamera tylko lekko), zamek odskakuje, łuska wylatuje.
## Przeładowanie pistoletu: obrót broni, pusty magazynek wypada na ziemię, nowy od dołu,
## zamek. Dwururka: łamanie, puste łuski wypadają, naboje po jednym, zatrzaśnięcie.
## Pole "gun" w items.json: kaliber, sposób zasilania, obrażenia, rozrzut, odrzut...

const ItemScript := preload("res://scripts/inventory/item.gd")
const WorldItems := preload("res://scripts/world_items.gd")

const ADS_TIME := 0.2
const HIP_POS := Vector3(0.16, -0.19, -0.42)
const HIP_PISTOL := Vector3(0.11, -0.2, -0.34)
const HIP_LONG := Vector3(0.15, -0.2, -0.3)
const ADS_DIST := 0.34
const DECALS_MAX := 40
const CASINGS_MAX := 80
const CASING_LAYER := 1 << 10     # łuski: nie blokują promieni strzału ani chwytu
const SHOT_MASK := 0xFFFFFFFF & ~CASING_LAYER

var main
var ads := false
var state := "idle"           # idle, reload, rack, pump, load
var shots: Array = []         # ostatnie strzały (testy)
var _cool := 0.0
var _t := 0.0
var _steps: Array = []        # kroki przeładowania: [czas, nazwa]
var _blend := 0.0             # 0 biodro, 1 przyrządy
var _kick := 0.0              # odrzut pozy (cofa broń)
var _recover := Vector2.ZERO  # część odrzutu kamery do oddania
var _flash: OmniLight3D
var _flash_t := 0.0
var _decals: Array = []
var _label: Label
var _rng := RandomNumberGenerator.new()
var casings: Array = []          # łuski na podłodze (najstarsze znikają)
var casings_total := 0           # wszystkie wyrzucone (testy)
var _slide := 0.0                # odskok zamka po strzale 0..1
var _bob_t := 0.0
var _time := 0.0
var _flash_mesh: MeshInstance3D


func setup(main_node) -> void:
	main = main_node
	_rng.seed = 1203
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.8, 0.45)
	_flash.omni_range = 6.0
	_flash.light_energy = 0.0
	main.world.add_child(_flash)
	_flash_mesh = _make_flash_mesh()
	main.world.add_child(_flash_mesh)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.72))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_label.position = Vector2(-340, -120)
	_label.size = Vector2(320, 60)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	layer.add_child(_label)


# --- stan broni ----------------------------------------------------------------

static func gun_def(it) -> Dictionary:
	return {} if it == null else it.get_def().get("gun", {})


## Broń w prawej ręce (albo null).
func current():
	var it = main.inventory.hand("r")
	return it if not gun_def(it).is_empty() else null


## Naboje w broni: [w magazynku/rurze, w komorze].
static func rounds(gun) -> Array:
	var g := gun_def(gun)
	var in_feed := 0
	if str(g.get("feed", "mag")) == "tube":
		in_feed = int(gun.props.get("tube", 0))
	else:
		var mag = gun.props.get("mag")
		if mag is Dictionary:
			in_feed = int((mag as Dictionary).get("props", {}).get("rounds", 0))
	return [in_feed, 1 if bool(gun.props.get("chamber", false)) else 0]


static func mag_rounds(mag) -> int:
	return int(mag.props.get("rounds", 0))


static func _feed_take(gun) -> bool:
	var g := gun_def(gun)
	if str(g.get("feed", "mag")) == "tube":
		var t := int(gun.props.get("tube", 0))
		if t <= 0:
			return false
		gun.props["tube"] = t - 1
		return true
	var mag = gun.props.get("mag")
	if not mag is Dictionary:
		return false
	var pr: Dictionary = (mag as Dictionary).get("props", {})
	var n := int(pr.get("rounds", 0))
	if n <= 0:
		return false
	pr["rounds"] = n - 1
	(mag as Dictionary)["props"] = pr
	return true


func is_ads() -> bool:
	return ads and _blend > 0.5


# --- wejście -------------------------------------------------------------------

func press(button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		ads = true
	elif button == MOUSE_BUTTON_LEFT:
		shoot()


func release(button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		ads = false


func shoot() -> bool:
	var gun = current()
	if gun == null or _cool > 0.0:
		return false
	if state != "idle":
		if state == "load":
			_steps.clear()  # strzał przerywa wkładanie naboi
			state = "idle"
		else:
			return false
	var g := gun_def(gun)
	if bool(gun.props.get("jammed", false)):
		main.sound.play("gun_click", _muzzle(), -4.0, 0.8)
		main.hud.show_message(tr("MSG_GUN_JAMMED"))
		_cool = 0.3
		return false
	if not bool(gun.props.get("chamber", false)):
		main.sound.play("gun_click", _muzzle(), -4.0)
		main.hud.show_message(tr("MSG_GUN_EMPTY") if rounds(gun)[0] == 0 else tr("MSG_GUN_RACK"))
		_cool = 0.3
		return false
	_fire(gun, g)
	return true


func _fire(gun, g: Dictionary) -> void:
	var skill: int = main.character.level("bron_palna")
	_cool = float(g.get("rof", 0.25))
	gun.props["chamber"] = false
	# promienie od oka (przyrządy) z rozrzutem: biodro, ruch, jedna ręka przy broni dwuręcznej
	var cam: Camera3D = main.player.camera
	var spread := lerpf(float(g.get("spread_hip", 3.5)), float(g.get("spread_ads", 0.5)), _blend)
	spread *= 1.0 - skill * 0.07
	if Vector2(main.player.velocity.x, main.player.velocity.z).length() > 1.0:
		spread += 1.2
	var one_handed: bool = bool(g.get("two_handed", false)) and not main.inventory.hands_two()
	if one_handed:
		spread *= 2.0
	spread *= 1.0 + (1.0 - main.health.arm_factor("r")) * 1.5
	var pellets := int(g.get("pellets", 1))
	var dmg := float(g.get("damage", 40.0))
	var rng_max := float(g.get("range", 60.0))
	# pocisk wylatuje z lufy w kierunku lufy (bez celownika: z biodra „na pałę”)
	var origin := _muzzle()
	var barrel := _barrel_basis()
	var record := {"gun": gun.def_id, "hits": [], "spread": spread, "ads": is_ads(), "origin": origin, "dir": -barrel.z}
	var space: PhysicsDirectSpaceState3D = main.player.get_world_3d().direct_space_state
	# lufa wsadzona w ścianę: pocisk trafia w przeszkodę między okiem a wylotem
	var q0 := PhysicsRayQueryParameters3D.create(cam.global_position, origin)
	q0.exclude = [main.player.get_rid()]
	q0.collision_mask = SHOT_MASK
	var blocked: Dictionary = space.intersect_ray(q0)
	for k in pellets:
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * deg_to_rad(spread)
		var dir := (barrel * Vector3(cos(a) * sin(r), sin(a) * sin(r), -cos(r))).normalized()
		var h: Dictionary = blocked
		if h.is_empty():
			var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * rng_max)
			q.exclude = [main.player.get_rid()]
			q.collision_mask = SHOT_MASK
			h = space.intersect_ray(q)
		if h.is_empty():
			continue
		var dist: float = origin.distance_to(h["position"])
		var falloff := clampf(1.0 - (dist / rng_max) * float(g.get("falloff", 0.4)), 0.2, 1.0)
		var hit := _impact(h, dir, dmg * falloff)
		record["hits"].append(hit)
	shots.append(record)
	if shots.size() > 20:
		shots.pop_front()
	# brud, zużycie i zacięcie (smar z WD-40 chroni)
	var dirt := float(gun.props.get("dirt", 0.0)) + float(g.get("dirt_per_shot", 0.006))
	gun.props["dirt"] = minf(1.0, dirt)
	gun.props["condition"] = maxf(0.0, gun.condition() - float(g.get("wear", 0.0015)))
	var oiled := int(gun.props.get("oiled", 0))
	if oiled > 0:
		gun.props["oiled"] = oiled - 1
	var jam: float = 0.003 + dirt * dirt * 0.35 + (1.0 - gun.condition()) * 0.12
	jam *= 0.25 if oiled > 0 else 1.0
	jam *= 1.0 - skill * 0.06
	# ponowne zasilenie komory: półautomat od razu, pompka po chwili
	var jammed: bool = _rng.randf() < jam
	var action := str(g.get("action", "semi"))
	if action == "semi":
		_eject(gun, 1)
		if _feed_take(gun):
			gun.props["chamber"] = true
			if jammed:
				gun.props["jammed"] = true
	elif action == "break":
		# druga lufa: następny strzał od razu, łuski zostają w lufach do złamania
		if _feed_take(gun):
			gun.props["chamber"] = true
	else:
		gun.props["spent"] = true
		if jammed:
			gun.props["jammed"] = true
		else:
			_begin([[float(g.get("pump_time", 0.55)) * (1.0 - skill * 0.05), "pump"]], "pump")
	if bool(gun.props.get("jammed", false)):
		main.hud.show_message(tr("MSG_GUN_JAMMED"))
	# efekty: dźwięk, hałas dla zombie, błysk, odrzut
	main.sound.play(str(g.get("sound", "gunshot")), _muzzle(), 6.0, _rng.randf_range(0.95, 1.05))
	main.noise.emit_noise(origin, float(g.get("noise", 100.0)), "NOISE_GUNSHOT")
	_flash.global_position = _muzzle()
	_flash.light_energy = 3.5
	_flash_t = 0.05
	_show_flash(float(g.get("pellets", 1)) > 1.0)
	_smoke(_muzzle(), -barrel.z, 14 if int(g.get("pellets", 1)) > 1 else 6)
	# odrzut: głównie dłonie i broń (poza), kamera tylko lekko
	var kick := float(g.get("recoil", 2.5)) * (1.0 - skill * 0.06) * (1.6 if one_handed else 1.0)
	kick *= lerpf(1.0, 0.8, _blend)
	var yaw := _rng.randf_range(-0.35, 0.35) * kick
	main.player.add_recoil(deg_to_rad(kick * 0.35), deg_to_rad(yaw * 0.35))
	_recover = Vector2(deg_to_rad(kick), deg_to_rad(yaw)) * 0.35 * 0.55
	_kick = 1.0
	_slide = 1.0
	main.character.add_xp("bron_palna", 2.0)


## Trafienie jednego promienia: zombie, szyba, bryła, ściana. Zwraca opis.
func _impact(h: Dictionary, dir: Vector3, dmg: float) -> Dictionary:
	var col: Object = h["collider"]
	var pos: Vector3 = h["position"]
	var out := {"target": col, "pos": pos, "damage": dmg}
	if col.has_method("take_hit"):
		out["killed"] = col.take_hit(dmg, pos, dir, dmg > 30.0)
		if col.has_meta("glass") or not col.has_method("shove"):
			return out
		main.character.add_xp("bron_palna", 3.0)
		return out
	if col is RigidBody3D and not (col as RigidBody3D).freeze:
		var b := col as RigidBody3D
		b.sleeping = false
		b.apply_impulse(dir * dmg * 0.08, pos - b.global_position)
	var snd := "impact_wood"
	if col.has_meta("hit_sound"):
		snd = str(col.get_meta("hit_sound"))
	elif col.has_meta("item") and col.get_meta("item").material() == "metal":
		snd = "impact_metal"
	main.sound.play(snd, pos, -6.0, 1.3)
	_decal(pos, h.get("normal", -dir), col)
	return out


func _decal(pos: Vector3, normal: Vector3, col: Object) -> void:
	var d := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.035)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.04, 0.035)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = m
	d.mesh = q
	d.set_meta("psx_skip", true)
	var parent: Node3D = col as Node3D if col is RigidBody3D else main.world
	parent.add_child(d)
	var n := normal.normalized()
	var up := Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT
	d.global_transform = Transform3D(Basis.looking_at(-n, up), pos + n * 0.003)
	_decals.append(d)
	while _decals.size() > DECALS_MAX:
		var old = _decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()


# --- przeładowanie -------------------------------------------------------------

## R: zacięcie -> przeładowanie zamka; magazynek -> wymiana na najpełniejszy;
## rura -> wkładanie naboi po jednym; pusta komora -> przeładowanie zamka.
func reload() -> bool:
	var gun = current()
	if gun == null or state != "idle":
		return false
	var g := gun_def(gun)
	var speed: float = 1.0 - main.character.level("bron_palna") * 0.07
	if bool(gun.props.get("jammed", false)):
		_begin([[0.7 * speed, "clear"]], "rack")
		return true
	if str(g.get("action", "")) == "break":
		var missing: int = int(g.get("capacity", 1)) + 1 - int(gun.props.get("tube", 0)) - (1 if bool(gun.props.get("chamber", false)) else 0)
		if missing <= 0:
			return false
		var have: int = main.inventory.count_of(str(g.get("ammo", "")))
		if have <= 0:
			main.hud.show_message(tr("MSG_NO_AMMO"))
			return false
		var bsteps: Array = [[0.45 * speed, "open"]]
		for k in mini(missing, have):
			bsteps.append([0.42 * speed, "bshell"])
		bsteps.append([0.35 * speed, "close"])
		_begin(bsteps, "break")
		return true
	if str(g.get("feed", "mag")) == "tube":
		if int(gun.props.get("tube", 0)) >= int(g.get("capacity", 5)):
			return _rack_if_empty(gun, speed)
		if main.inventory.count_of(str(g.get("ammo", ""))) <= 0:
			main.hud.show_message(tr("MSG_NO_AMMO"))
			return _rack_if_empty(gun, speed)
		_begin([[0.5 * speed, "shell"]], "load")
		return true
	var best = _best_mag(gun)
	if best == null:
		if gun.props.get("mag") is Dictionary and not bool(gun.props.get("chamber", false)) and rounds(gun)[0] > 0:
			return _rack_if_empty(gun, speed)
		main.hud.show_message(tr("MSG_NO_MAG"))
		return false
	var steps: Array = []
	if gun.props.get("mag") is Dictionary:
		steps.append([0.45 * speed, "mag_out"])
	steps.append([0.6 * speed, "mag_in"])
	if not bool(gun.props.get("chamber", false)):
		steps.append([0.4 * speed, "rack"])
	_begin(steps, "reload")
	return true


func _rack_if_empty(gun, speed: float) -> bool:
	if bool(gun.props.get("chamber", false)) or rounds(gun)[0] == 0:
		return false
	_begin([[0.45 * speed, "rack"]], "rack")
	return true


## Najpełniejszy pasujący magazynek w ekwipunku (pełniejszy niż ten w broni).
func _best_mag(gun):
	var g := gun_def(gun)
	var have: int = rounds(gun)[0] if gun.props.get("mag") is Dictionary else -1
	var best = null
	for it in main.inventory.all_carried():
		if it.def_id == str(g.get("mag", "")) and not it.pending and mag_rounds(it) > have:
			if best == null or mag_rounds(it) > mag_rounds(best):
				best = it
	return best


func _begin(steps: Array, new_state: String) -> void:
	_steps = steps
	state = new_state
	_t = 0.0


func _step_done(name: String) -> void:
	var gun = current()
	if gun == null:
		_steps.clear()
		return
	var g := gun_def(gun)
	match name:
		"mag_out":
			var old = ItemScript.from_dict(gun.props["mag"], ItemScript)
			gun.props.erase("mag")
			_drop_mag(old)
			main.sound.play("mag_out", _muzzle(), -4.0)
		"mag_in":
			var best = _best_mag(gun)
			if best != null:
				main.inventory.remove_item(best)
				gun.props["mag"] = best.to_dict()
				main.sound.play("mag_in", _muzzle(), -2.0)
		"open":
			# złamanie: puste łuski wypadają z luf
			var loaded: int = int(gun.props.get("tube", 0)) + (1 if bool(gun.props.get("chamber", false)) else 0)
			_eject(gun, int(g.get("capacity", 1)) + 1 - loaded)
			main.sound.play("mag_out", _muzzle(), -2.0, 0.7)
		"bshell":
			if main.inventory.consume(str(g.get("ammo", "")), 1):
				if not bool(gun.props.get("chamber", false)):
					gun.props["chamber"] = true
				else:
					gun.props["tube"] = int(gun.props.get("tube", 0)) + 1
				main.sound.play("shell_in", _muzzle(), -4.0)
		"close":
			main.sound.play("gun_rack", _muzzle(), -1.0, 0.8)
		"rack", "pump", "clear":
			if name == "clear":
				gun.props["jammed"] = false
				gun.props["chamber"] = false  # zacięty nabój wylatuje
				_eject(gun, 1)
			elif bool(gun.props.get("spent", false)):
				gun.props.erase("spent")
				_eject(gun, 1)  # pompka wyrzuca pustą łuskę
			if not bool(gun.props.get("chamber", false)) and _feed_take(gun):
				gun.props["chamber"] = true
			main.sound.play("gun_rack" if name != "pump" else "gun_pump", _muzzle(), -2.0)
		"shell":
			var ammo := str(g.get("ammo", ""))
			if int(gun.props.get("tube", 0)) < int(g.get("capacity", 5)) and main.inventory.consume(ammo, 1):
				gun.props["tube"] = int(gun.props.get("tube", 0)) + 1
				main.sound.play("shell_in", _muzzle(), -4.0)
				# następny nabój, dopóki jest miejsce i amunicja
				if int(gun.props["tube"]) < int(g.get("capacity", 5)) and main.inventory.count_of(ammo) > 0:
					_steps.append([0.5 * (1.0 - main.character.level("bron_palna") * 0.07), "shell"])
				elif not bool(gun.props.get("chamber", false)):
					_steps.append([0.5, "pump"])
	main.inventory.changed.emit()


# --- ładowanie magazynków i rozładowanie (ekwipunek) ----------------------------------

## Naboje przeciągnięte na magazynek albo broń z rurą: ładuje, ile się zmieści.
## Zwraca liczbę włożonych naboi (0: nie pasuje).
func load_into(ammo, target) -> int:
	var cal := str(ammo.get_def().get("ammo", {}).get("caliber", ""))
	if cal == "":
		return 0
	var space := 0
	var mg: Dictionary = target.get_def().get("magazine", {})
	var g := gun_def(target)
	if not mg.is_empty() and str(mg.get("caliber", "")) == cal:
		space = int(mg.get("capacity", 10)) - mag_rounds(target)
	elif str(g.get("feed", "")) == "tube" and str(g.get("caliber", "")) == cal:
		space = int(g.get("capacity", 5)) - int(target.props.get("tube", 0))
	else:
		return 0
	var n := mini(space, ammo.count)
	if n <= 0:
		return 0
	if not mg.is_empty():
		target.props["rounds"] = mag_rounds(target) + n
	else:
		target.props["tube"] = int(target.props.get("tube", 0)) + n
	ammo.count -= n
	if ammo.count <= 0:
		main.inventory.remove_item(ammo)
	main.sound.play_ui("shell_in")
	main.inventory.changed.emit()
	return n


## Prawy przycisk na magazynku albo broni w ekwipunku: naboje (i magazynek) do ekwipunku.
func unload(item) -> bool:
	var mg: Dictionary = item.get_def().get("magazine", {})
	var g := gun_def(item)
	if not mg.is_empty():
		var n := mag_rounds(item)
		if n <= 0:
			return false
		item.props["rounds"] = 0
		main.inventory.give(ItemScript.new(str(mg.get("ammo", "")), n))
	elif not g.is_empty():
		var n := 0
		if bool(item.props.get("chamber", false)):
			n += 1
			item.props["chamber"] = false
		item.props["jammed"] = false
		if str(g.get("feed", "mag")) == "tube":
			n += int(item.props.get("tube", 0))
			item.props["tube"] = 0
		elif item.props.get("mag") is Dictionary:
			main.inventory.give(ItemScript.from_dict(item.props["mag"], ItemScript))
			item.props.erase("mag")
		if n > 0:
			main.inventory.give(ItemScript.new(str(g.get("ammo", "")), n))
	else:
		return false
	main.sound.play_ui("mag_out")
	main.inventory.changed.emit()
	return true


# --- klatka: czasy, kamera, poza, napis ---------------------------------------

func _physics_process(delta: float) -> void:
	if main == null or main.player == null:
		return
	_cool = maxf(0.0, _cool - delta)
	_kick = move_toward(_kick, 0.0, delta * 6.0)
	_slide = move_toward(_slide, 0.0, delta * 14.0)
	_time += delta
	var hspeed := Vector2(main.player.velocity.x, main.player.velocity.z).length()
	_bob_t += delta * hspeed * 2.2
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash.light_energy = 0.0
			_flash_mesh.visible = false
	# oddawanie części odrzutu kamery (ręce wracają na cel)
	if _recover.length() > 0.0001:
		var step := _recover * minf(1.0, delta * 6.0)
		main.player.add_recoil(-step.x, -step.y)
		_recover -= step
	var gun = current()
	var in_combat: bool = main.combat.active
	if gun == null or not in_combat:
		ads = false
		if gun == null and state != "idle":
			_steps.clear()
			state = "idle"
	if state != "idle":
		_t += delta
		if not _steps.is_empty() and _t >= float(_steps[0][0]):
			var s: Array = _steps.pop_front()
			_t = 0.0
			_step_done(str(s[1]))
		if _steps.is_empty():
			state = "idle"
	var want := 1.0 if ads and state == "idle" else 0.0
	_blend = move_toward(_blend, want, delta / ADS_TIME)
	var g := gun_def(gun)
	var fov := lerpf(75.0, float(g.get("ads_fov", 60.0)), _blend * _blend * (3.0 - 2.0 * _blend))
	main.player.camera.fov = fov
	main.player.sens_mult = lerpf(1.0, fov / 75.0, _blend)
	_update_label(gun)


func _update_label(gun) -> void:
	if gun == null:
		_label.text = ""
		return
	var g := gun_def(gun)
	var r := rounds(gun)
	var t := "%s  %d%s" % [gun.display_name(), r[0], " +1" if r[1] > 0 else ""]
	if str(g.get("feed", "mag")) == "mag" and not gun.props.get("mag") is Dictionary:
		t = "%s  %s" % [gun.display_name(), tr("GUN_NO_MAG")]
	t += "\n" + tr("GUN_SPARE") % main.inventory.count_of(str(g.get("ammo", "")))
	if bool(gun.props.get("jammed", false)):
		t += "  " + tr("GUN_JAMMED_TAG")
	elif state != "idle":
		t += "  " + tr("GUN_RELOADING_TAG")
	_label.text = t


## Wylot lufy w świecie (z modelu w dłoni), a bez modelu: przed kamerą.
func _muzzle() -> Vector3:
	var gun = current()
	var cam: Camera3D = main.player.camera
	if gun != null and main.player.body != null:
		var vis = main.player.body.hand_visual("r")
		if vis != null:
			var m: Array = gun_def(gun).get("muzzle", [0.2, 0.05, 0.0])
			return vis.global_transform * Vector3(float(m[0]), float(m[1]), float(m[2]))
	return cam.global_position - cam.global_transform.basis.z * 0.6


## Poza rąk z bronią (w układzie kamery): z biodra albo przy oku, kołysanie w marszu,
## odrzut (podrzut dłoni), przeładowanie krok po kroku. Ruchome części modelu
## (zamek, magazynek, lufy, czółenko) ustawia _apply_parts.
func update_pose() -> void:
	var gun = current()
	if gun == null:
		return
	var g := gun_def(gun)
	var player = main.player
	var cam: Transform3D = player.camera.global_transform
	var long_gun: bool = bool(g.get("two_handed", false))
	var hip: Vector3 = HIP_LONG if long_gun else HIP_PISTOL
	var sight := float(g.get("sight_y", 0.07))
	var ads_pos := Vector3(0.0, -sight, -float(g.get("ads_dist", ADS_DIST)))
	var k := _blend * _blend * (3.0 - 2.0 * _blend)
	var p := hip.lerp(ads_pos, k)
	# kołysanie: krok i oddech (przy celowaniu dużo mniejsze)
	var sway := 1.0 - 0.75 * k
	p += Vector3(sin(_bob_t) * 0.008, -absf(cos(_bob_t)) * 0.01 + sin(_time * 1.4) * 0.0025, 0.0) * sway
	var yaw_in := 0.0 if not long_gun else -0.06 * (1.0 - k)   # długa broń z biodra lekko skośnie
	var pitch := 0.0
	var roll := 0.0
	# odrzut: szybki podrzut lufy i cofnięcie dłoni
	var kick_up := pow(_kick, 0.7)
	pitch += kick_up * deg_to_rad(22.0 if long_gun else 15.0)
	p.z += kick_up * (0.06 if long_gun else 0.035)
	p.y += kick_up * 0.012
	var sup: Array = g.get("support", [0.0, -0.03, 0.0])
	var left_off := Vector3(float(sup[0]), float(sup[1]), float(sup[2]))
	var step := _cur_step()
	var u := _step_u()
	var e := sin(clampf(u, 0.0, 1.0) * PI)
	match state:
		"reload":
			# pistolet: obrót bokiem, lewa dłoń po magazynek i z powrotem, zamek
			p = hip + Vector3(-0.07, 0.05, 0.06)
			pitch = deg_to_rad(12.0)
			match step:
				"mag_out":
					roll = deg_to_rad(-60.0) * smoothstep(0.0, 0.35, u)
					left_off = Vector3(-0.05, -0.1 - 0.06 * u, 0.06)
				"mag_in":
					roll = deg_to_rad(-60.0)
					left_off = Vector3(-0.01, -0.17 + 0.13 * smoothstep(0.0, 0.9, u), 0.03)
				"rack":
					roll = deg_to_rad(-60.0) * (1.0 - smoothstep(0.0, 0.4, u)) - deg_to_rad(10.0)
					left_off = Vector3(0.0, 0.07, 0.03 + 0.04 * e)
		"rack", "pump":
			if str(g.get("action", "semi")) == "pump":
				left_off.z += float(g.get("pump_travel", 0.07)) * e  # pompka do siebie i z powrotem
			else:
				p += Vector3(-0.04, 0.03, 0.04)
				roll = deg_to_rad(-20.0)
				left_off = Vector3(0.0, 0.07, 0.03 + 0.04 * e)
		"load":
			# rura od spodu: broń obrócona, lewa dłoń z nabojem pod komorę
			p = hip + Vector3(-0.05, 0.04, 0.05)
			roll = deg_to_rad(70.0)
			left_off = Vector3(0.0, -0.1 + 0.06 * e, -0.12)
		"break":
			# dwururka: złamana, lufy w dół; naboje do komór; zatrzaśnięcie podrzutem
			p = hip + Vector3(-0.06, 0.05, 0.08)
			match step:
				"open":
					pitch = deg_to_rad(-25.0) * smoothstep(0.0, 0.5, u)
					left_off = Vector3(0.0, 0.0, -0.22)
				"bshell":
					pitch = deg_to_rad(-25.0)
					left_off = Vector3(-0.02, 0.02 - 0.14 * e, -0.06 - 0.06 * e)
				"close":
					pitch = deg_to_rad(-25.0) + deg_to_rad(45.0) * e
					left_off = Vector3(0.0, 0.0, -0.22)
	var dir := Vector3(sin(yaw_in) * cos(pitch), sin(pitch), -cos(yaw_in) * cos(pitch)).normalized()
	var base: Basis = main.combat._hand_basis(dir, false)
	var hb_local: Basis = Basis(dir, roll) * base if absf(roll) > 0.0001 else base
	var hb: Basis = cam.basis * hb_local
	player.work_targets = {"r": cam * p, "l": null}
	player.work_rots = {"r": hb.get_rotation_quaternion(), "l": null}
	if main.inventory.hand("l") == null or main.inventory.hands_two():
		# druga dłoń podtrzymuje: chwyt pistoletu albo łoże / pompka strzelby
		var lp: Vector3 = p + hb_local * left_off
		player.work_targets["l"] = cam * lp
		player.work_rots["l"] = (cam.basis * (base if state == "idle" else hb_local)).get_rotation_quaternion()
	player.work_roll = 0.0
	_apply_parts(gun, g)


func _cur_step() -> String:
	return str(_steps[0][1]) if not _steps.is_empty() else ""


func _step_u() -> float:
	return _t / maxf(0.01, float(_steps[0][0])) if not _steps.is_empty() else 1.0


## Ruchome części modelu w dłoni: zamek, magazynek, lufy dwururki, czółenko pompki.
func _apply_parts(gun, g: Dictionary) -> void:
	var vis = _vis()
	if vis == null:
		return
	var u := _step_u()
	var e := sin(clampf(u, 0.0, 1.0) * PI)
	var step := _cur_step()
	var zamek: Node3D = vis.get_node_or_null("zamek")
	if zamek != null:
		var back := _slide
		if state in ["reload", "rack"] and step == "rack":
			back = maxf(back, e)
		# pusty pistolet: zamek zostaje w tylnym położeniu
		if not bool(gun.props.get("chamber", false)) and rounds(gun)[0] == 0 and state == "idle":
			back = 1.0
		zamek.transform = (zamek.get_meta("rest") as Transform3D).translated(Vector3(-float(g.get("slide", 0.028)) * back, 0, 0))
	var mag: Node3D = vis.get_node_or_null("magazynek")
	if mag != null:
		var has_mag: bool = gun.props.get("mag") is Dictionary
		mag.visible = has_mag or (state == "reload" and step == "mag_in")
		var drop := 0.0
		if state == "reload" and step == "mag_in":
			drop = 0.12 * (1.0 - smoothstep(0.0, 0.9, u))  # nowy magazynek wsuwany od dołu
		mag.transform = (mag.get_meta("rest") as Transform3D).translated(Vector3(0, -drop, 0))
	var lufy: Node3D = vis.get_node_or_null("lufy")
	if lufy != null:
		var ang := 0.0
		if state == "break":
			match step:
				"open": ang = smoothstep(0.0, 0.6, u)
				"bshell": ang = 1.0
				"close": ang = 1.0 - smoothstep(0.3, 0.7, u)
		lufy.transform = (lufy.get_meta("rest") as Transform3D) * Transform3D(Basis(Vector3.BACK, -deg_to_rad(32.0) * ang), Vector3.ZERO)
	var czol: Node3D = vis.get_node_or_null("czolenko")
	if czol != null:
		var tr_back := 0.0
		if state in ["pump", "rack"]:
			tr_back = float(g.get("pump_travel", 0.07)) * e
		czol.transform = (czol.get_meta("rest") as Transform3D).translated(Vector3(-tr_back, 0, 0))


func _vis():
	if main.player == null or main.player.body == null:
		return null
	return main.player.body.hand_visual("r")


## Kierunek lufy: oś +X modelu w dłoni (bez modelu: kamera). Zwraca bazę, której -Z to lufa.
func _barrel_basis() -> Basis:
	var cam: Camera3D = main.player.camera
	var vis = _vis()
	if vis == null or current() == null:
		return cam.global_transform.basis
	var fwd: Vector3 = (vis.global_transform.basis.x as Vector3).normalized()
	var up := Vector3.UP if absf(fwd.y) < 0.95 else Vector3.BACK
	return Basis.looking_at(fwd, up)


## Łuski: wylatują w prawo i do góry, odbijają się i zostają na podłodze.
func _eject(gun, n: int) -> void:
	if n <= 0:
		return
	var g := gun_def(gun)
	var kind := str(g.get("casing", "luska_9mm"))
	var vis = _vis()
	var xf: Transform3D = vis.global_transform if vis != null else main.player.camera.global_transform
	var mesh: Mesh = WorldItems.library_mesh(kind)
	for k in n:
		var b := RigidBody3D.new()
		b.collision_layer = CASING_LAYER
		b.collision_mask = 1
		b.mass = 0.02
		b.set_meta("casing", true)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		if mesh != null:
			WorldItems._swap_gun_materials(mi)
		b.add_child(mi)
		var col := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(0.07, 0.022, 0.022) if kind == "luska_12" else Vector3(0.02, 0.01, 0.01)
		col.shape = sh
		b.add_child(col)
		main.world.add_child(b)
		b.add_collision_exception_with(main.player)  # wylatuje z wnętrza bryły gracza
		var at: Vector3 = xf * (Vector3(0.03, 0.068, 0.0) if kind == "luska_9mm" else Vector3(0.09, 0.025, 0.0))
		b.global_transform = Transform3D(xf.basis.orthonormalized() * Basis(Vector3.UP, _rng.randf_range(-0.4, 0.4)), at + Vector3(0, 0.01 * k, 0))
		var right: Vector3 = xf.basis.z.normalized()   # bok modelu (+Z) to prawa strona broni
		var up: Vector3 = xf.basis.y.normalized()
		var back: Vector3 = -xf.basis.x.normalized()
		var v: Vector3 = right * _rng.randf_range(1.2, 2.0) + up * _rng.randf_range(1.3, 2.0) + back * _rng.randf_range(0.0, 0.5)
		if kind == "luska_12" and str(g.get("action", "")) == "break":
			v = back * _rng.randf_range(0.8, 1.4) + up * _rng.randf_range(0.6, 1.0)  # wypadają z komór do tyłu
		b.linear_velocity = v + main.player.velocity
		b.angular_velocity = Vector3(_rng.randf_range(-20, 20), _rng.randf_range(-20, 20), _rng.randf_range(-20, 20))
		casings.append(b)
		casings_total += 1
		var snd_at := at
		get_tree().create_timer(0.45 + 0.1 * k).timeout.connect(func(): if is_instance_valid(main): main.sound.play("casing", snd_at + Vector3(0, -1.2, 0), -10.0, _rng.randf_range(0.9, 1.15)))
	while casings.size() > CASINGS_MAX:
		var old = casings.pop_front()
		if is_instance_valid(old):
			old.queue_free()


## Pusty magazynek wypada z broni na ziemię (można go podnieść i załadować).
func _drop_mag(old) -> void:
	var vis = _vis()
	if main.world_items == null:
		main.inventory.give(old)
		return
	var cam: Camera3D = main.player.camera
	var at: Vector3 = cam.global_position - cam.global_transform.basis.z * 0.35 + Vector3(0, -0.3, 0)
	if vis != null:
		var mag: Node3D = vis.get_node_or_null("magazynek")
		at = mag.global_position if mag != null else (vis.global_position as Vector3)
	var body: RigidBody3D = main.world_items.spawn(old, Transform3D(Basis(Vector3.BACK, PI / 2.0) * Basis(), at - Vector3(0, 0.03, 0)))
	# wypada z dłoni wewnątrz bryły gracza: bez zderzeń z nim, inaczej fizyka wystrzeliłaby go daleko
	body.add_collision_exception_with(main.player)
	var pl = main.player
	get_tree().create_timer(1.5).timeout.connect(func(): if is_instance_valid(body) and is_instance_valid(pl): body.remove_collision_exception_with(pl))
	body.linear_velocity = main.player.velocity + Vector3(0, -0.6, 0)
	body.angular_velocity = Vector3(_rng.randf_range(-4, 4), 0, _rng.randf_range(-4, 4))


func _make_flash_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _flash_texture()
	m.albedo_color = Color(1.0, 0.8, 0.45)
	q.material = m
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("psx_skip", true)
	mi.visible = false
	return mi


static func _flash_texture() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5)
			var r := d.length() / 16.0
			var star := absf(sin(atan2(d.y, d.x) * 4.0))
			var a := clampf(1.0 - r * (1.4 - 0.7 * star), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


func _show_flash(big: bool) -> void:
	_flash_mesh.global_position = _muzzle() + (-_barrel_basis().z) * 0.03
	_flash_mesh.scale = Vector3.ONE * (1.8 if big else 1.0) * _rng.randf_range(0.8, 1.2)
	_flash_mesh.visible = true


## Dym z lufy: kilka szarych kłębów, które unoszą się i rozwiewają.
func _smoke(at: Vector3, dir: Vector3, amount: int) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 1.6
	p.explosiveness = 0.85
	p.direction = dir
	p.spread = 18.0
	p.initial_velocity_min = 0.25
	p.initial_velocity_max = 0.8
	p.gravity = Vector3(0, 0.12, 0)
	p.damping_min = 1.2
	p.damping_max = 2.0
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.09
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(1, 3.2))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.75, 0.74, 0.7, 0.45))
	grad.set_color(1, Color(0.6, 0.6, 0.6, 0.0))
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _smoke_texture()
	q.material = m
	p.mesh = q
	main.world.add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(2.2).timeout.connect(p.queue_free)


static var _smoke_tex: ImageTexture


static func _smoke_texture() -> ImageTexture:
	if _smoke_tex != null:
		return _smoke_tex
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for y in 32:
		for x in 32:
			var r := Vector2(x - 15.5, y - 15.5).length() / 16.0
			var a := clampf(1.0 - r, 0.0, 1.0) * rng.randf_range(0.7, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	_smoke_tex = ImageTexture.create_from_image(img)
	return _smoke_tex
