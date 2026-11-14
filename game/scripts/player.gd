extends CharacterBody3D
## Gracz, wersja z builda 1: chód, sprint, skok, latarka, pchanie brył.
## Pełny ruch (bezwładność, kucanie, wychylanie, ciało, dłonie) wchodzi w buildzie 2.

const WALK_SPEED := 2.6
const SPRINT_SPEED := 4.8
const ACCEL := 9.0
const FRICTION := 11.0
const JUMP_SPEED := 3.6
const MOUSE_SENS := 0.0022
const PUSH_FORCE := 260.0      # niutony, z jaką siłą postać pcha bryłę
const PUSH_MAX_SPEED := 2.2    # bryły nie rozpędzamy ponad tę prędkość
const EYE_HEIGHT := 1.65

var camera: Camera3D
var lamp: SpotLight3D
var pitch := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _init() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.8
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.9
	add_child(col)

	camera = Camera3D.new()
	camera.position.y = EYE_HEIGHT
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = 80.0
	camera.current = true
	add_child(camera)

	lamp = SpotLight3D.new()
	lamp.spot_range = 14.0
	lamp.spot_angle = 26.0
	lamp.light_energy = 3.0
	lamp.light_color = Color(1.0, 0.95, 0.82)
	lamp.shadow_enabled = true
	lamp.visible = false
	camera.add_child(lamp)


func look(relative: Vector2) -> void:
	rotate_y(-relative.x * MOUSE_SENS)
	pitch = clampf(pitch - relative.y * MOUSE_SENS, -1.45, 1.45)
	camera.rotation.x = pitch


func set_view(yaw: float, new_pitch: float) -> void:
	rotation.y = yaw
	pitch = new_pitch
	camera.rotation.x = pitch


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("flashlight"):
		lamp.visible = not lamp.visible


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (global_transform.basis * Vector3(input.x, 0.0, input.y))
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	var target := dir * speed
	var rate := ACCEL if dir != Vector3.ZERO else FRICTION
	if not is_on_floor():
		rate *= 0.25
	velocity.x = move_toward(velocity.x, target.x, rate * delta)
	velocity.z = move_toward(velocity.z, target.z, rate * delta)

	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_SPEED
	else:
		velocity.y -= _gravity * delta

	move_and_slide()
	_push_bodies(delta)


func _push_bodies(delta: float) -> void:
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var body := hit.get_collider() as RigidBody3D
		if body == null:
			continue
		var push_dir := -hit.get_normal()
		push_dir.y = 0.0
		if push_dir.length() < 0.2:
			continue  # stoimy na bryle albo pod nią
		push_dir = push_dir.normalized()
		if body.linear_velocity.dot(push_dir) > PUSH_MAX_SPEED:
			continue
		body.apply_impulse(push_dir * PUSH_FORCE * delta, hit.get_position() - body.global_position)
