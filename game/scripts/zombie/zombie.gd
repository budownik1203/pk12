extends CharacterBody3D
## Zombie. Zmysły: wzrok (stożek 120°, zasięg zależny od światła, linia wzroku)
## i słuch (zdarzenia hałasu, przez ściany słabiej). Stany:
##   wander      snuje się po swojej strefie,
##   investigate idzie do ostatniego hałasu albo miejsca, gdzie widział gracza,
##   chase       goni widzianego gracza,
##   attack      zamach; trafia, jeśli gracz dalej jest blisko i przed nim,
##   window      za oknem: wyrywa deski, a gdy okno wolne, przechodzi przez nie,
##   door        wali w zatrzaśnięte drzwi, aż wyłamie zatrzask,
##   stagger     zatacza się po mocnym ciosie,
##   down        leży po odepchnięciu albo przewróceniu, potem wstaje,
##   dead        zwłoki.
## Strefy: "out" (grunt za oknem) i "in" (pokój z komórką); łączy je tylko okno.

const BodyScript := preload("res://scripts/zombie/zombie_body.gd")

const SIGHT_ANGLE := 0.5            # cos(60°): połowa stożka 120°
const ATTACK_RANGE := 1.05
const ATTACK_HIT_RANGE := 1.35
const ATTACK_WINDUP := 0.55
const ATTACK_COOLDOWN := 1.3
const MEMORY := 5.0                 # sekundy pościgu po utracie z oczu
const GRAVITY := 9.8

var main
var manager
var zid := 0
var hp := 100.0
var speed_walk := 0.45
var speed_chase := 1.1
var state := "wander"
var target_pos := Vector3.ZERO
var zone := "out"
var body: Node3D
var nav: NavigationAgent3D

var _sense_t := 0.0
var _seen_t := 99.0
var _state_t := 0.0
var _attack_cool := 0.0
var _groan_t := 0.0
var _climb := -1.0                  # >= 0: trwa przechodzenie przez okno
var _climb_from := Vector3.ZERO
var _climb_to := Vector3.ZERO
var _stuck_t := 0.0
var _rng := RandomNumberGenerator.new()
var _fwd := Vector3.FORWARD
var _door = null                    # drzwi, w które wali (door_system albo simple_door)


func setup(main_node, mgr, id: int, pos: Vector3, speed_mult: float) -> void:
	main = main_node
	manager = mgr
	zid = id
	name = "Zombie%d" % id
	_rng.seed = 7919 * id + 13
	speed_walk *= speed_mult
	speed_chase *= speed_mult
	platform_floor_layers = 0
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
	floor_snap_length = 0.3
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 1.7
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, 0.85, 0)
	add_child(col)
	body = BodyScript.new()
	body.name = "Cialo"
	add_child(body)
	body.build(id)
	nav = NavigationAgent3D.new()
	nav.path_desired_distance = 0.4
	nav.target_desired_distance = 0.5
	nav.radius = 0.3
	nav.height = 1.7
	add_child(nav)
	position = pos
	zone = manager.zone_of(pos)
	_fwd = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
	_groan_t = _rng.randf_range(2.0, 8.0)
	_pick_wander()


func is_dead() -> bool:
	return state == "dead"


# --- zmysły ------------------------------------------------------------------------

func _sense() -> void:
	var pl = main.player
	if main.health.dead:
		return
	var eye := global_position + Vector3.UP * 1.6
	var to_p: Vector3 = pl.camera.global_position - eye
	var dist := to_p.length()
	var sight: float = manager.sight_range(self)
	if dist < sight and _fwd.dot(Vector3(to_p.x, 0, to_p.z).normalized()) > SIGHT_ANGLE or dist < 1.2:
		var q := PhysicsRayQueryParameters3D.create(eye, pl.camera.global_position)
		q.exclude = [get_rid(), pl.get_rid()]
		q.collision_mask = 1
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty() or (hit["collider"] is CharacterBody3D):
			_seen_t = 0.0
			target_pos = pl.global_position
			if state in ["wander", "investigate"]:
				_set_state("chase")
				main.sound.play("snarl", global_position + Vector3.UP * 1.5, -4.0, _rng.randf_range(0.85, 1.1))


## Hałas z noise.gd: idzie sprawdzić, jeśli usłyszał.
func hear(pos: Vector3, loudness: float) -> void:
	if state in ["dead", "down", "stagger", "attack", "chase"] and _seen_t < MEMORY:
		return
	var radius := loudness * 0.25
	if main.get("weather") != null:
		radius *= main.weather.hearing_factor()  # deszcz zagłusza
	if manager.zone_of(pos) != zone:
		radius *= 0.6  # przez ścianę słychać słabiej
	if global_position.distance_to(pos) <= radius and state in ["wander", "investigate", "chase"]:
		target_pos = pos
		if state == "wander":
			_set_state("investigate")


# --- ruch i stany --------------------------------------------------------------------

const StepUp := preload("res://scripts/step_up.gd")


func _set_state(s: String) -> void:
	state = s
	_state_t = 0.0


func _physics_process(delta: float) -> void:
	if main == null:
		return
	_state_t += delta
	_seen_t += delta
	_attack_cool = maxf(0.0, _attack_cool - delta)
	if not is_on_floor() and state != "dead" and _climb < 0.0:
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	if state != "dead":
		_sense_t -= delta
		if _sense_t <= 0.0:
			_sense_t = 0.25
			if _climb < 0.0:
				zone = manager.zone_of(global_position)  # strefa wg miejsca, gdzie naprawdę stoi
			_sense()
		_groan_t -= delta
		if _groan_t <= 0.0:
			_groan_t = _rng.randf_range(4.0, 11.0)
			main.sound.play("groan", global_position + Vector3.UP * 1.5, -8.0, _rng.randf_range(0.8, 1.15))
	var move := Vector3.ZERO
	var speed := 0.0
	match state:
		"wander":
			speed = speed_walk
			move = _steer_to(target_pos)
			if global_position.distance_to(target_pos) < 0.6 or _state_t > 12.0:
				_pick_wander()
		"investigate":
			speed = speed_walk * 1.4
			move = _route_to(target_pos)
			if global_position.distance_to(target_pos) < 0.8 or _state_t > 20.0:
				_set_state("wander")
				_pick_wander()
		"chase":
			speed = speed_chase
			if _seen_t < MEMORY:
				if _seen_t < 0.3:
					target_pos = main.player.global_position
				move = _route_to(target_pos)
				var d := global_position.distance_to(main.player.global_position)
				if d < ATTACK_RANGE and _attack_cool <= 0.0 and manager.zone_of(main.player.global_position) == zone:
					_set_state("attack")
			else:
				_set_state("investigate")
		"attack":
			_face(main.player.global_position, delta * 6.0)
			body.lunge = clampf(_state_t / ATTACK_WINDUP, 0.0, 1.0)
			if _state_t >= ATTACK_WINDUP:
				_strike()
				body.lunge = 0.0
				_attack_cool = ATTACK_COOLDOWN
				_set_state("chase")
		"window":
			_window_logic(delta)
		"door":
			if _door != null and _door.latched:
				_face(_door.door.global_position, delta * 4.0)
				body.lunge = absf(sin(_state_t * 3.0))
				_door.zombie_bang(delta, global_position)
			else:
				body.lunge = 0.0
				_set_state("chase" if _seen_t < MEMORY else "investigate")
		"stagger":
			body.stagger = maxf(0.0, 1.0 - _state_t / 0.7)
			if _state_t > 0.7:
				body.stagger = 0.0
				_set_state("chase" if _seen_t < MEMORY else "investigate")
		"down":
			body.down = 1.0
			if _state_t > 2.6:
				body.down = 0.0
				_set_state("chase" if _seen_t < MEMORY else "wander")
		"dead":
			body.down = 1.0
	if _climb >= 0.0:
		_climb_step(delta)
		speed = 0.0
		move = Vector3.ZERO
	if move.length() > 0.01 and state in ["wander", "investigate", "chase"]:
		_face(global_position + move, delta * 5.0)
		velocity.x = move.x * speed
		velocity.z = move.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, delta * 6.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 6.0)
	if state != "dead":
		if is_on_floor() and _climb < 0.0:
			StepUp.try_step(self, delta, 0.28)  # krawężnik chodnika, deski
		move_and_slide()
		_push_props()
		_check_stuck(delta, speed)
	body.gait = move_toward(body.gait, clampf(Vector2(velocity.x, velocity.z).length() / 1.2, 0.0, 1.0), delta * 3.0)
	body.reach = move_toward(body.reach, 1.0 if state in ["chase", "attack", "window"] else 0.0, delta * 2.5)
	body.pose(global_position, _fwd, delta, Vector2(velocity.x, velocity.z).length())


func _face(point: Vector3, rate: float) -> void:
	var d := point - global_position
	d.y = 0.0
	if d.length() < 0.01:
		return
	_fwd = _fwd.slerp(d.normalized(), clampf(rate, 0.0, 1.0)).normalized()


func _steer_to(p: Vector3) -> Vector3:
	var d := p - global_position
	d.y = 0.0
	return d.normalized() if d.length() > 0.05 else Vector3.ZERO


## Droga do celu z uwzględnieniem stref: do celu w drugiej strefie idzie przez okno.
func _route_to(p: Vector3) -> Vector3:
	var goal_zone: String = manager.zone_of(p)
	if goal_zone != zone:
		var w: Vector3 = manager.window_point(zone)
		if global_position.distance_to(w) < 0.55:
			_set_state("window")
			return Vector3.ZERO
		p = w
	# zatrzaśnięte drzwi tuż przed nim: walenie
	var blocking = _door_ahead()
	if blocking != null:
		_door = blocking
		_set_state("door")
		return Vector3.ZERO
	nav.target_position = p
	if nav.is_navigation_finished():
		return _steer_to(p)
	var next := nav.get_next_path_position()
	var dir := _steer_to(next)
	return dir if dir != Vector3.ZERO else _steer_to(p)


## Zatrzaśnięte drzwi na wprost w zasięgu ręki (promień na wysokości klamki).
func _door_ahead():
	var from := global_position + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(from, from + _fwd * 0.75)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	var c: Object = hit["collider"]
	if c.has_meta("door_sys") and c.get_meta("door_sys").latched:
		return c.get_meta("door_sys")
	return null


func _crosses_door(p: Vector3) -> bool:
	var wall_x: float = manager.door_wall_x
	return (global_position.x < wall_x) != (p.x < wall_x)


func _pick_wander() -> void:
	target_pos = manager.random_point(zone, _rng)


## Ciało zombie przepycha luźne przedmioty, na które wpada.
func _push_props() -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var other := c.get_collider()
		if other is RigidBody3D and not (other as RigidBody3D).freeze:
			(other as RigidBody3D).apply_central_impulse(-c.get_normal() * 2.0)


func _check_stuck(delta: float, speed: float) -> void:
	if speed > 0.1 and Vector2(velocity.x, velocity.z).length() < 0.1 and state in ["wander", "investigate"]:
		_stuck_t += delta
		if _stuck_t > 1.5:
			_stuck_t = 0.0
			_pick_wander()
	else:
		_stuck_t = 0.0


# --- atak --------------------------------------------------------------------------

func _strike() -> void:
	var pl = main.player
	var to_p: Vector3 = pl.global_position - global_position
	to_p.y = 0.0
	main.sound.play("snarl", global_position + Vector3.UP * 1.5, -2.0, 1.2)
	if to_p.length() > ATTACK_HIT_RANGE or _fwd.dot(to_p.normalized()) < 0.3 or main.health.dead:
		main.sound.play("whoosh", global_position + Vector3.UP * 1.2, -10.0, 0.9)
		return
	# garda: gracz w trybie walki z podniesioną gardą, przodem do zombie
	var cb = main.combat
	var facing: float = (-pl.camera.global_transform.basis.z).dot(-to_p.normalized())
	if cb.active and cb.blocking and facing > 0.4:
		var prof: Dictionary = cb.profile()
		pl._spend(12.0)
		if _rng.randf() < float(prof.get("block", 0.1)) + 0.25:
			main.sound.play("impact_wood", pl.camera.global_position - to_p.normalized() * 0.4, -3.0, 0.8)
			main.hud.show_message(tr("MSG_BLOCKED"))
			_set_state("stagger")
			return
	manager.wound_player(self)


## Cios gracza. Zwraca, czy zabił.
func take_hit(damage: float, at: Vector3, dir: Vector3, heavy: bool) -> bool:
	if state == "dead":
		return false
	var head: bool = at.y > global_position.y + 1.45 and state != "down"
	if state == "down":
		damage *= 1.6  # leżący: łatwy cel, cios w głowę z góry
	if head:
		damage *= 2.5
	hp -= damage
	_seen_t = 0.0
	target_pos = main.player.global_position
	main.sound.play("hit_flesh", at, 0.0, 0.9 if head else 1.1)
	if hp <= 0.0:
		die(dir)
		return true
	if state == "down":
		return false
	if heavy or damage > 25.0 or _rng.randf() < damage / 40.0:
		body.lunge = 0.0
		_set_state("stagger")
		velocity += Vector3(dir.x, 0, dir.z).normalized() * 1.5
	return false


## Odepchnięcie: zwykle przewraca.
func shove(dir: Vector3) -> void:
	if state == "dead" or state == "down":
		return
	velocity += Vector3(dir.x, 0, dir.z).normalized() * 3.0
	body.lunge = 0.0
	if _rng.randf() < 0.65:
		_set_state("down")
		main.sound.play("bodyfall", global_position + Vector3.UP * 0.3, -4.0)
	else:
		_set_state("stagger")


func die(dir: Vector3) -> void:
	_set_state("dead")
	body.down = 1.0
	body.lunge = 0.0
	velocity = Vector3.ZERO
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length() > 0.1:
		_fwd = flat.normalized()
	# zwłoki: nie blokują przejścia gracza, ale leżą w świecie
	collision_layer = 0
	collision_mask = 1
	main.sound.play("bodyfall", global_position + Vector3.UP * 0.3, 0.0)
	body.pose(global_position, _fwd, 0.0, 0.0)
	manager.on_zombie_died(self)


# --- okno --------------------------------------------------------------------------

func _window_logic(delta: float) -> void:
	var wb = main.window_boards
	var w: Vector3 = manager.window_point(zone)
	_face(manager.window_point("in" if zone == "out" else "out"), delta * 5.0)
	global_position = global_position.lerp(Vector3(w.x, global_position.y, w.z), clampf(delta * 3.0, 0.0, 1.0))
	if wb.passable():
		_start_climb()
	elif zone == "out":
		body.lunge = absf(sin(_state_t * 2.5)) * 0.8
		wb.zombie_pull(delta)
	else:
		_set_state("investigate")  # od środka deski nie przeszkadzają w pościgu na zewnątrz


func _start_climb() -> void:
	if _climb >= 0.0:
		return
	_climb = 0.0
	_climb_from = global_position
	var other := "in" if zone == "out" else "out"
	_climb_to = manager.window_point(other)
	collision_mask = 0  # na czas przełażenia przez parapet
	main.sound.play("bodyfall", global_position + Vector3.UP, -10.0, 1.3)


func _climb_step(delta: float) -> void:
	_climb += delta / 1.6
	var t := clampf(_climb, 0.0, 1.0)
	var sill: float = manager.window_sill
	var p := _climb_from.lerp(_climb_to, t)
	p.y = _climb_from.y + sin(t * PI) * (sill + 0.15)
	global_position = p
	body.reach = 1.0
	if _climb >= 1.0:
		_climb = -1.0
		collision_mask = 1
		zone = manager.zone_of(global_position)
		_set_state("chase" if _seen_t < MEMORY else "investigate")


func to_dict() -> Dictionary:
	return {"pos": [global_position.x, global_position.y, global_position.z], "hp": hp,
			"dead": state == "dead", "fwd": [_fwd.x, _fwd.z]}
