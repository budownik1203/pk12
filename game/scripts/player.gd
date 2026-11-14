extends CharacterBody3D
## Gracz: ciężki ruch z bezwładnością, sprint, kucanie, wychylanie, skok,
## wspinanie na przeszkody, wytrzymałość, pchanie brył. Widoczne ciało
## i dłonie z własną fizyką prowadzi body.gd (build 2b).

const BodyScript := preload("res://scripts/body.gd")

const RADIUS := 0.3
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const EYE_OFFSET := 0.15           # oczy są tyle poniżej czubka głowy

const WALK_SPEED := 2.4
const SPRINT_SPEED := 4.6
const CROUCH_SPEED := 1.2
const ACCEL := 6.5                 # m/s², rozpędzanie
const DECEL := 8.5                 # m/s², hamowanie
const AIR_CONTROL := 0.2
const JUMP_SPEED := 3.4
const MOUSE_SENS := 0.0022

const LEAN_OFFSET := 0.32          # metry w bok
const LEAN_ROLL := 0.16            # radiany
const LEAN_SPEED := 4.0

const STAMINA_MAX := 100.0
const SPRINT_DRAIN := 9.0          # na sekundę
const STAMINA_REGEN := 7.0
const STAMINA_PAUSE := 1.0         # sekundy bez wysiłku, zanim wraca
const JUMP_COST := 8.0
const MANTLE_COST := 12.0
const EXHAUSTED_UNTIL := 25.0

const MANTLE_MIN := 0.35           # niższe progi po prostu się przekracza
const MANTLE_MAX := 1.35           # mniej więcej wysokość klatki piersiowej
const MANTLE_REACH := 0.55

const PUSH_FORCE := 260.0
const PUSH_MAX_SPEED := 2.2
const CARRY_LIGHT := 5.0           # kg: do tej masy trzymany przedmiot nie spowalnia
const CARRY_HEAVY := 80.0          # kg: przy tej masie postać idzie najwolniej
const CARRY_MIN_FACTOR := 0.3
const CARRY_SPRINT_MAX := 20.0     # kg: z cięższym przedmiotem w ręku nie ma sprintu

var head: Node3D
var camera: Camera3D
var lamp: SpotLight3D
var pitch := 0.0
var height := STAND_HEIGHT
var crouching := false
var lean := 0.0
var stamina := STAMINA_MAX
var exhausted := false
var held_body: RigidBody3D = null  # ustawia system chwytu; tej bryły nie pchamy ciałem
var held_local_point := Vector3.ZERO  # punkt chwytu w układzie trzymanej bryły
var load_factor := 1.0             # mnożnik prędkości od odczuwanej masy ekwipunku
var load_stamina := 1.0            # mnożnik zużycia wytrzymałości od masy
var strength := 5                  # siła 1–10 (na razie stała; cechy postaci w buildzie 9)
var hand_items := {"l": null, "r": null, "two": false}    # przedmioty w rękach (z ekwipunku)
var work_targets := {"l": null, "r": null}  # punkty pracy, do których idą dłonie (Vector3)
var work_rots := {"l": null, "r": null}     # zadane ułożenie dłoni przy pracy (Quaternion)
var work_roll := 0.0               # obrót dłoni przy wkręcaniu
var work_side := ""                # ręka, która kręci
var body: Node3D

var _shape: CapsuleShape3D
var _col: CollisionShape3D
var _stamina_pause := 0.0
var _teleport_frames := 0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _mantle_time := -1.0
var _mantle_duration := 0.0
var _mantle_from := Vector3.ZERO
var _mantle_up := Vector3.ZERO
var _mantle_to := Vector3.ZERO


func _init() -> void:
	_shape = CapsuleShape3D.new()
	_shape.radius = RADIUS
	_shape.height = STAND_HEIGHT
	_col = CollisionShape3D.new()
	_col.shape = _shape
	_col.position.y = STAND_HEIGHT / 2.0
	add_child(_col)

	head = Node3D.new()
	head.position.y = STAND_HEIGHT - EYE_OFFSET
	add_child(head)

	camera = Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = 80.0
	camera.current = true
	head.add_child(camera)

	lamp = SpotLight3D.new()
	lamp.spot_range = 14.0
	lamp.spot_angle = 26.0
	lamp.light_energy = 3.0
	lamp.light_color = Color(1.0, 0.95, 0.82)
	lamp.shadow_enabled = true
	lamp.visible = false
	lamp.top_level = true  # położenie ustawia ciało: latarka jest w lewej dłoni
	camera.add_child(lamp)

	body = BodyScript.new()
	body.name = "Cialo"
	add_child(body)
	body.setup(self, camera)


func look(relative: Vector2) -> void:
	rotate_y(-relative.x * MOUSE_SENS)
	pitch = clampf(pitch - relative.y * MOUSE_SENS, -1.45, 1.45)
	head.rotation.x = pitch


func set_view(yaw: float, new_pitch: float) -> void:
	rotation.y = yaw
	pitch = new_pitch
	head.rotation.x = pitch


func toggle_flashlight() -> void:
	lamp.visible = not lamp.visible


func is_mantling() -> bool:
	return _mantle_time >= 0.0


func set_crouched(value: bool) -> void:
	crouching = value
	height = CROUCH_HEIGHT if value else STAND_HEIGHT
	_apply_height()


## Przeniesienie postaci bez wypychania brył (wczytanie zapisu, testy).
## Silnik fizyki widzi skok pozycji jako ruch z ogromną prędkością, więc na
## dwie klatki wyłączamy zderzenia postaci.
func teleport(pos: Vector3) -> void:
	_col.disabled = true
	_teleport_frames = 2
	_mantle_time = -1.0
	global_position = pos
	velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if _teleport_frames > 0:
		_teleport_frames -= 1
		if _teleport_frames == 0:
			_col.disabled = false
		return
	if is_mantling():
		_mantle_step(delta)
		return

	_update_crouch(delta)
	_update_lean(delta)

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := global_transform.basis * Vector3(input.x, 0.0, input.y)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO

	var held_mass := 0.0
	if held_body != null and is_instance_valid(held_body):
		held_mass = held_body.mass
	var sprinting := Input.is_action_pressed("sprint") and not crouching and not exhausted \
			and input.y < -0.1 and is_on_floor() and held_mass <= CARRY_SPRINT_MAX
	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif sprinting:
		speed = SPRINT_SPEED
	speed *= carry_factor(held_mass) * load_factor
	_update_stamina(delta, sprinting and dir != Vector3.ZERO)

	var target := dir * speed
	var rate := ACCEL if dir != Vector3.ZERO else DECEL
	if not is_on_floor():
		rate *= AIR_CONTROL
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if is_on_floor():
		if Input.is_action_just_pressed("jump") and not crouching:
			if not _try_mantle() and stamina >= JUMP_COST:
				velocity.y = JUMP_SPEED
				_spend(JUMP_COST)
	else:
		velocity.y -= _gravity * delta

	move_and_slide()
	_push_bodies(delta)


# --- kucanie i wychylanie -----------------------------------------------------

func _update_crouch(delta: float) -> void:
	var want := Input.is_action_pressed("crouch")
	if not want and crouching and not _can_stand():
		want = true  # nad głową jest przeszkoda
	crouching = want
	var target_h := CROUCH_HEIGHT if crouching else STAND_HEIGHT
	if not is_equal_approx(height, target_h):
		height = move_toward(height, target_h, 3.0 * delta)
		_apply_height()


func _apply_height() -> void:
	_shape.height = height
	_col.position.y = height / 2.0
	head.position.y = height - EYE_OFFSET


func _can_stand() -> bool:
	var from := global_position + Vector3(0, height - 0.05, 0)
	var to := global_position + Vector3(0, STAND_HEIGHT + 0.03, 0)
	return _ray(from, to).is_empty()


func _update_lean(delta: float) -> void:
	var want := Input.get_axis("lean_left", "lean_right")
	if want != 0.0:
		# nie wychylamy głowy w ścianę
		var side := global_transform.basis.x * signf(want)
		var hit := _ray(head.global_position, head.global_position + side * (LEAN_OFFSET + 0.2))
		if not hit.is_empty():
			var free: float = head.global_position.distance_to(hit["position"]) - 0.2
			want *= clampf(free / LEAN_OFFSET, 0.0, 1.0)
	lean = move_toward(lean, want, LEAN_SPEED * delta)
	camera.position.x = lean * LEAN_OFFSET
	camera.rotation.z = -lean * LEAN_ROLL


# --- wytrzymałość ---------------------------------------------------------------

func _update_stamina(delta: float, draining: bool) -> void:
	if draining:
		_spend(SPRINT_DRAIN * load_stamina * delta)
	elif _stamina_pause > 0.0:
		_stamina_pause -= delta
	else:
		stamina = minf(STAMINA_MAX, stamina + STAMINA_REGEN * delta)
	if stamina <= 0.5:
		exhausted = true
	elif exhausted and stamina >= EXHAUSTED_UNTIL:
		exhausted = false


func _spend(amount: float) -> void:
	stamina = maxf(0.0, stamina - amount)
	_stamina_pause = STAMINA_PAUSE


# --- wspinanie --------------------------------------------------------------------

func _try_mantle() -> bool:
	if stamina < MANTLE_COST:
		return false
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	# 1. szukamy powierzchni przed sobą (blat, skrzynia, parapet)
	var probe := global_position + forward * MANTLE_REACH + Vector3(0, MANTLE_MAX + 0.15, 0)
	var top := _ray(probe, probe + Vector3(0, -(MANTLE_MAX + 0.1), 0))
	if top.is_empty():
		return false
	var top_pos: Vector3 = top["position"]
	var normal: Vector3 = top["normal"]
	var ledge := top_pos.y - global_position.y
	if ledge < MANTLE_MIN or ledge > MANTLE_MAX or normal.y < 0.7:
		return false
	# 2. na górze musi być miejsce przynajmniej na kucającą postać
	var above := top_pos + Vector3(0, 0.05, 0)
	if not _ray(above, above + Vector3(0, CROUCH_HEIGHT, 0)).is_empty():
		return false
	# 3. droga nad krawędzią musi być wolna (nie wspinamy się przez ścianę)
	var lift := Vector3(0, top_pos.y - global_position.y + 0.3, 0)
	if not _ray(global_position + lift, Vector3(top_pos.x, global_position.y, top_pos.z) + lift).is_empty():
		return false
	_spend(MANTLE_COST)
	velocity = Vector3.ZERO
	_mantle_from = global_position
	_mantle_up = Vector3(global_position.x, top_pos.y + 0.03, global_position.z)
	_mantle_to = Vector3(top_pos.x, top_pos.y + 0.03, top_pos.z)
	_mantle_duration = 0.45 + ledge * 0.4
	_mantle_time = 0.0
	return true


func _mantle_step(delta: float) -> void:
	_mantle_time += delta
	var t := clampf(_mantle_time / _mantle_duration, 0.0, 1.0)
	# najpierw w górę (60% czasu), potem do przodu
	if t < 0.6:
		global_position = _mantle_from.lerp(_mantle_up, smoothstep(0.0, 1.0, t / 0.6))
	else:
		global_position = _mantle_up.lerp(_mantle_to, smoothstep(0.0, 1.0, (t - 0.6) / 0.4))
	if t >= 1.0:
		_mantle_time = -1.0
		velocity = Vector3.ZERO
		if not _can_stand():
			set_crouched(true)


# --- pomocnicze -------------------------------------------------------------------

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var exclude: Array[RID] = [get_rid()]
	if held_body != null and is_instance_valid(held_body):
		exclude.append(held_body.get_rid())
	q.exclude = exclude
	return get_world_3d().direct_space_state.intersect_ray(q)


func _push_bodies(delta: float) -> void:
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var body := hit.get_collider() as RigidBody3D
		if body == null or body == held_body:
			continue
		var push_dir := -hit.get_normal()
		push_dir.y = 0.0
		if push_dir.length() < 0.2:
			continue  # stoimy na bryle albo pod nią
		push_dir = push_dir.normalized()
		if body.linear_velocity.dot(push_dir) > PUSH_MAX_SPEED:
			continue
		body.apply_impulse(push_dir * PUSH_FORCE * delta, hit.get_position() - body.global_position)


## Mnożnik prędkości od masy trzymanego przedmiotu.
func carry_factor(mass: float) -> float:
	var t := clampf((mass - CARRY_LIGHT) / (CARRY_HEAVY - CARRY_LIGHT), 0.0, 1.0)
	return lerpf(1.0, CARRY_MIN_FACTOR, t)


func stands_on(body: Object) -> bool:
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		if hit.get_collider() == body and hit.get_normal().y > 0.6:
			return true
	return false
