extends Node
## Interakcja ze światem środkiem ekranu:
##   T  chwyt: łapiesz bryłę w punkcie, na który patrzysz, i ciągniesz ją
##      ruchem postaci i wzroku (drugi raz T puszcza),
##   F  użycie: obiekty z własną funkcją (włącznik światła),
##   kółko myszy przy chwycie: bliżej / dalej, lewy przycisk: rzut.
## Chwyt działa siłą przyłożoną w punkcie chwytu, więc ciężkie rzeczy da się
## tylko wlec po podłodze, a drzwi na zawiasie otwierają się po łuku.

const PlayerScript := preload("res://scripts/player.gd")
const HudScript := preload("res://scripts/hud.gd")

const REACH := 2.0          # zasięg ręki w metrach
const HOLD_MIN := 0.6
const HOLD_MAX := 2.0
const PULL_MAX := 420.0     # niutony w poziomie: tyle postać uciągnie
const LIFT_MAX := 260.0     # niutony w pionie: unosi około 26 kg
const BREAK_DIST := 2.6     # punkt chwytu dalej od oczu niż tyle: chwyt się zrywa
const STIFF := 70.0
const DAMP := 14.0
const MASS_CAP := 30.0
const HELD_ANGULAR_DAMP := 4.0
const THROW_SPEED := 6.0    # m/s dla lekkich rzeczy
const THROW_IMPULSE_MAX := 45.0

var main: Node
var player: PlayerScript
var hud: HudScript
var held: RigidBody3D = null
var focus: Object = null
var focus_kind := ""        # "", "grab", "use"

var _focus_point := Vector3.ZERO
var _local_point := Vector3.ZERO
var _hold_dist := 1.2
var _old_angular_damp := 0.0


func setup(main_node: Node) -> void:
	main = main_node
	player = main_node.player
	hud = main_node.hud


func toggle_grab() -> void:
	if held != null:
		release()
	elif focus_kind == "grab":
		_grab(focus as RigidBody3D, _focus_point)


func use() -> void:
	if held == null and focus_kind == "use":
		main.use_object(focus)


func adjust_distance(step: float) -> void:
	if held != null:
		_hold_dist = clampf(_hold_dist + step, HOLD_MIN, HOLD_MAX)


func throw_held() -> void:
	if held == null:
		return
	var body := held
	var point := body.to_global(_local_point)
	release()
	var dir := -player.camera.global_transform.basis.z
	var impulse := minf(body.mass * THROW_SPEED, THROW_IMPULSE_MAX)
	body.apply_impulse(dir * impulse, point - body.global_position)


func release() -> void:
	if held != null and is_instance_valid(held):
		held.angular_damp = _old_angular_damp
	held = null
	player.held_body = null


func _grab(body: RigidBody3D, point: Vector3) -> void:
	held = body
	player.held_body = body
	_local_point = body.to_local(point)
	_hold_dist = clampf(player.camera.global_position.distance_to(point), HOLD_MIN, HOLD_MAX)
	_old_angular_damp = body.angular_damp
	body.angular_damp = HELD_ANGULAR_DAMP
	body.sleeping = false


func _physics_process(_delta: float) -> void:
	if player == null:
		return
	_update_focus()
	if held != null:
		_drive_held()
	_update_cursor()


func _update_focus() -> void:
	focus = null
	focus_kind = ""
	var cam := player.camera
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_transform.basis.z * REACH)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var collider: Object = hit["collider"]
	if collider.has_meta("switch_id"):
		focus_kind = "use"
	elif collider is RigidBody3D and not collider.freeze:
		focus_kind = "grab"
	else:
		return
	focus = collider
	_focus_point = hit["position"]


func _drive_held() -> void:
	if not is_instance_valid(held):
		release()
		return
	if player.stands_on(held):
		release()  # nie da się podnieść czegoś, na czym się stoi
		return
	var cam := player.camera
	var target := cam.global_position - cam.global_transform.basis.z * _hold_dist
	var point := held.to_global(_local_point)
	var arm := point - held.global_position
	var error := target - point
	if cam.global_position.distance_to(point) > BREAK_DIST:
		release()
		return
	var point_velocity := held.linear_velocity + held.angular_velocity.cross(arm)
	var m := minf(held.mass, MASS_CAP)
	var force := error * STIFF * m - point_velocity * DAMP * m
	var horizontal := Vector3(force.x, 0.0, force.z).limit_length(PULL_MAX)
	var vertical := clampf(force.y, -LIFT_MAX, LIFT_MAX)
	held.sleeping = false
	held.apply_force(Vector3(horizontal.x, vertical, horizontal.z), arm)


func _update_cursor() -> void:
	if held != null:
		hud.set_cursor("fist")
	elif focus_kind == "grab":
		hud.set_cursor("hand")
	elif focus_kind == "use":
		hud.set_cursor("use")
	else:
		hud.set_cursor("dot")
