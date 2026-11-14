extends RefCounted
## Testy uruchamiane z wiersza poleceń, bez udziału gracza:
##   godot --headless --path game -- --test-zapisu
##   godot --path game -- --zrzuty=/sciezka/do/folderu
## Kod wyjścia 0 oznacza powodzenie.

const SaveGame := preload("res://scripts/save_game.gd")
const TEST_PATH := "user://test_zapisu.json"


static func run_save_test(main: Node) -> void:
	var tree := main.get_tree()
	var errors := PackedStringArray()

	# 1. Bryły mają czas opaść i się uspokoić.
	for i in 240:
		await tree.physics_frame
	var awake_after_settle: int = main.awake_body_count()
	if awake_after_settle > 0:
		var names := PackedStringArray()
		for b in main.bodies:
			if not b.sleeping:
				names.append("%s v=%.3f w=%.3f" % [b.name, b.linear_velocity.length(), b.angular_velocity.length()])
		errors.append("po 4 s nadal aktywnych brył: %d (%s)" % [awake_after_settle, ", ".join(names)])
	for b in main.bodies:
		if b.global_position.y < -1.0:
			errors.append("bryła %s wypadła poza świat" % b.name)

	# 1b. Gracz idzie przed siebie i pcha małą skrzynkę.
	var crate: RigidBody3D = null
	for b in main.bodies:
		if b.name == "skrzynka_mala_a":
			crate = b
	var crate_start: Vector3 = crate.global_position
	main.player.global_position = Vector3(crate_start.x, 0.02, crate_start.z + 1.0)
	main.player.set_view(0.0, 0.0)
	Input.action_press("move_forward")
	for i in 90:
		await tree.physics_frame
	Input.action_release("move_forward")
	var pushed: float = crate_start.z - crate.global_position.z
	if pushed < 0.2:
		errors.append("gracz nie przepchnął skrzynki (przesunięcie %.2f m)" % pushed)
	if main.player.global_position.y < -0.2 or main.player.global_position.y > 0.5:
		errors.append("gracz nie stoi na podłodze (y = %.2f)" % main.player.global_position.y)
	print("pchanie: skrzynka 6 kg przesunięta o %.2f m w 1,5 s" % pushed)
	for i in 180:
		await tree.physics_frame

	# 2. Zapis stanu.
	var before := {}
	for b in main.bodies:
		before[b.get_meta("save_id")] = b.global_transform
	var player_before: Vector3 = main.player.global_position
	main.set_style(2, false)
	main.player.lamp.visible = true
	if not SaveGame.save(main, TEST_PATH):
		errors.append("zapis się nie powiódł")

	# 3. Psujemy stan: przesuwamy wszystko, zmieniamy styl i język.
	for b in main.bodies:
		b.global_position += Vector3(0.7, 1.5, -0.4)
		b.linear_velocity = Vector3(1, 2, 3)
	main.player.global_position += Vector3(2, 0, -2)
	main.player.lamp.visible = false
	main.set_style(0, false)
	TranslationServer.set_locale("en")

	# 4. Odczyt i porównanie.
	var result: int = SaveGame.load_into(main, TEST_PATH)
	if result != SaveGame.Result.OK:
		errors.append("odczyt zwrócił kod %d" % result)
	await tree.physics_frame
	await tree.physics_frame
	for b in main.bodies:
		var want: Transform3D = before[b.get_meta("save_id")]
		if b.global_position.distance_to(want.origin) > 0.02:
			errors.append("%s: pozycja różni się o %.3f m" % [b.name, b.global_position.distance_to(want.origin)])
		if b.global_transform.basis.get_rotation_quaternion().angle_to(want.basis.get_rotation_quaternion()) > 0.02:
			errors.append("%s: obrót się różni" % b.name)
	if main.player.global_position.distance_to(player_before) > 0.05:
		errors.append("gracz: pozycja się różni")
	if main.style_index != 2:
		errors.append("styl nie wrócił (jest %d)" % main.style_index)
	if not main.player.lamp.visible:
		errors.append("latarka nie wróciła do stanu z zapisu")
	if not TranslationServer.get_locale().begins_with("pl"):
		errors.append("język nie wrócił (jest %s)" % TranslationServer.get_locale())

	# 5. Uszkodzony plik i zła wersja nie mogą wywrócić gry.
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

	# 6. Tłumaczenia: oba języki mają te same klucze i nic nie zostaje kluczem.
	for key in ["HINTS", "MSG_SAVED", "DEV_FPS", "STYLE_RAW"]:
		for code in ["pl", "en"]:
			TranslationServer.set_locale(code)
			if main.tr(key) == key:
				errors.append("brak tłumaczenia %s w języku %s" % [key, code])

	if errors.is_empty():
		print("TEST ZAPISU: OK (bryły: %d)" % main.bodies.size())
		tree.quit(0)
	else:
		for e in errors:
			printerr("TEST ZAPISU: BŁĄD: " + e)
		tree.quit(1)


static func take_screenshots(main: Node, args: PackedStringArray) -> void:
	var tree := main.get_tree()
	var dir := ""
	for a in args:
		if a.begins_with("--zrzuty="):
			dir = a.trim_prefix("--zrzuty=")
	main.dev_visible = true
	for i in 120:
		await tree.physics_frame
	for i in main.STYLES.size():
		main.set_style(i, false)
		for k in 12:
			await tree.process_frame
		await RenderingServer.frame_post_draw
		var img: Image = main.get_viewport().get_texture().get_image()
		img.save_png("%s/styl_%d.png" % [dir, i])
	# drugi kadr: latarka w ciemnej komórce
	main.set_style(1, false)
	main.player.global_position = Vector3(5.6, 0.02, 1.6)
	main.player.set_view(deg_to_rad(20.0), deg_to_rad(-12.0))
	main.player.lamp.visible = true
	for k in 12:
		await tree.process_frame
	await RenderingServer.frame_post_draw
	main.get_viewport().get_texture().get_image().save_png("%s/komorka_latarka.png" % dir)
	tree.quit(0)
