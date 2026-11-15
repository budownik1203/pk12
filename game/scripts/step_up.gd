extends RefCounted
## Wchodzenie na niskie przeszkody (krawężnik, deska na podłodze, próg) dla
## CharacterBody3D: zamiast utknąć albo wjechać na krawędź zaokrąglonym dołem
## kapsuły i podskoczyć, postać unosi się na wysokość stopnia i idzie dalej.
## Wywołać przed move_and_slide(), gdy postać stoi na ziemi.

## Zwraca, o ile podniesiono postać (0, gdy nie było stopnia).
static func try_step(body: CharacterBody3D, delta: float, max_height: float) -> float:
	var hv := Vector3(body.velocity.x, 0.0, body.velocity.z) * delta
	if hv.length() < 0.001:
		return 0.0
	# kawałek dalej niż ruch w jednej klatce, żeby stopień złapać przed zderzeniem
	var probe := hv.normalized() * maxf(hv.length(), 0.06)
	var from := body.global_transform
	if not body.test_move(from, probe):
		return 0.0  # nic nie stoi na drodze
	var up := Vector3.UP * max_height
	if body.test_move(from, up):
		return 0.0  # nad głową sufit albo belka
	var raised := from.translated(up)
	if body.test_move(raised, probe):
		return 0.0  # wyżej też przeszkoda: to ściana albo duża skrzynia, nie stopień
	var col := KinematicCollision3D.new()
	var ahead := raised.translated(probe)
	if not body.test_move(ahead, -up * 1.2, col):
		return 0.0  # za przeszkodą dziura
	if col.get_normal().y < 0.7:
		return 0.0  # ląduje na skosie albo krawędzi
	var rise := max_height + col.get_travel().y
	if rise < 0.01 or rise > max_height:
		return 0.0
	body.global_position.y += rise + 0.005
	return rise
