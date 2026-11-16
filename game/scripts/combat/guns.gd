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
## Strzał to bardzo głośny hałas (zombie z daleka), błysk z lufy, odrzut kamery.
## Pole "gun" w items.json: kaliber, sposób zasilania, obrażenia, rozrzut, odrzut...

const ItemScript := preload("res://scripts/inventory/item.gd")

const ADS_TIME := 0.18
const HIP_POS := Vector3(0.16, -0.19, -0.42)
const ADS_DIST := 0.34
const DECALS_MAX := 40

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


func setup(main_node) -> void:
	main = main_node
	_rng.seed = 1203
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.8, 0.45)
	_flash.omni_range = 6.0
	_flash.light_energy = 0.0
	main.world.add_child(_flash)
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
	var origin := cam.global_position
	var basis := cam.global_transform.basis
	var record := {"gun": gun.def_id, "hits": [], "spread": spread, "ads": is_ads()}
	var space: PhysicsDirectSpaceState3D = main.player.get_world_3d().direct_space_state
	for k in pellets:
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * deg_to_rad(spread)
		var dir := (basis * Vector3(cos(a) * sin(r), sin(a) * sin(r), -cos(r))).normalized()
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * rng_max)
		q.exclude = [main.player.get_rid()]
		var h: Dictionary = space.intersect_ray(q)
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
	if str(g.get("action", "semi")) == "semi":
		if _feed_take(gun):
			gun.props["chamber"] = true
			if jammed:
				gun.props["jammed"] = true
	else:
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
	var kick := float(g.get("recoil", 2.5)) * (1.0 - skill * 0.06) * (1.6 if one_handed else 1.0)
	kick *= lerpf(1.0, 0.8, _blend)
	var yaw := _rng.randf_range(-0.35, 0.35) * kick
	main.player.add_recoil(deg_to_rad(kick), deg_to_rad(yaw))
	_recover = Vector2(deg_to_rad(kick), deg_to_rad(yaw)) * 0.55
	_kick = 1.0
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
			main.inventory.give(old)
			main.sound.play("mag_out", _muzzle(), -4.0)
		"mag_in":
			var best = _best_mag(gun)
			if best != null:
				main.inventory.remove_item(best)
				gun.props["mag"] = best.to_dict()
				main.sound.play("mag_in", _muzzle(), -2.0)
		"rack", "pump", "clear":
			if name == "clear":
				gun.props["jammed"] = false
				gun.props["chamber"] = false  # zacięty nabój wylatuje
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
	_kick = move_toward(_kick, 0.0, delta * 7.0)
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash.light_energy = 0.0
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


## Poza rąk z bronią (w układzie kamery): z biodra albo przy oku, odrzut, przeładowanie.
func update_pose() -> void:
	var gun = current()
	if gun == null:
		return
	var g := gun_def(gun)
	var player = main.player
	var cam: Transform3D = player.camera.global_transform
	var sight := float(g.get("sight_y", 0.07))
	var ads_pos := Vector3(0.0, -sight, -float(g.get("ads_dist", ADS_DIST)))
	var k := _blend * _blend * (3.0 - 2.0 * _blend)
	var p := HIP_POS.lerp(ads_pos, k)
	var dir := Vector3(0, 0, -1)
	p.z += _kick * 0.05
	dir = (dir + Vector3(0, _kick * 0.25, 0)).normalized()
	var sup: Array = g.get("support", [0.0, -0.03, 0.0])
	var left_off := Vector3(float(sup[0]), float(sup[1]), float(sup[2]))
	var left_dir := dir
	match state:
		"reload":
			# broń przechylona do środka, lewa dłoń przy gnieździe magazynka
			p = HIP_POS + Vector3(-0.08, 0.04, 0.06)
			dir = Vector3(-0.35, 0.35, -0.85).normalized()
			var u := _t / maxf(0.01, float(_steps[0][0])) if not _steps.is_empty() else 1.0
			left_off = Vector3(0.0, -0.1 - 0.12 * sin(u * PI), 0.03)
		"rack", "pump":
			var u := _t / maxf(0.01, float(_steps[0][0])) if not _steps.is_empty() else 1.0
			if str(g.get("action", "semi")) == "pump":
				left_off.z += 0.1 * sin(u * PI)  # pompka do siebie i z powrotem
			else:
				dir = Vector3(-0.2, 0.2, -0.95).normalized()
				left_off = Vector3(0.0, 0.05, 0.12 - 0.12 * sin(u * PI))
		"load":
			p = HIP_POS + Vector3(-0.05, 0.03, 0.04)
			dir = Vector3(-0.3, 0.1, -0.95).normalized()
			left_off = Vector3(0.0, -0.08, -0.15)
	var hb: Basis = cam.basis * main.combat._hand_basis(dir, false)
	player.work_targets = {"r": cam * p, "l": null}
	player.work_rots = {"r": hb.get_rotation_quaternion(), "l": null}
	if main.inventory.hand("l") == null or main.inventory.hands_two():
		# druga dłoń podtrzymuje: chwyt pistoletu albo łoże / pompka strzelby
		var lp: Vector3 = p + main.combat._hand_basis(dir, false) * left_off
		player.work_targets["l"] = cam * lp
		player.work_rots["l"] = (cam.basis * main.combat._hand_basis(left_dir if state == "idle" else dir, false)).get_rotation_quaternion()
	player.work_roll = 0.0
