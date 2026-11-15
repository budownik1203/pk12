extends Node3D
## Ognisko: kilka polan, migoczące płomienie i światło, trzask. Opał w minutach
## gry; F z drewnem w ręce dokłada. Ulewa gasi ogień szybciej.

var main
var fuel := 30.0
var _light: OmniLight3D
var _flames: Array = []
var _crackle: AudioStreamPlayer3D
var _t := 0.0


func setup(main_node, fuel_minutes: float) -> void:
	main = main_node
	fuel = fuel_minutes
	name = "Ognisko"
	var body := StaticBody3D.new()
	body.set_meta("fire", self)
	var shape := CylinderShape3D.new()
	shape.radius = 0.35
	shape.height = 0.25
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, 0.12, 0)
	body.add_child(col)
	add_child(body)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.2, 0.13, 0.08)
	for k in 4:
		var log_mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.55, 0.07, 0.07)
		bm.material = wood
		log_mi.mesh = bm
		log_mi.rotation = Vector3(0, k * PI / 4.0, 0.25)
		log_mi.position = Vector3(0, 0.06, 0)
		add_child(log_mi)
	var ember := StandardMaterial3D.new()
	ember.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember.albedo_color = Color(1.0, 0.55, 0.15)
	for k in 5:
		var fl := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.09
		cm.height = 0.35
		cm.radial_segments = 5
		cm.material = ember
		fl.mesh = cm
		fl.position = Vector3(cos(k * 1.3) * 0.08, 0.2, sin(k * 1.3) * 0.08)
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fl)
		_flames.append(fl)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.62, 0.3)
	_light.light_energy = 2.2
	_light.omni_range = 7.0
	_light.shadow_enabled = true
	_light.position = Vector3(0, 0.5, 0)
	add_child(_light)
	_crackle = AudioStreamPlayer3D.new()
	_crackle.stream = main.sound.crackle_loop()
	_crackle.unit_size = 2.0
	_crackle.volume_db = -6.0
	add_child(_crackle)
	_crackle.play()


func burning() -> bool:
	return fuel > 0.0


func add_fuel(minutes: float) -> void:
	fuel += minutes


func _process(delta: float) -> void:
	if main == null:
		return
	_t += delta
	var burn: float = main.clock.game_hours(delta) * 60.0
	if main.weather.rain > 0.5 and not main.town.indoors(global_position):
		burn *= 1.0 + main.weather.rain * 3.0  # deszcz gasi
	fuel -= burn
	var strength := clampf(fuel / 20.0, 0.25, 1.0)
	for k in _flames.size():
		var fl: MeshInstance3D = _flames[k]
		fl.scale = Vector3.ONE * strength * (0.75 + 0.35 * sin(_t * (7.0 + k) + k))
	_light.light_energy = strength * (1.9 + 0.5 * sin(_t * 9.0) + 0.3 * sin(_t * 23.0))
	if fuel <= 0.0:
		main.noise.emit_noise(global_position, 10.0, "NOISE_FIRE_OUT")
		if global_position.distance_to(main.player.global_position) < 10.0:
			main.hud.show_message(tr("MSG_FIRE_OUT"))
		queue_free()
