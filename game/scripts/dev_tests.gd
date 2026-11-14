extends RefCounted
## Testy uruchamiane z wiersza poleceń, bez udziału gracza:
##   godot --headless --path game -- --test
##   godot --path game -- --zrzuty=/sciezka/do/folderu
## Kod wyjścia 0 oznacza powodzenie.

const SaveGame := preload("res://scripts/save_game.gd")
const TEST_PATH := "user://test_zapisu.json"


static func _wait(tree: SceneTree, frames: int) -> void:
	for i in frames:
		await tree.physics_frame


static func _body(main: Node, id: String) -> RigidBody3D:
	for b in main.bodies:
		if b.name == id:
			return b
	return null


static func _place(main: Node, pos: Vector3, yaw_deg: float, pitch_deg: float = 0.0) -> void:
	main.player.teleport(pos)
	main.player.set_view(deg_to_rad(yaw_deg), deg_to_rad(pitch_deg))


static func run_tests(main: Node) -> void:
	var tree := main.get_tree()
	var errors := PackedStringArray()
	var player = main.player
	var inter = main.interaction

	# 1. Bryły opadają i się uspokajają; nic nie wypada poza świat.
	await _wait(tree, 240)
	if main.awake_body_count() > 0:
		var names := PackedStringArray()
		for b in main.bodies:
			if not b.sleeping:
				names.append("%s v=%.3f w=%.3f" % [b.name, b.linear_velocity.length(), b.angular_velocity.length()])
		errors.append("po 4 s nadal aktywne bryły: " + ", ".join(names))
	for b in main.bodies:
		if b.global_position.y < -1.0:
			errors.append("bryła %s wypadła poza świat" % b.name)

	# 2. Rozpędzanie ma bezwładność: po 0,25 s gracz nie ma jeszcze pełnej prędkości.
	_place(main, Vector3(-1.5, 0.02, 0.5), 90.0)  # twarzą w -X, pusta podłoga
	await _wait(tree, 5)
	Input.action_press("move_forward")
	await _wait(tree, 15)
	var early: float = Vector2(player.velocity.x, player.velocity.z).length()
	await _wait(tree, 45)
	var late: float = Vector2(player.velocity.x, player.velocity.z).length()
	Input.action_release("move_forward")
	if early > player.WALK_SPEED * 0.8:
		errors.append("ruch bez bezwładności (%.2f m/s po 0,25 s)" % early)
	if absf(late - player.WALK_SPEED) > 0.15:
		errors.append("prędkość chodu %.2f zamiast %.2f" % [late, player.WALK_SPEED])
	await _wait(tree, 40)

	# 3. Sprint zużywa wytrzymałość, odpoczynek ją przywraca.
	_place(main, Vector3(3.5, 0.02, -2.6), 90.0)
	await _wait(tree, 5)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _wait(tree, 60)
	Input.action_release("sprint")
	Input.action_release("move_forward")
	var after_sprint: float = player.stamina
	if after_sprint > player.STAMINA_MAX - 5.0:
		errors.append("sprint nie zużył wytrzymałości (%.1f)" % after_sprint)
	await _wait(tree, 150)
	if player.stamina <= after_sprint:
		errors.append("wytrzymałość nie wraca po odpoczynku")

	# 4. Kucanie obniża oczy i kapsułę, puszczenie klawisza je podnosi.
	_place(main, Vector3(0.0, 0.02, 2.0), 0.0)
	await _wait(tree, 5)
	Input.action_press("crouch")
	await _wait(tree, 40)
	var eye_low: float = player.camera.global_position.y - player.global_position.y
	Input.action_release("crouch")
	await _wait(tree, 40)
	var eye_high: float = player.camera.global_position.y - player.global_position.y
	if eye_low > 1.0 or eye_high < 1.6:
		errors.append("kucanie: oczy na %.2f m, po wstaniu %.2f m" % [eye_low, eye_high])

	# 5. Wychylanie przesuwa kamerę w bok.
	Input.action_press("lean_right")
	await _wait(tree, 30)
	var lean_x: float = player.camera.position.x
	Input.action_release("lean_right")
	await _wait(tree, 30)
	if lean_x < 0.25 or absf(player.camera.position.x) > 0.02:
		errors.append("wychylanie: %.2f m w bok, po powrocie %.2f m" % [lean_x, player.camera.position.x])

	# 6. Wspinanie na stół (blat na 0,79 m).
	_place(main, Vector3(-2.2, 0.02, -1.35), 0.0)
	await _wait(tree, 10)
	Input.action_press("jump")
	await _wait(tree, 2)
	Input.action_release("jump")
	await _wait(tree, 90)
	if player.global_position.y < 0.7:
		errors.append("gracz nie wszedł na stół (y = %.2f)" % player.global_position.y)

	# 7. Pchanie ciałem: mała skrzynka przesuwa się przed graczem.
	var small := _body(main, "skrzynka_mala_a")
	var start: Vector3 = small.global_position
	_place(main, Vector3(start.x, 0.02, start.z + 1.0), 0.0)
	await _wait(tree, 5)
	Input.action_press("move_forward")
	await _wait(tree, 90)
	Input.action_release("move_forward")
	var pushed: float = start.z - small.global_position.z
	if pushed < 0.2:
		errors.append("gracz nie przepchnął skrzynki (%.2f m)" % pushed)
	await _wait(tree, 120)

	# 8. Chwyt: celownik pokazuje dłoń, lekka skrzynka daje się unieść i nieść.
	_place(main, small.global_position + Vector3(0, -0.18, 1.1), 0.0, -55.0)
	await _wait(tree, 5)
	if inter.focus_kind != "grab" or main.hud.cursor_state() != "hand":
		errors.append("celownik nie pokazuje dłoni nad skrzynką (%s / %s)" % [inter.focus_kind, main.hud.cursor_state()])
	inter.toggle_grab()
	await _wait(tree, 3)
	if inter.held != small or main.hud.cursor_state() != "fist":
		errors.append("chwyt nie zadziałał")
	for i in 35:  # unosimy wzrok stopniowo, jak ruchem myszy
		player.set_view(0.0, deg_to_rad(lerpf(-55.0, 15.0, (i + 1) / 35.0)))
		await tree.physics_frame
	await _wait(tree, 60)
	var lifted: float = small.global_position.y
	if lifted < 0.9:
		errors.append("skrzynka 6 kg nie dała się unieść (y = %.2f)" % lifted)
	Input.action_press("move_back")
	await _wait(tree, 60)
	Input.action_release("move_back")
	var gap: float = small.global_position.distance_to(player.camera.global_position)
	if inter.held != small or gap > 2.2:
		errors.append("niesiona skrzynka nie podąża za graczem (odległość %.2f m)" % gap)
	inter.toggle_grab()
	await _wait(tree, 120)
	if inter.held != null or small.global_position.y > 0.4:
		errors.append("puszczona skrzynka nie spadła (y = %.2f)" % small.global_position.y)

	# 9. Ciężka skrzynia (70 kg): nie da się jej unieść, ale da się ją wlec.
	var heavy := _body(main, "skrzynia_komorka")
	var heavy_start: Vector3 = heavy.global_position
	_place(main, heavy_start + Vector3(0, -0.43, 1.3), 0.0, -40.0)
	await _wait(tree, 5)
	inter.toggle_grab()
	player.set_view(0.0, deg_to_rad(30.0))
	await _wait(tree, 60)
	if heavy.global_position.y > heavy_start.y + 0.08:
		errors.append("skrzynia 70 kg dała się unieść (y = %.2f)" % heavy.global_position.y)
	player.set_view(0.0, deg_to_rad(-20.0))
	Input.action_press("move_back")
	await _wait(tree, 120)
	Input.action_release("move_back")
	var dragged: float = heavy.global_position.z - heavy_start.z
	print("wleczenie: skrzynia 70 kg przesunięta o %.2f m w 2 s" % dragged)
	if dragged < 0.15:
		errors.append("skrzyni 70 kg nie da się wlec (%.2f m)" % dragged)
	if dragged > 2.0:
		errors.append("skrzynię 70 kg wlecze się za łatwo (%.2f m w 2 s)" % dragged)
	inter.release()
	await _wait(tree, 60)

	# 10. Drzwi na zawiasie: chwyt i ruch w tył otwierają je po łuku.
	var door := _body(main, "drzwi_komorka")
	var door_start: Transform3D = door.global_transform
	_place(main, Vector3(3.4, 0.02, 1.45), -90.0, -5.0)  # sala, twarzą do drzwi
	await _wait(tree, 5)
	if inter.focus != door:
		errors.append("gracz nie celuje w drzwi")
	inter.toggle_grab()
	Input.action_press("move_back")
	await _wait(tree, 70)
	Input.action_release("move_back")
	inter.release()
	var swing: float = door.global_transform.basis.get_rotation_quaternion().angle_to(door_start.basis.get_rotation_quaternion())
	var hinge_drift: float = absf(door.global_position.y - door_start.origin.y)
	print("drzwi: obrót o %.0f stopni" % rad_to_deg(swing))
	if swing < deg_to_rad(15.0):
		errors.append("drzwi nie otwierają się przy ciągnięciu (%.1f stopnia)" % rad_to_deg(swing))
	if hinge_drift > 0.03:
		errors.append("drzwi zeszły z zawiasu (%.3f m w pionie)" % hinge_drift)
	await _wait(tree, 60)

	# 11. Włącznik światła pod F.
	_place(main, Vector3(3.6, 0.02, 0.35), -90.0, -24.0)
	await _wait(tree, 5)
	if inter.focus_kind != "use" or main.hud.cursor_state() != "use":
		errors.append("celownik nie pokazuje użycia nad włącznikiem (%s)" % inter.focus_kind)
	var lamp_before: bool = main.switches["lampa_sala"]["light"].visible
	inter.use()
	if main.switches["lampa_sala"]["light"].visible == lamp_before:
		errors.append("włącznik nie przełączył lampy")

	# 11b. Po wszystkich próbach żadna bryła nie wyleciała poza pokój.
	for b in main.bodies:
		var bp: Vector3 = b.global_position
		if bp.y < -0.5 or bp.y > 3.2 or absf(bp.x - 1.5) > 7.0 or absf(bp.z) > 4.0:
			errors.append("bryła %s wyleciała poza pokój (%s)" % [b.name, bp])

	# 12. Zapis, zepsucie stanu, odczyt i porównanie.
	await _wait(tree, 180)
	var before := {}
	for b in main.bodies:
		before[b.get_meta("save_id")] = b.global_transform
	var player_before: Vector3 = player.global_position
	var lamp_saved: bool = main.switches["lampa_sala"]["on"]
	main.set_style(2, false)
	player.lamp.visible = true
	if not SaveGame.save(main, TEST_PATH):
		errors.append("zapis się nie powiódł")
	for b in main.bodies:
		if b.name != "drzwi_komorka":
			b.global_position += Vector3(0.7, 1.5, -0.4)
			b.linear_velocity = Vector3(1, 2, 3)
	player.teleport(player.global_position + Vector3(-2, 0, 1))
	player.lamp.visible = false
	main.set_switch("lampa_sala", not lamp_saved)
	main.set_style(0, false)
	TranslationServer.set_locale("en")
	var result: int = SaveGame.load_into(main, TEST_PATH)
	if result != SaveGame.Result.OK:
		errors.append("odczyt zwrócił kod %d" % result)
	await _wait(tree, 2)
	for b in main.bodies:
		var want: Transform3D = before[b.get_meta("save_id")]
		if b.global_position.distance_to(want.origin) > 0.03:
			errors.append("%s: pozycja po odczycie różni się o %.3f m" % [b.name, b.global_position.distance_to(want.origin)])
		if b.global_transform.basis.get_rotation_quaternion().angle_to(want.basis.get_rotation_quaternion()) > 0.03:
			errors.append("%s: obrót po odczycie się różni" % b.name)
	if player.global_position.distance_to(player_before) > 0.05:
		errors.append("gracz: pozycja po odczycie się różni")
	if main.style_index != 2:
		errors.append("styl nie wrócił (jest %d)" % main.style_index)
	if not player.lamp.visible:
		errors.append("latarka nie wróciła do stanu z zapisu")
	if main.switches["lampa_sala"]["on"] != lamp_saved or main.switches["lampa_sala"]["light"].visible != lamp_saved:
		errors.append("lampa nie wróciła do stanu z zapisu")
	if not TranslationServer.get_locale().begins_with("pl"):
		errors.append("język nie wrócił (jest %s)" % TranslationServer.get_locale())

	# 13. Uszkodzony plik, inna wersja i brak pliku nie mogą wywrócić gry.
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string("{ to nie jest poprawny zapis")
	f.close()
	if SaveGame.load_into(main, TEST_PATH) != SaveGame.Result.BAD_FILE:
		errors.append("uszkodzony plik nie został odrzucony")
	f = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string('{"version": 999, "player": {}, "bodies": {}}')
	f.close()
	if SaveGame.load_into(main, TEST_PATH) != SaveGame.Result.BAD_FILE:
		errors.append("zapis z inną wersją nie został odrzucony")
	if SaveGame.load_into(main, "user://nie_ma_takiego.json") != SaveGame.Result.NO_FILE:
		errors.append("brak pliku nie został rozpoznany")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))

	# 14. Tłumaczenia: oba języki mają komplet tekstów.
	for key in ["HINTS", "MSG_SAVED", "DEV_FPS", "STYLE_RAW", "DEV_STAMINA", "DEV_HELD"]:
		for code in ["pl", "en"]:
			TranslationServer.set_locale(code)
			if main.tr(key) == key:
				errors.append("brak tłumaczenia %s w języku %s" % [key, code])

	if errors.is_empty():
		print("TESTY: OK (bryły: %d)" % main.bodies.size())
		tree.quit(0)
	else:
		for e in errors:
			printerr("TESTY: BŁĄD: " + e)
		tree.quit(1)


static func take_screenshots(main: Node, args: PackedStringArray) -> void:
	var tree := main.get_tree()
	var dir := ""
	for a in args:
		if a.begins_with("--zrzuty="):
			dir = a.trim_prefix("--zrzuty=")
	await _wait(tree, 120)
	# kadr 1: dłoń nad skrzynką
	var small := _body(main, "skrzynka_mala_a")
	_place(main, small.global_position + Vector3(0.5, -0.18, 1.3), 18.0, -48.0)
	await _shot(main, dir + "/chwyt_dlon.png")
	# kadr 2: skrzynka niesiona w powietrzu
	main.interaction.toggle_grab()
	main.player.set_view(deg_to_rad(18.0), deg_to_rad(-5.0))
	await _wait(tree, 60)
	await _shot(main, dir + "/chwyt_niesienie.png")
	main.interaction.release()
	# kadr 3: drzwi do komórki i włącznik
	_place(main, Vector3(2.6, 0.02, 0.9), -90.0, -6.0)
	await _wait(tree, 30)
	await _shot(main, dir + "/drzwi_wlacznik.png")
	tree.quit(0)


static func _shot(main: Node, path: String) -> void:
	var tree := main.get_tree()
	for k in 10:
		await tree.process_frame
	await RenderingServer.frame_post_draw
	main.get_viewport().get_texture().get_image().save_png(path)
