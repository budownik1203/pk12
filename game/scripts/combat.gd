extends Node
## Tryb walki (kliknięcie kółkiem myszy). Postać przekłada chwyt (0,3 s) i trzyma
## to, co ma w ręce, bojowo; przyciski myszy znaczą wtedy:
##   lewy: cios,
##   prawy przytrzymany: garda (blok, zjada wytrzymałość),
##   lewy przy trzymanym prawym: odepchnięcie.
## Bez niczego w rękach walczy się pięściami. Profil ciosu (obrażenia, czasy,
## zasięg, siła pchnięcia, garda) pochodzi z danych: items.json, pole "combat",
## a dla pięści "fists". Chwyt oburącz daje mocniejszy, wolniejszy cios i lepszą
## gardę. Z bronią palną w prawej ręce przyciski obsługuje guns.gd (lewy strzał,
## prawy przyrządy celownicze, R przeładowanie).

const ItemDB := preload("res://scripts/inventory/item_db.gd")

const SWITCH_TIME := 0.3
const HIT_AT := 0.2                 # ułamek powrotu, w którym ostrze / obuch trafia
const SHOVE_TIME := 0.35
const SHOVE_COOLDOWN := 0.8
const SHOVE_STAMINA := 15.0
const SHOVE_FORCE := 140.0
const BLOCK_DRAIN := 3.0            # wytrzymałości na sekundę trzymania gardy
const TWO_HAND_DAMAGE := 1.35
const TWO_HAND_TIME := 1.15
const TWO_HAND_BLOCK := 1.3

## pozy w układzie kamery: położenie dłoni i kierunek narzędzia
const POSE := {
	"ready": [Vector3(0.17, -0.2, -0.4), Vector3(0.0, 0.75, -0.65)],
	"windup": [Vector3(0.26, -0.06, -0.34), Vector3(0.3, 0.75, 0.55)],
	"strike": [Vector3(-0.02, -0.26, -0.56), Vector3(-0.35, -0.2, -0.9)],
	"block": [Vector3(0.02, -0.1, -0.42), Vector3(-1.0, 0.12, 0.0)],
	"shove": [Vector3(0.06, -0.14, -0.62), Vector3(0.0, 0.8, -0.3)],
}

var main
var active := false
var blocking := false
var state := "idle"                 # idle, windup, recover, shove
var hits: Array = []                # ostatnie trafienia (testy, ekran deweloperski)

var _t := 0.0
var _switch := 0.0
var _hit_done := false
var _shove_cool := 0.0
var _prof := {}
var _blend := 0.0                   # 0 poza walką, 1 w pełnej postawie


func setup(main_node) -> void:
	main = main_node


func toggle() -> void:
	active = not active
	blocking = false
	state = "idle"
	_switch = SWITCH_TIME
	if active:
		main.work.end()
		if main.interaction.grab_mode:
			main.interaction.toggle_grab_mode()
		main.interaction.release()
	var gun_on: bool = active and main.guns != null and main.guns.current() != null
	main.hud.show_message(tr("MSG_COMBAT_GUN_ON" if gun_on else ("MSG_COMBAT_ON" if active else "MSG_COMBAT_OFF")))
	main.hud.set_mode("" if active else tr("MODE_TOOLS"))
	main.sound.play("pickup", main.player.camera.global_position, -10.0, 0.8)


## Ustawia tryb walki bez komunikatu (domyślny tryb gry; kółko pod F przełącza).
func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	blocking = false
	state = "idle"
	_switch = SWITCH_TIME
	if active:
		main.work.end()
		main.interaction.release()


func is_ready() -> bool:
	return active and _switch <= 0.0


## Profil walki tego, co jest w prawej ręce (albo pięści).
func profile() -> Dictionary:
	ItemDB.ensure_loaded()
	var it = main.inventory.hand("r")
	var p: Dictionary
	if it == null:
		p = ItemDB.fists.duplicate()
		p["fists"] = true
	else:
		p = it.get_def().get("combat", {}).duplicate()
		if p.is_empty():
			# przedmiot bez profilu: słaby cios czymkolwiek, im cięższy, tym wolniejszy
			var m: float = it.total_mass()
			p = {"damage": 4.0 + m * 3.0, "windup": 0.2 + m * 0.05, "recover": 0.3 + m * 0.05,
					"reach": 0.8, "block": 0.1, "stamina": 5.0 + m * 2.0, "force": 20.0 + m * 10.0}
		p["grip"] = str(it.get_def().get("grip", ""))
		if main.inventory.hands_two():
			p["two"] = true
			p["damage"] = float(p["damage"]) * TWO_HAND_DAMAGE
			p["windup"] = float(p["windup"]) * TWO_HAND_TIME
			p["recover"] = float(p["recover"]) * TWO_HAND_TIME
			p["block"] = minf(0.95, float(p["block"]) * TWO_HAND_BLOCK)
			p["force"] = float(p["force"]) * 1.3
		p["bulky"] = it.is_bulky()
	# umiejętność broni i siła: mocniej i taniej
	var skill := "bron_ostra" if str(p.get("type", "tepa")) == "ostra" else "bron_tepa"
	var lvl: int = main.character.level(skill)
	p["skill"] = skill
	p["damage"] = float(p["damage"]) * (1.0 + lvl * 0.05) * (0.8 + main.character.level("sila") * 0.04)
	p["stamina"] = float(p["stamina"]) * (1.0 - lvl * 0.04)
	return p


func press(button: int) -> void:
	if not is_ready():
		return
	if main.guns != null and main.guns.current() != null and not main.inventory.hand("r").is_bulky():
		main.guns.press(button)
		return
	if button == MOUSE_BUTTON_RIGHT:
		blocking = true
	elif button == MOUSE_BUTTON_LEFT:
		if blocking:
			shove()
		else:
			attack()


func release(button: int) -> void:
	if main.guns != null:
		main.guns.release(button)
	if button == MOUSE_BUTTON_RIGHT:
		blocking = false


func attack() -> bool:
	if state != "idle" or not is_ready():
		return false
	_prof = profile()
	if bool(_prof.get("bulky", false)):
		main.hud.show_message(tr("MSG_CANT_FIGHT_BULKY"))
		return false
	var cost := float(_prof.get("stamina", 5.0))
	if main.player.stamina < cost * 0.4:
		main.hud.show_message(tr("MSG_TOO_TIRED"))
		return false
	main.player._spend(cost)
	state = "windup"
	_t = 0.0
	_hit_done = false
	return true


func shove() -> bool:
	if state != "idle" or _shove_cool > 0.0 or not is_ready():
		return false
	if main.player.stamina < SHOVE_STAMINA * 0.4:
		main.hud.show_message(tr("MSG_TOO_TIRED"))
		return false
	main.player._spend(SHOVE_STAMINA)
	state = "shove"
	_t = 0.0
	_shove_cool = SHOVE_COOLDOWN
	_shove_hit()
	return true


func _physics_process(delta: float) -> void:
	if main == null or main.player == null:
		return
	_switch = maxf(0.0, _switch - delta)
	_shove_cool = maxf(0.0, _shove_cool - delta)
	_blend = move_toward(_blend, 1.0 if active else 0.0, delta / SWITCH_TIME)
	if blocking and is_ready():
		main.player._spend(BLOCK_DRAIN * delta)
		if main.player.stamina <= 0.5:
			blocking = false  # bez sił garda opada
	match state:
		"windup":
			_t += delta
			if _t >= float(_prof.get("windup", 0.2)):
				state = "recover"
				_t = 0.0
		"recover":
			_t += delta
			var rec := float(_prof.get("recover", 0.3))
			if not _hit_done and _t >= rec * HIT_AT:
				_hit_done = true
				_hit()
			if _t >= rec:
				state = "idle"
		"shove":
			_t += delta
			if _t >= SHOVE_TIME:
				state = "idle"
	if _blend > 0.0:
		_update_pose()


# --- trafienia -----------------------------------------------------------------

func _hit() -> void:
	var cam: Camera3D = main.player.camera
	var o := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var side := cam.global_transform.basis.x
	var reach := float(_prof.get("reach", 0.8))
	var space: PhysicsDirectSpaceState3D = main.player.get_world_3d().direct_space_state
	var hit := {}
	# trzy promienie: na wprost i lekko na boki (łuk zamachu)
	for off in [0.0, -0.12, 0.12]:
		var q := PhysicsRayQueryParameters3D.create(o, o + (fwd + side * off).normalized() * reach)
		q.exclude = [main.player.get_rid()]
		var h: Dictionary = space.intersect_ray(q)
		if not h.is_empty():
			hit = h
			break
	main.sound.play("whoosh", o + fwd * 0.5, -12.0, 1.5)
	if hit.is_empty():
		return
	var col: Object = hit["collider"]
	var pos: Vector3 = hit["position"]
	var dmg: float = float(_prof.get("damage", 5.0)) * main.health.arm_factor("r")
	if bool(_prof.get("fists", false)) and not col is RigidBody3D and main.health.rng.randf() < 0.2:
		main.health.wound("dlon_p", "stluczenie", 0.35)  # pięść w ścianę boli
	var record := {"target": col, "damage": dmg, "pos": pos}
	hits.append(record)
	if hits.size() > 20:
		hits.pop_front()
	main.character.add_xp(str(_prof.get("skill", "bron_tepa")), 3.0)
	main.character.add_xp("sila", 0.5)
	if col.has_method("take_hit"):
		# zombie: głowa liczy się podwójnie i więcej, mocny cios zatacza
		var killed: bool = col.take_hit(dmg, pos, fwd, bool(_prof.get("two", false)) or dmg > 25.0)
		record["killed"] = killed
		main.noise.emit_noise(pos, 40.0, "NOISE_HIT")
		return
	if col is RigidBody3D and not (col as RigidBody3D).freeze:
		var body := col as RigidBody3D
		body.sleeping = false
		body.apply_impulse(fwd * float(_prof.get("force", 30.0)), pos - body.global_position)
	if col.has_meta("hp"):
		col.set_meta("hp", float(col.get_meta("hp")) - dmg)
		main.hud.show_message(tr("MSG_HIT") % dmg)
	var snd := "impact_wood"
	if col.has_meta("hit_sound"):
		snd = str(col.get_meta("hit_sound"))
	elif col.has_meta("item") and col.get_meta("item").material() == "metal":
		snd = "impact_metal"
	main.sound.play(snd, pos, -2.0, 0.9)
	main.noise.emit_noise(pos, 45.0, "NOISE_HIT")


func _shove_hit() -> void:
	var cam: Camera3D = main.player.camera
	var fwd := -cam.global_transform.basis.z
	var shape := SphereShape3D.new()
	shape.radius = 0.45
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), cam.global_position + fwd * 0.75)
	q.exclude = [main.player.get_rid()]
	var flat := Vector3(fwd.x, 0.15, fwd.z).normalized()
	for r in main.player.get_world_3d().direct_space_state.intersect_shape(q, 8):
		var body = r["collider"]
		if body is RigidBody3D and not body.freeze:
			body.sleeping = false
			body.apply_central_impulse(flat * minf(SHOVE_FORCE, body.mass * 6.0))
			hits.append({"target": body, "damage": 0.0, "shove": true})
		elif body.has_method("shove"):
			body.shove(flat)
			hits.append({"target": body, "damage": 0.0, "shove": true})
	main.sound.play("whoosh", cam.global_position + fwd * 0.4, -8.0, 0.8)


# --- poza ------------------------------------------------------------------------

func _pose_pair(a: String, b: String, k: float) -> Array:
	var pa: Array = POSE[a]
	var pb: Array = POSE[b]
	k = clampf(k, 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	return [(pa[0] as Vector3).lerp(pb[0], k), (pa[1] as Vector3).lerp(pb[1], k).normalized()]


func _current_pose() -> Array:
	match state:
		"windup":
			return _pose_pair("ready", "windup", _t / maxf(0.01, float(_prof.get("windup", 0.2))))
		"recover":
			var u := _t / maxf(0.01, float(_prof.get("recover", 0.3)))
			if u < HIT_AT:
				return _pose_pair("windup", "strike", u / HIT_AT)
			return _pose_pair("strike", "ready", (u - HIT_AT) / (1.0 - HIT_AT))
		"shove":
			var s := _t / SHOVE_TIME
			return _pose_pair("ready", "shove", s * 2.0) if s < 0.5 else _pose_pair("shove", "ready", (s - 0.5) * 2.0)
	if blocking:
		return POSE["block"]
	return POSE["ready"]


## Ułożenie dłoni z kierunku narzędzia (w układzie kamery): zwykły chwyt kieruje
## narzędzie wzdłuż -Z dłoni, chwyt "up" (młotek) wzdłuż +Y dłoni.
static func _hand_basis(dir: Vector3, grip_up: bool) -> Basis:
	if grip_up:
		var y := dir
		var z := (Vector3.BACK - y * y.dot(Vector3.BACK))
		if z.length() < 0.05:
			z = Vector3.UP
		z = z.normalized()
		return Basis(y.cross(z), y, z)
	var zz := -dir
	var yy := (Vector3.UP - zz * zz.dot(Vector3.UP))
	if yy.length() < 0.05:
		yy = Vector3.BACK
	yy = yy.normalized()
	return Basis(yy.cross(zz), yy, zz)


func _update_pose() -> void:
	var player = main.player
	if not active:
		return  # po wyjściu z walki pozę przejmuje praca narzędziem
	if main.guns != null and main.guns.current() != null and state == "idle":
		main.guns.update_pose()
		return
	var cam: Transform3D = player.camera.global_transform
	var prof := profile() if state == "idle" else _prof
	var pose := _current_pose()
	var p: Vector3 = pose[0]
	var d: Vector3 = pose[1]
	var targets := {"l": null, "r": null}
	var rots := {"l": null, "r": null}
	var fists: bool = bool(prof.get("fists", false))
	var hb := cam.basis * _hand_basis(d, str(prof.get("grip", "")) == "up")
	targets["r"] = cam * p
	rots["r"] = hb.get_rotation_quaternion()
	if bool(prof.get("two", false)):
		# druga dłoń wyżej na trzonku
		targets["l"] = cam * (p + d * 0.22)
		rots["l"] = rots["r"]
	elif fists or main.inventory.hand("l") == null:
		# wolna lewa: pięść w gardzie przy twarzy
		var guard := Vector3(-0.13, -0.15, -0.44) if blocking or fists else Vector3(-0.17, -0.24, -0.38)
		if state == "shove":
			guard = p + Vector3(-0.14, 0.0, 0.0)
		targets["l"] = cam * guard
		rots["l"] = (cam.basis * _hand_basis(Vector3(0, 0.6, -0.8).normalized(), false)).get_rotation_quaternion()
	if fists:
		rots["r"] = (cam.basis * _hand_basis(Vector3(0, 0.6, -0.8).normalized(), false)).get_rotation_quaternion()
	player.work_targets = targets
	player.work_rots = rots
	player.work_roll = 0.0
